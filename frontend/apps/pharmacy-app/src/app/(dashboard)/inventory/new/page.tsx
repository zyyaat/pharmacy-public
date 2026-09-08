'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { FormEvent, useState } from 'react'
import { ArrowRight, PackagePlus } from 'lucide-react'
import { ApiError, pharmacyApi, type CreatePharmacyProductInput } from '@/lib/api'
import { parseEGPToPiastres, piastresToEGPInput } from '@/lib/money'
import { Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Input } from '@/components/ui'

const dosageForms = [
  ['tablet', 'أقراص'],
  ['capsule', 'كبسولات'],
  ['syrup', 'شراب'],
  ['injection', 'حقن'],
  ['cream', 'كريم'],
  ['drop', 'قطرة'],
  ['inhaler', 'بخاخ'],
  ['other', 'أخرى'],
]

export default function NewProductPage() {
  const router = useRouter()
  const [packagingType, setPackagingType] = useState<CreatePharmacyProductInput['packaging_type']>('WHOLE_ONLY')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [priceError, setPriceError] = useState<string | null>(null)

  /** Suggest a strip price (half-up) whenever the user has not typed one yet. */
  function suggestStripPrice(form: HTMLFormElement) {
    const stripField = form.elements.namedItem('partial_selling_price') as HTMLInputElement | null
    if (!stripField || stripField.value.trim()) return
    const boxPiastres = parseEGPToPiastres((form.elements.namedItem('selling_price') as HTMLInputElement)?.value || '')
    const units = Number((form.elements.namedItem('units_per_box') as HTMLInputElement)?.value || 0)
    if (boxPiastres === null || units < 2) return
    stripField.value = piastresToEGPInput(Math.round(boxPiastres / units))
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setSaving(true)
    setError(null)
    setPriceError(null)
    const form = event.currentTarget
    const data = new FormData(form)

    const costPiastres = parseEGPToPiastres(String(data.get('cost_price') || ''))
    const sellingPiastres = parseEGPToPiastres(String(data.get('selling_price') || ''))
    const partialRaw = String(data.get('partial_selling_price') || '').trim()
    let partialPiastres: number | null = null
    if (packagingType === 'BOX_STRIP') {
      if (!partialRaw) {
        setPriceError('سعر بيع الشريط مطلوب للمنتجات التي تُباع بالشرائط (تم اقتراح قيمة تلقائياً — عدّلها إذا لزم).')
        setSaving(false)
        return
      }
      partialPiastres = parseEGPToPiastres(partialRaw)
      if (partialPiastres === null) {
        setPriceError('سعر بيع الشريط غير صالح. اكتب المبلغ بالجنيه مثل 17.55')
        setSaving(false)
        return
      }
    }
    if (costPiastres === null || sellingPiastres === null) {
      setPriceError('أسعار الشراء والبيع مطلوبة بالجنيه مثل 105.50')
      setSaving(false)
      return
    }

    const value: CreatePharmacyProductInput = {
      name: String(data.get('name') || '').trim(),
      generic_name: String(data.get('generic_name') || '').trim(),
      dosage_form: String(data.get('dosage_form') || 'tablet'),
      strength: String(data.get('strength') || '').trim(),
      barcode: String(data.get('barcode') || '').trim(),
      packaging_type: packagingType,
      units_per_box: packagingType === 'BOX_STRIP' ? Number(data.get('units_per_box') || 0) : 1,
      cost_price_piastres: costPiastres,
      selling_price_piastres: sellingPiastres,
      partial_selling_price_piastres: partialPiastres,
      min_stock_level: Number(data.get('min_stock_level') || 0),
      initial_boxes: Number(data.get('initial_boxes') || 0),
      initial_strips: packagingType === 'BOX_STRIP' ? Number(data.get('initial_strips') || 0) : 0,
      batch_number: String(data.get('batch_number') || '').trim(),
      expiry_date: String(data.get('expiry_date') || ''),
    }
    try {
      await pharmacyApi.createProduct(value)
      router.push('/inventory')
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : 'تعذر حفظ المنتج')
    } finally {
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
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><PackagePlus className="h-5 w-5 text-primary" />بيانات العلاج</CardTitle>
            <CardDescription>أدخل بيانات الصنف كما تظهر على العبوة والباركود الذي سيُستخدم في نقطة البيع.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 sm:grid-cols-2">
            <Input name="name" label="اسم العلاج" required placeholder="مثال: علاج معين" />
            <Input name="generic_name" label="المادة الفعالة / الاسم العلمي" placeholder="اختياري" />
            <div className="space-y-2">
              <label className="text-sm font-medium text-foreground/80">الشكل الدوائي</label>
              <select name="dosage_form" defaultValue="tablet" className="h-10 w-full rounded-lg border border-input bg-background px-3 text-sm">
                {dosageForms.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </div>
            <Input name="strength" label="التركيز" placeholder="مثال: 500mg" />
            <Input name="barcode" label="الباركود" required placeholder="امسح أو اكتب الباركود" />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>طريقة التعبئة والبيع</CardTitle>
            <CardDescription>لا يوجد خيار منفصل للبيع الجزئي؛ يتم استنتاجه من نوع التعبئة.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <label className={`cursor-pointer rounded-xl border p-4 transition ${packagingType === 'WHOLE_ONLY' ? 'border-primary bg-primary/5' : 'border-border'}`}>
                <input type="radio" name="packaging_type" value="WHOLE_ONLY" checked={packagingType === 'WHOLE_ONLY'} onChange={() => setPackagingType('WHOLE_ONLY')} className="sr-only" />
                <span className="font-semibold">عبوة كاملة فقط</span>
                <span className="mt-1 block text-xs text-muted-foreground">زجاجة، أنبوبة، بخاخ أو أي صنف لا يباع بأجزاء.</span>
              </label>
              <label className={`cursor-pointer rounded-xl border p-4 transition ${packagingType === 'BOX_STRIP' ? 'border-primary bg-primary/5' : 'border-border'}`}>
                <input type="radio" name="packaging_type" value="BOX_STRIP" checked={packagingType === 'BOX_STRIP'} onChange={() => setPackagingType('BOX_STRIP')} className="sr-only" />
                <span className="font-semibold">علبة تحتوي على شرائط</span>
                <span className="mt-1 block text-xs text-muted-foreground">تظهر في البيع كعلبة كاملة أو عدد من الشرائط.</span>
              </label>
            </div>
            {packagingType === 'BOX_STRIP' && (
              <div className="grid gap-4 rounded-xl bg-primary/5 p-4 sm:grid-cols-2">
                <Input
                  name="units_per_box"
                  label="عدد الشرائط داخل العلبة"
                  type="number"
                  min="2"
                  step="1"
                  required
                  onBlur={(event) => suggestStripPrice(event.currentTarget.form as HTMLFormElement)}
                />
                <Input name="partial_selling_price" label="سعر بيع الشريط (جنيه)" type="number" min="0" step="0.01" required placeholder="مثال: 17.55" />
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>الأسعار والمخزون الافتتاحي</CardTitle>
            <CardDescription>في حالة الشرائط، سعر الشراء للعلبة والمخزون يتحولان داخليًا إلى شرائط.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 sm:grid-cols-2">
            <Input name="cost_price" label="سعر الشراء للعبوة (جنيه)" type="number" min="0" step="0.01" required placeholder="مثال: 80.00" />
            <Input
              name="selling_price"
              label="سعر بيع العبوة (جنيه)"
              type="number"
              min="0"
              step="0.01"
              required
              placeholder="مثال: 105.50"
              onBlur={(event) => suggestStripPrice(event.currentTarget.form as HTMLFormElement)}
            />
            <Input name="min_stock_level" label="حد إعادة الطلب (بالوحدة الأساسية)" type="number" min="0" step="1" defaultValue="0" />
            <Input name="initial_boxes" label={packagingType === 'BOX_STRIP' ? 'عدد العلب المستلمة' : 'الكمية الافتتاحية'} type="number" min="0" step="1" defaultValue="0" />
            {packagingType === 'BOX_STRIP' && <Input name="initial_strips" label="عدد الشرائط الإضافية" type="number" min="0" step="1" defaultValue="0" />}
            <Input name="batch_number" label="رقم التشغيلة" placeholder="اختياري عند عدم إدخال مخزون" />
            <Input name="expiry_date" label="تاريخ الانتهاء" type="date" />
          </CardContent>
        </Card>

        {priceError && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{priceError}</p>}
        {error && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
        <div className="flex justify-end gap-3">
          <Button asChild variant="outline"><Link href="/inventory">إلغاء</Link></Button>
          <Button type="submit" loading={saving}>حفظ المنتج</Button>
        </div>
      </form>
    </div>
  )
}
