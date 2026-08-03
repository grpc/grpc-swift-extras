# gRPC testing protocol types

Use these protocol buffer types to construct and inspect gRPC interoperability test requests
and responses.

## Overview

These types are generated from the `grpc.testing` proto package that defines the gRPC
interoperability test suite. The hand-written ``TestService`` implementation and the
``InteroperabilityTestCase`` test cases use them as RPC request and response types; you
typically don't construct them directly.

The reconnect messages and service aren't currently exercised by any implemented
``InteroperabilityTestCase``.

## Topics

### Constructing unary call messages

- ``Grpc_Testing_Empty``
- ``Grpc_Testing_SimpleRequest``
- ``Grpc_Testing_SimpleResponse``
- ``Grpc_Testing_EchoStatus``
- ``Grpc_Testing_BoolValue``
- ``Grpc_Testing_Payload``
- ``Grpc_Testing_PayloadType``

### Constructing streaming call messages

- ``Grpc_Testing_StreamingInputCallRequest``
- ``Grpc_Testing_StreamingInputCallResponse``
- ``Grpc_Testing_StreamingOutputCallRequest``
- ``Grpc_Testing_StreamingOutputCallResponse``
- ``Grpc_Testing_ResponseParameters``

### Constructing reconnect messages

- ``Grpc_Testing_ReconnectParams``
- ``Grpc_Testing_ReconnectInfo``

### Defining services

- ``Grpc_Testing_EmptyService``
- ``Grpc_Testing_TestService``
- ``Grpc_Testing_UnimplementedService``
- ``Grpc_Testing_ReconnectService``
