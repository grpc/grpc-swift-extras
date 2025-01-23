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

public import GRPCCore
internal import Synchronization
package import Tracing

/// A server interceptor that extracts tracing information from the request.
///
/// The extracted tracing information is made available to user code via the current `ServiceContext`.
///
/// For more information, refer to the documentation for `swift-distributed-tracing`.
///
/// This interceptor will also inject all required and recommended span and event attributes, and set span status, as defined by
/// OpenTelemetry's documentation on:
/// - https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans
/// - https://opentelemetry.io/docs/specs/semconv/rpc/grpc/
public struct ServerOTelTracingInterceptor: ServerInterceptor {
  private let extractor: ServerRequestExtractor
  private let traceEachMessage: Bool
  private var serverHostname: String
  private var networkTransportMethod: String

  /// Create a new instance of a ``ServerOTelTracingInterceptor``.
  ///
  /// - Parameters:
  ///  - severHostname: The hostname of the RPC server. This will be the value for the `server.address` attribute in spans.
  ///  - networkTransportMethod: The transport in use (e.g. "tcp", "udp"). This will be the value for the
  ///  `network.transport` attribute in spans.
  ///  - traceEachMessage: If `true`, each response part sent and request part received will be recorded as a separate
  ///  event in a tracing span.
  public init(
    serverHostname: String,
    networkTransportMethod: String,
    traceEachMessage: Bool = true
  ) {
    self.extractor = ServerRequestExtractor()
    self.traceEachMessage = traceEachMessage
    self.serverHostname = serverHostname
    self.networkTransportMethod = networkTransportMethod
  }

  /// This interceptor will extract whatever `ServiceContext` key-value pairs have been inserted into the
  /// request's metadata, and will make them available to user code via the `ServiceContext/current`
  /// context.
  ///
  /// Which key-value pairs are extracted and made available will depend on the specific tracing implementation
  /// that has been configured when bootstrapping `swift-distributed-tracing` in your application.
  ///
  /// It will also inject all required and recommended span and event attributes, and set span status, as defined by OpenTelemetry's
  /// documentation on:
  /// - https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans
  /// - https://opentelemetry.io/docs/specs/semconv/rpc/grpc/
  public func intercept<Input, Output>(
    request: StreamingServerRequest<Input>,
    context: ServerContext,
    next: @Sendable (StreamingServerRequest<Input>, ServerContext) async throws ->
    StreamingServerResponse<Output>
  ) async throws -> StreamingServerResponse<Output> where Input: Sendable, Output: Sendable {
    try await self.intercept(
      tracer: InstrumentationSystem.tracer,
      request: request,
      context: context,
      next: next
    )
  }

  /// Same as ``intercept(request:context:next:)``, but allows specifying a `Tracer` for testing purposes.
  package func intercept<Input, Output>(
    tracer: any Tracer,
    request: StreamingServerRequest<Input>,
    context: ServerContext,
    next: @Sendable (StreamingServerRequest<Input>, ServerContext) async throws ->
      StreamingServerResponse<Output>
  ) async throws -> StreamingServerResponse<Output> where Input: Sendable, Output: Sendable {
    var serviceContext = ServiceContext.topLevel

    tracer.extract(
      request.metadata,
      into: &serviceContext,
      using: self.extractor
    )

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    return try await ServiceContext.$current.withValue(serviceContext) {
      try await tracer.withSpan(
        context.descriptor.fullyQualifiedMethod,
        context: serviceContext,
        ofKind: .server
      ) { span in
        span.setOTelServerSpanGRPCAttributes(
          context: context,
          serverHostname: self.serverHostname,
          networkTransportMethod: self.networkTransportMethod
        )

        var request = request
        if self.traceEachMessage {
          let messageReceivedCounter = Atomic(1)
          request.messages = RPCAsyncSequence(
            wrapping: request.messages.map { element in
              var event = SpanEvent(name: "rpc.message")
              event.attributes[GRPCTracingKeys.rpcMessageType] = "RECEIVED"
              event.attributes[GRPCTracingKeys.rpcMessageID] = messageReceivedCounter
                .wrappingAdd(1, ordering: .sequentiallyConsistent)
                .oldValue
              span.addEvent(event)
              return element
            }
          )
        }

        var response = try await next(request, context)

        switch response.accepted {
        case .success(var success):
          let wrappedProducer = success.producer

          if self.traceEachMessage {
            success.producer = { writer in
              let messageSentCounter = Atomic(1)
              let eventEmittingWriter = HookedWriter(
                wrapping: writer,
                afterEachWrite: {
                  var event = SpanEvent(name: "rpc.message")
                  event.attributes[GRPCTracingKeys.rpcMessageType] = "SENT"
                  event.attributes[GRPCTracingKeys.rpcMessageID] = messageSentCounter
                    .wrappingAdd(1, ordering: .sequentiallyConsistent)
                    .oldValue
                  span.addEvent(event)
                }
              )

              let wrappedResult = try await wrappedProducer(
                RPCWriter(wrapping: eventEmittingWriter)
              )

              return wrappedResult
            }
          } else {
            success.producer = { writer in
              return try await wrappedProducer(writer)
            }
          }

          response = .init(accepted: .success(success))

        case .failure(let error):
          span.attributes[GRPCTracingKeys.grpcStatusCode] = error.code.rawValue
          span.setStatus(SpanStatus(code: .error))
          span.recordError(error)
        }

        return response
      }
    }
  }
}

/// An extractor responsible for extracting the required instrumentation keys from request metadata.
struct ServerRequestExtractor: Instrumentation.Extractor {
  typealias Carrier = Metadata

  func extract(key: String, from carrier: Carrier) -> String? {
    var values = carrier[stringValues: key].makeIterator()
    // There should only be one value for each key. If more, pick just one.
    return values.next()
  }
}
