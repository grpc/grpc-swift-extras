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

private import DequeModule
public import GRPCCore
public import SwiftProtobuf

#if canImport(FoundationEssentials)
public import struct FoundationEssentials.URL
public import struct FoundationEssentials.Data
#else
public import struct Foundation.URL
public import struct Foundation.Data
#endif

/// Implements the gRPC Reflection service (v1).
///
/// The reflection service is a regular gRPC service providing information about other
/// services.
///
/// The service will offer information to clients about any registered services. You can register
/// a service by providing its descriptor set to the service.
@available(gRPCSwiftExtras 2.0, *)
public struct ReflectionService: Sendable {
  private let service: ReflectionService.V1

  /// Create a new instance of the reflection service from a list of descriptor set file URLs.
  ///
  /// - Parameter fileURLs: A list of file URLs containing serialized descriptor sets.
  public init(
    descriptorSetFileURLs fileURLs: [URL]
  ) throws {
    let fileDescriptorProtos = try Self.readDescriptorSets(atURLs: fileURLs)
    try self.init(fileDescriptors: fileDescriptorProtos)
  }

  /// Create a new instance of the reflection service from a list of descriptor set file paths.
  ///
  /// - Parameter filePaths: A list of file paths containing serialized descriptor sets.
  public init(
    descriptorSetFilePaths filePaths: [String]
  ) throws {
    let fileDescriptorProtos = try Self.readDescriptorSets(atPaths: filePaths)
    try self.init(fileDescriptors: fileDescriptorProtos)
  }

  /// Create a new instance of the reflection service from a list of file descriptor messages.
  ///
  /// - Parameter fileDescriptors: A list of file descriptors of the services to register.
  public init(
    fileDescriptors: [Google_Protobuf_FileDescriptorProto]
  ) throws {
    let registry = try ReflectionServiceRegistry(fileDescriptors: fileDescriptors)
    self.service = ReflectionService.V1(registry: registry)
  }
}

@available(gRPCSwiftExtras 2.0, *)
extension ReflectionService: RegistrableRPCService {
  public func registerMethods<Transport>(
    with router: inout RPCRouter<Transport>
  ) where Transport: ServerTransport {
    self.service.registerMethods(with: &router)
  }
}

@available(gRPCSwiftExtras 2.0, *)
extension ReflectionService {
  static func readSerializedFileDescriptorProto(
    atPath path: String
  ) throws -> Google_Protobuf_FileDescriptorProto {
    let fileURL: URL
    #if canImport(Darwin)
    fileURL = URL(filePath: path, directoryHint: .notDirectory)
    #else
    fileURL = URL(fileURLWithPath: path)
    #endif

    let binaryData = try Data(contentsOf: fileURL)
    guard let serializedData = Data(base64Encoded: binaryData) else {
      throw RPCError(
        code: .invalidArgument,
        message:
          """
          The \(path) file contents could not be transformed \
          into serialized data representing a file descriptor proto.
          """
      )
    }

    return try Google_Protobuf_FileDescriptorProto(serializedBytes: serializedData)
  }

  static func readSerializedFileDescriptorProtos(
    atPaths paths: [String]
  ) throws -> [Google_Protobuf_FileDescriptorProto] {
    var fileDescriptorProtos = [Google_Protobuf_FileDescriptorProto]()
    fileDescriptorProtos.reserveCapacity(paths.count)
    for path in paths {
      try fileDescriptorProtos.append(Self.readSerializedFileDescriptorProto(atPath: path))
    }
    return fileDescriptorProtos
  }

  static func readDescriptorSet(
    atURL fileURL: URL
  ) throws -> [Google_Protobuf_FileDescriptorProto] {
    let binaryData = try Data(contentsOf: fileURL)
    let descriptorSet = try Google_Protobuf_FileDescriptorSet(serializedBytes: binaryData)
    return descriptorSet.file
  }

  static func readDescriptorSet(
    atPath path: String
  ) throws -> [Google_Protobuf_FileDescriptorProto] {
    let fileURL: URL
    #if canImport(Darwin)
    fileURL = URL(filePath: path, directoryHint: .notDirectory)
    #else
    fileURL = URL(fileURLWithPath: path)
    #endif
    return try Self.readDescriptorSet(atURL: fileURL)
  }

  static func readDescriptorSets(
    atURLs fileURLs: [URL]
  ) throws -> [Google_Protobuf_FileDescriptorProto] {
    var fileDescriptorProtos = [Google_Protobuf_FileDescriptorProto]()
    fileDescriptorProtos.reserveCapacity(fileURLs.count)
    for url in fileURLs {
      try fileDescriptorProtos.append(contentsOf: Self.readDescriptorSet(atURL: url))
    }
    return fileDescriptorProtos
  }

  static func readDescriptorSets(
    atPaths paths: [String]
  ) throws -> [Google_Protobuf_FileDescriptorProto] {
    var fileDescriptorProtos = [Google_Protobuf_FileDescriptorProto]()
    fileDescriptorProtos.reserveCapacity(paths.count)
    for path in paths {
      try fileDescriptorProtos.append(contentsOf: Self.readDescriptorSet(atPath: path))
    }
    return fileDescriptorProtos
  }
}
