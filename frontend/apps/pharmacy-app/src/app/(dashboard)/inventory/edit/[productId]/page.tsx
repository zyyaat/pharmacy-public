'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { FormEvent, useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { ArrowRight, PencilLine } from 'lucide-react'
import { ApiError, pharmacyApi, type PharmacyProductDetail, type UpdatePharmacyProductInput } from '@/lib/api'
import { ProductFormFields, readProductFormCommon, type ProductFormDefaults } from '@/components/inventory/product-form-fields'
import { piastresToEGPInput } from '@/lib/money'
import { Button } from '@/components/ui'

/**
 * تعديل المنتج بنفس صفحة الإضافة بالضبط (طلب المستخدم: «التعديل يدخلني على نفس
 * صفحة الإضافة ونلغي المودال خالص») — نفس الحقول الكاملة بلا نافذة منبثقة.
 * المخزون الافتتاحي غير معروض هنا: الكميات تُدار من صفحة المخزون عبر
 * تعديل المخزون حتى يبقى سجل الحركات المرجع الواحد للكميات.
 */
export default function EditProductPage() {
  const router = useRouter()
  const params = useParams<{ productId: string }>()
  const productId = params?.productId

  const [detail, setDetail] = useState<PharmacyProductDetail | null>(null)
  const [defaults, setDefaults] = useState<ProductFormDefaults | null>(null)
  const [packagingType, setPackagingType] = useState<'WHOLE_ONLY' | 'BOX_STRIP'>('WHOLE_ONLY')
  const [isActive, setIsActive] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

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
      .catch((err) => !cancelled && setLoadError(err instanceof Error ? err.message : 'تعذر تحميل بيانات المنتج'))
    return () => {
      cancelled = true
    }
  }, [productId])

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!productId) return
    setError(null)
    const common = readProductFormCommon(new FormData(event.currentTarget), packagingType)
    if (common.error || !common.values) {
      setError(common.error || 'تعذر قراءة بيانات النموذج')
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
      setError(cause instanceof ApiError ? cause.message : 'تعذر حفظ التعديلات')
      setSaving(false)
    }
  }

  if (loadError) {
    return (
      <div className="mx-auto max-w-4xl space-y-4">
        <BackHeader name={null} />
        <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{loadError}</p>
        <Button asChild variant="outline"><Link href="/inventory">العودة للمخزون</Link></Button>
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <BackHeader name={detail?.name ?? null} />

      {(!detail || !defaults) ? (
        <p className="py-10 text-center text-sm text-muted-foreground">جاري تحميل بيانات المنتج...</p>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-6" key={detail.id}>
          <ProductFormFields packagingType={packagingType} onPackagingTypeChange={setPackagingType} defaults={defaults} />

          <label className="flex cursor-pointer items-center gap-2 rounded-xl border p-4 text-sm">
            <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} className="h-4 w-4" />
            المنتج مُفعّل ويظهر في نقطة البيع
          </label>

          {error && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
          <div className="flex justify-end gap-3">
            <Button asChild variant="outline"><Link href="/inventory">إلغاء</Link></Button>
            <Button type="submit" loading={saving}>حفظ التعديلات</Button>
          </div>
        </form>
      )}
    </div>
  )
}

function BackHeader({ name }: { name: string | null }) {
  return (
    <div className="flex items-center gap-3">
      <Button asChild variant="ghost" size="icon"><Link href="/inventory" aria-label="العودة للمخزون"><ArrowRight className="h-5 w-5" /></Link></Button>
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold"><PencilLine className="h-5 w-5 text-primary" />تعديل المنتج{name ? `: ${name}` : ''}</h1>
        <p className="mt-2 text-sm text-muted-foreground">نفس بيانات الإضافة كاملة — بلا نوافذ منبثقة.</p>
      </div>
    </div>
  )
}
