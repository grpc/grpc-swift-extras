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

@available(gRPCSwiftExtras 2.0, *)
extension BaseContext {
  func dimensions(
    serverHostname: String,
    networkTransport: String
  ) -> [(String, String)] {
    var dimensions: [(String, String)] = [
      (GRPCOTelAttributeKeys.serverAddress, serverHostname),
      (GRPCOTelAttributeKeys.networkTransport, networkTransport),
      (GRPCOTelAttributeKeys.rpcSystem, "grpc"),
      (GRPCOTelAttributeKeys.rpcService, self.descriptor.service.fullyQualifiedService),
      (GRPCOTelAttributeKeys.rpcMethod, self.descriptor.method),
    ]

    switch PeerAddress(self.remotePeer) {
    case let .ipv4(address, port):
      dimensions.append(contentsOf: [
        (GRPCOTelAttributeKeys.networkType, "ipv4"),
        (GRPCOTelAttributeKeys.networkPeerAddress, address),
      ])
      if let port {
        dimensions.append(contentsOf: [
          (GRPCOTelAttributeKeys.networkPeerPort, port.description),
          (GRPCOTelAttributeKeys.serverPort, port.description),
        ])
      }
    case let .ipv6(address, port):
      dimensions.append(contentsOf: [
        (GRPCOTelAttributeKeys.networkType, "ipv6"),
        (GRPCOTelAttributeKeys.networkPeerAddress, address),
      ])
      if let port {
        dimensions.append(contentsOf: [
          (GRPCOTelAttributeKeys.networkPeerPort, port.description),
          (GRPCOTelAttributeKeys.serverPort, port.description),
        ])
      }
    case let .unixDomainSocket(path):
      dimensions.append((GRPCOTelAttributeKeys.networkPeerAddress, path))
    case .none:
      break
    }

    return dimensions
  }
}
