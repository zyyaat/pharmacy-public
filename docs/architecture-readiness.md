# Pharmacy OS architecture readiness

**Assessment date:** 2026-09-06

## Executive decision

Pharmacy OS has a credible **modular-monolith foundation**, but it is **not
ready to promise millions of real-time transactions**. It can continue as a
careful foundation build and pilot system. It must not be marketed as
high-scale production infrastructure until the P0 gates below are complete and
verified with concurrency and failure testing.

The current position is:

- **Architecture direction:** sound.
- **Business correctness:** not yet proven for sales and inventory writes.
- **Horizontal scaling:** possible in principle, not operationally complete.
- **Real-time million-transaction readiness:** no.

The main risk is not Go or PostgreSQL. The main risk is that several domain
paths are still placeholders or incompletely registered, while the system
already exposes UI surfaces that look operational.

## Confirmed current state

### What is already a good foundation

- Go/Gin is an appropriate choice for a stateless API with predictable
  latency.
- PostgreSQL and `pgxpool` are appropriate for transactional inventory and
  financial data.
- The active schema has separate companies, company users, pharmacies,
  branches, employees, products, batches, stock movements, audit logs, and
  authentication sessions.
- Authentication uses opaque server-side sessions and cookie rotation rather
  than storing bearer tokens in browser storage.
- The current authentication principal carries tenant context. Protected
  pharmacy reads generally derive scope from the principal instead of trusting
  a pharmacy ID supplied by the browser.
- The schema has row-level-security concepts, tenant indexes, stock movement
  history, and `FOR UPDATE` usage in some attendance/authentication paths.
- The migration decision is clear: the active migrations are the source of
  truth; the old backup schema must not be imported wholesale.

### Confirmed defects and incomplete areas

1. **Admin `/pharmacies` was a real 404.** The sidebar pointed to a route that
   did not exist. The backend `pharmacy_handler.go` also contains placeholder
   CRUD handlers and is not a real platform pharmacy API.
2. **The 404 is now handled safely.** The sidebar no longer advertises a
   nonexistent dedicated page, and old `/pharmacies` links redirect to the
   existing `/accounts` page. No fake pharmacy records or fake API response
   were introduced.
3. **Route registration is incomplete relative to the codebase.** A handler or
   repository file is not evidence that an endpoint is live. Every endpoint
   must be verified in `backend/internal/handlers/handler.go`.
4. **Several repositories/services remain stubs.** In particular, employee
   operations and older medication/inventory service paths contain TODO or
   placeholder implementations.
5. **The inventory safety contract is not yet centralized.** A stock movement
   repository explicitly expects a transaction, while batch quantity updates
   can be called separately. This is unsafe until one service owns the
   transaction, locking, movement creation, and idempotency behavior.
6. **The backend entrypoint is minimal.** It pings the database and starts the
   server, but does not yet provide a complete graceful-shutdown,
   worker-startup, pool-budget, or production-observability lifecycle.
7. **Legacy and central authentication code coexist.** The central auth path
   must remain the only production path; legacy handlers must be isolated,
   removed, or explicitly marked unreachable and covered by tests.
8. **The pharmacy frontend must be treated as incomplete until auth refresh,
   unauthorized handling, and protected-route behavior are tested end to end.**
9. **Admin screens are partly read-only despite presenting management
   controls.** Buttons such as create/edit/delete must not imply a capability
   until the corresponding authorized backend contract exists.

## Readiness gates

### P0 — correctness and security gates

These are required before real operational sales or stock management:

- One inventory write service owns a database transaction.
- The service locks the exact product/batch rows, validates available stock,
  appends an immutable stock movement, and updates any projection atomically.
- Every retryable mutation accepts and enforces an idempotency key with a
  durable uniqueness rule.
- Tenant scope is derived from the authenticated principal at every repository
  boundary; client IDs are selectors only.
- Role and permission checks use one policy layer. A role shortcut must not
  silently bypass sensitive permission rules.
- Company-scope middleware must have explicit commit/rollback tests for
  success, handler error, panic, and already-written responses.
- The central auth flow is the sole production flow, with tested access expiry,
  refresh rotation, revocation, CSRF, password change, and account lockout.
- Add automated tests for tenant isolation, permission denial, concurrent stock
  updates, duplicate mutations, and transaction rollback.

### P1 — scale and operations gates

- Replace deep `OFFSET` pagination with cursor/keyset pagination on large
  lists.
- Profile real queries with `EXPLAIN (ANALYZE, BUFFERS)` and add indexes based
  on measured plans, not guesses.
- Bound the PostgreSQL pool per process and calculate the total connection
  budget across all replicas.
- Move email, exports, reports, and bulk operations to durable queue workers
  with retries, idempotency, and visible failure state.
- Add request IDs, structured logs, latency/error metrics, database-pool
  metrics, queue depth metrics, and audit events for sensitive changes.
- Add rate limiting and abuse protection to login, refresh, password reset,
  search, and expensive report endpoints.
- Replace process-local authorization/cache state with a bounded shared or
  versioned strategy before horizontal scaling.
