# Pharmacy OS — System Guide

This document is the operational and technical source of truth for agents and
developers working on Pharmacy OS. Read it before changing code. It describes
the product we are building, the architecture that exists today, the
authentication contract, the data model, deployment boundaries, and the rules
for extending the system safely.

The most important distinction in this document is:

- **Implemented:** behavior that is currently wired and reachable in the code.
- **Scaffolded:** code, schema, or UI that exists but is not fully connected.
- **Target:** the product behavior we are intentionally building toward.

Do not describe scaffolded or target behavior as working until the complete
path from database to API to frontend has been verified.

---

## 1. Product definition

Pharmacy OS is a multi-tenant pharmacy operations platform. It is intended to
serve companies or holding groups that operate one or more pharmacies, with
branches, employees, products, inventory, permissions, attendance, reports,
and operational analytics.

The business hierarchy is:

```text
Company / holding group
  ├── Company users and administrators
  ├── Pharmacies
  │     ├── Branches
  │     │     ├── Employees
  │     │     ├── Inventory
  │     │     └── Attendance
  │     └── Pharmacy-specific settings
  ├── Roles and permissions
  ├── Audit history
  └── Reports and analytics
```

The system is not a frontend-only dashboard. The Go API is the authority for
business data, authentication, sessions, tenancy, and permissions. The
Next.js applications are clients of that API.

### Product surfaces

| Surface | Location | Responsibility |
| --- | --- | --- |
| Marketing site | `frontend/apps/marketing` | Public product pages, pricing, privacy, terms |
| Admin dashboard | `frontend/apps/admin-dashboard` | Companies, pharmacies/accounts, company users, permissions, analytics, settings |
| Pharmacy application | `frontend/apps/pharmacy-app` | Daily pharmacy operations: inventory, branches, employees, attendance, reports, settings |
| Backend API | `backend` | Authentication, sessions, tenant-aware business API, persistence, jobs |
| PostgreSQL | External PostgreSQL/Supabase provider | Durable application data and Go-owned authentication data |

---

## 2. Repository map

```text
.
├── .replit                         # Replit modules, workflow, ports, publishing
├── replit.md                       # Collaborator-facing setup notes
├── SYSTEM_GUIDE.md                 # This document
├── backend/
│   ├── cmd/server/main.go          # API process entrypoint
│   ├── internal/
│   │   ├── auth/                   # Go-owned authentication and session logic
│   │   ├── config/                 # Environment configuration
│   │   ├── handlers/               # HTTP handlers and route setup
│   │   ├── jobs/                   # Background job/worker scaffolding
│   │   ├── middleware/             # CORS, tenant, role, permission, logging helpers
│   │   ├── models/                 # Domain models and permission types
│   │   ├── repository/             # PostgreSQL access
│   │   └── services/               # Business logic
│   ├── migrations/                 # SQL schema and indexes
│   ├── tests/integration/          # Integration tests (currently not compiling fully)
│   ├── go.mod / go.sum             # Go dependencies
│   └── vendor/                     # Vendored Go dependencies used by publishing
└── frontend/
    ├── apps/pharmacy-app/          # Next.js pharmacy client
    ├── apps/admin-dashboard/       # Next.js administration client
    ├── apps/marketing/             # Next.js public client
    └── .env.example                # Frontend environment examples
```

The frontend applications are intentionally independently deployable to
Vercel. Do not turn them into one runtime or move them into the Go process
without an explicit architectural decision.

---

## 3. Runtime and deployment

### Development

The Replit backend workflow is:

```bash
cd backend && go run ./cmd/server
```

The API listens on port `8080`. Health endpoints:

```text
GET /
GET /health
GET /api/v1/health
```

The current Replit workflow is named `Backend API`. The frontend apps are
normally developed/deployed independently from their Vercel root directories:

```text
frontend/apps/pharmacy-app
frontend/apps/admin-dashboard
frontend/apps/marketing
```

### Production publishing

