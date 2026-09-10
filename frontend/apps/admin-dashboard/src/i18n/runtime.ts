// Task 48 — حالة اللغة الحالية للوحدات خارج سياق React (api/money/lib…).
// تُستخدم في المتصفح فقط؛ الخادم يستخدم i18n/server.ts لكل طلب على حدة.
import { DEFAULT_LOCALE, type Locale } from './config'
import { messagesFor, type Messages } from './messages'
import { createTranslator, type Translator } from './translator'

let runtimeLocale: Locale = DEFAULT_LOCALE
let runtimeMessages: Messages = messagesFor(DEFAULT_LOCALE)

export function setRuntimeLocale(locale: Locale): void {
  if (locale === runtimeLocale) return
  runtimeLocale = locale
  runtimeMessages = messagesFor(locale)
}

export function currentRuntimeLocale(): Locale {
  return runtimeLocale
}

export function runtimeTranslator(namespace?: string): Translator {
  return createTranslator(runtimeMessages, namespace)
}
