import type { BadgeProps } from '@/components/ui'
import type { StockMovementType } from '@/lib/api'

/** تسميات أنواع حركات المخزون بالعربية */
export const movementTypeLabels: Record<StockMovementType, string> = {
  purchase: 'شراء',
  sale: 'بيع',
  return_to_supplier: 'مرتجع للمورد',
  return_from_customer: 'استرجاع من عميل',
  adjustment: 'تسوية مخزون',
  transfer_in: 'تحويل وارد',
  transfer_out: 'تحويل صادر',
  expiry_writeoff: 'إعدام منتهي الصلاحية',
  damage_writeoff: 'إعدام تالف',
  theft_loss: 'فقد/سرقة',
  production_input: 'استهلاك تصنيع',
  production_output: 'إنتاج',
}

export function movementTypeLabel(type: StockMovementType): string {
  return movementTypeLabels[type] ?? type
}

export function movementTypeVariant(type: StockMovementType): BadgeProps['variant'] {
  switch (type) {
    case 'purchase':
    case 'return_from_customer':
    case 'transfer_in':
    case 'production_output':
      return 'success'
    case 'sale':
      return 'default'
    case 'return_to_supplier':
    case 'expiry_writeoff':
    case 'damage_writeoff':
    case 'theft_loss':
      return 'destructive'
    default:
      return 'secondary'
  }
}

/** وصف الحركة: داخل (+) أم خارج (-) المخزون */
export function movementDirection(quantity: number): 'in' | 'out' {
  return quantity >= 0 ? 'in' : 'out'
}

export function formatMovementDate(iso: string): string {
  return new Date(iso).toLocaleDateString('ar-EG-u-nu-latn', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })
}

export function formatMovementTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('ar-EG-u-nu-latn', {
    hour: '2-digit',
    minute: '2-digit',
  })
}

/** تنسيق الكمية بالوحدة الأساسية (شريط/وحدة) */
export function formatMovementQuantity(quantity: number, unit: string): string {
  const abs = Math.abs(quantity)
  const rounded = Number.isInteger(abs) ? abs.toLocaleString('ar-EG-u-nu-latn') : abs.toLocaleString('ar-EG-u-nu-latn', { maximumFractionDigits: 2 })
  const unitLabel = unit === 'strip' ? 'شريط' : unit === 'box' ? 'علبة' : unit
  return `${rounded} ${unitLabel}`
}
