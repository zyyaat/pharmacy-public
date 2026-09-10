'use client'

import { useState } from 'react'
import { PackagePlus } from 'lucide-react'
import { parseEGPToPiastres, piastresToEGPInput } from '@/lib/money'
import { composeStrength, splitStrength, strengthUnits } from '@/lib/product'
import { useT } from '@/i18n/provider'
import { runtimeTranslator } from '@/i18n/runtime'
import { Card, CardContent, CardDescription, CardHeader, CardTitle, Input, Select } from '@/components/ui'

/** الأشكال الدوائية: القيمة المخزّنة + مفتاح التسمية في مساحة inventory */
export const dosageForms = [
  ['tablet', 'dosage_tablet'],
  ['capsule', 'dosage_capsule'],
  ['syrup', 'dosage_syrup'],
  ['injection', 'dosage_injection'],
  ['cream', 'dosage_cream'],
  ['drop', 'dosage_drop'],
  ['inhaler', 'dosage_inhaler'],
  ['other', 'dosage_other'],
] as const

/**
 * القيم الافتتاحية للحقول كنصوص — صفحة التعديل تملأها من بيانات المنتج
 * (الأسعار بالجنيه بعد التحويل من القروش) وصفحة الإضافة تتركها فارغة.
 */
export interface ProductFormDefaults {
  name: string
  generic_name: string
  dosage_form: string
  strength: string
  barcode: string
  units_per_box: string
  cost_price: string
  selling_price: string
  partial_selling_price: string
  min_stock_level: string
  initial_boxes: string
  initial_strips: string
  batch_number: string
  expiry_date: string
}

export const EMPTY_PRODUCT_FORM: ProductFormDefaults = {
  name: '',
  generic_name: '',
  dosage_form: 'tablet',
  strength: '',
  barcode: '',
  units_per_box: '',
  cost_price: '',
  selling_price: '',
  partial_selling_price: '',
  min_stock_level: '0',
  initial_boxes: '0',
  initial_strips: '0',
  batch_number: '',
  expiry_date: '',
}

/** Suggest a strip price (half-up) whenever the user has not typed one yet. */
export function suggestStripPrice(form: HTMLFormElement) {
  const stripField = form.elements.namedItem('partial_selling_price') as HTMLInputElement | null
  if (!stripField || stripField.value.trim()) return
  const boxPiastres = parseEGPToPiastres((form.elements.namedItem('selling_price') as HTMLInputElement)?.value || '')
  const units = Number((form.elements.namedItem('units_per_box') as HTMLInputElement)?.value || 0)
  if (boxPiastres === null || units < 2) return
  stripField.value = piastresToEGPInput(Math.round(boxPiastres / units))
}

/**
 * حقول نموذج المنتج المشتركة — نفس الصفحة للإضافة والتعديل (طلب المستخدم:
 * التعديل الكامل يدخل على نفس صفحة الإضافة ويُلغى المودال تماماً).
 * القيم تُقرأ من FormData وقت الإرسال (defaultValue)، ووقت العرض فقط
 * packagingType مُتحكَّم به لأنه يقود العرض الشرطي لحقول الشرائط.
 */
