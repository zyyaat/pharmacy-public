// مساعدات وحدة التقارير: فترات جاهزة، تنسيق تواريخ عربي، وقيم مشتقة.
// كل التواريخ بصيغة YYYY-MM-DD محلية — نفس صيغة حقول input[type=date].

export type PeriodPreset =
  | 'today'
  | 'yesterday'
  | 'last7'
  | 'last30'
  | 'this_month'
  | 'last_month'
  | 'custom'

export const periodPresetOptions: Array<{ value: PeriodPreset; label: string }> = [
  { value: 'today', label: 'اليوم' },
  { value: 'yesterday', label: 'أمس' },
  { value: 'last7', label: 'آخر 7 أيام' },
  { value: 'last30', label: 'آخر 30 يوم' },
  { value: 'this_month', label: 'هذا الشهر' },
  { value: 'last_month', label: 'الشهر الماضي' },
  { value: 'custom', label: 'فترة مخصصة' },
]

/** تحويل Date إلى YYYY-MM-DD بالتوقيت المحلي (وليس UTC). */
export function toDateInput(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

/** نطاق الفترة الجاهزة — custom بلا نطاق جاهز. */
export function presetRange(preset: PeriodPreset): { from: string; to: string } | null {
  const today = new Date()
  const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  switch (preset) {
    case 'today':
      return { from: toDateInput(startOfToday), to: toDateInput(startOfToday) }
    case 'yesterday': {
      const yesterday = new Date(startOfToday)
      yesterday.setDate(yesterday.getDate() - 1)
      return { from: toDateInput(yesterday), to: toDateInput(yesterday) }
    }
    case 'last7': {
      const from = new Date(startOfToday)
      from.setDate(from.getDate() - 6)
      return { from: toDateInput(from), to: toDateInput(startOfToday) }
    }
    case 'last30': {
      const from = new Date(startOfToday)
      from.setDate(from.getDate() - 29)
      return { from: toDateInput(from), to: toDateInput(startOfToday) }
    }
    case 'this_month':
      return {
        from: toDateInput(new Date(today.getFullYear(), today.getMonth(), 1)),
        to: toDateInput(startOfToday),
      }
    case 'last_month': {
      const first = new Date(today.getFullYear(), today.getMonth() - 1, 1)
      const last = new Date(today.getFullYear(), today.getMonth(), 0)
      return { from: toDateInput(first), to: toDateInput(last) }
    }
    default:
      return null
  }
}

/** تاريخ عربي مقروء: ٩ سبتمبر ٢٠٢٦ */
export function formatArabicDate(iso: string): string {
  if (!iso) return '—'
  // YYYY-MM-DD تُفسَّر كتوقيت محلي بلا إزاحة
  const [year, month, day] = iso.split('-').map(Number)
  const date = month && day ? new Date(year, month - 1, day) : new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return date.toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })
}

/** تاريخ ووقت عربي: ٩ سبتمبر ٢٠٢٦، ٠٢:٤٥ م */
export function formatArabicDateTime(iso: string): string {
  if (!iso) return '—'
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  const time = date.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })
  return `${date.toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })}، ${time}`
}

/** نطاق فترة مقروء: من ١ يناير ٢٠٢٦ إلى ٣١ يناير ٢٠٢٦ */
export function formatPeriodRange(from: string, to: string): string {
  if (!from && !to) return 'كل الفترات'
  if (from === to) return formatArabicDate(from)
  return `من ${formatArabicDate(from)} إلى ${formatArabicDate(to)}`
}

/** يوم الشهر من تاريخ YYYY-MM-DD لتسميات الرسم البياني */
export function dayLabel(isoDay: string): string {
  const day = isoDay?.split('-')[2]
  return day ? String(Number(day)) : ''
}
