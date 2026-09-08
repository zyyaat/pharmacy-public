---
name: Production database provisioning
description: Replit publishing behavior when an imported app has a development database but no production database.
---

For an imported app using Replit PostgreSQL, a successful local connection does not guarantee that a production database exists. The first publish may build successfully but crash during startup if production provisioning has not been enabled in Publishing settings.

**Why:** Production queries reported that no production database existed, while the deployed process received a development-style Helium hostname and repeatedly failed its health check.

**How to apply:** Before debugging application database code, check whether Publishing → Production database settings has Create production database enabled. Do not copy development data into production unless the user explicitly confirms it is safe.