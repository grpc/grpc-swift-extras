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

enum GRPCTracingKeys {
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

  fileprivate static let requestMetadataPrefix = "rpc.grpc.request.metadata."
  fileprivate static let responseMetadataPrefix = "rpc.grpc.response.metadata."
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
      self.attributes[GRPCTracingKeys.networkPeerAddress] = path

    case .none:
      // We don't recognise this address format, so don't populate any fields.
      ()
    }
  }

  func setOTelServerSpanGRPCAttributes(
    context: ServerContext,
    serverHostname: String,
    networkTransportMethod: String
  ) {
    self.attributes[GRPCTracingKeys.rpcSystem] = "grpc"
    self.attributes[GRPCTracingKeys.serverAddress] = serverHostname
    self.attributes[GRPCTracingKeys.networkTransport] = networkTransportMethod
    self.attributes[GRPCTracingKeys.rpcService] = context.descriptor.service.fullyQualifiedService
    self.attributes[GRPCTracingKeys.rpcMethod] = context.descriptor.method

    // Set server address information
    switch PeerAddress(context.localPeer) {
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
      self.attributes[GRPCTracingKeys.networkPeerAddress] = path

    case .none:
      // We don't recognise this address format, so don't populate any fields.
      ()
    }

    // Set client address information
    switch PeerAddress(context.remotePeer) {
    case .ipv4(let address, let port):
      self.attributes[GRPCTracingKeys.clientAddress] = address
      self.attributes[GRPCTracingKeys.clientPort] = port

    case .ipv6(let address, let port):
      self.attributes[GRPCTracingKeys.clientAddress] = address
      self.attributes[GRPCTracingKeys.clientPort] = port

    case .unixDomainSocket(let path):
      self.attributes[GRPCTracingKeys.clientAddress] = path

    case .none:
      // We don't recognise this address format, so don't populate any fields.
      ()
    }
  }

  func setMetadataStringAttributesAsRequestSpanAttributes(_ metadata: Metadata) {
    self.setMetadataStringAttributesAsSpanAttributes(
      metadata,
      prefix: GRPCTracingKeys.requestMetadataPrefix
    )
  }

  func setMetadataStringAttributesAsResponseSpanAttributes(_ metadata: Metadata) {
    self.setMetadataStringAttributesAsSpanAttributes(
      metadata,
      prefix: GRPCTracingKeys.responseMetadataPrefix
    )
  }

  private func setMetadataStringAttributesAsSpanAttributes(_ metadata: Metadata, prefix: String) {
    for (key, value) in metadata {
      switch value {
      case .string(let stringValue):
        let spanKey = prefix + key.lowercased()

        if let existingValue = self.attributes[spanKey]?.toSpanAttribute() {
          switch existingValue {
          case .stringArray(var strings):
            strings.append(stringValue)
            self.attributes[spanKey] = strings

          case .string(let oldString):
            self.attributes[spanKey] = [oldString, stringValue]

          default:
            fatalError("This should never happen: only strings should be iterated here.")
          }
        } else {
          self.attributes[spanKey] = stringValue
        }

      case .binary:
        ()
      }
    }
  }
}

package enum PeerAddress: Equatable {
  case ipv4(address: String, port: Int?)
  case ipv6(address: String, port: Int?)
  case unixDomainSocket(path: String)

  package init?(_ address: String) {
    // We expect this address to be of one of these formats:
    // - ipv4:<host>:<port> for ipv4 addresses
    // - ipv6:[<host>]:<port> for ipv6 addresses
    // - unix:<uds-pathname> for UNIX domain sockets

    // First get the first component so that we know what type of address we're dealing with
    let addressComponents = address.split(separator: ":", maxSplits: 1)

    guard addressComponents.count > 1 else {
      // This is some unexpected/unknown format
      return nil
    }

    // Check what type the transport is...
    switch addressComponents[0] {
    case "ipv4":
      let ipv4AddressComponents = addressComponents[1].split(separator: ":")
      if ipv4AddressComponents.count == 2, let port = Int(ipv4AddressComponents[1]) {
        self = .ipv4(address: String(ipv4AddressComponents[0]), port: port)
      } else {
        return nil
      }

    case "ipv6":
      if addressComponents[1].first == "[" {
        // At this point, we are looking at an address with format: [<address>]:<port>
        // We drop the first character ('[') and split by ']:' to keep two components: the address
        // and the port.
        let ipv6AddressComponents = addressComponents[1].dropFirst().split(separator: "]:")
        if ipv6AddressComponents.count == 2, let port = Int(ipv6AddressComponents[1]) {
          self = .ipv6(address: String(ipv6AddressComponents[0]), port: port)
        } else {
          return nil
        }
      } else {
        return nil
      }

    case "unix":
      // Whatever comes after "unix:" is the <pathname>
      self = .unixDomainSocket(path: String(addressComponents[1]))

    default:
      // This is some unexpected/unknown format
      return nil
    }
  }
}
