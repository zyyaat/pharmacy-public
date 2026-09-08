---
name: Pharmacy product ownership
description: The product catalog belongs to each pharmacy, not to the platform administrator or a shared global catalog.
---

The product catalog is tenant-scoped to the pharmacy. The user working inside the
pharmacy creates and edits its products, packaging hierarchy, package counts,
allowed sale units, prices, and stock settings. `super_admin` owns platform
administration, not the business definition of pharmacy products.

System-provided categories, dosage forms, and packaging labels may be controlled
options for consistent vocabulary, but they must not turn a pharmacy's product into
a shared global product.

**Why:** A central ERP-style catalog does not match Pharmacy OS's domain: products
belong to the pharmacy and their packaging can differ by product, manufacturer, or
pharmacy operation.

**How to apply:** Before changing the existing product schema, treat
`global_products` as a legacy/shared-catalog direction to evaluate for migration or
compatibility. Preserve tenant isolation and do not route product ownership through
`super_admin`.