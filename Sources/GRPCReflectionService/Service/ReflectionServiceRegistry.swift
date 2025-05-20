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
package import GRPCCore
package import SwiftProtobuf

#if canImport(FoundationEssentials)
package import struct FoundationEssentials.Data
#else
package import struct Foundation.Data
#endif

@available(gRPCSwiftExtras 1.0, *)
package struct ReflectionServiceRegistry: Sendable {
  private struct SerializedFileDescriptor: Sendable {
    var bytes: Data
    var dependencyFileNames: [String]
  }

  private struct ExtensionDescriptor: Sendable, Hashable {
    var extendeeTypeName: String
    var fieldNumber: Int32
  }

  private var fileDescriptorDataByFilename: [String: SerializedFileDescriptor]
  private var fileNameBySymbol: [String: String]
  private(set) var serviceNames: [String]

  // Stores the file names for each extension identified by an ExtensionDescriptor object.
  private var fileNameByExtensionDescriptor: [ExtensionDescriptor: String]
  // Stores the field numbers for each type that has extensions.
  private var fieldNumbersByType: [String: [Int32]]

  private mutating func storeSerialized(
    descriptor: Google_Protobuf_FileDescriptorProto
  ) throws(RPCError) {
    let serializedBytes: Data
    do {
      serializedBytes = try descriptor.serializedBytes()
    } catch {
      throw RPCError(
        code: .invalidArgument,
        message: "\(descriptor.name) couldn't be serialized.",
        cause: error
      )
    }

    let protoData = SerializedFileDescriptor(
      bytes: serializedBytes,
      dependencyFileNames: descriptor.dependency
    )

    self.fileDescriptorDataByFilename[descriptor.name] = protoData
  }

  private mutating func storeServices(descriptor: Google_Protobuf_FileDescriptorProto) {
    let serviceNames = descriptor.service.map { descriptor.package + "." + $0.name }
    self.serviceNames.append(contentsOf: serviceNames)
  }

  private mutating func storeSymbolNames(
    descriptor: Google_Protobuf_FileDescriptorProto
  ) {
    for symbol in descriptor.qualifiedSymbolNames {
      self.fileNameBySymbol[symbol] = descriptor.name
    }
  }

  private mutating func storeFieldNumbers(
    descriptor: Google_Protobuf_FileDescriptorProto
  ) {
    for `extension` in descriptor.extension {
      let typeName = String(`extension`.extendee.drop(while: { $0 == "." }))
      let extensionDescriptor = ExtensionDescriptor(
        extendeeTypeName: typeName,
        fieldNumber: `extension`.number
      )

      self.fileNameByExtensionDescriptor[extensionDescriptor] = descriptor.name
      self.fieldNumbersByType[typeName, default: []].append(`extension`.number)
    }
  }

  package init(fileDescriptors: [Google_Protobuf_FileDescriptorProto]) throws(RPCError) {
    self.serviceNames = []
    self.fileDescriptorDataByFilename = [:]
    self.fileNameBySymbol = [:]
    self.fileNameByExtensionDescriptor = [:]
    self.fieldNumbersByType = [:]

    for descriptor in fileDescriptors {
      try self.storeSerialized(descriptor: descriptor)
      self.storeServices(descriptor: descriptor)
      self.storeSymbolNames(descriptor: descriptor)
      self.storeFieldNumbers(descriptor: descriptor)
    }
  }

  package func serialisedFileDescriptorForDependenciesOfFile(
    named fileName: String
  ) throws(RPCError) -> [Data] {
    var toVisit = Deque<String>()
    var visited = Set<String>()
    var serializedBytess: [Data] = []
    toVisit.append(fileName)

    while let currentFileName = toVisit.popFirst() {
      if let protoData = self.fileDescriptorDataByFilename[currentFileName] {
        for dependency in protoData.dependencyFileNames {
          if !visited.contains(dependency) {
            toVisit.append(dependency)
          }
        }

        let serializedBytes = protoData.bytes
        serializedBytess.append(serializedBytes)
      } else {
        throw RPCError(code: .notFound, message: "File not found.")
      }
      visited.insert(currentFileName)
    }
    return serializedBytess
  }

  package func fileContainingSymbol(_ symbolName: String) throws(RPCError) -> String {
    if let fileName = self.fileNameBySymbol[symbolName] {
      return fileName
    } else {
      throw RPCError(code: .notFound, message: "Symbol not found.")
    }
  }

  package func fileContainingExtension(
    extendeeName: String,
    fieldNumber number: Int32
  ) throws(RPCError) -> String {
    let key = ExtensionDescriptor(extendeeTypeName: extendeeName, fieldNumber: number)
    if let fileName = self.fileNameByExtensionDescriptor[key] {
      return fileName
    } else {
      throw RPCError(code: .notFound, message: "Extension not found.")
    }
  }

  // Returns an empty array if the type has no extensions.
  package func extensionFieldNumbersOfType(
    named typeName: String
  ) throws(RPCError) -> [Int32] {
    if let fieldNumbers = self.fieldNumbersByType[typeName] {
      return fieldNumbers
    } else {
      throw RPCError(
        code: .invalidArgument,
        message: "The provided type is invalid."
      )
    }
  }
}

extension Google_Protobuf_FileDescriptorProto {
  fileprivate var qualifiedSymbolNames: [String] {
    var names: [String] = []

    for service in self.service {
      names.append(self.package + "." + service.name)

      for method in service.method {
        names.append(self.package + "." + service.name + "." + method.name)
      }
    }

    for messageType in self.messageType {
      names.append(self.package + "." + messageType.name)
    }

    for enumType in self.enumType {
      names.append(self.package + "." + enumType.name)
    }

    return names
  }
}
