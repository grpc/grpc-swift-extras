/*
 * Copyright 2025, gRPC Authors All rights reserved.
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

internal import GRPCCore
internal import Synchronization
internal import Tracing

extension Span {
  @available(gRPCSwiftExtras 2.0, *)
  func endRPC() {
    // No error, status code zero.
    self.attributes[GRPCTracingKeys.grpcStatusCode] = 0
    self.setStatus(SpanStatus(code: .ok))
    self.end()
  }

  @available(gRPCSwiftExtras 2.0, *)
  func endRPC(withError error: RPCError) {
    self.attributes[GRPCTracingKeys.grpcStatusCode] = error.code.rawValue
    self.setStatus(SpanStatus(code: .error))
    self.recordError(error)
    self.end()
  }

  @available(gRPCSwiftExtras 2.0, *)
  func endRPC(withError error: any Error) {
    if let error = error as? RPCError {
      self.endRPC(withError: error)
    } else if let convertible = error as? any RPCErrorConvertible {
      self.endRPC(withError: RPCError(convertible))
    } else {
      self.attributes[GRPCTracingKeys.grpcStatusCode] = RPCError.Code.unknown.rawValue
      self.setStatus(SpanStatus(code: .error))
      self.recordError(error)
      self.end()
    }
  }
}

extension SpanEvent {
  private static func rpcMessage(type: String, id: Int) -> Self {
    var event = SpanEvent(name: "rpc.message")
    event.attributes[GRPCTracingKeys.rpcMessageType] = type
    event.attributes[GRPCTracingKeys.rpcMessageID] = id
    return event
  }

  static func messageReceived(id: Int) -> Self {
    Self.rpcMessage(type: "RECEIVED", id: id)
  }

  static func messageSent(id: Int) -> Self {
    Self.rpcMessage(type: "SENT", id: id)
  }
}

@available(gRPCSwiftExtras 2.0, *)
final class TracedMessageWriter<Element>: RPCWriterProtocol {
  private let writer: any RPCWriterProtocol<Element>
  private let span: any Span
  private let messageID: Atomic<Int>

  init(wrapping writer: any RPCWriterProtocol<Element>, span: any Span) {
    self.writer = writer
    self.span = span
    self.messageID = Atomic(1)
  }

  private func nextMessageID() -> Int {
    self.messageID.wrappingAdd(1, ordering: .sequentiallyConsistent).oldValue
  }

  func write(_ element: Element) async throws {
    try await self.writer.write(element)
    self.span.addEvent(.messageSent(id: self.nextMessageID()))
  }

  func write(contentsOf elements: some Sequence<Element>) async throws {
    for element in elements {
      try await self.write(element)
    }
  }
}
