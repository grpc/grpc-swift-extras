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

import Foundation
import GRPCCore
import GRPCOTelMetricsInterceptors
import Metrics
import MetricsTestKit
import Testing

@Suite("Client OTel Metrics Interceptor ")
struct ClientOTelMetricsInterceptorTests {
  private let metrics = TestMetrics()

  @Test(
    "Successful RPC is recorded correctly",
    arguments: OTelMetricsInterceptorTestAddressType.allCases
  )
  @available(gRPCSwiftExtras 2.0, *)
  func interceptorRecordsMetricsForSuccessfulCall(
    addressType: OTelMetricsInterceptorTestAddressType
  ) async throws {
    let interceptor = ClientOTelMetricsInterceptor(
      serverHostname: "test-server",
      networkTransport: "tcp",
      metricsFactory: self.metrics
    )
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "test-service",
      method: "test-method"
    )
    let (_, requestStreamContinuation) = AsyncStream<String>.makeStream()

    let testValues = OTelMetricsInterceptorTestCaseValues(addressType: addressType)

    let response = try await interceptor.intercept(
      request: StreamingClientRequest { writer in
        try await writer.write(contentsOf: ["test-message"])
      },
      context: ClientContext(
        descriptor: methodDescriptor,
        remotePeer: testValues.remotePeerAddress,
        localPeer: testValues.localPeerAddress
      ),
    ) { request, _ in
      let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
      try await request.producer(writer)
      requestStreamContinuation.finish()
      return .init(
        metadata: [],
        bodyParts: RPCAsyncSequence(
          wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
            $0.yield(.message("response-message"))
            $0.finish()
          }
        )
      )
    }

    await #expect(throws: Never.self) {
      if case let .success(contents) = response.accepted {
        for try await _ in contents.bodyParts {}
      }
    }

    let requestsPerRPC = try #require(
      self.metrics.recorders.first { $0.label == "rpc.client.requests_per_rpc" }
    )
    expectDimensions(requestsPerRPC.dimensions, expectAdditional: testValues.expectedDimensions)
    #expect(requestsPerRPC.values.reduce(0, +) == 1)

    let responsesPerRPC = try #require(
      self.metrics.recorders.first { $0.label == "rpc.client.responses_per_rpc" }
    )
    expectDimensions(responsesPerRPC.dimensions, expectAdditional: testValues.expectedDimensions)
    #expect(responsesPerRPC.values.reduce(0, +) == 1)

    let duration = try #require(self.metrics.timers.first { $0.label == "rpc.client.duration" })
    expectDimensions(
      duration.dimensions,
      expectAdditional: [("rpc.grpc.status_code", "0")] + testValues.expectedDimensions
    )
    let lastDurationValueNanoSeconds = try #require(duration.lastValue)
    let lastDurationValue = Double(lastDurationValueNanoSeconds) / 1_000_000_000
    #expect(0 < lastDurationValue && lastDurationValue < 1)  // between 0 and 1 sec
  }

  @Test("RPC that throws is correctly recorded")
  @available(gRPCSwiftExtras 2.0, *)
  func interceptorRecordsMetricsForFailedCall() async throws {
    let interceptor = ClientOTelMetricsInterceptor(
      serverHostname: "test-server",
      networkTransport: "tcp",
      metricsFactory: self.metrics
    )

    let (_, requestStreamContinuation) = AsyncStream<String>.makeStream()
    let request = StreamingClientRequest<String> { writer in
      try await writer.write("test-message")
    }

    let next:
      (StreamingClientRequest<String>, ClientContext) async throws -> StreamingClientResponse<
        String
      > = { request, _ in
        // Make sure the `producer` closure's which includes instrumentation is called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await request.producer(writer)
        requestStreamContinuation.finish()

        return .init(
          metadata: [],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.finish(throwing: RPCError(code: .unavailable, message: "This should be thrown"))
            }
          )
        )
      }

    do {
      let response = try await interceptor.intercept(
        request: request,
        context: ClientContext(
          descriptor: .init(fullyQualifiedService: "test-service", method: "test-method"),
          remotePeer: "",
          localPeer: ""
        ),
        next: next
      )

      // Consume the response to trigger the hooks
      if case let .success(contents) = response.accepted {
        for try await _ in contents.bodyParts {
          // We don't care about any received messages here
        }
      }
    } catch {
      let requestsPerRPC = try #require(
        self.metrics.recorders.first(where: { $0.label == "rpc.client.requests_per_rpc" })
      )
      expectDimensions(requestsPerRPC.dimensions)
      #expect(requestsPerRPC.values.reduce(0, +) == 1)

      let responsesPerRPC = try #require(
        self.metrics.recorders.first(where: { $0.label == "rpc.client.responses_per_rpc" })
      )
      expectDimensions(responsesPerRPC.dimensions)
      #expect(responsesPerRPC.values == [])  // empty values, as error is thrown in response

      let duration = try #require(
        self.metrics.timers.first(where: { $0.label == "rpc.client.duration" })
      )
      expectDimensions(
        duration.dimensions,
        expectAdditional: [("rpc.grpc.status_code", "\(RPCError.Code.unavailable.rawValue)")]
      )
      let lastDurationValueNanoSeconds = try #require(duration.lastValue)
      let lastDurationValue = Double(lastDurationValueNanoSeconds) / 1_000_000_000
      #expect(0 < lastDurationValue && lastDurationValue < 1)  // between 0 and 1 sec
    }
  }

  @Test("Messages in bidirectional-streaming are counted correctly")
  @available(gRPCSwiftExtras 2.0, *)
  func interceptorCountsMessagesCorrectly() async throws {
    let interceptor = ClientOTelMetricsInterceptor(
      serverHostname: "test-server",
      networkTransport: "tcp",
      metricsFactory: self.metrics
    )
    let (_, requestStreamContinuation) = AsyncStream<String>.makeStream()

    let request = StreamingClientRequest<String> { writer in
      // write multiple requests
      try await writer.write("test-message-1")
      try await writer.write("test-message-2")
      try await writer.write("test-message-3")
    }

    let responseContent = StreamingClientResponse<String>(
      accepted: .success(
        .init(
          metadata: [],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              // write multiple responses
              $0.yield(.message("response-message-1"))
              $0.yield(.message("response-message-2"))
              $0.finish()
            }
          )
        )
      )
    )

    let next:
      (StreamingClientRequest<String>, ClientContext) async throws -> StreamingClientResponse<
        String
      > = { request, _ in
        // Make sure the `producer` closure's which includes instrumentation is called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await request.producer(writer)
        requestStreamContinuation.finish()
        return responseContent
      }

    // Execute the interceptor
    let response = try await interceptor.intercept(
      request: request,
      context: ClientContext(
        descriptor: .init(fullyQualifiedService: "test-service", method: "test-method"),
        remotePeer: "",
        localPeer: ""
      ),
      next: next
    )

    // Consume the response to trigger the hooks
    if case let .success(contents) = response.accepted {
      for try await _ in contents.bodyParts {}
    }

    let requestsPerRPC = try #require(
      self.metrics.recorders.first(where: { $0.label == "rpc.client.requests_per_rpc" })
    )
    expectDimensions(requestsPerRPC.dimensions)
    #expect(requestsPerRPC.values.reduce(0, +) == 3)  // 3 requests

    let responsesPerRPC = try #require(
      self.metrics.recorders.first(where: { $0.label == "rpc.client.responses_per_rpc" })
    )
    expectDimensions(responsesPerRPC.dimensions)
    #expect(responsesPerRPC.values.reduce(0, +) == 2)  // 2 responses

    let duration = try #require(
      self.metrics.timers.first(where: { $0.label == "rpc.client.duration" })
    )
    expectDimensions(duration.dimensions, expectAdditional: [("rpc.grpc.status_code", "0")])
    let lastDurationValueNanoSeconds = try #require(duration.lastValue)
    let lastDurationValue = Double(lastDurationValueNanoSeconds) / 1_000_000_000
    #expect(0 < lastDurationValue && lastDurationValue < 1)  // between 0 and 1 sec
  }
}
