// Shared display helpers for the sales history tab.
//
// Quantities are stored in base units (strips for BOX_STRIP products, the
// product unit otherwise). Money is integer piastres and is formatted
// exclusively through formatPiastres in lib/money.ts.
//
// Task 48: every user-visible label comes from the 'sales' message catalog
// through the runtime translator (this module is outside React context), and
// date formatting goes through the central i18n format layer.

import type { POSSaleStatus } from './api'
import { fmtDate } from '@/i18n/format'
import { runtimeTranslator } from '@/i18n/runtime'
import { soldQuantityIntent, type SoldLineInput, type QuantityIntent } from './quantity'

export function saleStatusLabel(status: string): string {
  const t = runtimeTranslator('sales')
  switch (status) {
    case 'returned':
      return t('statusReturned')
    case 'partially_returned':
      return t('statusPartiallyReturned')
    default:
      return t('statusCompleted')
  }
}

export function saleStatusVariant(status: string): 'success' | 'warning' | 'destructive' {
  switch (status) {
    case 'returned':
      return 'destructive'
    case 'partially_returned':
      return 'warning'
    default:
      return 'success'
  }
}

export function formatSaleDate(iso: string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return fmtDate(date, { day: 'numeric', month: 'long', year: 'numeric' })
}

export function formatSaleTime(iso: string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return ''
  return fmtDate(date, { hour: 'numeric', minute: '2-digit' })
}

/** Label of one base unit for the product, e.g. "شريط" or "وحدة". */
export function baseUnitLabel(packagingType: string): string {
  const t = runtimeTranslator('sales')
  return packagingType === 'BOX_STRIP' ? t('unitStrip') : t('unitUnit')
}

/** Locale-aware quantity text for a base-unit count, e.g. "5 شرائط". */
export function formatBaseQuantity(packagingType: string, quantity: number): string {
  const t = runtimeTranslator('sales')
  const isStrip = packagingType === 'BOX_STRIP'
  if (quantity === 1) return isStrip ? t('oneStrip') : t('oneUnit')
  if (quantity === 2) return isStrip ? t('twoStrips') : t('twoUnits')
  return isStrip ? t('manyStrips', { count: quantity }) : t('manyUnits', { count: quantity })
}

/** كيفية العرض من نية الكمية عبر قواعد الجمع العربية الموحدة (SSOT §6). */
function formatIntent(intent: QuantityIntent): string {
  const t = runtimeTranslator('sales')
  if (intent.unit === 'box') {
    if (intent.count === 1) return t('oneBox')
    if (intent.count === 2) return t('twoBoxes')
    return t('manyBoxes', { count: intent.count })
  }
  if (intent.unit === 'strip') {
    if (intent.count === 1) return t('oneStrip')
    if (intent.count === 2) return t('twoStrips')
    return t('manyStrips', { count: intent.count })
  }
  if (intent.count === 1) return t('oneUnit')
  if (intent.count === 2) return t('twoUnits')
  return t('manyUnits', { count: intent.count })
}

/**
 * عرض سطر مبيع من مدخله الكامل — الواجهة الوحيدة للقوالب والصفحات (SSOT).
 * الصفوف الجديدة تُقرأ من snapshot الخادم، والقديمة عبر fallback موثق.
 */
export function formatSoldLine(line: SoldLineInput): string {
  return formatIntent(soldQuantityIntent(line))
}

/**
 * How the line was sold: box lines show the box count, strip lines the
 * strip count. Backward-compatible positional wrapper around formatSoldLine;
 * the old implementation had a real bug (displayed base as boxes on box
 * lines) — passing the snapshot through saleQuantity fixes new rows.
 */
export function formatSoldQuantity(
  saleUnit: 'box' | 'strip',
  packagingType: string,
  unitsPerBox: number,
  quantityBase: number,
  saleQuantity?: number | null,
): string {
  return formatSoldLine({ sale_unit: saleUnit, packaging_type: packagingType, units_per_box: unitsPerBox, quantity_base: quantityBase, sale_quantity: saleQuantity })
}

/** "1 box = 10 strips" hint for the return input. */
export function boxConversionHint(packagingType: string, unitsPerBox: number): string | null {
  if (packagingType !== 'BOX_STRIP' || unitsPerBox < 2) return null
  return runtimeTranslator('sales')('boxHint', { count: unitsPerBox, unit: baseUnitLabel(packagingType) })
}
