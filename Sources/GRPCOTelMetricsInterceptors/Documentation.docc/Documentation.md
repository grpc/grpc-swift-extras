# ``GRPCOTelMetricsInterceptors``

This module contains client and server tracing interceptors adhering to OpenTelemetry's 
recommendations on recording metrics.

## Overview

You can read more on this topic at [OpenTelemetry's documentation](https://opentelemetry.io/docs).
Some relevant pages listing which attributes you can expect on your metrics include:
- [RPC Metrics](https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans)
- [gRPC conventions](https://opentelemetry.io/docs/specs/semconv/rpc/grpc)

You can set up a client interceptor like so during your bootstrapping phase:

```swift
// Create the client interceptor
let interceptor = ClientOTelMetricsInterceptor(
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

You can similarly add the server interceptor to your server like this:

```swift
// Create the server interceptor
let interceptor = ServerOTelMetricsInterceptor(
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

For more information, look at the documentation for:
- ``GRPCOTelMetricsInterceptors/ClientOTelMetricsInterceptor``,
- ``GRPCOTelMetricsInterceptors/ServerOTelMetricsInterceptor``,
- [Client Interceptors](https://swiftpackageindex.com/grpc/grpc-swift-2/documentation/grpccore/clientinterceptor), 
- [Server Interceptors](https://swiftpackageindex.com/grpc/grpc-swift-2/documentation/grpccore/serverinterceptor)
