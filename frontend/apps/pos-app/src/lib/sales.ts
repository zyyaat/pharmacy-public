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

/** How the line was sold: box lines show the box count, strip lines the strip count. */
export function formatSoldQuantity(saleUnit: 'box' | 'strip', packagingType: string, unitsPerBox: number, quantityBase: number): string {
  const t = runtimeTranslator('sales')
  if (saleUnit === 'box') {
    if (quantityBase === 1) return t('oneBox')
    if (quantityBase === 2) return t('twoBoxes')
    return t('manyBoxes', { count: quantityBase })
  }
  return formatBaseQuantity(packagingType, quantityBase)
}

/** "1 box = 10 strips" hint for the return input. */
export function boxConversionHint(packagingType: string, unitsPerBox: number): string | null {
  if (packagingType !== 'BOX_STRIP' || unitsPerBox < 2) return null
  return runtimeTranslator('sales')('boxHint', { count: unitsPerBox, unit: baseUnitLabel(packagingType) })
}
