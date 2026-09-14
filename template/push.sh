#!/usr/bin/env bash
# Create the template on first run, or push a new version after that.
set -euo pipefail
cd "$(dirname "$0")"

coder templates push "${TEMPLATE_NAME:-docker-in-docker}" --directory . --yes
