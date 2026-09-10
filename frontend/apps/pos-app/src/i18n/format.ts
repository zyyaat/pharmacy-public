// Task 48 — طبقة تنسيق الأرقام والتواريخ المركزية.
// قاعدة Task 47 ثابتة: الأرقام لاتينية (0-9) في كل اللغات دون استثناء،
// بينما أسماء الشهور وصيغ التواريخ تتبع لغة الواجهة الحالية.
import { type Locale } from './config'
import { currentRuntimeLocale } from './runtime'

const INTL_TAGS: Record<Locale, string> = {
  ar: 'ar-EG',
  en: 'en-GB',
  fr: 'fr-FR',
  es: 'es-ES',
  tr: 'tr-TR',
  zh: 'zh-CN',
  hi: 'hi-IN',
  ur: 'ur-PK',
}

function localeTag(locale: Locale): string {
  return `${INTL_TAGS[locale]}-u-nu-latn`
}

export function fmtNumber(value: number, opts?: Intl.NumberFormatOptions): string {
  return new Intl.NumberFormat(localeTag(currentRuntimeLocale()), opts).format(value)
}

export function fmtDate(value: string | number | Date, opts?: Intl.DateTimeFormatOptions): string {
  const date = value instanceof Date ? value : new Date(value)
  return new Intl.DateTimeFormat(localeTag(currentRuntimeLocale()), opts).format(date)
}

/** تاريخ ووقت معًا — يُستخدم حيث كانت toLocaleString سابقًا. */
export function fmtDateTime(value: string | number | Date, opts?: Intl.DateTimeFormatOptions): string {
  return fmtDate(value, opts)
}
