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
import GRPCHealthService
import GRPCInProcessTransport
import SwiftProtobuf
import XCTest

@available(gRPCSwiftExtras 2.0, *)
final class HealthTests: XCTestCase {
  private func withHealthClient(
    _ body: @Sendable (
      Grpc_Health_V1_Health.Client<InProcessTransport.Client>,
      HealthService.Provider
    ) async throws -> Void
  ) async throws {
    let health = HealthService()
    let inProcess = InProcessTransport()
    let server = GRPCServer(transport: inProcess.server, services: [health])
    let client = GRPCClient(transport: inProcess.client)
    let healthClient = Grpc_Health_V1_Health.Client(wrapping: client)

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.serve()
      }

      group.addTask {
        try await client.runConnections()
      }

      do {
        try await body(healthClient, health.provider)
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      group.cancelAll()
    }
  }

  func testCheckOnKnownService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor.testService

      healthProvider.updateStatus(.serving, forService: testServiceDescriptor)

      let message = Grpc_Health_V1_HealthCheckRequest.with {
        $0.service = testServiceDescriptor.fullyQualifiedService
      }

      try await healthClient.check(request: ClientRequest(message: message)) { response in
        try XCTAssertEqual(response.message.status, .serving)
      }
    }
  }

  func testCheckOnUnknownService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let message = Grpc_Health_V1_HealthCheckRequest.with {
        $0.service = "does.not.Exist"
      }

      try await healthClient.check(request: ClientRequest(message: message)) { response in
        try XCTAssertThrowsError(ofType: RPCError.self, response.message) { error in
          XCTAssertEqual(error.code, .notFound)
        }
      }
    }
  }

  func testCheckOnServer() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      // An unspecified service refers to the server.
      healthProvider.updateStatus(.notServing, forService: "")

      let message = Grpc_Health_V1_HealthCheckRequest()

      try await healthClient.check(request: ClientRequest(message: message)) { response in
        try XCTAssertEqual(response.message.status, .notServing)
      }
    }
  }

  func testWatchOnKnownService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor.testService

      let statusesToBeSent: [ServingStatus] = [.serving, .notServing, .serving]

      // Before watching the service, make the status of the service known to the Health service.
      healthProvider.updateStatus(statusesToBeSent[0], forService: testServiceDescriptor)

      let message = Grpc_Health_V1_HealthCheckRequest.with {
        $0.service = testServiceDescriptor.fullyQualifiedService
      }

      try await healthClient.watch(request: ClientRequest(message: message)) { response in
        var responseStreamIterator = response.messages.makeAsyncIterator()

        for i in 0 ..< statusesToBeSent.count {
          let next = try await responseStreamIterator.next()
          let message = try XCTUnwrap(next)
          let expectedStatus = Grpc_Health_V1_HealthCheckResponse.ServingStatus(statusesToBeSent[i])

          XCTAssertEqual(message.status, expectedStatus)

          if i < statusesToBeSent.count - 1 {
            healthProvider.updateStatus(statusesToBeSent[i + 1], forService: testServiceDescriptor)
          }
        }
      }
    }
  }

  func testWatchOnUnknownServiceDoesNotTerminateTheRPC() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor.testService

      let message = Grpc_Health_V1_HealthCheckRequest.with {
        $0.service = testServiceDescriptor.fullyQualifiedService
      }

      try await healthClient.watch(request: ClientRequest(message: message)) { response in
        var responseStreamIterator = response.messages.makeAsyncIterator()
        var next = try await responseStreamIterator.next()
        var message = try XCTUnwrap(next)

        // As the service was watched before being updated, the first status received should be
        // .serviceUnknown.
        XCTAssertEqual(message.status, .serviceUnknown)

        healthProvider.updateStatus(.notServing, forService: testServiceDescriptor)

        next = try await responseStreamIterator.next()
        message = try XCTUnwrap(next)

        // The RPC was not terminated and a status update was received successfully.
        XCTAssertEqual(message.status, .notServing)
      }
    }
  }

  func testMultipleWatchOnTheSameService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor.testService

      let statusesToBeSent: [ServingStatus] = [.serving, .notServing, .serving]

      try await withThrowingTaskGroup(
        of: [Grpc_Health_V1_HealthCheckResponse.ServingStatus].self
      ) { group in
        let message = Grpc_Health_V1_HealthCheckRequest.with {
          $0.service = testServiceDescriptor.fullyQualifiedService
        }

        // The continuation of this stream will be used to signal when the watch response streams
        // are up and ready.
        let signal = AsyncStream.makeStream(of: Void.self)
        let numberOfWatches = 2

        for _ in 0 ..< numberOfWatches {
          group.addTask {
            return try await healthClient.watch(
              request: ClientRequest(message: message)
            ) { response in
              signal.continuation.yield()  // Make signal

              var statuses = [Grpc_Health_V1_HealthCheckResponse.ServingStatus]()
              var responseStreamIterator = response.messages.makeAsyncIterator()

              // Since responseStreamIterator.next() will never be nil (ideally, as the response
              // stream is always open), the iteration cannot be based on when
              // responseStreamIterator.next() is nil. Else, the iteration infinitely awaits and the
              // test never finishes. Hence, it is based on the expected number of statuses to be
              // received.
              for _ in 0 ..< statusesToBeSent.count + 1 {
                // As the service will be watched before being updated, the first status received
                // should be .serviceUnknown. Hence, the range of this iteration is increased by 1.

                let next = try await responseStreamIterator.next()
                let message = try XCTUnwrap(next)
                statuses.append(message.status)
              }

              return statuses
            }
          }
        }

        // Wait until all the watch streams are up and ready.
        for await _ in signal.stream.prefix(numberOfWatches) {}

        for status in statusesToBeSent {
          healthProvider.updateStatus(status, forService: testServiceDescriptor)
        }

        for try await receivedStatuses in group {
          XCTAssertEqual(receivedStatuses[0], .serviceUnknown)

          for i in 0 ..< statusesToBeSent.count {
            let sentStatus = Grpc_Health_V1_HealthCheckResponse.ServingStatus(statusesToBeSent[i])
            XCTAssertEqual(sentStatus, receivedStatuses[i + 1])
          }
        }
      }
    }
  }

  func testWatchWithUnchangingStatusUpdates() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor.testService

      let statusesToBeSent: [ServingStatus] = [.notServing, .notServing, .notServing, .serving]

      // The repeated .notServing updates should be received only once. Also, as the service will
      // be watched before being updated, the first status received should be .serviceUnknown.
      let expectedStatuses: [Grpc_Health_V1_HealthCheckResponse.ServingStatus] = [
        .serviceUnknown,
        .notServing,
        .serving,
      ]

      let message = Grpc_Health_V1_HealthCheckRequest.with {
        $0.service = testServiceDescriptor.fullyQualifiedService
      }

      try await healthClient.watch(
        request: ClientRequest(message: message)
      ) { response in
        // Send all status updates.
        for status in statusesToBeSent {
          healthProvider.updateStatus(status, forService: testServiceDescriptor)
        }

        var responseStreamIterator = response.messages.makeAsyncIterator()

        for i in 0 ..< expectedStatuses.count {
          let next = try await responseStreamIterator.next()
          let message = try XCTUnwrap(next)

          XCTAssertEqual(message.status, expectedStatuses[i])
        }
      }
    }
  }

  func testWatchOnServer() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let statusesToBeSent: [ServingStatus] = [.serving, .notServing, .serving]

      // An unspecified service refers to the server.
      healthProvider.updateStatus(statusesToBeSent[0], forService: "")

      let message = Grpc_Health_V1_HealthCheckRequest()

      try await healthClient.watch(request: ClientRequest(message: message)) { response in
        var responseStreamIterator = response.messages.makeAsyncIterator()

        for i in 0 ..< statusesToBeSent.count {
          let next = try await responseStreamIterator.next()
          let message = try XCTUnwrap(next)
          let expectedStatus = Grpc_Health_V1_HealthCheckResponse.ServingStatus(statusesToBeSent[i])

          XCTAssertEqual(message.status, expectedStatus)

          if i < statusesToBeSent.count - 1 {
            healthProvider.updateStatus(statusesToBeSent[i + 1], forService: "")
          }
        }
      }
    }
  }

  func testListServicesEmpty() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let message = Grpc_Health_V1_HealthListRequest()

      let response = try await healthClient.list(message)
      XCTAssertEqual(response.statuses, [:])
    }
  }

  func testListServices() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let message = Grpc_Health_V1_HealthListRequest()

      // Service descriptors and their randomly generated status.
      let testServiceDescriptors: [(ServiceDescriptor, ServingStatus)] = (0 ..< 10).map { i in
        (
          ServiceDescriptor(package: "test", service: "Service\(i)"),
          Bool.random() ? .notServing : .serving
        )
      }

      for (index, (descriptor, status)) in testServiceDescriptors.enumerated() {
        healthProvider.updateStatus(
          status,
          forService: descriptor
        )

        let response = try await healthClient.list(message)
        let statuses = response.statuses
        XCTAssertTrue(statuses.count == index + 1)

        for (descriptor, status) in testServiceDescriptors.prefix(index + 1) {
          let receivedStatus = try XCTUnwrap(statuses[descriptor.fullyQualifiedService]?.status)
          let expectedStatus = Grpc_Health_V1_HealthCheckResponse.ServingStatus(
            status
          )

          XCTAssertEqual(receivedStatus, expectedStatus)
        }
      }
    }
  }

  func testListOnServer() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let message = Grpc_Health_V1_HealthListRequest()

      healthProvider.updateStatus(.notServing, forService: "")

      var response = try await healthClient.list(message)
      XCTAssertEqual(try XCTUnwrap(response.statuses[""]?.status), .notServing)

      healthProvider.updateStatus(.serving, forService: "")

      response = try await healthClient.list(message)
      XCTAssertEqual(try XCTUnwrap(response.statuses[""]?.status), .serving)
    }
  }

  func testListExceedingMaxAllowedServices() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let message = Grpc_Health_V1_HealthListRequest()
      let listMaxAllowedServices = 100

      for index in 1 ... listMaxAllowedServices {
        healthProvider.updateStatus(
          .notServing,
          forService: ServiceDescriptor(package: "test", service: "Service\(index)")
        )

        let response = try await healthClient.list(message)
        XCTAssertTrue(response.statuses.count == index)
      }

      healthProvider.updateStatus(.notServing, forService: ServiceDescriptor.testService)

      do {
        _ = try await healthClient.list(message)
        XCTFail("should error")
      } catch {
        let resolvedError = try XCTUnwrap(
          error as? RPCError,
          "health client list throws unexpected error: \(error)"
        )
        XCTAssertEqual(resolvedError.code, .resourceExhausted)
      }
    }
  }
}

@available(gRPCSwiftExtras 2.0, *)
extension ServiceDescriptor {
  fileprivate static let testService = ServiceDescriptor(package: "test", service: "Service")
}
