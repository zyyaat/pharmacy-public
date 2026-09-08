---
name: Company-user ledger actors
description: Durable audit and deletion rules for pharmacy operations performed by company-level users.
---

Company-level pharmacy operators must be recorded in a separate nullable actor column when an existing ledger column is foreign-keyed to pharmacy employees. The employee actor remains populated for employee operations, while the company-user actor identifies company-admin and company-manager operations.

**Why:** Company users and pharmacy employees are intentionally separate authentication domains. Reusing a company-user UUID in an employee foreign key breaks product creation, inventory movements, and sales. Leaving a company-user actor foreign key as `SET NULL` also violates the ledger's “one actor required” constraint when a company is deleted.

**How to apply:** For company-owned ledgers, keep the employee actor nullable, add a company-user actor reference, require one actor at insert time, and use cascade-safe ownership cleanup for company deletion.