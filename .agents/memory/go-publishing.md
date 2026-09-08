---
name: Replit Go publishing
description: Environment constraints encountered when running and publishing this imported Go API on Replit.
---

The Replit package firewall can reject older Go dependencies before the application build starts, and external Docker builds can use an older Go image than the version declared by an imported repository. Prefer an available compatible Go module and keep Docker builder images aligned with `go.mod`.

**Why:** The imported service initially requested Go 1.22 while the workspace exposed Go 1.21, and a DockHosting build later used Go 1.22 against a `go.mod` requiring Go 1.25. A compatible runtime and explicit Docker builder version were required before the API could build.

**How to apply:** Check available Go modules and every deployment Dockerfile early when an imported Go project fails before compilation. Keep deployment settings explicit: compile a production binary and run that binary. Avoid output names or paths excluded by `.gitignore`, because the build output may be absent when the publish runtime starts.