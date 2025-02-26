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
    url: "https://github.com/grpc/grpc-swift.git",
    from: "2.0.0"
  ),
  .package(
    url: "https://github.com/grpc/grpc-swift-protobuf.git",
    from: "1.0.0"
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
    from: "2.6.3"
  ),
]

let defaultSwiftSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
]

let targets: [Target] = [
  // An implementation of the gRPC Health service.
  .target(
    name: "GRPCHealthService",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
      .product(name: "SwiftProtobuf", package: "swift-protobuf"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCHealthServiceTests",
    dependencies: [
      .target(name: "GRPCHealthService"),
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "GRPCInProcessTransport", package: "grpc-swift"),
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // An implementation of the gRPC Reflection service.
  .target(
    name: "GRPCReflectionService",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
      .product(name: "SwiftProtobuf", package: "swift-protobuf"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCReflectionServiceTests",
    dependencies: [
      .target(name: "GRPCReflectionService"),
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "GRPCInProcessTransport", package: "grpc-swift"),
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
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "Tracing", package: "swift-distributed-tracing"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCOTelTracingInterceptorsTests",
    dependencies: [
      .target(name: "GRPCOTelTracingInterceptors"),
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "Tracing", package: "swift-distributed-tracing"),
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // Retroactive conformances of gRPC client and server to swift-server-lifecycle's Service.
  .target(
    name: "GRPCServiceLifecycle",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCServiceLifecycleTests",
    dependencies: [
      .target(name: "GRPCServiceLifecycle"),
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "ServiceLifecycleTestKit", package: "swift-service-lifecycle"),
      .product(name: "GRPCInProcessTransport", package: "grpc-swift"),
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // gRPC interop test implementation.
  .target(
    name: "GRPCInteropTests",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  // gRPC interop tests run with the in-process transport.
  .testTarget(
    name: "InProcessInteropTests",
    dependencies: [
      .target(name: "GRPCInteropTests"),
      .product(name: "GRPCCore", package: "grpc-swift"),
      .product(name: "GRPCInProcessTransport", package: "grpc-swift"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
]

let package = Package(
  name: "grpc-swift-extras",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
    .tvOS(.v18),
    .watchOS(.v11),
    .visionOS(.v2),
  ],
  products: products,
  dependencies: dependencies,
  targets: targets
)
