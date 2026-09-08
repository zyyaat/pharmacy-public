---
name: Vercel lockfile registry
description: Prevents external Vercel builds from using Replit-only npm package URLs.
---

Frontend package-lock files that will be consumed by Vercel must resolve packages through the public npm registry. Replit can write internal `package-firewall.replit.local` tarball URLs into lockfiles, which work inside the workspace but fail in Vercel with DNS `ENOTFOUND`.

**Why:** Vercel runs outside the Replit network and cannot resolve Replit's internal package firewall hostname.

**How to apply:** Before publishing a frontend from GitHub, search all committed package-lock files for `replit.local` and ensure resolved tarballs use `https://registry.npmjs.org/`.