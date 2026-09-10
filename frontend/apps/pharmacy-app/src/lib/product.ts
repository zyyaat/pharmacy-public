// Task 48 — وحدات عميل فقط: الترجمة وقت الاستدعاء عبر runtime + تنسيق الأرقام اللاتيني.
import { runtimeTranslator } from '@/i18n/runtime'
import { fmtNumber } from '@/i18n/format'

/**
 * عرض تركيز الدواء بجانب اسمه (كاربيمازول 200mg) بذكاء:
 * لا يُلحق التركيز إذا كان الاسم المسجّل أصلاً يحمل جرعة
 * (200mg / 1g / 5ml / 1000 وحدة…) أو يحتوي نص التركيز نفسه،
 * حتى لا نعرض «كاربيمازول 200mg 500mg» المزدحم والمضلل.
 */
const DOSE_IN_NAME_PATTERN = /\d\s*(?:mg|µg|mcg|g|ml|iu|ملجم|ملغ|مل|جرام|وحدة)/i

/** نص التركيز الجدير بالعرض بجانب الاسم — '' عند عدم الحاجة */
export function extraStrengthLabel(name: string, strength?: string | null): string {
  const clean = (strength ?? '').trim()
  if (!clean) return ''
  if (name.toLowerCase().includes(clean.toLowerCase())) return ''
  if (DOSE_IN_NAME_PATTERN.test(name)) return ''
  return clean
}

/**
 * وحدات التركيز الدوائي (نتيجة بحث الوحدات): ليست كلها mg — الأقراص تُوزن
 * بـ mg/mcg/g، السوائل بالمل، المحاليل والحقن بـ mg/ml، الإنزولين والفيتامينات
 * بوحدات دولية IU، والكريمات والنقط والمحاليل الوريدية بنسبة مئوية %.
 * «أخرى» لإبقاء التركيزات الخاصة نصاً كاملاً (مثل 120mg/5ml أو mEq).
 * التسميات تُترجم في المكوّن عبر t(unit.key) — هنا مفاتيح محايدة فقط.
 */
export const strengthUnits = [
  { value: 'mg', key: 'unit_mg' },
  { value: 'mcg', key: 'unit_mcg' },
  { value: 'g', key: 'unit_g' },
  { value: 'ml', key: 'unit_ml' },
  { value: 'mg/ml', key: 'unit_mg_ml' },
  { value: 'IU', key: 'unit_iu' },
  { value: '%', key: 'unit_percent' },
  { value: 'other', key: 'unit_other_full' },
] as const

/** ترجمة صيغ الوحدة المكتوبة (MG / ملجم / µg / iu …) إلى قيمة القائمة */
export function normalizeStrengthUnit(raw: string): string {
  const unit = raw.trim().toLowerCase().replace(/\s+/g, '')
  if (!unit) return ''
  const aliases: Record<string, string> = {
    mg: 'mg', ملجم: 'mg', ملغ: 'mg',
    mcg: 'mcg', ug: 'mcg', 'µg': 'mcg', 'μg': 'mcg', ميكروجرام: 'mcg', ميكروغرام: 'mcg',
    g: 'g', جم: 'g', جرام: 'g', غرام: 'g',
    ml: 'ml', مل: 'ml', ملليتر: 'ml', مليلتر: 'ml',
    'mg/ml': 'mg/ml', 'mg/1ml': 'mg/ml', 'ملجم/مل': 'mg/ml', 'ملغ/مل': 'mg/ml', 'مج/مل': 'mg/ml', 'مجم/مل': 'mg/ml',
    iu: 'IU', 'i.u': 'IU', 'i.u.': 'IU', وحدةدولية: 'IU', وحدهدولية: 'IU',
    '%': '%', '٪': '%', نسبة: '%', نسبةمئوية: '%',
  }
  return aliases[unit] ?? ''
}

/**
 * تفكيك تركيز محفوظ («500mg» / «5%» / «2.5ml») إلى رقم + وحدة لملء النموذج.
 * ما لا يطابق رقم+وحدة معروفة يُبقى كاملاً تحت «أخرى» حتى لا يضيع أي تنسيق قديم.
 */
export function splitStrength(strength?: string | null): { value: string; unit: string } {
  const clean = (strength ?? '').trim()
  if (!clean) return { value: '', unit: 'mg' }
  const match = clean.match(/^(\d+(?:[.,]\d+)?)\s*(.+)$/)
  if (match) {
    const unit = normalizeStrengthUnit(match[2])
    if (unit) return { value: match[1].replace(',', '.'), unit }
  }
  return { value: clean, unit: 'other' }
}

/** تركيب التركيز النهائي المخزَّن: رقم + وحدة (50 + mg → 50mg) أو النص كما هو عند «أخرى» */
export function composeStrength(value: string, unit: string): string {
  const clean = value.trim()
  if (!clean) return ''
  if (!unit || unit === 'other') return clean
  return `${clean.replace(/\s+/g, '').replace(',', '.')}${unit}`
}

/**
 * صياغة عدد العلب بالعربية للإشعارات الواضحة:
 * 1 → «علبة واحدة» · 2 → «علبتين» · 3-10 → «N علب» · غير ذلك → «N علبة».
 * حد الطلب يُحسب بالعلبة الكاملة دائماً — الشرائط المفردة لا تُحتسب.
 * الترجمة وقت الاستدعاء عبر runtimeTranslator (وحدات عميل فقط).
 */
export function boxWordAr(n: number): string {
  const t = runtimeTranslator('inventory')
  if (n === 1) return t('box_word_one')
  if (n === 2) return t('box_word_two')
  if (n >= 3 && n <= 10) return t('box_word_many', { count: fmtNumber(n) })
  return t('box_word_other', { count: fmtNumber(n) })
}

/** صياغة عدد الشرائط: 1 → «شريط واحد» · 2 → «شريطين» · 3-10 → «N شرائط» */
export function stripWordAr(n: number): string {
  const t = runtimeTranslator('inventory')
  if (n === 1) return t('strip_word_one')
  if (n === 2) return t('strip_word_two')
  if (n >= 3 && n <= 10) return t('strip_word_many', { count: fmtNumber(n) })
  return t('strip_word_other', { count: fmtNumber(n) })
}

/**
 * وصف الموجود على الرف كما يراه الصيدلي: «2 علبة و3 شرائط» أو
 * «علبة واحدة» أو «شريطين» — الشرائط تُعرض للعلم فقط ولا تدخل في حد الطلب.
 */
export function availabilityAr(fullBoxes: number, strips: number): string {
  if (fullBoxes > 0 && strips > 0) {
    const t = runtimeTranslator('inventory')
    return t('availability_box_and_strip', { boxes: fmtNumber(fullBoxes), strips: stripWordAr(strips) })
  }
  if (fullBoxes > 0) return boxWordAr(fullBoxes)
  return stripWordAr(strips)
}
