// Copyright 2016 The gRPC Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Service exported by server reflection.  A more complete description of how
// server reflection works can be found at
// https://github.com/grpc/grpc/blob/master/doc/server-reflection.md
//
// The canonical version of this proto can be found at
// https://github.com/grpc/grpc-proto/blob/master/grpc/reflection/v1/reflection.proto

// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by the gRPC Swift generator plugin for the protocol buffer compiler.
// Source: reflection.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/grpc/grpc-swift

package import GRPCCore
internal import GRPCProtobuf

// MARK: - grpc.reflection.v1.ServerReflection

/// Namespace containing generated types for the "grpc.reflection.v1.ServerReflection" service.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package enum Grpc_Reflection_V1_ServerReflection {
    /// Service descriptor for the "grpc.reflection.v1.ServerReflection" service.
    package static let descriptor = GRPCCore.ServiceDescriptor(fullyQualifiedService: "grpc.reflection.v1.ServerReflection")
    /// Namespace for method metadata.
    package enum Method {
        /// Namespace for "ServerReflectionInfo" metadata.
        package enum ServerReflectionInfo {
            /// Request type for "ServerReflectionInfo".
            package typealias Input = Grpc_Reflection_V1_ServerReflectionRequest
            /// Response type for "ServerReflectionInfo".
            package typealias Output = Grpc_Reflection_V1_ServerReflectionResponse
            /// Descriptor for "ServerReflectionInfo".
            package static let descriptor = GRPCCore.MethodDescriptor(
                service: GRPCCore.ServiceDescriptor(fullyQualifiedService: "grpc.reflection.v1.ServerReflection"),
                method: "ServerReflectionInfo"
            )
        }
        /// Descriptors for all methods in the "grpc.reflection.v1.ServerReflection" service.
        package static let descriptors: [GRPCCore.MethodDescriptor] = [
            ServerReflectionInfo.descriptor
        ]
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GRPCCore.ServiceDescriptor {
    /// Service descriptor for the "grpc.reflection.v1.ServerReflection" service.
    package static let grpc_reflection_v1_ServerReflection = GRPCCore.ServiceDescriptor(fullyQualifiedService: "grpc.reflection.v1.ServerReflection")
}

// MARK: grpc.reflection.v1.ServerReflection (server)

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Reflection_V1_ServerReflection {
    /// Streaming variant of the service protocol for the "grpc.reflection.v1.ServerReflection" service.
    ///
    /// This protocol is the lowest-level of the service protocols generated for this service
    /// giving you the most flexibility over the implementation of your service. This comes at
    /// the cost of more verbose and less strict APIs. Each RPC requires you to implement it in
    /// terms of a request stream and response stream. Where only a single request or response
    /// message is expected, you are responsible for enforcing this invariant is maintained.
    ///
    /// Where possible, prefer using the stricter, less-verbose ``ServiceProtocol``
    /// or ``SimpleServiceProtocol`` instead.
    package protocol StreamingServiceProtocol: GRPCCore.RegistrableRPCService {
        /// Handle the "ServerReflectionInfo" method.
        ///
        /// > Source IDL Documentation:
        /// >
        /// > The reflection service is structured as a bidirectional stream, ensuring
        /// > all related requests go to a single server.
        ///
        /// - Parameters:
        ///   - request: A streaming request of `Grpc_Reflection_V1_ServerReflectionRequest` messages.
        ///   - context: Context providing information about the RPC.
        /// - Throws: Any error which occurred during the processing of the request. Thrown errors
        ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
        ///     to an internal error.
        /// - Returns: A streaming response of `Grpc_Reflection_V1_ServerReflectionResponse` messages.
        func serverReflectionInfo(
            request: GRPCCore.StreamingServerRequest<Grpc_Reflection_V1_ServerReflectionRequest>,
            context: GRPCCore.ServerContext
        ) async throws -> GRPCCore.StreamingServerResponse<Grpc_Reflection_V1_ServerReflectionResponse>
    }

    /// Service protocol for the "grpc.reflection.v1.ServerReflection" service.
    ///
    /// This protocol is higher level than ``StreamingServiceProtocol`` but lower level than
    /// the ``SimpleServiceProtocol``, it provides access to request and response metadata and
    /// trailing response metadata. If you don't need these then consider using
    /// the ``SimpleServiceProtocol``. If you need fine grained control over your RPCs then
    /// use ``StreamingServiceProtocol``.
    package protocol ServiceProtocol: Grpc_Reflection_V1_ServerReflection.StreamingServiceProtocol {
        /// Handle the "ServerReflectionInfo" method.
        ///
        /// > Source IDL Documentation:
        /// >
        /// > The reflection service is structured as a bidirectional stream, ensuring
        /// > all related requests go to a single server.
        ///
        /// - Parameters:
        ///   - request: A streaming request of `Grpc_Reflection_V1_ServerReflectionRequest` messages.
        ///   - context: Context providing information about the RPC.
        /// - Throws: Any error which occurred during the processing of the request. Thrown errors
        ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
        ///     to an internal error.
        /// - Returns: A streaming response of `Grpc_Reflection_V1_ServerReflectionResponse` messages.
        func serverReflectionInfo(
            request: GRPCCore.StreamingServerRequest<Grpc_Reflection_V1_ServerReflectionRequest>,
            context: GRPCCore.ServerContext
        ) async throws -> GRPCCore.StreamingServerResponse<Grpc_Reflection_V1_ServerReflectionResponse>
    }

    /// Simple service protocol for the "grpc.reflection.v1.ServerReflection" service.
    ///
    /// This is the highest level protocol for the service. The API is the easiest to use but
    /// doesn't provide access to request or response metadata. If you need access to these
    /// then use ``ServiceProtocol`` instead.
    package protocol SimpleServiceProtocol: Grpc_Reflection_V1_ServerReflection.ServiceProtocol {
        /// Handle the "ServerReflectionInfo" method.
        ///
        /// > Source IDL Documentation:
        /// >
        /// > The reflection service is structured as a bidirectional stream, ensuring
        /// > all related requests go to a single server.
        ///
        /// - Parameters:
        ///   - request: A stream of `Grpc_Reflection_V1_ServerReflectionRequest` messages.
        ///   - response: A response stream of `Grpc_Reflection_V1_ServerReflectionResponse` messages.
        ///   - context: Context providing information about the RPC.
        /// - Throws: Any error which occurred during the processing of the request. Thrown errors
        ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
        ///     to an internal error.
        func serverReflectionInfo(
            request: GRPCCore.RPCAsyncSequence<Grpc_Reflection_V1_ServerReflectionRequest, any Swift.Error>,
            response: GRPCCore.RPCWriter<Grpc_Reflection_V1_ServerReflectionResponse>,
            context: GRPCCore.ServerContext
        ) async throws
    }
}

// Default implementation of 'registerMethods(with:)'.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Reflection_V1_ServerReflection.StreamingServiceProtocol {
    package func registerMethods<Transport>(with router: inout GRPCCore.RPCRouter<Transport>) where Transport: GRPCCore.ServerTransport {
        router.registerHandler(
            forMethod: Grpc_Reflection_V1_ServerReflection.Method.ServerReflectionInfo.descriptor,
            deserializer: GRPCProtobuf.ProtobufDeserializer<Grpc_Reflection_V1_ServerReflectionRequest>(),
            serializer: GRPCProtobuf.ProtobufSerializer<Grpc_Reflection_V1_ServerReflectionResponse>(),
            handler: { request, context in
                try await self.serverReflectionInfo(
                    request: request,
                    context: context
                )
            }
        )
    }
}