The Replit publishing configuration in `.replit` builds a static production
binary with vendored dependencies and runs it:

```bash
cd backend
CGO_ENABLED=0 go build -mod=vendor -o ../pharmacy-api ./cmd/server
```

The production deployment is configured as autoscale and listens on `8080`.
The published backend URL is not known until publishing completes. Never
invent a production URL from a project name or development domain.

### Frontend-to-backend connection

The Vercel applications use the public backend API URL:

```env
NEXT_PUBLIC_API_URL=https://<published-backend-domain>/api/v1
```

This value is public configuration, not a secret. It must be set at Vercel
build time for `pharmacy-app` and `admin-dashboard`; changing it requires a
new frontend deployment.

The backend must allow the exact frontend origins through `CORS_ORIGINS`,
without trailing slashes:

```env
CORS_ORIGINS=https://pharmacy-app.example,https://admin-dashboard.example
```

The frontend sends cookies with requests. Therefore CORS must allow credentials,
and production cookies must be secure. This is a browser/API connection, not a
secret-key connection.

---

## 4. Environment configuration

The canonical examples are:

- `backend/.env.example`
- `frontend/.env.example`
- `replit.md`
- `.replit` production user environment

Backend variables:

| Variable | Purpose | Secret? |
| --- | --- | --- |
| `PORT` | HTTP listen port; default `8080` | No |
| `APP_ENV` | `development`, `staging`, or `production` | No |
| `DATABASE_URL` | PostgreSQL connection string | Yes |
| `RIVER_DSN` | Optional PostgreSQL queue connection; defaults in documented setup | Yes |
| `BREVO_API_KEY` | Transactional email provider key | Yes |
| `MAIL_FROM_EMAIL` | Verified sender email | No, but operationally sensitive |
| `MAIL_FROM_NAME` | Email sender display name | No |
| `PUBLIC_APP_URL` | Frontend URL used in email links | No |
| `AUTH_COOKIE_SECURE` | Enables secure production cookies | No |
| `AUTH_COOKIE_DOMAIN` | Optional cookie domain | No |
| `CORS_ORIGINS` | Comma-separated exact frontend origins | No |
| `MAX_REQUEST_SIZE` | Maximum request body size | No |

Never put database URLs, API keys, session secrets, or provider credentials in
source control or any `NEXT_PUBLIC_*` variable. Never request a secret value in
chat. Use workspace secret management.

The current Go authentication implementation does not use Vercel as an
identity provider. Any external provider key, if introduced later, belongs in
the backend boundary only.

---

## 5. Backend architecture

The backend entrypoint is `backend/cmd/server/main.go`:

1. Load environment configuration.
2. Create a `pgxpool.Pool`.
3. Ping PostgreSQL before starting HTTP.
4. Construct the HTTP handler container.
5. Start Gin on `PORT`.

The intended request path is:

```text
HTTP request
  → CORS / recovery / logging
  → authentication
  → tenant selection
  → role and permission checks
  → handler
  → service
  → repository
  → PostgreSQL transaction/query
```

### Package responsibilities

#### `internal/handlers`

HTTP boundary. Handlers should:

- Parse and validate request input.
- Obtain authenticated identity and tenant context.
- Call a service.
- Map domain errors to stable HTTP status and error codes.
- Return a documented response shape.

Handlers should not contain large SQL queries or business workflows.

#### `internal/services`

Business rules and use cases. Services should:

- Enforce invariants.
- Coordinate multiple repositories.
- Own transaction boundaries when a use case changes multiple tables.
- Avoid depending on Gin request objects.
- Return typed/domain errors where possible.

#### `internal/repository`

PostgreSQL access. Repositories should:

- Use the shared `pgxpool.Pool`.
- Parameterize every query.
- Apply tenant filters in every tenant-owned query.
- Keep pagination and ordering deterministic.
- Return domain data, not HTTP responses.

#### `internal/middleware`

Cross-cutting request protection:

- CORS.
- Authentication compatibility helpers.
- Company/tenant context.
- Role and permission checks.
- Logging and recovery.

