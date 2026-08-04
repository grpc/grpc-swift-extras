# ``GRPCReflectionService``

An implementation of the gRPC reflection service.

## Overview

This module implements `grpc.reflection.v1.ServerReflection`, a regular gRPC service that
provides information about other services.

Reflection lets clients discover a server's services, methods, and message schemas at runtime,
without needing the server's `.proto` files ahead of time. This is especially useful for
debugging and ad-hoc tooling — clients like `grpcurl` and `grpcui` use reflection to call any
gRPC service dynamically, without generated stubs.

To use reflection, create a ``ReflectionService`` from your app's compiled descriptor sets, then
register it with your server like any other service. Once registered, it answers reflection
queries about whichever other services you've also registered on that server.

## Topics

### Server reflection

- ``ReflectionService``