// Default implementation of streaming methods from 'StreamingServiceProtocol'.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Reflection_V1_ServerReflection.ServiceProtocol {
}

// Default implementation of methods from 'ServiceProtocol'.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Reflection_V1_ServerReflection.SimpleServiceProtocol {
    package func serverReflectionInfo(
        request: GRPCCore.StreamingServerRequest<Grpc_Reflection_V1_ServerReflectionRequest>,
        context: GRPCCore.ServerContext
    ) async throws -> GRPCCore.StreamingServerResponse<Grpc_Reflection_V1_ServerReflectionResponse> {
        return GRPCCore.StreamingServerResponse<Grpc_Reflection_V1_ServerReflectionResponse>(
            metadata: [:],
            producer: { writer in
                try await self.serverReflectionInfo(
                    request: request.messages,
                    response: writer,
                    context: context
                )
                return [:]
            }
        )
    }
}

// MARK: grpc.reflection.v1.ServerReflection (client)

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Reflection_V1_ServerReflection {
    /// Generated client protocol for the "grpc.reflection.v1.ServerReflection" service.
    ///
    /// You don't need to implement this protocol directly, use the generated
    /// implementation, ``Client``.
    package protocol ClientProtocol: Sendable {
        /// Call the "ServerReflectionInfo" method.
        ///
        /// > Source IDL Documentation:
        /// >
        /// > The reflection service is structured as a bidirectional stream, ensuring
        /// > all related requests go to a single server.
        ///
        /// - Parameters:
        ///   - request: A streaming request producing `Grpc_Reflection_V1_ServerReflectionRequest` messages.
        ///   - serializer: A serializer for `Grpc_Reflection_V1_ServerReflectionRequest` messages.
        ///   - deserializer: A deserializer for `Grpc_Reflection_V1_ServerReflectionResponse` messages.
        ///   - options: Options to apply to this RPC.
        ///   - handleResponse: A closure which handles the response, the result of which is
        ///       returned to the caller. Returning from the closure will cancel the RPC if it
        ///       hasn't already finished.
        /// - Returns: The result of `handleResponse`.
        func serverReflectionInfo<Result>(
            request: GRPCCore.StreamingClientRequest<Grpc_Reflection_V1_ServerReflectionRequest>,
            serializer: some GRPCCore.MessageSerializer<Grpc_Reflection_V1_ServerReflectionRequest>,
            deserializer: some GRPCCore.MessageDeserializer<Grpc_Reflection_V1_ServerReflectionResponse>,
            options: GRPCCore.CallOptions,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<Grpc_Reflection_V1_ServerReflectionResponse>) async throws -> Result
        ) async throws -> Result where Result: Sendable
    }

    /// Generated client for the "grpc.reflection.v1.ServerReflection" service.
    ///
    /// The ``Client`` provides an implementation of ``ClientProtocol`` which wraps
    /// a `GRPCCore.GRPCCClient`. The underlying `GRPCClient` provides the long-lived
    /// means of communication with the remote peer.
    package struct Client<Transport>: ClientProtocol where Transport: GRPCCore.ClientTransport {
        private let client: GRPCCore.GRPCClient<Transport>

        /// Creates a new client wrapping the provided `GRPCCore.GRPCClient`.
        ///
        /// - Parameters:
        ///   - client: A `GRPCCore.GRPCClient` providing a communication channel to the service.
        package init(wrapping client: GRPCCore.GRPCClient<Transport>) {
            self.client = client
        }

        /// Call the "ServerReflectionInfo" method.
        ///
        /// > Source IDL Documentation:
        /// >
        /// > The reflection service is structured as a bidirectional stream, ensuring
        /// > all related requests go to a single server.
        ///
        /// - Parameters:
        ///   - request: A streaming request producing `Grpc_Reflection_V1_ServerReflectionRequest` messages.
        ///   - serializer: A serializer for `Grpc_Reflection_V1_ServerReflectionRequest` messages.
        ///   - deserializer: A deserializer for `Grpc_Reflection_V1_ServerReflectionResponse` messages.
        ///   - options: Options to apply to this RPC.
        ///   - handleResponse: A closure which handles the response, the result of which is
        ///       returned to the caller. Returning from the closure will cancel the RPC if it
        ///       hasn't already finished.
        /// - Returns: The result of `handleResponse`.
        package func serverReflectionInfo<Result>(
            request: GRPCCore.StreamingClientRequest<Grpc_Reflection_V1_ServerReflectionRequest>,
            serializer: some GRPCCore.MessageSerializer<Grpc_Reflection_V1_ServerReflectionRequest>,
            deserializer: some GRPCCore.MessageDeserializer<Grpc_Reflection_V1_ServerReflectionResponse>,
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<Grpc_Reflection_V1_ServerReflectionResponse>) async throws -> Result
        ) async throws -> Result where Result: Sendable {
            try await self.client.bidirectionalStreaming(
                request: request,
                descriptor: Grpc_Reflection_V1_ServerReflection.Method.ServerReflectionInfo.descriptor,
                serializer: serializer,
                deserializer: deserializer,
                options: options,
                onResponse: handleResponse
            )
        }
    }
}

