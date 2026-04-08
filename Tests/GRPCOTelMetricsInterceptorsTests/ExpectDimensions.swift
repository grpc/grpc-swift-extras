//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Temporal SDK open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift Temporal SDK project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Temporal SDK project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import Testing

func expectDimensions(
  _ dimensions: [(String, String)],
  rpcSystem: String = "grpc",
  serverAddress: String = "test-server",
  networkTransport: String = "tcp",
  rpcService: String = "test-service",
  rpcMethod: String = "test-method",
  expectAdditional additionalDimensions: [(String, String)] = [],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  struct Tuple: Hashable, CustomStringConvertible {
    let first: String
    let second: String

    var description: String {
      "(\(first), \(second))"
    }
  }

  let expectedDimensions =
    [
      ("rpc.system", rpcSystem),
      ("server.address", serverAddress),
      ("network.transport", networkTransport),
      ("rpc.service", rpcService),
      ("rpc.method", rpcMethod),
    ] + additionalDimensions

  let expectedSet: Set<Tuple> = expectedDimensions.reduce(into: []) { partialResult, element in
    partialResult.insert(Tuple(first: element.0, second: element.1))
  }
  let dimensionsSet: Set<Tuple> = dimensions.reduce(into: []) { partialResult, element in
    partialResult.insert(Tuple(first: element.0, second: element.1))
  }

  #expect(dimensionsSet == expectedSet, sourceLocation: sourceLocation)
}
