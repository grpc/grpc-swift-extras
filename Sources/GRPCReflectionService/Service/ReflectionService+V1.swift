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

internal import GRPCCore
internal import SwiftProtobuf

extension ReflectionService {
  struct V1: Grpc_Reflection_V1_ServerReflection.SimpleServiceProtocol {
    private typealias Response = Grpc_Reflection_V1_ServerReflectionResponse
    private typealias ResponsePayload = Response.OneOf_MessageResponse
    private typealias FileDescriptorResponse = Grpc_Reflection_V1_FileDescriptorResponse
    private typealias ExtensionNumberResponse = Grpc_Reflection_V1_ExtensionNumberResponse
    private let registry: ReflectionServiceRegistry

    init(registry: ReflectionServiceRegistry) {
      self.registry = registry
    }
  }
}

extension ReflectionService.V1 {
  private func findFileByFileName(_ fileName: String) throws(RPCError) -> FileDescriptorResponse {
    let data = try self.registry.serialisedFileDescriptorForDependenciesOfFile(named: fileName)
    return .with { $0.fileDescriptorProto = data }
  }

  func serverReflectionInfo(
    request: RPCAsyncSequence<Grpc_Reflection_V1_ServerReflectionRequest, any Swift.Error>,
    response: RPCWriter<Grpc_Reflection_V1_ServerReflectionResponse>,
    context: ServerContext
  ) async throws {
    for try await message in request {
      let payload: ResponsePayload

      switch message.messageRequest {
      case let .fileByFilename(fileName):
        payload = .makeFileDescriptorResponse { () throws(RPCError) -> FileDescriptorResponse in
          try self.findFileByFileName(fileName)
        }

      case .listServices:
        payload = .listServicesResponse(
          .with {
            $0.service = self.registry.serviceNames.map { serviceName in
              .with { $0.name = serviceName }
            }
          }
        )

      case let .fileContainingSymbol(symbolName):
        payload = .makeFileDescriptorResponse { () throws(RPCError) -> FileDescriptorResponse in
          let fileName = try self.registry.fileContainingSymbol(symbolName)
          return try self.findFileByFileName(fileName)
        }

      case let .fileContainingExtension(extensionRequest):
        payload = .makeFileDescriptorResponse { () throws(RPCError) -> FileDescriptorResponse in
          let fileName = try self.registry.fileContainingExtension(
            extendeeName: extensionRequest.containingType,
            fieldNumber: extensionRequest.extensionNumber
          )
          return try self.findFileByFileName(fileName)
        }

      case let .allExtensionNumbersOfType(typeName):
        payload = .makeExtensionNumberResponse { () throws(RPCError) -> ExtensionNumberResponse in
          let fieldNumbers = try self.registry.extensionFieldNumbersOfType(named: typeName)
          return .with {
            $0.extensionNumber = fieldNumbers
            $0.baseTypeName = typeName
          }
        }

      default:
        payload = .errorResponse(
          .with {
            $0.errorCode = Int32(RPCError.Code.unimplemented.rawValue)
            $0.errorMessage = "The request is not implemented."
          }
        )
      }

      try await response.write(Response(request: message, response: payload))
    }
  }
}

extension Grpc_Reflection_V1_ServerReflectionResponse.OneOf_MessageResponse {
  fileprivate init(catching body: () throws(RPCError) -> Self) {
    do {
      self = try body()
    } catch {
      self = .errorResponse(
        .with {
          $0.errorCode = Int32(error.code.rawValue)
          $0.errorMessage = error.message
        }
      )
    }
  }

  fileprivate static func makeFileDescriptorResponse(
    _ body: () throws(RPCError) -> Grpc_Reflection_V1_FileDescriptorResponse
  ) -> Self {
    Self { () throws(RPCError) -> Self in
      return .fileDescriptorResponse(try body())
    }
  }

  fileprivate static func makeExtensionNumberResponse(
    _ body: () throws(RPCError) -> Grpc_Reflection_V1_ExtensionNumberResponse
  ) -> Self {
    Self { () throws(RPCError) -> Self in
      return .allExtensionNumbersResponse(try body())
    }
  }
}

extension Grpc_Reflection_V1_ServerReflectionResponse {
  fileprivate init(
    request: Grpc_Reflection_V1_ServerReflectionRequest,
    response: Self.OneOf_MessageResponse
  ) {
    self = .with {
      $0.validHost = request.host
      $0.originalRequest = request
      $0.messageResponse = response
    }
  }
}
