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

import GRPCOTelTracingInterceptors
import Testing

@Suite("PeerAddress tests")
struct PeerAddressTests {
  @Test("IPv4 addresses are correctly parsed")
  func testIPv4() {
    let address = PeerAddress("ipv4:10.1.2.80:567")
    #expect(address == .ipv4(address: "10.1.2.80", port: 567))
  }

  @Test("IPv6 addresses are correctly parsed")
  func testIPv6() {
    let address = PeerAddress("ipv6:[2001::130F:::09C0:876A:130B]:1234")
    #expect(address == .ipv6(address: "2001::130F:::09C0:876A:130B", port: 1234))
  }

  @Test("Unix domain sockets are correctly parsed")
  func testUDS() {
    let address = PeerAddress("unix:some-path")
    #expect(address == .unixDomainSocket(path: "some-path"))
  }

  @Test(
    "Unrecognised addresses return nil",
    arguments: [
      "",
      "unknown",
      "in-process:1234",
      "ipv4:",
      "ipv4:1234",
      "ipv6:",
      "ipv6:123:456:789:123",
      "ipv6:123:456:789]:123",
      "ipv6:123:456:789]",
      "unix",
    ]
  )
  func testOther(address: String) {
    let address = PeerAddress(address)
    #expect(address == nil)
  }

  @Test(
    "Int.init(utf8View:)",
    arguments: [
      ("1", 1),
      ("21", 21),
      ("321", 321),
      ("4321", 4321),
      ("54321", 54321),
      ("65536", nil),  // Invalid: over 65535 IP port limit
      ("654321", nil),  // Invalid: over 5 digits
      ("abc", nil),  // Invalid: no digits
      ("a123", nil),  // Invalid: mixed digits and characters outside the valid ascii range for digits
      ("123a", nil),  // Invalid: mixed digits and characters outside the valid ascii range for digits
      ("(123", nil),  // Invalid: mixed digits and characters outside the valid ascii range for digits
      ("123(", nil),  // Invalid: mixed digits and characters outside the valid ascii range for digits
      ("", nil),  // Invalid: empty string
    ]
  )
  func testIntInitFromUTF8View(string: String, expectedInt: Int?) async throws {
    #expect(expectedInt == Int(ipAddressPortStringBytes: string.utf8))
  }
}
