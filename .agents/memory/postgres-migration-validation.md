---
name: Imported PostgreSQL migration validation
description: Imported SQL migration chains may contain PostgreSQL-invalid indexes, constraints, comments, generated columns, or seed keys.
---

Validate an imported migration chain against the actual PostgreSQL version before treating documentation order as executable.

**Why:** Imported projects can contain migration files that were never run together on PostgreSQL; time-dependent partial indexes, partial unique constraints, and generated-column defaults fail at apply time.

**How to apply:** Use the documented active sequence, exclude explicitly marked legacy placeholders, apply to a clean development database, and fix schema-compatible SQL rather than weakening data constraints.