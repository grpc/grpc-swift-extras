#!/bin/bash
## Copyright 2024, gRPC Authors All rights reserved.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

set -eu

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
root="$here/../.."
protoc=$(which protoc)

# Build the protoc plugins.
swift build -c release --product protoc-gen-swift
swift build -c release --product protoc-gen-grpc-swift

# Grab the plugin paths.
bin_path=$(swift build -c release --show-bin-path)
protoc_gen_swift="$bin_path/protoc-gen-swift"
protoc_generate_grpc_swift="$bin_path/protoc-gen-grpc-swift"

# Generates gRPC by invoking protoc with the gRPC Swift plugin.
# Parameters:
# - $1: .proto file
# - $2: proto path
# - $3: output path
# - $4 onwards: options to forward to the plugin
function generate_grpc {
  local proto=$1
  local args=("--plugin=$protoc_generate_grpc_swift" "--proto_path=${2}" "--grpc-swift_out=${3}")

  for option in "${@:4}"; do
    args+=("--grpc-swift_opt=$option")
  done

  invoke_protoc "${args[@]}" "$proto"
}

# Generates messages by invoking protoc with the Swift plugin.
# Parameters:
# - $1: .proto file
# - $2: proto path
# - $3: output path
# - $4 onwards: options to forward to the plugin
function generate_message {
  local proto=$1
  local args=("--plugin=$protoc_gen_swift" "--proto_path=$2" "--swift_out=$3")

  for option in "${@:4}"; do
    args+=("--swift_opt=$option")
  done

  invoke_protoc "${args[@]}" "$proto"
}

function invoke_protoc {
  # Setting -x when running the script produces a lot of output, instead boil
  # just echo out the protoc invocations.
  echo "$protoc" "$@"
  "$protoc" "$@"
}

#------------------------------------------------------------------------------

function generate_interop_test_service {
  local protos=(
    "$here/tests/interoperability/src/proto/grpc/testing/empty_service.proto"
    "$here/tests/interoperability/src/proto/grpc/testing/empty.proto"
    "$here/tests/interoperability/src/proto/grpc/testing/messages.proto"
    "$here/tests/interoperability/src/proto/grpc/testing/test.proto"
  )
  local output="$root/Sources/GRPCInteropTests/Generated"

  for proto in "${protos[@]}"; do
    generate_message "$proto" "$here/tests/interoperability" "$output" "Visibility=Public" "FileNaming=DropPath" "UseAccessLevelOnImports=true"
    generate_grpc "$proto" "$here/tests/interoperability" "$output" "Visibility=Public" "Server=true" "FileNaming=DropPath" "UseAccessLevelOnImports=true"
  done
}

function generate_health_service {
  local proto="$here/upstream/grpc/health/v1/health.proto"
  local output="$root/Sources/GRPCHealthService/Generated"

  generate_message "$proto" "$(dirname "$proto")" "$output" "Visibility=Package" "UseAccessLevelOnImports=true"
  generate_grpc "$proto" "$(dirname "$proto")" "$output" "Visibility=Package" "Client=true" "Server=true" "UseAccessLevelOnImports=true"
}

function generate_reflection_service {
  local proto="$here/upstream/grpc/reflection/v1/reflection.proto"
  local output="$root/Sources/GRPCReflectionService/Generated"

  generate_message "$proto" "$(dirname "$proto")" "$output" "Visibility=Package" "UseAccessLevelOnImports=true"
  generate_grpc "$proto" "$(dirname "$proto")" "$output" "Visibility=Package" "UseAccessLevelOnImports=true"
}

#- TEST DATA ------------------------------------------------------------------

function generate_reflection_service_descriptor_set {
  local proto="$here/upstream/grpc/reflection/v1/reflection.proto"
  local proto_path="$here/upstream"
  local output="$root/Tests/GRPCReflectionServiceTests/Generated/DescriptorSets/reflection.pb"

  invoke_protoc --descriptor_set_out="$output" "$proto" -I "$proto_path" \
    --include_source_info \
    --include_imports
}

function generate_health_service_descriptor_set {
  local proto="$here/upstream/grpc/health/v1/health.proto"
  local proto_path="$here/upstream"
  local output="$root/Tests/GRPCReflectionServiceTests/Generated/DescriptorSets/health.pb"

  invoke_protoc --descriptor_set_out="$output" "$proto" -I "$proto_path" \
    --include_source_info \
    --include_imports
}

function generate_base_message_descriptor_set {
  local proto="$here/tests/reflection/base_message.proto"
  local proto_path="$here/tests/reflection"
  local output="$root/Tests/GRPCReflectionServiceTests/Generated/DescriptorSets/base_message.pb"

  invoke_protoc --descriptor_set_out="$output" "$proto" -I "$proto_path" \
    --include_source_info \
    --include_imports
}

function generate_message_with_dependency_descriptor_set {
  local proto="$here/tests/reflection/message_with_dependency.proto"
  local proto_path="$here/tests/reflection"
  local output="$root/Tests/GRPCReflectionServiceTests/Generated/DescriptorSets/message_with_dependency.pb"

  invoke_protoc --descriptor_set_out="$output" "$proto" -I "$proto_path" \
    --include_source_info \
    --include_imports
}

#------------------------------------------------------------------------------

generate_interop_test_service
generate_health_service
generate_reflection_service

generate_reflection_service_descriptor_set
generate_health_service_descriptor_set
generate_base_message_descriptor_set
generate_message_with_dependency_descriptor_set
