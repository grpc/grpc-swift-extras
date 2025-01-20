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

internal struct HookedRPCAsyncSequence<Wrapped: AsyncSequence & Sendable>: AsyncSequence, Sendable
where Wrapped.Element: Sendable {
  private let wrapped: Wrapped

  private let forEachElement: @Sendable (Wrapped.Element) -> Void
  private let onFinish: @Sendable () -> Void
  private let onFailure: @Sendable (any Error) -> Void

  init(
    wrapping sequence: Wrapped,
    forEachElement: @escaping @Sendable (Wrapped.Element) -> Void,
    onFinish: @escaping @Sendable () -> Void,
    onFailure: @escaping @Sendable (any Error) -> Void
  ) {
    self.wrapped = sequence
    self.forEachElement = forEachElement
    self.onFinish = onFinish
    self.onFailure = onFailure
  }

  func makeAsyncIterator() -> HookedAsyncIterator {
    HookedAsyncIterator(
      self.wrapped,
      forEachElement: self.forEachElement,
      onFinish: self.onFinish,
      onFailure: self.onFailure
    )
  }

  struct HookedAsyncIterator: AsyncIteratorProtocol {
    typealias Element = Wrapped.Element

    private var wrapped: Wrapped.AsyncIterator
    private let forEachElement: @Sendable (Wrapped.Element) -> Void
    private let onFinish: @Sendable () -> Void
    private let onFailure: @Sendable (any Error) -> Void

    init(
      _ sequence: Wrapped,
      forEachElement: @escaping @Sendable (Wrapped.Element) -> Void,
      onFinish: @escaping @Sendable () -> Void,
      onFailure: @escaping @Sendable (any Error) -> Void
    ) {
      self.wrapped = sequence.makeAsyncIterator()
      self.forEachElement = forEachElement
      self.onFinish = onFinish
      self.onFailure = onFailure
    }

    mutating func next(
      isolation actor: isolated (any Actor)?
    ) async throws(Wrapped.Failure) -> Wrapped.Element? {
      do {
        if let element = try await self.wrapped.next(isolation: actor) {
          self.forEachElement(element)
          return element
        }

        self.onFinish()
        return nil
      } catch {
        self.onFailure(error)
        throw error
      }
    }

    mutating func next() async throws -> Wrapped.Element? {
      do {
        if let element = try await self.wrapped.next() {
          self.forEachElement(element)
          return element
        }

        self.onFinish()
        return nil
      } catch {
        self.onFailure(error)
        throw error
      }
    }
  }
}
