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
internal import Tracing
internal import Synchronization

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
  private let emitEventOnEachWrite: Bool
  private var serverHostname: String
  private var networkTransportMethod: String

  /// Create a new instance of a ``ServerOTelTracingInterceptor``.
  ///
  /// - Parameters:
  ///  - severHostname: The hostname of the RPC server. This will be the value for the `server.address` attribute in spans.
  ///  - networkTransportMethod: The transport in use (e.g. "tcp", "udp"). This will be the value for the
  ///  `network.transport` attribute in spans.
  ///  - emitEventOnEachWrite: If `true`, each response part sent and request part received will be recorded as a separate
  ///  event in a tracing span. Otherwise, only the request/response start and end will be recorded as events.
  public init(
    serverHostname: String,
    networkTransportMethod: String,
    emitEventOnEachWrite: Bool = false
  ) {
    self.extractor = ServerRequestExtractor()
    self.emitEventOnEachWrite = emitEventOnEachWrite
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
    var serviceContext = ServiceContext.topLevel
    let tracer = InstrumentationSystem.tracer

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

        span.addEvent("Received request")

        var request = request
        if self.emitEventOnEachWrite {
          let messageReceivedCounter = Atomic(1)
          request.messages = RPCAsyncSequence(
            wrapping: request.messages.map { element in
              var event = SpanEvent(name: "rpc.message")
              event.attributes.rpc.messageType = "RECEIVED"
              event.attributes.rpc.messageID =
              messageReceivedCounter
                .wrappingAdd(1, ordering: .sequentiallyConsistent)
                .oldValue
              span.addEvent(event)
              return element
            }
          )
        }

        var response = try await next(request, context)

        span.addEvent("Finished processing request")

        switch response.accepted {
        case .success(var success):
          let wrappedProducer = success.producer

          if self.emitEventOnEachWrite {
            success.producer = { writer in
              let messageSentCounter = Atomic(1)
              let eventEmittingWriter = HookedWriter(
                wrapping: writer,
                afterEachWrite: {
                  var event = SpanEvent(name: "rpc.message")
                  event.attributes.rpc.messageType = "SENT"
                  event.attributes.rpc.messageID =
                  messageSentCounter
                    .wrappingAdd(1, ordering: .sequentiallyConsistent)
                    .oldValue
                  span.addEvent(event)
                }
              )

              let wrappedResult = try await wrappedProducer(
                RPCWriter(wrapping: eventEmittingWriter)
              )

              span.addEvent("Sent response end")
              return wrappedResult
            }
          } else {
            success.producer = { writer in
              let wrappedResult = try await wrappedProducer(writer)
              span.addEvent("Sent response end")
              return wrappedResult
            }
          }

          response = .init(accepted: .success(success))

        case .failure(let error):
          span.attributes.rpc.grpcStatusCode = error.code.rawValue
          span.setStatus(SpanStatus(code: .error))
          span.addEvent("Sent error response")
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
