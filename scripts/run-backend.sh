#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../backend"

exec env \
  GOTOOLCHAIN=auto \
  GOSUMDB=sum.golang.org \
  GOPROXY=https://proxy.golang.org,direct \
  GOFLAGS=-mod=vendor \
  CGO_ENABLED=0 \
  go run ./cmd/server