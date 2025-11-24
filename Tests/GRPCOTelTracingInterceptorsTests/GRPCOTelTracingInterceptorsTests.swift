/*
 * Copyright 2024-2025, gRPC Authors All rights reserved.
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
import GRPCOTelTracingInterceptors
import Testing
import Tracing

import struct Foundation.UUID

@Suite("OTel Tracing Client Interceptor Tests")
struct OTelTracingClientInterceptorTests {
  @Test(
    "Successful RPC is recorded correctly",
    arguments: OTelTracingInterceptorTestAddressType.allCases
  )
  @available(gRPCSwiftExtras 2.0, *)
  func testSuccessfulRPC(addressType: OTelTracingInterceptorTestAddressType) async throws {
    let tracer = TestTracer()
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let interceptor = ClientOTelTracingInterceptor(
        serverHostname: "someserver.com",
        networkTransportMethod: "tcp",
        traceEachMessage: false
      )
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "OTelTracingClientInterceptorTests",
        method: "testSuccessfulRPC"
      )
      let testValues = self.getTestValues(
        addressType: addressType,
        methodDescriptor: methodDescriptor
      )
      let response = try await interceptor.intercept(
        tracer: tracer,
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request1"])
          try await writer.write(contentsOf: ["request2"])
        }),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: testValues.remotePeerAddress,
          localPeer: testValues.localPeerAddress
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        #expect(stream.metadata == ["trace-id": "\(traceIDString)"])

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(
          metadata: [],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.yield(.message(["response"]))
              $0.finish()
            }
          )
        )
      }

      await assertStreamContentsEqual(["request1", "request2"], requestStream)
      try await assertStreamContentsEqual([["response"]], response.messages)

      assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
        // No events are recorded
        #expect(events.isEmpty)
      } assertAttributes: { attributes in
        #expect(attributes == testValues.expectedSpanAttributes)
      } assertStatus: { status in
        #expect(status == SpanStatus(code: .ok))
      } assertErrors: { errors in
        #expect(errors == [])
      }
    }
  }

  @Test("All events are recorded when traceEachMessage is true")
  @available(gRPCSwiftExtras 2.0, *)
  func testAllEventsRecorded() async throws {
    let tracer = TestTracer()
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString

    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let interceptor = ClientOTelTracingInterceptor(
        serverHostname: "someserver.com",
        networkTransportMethod: "tcp",
        traceEachMessage: true
      )
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "OTelTracingClientInterceptorTests",
        method: "testAllEventsRecorded"
      )
      let testValues = self.getTestValues(addressType: .ipv4, methodDescriptor: methodDescriptor)
      let response = try await interceptor.intercept(
        tracer: tracer,
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request1"])
          try await writer.write(contentsOf: ["request2"])
        }),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: testValues.remotePeerAddress,
          localPeer: testValues.localPeerAddress
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        #expect(stream.metadata == ["trace-id": "\(traceIDString)"])

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(
          metadata: [],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.yield(.message(["response"]))
              $0.finish()
            }
          )
        )
      }

      await assertStreamContentsEqual(["request1", "request2"], requestStream)
      try await assertStreamContentsEqual([["response"]], response.messages)

      assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
        #expect(
          events == [
            // Recorded when `request1` is sent
            TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 1]),
            // Recorded when `request2` is sent
            TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 2]),
            // Recorded when receiving response part
            TestSpanEvent("rpc.message", ["rpc.message.type": "RECEIVED", "rpc.message.id": 1]),
          ]
        )
      } assertAttributes: { attributes in
        #expect(attributes == testValues.expectedSpanAttributes)
      } assertStatus: { status in
        #expect(status == SpanStatus(code: .ok))
      } assertErrors: { errors in
        #expect(errors == [])
      }
    }
  }

  @Test("All string-valued request metadata is included if opted-in")
  @available(gRPCSwiftExtras 2.0, *)
  func testRequestMetadataOptIn() async throws {
    let tracer = TestTracer()
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString

    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let interceptor = ClientOTelTracingInterceptor(
        serverHostname: "someserver.com",
        networkTransportMethod: "tcp",
        includeRequestMetadata: true
      )
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "OTelTracingClientInterceptorTests",
        method: "testRequestMetadataOptIn"
      )
      let response = try await interceptor.intercept(
        tracer: tracer,
        request: .init(
          metadata: [
            "some-request-metadata": "some-request-value",
            "some-repeated-request-metadata": "some-repeated-request-value1",
            "some-repeated-request-metadata": "some-repeated-request-value2",
            "some-request-metadata-bin": .binary([1]),
          ],
          producer: { writer in
            try await writer.write(contentsOf: ["request1"])
            try await writer.write(contentsOf: ["request2"])
          }
        ),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: "ipv4:10.1.2.80:567",
          localPeer: "ipv4:10.1.2.80:123"
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        #expect(
          stream.metadata.contains(where: {
            ($0.key == "trace-id") && ($0.value == .string(traceIDString))
          })
        )

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(
          metadata: [
            "some-response-metadata": "some-response-value",
            "some-response-metadata-bin": .binary([2]),
          ],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.yield(.message(["response"]))
              $0.yield(
                .trailingMetadata([
                  "some-repeated-response-metadata": "some-repeated-response-value1",
                  "some-repeated-response-metadata": "some-repeated-response-value2",
                ])
              )
              $0.finish()
            }
          )
        )
      }

      await assertStreamContentsEqual(["request1", "request2"], requestStream)
      try await assertStreamContentsEqual([["response"]], response.messages)

      assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
        #expect(
          events == [
            // Recorded when `request1` is sent
            TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 1]),
            // Recorded when `request2` is sent
            TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 2]),
            // Recorded when receiving response part
            TestSpanEvent("rpc.message", ["rpc.message.type": "RECEIVED", "rpc.message.id": 1]),
          ]
        )
      } assertAttributes: { attributes in
        #expect(
          attributes == [
            "rpc.system": "grpc",
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "rpc.grpc.status_code": 0,
            "server.address": "someserver.com",
            "server.port": 567,
            "network.peer.address": "10.1.2.80",
            "network.peer.port": 567,
            "network.transport": "tcp",
            "network.type": "ipv4",
            "rpc.grpc.request.metadata.some-request-metadata": "some-request-value",
            "rpc.grpc.request.metadata.some-repeated-request-metadata": .stringArray([
              "some-repeated-request-value1", "some-repeated-request-value2",
            ]),
          ]
        )
      } assertStatus: { status in
        #expect(status == SpanStatus(code: .ok))
      } assertErrors: { errors in
        #expect(errors == [])
      }
    }
  }

  @Test("All string-valued response metadata is included if opted-in")
  @available(gRPCSwiftExtras 2.0, *)
  func testResponseMetadataOptIn() async throws {
    let tracer = TestTracer()
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString

    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let interceptor = ClientOTelTracingInterceptor(
        serverHostname: "someserver.com",
        networkTransportMethod: "tcp",
        includeResponseMetadata: true
      )
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "OTelTracingClientInterceptorTests",
        method: "testResponseMetadataOptIn"
      )
      let response = try await interceptor.intercept(
        tracer: tracer,
        request: .init(
          metadata: [
            "some-request-metadata": "some-request-value",
            "some-repeated-request-metadata": "some-repeated-request-value1",
            "some-repeated-request-metadata": "some-repeated-request-value2",
            "some-request-metadata-bin": .binary([1]),
          ],
          producer: { writer in
            try await writer.write(contentsOf: ["request1"])
            try await writer.write(contentsOf: ["request2"])
          }
        ),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: "ipv4:10.1.2.80:567",
          localPeer: "ipv4:10.1.2.80:123"
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        #expect(
          stream.metadata.contains(where: {
            ($0.key == "trace-id") && ($0.value == .string(traceIDString))
          })
        )

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(
          metadata: [
            "some-response-metadata": "some-response-value",
            "some-response-metadata-bin": .binary([2]),
          ],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.yield(.message(["response"]))
              $0.yield(
                .trailingMetadata([
                  "some-repeated-response-metadata": "some-repeated-response-value1",
                  "some-repeated-response-metadata": "some-repeated-response-value2",
                ])
              )
              $0.finish()
            }
          )
        )
      }

      await assertStreamContentsEqual(["request1", "request2"], requestStream)
      try await assertStreamContentsEqual([["response"]], response.messages)

      assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
        #expect(
          events == [
            // Recorded when `request1` is sent
            TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 1]),
            // Recorded when `request2` is sent
            TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 2]),
            // Recorded when receiving response part
            TestSpanEvent("rpc.message", ["rpc.message.type": "RECEIVED", "rpc.message.id": 1]),
          ]
        )
      } assertAttributes: { attributes in
        #expect(
          attributes == [
            "rpc.system": "grpc",
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "rpc.grpc.status_code": 0,
            "server.address": "someserver.com",
            "server.port": 567,
            "network.peer.address": "10.1.2.80",
            "network.peer.port": 567,
            "network.transport": "tcp",
            "network.type": "ipv4",
            "rpc.grpc.response.metadata.some-response-metadata": "some-response-value",
            "rpc.grpc.response.metadata.some-repeated-response-metadata": .stringArray([
              "some-repeated-response-value1", "some-repeated-response-value2",
            ]),
          ]
        )
      } assertStatus: { status in
        #expect(status == SpanStatus(code: .ok))
      } assertErrors: { errors in
        #expect(errors == [])
      }
    }
  }

  @Test("RPC that throws is correctly recorded")
  @available(gRPCSwiftExtras 2.0, *)
  func testThrowingRPC() async throws {
    let tracer = TestTracer()
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    await ServiceContext.$current.withValue(serviceContext) {
      let interceptor = ClientOTelTracingInterceptor(
        serverHostname: "someserver.com",
        networkTransportMethod: "tcp",
        traceEachMessage: false
      )
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "OTelTracingClientInterceptorTests",
        method: "testThrowingRPC"
      )
      do {
        let _: StreamingClientResponse<Void> = try await interceptor.intercept(
          tracer: tracer,
          request: StreamingClientRequest(of: Void.self, producer: { writer in }),
          context: ClientContext(
            descriptor: methodDescriptor,
            remotePeer: "ipv4:10.1.2.80:567",
            localPeer: "ipv4:10.1.2.80:123"
          )
        ) { stream, _ in
          // Assert the metadata contains the injected context key-value.
          #expect(stream.metadata == ["trace-id": "\(traceIDString)"])
          // Now throw
          throw TracingInterceptorTestError.testError
        }
        Issue.record("Should have thrown")
      } catch {
        assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
          // No events are recorded
          #expect(events.isEmpty)
        } assertAttributes: { attributes in
          // The attributes should not contain a grpc status code, as the request was never even sent.
          #expect(
            attributes == [
              "rpc.system": "grpc",
              "rpc.method": .string(methodDescriptor.method),
              "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
              "rpc.grpc.status_code": .int64(Int64(RPCError.Code.unknown.rawValue)),
              "server.address": "someserver.com",
              "server.port": 567,
              "network.peer.address": "10.1.2.80",
              "network.peer.port": 567,
              "network.transport": "tcp",
              "network.type": "ipv4",
            ]
          )
        } assertStatus: { status in
          #expect(status == SpanStatus(code: .error))
        } assertErrors: { errors in
          #expect(errors == [.testError])
        }
      }
    }
  }

  @Test("RPC with a failure response is correctly recorded")
  @available(gRPCSwiftExtras 2.0, *)
  func testFailedRPC() async throws {
    let tracer = TestTracer()
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let (requestStream, requestStreamContinuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let interceptor = ClientOTelTracingInterceptor(
        serverHostname: "someserver.com",
        networkTransportMethod: "tcp",
        traceEachMessage: false
      )
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "OTelTracingClientInterceptorTests",
        method: "testFailedRPC"
      )
      let response: StreamingClientResponse<Void> = try await interceptor.intercept(
        tracer: tracer,
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request"])
        }),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: "ipv4:10.1.2.80:567",
          localPeer: "ipv4:10.1.2.80:123"
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        #expect(stream.metadata == ["trace-id": "\(traceIDString)"])

        // Write into the request stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: requestStreamContinuation))
        try await stream.producer(writer)
        requestStreamContinuation.finish()

        return .init(error: RPCError(code: .unavailable, message: "This should not work"))
      }

      await assertStreamContentsEqual(["request"], requestStream)

      switch response.accepted {
      case .success:
        Issue.record("Response should have failed")
        return

      case .failure(let failure):
        #expect(failure == RPCError(code: .unavailable, message: "This should not work"))
      }

      assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
        // No events are recorded
        #expect(events.isEmpty)
      } assertAttributes: { attributes in
        #expect(
          attributes == [
            "rpc.system": "grpc",
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "rpc.grpc.status_code": 14,  // this is unavailable's raw code
            "server.address": "someserver.com",
            "server.port": 567,
            "network.peer.address": "10.1.2.80",
            "network.peer.port": 567,
            "network.transport": "tcp",
            "network.type": "ipv4",
          ]
        )
      } assertStatus: { status in
        #expect(status == .some(.init(code: .error)))
      } assertErrors: { errors in
        #expect(errors.count == 1)
      }
    }
  }

  @Test("Accepted server-streaming RPC that throws error during response is correctly recorded")
  @available(gRPCSwiftExtras 2.0, *)
  func testAcceptedRPCWithError() async throws {
    let tracer = TestTracer()
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    serviceContext.traceID = traceIDString

    // FIXME: use 'ServiceContext.withValue(serviceContext)'
    //
    // This is blocked on: https://github.com/apple/swift-service-context/pull/46
    try await ServiceContext.$current.withValue(serviceContext) {
      let interceptor = ClientOTelTracingInterceptor(
        serverHostname: "someserver.com",
        networkTransportMethod: "tcp",
        traceEachMessage: false
      )
      let methodDescriptor = MethodDescriptor(
        fullyQualifiedService: "OTelTracingClientInterceptorTests",
        method: "testAcceptedRPCWithError"
      )
      let response: StreamingClientResponse<String> = try await interceptor.intercept(
        tracer: tracer,
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request"])
        }),
        context: ClientContext(
          descriptor: methodDescriptor,
          remotePeer: "ipv4:10.1.2.80:567",
          localPeer: "ipv4:10.1.2.80:123"
        )
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        #expect(stream.metadata == ["trace-id": "\(traceIDString)"])

        return .init(
          metadata: [],
          bodyParts: RPCAsyncSequence(
            wrapping: AsyncThrowingStream<StreamingClientResponse.Contents.BodyPart, any Error> {
              $0.finish(throwing: RPCError(code: .unavailable, message: "This should be thrown"))
            }
          )
        )
      }

      switch response.accepted {
      case .success(let success):
        do {
          for try await _ in success.bodyParts {
            // We don't care about any received messages here - we're not even writing any.
          }
        } catch {
          #expect(
            error as? RPCError
              == RPCError(
                code: .unavailable,
                message: "This should be thrown"
              )
          )
        }

      case .failure:
        Issue.record("Response should have been successful")
        return
      }

      assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
        // No events are recorded
        #expect(events.isEmpty)
      } assertAttributes: { attributes in
        #expect(
          attributes == [
            "rpc.system": "grpc",
            "rpc.method": .string(methodDescriptor.method),
            "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
            "rpc.grpc.status_code": 14,  // this is unavailable's raw code
            "server.address": "someserver.com",
            "server.port": 567,
            "network.peer.address": "10.1.2.80",
            "network.peer.port": 567,
            "network.transport": "tcp",
            "network.type": "ipv4",
          ]
        )
      } assertStatus: { status in
        #expect(status == .some(.init(code: .error)))
      } assertErrors: { errors in
        #expect(errors.count == 1)
      }
    }
  }

  @available(gRPCSwiftExtras 2.0, *)
  private func getTestValues(
    addressType: OTelTracingInterceptorTestAddressType,
    methodDescriptor: MethodDescriptor
  ) -> OTelTracingInterceptorTestCaseValues {
    switch addressType {
    case .ipv4:
      return OTelTracingInterceptorTestCaseValues(
        remotePeerAddress: "ipv4:10.1.2.80:567",
        localPeerAddress: "ipv4:10.1.2.80:123",
        expectedSpanAttributes: [
          "rpc.system": "grpc",
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": 0,
          "server.address": "someserver.com",
          "server.port": 567,
          "network.peer.address": "10.1.2.80",
          "network.peer.port": 567,
          "network.transport": "tcp",
          "network.type": "ipv4",
        ]
      )

    case .ipv6:
      return OTelTracingInterceptorTestCaseValues(
        remotePeerAddress: "ipv6:[2001::130F:::09C0:876A:130B]:1234",
        localPeerAddress: "ipv6:[ff06:0:0:0:0:0:0:c3]:5678",
        expectedSpanAttributes: [
          "rpc.system": "grpc",
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": 0,
          "server.address": "someserver.com",
          "server.port": 1234,
          "network.peer.address": "2001::130F:::09C0:876A:130B",
          "network.peer.port": 1234,
          "network.transport": "tcp",
          "network.type": "ipv6",
        ]
      )

    case .uds:
      return OTelTracingInterceptorTestCaseValues(
        remotePeerAddress: "unix:some-path",
        localPeerAddress: "unix:some-path",
        expectedSpanAttributes: [
          "rpc.system": "grpc",
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": 0,
          "server.address": "someserver.com",
          "network.peer.address": "some-path",
          "network.transport": "tcp",
        ]
      )
    }
  }
}

@Suite("OTel Tracing Server Interceptor Tests")
struct OTelTracingServerInterceptorTests {
  @Test(
    "Successful RPC is recorded correctly",
    arguments: OTelTracingInterceptorTestAddressType.allCases
  )
  @available(gRPCSwiftExtras 2.0, *)
  func testSuccessfulRPC(addressType: OTelTracingInterceptorTestAddressType) async throws {
    let tracer = TestTracer()
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "OTelTracingServerInterceptorTests",
      method: "testSuccessfulRPC"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      traceEachMessage: false
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())

    let testValues = self.getTestValues(
      addressType: addressType,
      methodDescriptor: methodDescriptor
    )
    let response = try await interceptor.intercept(
      tracer: tracer,
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: testValues.remotePeerAddress,
        localPeer: testValues.localPeerAddress,
        cancellation: .init()
      )
    ) { _, _ in
      // Make sure we get the metadata injected into our service context
      #expect(ServiceContext.current?.traceID == traceIDString)

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

    // Get the response out into a response stream, and assert its contents
    let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
    )
    responseStreamContinuation.finish()

    await assertStreamContentsEqual(["response1", "response2"], responseStream)
    #expect(trailingMetadata == ["Result": "Trailing metadata"])

    assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
      #expect(events.isEmpty)
    } assertAttributes: { attributes in
      #expect(attributes == testValues.expectedSpanAttributes)
    } assertStatus: { status in
      #expect(status == SpanStatus(code: .ok))
    } assertErrors: { errors in
      #expect(errors.isEmpty)
    }
  }

  @Test("All events are recorded when traceEachMessage is true")
  @available(gRPCSwiftExtras 2.0, *)
  func testAllEventsRecorded() async throws {
    let tracer = TestTracer()
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "OTelTracingServerInterceptorTests",
      method: "testAllEventsRecorded"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      traceEachMessage: true
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())
    let testValues = getTestValues(addressType: .ipv4, methodDescriptor: methodDescriptor)
    let response = try await interceptor.intercept(
      tracer: tracer,
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: testValues.remotePeerAddress,
        localPeer: testValues.localPeerAddress,
        cancellation: .init()
      )
    ) { request, _ in
      // Make sure we get the metadata injected into our service context
      #expect(ServiceContext.current?.traceID == traceIDString)

      for try await _ in request.messages {
        // We need to iterate over the messages for the span to be able to record the events.
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

    // Get the response out into a response stream, and assert its contents
    let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
    )
    responseStreamContinuation.finish()

    #expect(trailingMetadata == ["Result": "Trailing metadata"])
    await assertStreamContentsEqual(["response1", "response2"], responseStream)

    assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
      #expect(
        events == [
          // Recorded when request is received
          TestSpanEvent("rpc.message", ["rpc.message.type": "RECEIVED", "rpc.message.id": 1]),
          // Recorded when `response1` is sent
          TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 1]),
          // Recorded when `response2` is sent
          TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 2]),
        ]
      )
    } assertAttributes: { attributes in
      #expect(attributes == testValues.expectedSpanAttributes)
    } assertStatus: { status in
      #expect(status == SpanStatus(code: .ok))
    } assertErrors: { errors in
      #expect(errors.isEmpty)
    }
  }

  @Test("All string-valued request metadata is included if opted-in")
  @available(gRPCSwiftExtras 2.0, *)
  func testRequestMetadataOptIn() async throws {
    let tracer = TestTracer()
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "OTelTracingServerInterceptorTests",
      method: "testRequestMetadataOptIn"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      includeRequestMetadata: true
    )
    let request = ServerRequest(
      metadata: [
        "some-request-metadata": "some-request-value",
        "some-repeated-request-metadata": "some-repeated-request-value1",
        "some-repeated-request-metadata": "some-repeated-request-value2",
        "some-request-metadata-bin": .binary([1]),
      ],
      message: [UInt8]()
    )
    let response = try await interceptor.intercept(
      tracer: tracer,
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: "ipv4:10.1.2.80:567",
        localPeer: "ipv4:10.1.2.90:123",
        cancellation: .init()
      )
    ) { request, _ in
      for try await _ in request.messages {
        // We need to iterate over the messages for the span to be able to record the events.
      }

      return StreamingServerResponse<String>(
        accepted: .success(
          .init(
            metadata: [
              "some-response-metadata": "some-response-value",
              "some-response-metadata-bin": .binary([2]),
            ],
            producer: { writer in
              try await writer.write("response1")
              try await writer.write("response2")
              return [
                "some-repeated-response-metadata": "some-repeated-response-value1",
                "some-repeated-response-metadata": "some-repeated-response-value2",
              ]
            }
          )
        )
      )
    }

    // Get the response out into a response stream, and assert its contents
    let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
    )
    responseStreamContinuation.finish()

    #expect(
      trailingMetadata == [
        "some-repeated-response-metadata": "some-repeated-response-value1",
        "some-repeated-response-metadata": "some-repeated-response-value2",
      ]
    )
    await assertStreamContentsEqual(["response1", "response2"], responseStream)

    assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
      #expect(
        events == [
          // Recorded when request is received
          TestSpanEvent("rpc.message", ["rpc.message.type": "RECEIVED", "rpc.message.id": 1]),
          // Recorded when `response1` is sent
          TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 1]),
          // Recorded when `response2` is sent
          TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 2]),
        ]
      )
    } assertAttributes: { attributes in
      #expect(
        attributes == [
          "rpc.system": "grpc",
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": 0,
          "server.address": "someserver.com",
          "server.port": 123,
          "network.peer.address": "10.1.2.90",
          "network.peer.port": 123,
          "network.transport": "tcp",
          "network.type": "ipv4",
          "client.address": "10.1.2.80",
          "client.port": 567,
          "rpc.grpc.request.metadata.some-request-metadata": "some-request-value",
          "rpc.grpc.request.metadata.some-repeated-request-metadata": .stringArray([
            "some-repeated-request-value1", "some-repeated-request-value2",
          ]),
        ]
      )
    } assertStatus: { status in
      #expect(status == SpanStatus(code: .ok))
    } assertErrors: { errors in
      #expect(errors.isEmpty)
    }
  }

  @Test("All string-valued response metadata is included if opted-in")
  @available(gRPCSwiftExtras 2.0, *)
  func testResponseMetadataOptIn() async throws {
    let tracer = TestTracer()
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "OTelTracingServerInterceptorTests",
      method: "testResponseMetadataOptIn"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      includeResponseMetadata: true
    )
    let request = ServerRequest(
      metadata: [
        "some-request-metadata": "some-request-value",
        "some-repeated-request-metadata": "some-repeated-request-value1",
        "some-repeated-request-metadata": "some-repeated-request-value2",
        "some-request-metadata-bin": .binary([1]),
      ],
      message: [UInt8]()
    )
    let response = try await interceptor.intercept(
      tracer: tracer,
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: "ipv4:10.1.2.80:567",
        localPeer: "ipv4:10.1.2.90:123",
        cancellation: .init()
      )
    ) { request, _ in
      for try await _ in request.messages {
        // We need to iterate over the messages for the span to be able to record the events.
      }

      return StreamingServerResponse<String>(
        accepted: .success(
          .init(
            metadata: [
              "some-response-metadata": "some-response-value",
              "some-response-metadata-bin": .binary([2]),
            ],
            producer: { writer in
              try await writer.write("response1")
              try await writer.write("response2")
              return [
                "some-repeated-response-metadata": "some-repeated-response-value1",
                "some-repeated-response-metadata": "some-repeated-response-value2",
              ]
            }
          )
        )
      )
    }

    // Get the response out into a response stream, and assert its contents
    let (responseStream, responseStreamContinuation) = AsyncStream<String>.makeStream()
    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: responseStreamContinuation))
    )
    responseStreamContinuation.finish()

    #expect(
      trailingMetadata == [
        "some-repeated-response-metadata": "some-repeated-response-value1",
        "some-repeated-response-metadata": "some-repeated-response-value2",
      ]
    )
    await assertStreamContentsEqual(["response1", "response2"], responseStream)

    assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
      #expect(
        events == [
          // Recorded when request is received
          TestSpanEvent("rpc.message", ["rpc.message.type": "RECEIVED", "rpc.message.id": 1]),
          // Recorded when `response1` is sent
          TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 1]),
          // Recorded when `response2` is sent
          TestSpanEvent("rpc.message", ["rpc.message.type": "SENT", "rpc.message.id": 2]),
        ]
      )
    } assertAttributes: { attributes in
      #expect(
        attributes == [
          "rpc.system": "grpc",
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": 0,
          "server.address": "someserver.com",
          "server.port": 123,
          "network.peer.address": "10.1.2.90",
          "network.peer.port": 123,
          "network.transport": "tcp",
          "network.type": "ipv4",
          "client.address": "10.1.2.80",
          "client.port": 567,
          "rpc.grpc.response.metadata.some-response-metadata": "some-response-value",
          "rpc.grpc.response.metadata.some-repeated-response-metadata": .stringArray([
            "some-repeated-response-value1", "some-repeated-response-value2",
          ]),
        ]
      )
    } assertStatus: { status in
      #expect(status == SpanStatus(code: .ok))
    } assertErrors: { errors in
      #expect(errors.isEmpty)
    }
  }

  @Test("RPC that throws is correctly recorded")
  @available(gRPCSwiftExtras 2.0, *)
  func testThrowingRPC() async throws {
    let tracer = TestTracer()
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "TracingInterceptorTests",
      method: "testServerInterceptorErrorEncountered"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      traceEachMessage: false
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())
    let testValues = getTestValues(
      addressType: .ipv4,
      methodDescriptor: methodDescriptor,
      statusCode: RPCError.Code.unknown.rawValue
    )
    do {
      let _: StreamingServerResponse<String> = try await interceptor.intercept(
        tracer: tracer,
        request: .init(single: request),
        context: ServerContext(
          descriptor: methodDescriptor,
          remotePeer: testValues.remotePeerAddress,
          localPeer: testValues.localPeerAddress,
          cancellation: .init()
        )
      ) { _, _ in
        // Make sure we get the metadata injected into our service context
        #expect(ServiceContext.current?.traceID == traceIDString)

        throw TracingInterceptorTestError.testError
      }
      Issue.record("Should have thrown")
    } catch {
      assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
        #expect(events.isEmpty)
      } assertAttributes: { attributes in
        #expect(attributes == testValues.expectedSpanAttributes)
      } assertStatus: { status in
        #expect(status == SpanStatus(code: .error))
      } assertErrors: { errors in
        #expect(errors == [.testError])
      }
    }
  }

  @Test("RPC with a failure response is correctly recorded")
  @available(gRPCSwiftExtras 2.0, *)
  func testFailedRPC() async throws {
    let tracer = TestTracer()
    let methodDescriptor = MethodDescriptor(
      fullyQualifiedService: "TracingInterceptorTests",
      method: "testServerInterceptorErrorResponse"
    )
    let interceptor = ServerOTelTracingInterceptor(
      serverHostname: "someserver.com",
      networkTransportMethod: "tcp",
      traceEachMessage: false
    )
    let traceIDString = UUID().uuidString
    let request = ServerRequest(metadata: ["trace-id": .string(traceIDString)], message: [UInt8]())
    let testValues = getTestValues(addressType: .ipv4, methodDescriptor: methodDescriptor)
    let response = try await interceptor.intercept(
      tracer: tracer,
      request: .init(single: request),
      context: ServerContext(
        descriptor: methodDescriptor,
        remotePeer: testValues.remotePeerAddress,
        localPeer: testValues.localPeerAddress,
        cancellation: .init()
      )
    ) { _, _ in
      // Make sure we get the metadata injected into our service context
      #expect(ServiceContext.current?.traceID == traceIDString)

      return StreamingServerResponse<String>(
        error: RPCError(code: .unavailable, message: "Test error")
      )
    }

    #expect(throws: RPCError.self) {
      try response.accepted.get()
    }

    assertTestSpanComponents(forMethod: methodDescriptor, tracer: tracer) { events in
      #expect(events.isEmpty)
    } assertAttributes: { attributes in
      #expect(
        attributes == [
          "rpc.system": "grpc",
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": 14,  // this is unavailable's raw code
          "server.address": "someserver.com",
          "server.port": 123,
          "network.peer.address": "10.1.2.90",
          "network.peer.port": 123,
          "network.transport": "tcp",
          "network.type": "ipv4",
          "client.address": "10.1.2.80",
          "client.port": 567,
        ]
      )
    } assertStatus: { status in
      #expect(status == .some(.init(code: .error)))
    } assertErrors: { errors in
      #expect(errors.count == 1)
    }
  }

  @available(gRPCSwiftExtras 2.0, *)
  private func getTestValues(
    addressType: OTelTracingInterceptorTestAddressType,
    methodDescriptor: MethodDescriptor,
    statusCode: Int = 0
  ) -> OTelTracingInterceptorTestCaseValues {
    switch addressType {
    case .ipv4:
      return OTelTracingInterceptorTestCaseValues(
        remotePeerAddress: "ipv4:10.1.2.80:567",
        localPeerAddress: "ipv4:10.1.2.90:123",
        expectedSpanAttributes: [
          "rpc.system": "grpc",
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": .int64(Int64(statusCode)),
          "server.address": "someserver.com",
          "server.port": 123,
          "network.peer.address": "10.1.2.90",
          "network.peer.port": 123,
          "network.transport": "tcp",
          "network.type": "ipv4",
          "client.address": "10.1.2.80",
          "client.port": 567,
        ]
      )

    case .ipv6:
      return OTelTracingInterceptorTestCaseValues(
        remotePeerAddress: "ipv6:[2001::130F:::09C0:876A:130B]:1234",
        localPeerAddress: "ipv6:[ff06:0:0:0:0:0:0:c3]:5678",
        expectedSpanAttributes: [
          "rpc.system": "grpc",
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": .int64(Int64(statusCode)),
          "server.address": "someserver.com",
          "server.port": 5678,
          "network.peer.address": "ff06:0:0:0:0:0:0:c3",
          "network.peer.port": 5678,
          "network.transport": "tcp",
          "network.type": "ipv6",
          "client.address": "2001::130F:::09C0:876A:130B",
          "client.port": 1234,
        ]
      )

    case .uds:
      return OTelTracingInterceptorTestCaseValues(
        remotePeerAddress: "unix:some-path",
        localPeerAddress: "unix:some-path",
        expectedSpanAttributes: [
          "rpc.system": "grpc",
          "rpc.method": .string(methodDescriptor.method),
          "rpc.service": .string(methodDescriptor.service.fullyQualifiedService),
          "rpc.grpc.status_code": .int64(Int64(statusCode)),
          "server.address": "someserver.com",
          "network.peer.address": "some-path",
          "network.transport": "tcp",
          "client.address": "some-path",
        ]
      )
    }
  }
}

// -  MARK: Utilities

@available(gRPCSwiftExtras 2.0, *)
private func getTestSpanForMethod(
  tracer: TestTracer,
  methodDescriptor: MethodDescriptor
) -> TestSpan {
  tracer.getSpan(ofOperation: methodDescriptor.fullyQualifiedMethod)!
}

@available(gRPCSwiftExtras 2.0, *)
private func assertTestSpanComponents(
  forMethod method: MethodDescriptor,
  tracer: TestTracer,
  assertEvents: ([TestSpanEvent]) -> Void,
  assertAttributes: (SpanAttributes) -> Void,
  assertStatus: (SpanStatus?) -> Void,
  assertErrors: ([TracingInterceptorTestError]) -> Void
) {
  let span = getTestSpanForMethod(tracer: tracer, methodDescriptor: method)
  assertEvents(span.events.map({ TestSpanEvent($0) }))
  assertAttributes(span.attributes)
  assertStatus(span.status)
  assertErrors(span.errors)
}

@available(gRPCSwiftExtras 2.0, *)
private func assertStreamContentsEqual<T: Equatable>(
  _ array: [T],
  _ stream: any AsyncSequence<T, any Error>
) async throws {
  var streamElements = [T]()
  for try await element in stream {
    streamElements.append(element)
  }
  #expect(streamElements == array)
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

enum OTelTracingInterceptorTestAddressType {
  case ipv4
  case ipv6
  case uds

  static let allCases: [Self] = [.ipv4, .ipv6, .uds]
}

struct OTelTracingInterceptorTestCaseValues {
  let remotePeerAddress: String
  let localPeerAddress: String
  let expectedSpanAttributes: SpanAttributes
}
