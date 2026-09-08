---
name: Replit Go publishing
description: Environment constraints encountered when running and publishing this imported Go API on Replit.
---

Imported Go services can declare a newer toolchain than the workspace's default module. When the declared toolchain is not installed, use `GOTOOLCHAIN=auto` with public checksum verification and vendored dependencies; local-only mode will fail before the server starts.

**Why:** This workspace exposed Go 1.21 while the imported project declared Go 1.25. Automatic download succeeded only after enabling `GOSUMDB=sum.golang.org`; the environment's default checksum-disabled setting prevented startup.

**How to apply:** Check the declared Go version early, use `GOTOOLCHAIN=auto GOSUMDB=sum.golang.org GOPROXY=https://proxy.golang.org,direct` for workflows and local scripts, and keep `GOFLAGS=-mod=vendor`. Keep deployment settings explicit: compile a production binary and run that binary.