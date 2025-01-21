/*
 * Copyright 2025, gRPC Authors All rights reserved.
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
internal import Tracing

public enum GRPCTracingKeys {
  static let rpcSystem = "rpc.system"
  static let rpcMethod = "rpc.method"
  static let rpcService = "rpc.service"
  static let rpcMessageID = "rpc.message.id"
  static let rpcMessageType = "rpc.message.type"
  static let grpcStatusCode = "rpc.grpc.status_code"

  static let serverAddress = "server.address"
  static let serverPort = "server.port"

  static let clientAddress = "client.address"
  static let clientPort = "client.port"

  static let networkTransport = "network.transport"
  static let networkType = "network.type"
  static let networkPeerAddress = "network.peer.address"
  static let networkPeerPort = "network.peer.port"
}

extension Span {
  // See: https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans/
  func setOTelClientSpanGRPCAttributes(
    context: ClientContext,
    serverHostname: String,
    networkTransportMethod: String
  ) {
    self.attributes[GRPCTracingKeys.rpcSystem] = "grpc"
    self.attributes[GRPCTracingKeys.serverAddress] = serverHostname
    self.attributes[GRPCTracingKeys.networkTransport] = networkTransportMethod
    self.attributes[GRPCTracingKeys.rpcService] = context.descriptor.service.fullyQualifiedService
    self.attributes[GRPCTracingKeys.rpcMethod] = context.descriptor.method

    // Set server address information
    switch PeerAddress(context.remotePeer) {
    case .ipv4(let address, let port):
      self.attributes[GRPCTracingKeys.networkType] = "ipv4"
      self.attributes[GRPCTracingKeys.networkPeerAddress] = address
      self.attributes[GRPCTracingKeys.networkPeerPort] = port
      self.attributes[GRPCTracingKeys.serverPort] = port

    case .ipv6(let address, let port):
      self.attributes[GRPCTracingKeys.networkType] = "ipv6"
      self.attributes[GRPCTracingKeys.networkPeerAddress] = address
      self.attributes[GRPCTracingKeys.networkPeerPort] = port
      self.attributes[GRPCTracingKeys.serverPort] = port

    case .unixDomainSocket(let path):
      self.attributes[GRPCTracingKeys.networkType] = "unix"
      self.attributes[GRPCTracingKeys.networkPeerAddress] = path

    case .other(let address):
      // We can't nicely format the span attributes to contain the appropriate information here,
      // so include the whole thing as part of the peer address.
      self.attributes[GRPCTracingKeys.networkPeerAddress] = address
    }
  }
}

package enum PeerAddress: Equatable {
  case ipv4(address: String, port: Int?)
  case ipv6(address: String, port: Int?)
  case unixDomainSocket(path: String)
  case other(String)

  package init(_ address: String) {
    // We expect this address to be of one of these formats:
    // - ipv4:<host>:<port> for ipv4 addresses
    // - ipv6:[<host>]:<port> for ipv6 addresses
    // - unix:<uds-pathname> for UNIX domain sockets
    let addressComponents = address.split(separator: ":", omittingEmptySubsequences: false)

    guard addressComponents.count > 1 else {
      // This is some unexpected/unknown format, so we have no way of splitting it up nicely.
      self = .other(address)
      return
    }

    // Check what type the transport is...
    switch addressComponents[0] {
    case "ipv4":
      guard addressComponents.count == 3, let port = Int(addressComponents[2]) else {
        // This is some unexpected/unknown format, so we have no way of splitting it up nicely.
        self = .other(address)
        return
      }
      self = .ipv4(address: String(addressComponents[1]), port: port)

    case "ipv6":
      guard addressComponents.count > 2, let port = Int(addressComponents.last!) else {
        // This is some unexpected/unknown format, so we have no way of splitting it up nicely.
        self = .other(address)
        return
      }
      self = .ipv6(
        address: String(
          addressComponents[1 ..< addressComponents.count - 1].joined(separator: ":")
        ),
        port: port
      )

    case "unix":
      guard addressComponents.count == 2 else {
        // This is some unexpected/unknown format, so we have no way of splitting it up nicely.
        self = .other(address)
        return
      }
      self = .unixDomainSocket(path: String(addressComponents[1]))

    default:
      // This is some unexpected/unknown format, so we have no way of splitting it up nicely.
      self = .other(address)
    }
  }
}
