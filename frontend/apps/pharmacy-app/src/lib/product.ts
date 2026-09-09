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
