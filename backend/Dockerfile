# Pharmacy OS Backend - Standalone Dockerfile
# Clean Go project - no monorepo overhead!

# Stage 1: Build (deps are vendored — the build never touches the network)
FROM golang:1.25-alpine AS builder
RUN apk add --no-cache git ca-certificates
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOFLAGS=-mod=vendor go build -ldflags="-s -w" -o server ./cmd/server

# Stage 2: Runtime
FROM alpine:latest
RUN apk --no-cache add ca-certificates wget tzdata
WORKDIR /app
COPY --from=builder /app/server .
RUN chmod +x ./server
EXPOSE 8080
CMD ["./server"]
