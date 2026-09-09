'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { FormEvent, useState } from 'react'
import { ArrowRight } from 'lucide-react'
import { ApiError, pharmacyApi, type CreatePharmacyProductInput } from '@/lib/api'
import { ProductFormFields, readProductFormCommon } from '@/components/inventory/product-form-fields'
import { Button } from '@/components/ui'

export default function NewProductPage() {
  const router = useRouter()
  const [packagingType, setPackagingType] = useState<CreatePharmacyProductInput['packaging_type']>('WHOLE_ONLY')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError(null)
    const form = event.currentTarget
    const data = new FormData(form)

    const common = readProductFormCommon(data, packagingType)
    if (common.error || !common.values) {
      setError(common.error || 'تعذر قراءة بيانات النموذج')
      return
    }

    const value: CreatePharmacyProductInput = {
      ...common.values,
      initial_boxes: Number(data.get('initial_boxes') || 0),
      initial_strips: packagingType === 'BOX_STRIP' ? Number(data.get('initial_strips') || 0) : 0,
      batch_number: String(data.get('batch_number') || '').trim(),
      expiry_date: String(data.get('expiry_date') || ''),
    }
    setSaving(true)
    try {
      await pharmacyApi.createProduct(value)
      router.push('/inventory')
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : 'تعذر حفظ المنتج')
      setSaving(false)
    }
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div className="flex items-center gap-3">
        <Button asChild variant="ghost" size="icon"><Link href="/inventory" aria-label="العودة للمخزون"><ArrowRight className="h-5 w-5" /></Link></Button>
        <div>
          <h1 className="text-2xl font-bold">إضافة منتج جديد</h1>
          <p className="mt-2 text-sm text-muted-foreground">نوع التعبئة يحدد تلقائيًا طريقة البيع والمخزون.</p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-6">
        <ProductFormFields packagingType={packagingType} onPackagingTypeChange={setPackagingType} showInitialStock />

        {error && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
        <div className="flex justify-end gap-3">
          <Button asChild variant="outline"><Link href="/inventory">إلغاء</Link></Button>
          <Button type="submit" loading={saving}>حفظ المنتج</Button>
        </div>
      </form>
    </div>
  )
}