Do not bypass middleware by trusting IDs supplied by the frontend.

#### `internal/jobs`

Background job scaffolding exists for work that should not block an HTTP
request, such as email, reports, cleanup, or other long-running operations.
Workers must be made explicit and observable before relying on them in
production.

### Current route reality

The active route registration is in:

```text
backend/internal/handlers/handler.go
```

The currently registered routes are health endpoints, the auth routes provided
by `internal/auth`, and the protected company-management slice:

```text
GET    /api/v1/companies
GET    /api/v1/companies/:id
GET    /api/v1/companies/:id/summary
PUT    /api/v1/companies/:id
PATCH  /api/v1/companies/:id/status
DELETE /api/v1/companies/:id
```

These routes use the same opaque session middleware as `/auth/me`, adapt the
authenticated principal into company permission context, and never register
the legacy company JWT middleware. Non-super-admin users are scoped to their
own company. Domain handler files still exist for pharmacies, inventory,
employees, branches, attendance, and dashboard, but their availability must
be verified in `SetupRoutes` before calling them live.

The frontend API clients already reference paths such as:

```text
/api/v1/companies
/api/v1/companies/:id/users
/api/v1/companies/:id/accounts
/api/v1/dashboard/stats
/api/v1/dashboard/activity
```

Do not assume these routes work solely because a client method or handler file
exists. Add and verify the complete route-to-database path before exposing a
feature.

---

## 6. Authentication and session contract

Authentication is owned by the Go API. The browser clients do not store
access tokens in localStorage and do not manage password verification.

### Login

Company/admin login uses:

```json
{
  "email": "user@example.com",
  "password": "••••••••",
  "account_type": "company_user"
}
```

Pharmacy/employee login uses:

```json
{
  "email": "employee@example.com",
  "password": "••••••••",
  "account_type": "employee"
}
```

The backend looks up the principal in `company_users` or `employees`, checks
status and email verification, validates bcrypt password hashes, records login
state, creates a database-backed session, and sets cookies.

### Cookies

The current cookie names are:

```text
pharmacy_access  — HttpOnly short-lived access session
pharmacy_refresh — HttpOnly refresh session scoped to auth paths
pharmacy_csrf    — readable CSRF token used by the browser client
```

Production cookies use `Secure` and `SameSite=None` so the Vercel frontend can
call the separately hosted backend. This requires exact CORS origins and
`credentials: include`.

### Authenticated requests

The backend checks the access cookie first. A Bearer token is retained for
server-to-server clients, not as the primary browser mechanism.

The authentication middleware:

1. Extracts the access cookie or Bearer token.
2. Hashes the opaque token.
3. Looks up a non-revoked, non-expired session.
4. Loads the principal from the appropriate table.
5. Places identity fields in request context.

The Next.js clients hydrate their user from `/auth/me` in a shared
`AuthProvider`, guard dashboard route groups, and retry one protected request
after a successful `/auth/refresh`. They must continue to use
`credentials: include`; no browser token storage is part of this contract.

The current session table stores token hashes, expiry timestamps, principal
type/id, user-agent, IP, revocation, and refresh-family information. Refresh
rotation is transactionally protected.

### CSRF

State-changing auth endpoints require the `pharmacy_csrf` cookie value in the
`X-CSRF-Token` header. Frontend API clients read the non-HttpOnly cookie and
send the header for non-GET requests.

Do not remove CSRF checks just because CORS exists. CORS and CSRF protect
different boundaries.

### Auth endpoints

The active Go auth handler defines:

```text
POST /api/v1/auth/login
POST /api/v1/auth/register
POST /api/v1/auth/refresh
POST /api/v1/auth/logout
GET  /api/v1/auth/me
POST /api/v1/auth/logout-all
POST /api/v1/auth/change-password
POST /api/v1/auth/forgot-password
POST /api/v1/auth/reset-password
POST /api/v1/auth/verify-email
POST /api/v1/auth/resend-verification
```

