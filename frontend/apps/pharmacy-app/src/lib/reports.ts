// مساعدات وحدة التقارير: فترات جاهزة، تنسيق تواريخ، وقيم مشتقة.
// كل التواريخ بصيغة YYYY-MM-DD محلية — نفس صيغة حقول input[type=date].
// Task 48: التسميات والتنسيق يتبعان لغة الواجهة الحالية عبر i18n.
import { fmtDate, fmtDateTime } from '@/i18n/format'
import { runtimeTranslator } from '@/i18n/runtime'

export type PeriodPreset =
  | 'today'
  | 'yesterday'
  | 'last7'
  | 'last30'
  | 'this_month'
  | 'last_month'
  | 'custom'

/** خيارات منتقي الفترة — تُبنى لحظة الاستدعاء بلغة الواجهة الحالية. */
export function periodPresetOptions(): Array<{ value: PeriodPreset; label: string }> {
  const t = runtimeTranslator('reports')
  return [
    { value: 'today', label: t('preset_today') },
    { value: 'yesterday', label: t('preset_yesterday') },
    { value: 'last7', label: t('preset_last7') },
    { value: 'last30', label: t('preset_last30') },
    { value: 'this_month', label: t('preset_this_month') },
    { value: 'last_month', label: t('preset_last_month') },
    { value: 'custom', label: t('preset_custom') },
  ]
}

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

/** تاريخ مقروء بلغة الواجهة: 9 سبتمبر 2026 */
export function formatArabicDate(iso: string): string {
  if (!iso) return '—'
  // YYYY-MM-DD تُفسَّر كتوقيت محلي بلا إزاحة
  const [year, month, day] = iso.split('-').map(Number)
  const date = month && day ? new Date(year, month - 1, day) : new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return fmtDate(date, { day: 'numeric', month: 'long', year: 'numeric' })
}

/** تاريخ ووقت بلغة الواجهة: 9 سبتمبر 2026، 02:45 م */
export function formatArabicDateTime(iso: string): string {
  if (!iso) return '—'
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return runtimeTranslator('reports')('date_time_join', {
    date: fmtDate(date, { day: 'numeric', month: 'long', year: 'numeric' }),
    time: fmtDateTime(date, { hour: '2-digit', minute: '2-digit' }),
  })
}

/** نطاق فترة مقروء: من 1 يناير 2026 إلى 31 يناير 2026 */
export function formatPeriodRange(from: string, to: string): string {
  const t = runtimeTranslator('reports')
  if (!from && !to) return t('range_all')
  if (from === to) return formatArabicDate(from)
  return t('range_from_to', { from: formatArabicDate(from), to: formatArabicDate(to) })
}

/** يوم الشهر من تاريخ YYYY-MM-DD لتسميات الرسم البياني */
export function dayLabel(isoDay: string): string {
  const day = isoDay?.split('-')[2]
  return day ? String(Number(day)) : ''
}
