# ``GRPCHealthService``

This module contains an implementation of the gRPC Health service
(`grpc.health.v1.Health`).

## Overview

The gRPC Health service is a regular gRPC service that allows clients to
request the status of another service. This can be done by polling the server
(the `Check` RPC) or by subscribing to changes in the status of a service (the
`Watch` RPC).

## Topics

### Health checking

- ``HealthService``
- ``ServingStatus``
