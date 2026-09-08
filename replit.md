# Pharmacy OS monorepo

This repository contains the Pharmacy OS frontend monorepo and backend:

- `frontend/apps/pharmacy-app/` — the main Next.js pharmacy application.
- `frontend/apps/admin-dashboard/` — the Next.js admin dashboard.
- `frontend/apps/marketing/` — the Next.js public marketing site.
- `backend/` — the Go 1.25 Gin API and its migrations.
- `SYSTEM_GUIDE.md` — the full product, architecture, authentication, data model,
  deployment, and agent-development guide. Read it before changing the project.
- `docs/architecture-readiness.md` — the current scale-readiness decision,
  confirmed gaps, and mandatory workflow for future agents.

## Delivery priority

For high-volume work, follow `docs/architecture-readiness.md` in order:
transactional and idempotent inventory writes first, tenant/permission
regression tests second, then measured pool/observability/query improvements.
Do not introduce distributed infrastructure without a baseline load test.

## Replit setup

Each frontend has its own independent workflow. The selected Run workflow is
`Project`, which starts all frontend workflows and the shared backend together.
The frontend workflows can also run independently on dedicated ports,
while `Backend API` provides the shared Go API:

```bash
cd frontend/apps/admin-dashboard && npm ci
cd frontend/apps/pharmacy-app && npm ci
cd frontend/apps/marketing && npm ci
cd backend && GOTOOLCHAIN=auto GOSUMDB=sum.golang.org GOPROXY=https://proxy.golang.org,direct GOFLAGS=-mod=vendor go run ./cmd/server
cd frontend/apps/admin-dashboard && NEXT_PUBLIC_API_URL=/api/v1 npm run dev -- -p 5000
```

The backend can also be started with one stable command from the repository
root:

```bash
cd backend && GOTOOLCHAIN=auto GOSUMDB=sum.golang.org GOPROXY=https://proxy.golang.org,direct GOFLAGS=-mod=vendor go run ./cmd/server
```

The Replit-managed PostgreSQL database is connected automatically through `DATABASE_URL` and the `PG*` environment variables. The active development schema is created by migrations `00000000000001_foundation.sql` through `00000000000013_company_actor_cleanup.sql`; `00000000000001_init.sql` and `00000000000002_permissions_system.sql` are older legacy/placeholder files and are not part of the active migration sequence. Apply the active migrations in filename order to a new development database before using the API.

The frontend workflows use separate local and external preview ports, so they do
not overwrite one another:

- `Admin Dashboard` — `frontend/apps/admin-dashboard` on local/external port `5000`.
- `Pharmacy App` — `frontend/apps/pharmacy-app` on local `5001`, external `3000`.
- `Marketing Site` — `frontend/apps/marketing` on local `5002`, external `3001`.
- `Backend API` — the shared Go API on port `8080`.

Choose `5000`, `3000`, or `3001` from the Preview port selector when viewing a
specific frontend.

The frontend apps proxy `/api/v1/*` to the backend during Replit development, so browser requests do not use `localhost`.

Production publishing builds and runs a non-ignored binary:

```bash
cd backend && go build -o ../pharmacy-api ./cmd/server
./pharmacy-api
```

The backend API listens on port `8080` by default. Health checks:

- `GET /health`
- `GET /api/v1/health`

For the backend, configure these environment variables in Replit Secrets:

- `DATABASE_URL` — Replit-managed PostgreSQL connection string; injected automatically.
- `RIVER_DSN` — optional PostgreSQL queue connection string; defaults to the application database URL in the documented setup.
- `BREVO_API_KEY` — Brevo API key for email verification and password reset.
- `MAIL_FROM_EMAIL` — verified Brevo sender email.
- `MAIL_FROM_NAME` — optional sender name.
- `PUBLIC_APP_URL` — public Vercel URL used in email links.
- `AUTH_COOKIE_SECURE` — set to `true` in production.

Set `CORS_ORIGINS` to the exact Vercel frontend origins, without trailing slashes, for example:

```text
https://your-frontend.vercel.app
```

Apply the active migrations, including `backend/migrations/00000000000006_go_auth.sql`, before using the auth endpoints.
The Go API owns authentication: passwords, email tokens, opaque sessions, cookie
rotation, revocation, CSRF validation, and realm separation. Platform and
pharmacy apps use separate login/me/refresh/logout routes and cookies. Platform
sessions are restricted to `super_admin`; pharmacy sessions are restricted to
employees and assigned company managers, never `super_admin`. The frontend must
use `credentials: include`; it must not store auth tokens in localStorage.

## Frontend

The three frontend apps remain independently deployable on Vercel. Use these Vercel Root Directories:

- `frontend/apps/pharmacy-app`
- `frontend/apps/admin-dashboard`
- `frontend/apps/marketing`

The frontend repository was refreshed from its latest upstream commit. Its app-specific settings were not modified here.

After publishing the backend, set `NEXT_PUBLIC_API_URL` in the Vercel environment
for `pharmacy-app` and `admin-dashboard` to the published backend URL followed by
`/api/v1` (for example, `https://your-backend.replit.app/api/v1`). Keep the backend
`CORS_ORIGINS` values aligned with the exact Vercel origins, without trailing slashes.

For the Marketing Site, set `NEXT_PUBLIC_PHARMACY_APP_URL` to the public Pharmacy
App origin (for example, `https://pharmacy-app-theta-nine.vercel.app`). The
Marketing CTA and `/register` redirect must always send users to the Pharmacy App
registration page, not to a route on the Marketing Site.