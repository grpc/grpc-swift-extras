/*
 * Copyright 2025, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import GRPCCore
import GRPCInProcessTransport
import GRPCOTelTracingInterceptors
import InMemoryTracing
import SwiftProtobuf
import Testing
import Tracing

struct OTelTracingIntegrationTests {
  enum TracingLevel: CaseIterable {
    case minimal
    case all
  }

  @available(gRPCSwiftExtras 2.0, *)
  func withEchoService(
    clientTracing: TracingLevel = .minimal,
    serverTracing: TracingLevel = .minimal,
    clientThrows: ThrowingInterceptor.When? = nil,
    serverThrows: ThrowingInterceptor.When? = nil,
    body: (_ echo: Echo_Echo.Client<InProcessTransport.Client>) async throws -> Void
  ) async throws -> InMemoryTracer {
    let echo = EchoService()
    let transport = InProcessTransport()
    let tracer = InMemoryTracer()

    // Server interceptors
    var serverInterceptors: [any ServerInterceptor] = []
    let serverTracer = ServerOTelTracingInterceptor(
      serverHostname: "localhost",
      networkTransportMethod: "inproc",
      traceEachMessage: serverTracing == .all,
      includeRequestMetadata: serverTracing == .all,
      includeResponseMetadata: serverTracing == .all,
      tracerOverride: tracer
    )
    serverInterceptors.append(serverTracer)
    if let serverThrows {
      serverInterceptors.append(ThrowingInterceptor(when: serverThrows))
    }

    // Client interceptors
    var clientInterceptors: [any ClientInterceptor] = []
    let clientTracer = ClientOTelTracingInterceptor(
      serverHostname: "localhost",
      networkTransportMethod: "inproc",
      traceEachMessage: clientTracing == .all,
      includeRequestMetadata: clientTracing == .all,
      includeResponseMetadata: clientTracing == .all,
      tracerOverride: tracer
    )
    clientInterceptors.append(clientTracer)
    if let clientThrows {
      clientInterceptors.append(ThrowingInterceptor(when: clientThrows))
    }

    try await withGRPCServer(
      transport: transport.server,
      services: [echo],
      interceptors: serverInterceptors
    ) { server in
      try await withGRPCClient(
        transport: transport.client,
        interceptors: clientInterceptors
      ) { client in
        try await body(Echo_Echo.Client(wrapping: client))
      }
    }

    return tracer
  }

  @available(gRPCSwiftExtras 2.0, *)
  @Test(arguments: TracingLevel.allCases)
  func unary(level: TracingLevel) async throws {
    let tracer = try await withEchoService(clientTracing: level, serverTracing: level) { echo in
      let reply = try await echo.get(.with { $0.text = "Hello!" })
      #expect(reply.text == "Hello!")
    }

    #expect(tracer.activeSpans.isEmpty)
    let spans = try #require(tracer.rpcSpans())
    for span in spans {
      #expect(span.operationName == "echo.Echo/Get")
      #expect(span.errors.isEmpty)
      #expect(span.status?.code == .ok)
    }

    guard level == .all else { return }

    let clientMessageTypes = spans.client.events.map { $0.attributes.get("rpc.message.type") }
    #expect(clientMessageTypes == ["SENT", "RECEIVED"])

    let clientMessageIDs = spans.client.events.map { $0.attributes.get("rpc.message.id") }
    #expect(clientMessageIDs == [1, 1])

    let serverMessageTypes = spans.server.events.map { $0.attributes.get("rpc.message.type") }
    #expect(serverMessageTypes == ["RECEIVED", "SENT"])

    let serverMessageIDs = spans.server.events.map { $0.attributes.get("rpc.message.id") }
    #expect(serverMessageIDs == [1, 1])

  }

  @available(gRPCSwiftExtras 2.0, *)
  @Test(arguments: TracingLevel.allCases)
  func serverStreaming(level: TracingLevel) async throws {
    let tracer = try await withEchoService(clientTracing: level, serverTracing: level) { echo in
      try await echo.expand(.with { $0.text = "Foo Bar Baz" }) { response in
        let messages = try await response.messages.reduce(into: []) { $0.append($1.text) }
        #expect(messages == ["Foo", "Bar", "Baz"])
      }
    }

    #expect(tracer.activeSpans.isEmpty)
    let spans = try #require(tracer.rpcSpans())
    for span in spans {
      #expect(span.operationName == "echo.Echo/Expand")
      #expect(span.errors.isEmpty)
      #expect(span.status?.code == .ok)

    }

    guard level == .all else { return }

    let clientMessageTypes = spans.client.events.map { $0.attributes.get("rpc.message.type") }
    #expect(clientMessageTypes == ["SENT", "RECEIVED", "RECEIVED", "RECEIVED"])

    let clientMessageIDs = spans.client.events.map { $0.attributes.get("rpc.message.id") }
    #expect(clientMessageIDs == [1, 1, 2, 3])

    let serverMessageTypes = spans.server.events.map { $0.attributes.get("rpc.message.type") }
    #expect(serverMessageTypes == ["RECEIVED", "SENT", "SENT", "SENT"])

    let serverMessageIDs = spans.server.events.map { $0.attributes.get("rpc.message.id") }
    #expect(serverMessageIDs == [1, 1, 2, 3])
  }

  @available(gRPCSwiftExtras 2.0, *)
  @Test(arguments: TracingLevel.allCases)
  func clientStreaming(level: TracingLevel) async throws {
    let tracer = try await withEchoService(clientTracing: level, serverTracing: level) { echo in
      let reply = try await echo.collect { writer in
        try await writer.write(.with { $0.text = "Foo" })
        try await writer.write(.with { $0.text = "Bar" })
        try await writer.write(.with { $0.text = "Baz" })
      }

      #expect(reply.text == "Foo Bar Baz")
    }

    #expect(tracer.activeSpans.isEmpty)
    let spans = try #require(tracer.rpcSpans())
    for span in spans {
      #expect(span.operationName == "echo.Echo/Collect")
      #expect(span.errors.isEmpty)
      #expect(span.status?.code == .ok)
    }

    guard level == .all else { return }

    let clientMessageTypes = spans.client.events.map { $0.attributes.get("rpc.message.type") }
    #expect(clientMessageTypes == ["SENT", "SENT", "SENT", "RECEIVED"])

    let clientMessageIDs = spans.client.events.map { $0.attributes.get("rpc.message.id") }
    #expect(clientMessageIDs == [1, 2, 3, 1])

    let serverMessageTypes = spans.server.events.map { $0.attributes.get("rpc.message.type") }
    #expect(serverMessageTypes == ["RECEIVED", "RECEIVED", "RECEIVED", "SENT"])

    let serverMessageIDs = spans.server.events.map { $0.attributes.get("rpc.message.id") }
    #expect(serverMessageIDs == [1, 2, 3, 1])
  }

  @available(gRPCSwiftExtras 2.0, *)
  @Test(arguments: TracingLevel.allCases)
  func bidirectionalStreaming(level: TracingLevel) async throws {
    let tracer = try await withEchoService(clientTracing: level, serverTracing: level) { echo in
      try await echo.update { writer in
        try await writer.write(.with { $0.text = "Foo" })
        try await writer.write(.with { $0.text = "Bar" })
        try await writer.write(.with { $0.text = "Baz" })
      } onResponse: { response in
        let messages = try await response.messages.reduce(into: []) { $0.append($1.text) }
        #expect(messages == ["Foo", "Bar", "Baz"])
      }
    }

    #expect(tracer.activeSpans.isEmpty)
    let spans = try #require(tracer.rpcSpans())
    for span in spans {
      #expect(span.operationName == "echo.Echo/Update")
      #expect(span.errors.isEmpty)
      #expect(span.status?.code == .ok)
    }

    guard level == .all else { return }

    // We can't infer ordering of events for this RPC, they could be interleaved. We only know
    // that there should be three SENT and three RECEIVED in each span.
    for span in spans {
      #expect(span.events.count == 6)

      let sent = span.events.filter { $0.attributes.get("rpc.message.type") == "SENT" }
      #expect(sent.count == 3)
      for (index, event) in sent.enumerated() {
        #expect(event.attributes.get("rpc.message.id") == .int64(Int64(index + 1)))
      }

      let received = span.events.filter { $0.attributes.get("rpc.message.type") == "RECEIVED" }
      #expect(received.count == 3)
      for (index, event) in received.enumerated() {
        #expect(event.attributes.get("rpc.message.id") == .int64(Int64(index + 1)))
      }
    }
  }

  @available(gRPCSwiftExtras 2.0, *)
  @Test(
    arguments: [
      (.immediately(RPCError(code: .aborted, message: "")), .aborted),
      (.immediately(ConvertibleError(.aborted)), .aborted),
      (.immediately(NonConvertibleError()), .unknown),

      (.inRequestBody(RPCError(code: .aborted, message: "")), .aborted),
      (.inRequestBody(ConvertibleError(.aborted)), .aborted),
      (.inRequestBody(NonConvertibleError()), .unknown),

      (.inResponseBody(RPCError(code: .aborted, message: "")), .aborted),
      (.inResponseBody(ConvertibleError(.aborted)), .aborted),
      (.inResponseBody(NonConvertibleError()), .unknown),

      // API requires an RPCError so can't use convertible/non-convertible
      (.inResponseHead(RPCError(code: .aborted, message: "")), .aborted),
    ] as [(ThrowingInterceptor.When, RPCError.Code)]
  )
  func serverInterceptorThrows(
    when: ThrowingInterceptor.When,
    statusCode: RPCError.Code
  ) async throws {
    let tracer = try await withEchoService(serverThrows: when) { echo in
      await #expect(throws: RPCError.self) {
        try await echo.get(.with { $0.text = "uhoh" })
      }
    }

    #expect(tracer.activeSpans.isEmpty)

    let span = try #require(tracer.rpcSpan(for: .server))
    #expect(span.errors.count == 1)
    #expect(span.status?.code == .error)
    #expect(span.attributes.get("rpc.grpc.status_code") == .int64(Int64(statusCode.rawValue)))
  }

  @available(gRPCSwiftExtras 2.0, *)
  @Test(
    .disabled("known issues with tracing interceptors"),
    arguments: [
      (.immediately(RPCError(code: .aborted, message: "")), .aborted),
      (.immediately(ConvertibleError(.aborted)), .aborted),
      (.immediately(NonConvertibleError()), .unknown),

      (.inRequestBody(RPCError(code: .aborted, message: "")), .aborted),
      (.inRequestBody(ConvertibleError(.aborted)), .aborted),
      (.inRequestBody(NonConvertibleError()), .unknown),

      (.inResponseBody(RPCError(code: .aborted, message: "")), .aborted),
      (.inResponseBody(ConvertibleError(.aborted)), .aborted),
      (.inResponseBody(NonConvertibleError()), .unknown),

      // API requires an RPCError so can't use convertible/non-convertible
      (.inResponseHead(RPCError(code: .aborted, message: "")), .aborted),
    ] as [(ThrowingInterceptor.When, RPCError.Code)]
  )
  func clientInterceptorThrows(
    when: ThrowingInterceptor.When,
    statusCode: RPCError.Code
  ) async throws {
    let tracer = try await withEchoService(clientThrows: when) { echo in
      await #expect(throws: RPCError.self) {
        try await echo.get(.with { $0.text = "uhoh" })
      }
    }

    #expect(tracer.activeSpans.isEmpty)

    let span = try #require(tracer.rpcSpan(for: .client))
    #expect(span.errors.count == 1)
    #expect(span.status?.code == .error)
    #expect(span.attributes.get("rpc.grpc.status_code") == .int64(Int64(statusCode.rawValue)))
  }
}

extension InMemoryTracer {
  func rpcSpan(for kind: SpanKind) -> FinishedInMemorySpan? {
    self.finishedSpans.first { $0.kind == kind }
  }

  func rpcSpans() -> RPCSpans? {
    if let server = self.rpcSpan(for: .server), let client = self.rpcSpan(for: .client) {
      return RPCSpans(client: client, server: server)
    } else {
      return nil
    }
  }

  struct RPCSpans: Sequence {
    var client: FinishedInMemorySpan
    var server: FinishedInMemorySpan

    func makeIterator() -> IndexingIterator<[FinishedInMemorySpan]> {
      return [self.client, self.server].makeIterator()
    }
  }
}

@available(gRPCSwiftExtras 2.0, *)
struct ThrowingInterceptor: ServerInterceptor, ClientInterceptor {
  let when: When

  enum When: CustomStringConvertible {
    case immediately(any Error)
    case inRequestBody(any Error)
    case inResponseHead(RPCError)
    case inResponseBody(any Error)

    var description: String {
      switch self {
      case .immediately(let error):
        "immediately(\(error))"
      case .inRequestBody(let error):
        "inRequestBody(\(error))"
      case .inResponseHead(let error):
        "inResponseHead(\(error))"
      case .inResponseBody(let error):
        "inResponseBody(\(error))"
      }
    }
  }

  init(when: When) {
    self.when = when
  }

  func intercept<Input, Output>(
    request: StreamingServerRequest<Input>,
    context: ServerContext,
    next: (StreamingServerRequest<Input>, ServerContext) async throws -> StreamingServerResponse<
      Output
    >
  ) async throws -> StreamingServerResponse<Output> where Input: Sendable, Output: Sendable {
    switch self.when {
    case .immediately(let error):
      throw error

    case .inRequestBody(let error):
      var request = request
      request.messages = RPCAsyncSequence(
        wrapping: AsyncThrowingStream { continuation in
          continuation.finish(throwing: error)
        }
      )
      return try await next(request, context)

    case .inResponseHead(let error):
      return StreamingServerResponse(error: error)

    case .inResponseBody(let error):
      return StreamingServerResponse { _ in
        throw error
      }
    }
  }

  func intercept<Input, Output>(
    request: StreamingClientRequest<Input>,
    context: ClientContext,
    next: (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<
      Output
    >
  ) async throws -> StreamingClientResponse<Output> where Input: Sendable, Output: Sendable {
    switch self.when {
    case .immediately(let error):
      throw error

    case .inRequestBody(let error):
      var request = request
      request.producer = { _ in
        throw error
      }
      return try await next(request, context)

    case .inResponseBody(let error):
      return StreamingClientResponse(
        metadata: [:],
        bodyParts: RPCAsyncSequence(
          wrapping: AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
          }
        )
      )

    case .inResponseHead(let error):
      return StreamingClientResponse(error: error)
    }
  }
}

@available(gRPCSwiftExtras 2.0, *)
private struct ConvertibleError: RPCErrorConvertible, Error {
  fileprivate var rpcErrorCode: RPCError.Code
  fileprivate var rpcErrorMessage: String { "" }

  fileprivate init(_ code: RPCError.Code) {
    self.rpcErrorCode = code
  }
}

private struct NonConvertibleError: Error {}
