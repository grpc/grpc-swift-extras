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
internal import GRPCInterceptorsCore
package import Metrics

/// A client interceptor that records metrics information for a request.
///
/// For more information, refer to the documentation for `swift-metrics`.
///
/// This interceptor will record all required and recommended metrics and dimensions as defined by OpenTelemetry's documentation on:
/// - https://opentelemetry.io/docs/specs/semconv/rpc/rpc-metrics
@available(gRPCSwiftExtras 2.0, *)
public struct ClientOTelMetricsInterceptor: ClientInterceptor {
  private let serverHostname: String
  private let networkTransport: String
  private let metricsFactory: (any MetricsFactory)?

  /// Create a new instance of a `ClientOTelMetricsInterceptor`.
  /// - Parameters:
  ///   - serverHostname: The hostname of the RPC server. This will be the value for the `server.address` dimension in metrics.
  ///   - networkTransport: The transport in use (e.g. "tcp", "unix"). This will be the value for the
  ///  `network.transport` dimension in metrics.
  public init(serverHostname: String, networkTransport: String) {
    self.init(
      serverHostname: serverHostname,
      networkTransport: networkTransport,
      metricsFactory: nil
    )
  }

  package init(
    serverHostname: String,
    networkTransport: String,
    metricsFactory: (any MetricsFactory)?
  ) {
    self.serverHostname = serverHostname
    self.networkTransport = networkTransport
    self.metricsFactory = metricsFactory
  }

  public func intercept<Input: Sendable, Output: Sendable>(
    request: StreamingClientRequest<Input>,
    context: ClientContext,
    next: (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<
      Output
    >
  ) async throws -> StreamingClientResponse<Output> {
    let dimensions = context.dimensions(
      serverHostname: self.serverHostname,
      networkTransport: self.networkTransport
    )

    let metricsContext = GRPCMetricsContext(
      kind: .client,
      dimensions: dimensions,
      metricsFactory: self.metricsFactory ?? MetricsSystem.factory
    )

    var request = request
    let wrappedProducer = request.producer
    request.producer = { writer in
      let metricsWriter = HookedWriter(wrapping: writer) {
        metricsContext.recordSentMessage()
      }
      try await wrappedProducer(RPCWriter(wrapping: metricsWriter))
    }

    var response = try await next(request, context)

    switch response.accepted {
    case var .success(contents):
      let sequence = HookedRPCAsyncSequence(wrapping: contents.bodyParts) { _ in
        metricsContext.recordReceivedMessage()
      } onFinish: { error in
        metricsContext.recordCallFinished(error: error)
      }

      contents.bodyParts = RPCAsyncSequence(wrapping: sequence)
      response.accepted = .success(contents)
    case let .failure(rpcError):
      metricsContext.recordCallFinished(error: rpcError)
    }

    return response
  }
}
