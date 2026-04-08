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
internal import GRPCInterceptorsCore
internal import Tracing

@available(gRPCSwiftExtras 2.0, *)
extension Span {
  // See: https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans/
  func setOTelClientSpanGRPCAttributes(
    context: ClientContext,
    serverHostname: String,
    networkTransportMethod: String
  ) {
    self.attributes[GRPCOTelAttributeKeys.rpcSystem] = "grpc"
    self.attributes[GRPCOTelAttributeKeys.serverAddress] = serverHostname
    self.attributes[GRPCOTelAttributeKeys.networkTransport] = networkTransportMethod
    self.attributes[GRPCOTelAttributeKeys.rpcService] = context.descriptor.service.fullyQualifiedService
    self.attributes[GRPCOTelAttributeKeys.rpcMethod] = context.descriptor.method

    // Set server address information
    switch PeerAddress(context.remotePeer) {
    case .ipv4(let address, let port):
      self.attributes[GRPCOTelAttributeKeys.networkType] = "ipv4"
      self.attributes[GRPCOTelAttributeKeys.networkPeerAddress] = address
      self.attributes[GRPCOTelAttributeKeys.networkPeerPort] = port
      self.attributes[GRPCOTelAttributeKeys.serverPort] = port

    case .ipv6(let address, let port):
      self.attributes[GRPCOTelAttributeKeys.networkType] = "ipv6"
      self.attributes[GRPCOTelAttributeKeys.networkPeerAddress] = address
      self.attributes[GRPCOTelAttributeKeys.networkPeerPort] = port
      self.attributes[GRPCOTelAttributeKeys.serverPort] = port

    case .unixDomainSocket(let path):
      self.attributes[GRPCOTelAttributeKeys.networkPeerAddress] = path

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
    self.attributes[GRPCOTelAttributeKeys.rpcSystem] = "grpc"
    self.attributes[GRPCOTelAttributeKeys.serverAddress] = serverHostname
    self.attributes[GRPCOTelAttributeKeys.networkTransport] = networkTransportMethod
    self.attributes[GRPCOTelAttributeKeys.rpcService] = context.descriptor.service.fullyQualifiedService
    self.attributes[GRPCOTelAttributeKeys.rpcMethod] = context.descriptor.method

    // Set server address information
    switch PeerAddress(context.localPeer) {
    case .ipv4(let address, let port):
      self.attributes[GRPCOTelAttributeKeys.networkType] = "ipv4"
      self.attributes[GRPCOTelAttributeKeys.networkPeerAddress] = address
      self.attributes[GRPCOTelAttributeKeys.networkPeerPort] = port
      self.attributes[GRPCOTelAttributeKeys.serverPort] = port

    case .ipv6(let address, let port):
      self.attributes[GRPCOTelAttributeKeys.networkType] = "ipv6"
      self.attributes[GRPCOTelAttributeKeys.networkPeerAddress] = address
      self.attributes[GRPCOTelAttributeKeys.networkPeerPort] = port
      self.attributes[GRPCOTelAttributeKeys.serverPort] = port

    case .unixDomainSocket(let path):
      self.attributes[GRPCOTelAttributeKeys.networkPeerAddress] = path

    case .none:
      // We don't recognise this address format, so don't populate any fields.
      ()
    }

    // Set client address information
    switch PeerAddress(context.remotePeer) {
    case .ipv4(let address, let port):
      self.attributes[GRPCOTelAttributeKeys.clientAddress] = address
      self.attributes[GRPCOTelAttributeKeys.clientPort] = port

    case .ipv6(let address, let port):
      self.attributes[GRPCOTelAttributeKeys.clientAddress] = address
      self.attributes[GRPCOTelAttributeKeys.clientPort] = port

    case .unixDomainSocket(let path):
      self.attributes[GRPCOTelAttributeKeys.clientAddress] = path

    case .none:
      // We don't recognise this address format, so don't populate any fields.
      ()
    }
  }

  func setMetadataStringAttributesAsRequestSpanAttributes(_ metadata: Metadata) {
    self.setMetadataStringAttributesAsSpanAttributes(
      metadata,
      prefix: GRPCOTelAttributeKeys.requestMetadataPrefix
    )
  }

  func setMetadataStringAttributesAsResponseSpanAttributes(_ metadata: Metadata) {
    self.setMetadataStringAttributesAsSpanAttributes(
      metadata,
      prefix: GRPCOTelAttributeKeys.responseMetadataPrefix
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
            ()
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
    let addressUTF8View = address.utf8

    // First get the first component so that we know what type of address we're dealing with
    let firstColonIndex = addressUTF8View.firstIndex(of: UInt8(ascii: ":"))

    guard let firstColonIndex else {
      // This is some unexpected/unknown format
      return nil
    }

    let addressType = addressUTF8View[..<firstColonIndex]

    var addressWithoutType = addressUTF8View[firstColonIndex...]
    addressWithoutType.removeFirst()

    // Check what type the transport is...
    if addressType.elementsEqual("ipv4".utf8) {
      guard let addressColon = addressWithoutType.firstIndex(of: UInt8(ascii: ":")) else {
        // This is some unexpected/unknown format
        return nil
      }

      let hostComponent = addressWithoutType[..<addressColon]
      var portComponent = addressWithoutType[addressColon...]
      portComponent.removeFirst()

      if let host = String(hostComponent), let port = Int(ipAddressPortStringBytes: portComponent) {
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
      portComponent.removeFirst()

      if let firstBracket = hostComponent.popFirst(), let lastBracket = hostComponent.popLast(),
        firstBracket == UInt8(ascii: "["), lastBracket == UInt8(ascii: "]"),
        let host = String(hostComponent), let port = Int(ipAddressPortStringBytes: portComponent)
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
  package init?(ipAddressPortStringBytes: some Collection<UInt8>) {
    guard (1 ... 5).contains(ipAddressPortStringBytes.count) else {
      // Valid IP port values go up to 2^16-1 (65535), which is 5 digits long.
      // If the string we get is over 5 characters, we know for sure that this is an invalid port.
      // If it's empty, we also know it's invalid as we need at least one digit.
      return nil
    }

    var value = 0
    for utf8Char in ipAddressPortStringBytes {
      value &*= 10
      guard (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(utf8Char) else {
        // non-digit character
        return nil
      }
      value &+= Int(utf8Char &- UInt8(ascii: "0"))
    }

    guard value <= Int(UInt16.max) else {
      // Valid IP port values go up to 2^16-1.
      // If a number greater than this was given, it can't be a valid port.
      return nil
    }

    self = value
  }
}