- Stop running dashboard-wide counts and joins on every request; introduce
  read models or pre-aggregated counters after query profiling.

### P2 — only after measured need

- Read replicas for genuinely read-heavy workloads.
- Partitioning for tables whose measured size and write/read patterns justify
  it.
- Regional deployment or service decomposition. Do not split the modular
  monolith merely because traffic is expected to grow.

## Required workflow for the next agent

1. **Orient before editing.** Read `SYSTEM_GUIDE.md`, this assessment, the
   relevant migration, and the current route registration. Search first; do
   not infer that a file is live from its name.
2. **Define the backend contract first.** Document auth requirement, tenant
   scope, permissions, request/response shape, error codes, pagination, and
   idempotency behavior before building UI.
3. **Implement in layers.** Keep the flow
   `route -> middleware -> handler -> service -> repository -> database`.
   Business invariants belong in the service/database transaction, not in
   React components.
4. **Make scope non-optional.** Derive company, pharmacy, and branch scope
   from the authenticated principal. Reject missing or mismatched scope
   explicitly.
5. **Make writes safe to retry.** Use one transaction for the business write,
   append-only audit/ledger data, row locks or an equivalent concurrency
   strategy, and a durable idempotency record.
6. **Do not hide incomplete behavior.** Never use mock fallback data, empty
   success responses, or UI controls for an endpoint that is not implemented.
   Return an explicit error or keep the control disabled.
7. **Test the failure modes, not only the happy path.** Every protected write
   needs tests for unauthorized, wrong tenant, wrong permission, duplicate
   retry, concurrent update, rollback, and database error.
8. **Verify the whole slice.** Run focused tests while editing, then run
   `go test ./...`, frontend type/build checks for the affected app, smoke-test
   the route through the Replit workflow, and inspect workflow/browser logs.
9. **Measure before claiming scale.** Add a reproducible load test with
   concurrency, p95/p99 latency, error rate, pool saturation, lock waits,
   queue lag, and database CPU/IO. A passing unit test is not a capacity
   certification.
10. **Keep migrations forward-only and intentional.** Do not import the old
    backup schema or mutate production data as a shortcut. Every schema change
    needs a migration, rollback consideration, and tenant/security review.

## Definition of done for a production slice

A slice is not complete until its backend route is registered, its contract is
typed in the client, loading/empty/error/unauthorized states exist in the UI,
tenant and permission tests pass, writes are transactional and retry-safe, the
affected workflows start cleanly, and the route has been smoke-tested through
the proxied preview.

## Immediate execution plan

This is the default order for the next implementation cycle. Do not skip to
distributed infrastructure before the earlier gates produce measurements.

### Execute now: correctness that also protects throughput

1. **Inventory write boundary**
   - Create one service method for receiving, selling, transferring, and
     adjusting stock.
   - Run the row lock, available-stock validation, stock movement insert,
     projection update, and audit event in one transaction.
   - Add a durable idempotency key for every external mutation.
   - Reject duplicate requests with the original result instead of performing
     the write twice.
2. **Security regression tests**
   - Test wrong company, wrong pharmacy, wrong branch, missing permission,
     inactive account, and session revocation.
   - Test transaction commit, handler error rollback, panic rollback, and
     responses that were already written.
3. **Route and contract inventory**
   - Maintain a table of every UI API call, registered backend route, auth
     requirement, tenant scope, and implementation status.
   - Remove or disable controls whose backend behavior is still a placeholder.

### Execute next: measured performance foundations

1. Configure explicit PostgreSQL pool limits, per-request timeouts, and
   graceful shutdown. Calculate the connection budget for one instance and for
   the expected replica count.
2. Add request IDs, structured logs, latency/error metrics, database pool
   metrics, and queue depth/failure metrics.
3. Profile the real list and dashboard queries with
   `EXPLAIN (ANALYZE, BUFFERS)`. Add only indexes justified by the plan.
4. Replace deep `OFFSET` pagination with keyset/cursor pagination on large,
   frequently accessed lists.
5. Move email, exports, reports, and bulk operations out of the request path
   into durable workers with retries and visible failure state.

### Execute after baseline load tests

- Add a shared distributed cache only for measured hot reads or permission
  data; define invalidation and bounded TTL first.
- Add read replicas only after identifying read saturation.
- Add partitioning only after table growth and query plans justify it.
- Consider service decomposition only when a bounded domain has an
  independently measured scaling or deployment need.

### Work-context text for future agents

Use the following as the default instruction when implementing new features:

> Build for a correct, observable modular monolith first. Do not add Redis,
> microservices, read replicas, or partitioning as a guess. Start with the
> backend contract and registered route, derive tenant scope from the
> authenticated principal, centralize role and permission checks, and make
> every mutation transactional and retry-safe. Measure query plans, pool
> saturation, lock waits, p95/p99 latency, and error rate before claiming a
> performance improvement. Never hide an incomplete endpoint with mock data or
> a successful empty response. A feature is complete only when its failure
> paths, tenant isolation, concurrency behavior, and proxied preview are
> tested.
