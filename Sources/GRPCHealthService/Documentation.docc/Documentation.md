# ``GRPCHealthService``

An implementation of the gRPC health service.

## Overview

This module implements `grpc.health.v1.Health`, a regular gRPC service that allows clients to
request the status of another service. Clients can poll with `Check`, subscribe to status
changes with `Watch`, or list every tracked service's status with `List`.

To use it, create a `HealthService`, register it with your server like any other service, and
push a status through its `provider`:

```swift
let health = HealthService()
try await withGRPCServer(
  transport: transport,
  services: [health, FooService()]
) { server in
  // Update the status of the 'bar.Foo' service.
  health.provider.updateStatus(.serving, forService: .bar_Foo)
}
```

`HealthService` has no default-serving status. It only knows what you tell it. If you never
call `updateStatus(_:forService:)` for a service, that service has no stored state. `Check`
then fails with `notFound` instead of reporting `serving`. Push a status for each service as
soon as you register it.

`List` is capped at 100 tracked services, and the limit isn't configurable. If you track more
than 100 services, `List` fails for every caller, so clients should fall back to per-service
`Check` or `Watch` calls instead.

Opening a `Watch` stream before you've pushed any status doesn't fail — it yields
`serviceUnknown` immediately, then delivers real transitions as you report them; watchers never
see a duplicate status.

## Topics

### Health checking

- ``HealthService``
- ``ServingStatus``
