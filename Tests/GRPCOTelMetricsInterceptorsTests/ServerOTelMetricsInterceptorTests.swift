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

@Suite("Server OTel Metrics Interceptor ")
struct ServerOTelMetricsInterceptorTests {
  private let metrics = TestMetrics()

  @Test(
    "Successful RPC is recorded correctly",
    arguments: OTelMetricsInterceptorTestAddressType.allCases
  )
  @available(gRPCSwiftExtras 2.0, *)
  func interceptorRecordsMetricsForSuccessfulCall(
    addressType: OTelMetricsInterceptorTestAddressType
  ) async throws {
    let interceptor = ServerOTelMetricsInterceptor(
      serverHostname: "test-server",
      networkTransport: "tcp",
      metricsFactory: self.metrics
    )
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "test-service",
      method: "test-method"
    )
    let request = ServerRequest(metadata: [:], message: "Hello World")

    let testValues = OTelMetricsInterceptorTestCaseValues(addressType: addressType)

    let response = try await interceptor.intercept(
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: testValues.remotePeerAddress,
        localPeer: testValues.localPeerAddress,
        cancellation: .init()
      )
    ) { request, _ in
      for try await _ in request.messages {
        // We need to iterate over the messages for the interceptor to be able to record metrics.
      }

      return StreamingServerResponse<String>(
        accepted: .success(
          .init(
            metadata: [],
            producer: { writer in
              try await writer.write("response1")
              try await writer.write("response2")
              return ["Result": "Trailing metadata"]
            }
          )
        )
      )
    }

    let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
    )
    responseStreamContinuation.finish()

    await assertStreamContentsEqual(["response1", "response2"], responseStream)
    #expect(trailingMetadata == ["Result": "Trailing metadata"])

    let requestsPerRPC = try #require(
      self.metrics.recorders.first { $0.label == "rpc.server.requests_per_rpc" }
    )
    expectDimensions(requestsPerRPC.dimensions, expectAdditional: testValues.expectedDimensions)
    #expect(requestsPerRPC.values.reduce(0, +) == 1)

    let responsesPerRPC = try #require(
      self.metrics.recorders.first { $0.label == "rpc.server.responses_per_rpc" }
    )
    expectDimensions(responsesPerRPC.dimensions, expectAdditional: testValues.expectedDimensions)
    #expect(responsesPerRPC.values.reduce(0, +) == 2)

    let duration = try #require(self.metrics.timers.first { $0.label == "rpc.server.duration" })
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
    let interceptor = ServerOTelMetricsInterceptor(
      serverHostname: "test-server",
      networkTransport: "tcp",
      metricsFactory: self.metrics
    )
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "test-service",
      method: "test-method"
    )
    let request = ServerRequest(metadata: [:], message: "Hello World")

    // (StreamingServerRequest<Input>, ServerContext) async throws -> StreamingServerResponse<Output>
    let next:
      (StreamingServerRequest<String>, ServerContext) async throws -> StreamingServerResponse<
        String
      > = { request, _ in
        for try await _ in request.messages {
          // We need to iterate over the messages for the interceptor to be able to record metrics.
        }

        return StreamingServerResponse(
          error: RPCError(code: .unavailable, message: "This should be thrown")
        )
      }

    do {
      let response = try await interceptor.intercept(
        request: .init(single: request),
        context: ServerContext(
          descriptor: methodDescriptor,
          remotePeer: "",
          localPeer: "",
          cancellation: .init()
        ),
        next: next
      )

      let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
      let responseContents = try response.accepted.get()
      let trailingMetadata = try await responseContents.producer(
        RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
      )
      responseStreamContinuation.finish()

      await assertStreamContentsEqual(["response1", "response2"], responseStream)
      #expect(trailingMetadata == ["Result": "Trailing metadata"])
    } catch {
      let requestsPerRPC = try #require(
        self.metrics.recorders.first(where: { $0.label == "rpc.server.requests_per_rpc" })
      )
      expectDimensions(requestsPerRPC.dimensions)
      #expect(requestsPerRPC.values.reduce(0, +) == 1)

      let responsesPerRPC = try #require(
        self.metrics.recorders.first(where: { $0.label == "rpc.server.responses_per_rpc" })
      )
      expectDimensions(responsesPerRPC.dimensions)
      #expect(responsesPerRPC.values == [])  // empty values, as error is thrown in response

      let duration = try #require(
        self.metrics.timers.first(where: { $0.label == "rpc.server.duration" })
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
}

@available(gRPCSwiftExtras 2.0, *)
private func assertStreamContentsEqual<T: Equatable>(
  _ array: [T],
  _ stream: any AsyncSequence<T, Never>
) async {
  var streamElements = [T]()
  for await element in stream {
    streamElements.append(element)
  }
  #expect(streamElements == array)
}