// Helpers providing default arguments to 'ClientProtocol' methods.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Reflection_V1_ServerReflection.ClientProtocol {
    /// Call the "ServerReflectionInfo" method.
    ///
    /// > Source IDL Documentation:
    /// >
    /// > The reflection service is structured as a bidirectional stream, ensuring
    /// > all related requests go to a single server.
    ///
    /// - Parameters:
    ///   - request: A streaming request producing `Grpc_Reflection_V1_ServerReflectionRequest` messages.
    ///   - options: Options to apply to this RPC.
    ///   - handleResponse: A closure which handles the response, the result of which is
    ///       returned to the caller. Returning from the closure will cancel the RPC if it
    ///       hasn't already finished.
    /// - Returns: The result of `handleResponse`.
    package func serverReflectionInfo<Result>(
        request: GRPCCore.StreamingClientRequest<Grpc_Reflection_V1_ServerReflectionRequest>,
        options: GRPCCore.CallOptions = .defaults,
        onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<Grpc_Reflection_V1_ServerReflectionResponse>) async throws -> Result
    ) async throws -> Result where Result: Sendable {
        try await self.serverReflectionInfo(
            request: request,
            serializer: GRPCProtobuf.ProtobufSerializer<Grpc_Reflection_V1_ServerReflectionRequest>(),
            deserializer: GRPCProtobuf.ProtobufDeserializer<Grpc_Reflection_V1_ServerReflectionResponse>(),
            options: options,
            onResponse: handleResponse
        )
    }
}

