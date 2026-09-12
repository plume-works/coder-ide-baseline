#! /bin/bash
set -euo pipefail

# Local build of the workspace base image. CI publishes the multi-arch image;
# this builds a single architecture for testing on the current machine.
cd "$(dirname "$0")"

IMAGE="${IMAGE:-ghcr.io/plume-works/coder-ide-baseline:latest}"
PLATFORM="${PLATFORM:-linux/$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')}"

docker buildx build --platform "$PLATFORM" -t "$IMAGE" --load .
