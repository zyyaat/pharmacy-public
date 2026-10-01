# Pharmacy OS Backend — repo-root Dockerfile wrapper
#
# Used when the PaaS service keeps the project root at the repository root
# (RunxBuild and DockHosting both accept a root Dockerfile; DockHosting
# also lets you point at backend/Dockerfile directly). This wrapper builds
# the Go backend exactly like backend/Dockerfile, with the build context
# set to the repository root.
#
# Deps are vendored (backend/vendor) — the build never touches the network.

# Stage 1: Build
FROM golang:1.25-alpine AS builder
RUN apk add --no-cache git ca-certificates
WORKDIR /src
COPY backend/go.mod backend/go.sum ./
COPY backend/vendor ./vendor
COPY backend/cmd ./cmd
COPY backend/internal ./internal
COPY backend/migrations ./migrations
RUN CGO_ENABLED=0 GOOS=linux GOFLAGS=-mod=vendor go build -ldflags="-s -w" -o /out/server ./cmd/server

# Stage 2: Runtime
FROM alpine:latest
RUN apk --no-cache add ca-certificates wget tzdata
WORKDIR /app
COPY --from=builder /out/server .
RUN chmod +x ./server
EXPOSE 8080
CMD ["./server"]
