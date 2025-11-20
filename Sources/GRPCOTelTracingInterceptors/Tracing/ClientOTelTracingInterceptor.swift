/*
 * Copyright 2024-2025, gRPC Authors All rights reserved.
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

public import GRPCCore
internal import Synchronization
package import Tracing

/// A client interceptor that injects tracing information into the request.
///
/// The tracing information is taken from the current `ServiceContext`, and injected into the request's
/// metadata. It will then be picked up by the server-side ``ServerOTelTracingInterceptor``.
///
/// For more information, refer to the documentation for `swift-distributed-tracing`.
///
/// This interceptor will also inject all required and recommended span and event attributes, and set span status, as defined by
/// OpenTelemetry's documentation on:
/// - https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans
/// - https://opentelemetry.io/docs/specs/semconv/rpc/grpc/
@available(gRPCSwiftExtras 2.0, *)
public struct ClientOTelTracingInterceptor: ClientInterceptor {
  private let injector: ClientRequestInjector
  private var serverHostname: String
  private var networkTransportMethod: String

  private let traceEachMessage: Bool
  private var includeRequestMetadata: Bool
  private var includeResponseMetadata: Bool
  private let tracerOverride: (any Tracer)?

  /// Create a new instance of a ``ClientOTelTracingInterceptor``.
  ///
  /// - Parameters:
  ///  - severHostname: The hostname of the RPC server. This will be the value for the `server.address` attribute in spans.
  ///  - networkTransportMethod: The transport in use (e.g. "tcp", "unix"). This will be the value for the
  ///  `network.transport` attribute in spans.
  ///  - traceEachMessage: If `true`, each request part sent and response part received will be recorded as a separate
  ///  event in a tracing span.
  ///
  /// - Important: Be careful when setting `includeRequestMetadata` or `includeResponseMetadata` to `true`,
  /// as including all request/response metadata can be a security risk.
  public init(
    serverHostname: String,
    networkTransportMethod: String,
    traceEachMessage: Bool = true
  ) {
    self.init(
      serverHostname: serverHostname,
      networkTransportMethod: networkTransportMethod,
      traceEachMessage: traceEachMessage,
      includeRequestMetadata: false,
      includeResponseMetadata: false
    )
  }

  /// Create a new instance of a ``ClientOTelTracingInterceptor``.
  ///
  /// - Parameters:
  ///  - severHostname: The hostname of the RPC server. This will be the value for the `server.address` attribute in spans.
  ///  - networkTransportMethod: The transport in use (e.g. "tcp", "unix"). This will be the value for the
  ///  `network.transport` attribute in spans.
  ///  - traceEachMessage: If `true`, each request part sent and response part received will be recorded as a separate
  ///  event in a tracing span.
  ///  - includeRequestMetadata: if `true`, **all** metadata keys with string values included in the request will be added to the span as attributes.
  ///  - includeResponseMetadata: if `true`, **all** metadata keys with string values included in the response will be added to the span as attributes.
  public init(
    serverHostname: String,
    networkTransportMethod: String,
    traceEachMessage: Bool = true,
    includeRequestMetadata: Bool = false,
    includeResponseMetadata: Bool = false
  ) {
    self.init(
      serverHostname: serverHostname,
      networkTransportMethod: networkTransportMethod,
      traceEachMessage: traceEachMessage,
      includeRequestMetadata: includeRequestMetadata,
      includeResponseMetadata: includeResponseMetadata,
      tracerOverride: nil
    )
  }

  package init(
    serverHostname: String,
    networkTransportMethod: String,
    traceEachMessage: Bool,
    includeRequestMetadata: Bool,
    includeResponseMetadata: Bool,
    tracerOverride: (any Tracer)?
  ) {
    self.injector = ClientRequestInjector()
    self.serverHostname = serverHostname
    self.networkTransportMethod = networkTransportMethod
    self.traceEachMessage = traceEachMessage
    self.includeRequestMetadata = includeRequestMetadata
    self.includeResponseMetadata = includeResponseMetadata
    self.tracerOverride = tracerOverride
  }

  /// This interceptor will inject as the request's metadata whatever `ServiceContext` key-value pairs
  /// have been made available by the tracing implementation bootstrapped in your application.
  ///
  /// Which key-value pairs are injected will depend on the specific tracing implementation
  /// that has been configured when bootstrapping `swift-distributed-tracing` in your application.
  ///
  /// It will also inject all required and recommended span and event attributes, and set span status, as defined by OpenTelemetry's
  /// documentation on:
  /// - https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans
  /// - https://opentelemetry.io/docs/specs/semconv/rpc/grpc/
  public func intercept<Input, Output>(
    request: StreamingClientRequest<Input>,
    context: ClientContext,
    next: (
      StreamingClientRequest<Input>,
      ClientContext
    ) async throws -> StreamingClientResponse<Output>
  ) async throws -> StreamingClientResponse<Output> where Input: Sendable, Output: Sendable {
    try await self.intercept(
      tracer: self.tracerOverride ?? InstrumentationSystem.tracer,
      request: request,
      context: context,
      next: next
    )
  }

  /// Same as ``intercept(request:context:next:)``, but allows specifying a `Tracer` for testing purposes.
  package func intercept<Input, Output>(
    tracer: any Tracer,
    request: StreamingClientRequest<Input>,
    context: ClientContext,
    next: (
      StreamingClientRequest<Input>,
      ClientContext
    ) async throws -> StreamingClientResponse<Output>
  ) async throws -> StreamingClientResponse<Output> where Input: Sendable, Output: Sendable {
    var request = request
    let span = tracer.startSpan(context.descriptor.fullyQualifiedMethod, ofKind: .client)

    span.setOTelClientSpanGRPCAttributes(
      context: context,
      serverHostname: self.serverHostname,
      networkTransportMethod: self.networkTransportMethod
    )

    if self.includeRequestMetadata {
      span.setMetadataStringAttributesAsRequestSpanAttributes(request.metadata)
    }

    tracer.inject(span.context, into: &request.metadata, using: self.injector)

    if self.traceEachMessage {
      let originalProducer = request.producer
      request.producer = { writer in
        let tracingWriter = TracedMessageWriter(wrapping: writer, span: span)
        return try await originalProducer(RPCWriter(wrapping: tracingWriter))
      }
    }

    var response: StreamingClientResponse<Output>

    do {
      response = try await ServiceContext.$current.withValue(span.context) {
        try await next(request, context)
      }
    } catch {
      span.endRPC(withError: error)
      throw error
    }

    if self.includeResponseMetadata {
      span.setMetadataStringAttributesAsResponseSpanAttributes(response.metadata)
    }

    switch response.accepted {
    case .success(var success):
      let tracedResponse = TracedClientResponseBodyParts(
        wrapping: success.bodyParts,
        span: span,
        eventPerMessage: self.traceEachMessage,
        includeMetadata: self.includeResponseMetadata
      )
      success.bodyParts = RPCAsyncSequence(wrapping: tracedResponse)
      response.accepted = .success(success)

    case .failure(let error):
      span.endRPC(withError: error)
    }

    return response
  }
}

/// An injector responsible for injecting the required instrumentation keys from the `ServiceContext` into
/// the request metadata.
@available(gRPCSwiftExtras 2.0, *)
struct ClientRequestInjector: Instrumentation.Injector {
  typealias Carrier = Metadata

  func inject(_ value: String, forKey key: String, into carrier: inout Carrier) {
    carrier.addString(value, forKey: key)
  }
}

@available(gRPCSwiftExtras 2.0, *)
internal struct TracedClientResponseBodyParts<Output>: AsyncSequence, Sendable
where Output: Sendable {
  typealias Base = RPCAsyncSequence<StreamingClientResponse<Output>.Contents.BodyPart, any Error>
  typealias Element = Base.Element

  private let base: Base
  private var span: any Span
  private var eventPerMessage: Bool
  private var includeMetadata: Bool

  init(
    wrapping base: Base,
    span: any Span,
    eventPerMessage: Bool,
    includeMetadata: Bool
  ) {
    self.base = base
    self.span = span
    self.eventPerMessage = eventPerMessage
    self.includeMetadata = includeMetadata
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(
      wrapping: self.base.makeAsyncIterator(),
      span: self.span,
      eventPerMessage: self.eventPerMessage,
      includeMetadata: self.includeMetadata
    )
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    typealias Element = Base.Element

    private var wrapped: Base.AsyncIterator
    private var span: any Span
    private var messageID: Int
    private var eventPerMessage: Bool
    private var includeMetadata: Bool

    init(
      wrapping iterator: Base.AsyncIterator,
      span: any Span,
      eventPerMessage: Bool,
      includeMetadata: Bool
    ) {
      self.wrapped = iterator
      self.span = span
      self.eventPerMessage = eventPerMessage
      self.includeMetadata = includeMetadata
      self.messageID = 1
    }

    private mutating func nextMessageID() -> Int {
      defer { self.messageID += 1 }
      return self.messageID
    }

    mutating func next(
      isolation actor: isolated (any Actor)?
    ) async throws(any Error) -> Element? {
      do {
        if let element = try await self.wrapped.next(isolation: actor) {
          if self.eventPerMessage {
            switch element {
            case .message:
              self.span.addEvent(.messageReceived(id: self.nextMessageID()))

            case .trailingMetadata(let metadata):
              if self.includeMetadata {
                self.span.setMetadataStringAttributesAsResponseSpanAttributes(metadata)
              }
            }
          }

          return element
        } else {
          self.span.endRPC()
          return nil
        }
      } catch {
        self.span.endRPC(withError: error)
        throw error
      }
    }

    mutating func next() async throws -> Element? {
      try await self.next(isolation: nil)
    }
  }
}
