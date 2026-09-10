// Task 48 — إعدادات نظام اللغات الموحّد لكل التطبيقات.
// أفضل الممارسات المتبعة هنا:
// - اللغة الافتراضية العربية (RTL) مع دعم LTR الكامل.
// - قائمة اللغات الأكثر استخدامًا عالميًا (6 من أعلى 10 لغات متحدثة + tr وur).
// - حفظ التفضيل دائمًا على الحساب (الباكند) + كوكي لعرضه من الخادم (SSR).
export const locales = ['ar', 'en', 'fr', 'es', 'tr', 'zh', 'hi', 'ur'] as const

export type Locale = (typeof locales)[number]

export const DEFAULT_LOCALE: Locale = 'ar'

/** كوكي لغة الواجهة — يُقرأ من الخادم لرسم html lang/dir والقاموس الصحيحين. */
export const LOCALE_COOKIE = 'pharmacy_locale'

export interface LocaleMeta {
  nativeName: string
  englishName: string
  dir: 'rtl' | 'ltr'
}

export const LOCALE_META: Record<Locale, LocaleMeta> = {
  ar: { nativeName: 'العربية', englishName: 'Arabic', dir: 'rtl' },
  en: { nativeName: 'English', englishName: 'English', dir: 'ltr' },
  fr: { nativeName: 'Français', englishName: 'French', dir: 'ltr' },
  es: { nativeName: 'Español', englishName: 'Spanish', dir: 'ltr' },
  tr: { nativeName: 'Türkçe', englishName: 'Turkish', dir: 'ltr' },
  zh: { nativeName: '中文', englishName: 'Chinese', dir: 'ltr' },
  hi: { nativeName: 'हिन्दी', englishName: 'Hindi', dir: 'ltr' },
  ur: { nativeName: 'اردو', englishName: 'Urdu', dir: 'rtl' },
}

export function isLocale(value: unknown): value is Locale {
  return typeof value === 'string' && (locales as readonly string[]).includes(value)
}

export function dirFor(locale: Locale): 'rtl' | 'ltr' {
  return LOCALE_META[locale].dir
}
