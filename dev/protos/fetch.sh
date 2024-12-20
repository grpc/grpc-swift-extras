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
upstream="$here/upstream"

# Create a temporary directory for the repo checkouts.
checkouts="$(mktemp -d)"

# Clone the grpc and google protos into the staging area.
git clone --depth 1 https://github.com/grpc/grpc-proto "$checkouts/grpc-proto"

# Remove the old protos.
rm -rf "$upstream"

# Create new directories to poulate. These are based on proto package name
# rather than source repository name.
mkdir -p "$upstream/grpc/health/v1"
mkdir -p "$upstream/grpc/reflection/v1"

# Copy over the grpc-proto protos.
cp -rp "$checkouts/grpc-proto/grpc/health/v1/health.proto" "$upstream/grpc/health/v1/health.proto"
cp -rp "$checkouts/grpc-proto/grpc/reflection/v1/reflection.proto" "$upstream/grpc/reflection/v1/reflection.proto"
