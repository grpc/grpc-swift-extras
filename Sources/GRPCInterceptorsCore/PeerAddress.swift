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
