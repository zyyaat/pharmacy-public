'use client'

import { formatPiastres } from '@/lib/money'
import { extraStrengthLabel } from '@/lib/product'
import { formatSoldLine } from '@/lib/sales'
import type { ReceiptSettings, POSSaleDetail } from '@/lib/api'
import { useT } from '@/i18n/provider'
import { fmtDateTime } from '@/i18n/format'

export interface ReceiptPharmacy {
  name: string
  city?: string
  address?: string
  phone?: string
}

export interface ReceiptData {
  sale: {
    invoice_number: number
    created_at: string
    total_amount_piastres: number
    /** خصم الفاتورة بالقروش — يظهر سطراً مستقلاً فوق الإجمالي عند وجوده */
    discount_amount_piastres?: number
    /** فاتورة آجل على حساب عميل مسجل */
    payment_type?: 'cash' | 'credit'
    customer_name?: string
  }
  items: Array<{
    product_name: string
    /** تركيز الدواء — يُعرض بجانب الاسم إن لم يكن الاسم يحمل جرعة أصلاً */
    strength: string
    sale_unit: 'box' | 'strip'
    packaging_type?: 'WHOLE_ONLY' | 'BOX_STRIP'
    units_per_box: number
    quantity_base: number
    /** snapshot نية البيع (Final Decision 12) — يمرر للمنسق الموحد SSOT */
    sale_quantity?: number | null
    unit_price_piastres: number
    amount_piastres: number
  }>
}

function receiptDate(iso: string) {
  return fmtDateTime(iso, { dateStyle: 'short', timeStyle: 'short' })
}

/**
 * يركّب الاسم الظاهر في رأس الفاتورة من البادئة والاسم المسجّل:
 * بادئة تنتهي بنقطة تُلصق بالاسم مباشرة (صيدلية د. + محمد => صيدلية د.محمد)،
 * وغير ذلك تفصل بمسافة (صيدلية + محمد => صيدلية محمد). ولو الاسم المسجّل
 * يبدأ أصلاً بالبادئة فتُترك كما هو بلا تكرار (صيدلية + صيدلية النور).
 */
export function composePharmacyDisplayName(prefix: string, name: string): string {
  const cleanName = name.trim()
  const cleanPrefix = prefix.trim()
  if (!cleanPrefix) return cleanName
  if (cleanName.startsWith(cleanPrefix)) return cleanName
  return cleanPrefix.endsWith('.') ? `${cleanPrefix}${cleanName}` : `${cleanPrefix} ${cleanName}`
}

function Dashed() {
  return <div className="my-1.5 border-t border-dashed border-neutral-500" aria-hidden="true" />
}

/**
 * قالب إيصال حراري — نسخة واحدة. طباعة نسختين تتولد في ReceiptPrinter.
 * الألوان ثابتة رمادية/سوداء (الحرارية أحادية) والأبعاد بالمليمتر حسب الإعدادات.
 */
