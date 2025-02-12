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
    let addressUTF8View = address.utf8

    // First get the first component so that we know what type of address we're dealing with
    let firstColonIndex = addressUTF8View.firstIndex(of: UInt8(ascii: ":"))

    guard let firstColonIndex else {
      // This is some unexpected/unknown format
      return nil
    }

    let addressType = addressUTF8View[..<firstColonIndex]

    var addressWithoutType = addressUTF8View[firstColonIndex...]
    _ = addressWithoutType.popFirst()

    // Check what type the transport is...
    if addressType.elementsEqual("ipv4".utf8) {
      guard let addressColon = addressWithoutType.firstIndex(of: UInt8(ascii: ":")) else {
        // This is some unexpected/unknown format
        return nil
      }

      let hostComponent = addressWithoutType[..<addressColon]
      var portComponent = addressWithoutType[addressColon...]
      _ = portComponent.popFirst()

      if let host = String(hostComponent), let port = Int(utf8View: portComponent) {
        self = .ipv4(address: host, port: port)
      } else {
        return nil
      }
    } else if addressType.elementsEqual("ipv6".utf8) {
      guard let lastColonIndex = addressWithoutType.lastIndex(of: UInt8(ascii: ":")) else {
        // This is some unexpected/unknown format
        return nil
      }

      var hostComponent = addressWithoutType[..<lastColonIndex]
      var portComponent = addressWithoutType[lastColonIndex...]
      _ = portComponent.popFirst()

      if let firstBracket = hostComponent.popFirst(), let lastBracket = hostComponent.popLast(),
        firstBracket == UInt8(ascii: "["), lastBracket == UInt8(ascii: "]"),
        let host = String(hostComponent), let port = Int(utf8View: portComponent)
      {
        self = .ipv6(address: host, port: port)
      } else {
        // This is some unexpected/unknown format
        return nil
      }
    } else if addressType.elementsEqual("unix".utf8) {
      // Whatever comes after "unix:" is the <pathname>
      self = .unixDomainSocket(path: String(addressWithoutType) ?? "")
    } else {
      // This is some unexpected/unknown format
      return nil
    }
  }
}

extension Int {
  package init?(utf8View: Substring.UTF8View.SubSequence) {
    var value = 0
    for utf8Element in utf8View {
      value &*= 10
      let elementValue = Int(utf8Element - 48)  // ASCII code for 0 is 48
      guard elementValue >= 0, elementValue <= 9 else {
        // non-digit character
        return nil
      }
      value &+= elementValue
    }
    self = value
  }
}
