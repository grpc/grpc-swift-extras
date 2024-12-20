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

import GRPCCore
import GRPCReflectionService
import SwiftProtobuf

struct ReflectionClient: Sendable {
  private typealias Request = Grpc_Reflection_V1_ServerReflectionRequest
  private let stub: Grpc_Reflection_V1_ServerReflection.Client

  init(wrapping client: GRPCClient) {
    self.stub = Grpc_Reflection_V1_ServerReflection.Client(wrapping: client)
  }

  func listServices() async throws -> [String] {
    try await self.stub.serverReflectionInfo { requestStream in
      // 'listServices' must be set, but its contents are ignored.
      let request = Self.Request.with { $0.listServices = "" }
      try await requestStream.write(request)
    } onResponse: { response in
      for try await message in response.messages {
        switch message.messageResponse {
        case .listServicesResponse(let response):
          return response.service.map { $0.name }
        default:
          continue
        }
      }
      throw RPCError(code: .internalError, message: "No list services response.")
    }
  }

  func fileByFileName(_ name: String) async throws -> [Google_Protobuf_FileDescriptorProto] {
    try await self.fileDescriptorsResponse(forRequest: .with { $0.fileByFilename = name })
  }

  func fileContainingSymbol(_ name: String) async throws -> [Google_Protobuf_FileDescriptorProto] {
    try await self.fileDescriptorsResponse(forRequest: .with { $0.fileContainingSymbol = name })
  }

  func fileContainingExtension(
    number: Int32,
    in containingType: String
  ) async throws -> [Google_Protobuf_FileDescriptorProto] {
    try await self.fileDescriptorsResponse(
      forRequest: .with {
        $0.fileContainingExtension = .with {
          $0.containingType = containingType
          $0.extensionNumber = number
        }
      }
    )
  }

  private func fileDescriptorsResponse(
    forRequest request: Grpc_Reflection_V1_ServerReflectionRequest
  ) async throws -> [Google_Protobuf_FileDescriptorProto] {
    try await self.stub.serverReflectionInfo { requestStream in
      try await requestStream.write(request)
    } onResponse: { response in
      for try await message in response.messages {
        switch message.messageResponse {
        case .fileDescriptorResponse(let response):
          return try response.fileDescriptorProto.map {
            try Google_Protobuf_FileDescriptorProto(serializedBytes: $0)
          }

        case .errorResponse(let response):
          let code = Status.Code(rawValue: Int(response.errorCode))
          throw RPCError(
            code: code.flatMap { RPCError.Code($0) } ?? .unknown,
            message: response.errorMessage
          )

        default:
          continue
        }
      }

      throw RPCError(code: .internalError, message: "No list services response.")
    }
  }

}
