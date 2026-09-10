// Shared display helpers for the sales history tab.
//
// Quantities are stored in base units (strips for BOX_STRIP products, the
// product unit otherwise). Money is integer piastres and is formatted
// exclusively through formatPiastres in lib/money.ts.

import type { POSSaleStatus } from './api'

export function saleStatusLabel(status: string): string {
  switch (status) {
    case 'returned':
      return 'مرتجعة بالكامل'
    case 'partially_returned':
      return 'مرتجعة جزئياً'
    default:
      return 'مكتملة'
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

const dateFormatter = new Intl.DateTimeFormat('ar-EG-u-nu-latn', {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
})

const timeFormatter = new Intl.DateTimeFormat('ar-EG-u-nu-latn', {
  hour: 'numeric',
  minute: '2-digit',
})

export function formatSaleDate(iso: string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return dateFormatter.format(date)
}

export function formatSaleTime(iso: string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return ''
  return timeFormatter.format(date)
}

/** Label of one base unit for the product, e.g. "شريط" or "وحدة". */
export function baseUnitLabel(packagingType: string): string {
  return packagingType === 'BOX_STRIP' ? 'شريط' : 'وحدة'
}

/** Arabic-aware quantity text for a base-unit count, e.g. "5 شرائط". */
export function formatBaseQuantity(packagingType: string, quantity: number): string {
  const unit = baseUnitLabel(packagingType)
  if (quantity === 1) return unit === 'شريط' ? 'شريط واحد' : 'وحدة واحدة'
  if (quantity === 2) return unit === 'شريط' ? 'شريطان' : `وحدتان`
  return `${quantity} ${unit === 'شريط' ? 'شرائط' : 'وحدات'}`
}

/** How the line was sold: box lines show the box count, strip lines the strip count. */
export function formatSoldQuantity(saleUnit: 'box' | 'strip', packagingType: string, unitsPerBox: number, quantityBase: number): string {
  if (saleUnit === 'box') {
    if (quantityBase === 1) return 'علبة واحدة'
    if (quantityBase === 2) return 'علبتان'
    return `${quantityBase} علب`
  }
  return formatBaseQuantity(packagingType, quantityBase)
}

/** "1 box = 10 strips" hint for the return input. */
export function boxConversionHint(packagingType: string, unitsPerBox: number): string | null {
  if (packagingType !== 'BOX_STRIP' || unitsPerBox < 2) return null
  return `العلبة = ${unitsPerBox} ${baseUnitLabel(packagingType)}`
}
