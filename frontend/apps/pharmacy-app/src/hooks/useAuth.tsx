'use client'

import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { authApi } from '@/lib/api'
import { applyLocaleEverywhere } from '@/i18n/change-locale'
import { DEFAULT_LOCALE, isLocale } from '@/i18n/config'
import { useT } from '@/i18n/provider'

export type PharmacyUser = Record<string, unknown> & {
  account_type?: 'company_user' | 'employee'
  role?: string
  pharmacy_id?: string
  /** Task 57 — هل ما زال معالج إعداد الصيدلية مطلوبًا قبل دخول اللوحة؟ */
  onboarding_required?: boolean
}

function isPharmacyAccount(user: PharmacyUser): boolean {
  if (!user.pharmacy_id) return false
  if (user.account_type === 'employee') return true
  return user.account_type === 'company_user' &&
    ['company_admin', 'company_manager'].includes(user.role || '')
}

/**
 * Task 48 — مزامنة لغة الواجهة مع التفضيل المحفوظ دائمًا على الحساب.
 * تُستدعى بعد الدخول وبعد كل جلب للجلسة: الكوكي يظل صورة طبق الأصل من قاعدة البيانات،
 * وإذا اختلفا (جهاز جديد مثلاً) تُطبَّق لغة الحساب مع إعادة تحميل واحدة فقط عند الحاجة
 * كي تُرسم شجرة الخادم بالقاموس الصحيح من أول مرة.
 */
function syncLocaleFromUser(user: PharmacyUser, allowReload = true) {
  const stored = user.locale
  if (typeof stored !== 'string' || !isLocale(stored)) return
  const cookieRow = document.cookie
    .split('; ')
    .find((row) => row.startsWith('pharmacy_locale='))
  const cookieValue = cookieRow?.split('=')[1]
  if (cookieValue === stored) {
    applyLocaleEverywhere(stored)
    return
  }
  applyLocaleEverywhere(stored)
  // إعادة التحميل فقط عندما يكون ما رسمه الخادم مختلفًا فعلًا عن لغة الحساب
  if (allowReload && (cookieValue !== undefined || stored !== DEFAULT_LOCALE)) {
    window.location.reload()
  }
}

interface AuthContextValue {
  user: PharmacyUser | null
  loading: boolean
  error: string | null
  login: (email: string, password: string) => Promise<void>
  logout: () => Promise<void>
  refetch: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  // AuthProvider يُرسم داخل I18nProvider — لذلك useT متاح هنا (Task 48)
  const t = useT('auth')
  const [user, setUser] = useState<PharmacyUser | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refetch = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      const response = await authApi.me()
      if (!isPharmacyAccount(response.user)) {
        throw new Error(t('unsupported_account'))
      }
      setUser(response.user)
      syncLocaleFromUser(response.user)
    } catch {
      setUser(null)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void refetch()
  }, [refetch])

  const login = async (email: string, password: string) => {
    try {
      setLoading(true)
      setError(null)
      const response = await authApi.login(email, password)
      if (!isPharmacyAccount(response.user)) {
        throw new Error(t('not_pharmacy_account'))
      }
      setUser(response.user)
      // بعد الدخول مباشرة: ضبط الكوكي قبل التوجيه كي يرسم الخادم اللغة الصحيحة، بلا إعادة تحميل
      syncLocaleFromUser(response.user, false)
    } catch (err) {
      const message = err instanceof Error ? err.message : t('login_failed')
      setError(message)
      throw err
    } finally {
      setLoading(false)
    }
  }

  const logout = async () => {
    try {
      await authApi.logout()
    } finally {
      setUser(null)
    }
  }

  return (
    <AuthContext.Provider value={{ user, loading, error, login, logout, refetch }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside AuthProvider')
  return context
}