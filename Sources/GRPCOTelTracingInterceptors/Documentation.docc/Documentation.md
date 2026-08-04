# ``GRPCOTelTracingInterceptors``

Client and server interceptors that follow OpenTelemetry's recommendations on tracing.

## Overview

Interceptors let you observe and modify RPCs without changing your service or client code.
`GRPCOTelTracingInterceptors` uses this to automatically create and propagate OpenTelemetry
spans for every RPC, so you get gRPC call tracing without instrumenting each call by hand.

You can set up a client interceptor as follows, during your bootstrapping phase:

```swift
// Create the client interceptor
let interceptor = ClientOTelTracingInterceptor(
  serverHostname: "someserver.com",
  networkTransportMethod: "tcp"
)

// Add it as an interceptor when creating your client
let client = GRPCClient(
  transport: transport, 
  interceptors: [interceptor]
)

// Finally run your client
try await client.runConnections()
```

You can similarly add the server interceptor to your server as follows:

```swift
// Create the server interceptor
let interceptor = ServerOTelTracingInterceptor(
  serverHostname: "someserver.com",
  networkTransportMethod: "tcp"
)

// Add it as an interceptor when creating your server
let server = GRPCServer(
  transport: transport,
  services: [TestService()],
  interceptors: interceptor
)

// Finally run your server
try await server.serve()
```

For more information, see:
- [OpenTelemetry's documentation](https://opentelemetry.io/docs)
  - [RPC spans](https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans)
  - [gRPC conventions](https://opentelemetry.io/docs/specs/semconv/rpc/grpc)
- [gRPC-swift client interceptors](https://swiftpackageindex.com/grpc/grpc-swift-2/documentation/grpccore/clientinterceptor)
- [gRPC-swift server interceptors](https://swiftpackageindex.com/grpc/grpc-swift-2/documentation/grpccore/serverinterceptor)

## Topics

### Client interceptors

- ``ClientOTelTracingInterceptor``

### Server interceptors

- ``ServerOTelTracingInterceptor``
