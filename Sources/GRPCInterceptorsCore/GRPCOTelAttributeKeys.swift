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

package enum GRPCOTelAttributeKeys {
  package static let rpcSystem = "rpc.system"
  package static let rpcMethod = "rpc.method"
  package static let rpcService = "rpc.service"
  package static let rpcMessageID = "rpc.message.id"
  package static let rpcMessageType = "rpc.message.type"
  package static let grpcStatusCode = "rpc.grpc.status_code"

  package static let serverAddress = "server.address"
  package static let serverPort = "server.port"

  package static let clientAddress = "client.address"
  package static let clientPort = "client.port"

  package static let networkTransport = "network.transport"
  package static let networkType = "network.type"
  package static let networkPeerAddress = "network.peer.address"
  package static let networkPeerPort = "network.peer.port"

  package static let requestMetadataPrefix = "rpc.grpc.request.metadata."
  package static let responseMetadataPrefix = "rpc.grpc.response.metadata."
}
