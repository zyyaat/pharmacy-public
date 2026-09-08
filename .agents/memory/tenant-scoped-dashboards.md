---
name: Tenant-scoped dashboards
description: Rules for keeping dashboard and pharmacy data isolated by the authenticated session.
---

The platform uses one shared PostgreSQL database with logical tenant isolation: dashboard and pharmacy reads must derive company/pharmacy scope from the authenticated principal, and client-supplied tenant identifiers are not an authorization boundary. Empty results are valid empty states; failures must remain visible rather than becoming demo data.

**Why:** The imported project exposed hardcoded dashboard values and placeholder handlers, which could make one account appear to see another account's data and could hide backend failures.

**How to apply:** When adding dashboard, inventory, employee, branch, attendance, or activity endpoints, scope every query using session-derived identifiers and make the UI distinguish loading, empty, and error states. Do not create demo rows to make a tenant look populated.