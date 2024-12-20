/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

import Foundation
import GRPCCore
import GRPCInProcessTransport
import GRPCReflectionService
import Testing

@Suite("gRPC Reflection Service Tests")
struct GRPCReflectionServiceTests {
  func withReflectionClient(
    descriptorSetPaths: [String] = Bundle.module.pathsForDescriptorSets,
    execute body: (ReflectionClient) async throws -> Void
  ) async throws {
    let inProcess = InProcessTransport()
    try await withGRPCServer(
      transport: inProcess.server,
      services: [ReflectionService(descriptorSetFilePaths: descriptorSetPaths)]
    ) { server in
      try await withGRPCClient(transport: inProcess.client) { client in
        try await body(ReflectionClient(wrapping: client))
      }
    }
  }

  @Test("List services")
  func listServices() async throws {
    try await self.withReflectionClient { reflection in
      let services = try await reflection.listServices()
      let expected = [
        "grpc.health.v1.Health",
        "grpc.reflection.v1.ServerReflection",
      ]
      #expect(services.sorted() == expected)
    }
  }

  @Test(
    "File by file name",
    arguments: [
      "grpc/reflection/v1/reflection.proto",
      "grpc/health/v1/health.proto",
    ]
  )
  func fileByFileName(fileName: String) async throws {
    try await self.withReflectionClient { reflection in
      let descriptors = try await reflection.fileByFileName(fileName)
      let expected = [fileName]
      #expect(descriptors.map { $0.name } == expected)
    }
  }

  @Test("File by file name (doesn't exist)")
  func testFileByNonExistentFileName() async throws {
    try await self.withReflectionClient { reflection in
      await #expect {
        try await reflection.fileByFileName("nonExistent.proto")
      } throws: { error in
        guard let error = error as? RPCError else { return false }
        #expect(error.code == .notFound)
        #expect(error.message == "File not found.")
        return true
      }
    }
  }

  @Test(
    "File containing symbol",
    arguments: [
      ("grpc/health/v1/health.proto", "grpc.health.v1.Health"),
      ("grpc/health/v1/health.proto", "grpc.health.v1.HealthCheckRequest"),
      ("grpc/reflection/v1/reflection.proto", "grpc.reflection.v1.ServerReflectionRequest"),
      ("grpc/reflection/v1/reflection.proto", "grpc.reflection.v1.ExtensionNumberResponse"),
      ("grpc/reflection/v1/reflection.proto", "grpc.reflection.v1.ErrorResponse"),
    ] as [(String, String)]
  )
  func fileContainingSymbol(fileName: String, symbol: String) async throws {
    try await self.withReflectionClient { reflection in
      let descriptors = try await reflection.fileContainingSymbol(symbol)
      let expected = [fileName]
      #expect(descriptors.map { $0.name } == expected)
    }
  }

  @Test("File containing symbol includes dependencies")
  func fileContainingSymbolWithDependency() async throws {
    try await self.withReflectionClient { reflection in
      let descriptors = try await reflection.fileContainingSymbol(".MessageWithDependency")
      let expected = ["message_with_dependency.proto", "google/protobuf/empty.proto"]
      #expect(descriptors.map { $0.name } == expected)
    }
  }

  @Test("File containing symbol (doesn't exist)")
  func testFileContainingNonExistentSymbol() async throws {
    try await self.withReflectionClient { reflection in
      await #expect {
        try await reflection.fileContainingSymbol("nonExistentSymbol")
      } throws: { error in
        guard let error = error as? RPCError else { return false }
        #expect(error.code == .notFound)
        #expect(error.message == "Symbol not found.")
        return true
      }
    }
  }

  @Test("File containing extension")
  func testFileContainingExtension() async throws {
    try await self.withReflectionClient { reflection in
      let descriptors = try await reflection.fileContainingExtension(number: 100, in: "BaseMessage")
      let expected = ["base_message.proto"]
      #expect(descriptors.map { $0.name } == expected)
    }
  }

  @Test("File containing extension (doesn't exist)")
  func testFileContainingNonExistentExtension() async throws {
    try await self.withReflectionClient { reflection in
      await #expect {
        try await reflection.fileContainingExtension(number: 42, in: "NonExistent")
      } throws: { error in
        guard let error = error as? RPCError else { return false }
        #expect(error.code == .notFound)
        #expect(error.message == "Extension not found.")
        return true
      }
    }
  }
}

extension Bundle {
  func path(forDescriptorSet name: String) -> String? {
    self.path(forResource: name, ofType: "pb", inDirectory: "DescriptorSets")
  }

  var pathsForDescriptorSets: [String] {
    self.paths(forResourcesOfType: "pb", inDirectory: "DescriptorSets")
  }
}
