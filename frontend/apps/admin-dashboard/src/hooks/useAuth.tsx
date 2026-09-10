'use client'

import { createContext, useContext, useState, useEffect, useCallback, type ReactNode } from 'react'
import { authApi } from '@/lib/api'
import type { CompanyUser, LoginCredentials, AuthResponse } from '@/types'
import { applyLocaleEverywhere } from '@/i18n/change-locale'
import { DEFAULT_LOCALE, isLocale } from '@/i18n/config'
import { useT } from '@/i18n/provider'

interface UseAuthReturn {
  user: CompanyUser | null
  loading: boolean
  error: string | null
  login: (credentials: LoginCredentials) => Promise<AuthResponse>
  logout: () => Promise<void>
  refetch: () => Promise<void>
}


/**
 * Task 48 — مزامنة لغة الواجهة مع التفضيل المحفوظ دائمًا على الحساب
 * (نفس منطق تطبيقات الصيدلية ونقطة البيع).
 */
function syncLocaleFromUser(user: CompanyUser, allowReload = true) {
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
  if (allowReload && (cookieValue !== undefined || stored !== DEFAULT_LOCALE)) {
    window.location.reload()
  }
}

const AuthContext = createContext<UseAuthReturn | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  // AuthProvider يُرسم داخل I18nProvider لذا useT متاح هنا
  const t = useT('auth')
  const [user, setUser] = useState<CompanyUser | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchUser = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      const profile = await authApi.getProfile()
      if (profile.account_type !== 'company_user' || profile.role !== 'super_admin') {
        throw new Error(t('admin_only'))
      }
      setUser(profile)
      syncLocaleFromUser(profile)
    } catch {
      setUser(null)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void fetchUser()
  }, [fetchUser])

  const login = async (credentials: LoginCredentials): Promise<AuthResponse> => {
    try {
      setLoading(true)
      setError(null)
      const response = await authApi.login(credentials.email, credentials.password)
      if (response.user.account_type !== 'company_user' || response.user.role !== 'super_admin') {
        throw new Error(t('admin_only'))
      }
      setUser(response.user)
      // بعد الدخول: ضبط الكوكي قبل التوجيه بلا إعادة تحميل
      syncLocaleFromUser(response.user, false)
      return response
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Login failed'
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

  const value: UseAuthReturn = {
    user,
    loading,
    error,
    login,
    logout,
    refetch: fetchUser,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): UseAuthReturn {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth must be used inside AuthProvider')
  }
  return context
}