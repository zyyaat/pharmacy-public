# Pharmacy Product Domain Design

> **Status:** Discussion draft — no database migration or application behavior should be
> implemented from this document until the open decisions are confirmed.
>
> **Scope:** Product catalog, pharmaceutical classification, packaging hierarchy,
> sellable units, inventory representation, and the future POS contract.

## 1. Product vision

Pharmacy OS is not a generic ERP with a few configurable fields. The product model
must understand pharmacy operations by default:

- Employees select from prepared pharmaceutical classifications and units.
- Employees do not invent categories, dosage forms, or packaging rules while working.
- A product can have a real packaging hierarchy, such as:
  - one box contains four strips;
  - one strip contains ten tablets.
- The POS can sell a complete package or an allowed partial package.
- Inventory and invoices remain mathematically consistent when a package is opened.
- The model must support future pharmacy workflows without being tied to a single
  product example.

The first implementation phase is limited to the product and inventory foundation.
POS screens, sales documents, purchasing, and reports are future consumers of this
foundation and are not part of the first implementation.

## 2. The core distinction: dosage form vs. packaging

These concepts must not be mixed:

### Dosage form

What the medicine physically is:

- tablet
- capsule
- syrup
- drops
- injection
- cream
- ointment
- inhaler
- suppository
- and other pharmacy-specific forms

### Packaging level

How the product is physically packaged and sold:

- box
- strip/blister
- bottle
- tube
- vial
- ampoule
- piece
- kit
- and other controlled packaging levels

For example, `tablet` is the dosage form. `box` and `strip` are packaging levels.
The product record should therefore not treat `box` as the dosage form or assume that
all tablets have the same packaging.

## 3. Example of the intended behavior

Example product:

- Product: a tablet medicine
- Dosage form: tablet
- Packaging: one box contains four strips
- Optional lower level: one strip contains ten tablets

If the smallest permitted sellable unit is a strip:

- inventory is normalized to strips;
- `4 strips` is represented to the employee as `1 full box`;
- `3 strips` is represented as `3 strips`, not as `0.75 box`;
- the POS offers:
  - full box
  - one strip
  - two strips
  - three strips
- the POS must not offer `4 strips` as a second name for a full box.

If the pharmacy allows tablets to be sold individually, the canonical inventory unit
can instead be the tablet:

- one strip = ten tablets;
- one box = four strips = forty tablets;
- the POS may offer a full box, strips, and tablets only if those sale levels are
  explicitly enabled for that product.

The important rule is:

> The canonical inventory unit is the smallest unit that this pharmacy is allowed
> to sell for this product, not automatically the smallest physical object.

This avoids forcing every product to be tracked as tablets when the pharmacy only
sells full boxes and strips.

## 4. How quantities should be stored

The system should store one authoritative quantity per stock location and batch in a
canonical unit. Display quantities are derived from the packaging hierarchy.

For a box containing four strips:

| Canonical quantity | Employee-facing display |
|---:|---|
| 0 | 0 full boxes, 0 strips |
| 1 | 1 strip |
| 3 | 3 strips |
| 4 | 1 full box |
| 5 | 1 full box + 1 strip |
| 7 | 1 full box + 3 strips |
| 8 | 2 full boxes |

The system must not keep independent, manually-updated columns for both “boxes” and
“strips” as the source of truth. That would eventually create contradictions. It
should keep the normalized quantity and calculate the package breakdown, with
transactional updates for every stock change.

For products whose canonical unit can be fractional, such as liquids or measured
materials, the model must use exact decimal arithmetic. Floating-point values must
not be used for money or stock quantities.

## 5. Unit conversion rules

The conversion model should represent an ordered product-specific hierarchy, not only
an arbitrary pair of enum values.

Conceptually:

```text
box
  contains 4 strips
    each strip contains 10 tablets
```

Each level needs:

- a controlled unit label;
- its position in the hierarchy;
- how many lower-level units it contains;
- whether it is a complete package;
- whether it is allowed to be sold;
- whether it is the canonical inventory unit;
- an optional barcode;
- optional price and pricing behavior.

Conversions belong to the product because packaging differs by manufacturer and SKU.
The system must never assume that every box contains the same number of strips or
that every strip contains the same number of tablets.

## 6. Pharmacy-owned products and controlled options

The product catalog belongs to the pharmacy. It is not a global catalog owned by
`super_admin`, and `super_admin` is not the business owner of a pharmacy's products,
packaging, prices, or stock.

The user working inside the pharmacy is the person who adds and edits the product.
The exact pharmacy-role permission can be defined separately, but the data ownership
boundary is clear: the product is tenant-scoped to its pharmacy.

Employees should select classification and unit labels from prepared system options
instead of inventing arbitrary values during routine work. This does **not** make
the product itself global. It only keeps the vocabulary consistent.

### System-provided options

These are reusable options supplied by the application:

- product categories;
- dosage forms;
- packaging/unit types;
- prescription rules;
- storage requirements;
- controlled-substance classifications;
- allowed sale-unit policies.

The system options are not a shared product record. They are the available building
blocks from which each pharmacy creates its own products.

### Pharmacy-owned product definition

The pharmacy user creates and edits:

- name and commercial identity;
- generic name and active ingredients;
- strength/concentration;
- manufacturer;
- category;
- dosage form;
- barcode and national code;
- packaging hierarchy;
- allowed sale units;
- canonical inventory unit.

