// Task 48 — تسميات حركات المخزون عبر كتالوج i18n (مساحة movements).
// وحدات عميل فقط — الترجمة وقت الاستدعاء عبر runtimeTranslator حتى تتغير
// التسميات فور تبديل اللغة دون إعادة تحميل، مع بقاء توقيع الدوال كما هو
// لصالح كل المستدعين (سجل الحركات + تقارير الحركات).
import type { BadgeProps } from '@/components/ui'
import type { StockMovementType } from '@/lib/api'
import { runtimeTranslator } from '@/i18n/runtime'
import { fmtDate, fmtNumber } from '@/i18n/format'

/** مفاتيح تسميات أنواع حركات المخزون في مساحة movements */
const movementTypeKeys: Record<StockMovementType, string> = {
  purchase: 'type_purchase',
  sale: 'type_sale',
  return_to_supplier: 'type_return_to_supplier',
  return_from_customer: 'type_return_from_customer',
  adjustment: 'type_adjustment',
  transfer_in: 'type_transfer_in',
  transfer_out: 'type_transfer_out',
  expiry_writeoff: 'type_expiry_writeoff',
  damage_writeoff: 'type_damage_writeoff',
  theft_loss: 'type_theft_loss',
  production_input: 'type_production_input',
  production_output: 'type_production_output',
}

export function movementTypeLabel(type: StockMovementType): string {
  const t = runtimeTranslator('movements')
  const key = movementTypeKeys[type]
  return key ? t(key) : type
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
  return fmtDate(iso, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })
}

export function formatMovementTime(iso: string): string {
  return fmtDate(iso, {
    hour: '2-digit',
    minute: '2-digit',
  })
}

/** تنسيق الكمية بالوحدة الأساسية (شريط/علبة) — الوحدات الأخرى تبقى كما وردت من الخادم */
export function formatMovementQuantity(quantity: number, unit: string): string {
  const abs = Math.abs(quantity)
  const rounded = Number.isInteger(abs) ? fmtNumber(abs) : fmtNumber(abs, { maximumFractionDigits: 2 })
  const t = runtimeTranslator('movements')
  const unitLabel = unit === 'strip' ? t('unit_strip') : unit === 'box' ? t('unit_box') : unit
  return `${rounded} ${unitLabel}`
}
