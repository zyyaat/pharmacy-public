'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { FormEvent, useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { ArrowRight, PencilLine, Printer } from 'lucide-react'
import { ApiError, pharmacyApi, type LabelSettingsData, type LabelSize, type LabelTemplate, type PharmacyProductDetail, type UpdatePharmacyProductInput } from '@/lib/api'
import { ProductFormFields, readProductFormCommon, type ProductFormDefaults } from '@/components/inventory/product-form-fields'
import LabelPrintManager, { type LabelPrintJob } from '@/components/labels/label-print-manager'
import { piastresToEGPInput } from '@/lib/money'
import { useT } from '@/i18n/provider'
import { Button } from '@/components/ui'
import { RequirePermission } from '@/components/permissions/gate'

/**
 * تعديل المنتج بنفس صفحة الإضافة بالضبط (طلب المستخدم: «التعديل يدخلني على نفس
 * صفحة الإضافة ونلغي المودال خالص») — نفس الحقول الكاملة بلا نافذة منبثقة.
 * المخزون الافتتاحي غير معروض هنا: الكميات تُدار من صفحة المخزون عبر
 * تعديل المخزون حتى يبقى سجل الحركات المرجع الواحد للكميات.
 */
export default function EditProductPage() {
  const t = useT('inventory')
  const router = useRouter()
  const params = useParams<{ productId: string }>()
  const productId = params?.productId

  const [detail, setDetail] = useState<PharmacyProductDetail | null>(null)
  const [defaults, setDefaults] = useState<ProductFormDefaults | null>(null)
  const [barcodeType, setBarcodeType] = useState('')
  const [packagingType, setPackagingType] = useState<'WHOLE_ONLY' | 'BOX_STRIP'>('WHOLE_ONLY')
  const [isActive, setIsActive] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [printJob, setPrintJob] = useState<LabelPrintJob | null>(null)
  const [printingLabel, setPrintingLabel] = useState(false)

  useEffect(() => {
    if (!productId) return
    let cancelled = false
    pharmacyApi
      .getProduct(productId)
      .then((response) => {
        if (cancelled) return
        const d = response.data
        setDetail(d)
        setPackagingType(d.packaging_type)
        setIsActive(d.is_active)
        setBarcodeType(d.barcode_type ?? '')
        setDefaults({
          name: d.name,
          generic_name: d.generic_name,
          dosage_form: d.dosage_form || 'tablet',
          strength: d.strength ?? '',
          barcode: d.barcode,
          units_per_box: String(d.units_per_box),
          cost_price: piastresToEGPInput(d.cost_price_piastres),
          selling_price: piastresToEGPInput(d.selling_price_piastres),
          partial_selling_price: d.partial_selling_price_piastres != null ? piastresToEGPInput(d.partial_selling_price_piastres) : '',
          min_stock_level: String(d.min_stock_level),
          initial_boxes: '0',
          initial_strips: '0',
          batch_number: '',
          expiry_date: '',
        })
      })
      .catch((err) => !cancelled && setLoadError(err instanceof Error ? err.message : t('error_load_product')))
    return () => {
      cancelled = true
    }
  }, [productId, t])

  // توليد باركود داخلي لمنتج قائم بلا باركود (Final Decision 6): خادمي حصراً
  // عبر نقطة النهاية المخصصة، والرمز المولّد يُعرض في الحقل فورًا بشارة «داخلي».
  async function handleGenerateBarcode(): Promise<string | null> {
    if (!productId) return null
    setError(null)
    setNotice(null)
    try {
      const response = await pharmacyApi.generateProductBarcode(productId)
      const { barcode, barcode_type } = response.data
      setBarcodeType(barcode_type)
      setDefaults((prev) => (prev ? { ...prev, barcode } : prev))
      setDetail((prev) => (prev ? { ...prev, barcode, barcode_type } : prev))
      setNotice(t('barcode_generated_notice'))
      return barcode
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : t('barcode_generate_error'))
      return null
    }
  }

  // طباعة ملصق من شاشة المنتج (إجراء الطباعة من المخزون): يُحمّل القالب
  // الافتراضي من إعدادات الملصقات ويطبع نسخة واحدة بمقاسه الحقيقي.
  async function handlePrintLabel() {
    if (!detail || !defaults?.barcode || printingLabel) return
    setPrintingLabel(true)
    try {
      const [labels, context] = await Promise.all([
        pharmacyApi.getLabelSettings(),
        pharmacyApi.getContext().catch(() => null),
      ])
      const data: LabelSettingsData = labels.data
      const template: LabelTemplate | undefined =
        data.templates.find((tpl) => tpl.id === data.default_template_id) ?? data.templates[0]
      const size: LabelSize | undefined = data.sizes.find((s) => s.id === template?.size_id) ?? data.sizes[0]
      if (!template || !size) return
      setPrintJob({
        jobId: `label-${detail.id}-${Date.now()}`,
        template,
        size,
        pharmacyName: context?.pharmacy?.name ?? '',
        products: [
          {
            name: detail.name,
            generic_name: detail.generic_name,
            strength: detail.strength ?? '',
            barcode: defaults.barcode,
            selling_price_piastres: detail.selling_price_piastres,
            partial_selling_price_piastres: detail.partial_selling_price_piastres ?? 0,
            units_per_box: detail.units_per_box,
            packaging_type: detail.packaging_type,
          },
        ],
      })
    } finally {
      setPrintingLabel(false)
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!productId) return
    setError(null)
    const common = readProductFormCommon(new FormData(event.currentTarget), packagingType)
    if (common.error || !common.values) {
      setError(common.error || t('error_read_form'))
      return
    }
    const payload: UpdatePharmacyProductInput = {
      ...common.values,
      is_active: isActive,
    }
    setSaving(true)
    try {
      await pharmacyApi.updateProduct(productId, payload)
      router.push('/inventory')
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : t('error_save_edits'))
      setSaving(false)
    }
  }

  if (loadError) {
    return (
      <div className="mx-auto max-w-4xl space-y-4">
        <BackHeader name={null} />
        <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{loadError}</p>
        <Button asChild variant="outline"><Link href="/inventory">{t('back_to_inventory')}</Link></Button>
      </div>
    )
  }
  return (
    <RequirePermission anyOf={['inventory.manage_products']}>
    <div className="mx-auto max-w-4xl space-y-6">
      <BackHeader name={detail?.name ?? null} />

      {(!detail || !defaults) ? (
        <p className="py-10 text-center text-sm text-muted-foreground">{t('loading_product')}</p>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-6" key={detail.id}>
          <ProductFormFields
            packagingType={packagingType}
            onPackagingTypeChange={setPackagingType}
            defaults={defaults}
            barcodeType={barcodeType}
            onGenerateBarcode={defaults.barcode ? undefined : handleGenerateBarcode}
          />

          {/* طباعة ملصق المنتج بالقالب الافتراضي (إجراء الطباعة من المخزون) */}
          {defaults.barcode && (
            <div>
              <Button type="button" variant="outline" loading={printingLabel} onClick={handlePrintLabel}>
                <Printer className="h-4 w-4 rtl-flip" />
                {t('barcode_print_label')}
              </Button>
            </div>
          )}

          <label className="flex cursor-pointer items-center gap-2 rounded-xl border p-4 text-sm">
            <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} className="h-4 w-4" />
            {t('active_label')}
          </label>

          {error && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
          {notice && <p className="rounded-lg border border-primary/30 bg-primary/10 p-3 text-sm text-primary">{notice}</p>}
          <div className="flex justify-end gap-3">
            <Button asChild variant="outline"><Link href="/inventory">{t('cancel')}</Link></Button>
            <Button type="submit" loading={saving}>{t('save_edits')}</Button>
          </div>
        </form>
      )}

      {/* بوابة الطباعة: تُركّب الملصق خارج هيكل التطبيق وقت فتح نافذة الطباعة */}
      <LabelPrintManager job={printJob} />
    </div>
    </RequirePermission>
  )
}

function BackHeader({ name }: { name: string | null }) {
  const t = useT('inventory')
  return (
    <div className="flex items-center gap-3">
      <Button asChild variant="ghost" size="icon"><Link href="/inventory" aria-label={t('back_to_inventory')}><ArrowRight className="rtl-flip h-5 w-5" /></Link></Button>
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold"><PencilLine className="h-5 w-5 text-primary" />{name ? t('edit_title_named', { name }) : t('edit_title')}</h1>
        <p className="mt-2 text-sm text-muted-foreground">{t('edit_subtitle')}</p>
      </div>
    </div>
  )
}
