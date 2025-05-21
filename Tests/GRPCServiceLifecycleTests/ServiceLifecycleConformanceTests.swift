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

import GRPCCore
import GRPCInProcessTransport
import GRPCServiceLifecycle
import ServiceLifecycleTestKit
import Testing

@Suite("gRPC ServiceLifecycle/Service conformance tests")
struct ServiceLifecycleConformanceTests {
  @Test("Client respects graceful shutdown")
  @available(gRPCSwiftExtras 2.0, *)
  func clientGracefulShutdown() async throws {
    let inProcess = InProcessTransport()
    try await testGracefulShutdown { trigger in
      try await withThrowingDiscardingTaskGroup { group in
        group.addTask {
          let client = GRPCClient(transport: inProcess.client)
          try await client.run()
        }

        group.addTask {
          try await Task.sleep(for: .milliseconds(10))
          trigger.triggerGracefulShutdown()
        }
      }
    }
  }

  @Test("Server respects graceful shutdown")
  @available(gRPCSwiftExtras 2.0, *)
  func serverGracefulShutdown() async throws {
    let inProcess = InProcessTransport()
    try await testGracefulShutdown { trigger in
      try await withThrowingDiscardingTaskGroup { group in
        group.addTask {
          let server = GRPCServer(transport: inProcess.server, services: [])
          try await server.run()
        }

        group.addTask {
          try await Task.sleep(for: .milliseconds(10))
          trigger.triggerGracefulShutdown()
        }
      }
    }
  }
}
