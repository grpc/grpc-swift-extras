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

public import GRPCCore
public import ServiceLifecycle

// A `@retroactive` conformance here is okay because this project is also owned by the owners of
// `GRPCCore`, and thus, the owners of `GRPCClient`. A conflicting conformance won't be added.
@available(gRPCSwiftExtras 1.0, *)
@available(*, deprecated, message: "See https://forums.swift.org/t/80177")
extension GRPCClient: @retroactive Service {
  public func run() async throws {
    try await withGracefulShutdownHandler {
      try await self.runConnections()
    } onGracefulShutdown: {
      self.beginGracefulShutdown()
    }
  }
}
