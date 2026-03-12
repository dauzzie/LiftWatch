#!/bin/sh
set -euo pipefail

cd "$CI_WORKSPACE"
xcodegen generate
