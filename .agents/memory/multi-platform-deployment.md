---
name: Multi-platform deployment
description: The deployment contract between independently hosted Next.js apps, the Go API, and Supabase PostgreSQL.
---

Use a same-origin Next.js proxy for independently hosted frontends: set the browser-facing API base to `/api/v1` and configure the server-side `BACKEND_INTERNAL_URL` to the public HTTPS backend origin. Use direct absolute API URLs only when the backend CORS allowlist and cross-site cookies are intentionally configured.

**Why:** A relative API base with a hardcoded localhost rewrite works in Replit development but produces browser “Failed to fetch” errors on Vercel because localhost points to the Vercel runtime. Same-origin proxying also reduces cross-site cookie and CORS failures.

**How to apply:** Deploy the backend first, set `NEXT_PUBLIC_API_URL=/api/v1` and `BACKEND_INTERNAL_URL=https://<public-backend-host>` on each Vercel Next.js app, and redeploy. Keep database credentials only on the backend; the backend uses `DATABASE_URL` for Supabase PostgreSQL and must allow exact frontend origins for any direct API callers.