//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Temporal SDK open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift Temporal SDK project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Temporal SDK project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

struct OTelMetricsInterceptorTestCaseValues {
  let remotePeerAddress: String
  let localPeerAddress: String
  let expectedDimensions: [(String, String)]

  init(addressType: OTelMetricsInterceptorTestAddressType) {
    switch addressType {
    case .ipv4:
      self.remotePeerAddress = "ipv4:10.1.2.80:567"
      self.localPeerAddress = "ipv4:10.1.2.80:123"
      self.expectedDimensions = [
        ("network.peer.address", "10.1.2.80"),
        ("network.peer.port", "567"),
        ("server.port", "567"),
        ("network.type", "ipv4"),
      ]
    case .ipv6:
      self.remotePeerAddress = "ipv6:[2001::130F:::09C0:876A:130B]:1234"
      self.localPeerAddress = "ipv6:[ff06:0:0:0:0:0:0:c3]:5678"
      self.expectedDimensions = [
        ("network.peer.address", "2001::130F:::09C0:876A:130B"),
        ("network.peer.port", "1234"),
        ("server.port", "1234"),
        ("network.type", "ipv6"),
      ]
    case .uds:
      self.remotePeerAddress = "unix:some-path"
      self.localPeerAddress = "unix:some-path"
      self.expectedDimensions = [
        ("network.peer.address", "some-path")
      ]
    }
  }
}