The pharmacy user also owns:

- enabled/discontinued state;
- purchase cost;
- selling prices;
- tax behavior;
- reorder thresholds;
- branch/location;
- preferred supplier;
- whether a lower package level is allowed to be sold.

The number of units inside a package is also part of this pharmacy-owned product
definition. For example, the pharmacy user may define that this particular product's
box contains four strips. It must not be assumed from a generic global product
record.

## 7. Pricing rules to preserve

The POS must never calculate a price by blindly dividing a displayed box price unless
that is the configured pricing policy.

The future model should support:

1. A base price for the canonical sale unit.
2. Derived prices for larger package levels.
3. An explicit override for a package level when the pharmacy wants a package discount
   or a different commercial price.
4. Exact money arithmetic with a defined currency and rounding policy.

Example:

- strip price: 12.00
- four strips imply a calculated box price of 48.00
- the pharmacy may explicitly override the box price to 45.00
- the POS still converts the sold box to four canonical units for stock.

The price calculation and the stock conversion are related but not the same thing:
stock must follow the physical conversion, while price may follow a configured
commercial rule.

## 8. Inventory and batch principles

The product definition is not the same as stock. Stock belongs to a pharmacy branch
and is usually split by batch:

- lot/batch number;
- expiry date;
- received quantity in the canonical unit;
- remaining quantity in the canonical unit;
- purchase cost;
- supplier/reference;
- storage location;
- quarantine or quality status.

Every future POS or receiving operation should create an immutable stock movement
inside a transaction. A fast current-quantity snapshot may exist for reads, but the
movement ledger remains the audit source of truth.

For a sale:

```text
selected package quantity × package-to-canonical factor
    = stock quantity to deduct
```

For a box containing four strips:

```text
1 box sale → deduct 4 canonical strips
1 strip sale → deduct 1 canonical strip
```

The deduction must be atomic and must not allow a negative balance. Batch selection
should later follow a pharmacy-safe policy such as FEFO (first expiry, first out),
while respecting quarantine and reserved quantities.

## 9. Performance principles

“Millions of operations” should be handled through a correct data model first, then
through measured indexes and transaction design:

- integer or exact numeric quantities, never floating-point stock;
- canonical-unit arithmetic in the database transaction;
- indexed product lookup by tenant, active state, barcode, and normalized search;
- indexed batch lookup by product, branch, expiry, and available quantity;
- append-only movement records;
- idempotency keys for retried writes;
- short atomic stock updates;
- no recalculation of an entire movement history during every POS click;
- cache only derived/read data, never correctness-critical stock state.

The exact schema and indexes should be validated against real query patterns and
benchmarks rather than promising a number before the workload is measured.

## 10. Existing project findings

The repository already contains an earlier product/inventory foundation:

- `global_products`
- `unit_conversions`
- `pharmacy_products`
- `inventory_batches`
- `stock_movements`

It also contains an older, simpler medication model. The new work must not create a
second competing inventory system. The existing `global_products` table is a
technical artifact from a generic/shared-catalog direction and does not match the
confirmed pharmacy-owned business model as the final source of truth. Before
implementation we must decide whether to:

1. evolve the existing product/inventory foundation into pharmacy-owned products;
2. migrate and retire the old medication and shared-global-product models; or
3. keep a compatibility layer temporarily while all consumers move to the
   pharmacy-owned model.

The current `unit_conversions` table is a useful starting point, but by itself it
does not fully enforce:

- hierarchy order;
- canonical inventory unit;
- allowed sale units;
- full-package display semantics;
- package-specific pricing;
- product-level barcode per packaging level;
- pharmacy-specific sale policy.

## 11. Proposed conceptual entities

These are design concepts, not an instruction to create them yet:

1. **Controlled product categories**
2. **Controlled dosage forms**
3. **Controlled unit/packaging types**
4. **Pharmacy-owned product identity**
5. **Product packaging levels and containment rules**
6. **Pharmacy product pricing and operational settings**
7. **Branch inventory batches**
8. **Stock movement ledger**
9. **Future sales-line unit selection**

The implementation should use tenant-safe relationships throughout. A pharmacy must
never read or change another pharmacy's product settings, batches, or prices.

## 12. Decisions required before schema work

The following decisions are intentionally open:

1. Which existing pharmacy role is allowed to add and edit pharmacy products?
   This is a permission question inside the pharmacy, not a `super_admin` ownership
   question.
2. Is the canonical inventory unit the smallest permitted sale unit? This is the
   recommended rule.
3. For tablet products, should the initial release support:
   - box + strip only;
   - box + strip + tablet;
   - or any configured hierarchy?
4. Should the pharmacy user be able to edit package counts while editing the
   pharmacy-owned product? The current understanding is yes.
5. Should prices be derived by conversion by default with explicit package-level
   overrides?
6. Are batch number and expiry required for all medicines, optional for cosmetics and
   non-expiring goods, or controlled per category?
7. Which classifications must be present in the first curated catalog?
8. What are the initial currency, tax, and money-rounding rules?
9. Should the product barcode identify the whole product only, or can each packaging
   level have its own barcode?
10. Should partial packages be allowed per product, per pharmacy, or per branch?

No database migration should be written until these decisions are confirmed.