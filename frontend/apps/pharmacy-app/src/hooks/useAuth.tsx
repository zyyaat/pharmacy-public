'use client'

import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { authApi } from '@/lib/api'

export type PharmacyUser = Record<string, unknown> & {
  account_type?: 'company_user' | 'employee'
  role?: string
  pharmacy_id?: string
}

function isPharmacyAccount(user: PharmacyUser): boolean {
  if (!user.pharmacy_id) return false
  if (user.account_type === 'employee') return true
  return user.account_type === 'company_user' &&
    ['company_admin', 'company_manager'].includes(user.role || '')
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
  const [user, setUser] = useState<PharmacyUser | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refetch = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      const response = await authApi.me()
      if (!isPharmacyAccount(response.user)) {
        throw new Error('نوع الحساب غير مدعوم في تطبيق الصيدلية')
      }
      setUser(response.user)
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
        throw new Error('هذا الحساب غير مخصص لتطبيق الصيدلية')
      }
      setUser(response.user)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'فشل تسجيل الدخول'
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