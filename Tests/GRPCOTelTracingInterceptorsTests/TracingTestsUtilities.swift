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
import Synchronization
import Tracing

@available(gRPCSwiftExtras 2.0, *)
final class TestTracer: Tracer {
  typealias Span = TestSpan

  private let testSpans: Mutex<[String: TestSpan]> = .init([:])

  func getSpan(ofOperation operationName: String) -> TestSpan? {
    self.testSpans.withLock { $0[operationName] }
  }

  func getEventsForTestSpan(ofOperation operationName: String) -> [SpanEvent] {
    self.getSpan(ofOperation: operationName)?.events ?? []
  }

  func extract<Carrier, Extract>(
    _ carrier: Carrier,
    into context: inout ServiceContextModule.ServiceContext,
    using extractor: Extract
  ) where Carrier == Extract.Carrier, Extract: Instrumentation.Extractor {
    let traceID = extractor.extract(key: TraceID.keyName, from: carrier)
    context[TraceID.self] = traceID
  }

  func inject<Carrier, Inject>(
    _ context: ServiceContextModule.ServiceContext,
    into carrier: inout Carrier,
    using injector: Inject
  ) where Carrier == Inject.Carrier, Inject: Instrumentation.Injector {
    if let traceID = context.traceID {
      injector.inject(traceID, forKey: TraceID.keyName, into: &carrier)
    }
  }

  func forceFlush() {
    // no-op
  }

  func startSpan<Instant>(
    _ operationName: String,
    context: @autoclosure () -> ServiceContext,
    ofKind kind: SpanKind,
    at instant: @autoclosure () -> Instant,
    function: String,
    file fileID: String,
    line: UInt
  ) -> TestSpan where Instant: TracerInstant {
    return self.testSpans.withLock { testSpans in
      let span = TestSpan(context: context(), operationName: operationName)
      testSpans[operationName] = span
      return span
    }
  }
}

@available(gRPCSwiftExtras 2.0, *)
final class TestSpan: Span, Sendable {
  private struct State {
    var context: ServiceContextModule.ServiceContext
    var operationName: String
    var attributes: Tracing.SpanAttributes
    var status: Tracing.SpanStatus?
    var events: [Tracing.SpanEvent] = []
    var errors: [TracingInterceptorTestError]
  }

  private let state: Mutex<State>
  let isRecording: Bool

  var context: ServiceContextModule.ServiceContext {
    self.state.withLock { $0.context }
  }

  var operationName: String {
    get { self.state.withLock { $0.operationName } }
    set { self.state.withLock { $0.operationName = newValue } }
  }

  var attributes: Tracing.SpanAttributes {
    get { self.state.withLock { $0.attributes } }
    set { self.state.withLock { $0.attributes = newValue } }
  }

  var events: [Tracing.SpanEvent] {
    self.state.withLock { $0.events }
  }

  var status: SpanStatus? {
    self.state.withLock { $0.status }
  }

  var errors: [TracingInterceptorTestError] {
    self.state.withLock { $0.errors }
  }

  init(
    context: ServiceContextModule.ServiceContext,
    operationName: String,
    attributes: Tracing.SpanAttributes = [:],
    isRecording: Bool = true
  ) {
    let state = State(
      context: context,
      operationName: operationName,
      attributes: attributes,
      errors: []
    )
    self.state = Mutex(state)
    self.isRecording = isRecording
  }

  func setStatus(_ status: Tracing.SpanStatus) {
    self.state.withLock { $0.status = status }
  }

  func addEvent(_ event: Tracing.SpanEvent) {
    self.state.withLock { $0.events.append(event) }
  }

  func recordError<Instant>(
    _ error: any Error,
    attributes: Tracing.SpanAttributes,
    at instant: @autoclosure () -> Instant
  ) where Instant: Tracing.TracerInstant {
    // For the purposes of these tests, we don't really care about the error being thrown
    self.state.withLock { $0.errors.append(TracingInterceptorTestError.testError) }
  }

  func addLink(_ link: Tracing.SpanLink) {
    self.state.withLock {
      $0.context.spanLinks?.append(link)
    }
  }

  func end<Instant>(at instant: @autoclosure () -> Instant) where Instant: Tracing.TracerInstant {
    // no-op
  }
}

enum TraceID: ServiceContextModule.ServiceContextKey {
  typealias Value = String

  static let keyName = "trace-id"
}

enum ServiceContextSpanLinksKey: ServiceContextModule.ServiceContextKey {
  typealias Value = [SpanLink]

  static let keyName = "span-links"
}

extension ServiceContext {
  var traceID: String? {
    get {
      self[TraceID.self]
    }
    set {
      self[TraceID.self] = newValue
    }
  }

  var spanLinks: [SpanLink]? {
    get {
      self[ServiceContextSpanLinksKey.self]
    }
    set {
      self[ServiceContextSpanLinksKey.self] = newValue
    }
  }
}

struct TestWriter<WriterElement: Sendable>: RPCWriterProtocol {
  typealias Element = WriterElement

  private let streamContinuation: AsyncStream<Element>.Continuation

  init(streamContinuation: AsyncStream<Element>.Continuation) {
    self.streamContinuation = streamContinuation
  }

  func write(_ element: WriterElement) {
    self.streamContinuation.yield(element)
  }

  func write(contentsOf elements: some Sequence<Self.Element>) {
    elements.forEach { element in
      self.write(element)
    }
  }
}

struct TestSpanEvent: Equatable, CustomDebugStringConvertible {
  var name: String
  var attributes: SpanAttributes

  // This conformance is so any test errors are nicer to look at and understand
  var debugDescription: String {
    var attributesDescription = ""
    self.attributes.forEach { key, value in
      attributesDescription += " \(key): \(value),"
    }

    return """
      (name: \(self.name), attributes: [\(attributesDescription)])
      """
  }

  init(_ name: String, _ attributes: SpanAttributes) {
    self.name = name
    self.attributes = attributes
  }

  init(_ spanEvent: SpanEvent) {
    self.name = spanEvent.name
    self.attributes = spanEvent.attributes
  }
}

enum TracingInterceptorTestError: Error, Equatable {
  case testError
}