export default function ReceiptTemplate({
  data,
  pharmacy,
  cashierName,
  settings,
  showCopyLabel = false,
  copyLabel,
}: {
  data: ReceiptData
  pharmacy: ReceiptPharmacy
  cashierName?: string
  settings: ReceiptSettings
  showCopyLabel?: boolean
  copyLabel?: string
}) {
  const t = useT('pos')
  const compact = settings.paper_width_mm < 70 // 58mm: الأعمدة تضيق فتتكدد السطور
  const itemsCount = data.items.length
  const resolvedCopyLabel = copyLabel ?? t('copyCustomer')

  return (
    <div className="bg-white px-[3mm] py-[4mm] text-[#111]" style={{ fontSize: compact ? '11px' : '12.5px', lineHeight: 1.55 }}>
      {showCopyLabel && (
        <p className="mb-2 text-center font-bold tracking-wide text-neutral-600">— {resolvedCopyLabel} —</p>
      )}

      {/* الرأس — الاسم المركب من البادئة والاسم المسجّل */}
      <p className="text-center font-extrabold" style={{ fontSize: compact ? '15px' : '17px' }}>{composePharmacyDisplayName(settings.name_prefix, pharmacy.name) || t('fallbackPharmacyName')}</p>
      {settings.show_address && (pharmacy.address || pharmacy.city) && (
        <p className="mt-0.5 text-center text-neutral-700">{[pharmacy.address, pharmacy.city].filter(Boolean).join(t('addressCitySeparator'))}</p>
      )}
      {settings.show_phone && pharmacy.phone && (
        <p className="text-center text-neutral-700" dir="ltr">{pharmacy.phone}</p>
      )}

      <Dashed />

      {/* بيانات الفاتورة */}
      <Row label={t('invoiceNo')} value={`INV-${data.sale.invoice_number}`} />
      <Row label={t('date')} value={<span suppressHydrationWarning>{receiptDate(data.sale.created_at)}</span>} />
      {settings.show_cashier && cashierName && <Row label={t('cashier')} value={cashierName} />}

      <Dashed />

      {/* الأصناف */}
      <div className="space-y-1">
        {data.items.map((item, index) => {
          const strengthLabel = extraStrengthLabel(item.product_name, item.strength)
          // الكمية عبر المنسق الموحد SSOT (Final Decision 12): نية البيع من
          // الـsnapshot عند توفره وإلا fallback القص — بلا منسق محلي ثالث.
          const quantityText = formatSoldLine({
            sale_unit: item.sale_unit,
            packaging_type: item.packaging_type ?? 'BOX_STRIP',
            units_per_box: item.units_per_box,
            quantity_base: item.quantity_base,
            sale_quantity: item.sale_quantity,
          })
          return compact ? (
            <div key={index}>
              <p className="font-semibold leading-snug">
                {item.product_name}
                {strengthLabel && <span className="font-normal text-neutral-500"> {strengthLabel}</span>}
              </p>
              <div className="flex items-baseline justify-between gap-2">
                <span className="text-neutral-700">{quantityText} × {formatPiastres(item.unit_price_piastres)}</span>
                <span className="font-bold">{formatPiastres(item.amount_piastres)}</span>
              </div>
            </div>
          ) : (
            <div key={index} className="flex items-baseline justify-between gap-2">
              <span className="min-w-0 shrink font-semibold leading-snug">
                {item.product_name}
                {strengthLabel && <span className="font-normal text-neutral-500"> {strengthLabel}</span>}
              </span>
              <span className="shrink-0 whitespace-nowrap text-neutral-700">{quantityText}</span>
              <span className="w-[22%] shrink-0 whitespace-nowrap text-start font-bold">{formatPiastres(item.amount_piastres)}</span>
            </div>
          )
        })}
      </div>

      <Dashed />

      {/* الخصم ثم الإجمالي — الإجمالي هو الصافي بعد الخصم دائماً */}
      {!!data.sale.discount_amount_piastres && data.sale.discount_amount_piastres > 0 && (
        <div className="flex items-baseline justify-between">
          <span className="font-semibold text-neutral-700">{t('discount')}</span>
          <span className="font-bold">-{formatPiastres(data.sale.discount_amount_piastres)}</span>
        </div>
      )}
      <div className="flex items-baseline justify-between">
        <span className="font-bold">{t('totalWithItems', { items: itemsCount === 1 ? t('totalItemsOne') : t('totalItemsMany', { count: itemsCount }) })}</span>
        <span className="font-extrabold" style={{ fontSize: compact ? '15px' : '16.5px' }}>{formatPiastres(data.sale.total_amount_piastres)}</span>
      </div>

      <Dashed />

      {/* فاتورة آجل — تُقيد على حساب العميل في صفحة حسابات العملاء */}
      {data.sale.payment_type === 'credit' && (
        <p className="mt-1 text-center font-semibold">{data.sale.customer_name ? t('creditInvoiceWithCustomer', { name: data.sale.customer_name }) : t('creditInvoice')}</p>
      )}

      {/* الذيل */}
      {settings.show_thank_you && settings.thank_you_text && (
        <p className="text-center font-semibold">{settings.thank_you_text}</p>
      )}
      {settings.show_return_policy && settings.return_policy_text && (
        <p className="mt-0.5 text-center text-neutral-700">{settings.return_policy_text}</p>
      )}
    </div>
  )
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-2">
      <span className="text-neutral-700">{label}</span>
      <span className="font-semibold">{value}</span>
    </div>
  )
}

/** يحول تفاصيل الفاتورة القادمة من الخادم إلى بيانات الإيصال */
export function saleDetailToReceipt(detail: POSSaleDetail): ReceiptData {
  return {
    sale: {
      invoice_number: detail.sale.invoice_number,
      created_at: detail.sale.created_at,
      total_amount_piastres: detail.sale.total_amount_piastres,
      discount_amount_piastres: detail.sale.discount_amount_piastres,
      payment_type: detail.sale.payment_type,
      customer_name: detail.sale.customer_name,
    },
    items: detail.items.map((item) => ({
      product_name: item.product_name,
      strength: item.strength ?? '',
      sale_unit: item.sale_unit,
      packaging_type: item.packaging_type,
      units_per_box: item.units_per_box,
      quantity_base: item.quantity_base,
      sale_quantity: item.sale_quantity,
      unit_price_piastres: item.unit_price_piastres,
      amount_piastres: item.amount_piastres,
    })),
  }
}
