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
internal import Tracing

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
public struct ClientOTelTracingInterceptor: ClientInterceptor {
  private let injector: ClientRequestInjector
  private let emitEventOnEachWrite: Bool
  private var serverHostname: String
  private var networkTransportMethod: String

  /// Create a new instance of a ``ClientOTelTracingInterceptor``.
  ///
  /// - Parameters:
  ///  - severHostname: The hostname of the RPC server. This will be the value for the `server.address` attribute in spans.
  ///  - networkTransportMethod: The transport in use (e.g. "tcp", "udp"). This will be the value for the
  ///  `network.transport` attribute in spans.
  ///  - emitEventOnEachWrite: If `true`, each request part sent and response part received will be recorded as a separate
  ///  event in a tracing span. Otherwise, only the request/response start and end will be recorded as events.
  public init(
    serverHostname: String,
    networkTransportMethod: String,
    emitEventOnEachWrite: Bool = false
  ) {
    self.injector = ClientRequestInjector()
    self.serverHostname = serverHostname
    self.networkTransportMethod = networkTransportMethod
    self.emitEventOnEachWrite = emitEventOnEachWrite
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
    var request = request
    let tracer = InstrumentationSystem.tracer
    let serviceContext = ServiceContext.current ?? .topLevel

    tracer.inject(
      serviceContext,
      into: &request.metadata,
      using: self.injector
    )

    return try await tracer.withSpan(
      context.descriptor.fullyQualifiedMethod,
      context: serviceContext,
      ofKind: .client
    ) { span in
      span.setOTelClientSpanGRPCAttributes(
        context: context,
        serverHostname: self.serverHostname,
        networkTransportMethod: self.networkTransportMethod
      )

      span.addEvent("Request started")

      let wrappedProducer = request.producer
      if self.emitEventOnEachWrite {
        request.producer = { writer in
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
          try await wrappedProducer(RPCWriter(wrapping: eventEmittingWriter))
          span.addEvent("Request ended")
        }
      } else {
        request.producer = { writer in
          try await wrappedProducer(RPCWriter(wrapping: writer))
          span.addEvent("Request ended")
        }
      }

      var response = try await next(request, context)
      switch response.accepted {
      case .success(var success):
        span.addEvent("Received response start")
        span.attributes.rpc.grpcStatusCode = 0
        if self.emitEventOnEachWrite {
          let messageReceivedCounter = Atomic(1)
          let onEachPartRecordingSequence = success.bodyParts.map { element in
            var event = SpanEvent(name: "rpc.message")
            event.attributes.rpc.messageType = "RECEIVED"
            event.attributes.rpc.messageID =
              messageReceivedCounter
              .wrappingAdd(1, ordering: .sequentiallyConsistent)
              .oldValue
            span.addEvent(event)
            return element
          }

          let onFinishRecordingSequence = OnFinishAsyncSequence(
            wrapping: onEachPartRecordingSequence
          ) {
            span.addEvent("Received response end")
          }

          success.bodyParts = RPCAsyncSequence(wrapping: onFinishRecordingSequence)
          response.accepted = .success(success)
        } else {
          let onFinishRecordingSequence = OnFinishAsyncSequence(wrapping: success.bodyParts) {
            span.addEvent("Received response end")
          }

          success.bodyParts = RPCAsyncSequence(wrapping: onFinishRecordingSequence)
          response.accepted = .success(success)
        }

      case .failure(let error):
        span.attributes.rpc.grpcStatusCode = error.code.rawValue
        span.setStatus(SpanStatus(code: .error))
        span.addEvent("Received error response")
        span.recordError(error)
      }

      return response
    }
  }
}

/// An injector responsible for injecting the required instrumentation keys from the `ServiceContext` into
/// the request metadata.
struct ClientRequestInjector: Instrumentation.Injector {
  typealias Carrier = Metadata

  func inject(_ value: String, forKey key: String, into carrier: inout Carrier) {
    carrier.addString(value, forKey: key)
  }
}
