---
name: Authentication query qualification
description: SQL safety rule for authentication lookups that join company and pharmacy data.
---

Authentication lookup queries that join multiple tables must qualify every shared column, especially identity fields such as email.

**Why:** An unqualified email predicate in a joined login query caused PostgreSQL to reject valid credentials with an ambiguous-column error; the handler then exposed a misleading invalid-credentials response.

**How to apply:** When changing auth joins, qualify predicates with their source alias and preserve integration coverage for register, logout, login, and session lookup.