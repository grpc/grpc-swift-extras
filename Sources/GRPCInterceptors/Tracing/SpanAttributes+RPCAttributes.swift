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

import Tracing

@dynamicMemberLookup
package struct RPCAttributes: SpanAttributeNamespace {
  var attributes: SpanAttributes

  init(attributes: SpanAttributes) {
    self.attributes = attributes
  }

  struct NestedSpanAttributes: NestedSpanAttributesProtocol {
    init() {}

    var system: Key<String> { "rpc.system" }
    var method: Key<String> { "rpc.method" }
    var service: Key<String> { "rpc.service" }
    var messageID: Key<Int> { "rpc.message.id" }
    var messageType: Key<String> { "rpc.message.type" }
    var grpcStatusCode: Key<Int> { "rpc.grpc.status_code" }

    var serverAddress: Key<String>{ "server.address" }
    var serverPort: Key<Int> { "server.port" }

    var clientAddress: Key<String> { "client.address" }
    var clientPort: Key<Int> { "client.port" }

    var networkTransport: Key<String> { "network.transport" }
    var networkType: Key<String> { "network.type" }
    var networkPeerAddress: Key<String> { "network.peer.address" }
    var networkPeerPort: Key<Int> { "network.peer.port" }
  }
}

package extension SpanAttributes {
  /// Semantic conventions for RPC spans.
  var rpc: RPCAttributes {
    get {
      .init(attributes: self)
    }
    set {
      self = newValue.attributes
    }
  }
}
