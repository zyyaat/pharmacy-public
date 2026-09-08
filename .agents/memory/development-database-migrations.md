---
name: Development database migrations
description: The development PostgreSQL database may start empty and does not apply repository SQL migrations automatically.
---

The backend can start against an empty development database because it does not run migrations at startup. Before testing database-backed features, apply the active SQL migrations in order, excluding the legacy init migration.

**Why:** A healthy API process does not prove that the schema exists; requests can fail later when a handler reaches a missing table or view.

**How to apply:** Use the database tooling against development only, and keep schema changes represented as ordered files under backend/migrations for publish-time synchronization.