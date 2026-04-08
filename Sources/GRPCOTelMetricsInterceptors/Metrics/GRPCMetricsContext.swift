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

internal import GRPCCore
internal import GRPCInterceptorsCore
internal import Metrics

@available(gRPCSwiftExtras 2.0, *)
struct GRPCMetricsContext {
  private let kind: ServiceKind
  private let metricsFactory: any MetricsFactory

  private let startTime: ContinuousClock.Instant
  private let dimensions: [(String, String)]

  private let requestsPerRPC: Recorder
  private let responsesPerRPC: Recorder

  init(kind: ServiceKind, dimensions: [(String, String)], metricsFactory: any MetricsFactory) {
    self.kind = kind
    self.metricsFactory = metricsFactory
    self.startTime = .now
    self.dimensions = dimensions

    self.requestsPerRPC = Recorder(
      label: "rpc.\(kind.rawValue).requests_per_rpc",
      dimensions: dimensions,
      factory: metricsFactory
    )
    self.responsesPerRPC = Recorder(
      label: "rpc.\(kind.rawValue).responses_per_rpc",
      dimensions: dimensions,
      factory: metricsFactory
    )
  }

  func recordSentMessage() {
    switch kind {
    case .client:
      requestsPerRPC.record(1)
    case .server:
      responsesPerRPC.record(1)
    }
  }

  func recordReceivedMessage() {
    switch kind {
    case .client:
      responsesPerRPC.record(1)
    case .server:
      requestsPerRPC.record(1)
    }
  }

  func recordCallFinished(error: (any Error)?) {
    var dimensions = dimensions

    let statusCode: Status.Code =
      if let error {
        .init(error.rpcErrorCode ?? .unknown)
      } else {
        .ok
      }

    dimensions.append((GRPCOTelAttributeKeys.grpcStatusCode, statusCode.rawValue.description))

    Metrics.Timer(
      label: "rpc.\(kind.rawValue).duration",
      dimensions: dimensions,
      preferredDisplayUnit: .seconds,
      factory: self.metricsFactory
    )
    .record(duration: .now - startTime)
  }
}

@available(gRPCSwiftExtras 2.0, *)
extension Error {
  fileprivate var rpcErrorCode: RPCError.Code? {
    if let rpcError = self as? RPCError {
      return rpcError.code
    } else if let rpcError = self as? any RPCErrorConvertible {
      return rpcError.rpcErrorCode
    } else {
      return nil
    }
  }
}
