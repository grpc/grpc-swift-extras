/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
import Tracing
import XCTest

@testable import GRPCInterceptors

final class TracingInterceptorTests: XCTestCase {
  override class func setUp() {
    InstrumentationSystem.bootstrap(TestTracer())
  }

  // - MARK: Client Interceptor Tests

  func testClientInterceptor_IPv4() async throws {
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let interceptor = ClientOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp"
    )
    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "TracingInterceptorTests",
        method: "testClientInterceptor"
      )
      let response = try await interceptor.intercept(
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request1"])
          try await writer.write(contentsOf: ["request2"])
        }),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: "ipv4:10.1.2.80:567",
          localPeer: "ipv4:10.1.2.80:123"
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(
          metadata: [],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.yield(.message(["response"]))
              $0.finish()
            }
          )
        )
      }

      await AssertStreamContentsEqual(["request1", "request2"], requestStream)
      try await AssertStreamContentsEqual([["response"]], response.messages)

      AssertTestSpanComponents(forMethod: methodDescriptor) { events in
        XCTAssertEqual(
          events.map({ $0.name }),
          [
            "Request started",
            "Request ended",
            "Received response start",
            "Received response end",
          ]
        )
      } assertAttributes: { attributes in
        XCTAssertEqual(
          attributes,
          [
            "rpc.system": .string("grpc"),
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "rpc.grpc.status_code": .int(0),
            "server.address": .string("someserver.com"),
            "server.port": .int(567),
            "network.peer.address": .string("10.1.2.80"),
            "network.peer.port": .int(567),
            "network.transport": .string("tcp"),
            "network.type": .string("ipv4"),
          ]
        )
      } assertStatus: { status in
        XCTAssertNil(status)
      } assertErrors: { errors in
        XCTAssertEqual(errors, [])
      }
    }
  }

  func testClientInterceptor_IPv6() async throws {
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let interceptor = ClientOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp"
    )
    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "TracingInterceptorTests",
        method: "testClientInterceptor"
      )
      let response = try await interceptor.intercept(
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request1"])
          try await writer.write(contentsOf: ["request2"])
        }),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: "ipv6:2001::130F:::09C0:876A:130B:1234",
          localPeer: "ipv6:ff06:0:0:0:0:0:0:c3:5678"
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(
          metadata: [],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.yield(.message(["response"]))
              $0.finish()
            }
          )
        )
      }

      await AssertStreamContentsEqual(["request1", "request2"], requestStream)
      try await AssertStreamContentsEqual([["response"]], response.messages)

      AssertTestSpanComponents(forMethod: methodDescriptor) { events in
        XCTAssertEqual(
          events.map({ $0.name }),
          [
            "Request started",
            "Request ended",
            "Received response start",
            "Received response end",
          ]
        )
      } assertAttributes: { attributes in
        XCTAssertEqual(
          attributes,
          [
            "rpc.system": .string("grpc"),
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "rpc.grpc.status_code": .int(0),
            "server.address": .string("someserver.com"),
            "server.port": .int(1234),
            "network.peer.address": .string("2001::130F:::09C0:876A:130B"),
            "network.peer.port": .int(1234),
            "network.transport": .string("tcp"),
            "network.type": .string("ipv6"),
          ]
        )
      } assertStatus: { status in
        XCTAssertNil(status)
      } assertErrors: { errors in
        XCTAssertEqual(errors, [])
      }
    }
  }

  func testClientInterceptor_UDS() async throws {
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let interceptor = ClientOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp"
    )
    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "TracingInterceptorTests",
        method: "testClientInterceptor"
      )
      let response = try await interceptor.intercept(
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request1"])
          try await writer.write(contentsOf: ["request2"])
        }),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: "unix:some-path",
          localPeer: "unix:some-path"
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(
          metadata: [],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.yield(.message(["response"]))
              $0.finish()
            }
          )
        )
      }

      await AssertStreamContentsEqual(["request1", "request2"], requestStream)
      try await AssertStreamContentsEqual([["response"]], response.messages)

      AssertTestSpanComponents(forMethod: methodDescriptor) { events in
        XCTAssertEqual(
          events.map({ $0.name }),
          [
            "Request started",
            "Request ended",
            "Received response start",
            "Received response end",
          ]
        )
      } assertAttributes: { attributes in
        XCTAssertEqual(
          attributes,
          [
            "rpc.system": .string("grpc"),
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "rpc.grpc.status_code": .int(0),
            "server.address": .string("someserver.com"),
            "network.peer.address": .string("some-path"),
            "network.transport": .string("tcp"),
            "network.type": .string("unix"),
          ]
        )
      } assertStatus: { status in
        XCTAssertNil(status)
      } assertErrors: { errors in
        XCTAssertEqual(errors, [])
      }
    }
  }

  func testClientInterceptorAllEventsRecorded() async throws {
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "TracingInterceptorTests",
      method: "testClientInterceptorAllEventsRecorded"
    )
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let interceptor = ClientOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      emitEventOnEachWrite: true
    )
    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let response = try await interceptor.intercept(
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request1"])
          try await writer.write(contentsOf: ["request2"])
        }),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: "ipv4:10.1.2.80:567",
          localPeer: "ipv4:10.1.2.80:123"
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(
          metadata: [],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.yield(.message(["response"]))
              $0.finish()
            }
          )
        )
      }

      await AssertStreamContentsEqual(["request1", "request2"], requestStream)
      try await AssertStreamContentsEqual([["response"]], response.messages)

      AssertTestSpanComponents(forMethod: methodDescriptor) { events in
        XCTAssertEqual(
          events,
          [
            TestSpanEvent("Request started", [:]),
            // Recorded when `request1` is sent
            TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 1]),
            // Recorded when `request2` is sent
            TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 2]),
            // Recorded after all request parts have been sent
            TestSpanEvent("Request ended", [:]),
            // Recorded when receiving response part
            TestSpanEvent("Received response start", [:]),
            TestSpanEvent("rpc.message", ["rpc.message.type": "RECEIVED", "rpc.message.id": 1]),
            // Recorded at end of response
            TestSpanEvent("Received response end", [:]),
          ]
        )
      } assertAttributes: { attributes in
        XCTAssertEqual(
          attributes,
          [
            "rpc.system": .string("grpc"),
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "rpc.grpc.status_code": .int(0),
            "server.address": .string("someserver.com"),
            "server.port": .int(567),
            "network.peer.address": .string("10.1.2.80"),
            "network.peer.port": .int(567),
            "network.transport": .string("tcp"),
            "network.type": .string("ipv4"),
          ]
        )
      } assertStatus: { status in
        XCTAssertNil(status)
      } assertErrors: { errors in
        XCTAssertEqual(errors, [])
      }
    }
  }

  func testClientInterceptorErrorEncountered() async throws {
    var serviceContext = ServiceContext.topLevel
    let interceptor = ClientOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp"
    )
    let traceIDString = UUID().uuidString
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    await ServiceContext.$current.withValue(serviceContext) {
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "TracingInterceptorTests",
        method: "testClientInterceptorErrorEncountered"
      )
      do {
        let _: StreamingClientResponse<Void> = try await interceptor.intercept(
          request: StreamingClientRequest(of: Void.self, producer: { writer in }),
          context: ClientContext(
            descriptor: methodDescriptor,
            remotePeer: "ipv4:10.1.2.80:567",
            localPeer: "ipv4:10.1.2.80:123"
          )
        ) { stream, _ in
          // Assert the metadata contains the injected context key-value.
          XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

          throw TracingInterceptorTestError.testError
        }
        XCTFail("Should have thrown")
      } catch {
        AssertTestSpanComponents(forMethod: methodDescriptor) { events in
          // We errored when writing our request, so this is the only event we should be seeing
          XCTAssertEqual(events.map({ $0.name }), ["Request started"])
        } assertAttributes: { attributes in
          // The attributes should not contain a grpc status code, as the request was never even sent.
          XCTAssertEqual(
            attributes,
            [
              "rpc.system": .string("grpc"),
              "rpc.method": .string(methodDescriptor.method),
              "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
              "server.address": .string("someserver.com"),
              "server.port": .int(567),
              "network.peer.address": .string("10.1.2.80"),
              "network.peer.port": .int(567),
              "network.transport": .string("tcp"),
              "network.type": .string("ipv4"),
            ]
          )
        } assertStatus: { status in
          XCTAssertNil(status)
        } assertErrors: { errors in
          XCTAssertEqual(errors, [.testError])
        }
      }
    }
  }

  func testClientInterceptorErrorReponse() async throws {
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let interceptor = ClientOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp"
    )
    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "TracingInterceptorTests",
        method: "testClientInterceptor"
      )
      let response: StreamingClientResponse<Void> = try await interceptor.intercept(
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request"])
        }),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: "ipv4:10.1.2.80:567",
          localPeer: "ipv4:10.1.2.80:123"
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(error: RPCError(code: .unavailable, message: "This should not work"))
      }

      await AssertStreamContentsEqual(["request"], requestStream)

      switch response.accepted {
      case .success:
        XCTFail("Response should have failed")

      case .failure(let failure):
        XCTAssertEqual(failure, RPCError(code: .unavailable, message: "This should not work"))
      }

      AssertTestSpanComponents(forMethod: methodDescriptor) { events in
        XCTAssertEqual(
          events.map({ $0.name }),
          [
            "Request started",
            "Request ended",
            "Received error response",
          ]
        )
      } assertAttributes: { attributes in
        XCTAssertEqual(
          attributes,
          [
            "rpc.system": .string("grpc"),
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "rpc.grpc.status_code": .int(14),  // this is unavailable's raw code
            "server.address": .string("someserver.com"),
            "server.port": .int(567),
            "network.peer.address": .string("10.1.2.80"),
            "network.peer.port": .int(567),
            "network.transport": .string("tcp"),
            "network.type": .string("ipv4"),
          ]
        )
      } assertStatus: { status in
        XCTAssertEqual(status, .some(.init(code: .error)))
      } assertErrors: { errors in
        XCTAssertEqual(errors.count, 1)
      }
    }
  }

  // - MARK: Server Interceptor Tests

  func testServerInterceptor_IPv4() async throws {
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "TracingInterceptorTests",
      method: "testServerInterceptor"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      emitEventOnEachWrite: false
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())
    let response = try await interceptor.intercept(
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: "ipv4:10.1.2.80:567",
        localPeer: "ipv4:10.1.2.90:123",
        cancellation: .init()
      )
    ) { _, _ in
      // Make sure we get the metadata injected into our service context
      XCTAssertEqual(ServiceContext.current?.traceID, traceIDString)

      return StreamingServerResponse<String>(
        accepted: .success(
          .init(
            metadata: [],
            producer: { writer in
              try await writer.write("response1")
              try await writer.write("response2")
              return ["Result": "Trailing metadata"]
            }
          )
        )
      )
    }

    // Get the response out into a response stream, and assert its contents
    let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
    )
    responseStreamContinuation.finish()

    await AssertStreamContentsEqual(["response1", "response2"], responseStream)
    XCTAssertEqual(trailingMetadata, ["Result": "Trailing metadata"])

    AssertTestSpanComponents(forMethod: methodDescriptor) { events in
      XCTAssertEqual(
        events.map({ $0.name }),
        [
          "Received request",
          "Finished processing request",
          "Sent response end",
        ]
      )
    } assertAttributes: { attributes in
      XCTAssertEqual(
        attributes,
        [
          "rpc.system": .string("grpc"),
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "server.address": .string("someserver.com"),
          "server.port": .int(123),
          "network.peer.address": .string("10.1.2.90"),
          "network.peer.port": .int(123),
          "network.transport": .string("tcp"),
          "network.type": .string("ipv4"),
          "client.address": .string("10.1.2.80"),
          "client.port": .int(567),
        ]
      )
    } assertStatus: { status in
      XCTAssertNil(status)
    } assertErrors: { errors in
      XCTAssertEqual(errors, [])
    }
  }

  func testServerInterceptor_IPv6() async throws {
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "TracingInterceptorTests",
      method: "testServerInterceptor"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      emitEventOnEachWrite: false
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())
    let response = try await interceptor.intercept(
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: "ipv6:2001::130F:::09C0:876A:130B:1234",
        localPeer: "ipv6:ff06:0:0:0:0:0:0:c3:5678",
        cancellation: .init()
      )
    ) { _, _ in
      // Make sure we get the metadata injected into our service context
      XCTAssertEqual(ServiceContext.current?.traceID, traceIDString)

      return StreamingServerResponse<String>(
        accepted: .success(
          .init(
            metadata: [],
            producer: { writer in
              try await writer.write("response1")
              try await writer.write("response2")
              return ["Result": "Trailing metadata"]
            }
          )
        )
      )
    }

    // Get the response out into a response stream, and assert its contents
    let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
    )
    responseStreamContinuation.finish()

    XCTAssertEqual(trailingMetadata, ["Result": "Trailing metadata"])
    await AssertStreamContentsEqual(["response1", "response2"], responseStream)

    AssertTestSpanComponents(forMethod: methodDescriptor) { events in
      XCTAssertEqual(
        events.map({ $0.name }),
        [
          "Received request",
          "Finished processing request",
          "Sent response end",
        ]
      )
    } assertAttributes: { attributes in
      XCTAssertEqual(
        attributes,
        [
          "rpc.system": .string("grpc"),
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "server.address": .string("someserver.com"),
          "server.port": .int(5678),
          "network.peer.address": .string("ff06:0:0:0:0:0:0:c3"),
          "network.peer.port": .int(5678),
          "network.transport": .string("tcp"),
          "network.type": .string("ipv6"),
          "client.address": .string("2001::130F:::09C0:876A:130B"),
          "client.port": .int(1234),
        ]
      )
    } assertStatus: { status in
      XCTAssertNil(status)
    } assertErrors: { errors in
      XCTAssertEqual(errors, [])
    }
  }

  func testServerInterceptor_UDS() async throws {
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "TracingInterceptorTests",
      method: "testServerInterceptor"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      emitEventOnEachWrite: false
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())
    let response = try await interceptor.intercept(
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: "unix:some-path",
        localPeer: "unix:some-path",
        cancellation: .init()
      )
    ) { _, _ in
      // Make sure we get the metadata injected into our service context
      XCTAssertEqual(ServiceContext.current?.traceID, traceIDString)

      return StreamingServerResponse<String>(
        accepted: .success(
          .init(
            metadata: [],
            producer: { writer in
              try await writer.write("response1")
              try await writer.write("response2")
              return ["Result": "Trailing metadata"]
            }
          )
        )
      )
    }

    // Get the response out into a response stream, and assert its contents
    let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
    )
    responseStreamContinuation.finish()

    XCTAssertEqual(trailingMetadata, ["Result": "Trailing metadata"])
    await AssertStreamContentsEqual(["response1", "response2"], responseStream)

    AssertTestSpanComponents(forMethod: methodDescriptor) { events in
      XCTAssertEqual(
        events.map({ $0.name }),
        [
          "Received request",
          "Finished processing request",
          "Sent response end",
        ]
      )
    } assertAttributes: { attributes in
      XCTAssertEqual(
        attributes,
        [
          "rpc.system": .string("grpc"),
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "server.address": .string("someserver.com"),
          "network.peer.address": .string("some-path"),
          "network.transport": .string("tcp"),
          "network.type": .string("unix"),
          "client.address": .string("some-path"),
        ]
      )
    } assertStatus: { status in
      XCTAssertNil(status)
    } assertErrors: { errors in
      XCTAssertEqual(errors, [])
    }
  }

  func testServerInterceptorAllEventsRecorded() async throws {
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "TracingInterceptorTests",
      method: "testServerInterceptorAllEventsRecorded"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      emitEventOnEachWrite: true
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())
    let response = try await interceptor.intercept(
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: "ipv4:10.1.2.80:567",
        localPeer: "ipv4:10.1.2.90:123",
        cancellation: .init()
      )
    ) { request, _ in
      // Make sure we get the metadata injected into our service context
      XCTAssertEqual(ServiceContext.current?.traceID, traceIDString)

      for try await _ in request.messages {
        // We need to iterate over the messages for the span to be able to record the events.
      }

      return StreamingServerResponse<String>(
        accepted: .success(
          .init(
            metadata: [],
            producer: { writer in
              try await writer.write("response1")
              try await writer.write("response2")
              return ["Result": "Trailing metadata"]
            }
          )
        )
      )
    }

    // Get the response out into a response stream, and assert its contents
    let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
    )
    responseStreamContinuation.finish()

    XCTAssertEqual(trailingMetadata, ["Result": "Trailing metadata"])
    await AssertStreamContentsEqual(["response1", "response2"], responseStream)

    AssertTestSpanComponents(forMethod: methodDescriptor) { events in
      XCTAssertEqual(
        events,
        [
          TestSpanEvent("Received request", [:]),
          // Recorded when request is received
          TestSpanEvent("rpc.message", ["rpc.message.type": "RECEIVED", "rpc.message.id": 1]),
          // Recorded after all request parts have been received
          TestSpanEvent("Finished processing request", [:]),
          // Recorded when `response1` is sent
          TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 1]),
          // Recorded when `response2` is sent
          TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 2]),
          // Recorded at end of response
          TestSpanEvent("Sent response end", [:]),
        ]
      )
    } assertAttributes: { attributes in
      XCTAssertEqual(
        attributes,
        [
          "rpc.system": .string("grpc"),
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "server.address": .string("someserver.com"),
          "server.port": .int(123),
          "network.peer.address": .string("10.1.2.90"),
          "network.peer.port": .int(123),
          "network.transport": .string("tcp"),
          "network.type": .string("ipv4"),
          "client.address": .string("10.1.2.80"),
          "client.port": .int(567),
        ]
      )
    } assertStatus: { status in
      XCTAssertNil(status)
    } assertErrors: { errors in
      XCTAssertEqual(errors, [])
    }
  }

  func testServerInterceptorErrorEncountered() async throws {
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "TracingInterceptorTests",
      method: "testServerInterceptorErrorEncountered"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      emitEventOnEachWrite: false
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())
    do {
      let _: StreamingServerResponse<String> = try await interceptor.intercept(
        request: .init(single: request),
        context: ServerContext(
          descriptor: methodDescriptor,
          remotePeer: "ipv4:10.1.2.80:567",
          localPeer: "ipv4:10.1.2.90:123",
          cancellation: .init()
        )
      ) { _, _ in
        // Make sure we get the metadata injected into our service context
        XCTAssertEqual(ServiceContext.current?.traceID, traceIDString)

        throw TracingInterceptorTestError.testError
      }
      XCTFail("Should have thrown")
    } catch {
      AssertTestSpanComponents(forMethod: methodDescriptor) { events in
        XCTAssertEqual(events.map({ $0.name }), ["Received request"])
      } assertAttributes: { attributes in
        // The attributes should not contain a grpc status code, as the request was never even sent.
        XCTAssertEqual(
          attributes,
          [
            "rpc.system": .string("grpc"),
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "server.address": .string("someserver.com"),
            "server.port": .int(123),
            "network.peer.address": .string("10.1.2.90"),
            "network.peer.port": .int(123),
            "network.transport": .string("tcp"),
            "network.type": .string("ipv4"),
            "client.address": .string("10.1.2.80"),
            "client.port": .int(567),
          ]
        )
      } assertStatus: { status in
        XCTAssertNil(status)
      } assertErrors: { errors in
        XCTAssertEqual(errors, [.testError])
      }
    }
  }

  func testServerInterceptorErrorResponse() async throws {
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "TracingInterceptorTests",
      method: "testServerInterceptorErrorResponse"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      emitEventOnEachWrite: false
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())
    let response = try await interceptor.intercept(
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: "ipv4:10.1.2.80:567",
        localPeer: "ipv4:10.1.2.90:123",
        cancellation: .init()
      )
    ) { _, _ in
      // Make sure we get the metadata injected into our service context
      XCTAssertEqual(ServiceContext.current?.traceID, traceIDString)

      return StreamingServerResponse<String>(
        error: RPCError(code: .unavailable, message: "Test error")
      )
    }

    XCTAssertThrowsError(try response.accepted.get())

    AssertTestSpanComponents(forMethod: methodDescriptor) { events in
      XCTAssertEqual(
        events.map({ $0.name }),
        [
          "Received request",
          "Finished processing request",
          "Sent error response",
        ]
      )
    } assertAttributes: { attributes in
      XCTAssertEqual(
        attributes,
        [
          "rpc.system": .string("grpc"),
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": .int(14),  // this is unavailable's raw code
          "server.address": .string("someserver.com"),
          "server.port": .int(123),
          "network.peer.address": .string("10.1.2.90"),
          "network.peer.port": .int(123),
          "network.transport": .string("tcp"),
          "network.type": .string("ipv4"),
          "client.address": .string("10.1.2.80"),
          "client.port": .int(567),
        ]
      )
    } assertStatus: { status in
      XCTAssertEqual(status, .some(.init(code: .error)))
    } assertErrors: { errors in
      XCTAssertEqual(errors.count, 1)
    }
  }

  // -  MARK: Utilities

  private func getTestSpanForMethod(_ methodDescriptor: MethodDescriptor) -> TestSpan {
    let tracer = InstrumentationSystem.tracer as! TestTracer
    return tracer.getSpan(ofOperation: methodDescriptor.fullyQualifiedMethod)!
  }

  private func AssertTestSpanComponents(
    forMethod method: MethodDescriptor,
    assertEvents: ([TestSpanEvent]) -> Void,
    assertAttributes: (SpanAttributes) -> Void,
    assertStatus: (SpanStatus?) -> Void,
    assertErrors: ([TracingInterceptorTestError]) -> Void
  ) {
    let span = self.getTestSpanForMethod(method)
    assertEvents(span.events.map({ TestSpanEvent($0) }))
    assertAttributes(span.attributes)
    assertStatus(span.status)
    assertErrors(span.errors)
  }

  private func AssertStreamContentsEqual<T: Equatable>(
    _ array: [T],
    _ stream: any AsyncSequence<T, any Error>
  ) async throws {
    var streamElements = [T]()
    for try await element in stream {
      streamElements.append(element)
    }
    XCTAssertEqual(streamElements, array)
  }

  private func AssertStreamContentsEqual<T: Equatable>(
    _ array: [T],
    _ stream: any AsyncSequence<T, Never>
  ) async {
    var streamElements = [T]()
    for await element in stream {
      streamElements.append(element)
    }
    XCTAssertEqual(streamElements, array)
  }
}
