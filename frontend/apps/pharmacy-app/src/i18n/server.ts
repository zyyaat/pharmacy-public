// Task 48 — i18n من جهة الخادم: قراءة الكوكي مرة واحدة لكل طلب
// لتوليد html lang/dir + القاموس + مترجم جاهز لمكونات الخادم.
import { cookies } from 'next/headers'
import { DEFAULT_LOCALE, dirFor, LOCALE_COOKIE, isLocale, type Locale } from './config'
import { messagesFor, type Messages } from './messages'
import { createTranslator, type Translator } from './translator'

export interface ServerI18n {
  locale: Locale
  dir: 'rtl' | 'ltr'
  messages: Messages
  t: Translator
}

export async function getServerI18n(namespace?: string): Promise<ServerI18n> {
  const store = await cookies()
  const raw = store.get(LOCALE_COOKIE)?.value
  const locale: Locale = isLocale(raw) ? raw : DEFAULT_LOCALE
  const messages = messagesFor(locale)
  return { locale, dir: dirFor(locale), messages, t: createTranslator(messages, namespace) }
}
