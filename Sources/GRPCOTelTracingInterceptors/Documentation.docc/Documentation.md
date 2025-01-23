# ``GRPCOTelTracingInterceptors``

This module contains client and server tracing interceptors adhering to OpenTelemetry's 
recommendations on tracing.

## Overview

You can read more on this topic at [OpenTelemetry's documentation](https://opentelemetry.io/docs). 
Some relevant pages listing which attributes and events you can expect on your spans include:
- [RPC Spans](https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans)
- [gRPC conventions](https://opentelemetry.io/docs/specs/semconv/rpc/grpc)

You can set up a client interceptor like so during your bootstrapping phase:

```swift
// Create the client interceptor
let interceptor = ClientOTelTracingInterceptor(
  serverHostname: "someserver.com",
  networkTransportMethod: "tcp"
)

// Add it as an interceptor when creating your client
let client = GRPCClient(
  transport: someTransport, 
  interceptors: [interceptor]
)

// Finally run your client
try await client.runConnections()
```

You can similarly add the server interceptor to your server like this:

```swift
// Create the server interceptor
let interceptor = ServerOTelTracingInterceptor(
  serverHostname: "someserver.com",
  networkTransportMethod: "tcp"
)

// Add it as an interceptor when creating your server
let server = GRPCServer(
  transport: inProcess.server,
  services: [TestService()],
  interceptors: interceptor
)

// Finally run your server
try await server.serve()
```

For more information, look at the documentation for:
- ``GRPCOTelTracingInterceptors/ClientOTelTracingInterceptor``,
- ``GRPCOTelTracingInterceptors/ServerOTelTracingInterceptor``,
- [Client Interceptors](https://swiftpackageindex.com/grpc/grpc-swift/documentation/grpccore/clientinterceptor), 
- [Server Interceptors](https://swiftpackageindex.com/grpc/grpc-swift/documentation/grpccore/serverinterceptor)
