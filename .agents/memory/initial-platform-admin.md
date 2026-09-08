---
name: Initial platform admin provisioning
description: Operational rule for creating the first Super Admin when production has no existing platform administrator.
---

The first production Super Admin must be provisioned through the backend's one-time startup bootstrap, not by mutating the production database through the read-only database tooling. Production startup always validates a durable bootstrap state; a new database requires the managed password secret, while an initialized database starts without it. A database-level singleton constraint and immutable identity protection prevent a second or replacement Super Admin.

**Why:** Production SQL access through the database tooling is read-only, while platform admin routes intentionally require an existing Super Admin.

**How to apply:** Publish the schema and backend with the bootstrap secret for a new database, verify the account can log in, then remove the secret. If a new database is provisioned later, add the secret deliberately for that one-time initialization.