export function ProductFormFields({
  packagingType,
  onPackagingTypeChange,
  defaults = EMPTY_PRODUCT_FORM,
  showInitialStock = false,
}: {
  packagingType: 'WHOLE_ONLY' | 'BOX_STRIP'
  onPackagingTypeChange: (type: 'WHOLE_ONLY' | 'BOX_STRIP') => void
  defaults?: ProductFormDefaults
  showInitialStock?: boolean
}) {
  const t = useT('inventory')
  // التركيز حقلان: رقم + وحدة من القائمة (طلب المستخدم: الدكتور يكتب رقم فقط
  // مثل 50 ويختار mg) — القيم المحفوظة القديمة تُفكّك تلقائياً عند التعديل،
  // وما لا يُفكّك يبقى كاملاً تحت وحدة «أخرى».
  const strengthSplit = splitStrength(defaults.strength)
  const [strengthUnit, setStrengthUnit] = useState(strengthSplit.unit)

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><PackagePlus className="h-5 w-5 text-primary" />{t('treatment_info_title')}</CardTitle>
          <CardDescription>{t('treatment_info_desc')}</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <Input name="name" label={t('label_name')} required defaultValue={defaults.name} placeholder={t('placeholder_name')} />
          <Input name="generic_name" label={t('label_generic_name')} defaultValue={defaults.generic_name} placeholder={t('placeholder_optional')} />
          <div className="space-y-2">
            <label className="text-sm font-medium text-foreground/80">{t('label_dosage_form')}</label>
            <Select
              name="dosage_form"
              defaultValue={defaults.dosage_form || 'tablet'}
              options={dosageForms.map(([value, key]) => ({ value, label: t(key) }))}
            />
          </div>
          <div className="space-y-2">
            <label className="text-sm font-medium text-foreground/80">{t('label_strength')}</label>
            <div className="flex items-start gap-2">
              <div className="min-w-0 flex-1">
                <Input
                  name="strength_value"
                  placeholder={strengthUnit === 'other' ? t('placeholder_strength_other') : t('placeholder_strength_value')}
                  inputMode={strengthUnit === 'other' ? 'text' : 'decimal'}
                  defaultValue={strengthSplit.value}
                  aria-label={t('strength_value_aria')}
                />
              </div>
              <div className="w-40 shrink-0">
                <Select
                  name="strength_unit"
                  value={strengthUnit}
                  onValueChange={setStrengthUnit}
                  options={strengthUnits.map((unit) => ({ value: unit.value, label: t(unit.key) }))}
                  aria-label={t('strength_unit_aria')}
                />
              </div>
            </div>
          </div>
          <Input name="barcode" label={t('label_barcode')} required defaultValue={defaults.barcode} placeholder={t('placeholder_barcode')} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('packaging_title')}</CardTitle>
          <CardDescription>{t('packaging_desc')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <label className={`cursor-pointer rounded-xl border p-4 transition ${packagingType === 'WHOLE_ONLY' ? 'border-primary bg-primary/5' : 'border-border'}`}>
              <input type="radio" name="packaging_type" value="WHOLE_ONLY" checked={packagingType === 'WHOLE_ONLY'} onChange={() => onPackagingTypeChange('WHOLE_ONLY')} className="sr-only" />
              <span className="font-semibold">{t('packaging_whole')}</span>
              <span className="mt-1 block text-xs text-muted-foreground">{t('packaging_whole_desc')}</span>
            </label>
            <label className={`cursor-pointer rounded-xl border p-4 transition ${packagingType === 'BOX_STRIP' ? 'border-primary bg-primary/5' : 'border-border'}`}>
              <input type="radio" name="packaging_type" value="BOX_STRIP" checked={packagingType === 'BOX_STRIP'} onChange={() => onPackagingTypeChange('BOX_STRIP')} className="sr-only" />
              <span className="font-semibold">{t('packaging_box_strip')}</span>
              <span className="mt-1 block text-xs text-muted-foreground">{t('packaging_box_strip_desc')}</span>
            </label>
          </div>
          {packagingType === 'BOX_STRIP' && (
            <div className="grid gap-4 rounded-xl bg-primary/5 p-4 sm:grid-cols-2">
              <Input
                name="units_per_box"
                label={t('label_units_per_box')}
                type="number"
                min="2"
                step="1"
                required
                defaultValue={defaults.units_per_box}
                onBlur={(event) => suggestStripPrice(event.currentTarget.form as HTMLFormElement)}
              />
              <Input name="partial_selling_price" label={t('label_strip_price')} type="number" min="0" step="0.01" required defaultValue={defaults.partial_selling_price} placeholder={t('placeholder_strip_price')} />
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{showInitialStock ? t('prices_initial_title') : t('prices_title')}</CardTitle>
          <CardDescription>
            {showInitialStock
              ? t('prices_initial_desc')
              : t('prices_desc')}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <Input name="cost_price" label={t('label_cost_price')} type="number" min="0" step="0.01" required defaultValue={defaults.cost_price} placeholder={t('placeholder_cost_price')} />
          <Input
            name="selling_price"
            label={t('label_selling_price')}
            type="number"
            min="0"
            step="0.01"
            required
            defaultValue={defaults.selling_price}
            placeholder={t('placeholder_selling_price')}
            onBlur={(event) => suggestStripPrice(event.currentTarget.form as HTMLFormElement)}
          />
          <Input name="min_stock_level" label={t('label_min_stock')} type="number" min="0" step="1" defaultValue={defaults.min_stock_level} />
          {showInitialStock && (
            <>
              <Input name="initial_boxes" label={packagingType === 'BOX_STRIP' ? t('label_initial_boxes') : t('label_initial_quantity')} type="number" min="0" step="1" defaultValue={defaults.initial_boxes} />
              {packagingType === 'BOX_STRIP' && <Input name="initial_strips" label={t('label_initial_strips')} type="number" min="0" step="1" defaultValue={defaults.initial_strips} />}
              <Input name="batch_number" label={t('label_batch_number')} defaultValue={defaults.batch_number} placeholder={t('placeholder_batch_number')} />
              <Input name="expiry_date" label={t('label_expiry_date')} type="date" defaultValue={defaults.expiry_date} />
            </>
          )}
        </CardContent>
      </Card>
    </>
  )
}

/** الحقول المشتركة بين الإضافة والتعديل بعد التحقق من الأسعار */
export interface ProductFormValues {
  name: string
  generic_name: string
  dosage_form: string
  strength: string
  barcode: string
  packaging_type: 'WHOLE_ONLY' | 'BOX_STRIP'
  units_per_box: number
  cost_price_piastres: number
  selling_price_piastres: number
  partial_selling_price_piastres: number | null
  min_stock_level: number
}

/** قراءة الحقول المشتركة من FormData مع تحقق الأسعار — مستخدمة في الإضافة والتعديل */
export function readProductFormCommon(
  data: FormData,
  packagingType: 'WHOLE_ONLY' | 'BOX_STRIP',
): { error: string; values: null } | { error: null; values: ProductFormValues } {
  // وحدة عميل فقط (صفحات الإضافة/التعديل كلاهما 'use client') — الترجمة وقت الاستدعاء
  const t = runtimeTranslator('inventory')
  const partialRaw = String(data.get('partial_selling_price') || '').trim()
  let partialPiastres: number | null = null
  if (packagingType === 'BOX_STRIP') {
    if (!partialRaw) {
      return { error: t('error_strip_price_required'), values: null }
    }
    partialPiastres = parseEGPToPiastres(partialRaw)
    if (partialPiastres === null) {
      return { error: t('error_strip_price_invalid'), values: null }
    }
  }
  const costPiastres = parseEGPToPiastres(String(data.get('cost_price') || ''))
  const sellingPiastres = parseEGPToPiastres(String(data.get('selling_price') || ''))
  if (costPiastres === null || sellingPiastres === null) {
    return { error: t('error_prices_required'), values: null }
  }
  // تركيب التركيز من الرقم + الوحدة («أخرى» تُحفظ النص كما كُتب)
  const strengthValue = String(data.get('strength_value') || '').trim()
  const strengthUnit = String(data.get('strength_unit') || 'mg')
  const strength = composeStrength(strengthValue, strengthUnit)
  if (strength && strengthUnit !== 'other' && !/^\d+(?:[.,]\d+)?$/.test(strengthValue)) {
    return { error: t('error_strength_invalid'), values: null }
  }
  return {
    error: null,
    values: {
      name: String(data.get('name') || '').trim(),
      generic_name: String(data.get('generic_name') || '').trim(),
      dosage_form: String(data.get('dosage_form') || 'tablet'),
      strength,
      barcode: String(data.get('barcode') || '').trim(),
      packaging_type: packagingType,
      units_per_box: packagingType === 'BOX_STRIP' ? Number(data.get('units_per_box') || 0) : 1,
      cost_price_piastres: costPiastres,
      selling_price_piastres: sellingPiastres,
      partial_selling_price_piastres: partialPiastres,
      min_stock_level: Number(data.get('min_stock_level') || 0),
    },
  }
}
