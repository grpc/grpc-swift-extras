// swift-tools-version: 6.0
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

import PackageDescription

let products: [Product] = [
  .library(
    name: "GRPCHealthService",
    targets: ["GRPCHealthService"]
  ),
  .library(
    name: "GRPCReflectionService",
    targets: ["GRPCReflectionService"]
  ),
  .library(
    name: "GRPCOTelTracingInterceptors",
    targets: ["GRPCOTelTracingInterceptors"]
  ),
  .library(
    name: "GRPCServiceLifecycle",
    targets: ["GRPCServiceLifecycle"]
  ),
  .library(
    name: "GRPCInteropTests",
    targets: ["GRPCInteropTests"]
  ),
]

let dependencies: [Package.Dependency] = [
  .package(
    url: "https://github.com/grpc/grpc-swift-2.git",
    from: "2.0.0"
  ),
  .package(
    url: "https://github.com/grpc/grpc-swift-protobuf.git",
    from: "2.0.0"
  ),
  .package(
    url: "https://github.com/apple/swift-protobuf.git",
    from: "1.28.1"
  ),
  .package(
    url: "https://github.com/apple/swift-distributed-tracing.git",
    from: "1.1.2"
  ),
  .package(
    url: "https://github.com/swift-server/swift-service-lifecycle.git",
    from: "2.8.0"
  ),
]

// -------------------------------------------------------------------------------------------------

// This adds some build settings which allow us to map "@available(gRPCSwiftExtras 2.x, *)" to
// the appropriate OS platforms.
let nextMinorVersion = 1
let availabilitySettings: [SwiftSetting] = (0 ... nextMinorVersion).map { minor in
  let name = "gRPCSwiftExtras"
  let version = "2.\(minor)"
  let platforms = "macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"
  let setting = "AvailabilityMacro=\(name) \(version):\(platforms)"
  return .enableExperimentalFeature(setting)
}

let defaultSwiftSettings: [SwiftSetting] =
  availabilitySettings + [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
  ]

// -------------------------------------------------------------------------------------------------

let targets: [Target] = [
  // An implementation of the gRPC Health service.
  .target(
    name: "GRPCHealthService",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
      .product(name: "SwiftProtobuf", package: "swift-protobuf"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCHealthServiceTests",
    dependencies: [
      .target(name: "GRPCHealthService"),
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "GRPCInProcessTransport", package: "grpc-swift-2"),
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // An implementation of the gRPC Reflection service.
  .target(
    name: "GRPCReflectionService",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
      .product(name: "SwiftProtobuf", package: "swift-protobuf"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCReflectionServiceTests",
    dependencies: [
      .target(name: "GRPCReflectionService"),
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "GRPCInProcessTransport", package: "grpc-swift-2"),
      .product(name: "SwiftProtobuf", package: "swift-protobuf"),
    ],
    resources: [
      .copy("Generated/DescriptorSets")
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // gRPC OTel tracing interceptors.
  .target(
    name: "GRPCOTelTracingInterceptors",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "Tracing", package: "swift-distributed-tracing"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCOTelTracingInterceptorsTests",
    dependencies: [
      .target(name: "GRPCOTelTracingInterceptors"),
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "Tracing", package: "swift-distributed-tracing"),
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // Retroactive conformances of gRPC client and server to swift-server-lifecycle's Service.
  .target(
    name: "GRPCServiceLifecycle",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCServiceLifecycleTests",
    dependencies: [
      .target(name: "GRPCServiceLifecycle"),
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "ServiceLifecycleTestKit", package: "swift-service-lifecycle"),
      .product(name: "GRPCInProcessTransport", package: "grpc-swift-2"),
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // gRPC interop test implementation.
  .target(
    name: "GRPCInteropTests",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  // gRPC interop tests run with the in-process transport.
  .testTarget(
    name: "InProcessInteropTests",
    dependencies: [
      .target(name: "GRPCInteropTests"),
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "GRPCInProcessTransport", package: "grpc-swift-2"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
]

let package = Package(
  name: "grpc-swift-extras",
  products: products,
  dependencies: dependencies,
  targets: targets
)
