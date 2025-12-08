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
