'use client'

import Ean13Svg from './ean13-svg'
import { formatPiastres, stripPricePiastres } from '@/lib/money'
import { useT } from '@/i18n/provider'

/** عرض قالب الملصق — مطابق لنوع الخادم في label_settings_handler.go */
export interface LabelTemplateView {
  id: string
  name: string
  system: boolean
  size_id: string
  fields: string[]
  font_scale: number
  show_pharmacy: boolean
}

export interface LabelSizeView {
  id: string
  width_mm: number
  height_mm: number
}

/** بيانات المنتج اللازمة لرسم ملصق واحد */
export interface LabelProductView {
  name: string
  generic_name?: string
  strength?: string
  barcode: string
  selling_price_piastres: number
  partial_selling_price_piastres: number
  units_per_box: number
  packaging_type?: string
}

/**
 * ملصق واحد بمقاس المليمتر الحقيقي. الباركود يُرسم دائمًا أسفل الملصق
 * (أسفل = أفضل للقراءة ويحفظ مناطق الهدوء، GS1 §7.4 من التقرير)، وبقية
 * الحقول تُرسم بترتيب القالب فوقه. حجم الخط يتضاعف بالنسبة المئوية للقالب.
 */
export function LabelSheet({
  template,
  size,
  product,
  pharmacyName,
  scale = 1,
}: {
  template: LabelTemplateView
  size: LabelSizeView
  product: LabelProductView
  pharmacyName?: string
  /** معاينة مكبّرة في الشاشة (الطباعة دائمًا 1) */
  scale?: number
}) {
  const t = useT('settings')
  const font = (px: number) => `${(px * template.font_scale) / 100}px`
  const price = formatPiastres(stripPricePiastres(product))

  const textFields = template.fields.filter((f) => f !== 'barcode')
  const hasBarcode = template.fields.includes('barcode')

  return (
    <div
      className="flex flex-col overflow-hidden bg-white text-[#111]"
      style={{
        width: `${size.width_mm * scale}mm`,
        height: `${size.height_mm * scale}mm`,
        padding: `${1 * scale}mm`,
        boxSizing: 'border-box',
      }}
    >
      {template.show_pharmacy && pharmacyName && (
        <p className="truncate text-center font-semibold" style={{ fontSize: font(6), lineHeight: 1.2 }}>
          {pharmacyName}
        </p>
      )}
      <div className={hasBarcode ? 'min-h-0 flex-1' : ''}>
        {textFields.includes('name') && (
          <p className="truncate font-bold" style={{ fontSize: font(8), lineHeight: 1.25 }} title={product.name}>
            {product.name}
          </p>
        )}
        {textFields.includes('generic_name') && product.generic_name && (
          <p className="truncate" style={{ fontSize: font(6.5), lineHeight: 1.25 }}>{product.generic_name}</p>
        )}
        {textFields.includes('strength') && product.strength && (
          <p className="truncate" style={{ fontSize: font(6.5), lineHeight: 1.25 }} dir="ltr">{product.strength}</p>
        )}
        {textFields.includes('price') && (
          <p className="truncate font-extrabold" style={{ fontSize: font(9), lineHeight: 1.25 }}>{price}</p>
        )}
        {textFields.includes('units_hint') && product.packaging_type === 'BOX_STRIP' && (
          <p className="truncate text-neutral-600" style={{ fontSize: font(6), lineHeight: 1.25 }}>
            {t('labelUnitsHint', { count: product.units_per_box })}
          </p>
        )}
      </div>
      {hasBarcode && (
        <div className="flex items-end justify-center pt-[0.5mm]" style={{ minHeight: '7mm' }}>
          <Ean13Svg
            code={product.barcode}
            className="w-full"
            showText={size.height_mm >= 15}
          />
        </div>
      )}
    </div>
  )
}
