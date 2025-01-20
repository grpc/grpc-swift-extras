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

@dynamicMemberLookup
package struct RPCAttributes: SpanAttributeNamespace {
  var attributes: SpanAttributes

  init(attributes: SpanAttributes) {
    self.attributes = attributes
  }

  struct NestedSpanAttributes: NestedSpanAttributesProtocol {
    init() {}

    var system: Key<String> { "rpc.system" }
    var method: Key<String> { "rpc.method" }
    var service: Key<String> { "rpc.service" }
    var messageID: Key<Int> { "rpc.message.id" }
    var messageType: Key<String> { "rpc.message.type" }
    var grpcStatusCode: Key<Int> { "rpc.grpc.status_code" }

    var serverAddress: Key<String> { "server.address" }
    var serverPort: Key<Int> { "server.port" }

    var clientAddress: Key<String> { "client.address" }
    var clientPort: Key<Int> { "client.port" }

    var networkTransport: Key<String> { "network.transport" }
    var networkType: Key<String> { "network.type" }
    var networkPeerAddress: Key<String> { "network.peer.address" }
    var networkPeerPort: Key<Int> { "network.peer.port" }
  }
}

extension SpanAttributes {
  /// Semantic conventions for RPC spans.
  package var rpc: RPCAttributes {
    get {
      .init(attributes: self)
    }
    set {
      self = newValue.attributes
    }
  }
}

extension Span {
  // See: https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans/
  func setOTelClientSpanGRPCAttributes(
    context: ClientContext,
    serverHostname: String,
    networkTransportMethod: String
  ) {
    self.attributes.rpc.system = "grpc"
    self.attributes.rpc.serverAddress = serverHostname
    self.attributes.rpc.networkTransport = networkTransportMethod
    self.attributes.rpc.service = context.descriptor.service.fullyQualifiedService
    self.attributes.rpc.method = context.descriptor.method

    // Set server address information
    switch PeerAddress(context.remotePeer) {
    case .ipv4(let address, let port):
      self.attributes.rpc.networkType = "ipv4"
      self.attributes.rpc.networkPeerAddress = address
      self.attributes.rpc.networkPeerPort = port
      self.attributes.rpc.serverPort = port

    case .ipv6(let address, let port):
      self.attributes.rpc.networkType = "ipv6"
      self.attributes.rpc.networkPeerAddress = address
      self.attributes.rpc.networkPeerPort = port
      self.attributes.rpc.serverPort = port

    case .unixDomainSocket(let path):
      self.attributes.rpc.networkType = "unix"
      self.attributes.rpc.networkPeerAddress = path

    case .other(let address):
      // We can't nicely format the span attributes to contain the appropriate information here,
      // so include the whole thing as part of the server address.
      self.attributes.rpc.serverAddress = address
    }
  }

  func setOTelServerSpanGRPCAttributes(
    context: ServerContext,
    serverHostname: String,
    networkTransportMethod: String
  ) {
    self.attributes.rpc.system = "grpc"
    self.attributes.rpc.serverAddress = serverHostname
    self.attributes.rpc.networkTransport = networkTransportMethod
    self.attributes.rpc.service = context.descriptor.service.fullyQualifiedService
    self.attributes.rpc.method = context.descriptor.method

    // Set server address information
    switch PeerAddress(context.localPeer) {
    case .ipv4(let address, let port):
      self.attributes.rpc.networkType = "ipv4"
      self.attributes.rpc.networkPeerAddress = address
      self.attributes.rpc.networkPeerPort = port
      self.attributes.rpc.serverPort = port

    case .ipv6(let address, let port):
      self.attributes.rpc.networkType = "ipv6"
      self.attributes.rpc.networkPeerAddress = address
      self.attributes.rpc.networkPeerPort = port
      self.attributes.rpc.serverPort = port

    case .unixDomainSocket(let path):
      self.attributes.rpc.networkType = "unix"
      self.attributes.rpc.networkPeerAddress = path

    case .other(let address):
      // We can't nicely format the span attributes to contain the appropriate information here,
      // so include the whole thing as part of the server address.
      self.attributes.rpc.serverAddress = address
    }

    switch PeerAddress(context.remotePeer) {
    case .ipv4(let address, let port):
      self.attributes.rpc.clientAddress = address
      self.attributes.rpc.clientPort = port

    case .ipv6(let address, let port):
      self.attributes.rpc.clientAddress = address
      self.attributes.rpc.clientPort = port

    case .unixDomainSocket(let path):
      self.attributes.rpc.clientAddress = path

    case .other(let address):
      self.attributes.rpc.clientAddress = address
    }
  }
}

private enum PeerAddress {
  case ipv4(address: String, port: Int?)
  case ipv6(address: String, port: Int?)
  case unixDomainSocket(path: String)
  case other(String)

  init(_ address: String) {
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
