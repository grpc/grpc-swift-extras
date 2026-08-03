# ``GRPCServiceLifecycle``

This module conforms `GRPCClient` and `GRPCServer` to the `Service` protocol from
Swift Service Lifecycle, enabling easy composition.

## Overview

Importing `GRPCServiceLifecycle` adds Swift Service Lifecycle conformance to `GRPCClient` and
`GRPCServer` by giving each a `run()` method that runs the client's connections or the server
until told to stop, and that honors graceful shutdown from a `ServiceGroup`.

Add each `GRPCServer` or `GRPCClient` to a `ServiceGroup` only once. If you add the same instance
twice — for example, directly and again through a wrapper type that also calls `run()` on it —
its graceful-shutdown handler runs twice, which can break shutdown behavior.

For more information on Swift Service Lifecycle, see its
[documentation](https://swiftpackageindex.com/swift-server/swift-service-lifecycle/documentation/servicelifecycle).