// Helpers providing sugared APIs for 'ClientProtocol' methods.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Reflection_V1_ServerReflection.ClientProtocol {
    /// Call the "ServerReflectionInfo" method.
    ///
    /// > Source IDL Documentation:
    /// >
    /// > The reflection service is structured as a bidirectional stream, ensuring
    /// > all related requests go to a single server.
    ///
    /// - Parameters:
    ///   - metadata: Additional metadata to send, defaults to empty.
    ///   - options: Options to apply to this RPC, defaults to `.defaults`.
    ///   - producer: A closure producing request messages to send to the server. The request
    ///       stream is closed when the closure returns.
    ///   - handleResponse: A closure which handles the response, the result of which is
    ///       returned to the caller. Returning from the closure will cancel the RPC if it
    ///       hasn't already finished.
    /// - Returns: The result of `handleResponse`.
    package func serverReflectionInfo<Result>(
        metadata: GRPCCore.Metadata = [:],
        options: GRPCCore.CallOptions = .defaults,
        requestProducer producer: @Sendable @escaping (GRPCCore.RPCWriter<Grpc_Reflection_V1_ServerReflectionRequest>) async throws -> Void,
        onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<Grpc_Reflection_V1_ServerReflectionResponse>) async throws -> Result
    ) async throws -> Result where Result: Sendable {
        let request = GRPCCore.StreamingClientRequest<Grpc_Reflection_V1_ServerReflectionRequest>(
            metadata: metadata,
            producer: producer
        )
        return try await self.serverReflectionInfo(
            request: request,
            options: options,
            onResponse: handleResponse
        )
    }
}