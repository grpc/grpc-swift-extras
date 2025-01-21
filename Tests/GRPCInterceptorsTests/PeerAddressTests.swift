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

import GRPCInterceptors
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

  @Test("Unrecognised addresses are correctly parsed")
  func testOther() {
    let address = PeerAddress("in-process:1234")
    #expect(address == .other("in-process:1234"))
  }
}