Error responses use a stable shape such as:

```json
{
  "error": "invalid_credentials",
  "code": "INVALID_CREDENTIALS",
  "message": "Invalid email or password"
}
```

Preserve error codes when extending the frontend; user-facing text can change
without breaking client behavior.

---

## 7. Frontend architecture and client contract

Both operational clients use a small local API client:

```text
frontend/apps/pharmacy-app/src/lib/api.ts
frontend/apps/admin-dashboard/src/lib/api.ts
```

The clients:

- Build URLs from `NEXT_PUBLIC_API_URL`.
- Send JSON.
- Use `credentials: 'include'`.
- Read `pharmacy_csrf` for mutating requests.
- Do not persist bearer tokens.
- Convert non-2xx responses to errors.

The admin dashboard has an auth hook that hydrates user state through
`GET /auth/me`. The pharmacy app auth hook is currently a placeholder and must
be completed before treating the pharmacy dashboard as production-ready.

When adding a frontend feature:

1. Define the backend contract first.
2. Add typed request/response types.
3. Add an API client method.
4. Handle loading, empty, error, and unauthorized states.
5. Keep tenant and permission decisions on the backend.
6. Never use mock fallback data that can make a failed API look healthy.

The frontend must not:

- Query PostgreSQL directly.
- Trust a company/pharmacy/branch ID from the URL without backend authorization.
- Store backend session tokens in localStorage.
- Put a secret in `NEXT_PUBLIC_*`.
- Treat a successful page render as proof that the API request succeeded.

---

## 8. Domain and database model

The SQL migrations define the intended operational model. Important domain
groups include:

### Organization and tenancy

```text
companies
company_users
pharmacies
branches
employees
permissions / company permissions
```

Tenant-owned data must always be constrained by the authenticated company,
pharmacy, and/or branch context. A frontend-supplied ID is only a selector, not
an authorization decision.

### Product and inventory

```text
global_products
unit_conversions
pharmacy_products
inventory_batches
stock_movements
```

The distinction is intentional:

- A global product is the catalog definition.
- A pharmacy product is that product's local configuration.
- A batch tracks expiry and quantity.
- A stock movement explains how quantity changed.

Inventory writes should use database transactions and create an auditable
movement record instead of silently overwriting quantities.

### Attendance and audit

Attendance belongs to employees and branches. Audit data should explain who
changed what, for which tenant, and when. Reports should read from durable
records and should not become a second source of truth.

### Authentication

The Go-owned auth migration adds password/account state to employees and creates:

```text
auth_sessions
auth_email_tokens
```

Apply and verify migrations in the correct environment before using auth or
domain features. The server currently expects the database to be reachable at
startup; it does not run migrations automatically.

---

## 9. Multi-tenancy and permissions

The intended identity carries:

```text
principal_type
principal_id
company_id
pharmacy_id
branch_id
role
permission_version
```

Every protected use case should answer all of these questions:

1. Who is the caller?
2. Which company owns the requested record?
3. Which pharmacy and branch are in scope?
4. Does the caller's role permit the operation?
5. Does the record belong to that scope?

Tenant isolation must be enforced server-side in middleware, service rules,
and repository queries. PostgreSQL row-level security exists in portions of the
schema, but application authorization must still be correct and tested.

Permission caches, when used, must have bounded size and TTL and must respect
permission version changes. Never cache authorization indefinitely.

---

## 10. Scaling principles

The first scaling goal is a correct modular monolith, not premature
microservices.

### Keep the HTTP layer stateless

Multiple backend instances should be able to serve requests. Durable state
belongs in PostgreSQL or an explicit shared cache/queue, not process memory.

### Protect PostgreSQL

- Use one shared, tuned pool per process.
- Bound pool size against database capacity.
- Index tenant filters, foreign keys, lookup fields, expiry, and timestamps.
- Paginate every list endpoint.
- Avoid unbounded joins and `SELECT *`.
- Use transactions for inventory and multi-table business operations.
- Measure slow queries before adding a cache.

