#!/bin/sh
set -euo pipefail

WORKSPACE_PATH="${CI_WORKSPACE:-${CI_PRIMARY_REPOSITORY_PATH:-$(pwd)}}"
cd "$WORKSPACE_PATH"
xcodegen generate
