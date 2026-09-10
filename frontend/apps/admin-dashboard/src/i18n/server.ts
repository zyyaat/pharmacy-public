// Task 50 — i18n من جهة الخادم بلغة الحساب نفسها (أفضل الممارسات):
// لو فيه جلسة صالحة تُقرأ اللغة من قاعدة البيانات عبر /me — فاللغة تتبع
// الحساب على أي متصفح/جهاز من أول فرشاة، بلا كوكي ولا إعادة تحميل ولا وميض.
// ولا جلسة → الكوكي (آخر لغة استُخدمت على الجهاز) ثم الافتراضية.
// cache() من react يضمن نداء /me واحدًا لكل طلب مهما تعددت الاستدعاءات.
import { cache } from 'react'
import { cookies, headers } from 'next/headers'
import { DEFAULT_LOCALE, dirFor, LOCALE_COOKIE, isLocale, type Locale } from './config'
import { messagesFor, type Messages } from './messages'
import { createTranslator, type Translator } from './translator'

const BACKEND_ORIGIN = process.env.BACKEND_INTERNAL_URL || 'http://127.0.0.1:8080'

// لغة الحساب من الجلسة — أي فشل (لا جلسة/انتهاء/شبكة) يعيد null بصمت كي
// لا يتعطل رسم الصفحة أبدًا، ويُستكمل بالكوكي/الافتراضية.
const sessionLocale = cache(async (): Promise<Locale | null> => {
  try {
    const hdrs = await headers()
    const cookieHeader = hdrs.get('cookie') ?? ''
    if (!cookieHeader) return null
    const res = await fetch(`${BACKEND_ORIGIN}/api/v1/auth/platform/me`, {
      headers: { cookie: cookieHeader },
      cache: 'no-store',
      signal: AbortSignal.timeout(2500),
    })
    if (!res.ok) return null
    const data = (await res.json()) as { user?: { locale?: unknown } }
    const locale = data.user?.locale
    return typeof locale === 'string' && isLocale(locale) ? locale : null
  } catch {
    return null
  }
})

export interface ServerI18n {
  locale: Locale
  dir: 'rtl' | 'ltr'
  messages: Messages
  t: Translator
}

export async function getServerI18n(namespace?: string): Promise<ServerI18n> {
  const store = await cookies()
  const raw = store.get(LOCALE_COOKIE)?.value
  const cookieLocale: Locale = isLocale(raw) ? raw : DEFAULT_LOCALE
  const locale: Locale = (await sessionLocale()) ?? cookieLocale
  const messages = messagesFor(locale)
  return { locale, dir: dirFor(locale), messages, t: createTranslator(messages, namespace) }
}