### Separate interactive and asynchronous work

User requests should return quickly. Email delivery, exports, large reports,
cleanup, and bulk operations belong in background jobs with retries,
idempotency, and observable failure states.

### Make APIs safe to retry

Mutating operations should define idempotency behavior where retries are
possible. Stock movements especially must not be duplicated because of a
network retry.

### Add observability before load

Before claiming readiness for very high concurrency, add:

- Request IDs.
- Structured logs.
- Latency and error metrics.
- Database pool metrics.
- Queue depth and failure metrics.
- Audit events for sensitive operations.
- Load tests for login, inventory reads, and inventory writes.

Autoscaling compute does not remove PostgreSQL, email, queue, or rate-limit
bottlenecks. Scale the whole dependency chain.

---

## 11. Current gaps to track honestly

These are known from the current code and must not be hidden from future
agents:

1. Domain handlers/services/repositories exist, but route registration is
   incomplete. Verify `backend/internal/handlers/handler.go` before claiming a
   domain API is live.
2. The admin client references companies, users, accounts, and dashboard paths
   that require complete backend wiring and authorization.
3. The pharmacy app authentication hook is still a placeholder.
4. Frontend auth state and route protection need a shared production-safe
   strategy; each hook instance should not independently create inconsistent
   session state.
5. Access sessions expire after a short TTL; a coordinated refresh-on-401
   client flow must be implemented and tested.
6. The backend starts only after a database ping but does not run migrations,
   start all workers, or install graceful shutdown handling in the entrypoint.
7. `config.Validate` and some configuration fields exist but are not all
   enforced in startup.
8. The imported integration test suite currently has compile errors and cannot
   yet serve as a complete `go test ./...` gate.
9. README endpoint lists may describe the target API rather than the currently
   registered API. Confirm code before relying on documentation.

Do not "fix" these by silently replacing the architecture or adding a second
authentication system. Address them one vertical slice at a time.

---

## 12. Safe feature-development workflow

For every new module or capability:

### Step 1 — Define the use case

Write down the actor, tenant scope, permission, state transitions, audit
requirements, and expected API behavior.

### Step 2 — Define the data contract

Decide schema changes, constraints, indexes, pagination, and transaction
boundaries. Add a migration; do not edit production data manually.

### Step 3 — Implement backend layers

Implement in this order:

```text
model/types
→ repository
→ service/use case
→ handler
→ middleware/permission checks
→ route registration
```

### Step 4 — Verify the API independently

Test success, validation errors, unauthorized access, cross-tenant access,
duplicate requests, empty results, and database failures before building the
screen.

### Step 5 — Implement the frontend client and screen

Add typed API methods, loading/empty/error states, optimistic behavior only
when safe, and no fake fallback that masks outages.

### Step 6 — Verify the complete path

Verify:

```text
Vercel app
→ CORS
→ cookies/session
→ route
→ permission
→ service
→ repository
→ database
```

### Step 7 — Update this guide

When a feature becomes truly live, update its status in this document and
record the route, permission, migration, and frontend entry point.

---

## 13. Agent instructions

Any future agent should:

1. Read `SYSTEM_GUIDE.md`, `replit.md`, and the relevant code before editing.
2. Verify current code instead of trusting a README or a placeholder file.
3. Preserve the Go backend, Next.js clients, PostgreSQL, and cookie-based auth
   boundaries unless a deliberate migration is approved.
4. Never expose or ask for secret values in chat.
5. Never put backend secrets in frontend code or `NEXT_PUBLIC_*`.
6. Keep tenant and permission checks in the backend.
7. Prefer a complete vertical slice over broad disconnected scaffolding.
8. Use migrations for schema changes.
9. Run the narrowest relevant build/tests, then verify the whole changed flow.
10. Update this document when the actual architecture or operational contract
    changes.

This guide is a living technical contract. If it conflicts with the code,
inspect the code, resolve the discrepancy explicitly, and then update the
guide so the next agent does not repeat the confusion.