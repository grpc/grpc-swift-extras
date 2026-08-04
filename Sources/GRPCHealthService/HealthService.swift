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

public import GRPCCore

/// A gRPC service that reports whether a server can handle RPCs.
///
/// Its semantics are documented in the [gRPC repository](https://github.com/grpc/grpc/blob/5011420f160b91129a7baebe21df9444a07896a6/doc/health-checking.md).
///
/// `HealthService` implements the `grpc.health.v1` service and can be registered with a server
/// like any other service. It holds a ``HealthService/Provider-swift.struct`` that provides
/// status updates to the service. The service doesn't know about the other services running on the
/// server, so it must be provided with status updates via the ``Provider-swift.struct``. To make it
/// easier to specify which service is being updated, the generated code for services includes an
/// extension to `ServiceDescriptor`.
///
/// The following shows an example of initializing a health service and updating the status of
/// the `Foo` service in the `bar` package.
///
/// ```swift
/// let health = HealthService()
/// try await withGRPCServer(
///   transport: transport,
///   services: [health, FooService()]
/// ) { server in
///   // Update the status of the 'bar.Foo' service.
///   health.provider.updateStatus(.serving, forService: .bar_Foo)
///
///   // ...
/// }
/// ```
@available(gRPCSwiftExtras 2.0, *)
public struct HealthService: Sendable, RegistrableRPCService {
  /// An implementation of the `grpc.health.v1.Health` service.
  private let service: Service

  /// Provides status updates to the Health service.
  public let provider: HealthService.Provider

  /// Creates a health service with no recorded service statuses.
  public init() {
    let healthService = Service()
    self.service = healthService
    self.provider = HealthService.Provider(healthService: healthService)
  }

  /// Registers the service's methods with the given router.
  ///
  /// - Parameter router: The router to register the service's methods with.
  public func registerMethods<Transport>(
    with router: inout RPCRouter<Transport>
  ) where Transport: ServerTransport {
    self.service.registerMethods(with: &router)
  }
}

@available(gRPCSwiftExtras 2.0, *)
extension HealthService {
  /// Provides status updates to the health service.
  public struct Provider: Sendable {
    private let healthService: Service

    /// Updates the status of a service identified by its service descriptor.
    ///
    /// - Parameters:
    ///   - status: The status of the service.
    ///   - service: The description of the service.
    public func updateStatus(
      _ status: ServingStatus,
      forService service: ServiceDescriptor
    ) {
      self.healthService.updateStatus(
        Grpc_Health_V1_HealthCheckResponse.ServingStatus(status),
        forService: service.fullyQualifiedService
      )
    }

    /// Updates the status of a service identified by its fully qualified name.
    ///
    /// - Parameters:
    ///   - status: The status of the service.
    ///   - service: The fully qualified service name in the format:
    ///     - "package.service": if the service is part of a package. For example, "helloworld.Greeter".
    ///     - "service": if the service is not part of a package. For example, "Greeter".
    public func updateStatus(
      _ status: ServingStatus,
      forService service: String
    ) {
      self.healthService.updateStatus(
        Grpc_Health_V1_HealthCheckResponse.ServingStatus(status),
        forService: service
      )
    }

    fileprivate init(healthService: Service) {
      self.healthService = healthService
    }
  }
}

@available(gRPCSwiftExtras 2.0, *)
extension Grpc_Health_V1_HealthCheckResponse.ServingStatus {
  package init(_ status: ServingStatus) {
    switch status.value {
    case .serving:
      self = .serving
    case .notServing:
      self = .notServing
    }
  }
}
