// Task 48 — تغيير اللغة: حفظ دائم على الحساب أولًا (PATCH) ثم تحديث
// الكوكي وحالة الوحدات وخصائص html — الاستدعاء يكمل بـ router.refresh().
import { authApi } from '@/lib/api'
import { dirFor, LOCALE_COOKIE, type Locale } from './config'
import { setRuntimeLocale } from './runtime'

export function applyLocaleCookie(locale: Locale): void {
  document.cookie = `${LOCALE_COOKIE}=${locale}; path=/; max-age=31536000; samesite=lax`
}

export function applyLocaleEverywhere(locale: Locale): void {
  applyLocaleCookie(locale)
  setRuntimeLocale(locale)
  document.documentElement.lang = locale
  document.documentElement.dir = dirFor(locale)
}

/** حفظ دائم على الحساب + تطبيق فوري — يرمي عند فشل الشبكة كي لا يُرتَب المستخدم. */
export async function changeLocale(locale: Locale): Promise<void> {
  await authApi.setMyLocale(locale)
  applyLocaleEverywhere(locale)
}
