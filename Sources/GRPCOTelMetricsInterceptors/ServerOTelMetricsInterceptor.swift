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

/// A server interceptor that records metrics information for a request.
///
/// For more information, refer to the documentation for `swift-metrics`.
///
/// This interceptor will record all required and recommended metrics and dimensions as defined by OpenTelemetry's documentation on:
/// - https://opentelemetry.io/docs/specs/semconv/rpc/rpc-metrics
@available(gRPCSwiftExtras 2.0, *)
public struct ServerOTelMetricsInterceptor: ServerInterceptor {
  private let serverHostname: String
  private let networkTransport: String
  private let metricsFactory: (any MetricsFactory)?

  /// Create a new instance of a `ServerOTelMetricsInterceptor`.
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
    request: StreamingServerRequest<Input>,
    context: ServerContext,
    next: (StreamingServerRequest<Input>, ServerContext) async throws -> StreamingServerResponse<
      Output
    >
  ) async throws -> StreamingServerResponse<Output> {
    let dimensions = context.dimensions(
      serverHostname: self.serverHostname,
      networkTransport: networkTransport
    )

    let metricsContext = GRPCMetricsContext(
      kind: .server,
      dimensions: dimensions,
      metricsFactory: self.metricsFactory ?? MetricsSystem.factory
    )

    var request = request
    request.messages = RPCAsyncSequence(
      wrapping: request.messages.map({ element in
        metricsContext.recordReceivedMessage()
        return element
      })
    )

    var response = try await next(request, context)

    switch response.accepted {
    case var .success(success):
      let wrappedProducer = success.producer

      success.producer = { writer in
        let hookedWriter = HookedWriter(wrapping: writer) {
          metricsContext.recordSentMessage()
        }

        let metadata: Metadata
        do {
          metadata = try await wrappedProducer(RPCWriter(wrapping: hookedWriter))
        } catch {
          metricsContext.recordCallFinished(error: error)
          throw error
        }

        metricsContext.recordCallFinished(error: nil)
        return metadata
      }

      response.accepted = .success(success)
      return response
    case let .failure(rpcError):
      metricsContext.recordCallFinished(error: rpcError)
    }

    return response
  }
}
