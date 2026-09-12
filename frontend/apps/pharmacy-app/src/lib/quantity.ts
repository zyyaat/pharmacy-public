/**
 * Quantity representation core — the SSOT for how a sold line is displayed
 * (barcode-design-v2-review.md §5.3 + §6, Final Decisions 11/12).
 *
 * PURE module: no React, no i18n, no money. It maps a stored sale line to
 * the STRUCTURAL intent («2 boxes», «7 strips», «1 unit») and both platform
 * formatters (web lib/sales.ts, mobile format.dart) translate that intent
 * with their own catalogs. The same golden vectors (scripts/golden_quantity_vectors.json)
 * pin this contract on both platforms.
 *
 * Rules locked by the approved design:
 *  1. The invoice shows the SALE INTENT, never a forced conversion to the
 *     largest unit: «2 علبة» stays «2 علبة», «7 شرائط» stays «7 شرائط».
 *  2. The write-time snapshot (sale_quantity + units_per_box_snapshot) is
 *     the only source for interpreting an invoice; a later packaging edit
 *     can never reinterpret yesterday's invoice.
 *  3. Pre-snapshot rows (sale_quantity == null) use the documented legacy
 *     fallback: strip lines read the base directly, box lines derive
 *     base / units_per_box (current) — the report's transition clause.
 *  4. Display only: money, discounts and returns keep reading
 *     base_quantity / piastres and NEVER call this module.
 */

export interface SoldLineInput {
  sale_unit: 'box' | 'strip'
  /** WHOLE_ONLY | BOX_STRIP */
  packaging_type: string
  /** snapshot عند توفره، وإلا القيمة الحالية للمنتج (صفوف قديمة) */
  units_per_box: number
  /** الكمية بوحدات القاعدة (شرائط/عبوات) كما تخزنها قاعدة البيانات */
  quantity_base: number
  /** snapshot نية الكاشير (migration 24) — null للصفوف القديمة */
  sale_quantity?: number | null
}

export type QuantityUnit = 'box' | 'strip' | 'unit'

export interface QuantityIntent {
  unit: QuantityUnit
  count: number
}

/**
 * Reduce one stored sale line to its display intent. This is the single
 * place where the box/base arithmetic lives for DISPLAY purposes.
 */
export function soldQuantityIntent(line: SoldLineInput): QuantityIntent {
  const isStripLine = line.sale_unit === 'strip'
  if (isStripLine) {
    // Strip lines: the intent IS the base count (never rewritten).
    // The snapshot (when present) must equal it; base wins on any mismatch
    // because returns and money are computed on the base.
    return {
      unit: line.packaging_type === 'BOX_STRIP' ? 'strip' : 'unit',
      count: line.quantity_base,
    }
  }
  // Box lines: the intent is the number of boxes the cashier entered.
  if (line.sale_quantity != null && line.sale_quantity > 0) {
    return { unit: 'box', count: line.sale_quantity }
  }
  // Legacy fallback (pre-snapshot rows): derive with the packaging at hand.
  const boxes = line.units_per_box > 0 ? line.quantity_base / line.units_per_box : line.quantity_base
  return { unit: 'box', count: boxes }
}
