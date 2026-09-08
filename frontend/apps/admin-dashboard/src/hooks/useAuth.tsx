'use client'

import { createContext, useContext, useState, useEffect, useCallback, type ReactNode } from 'react'
import { authApi } from '@/lib/api'
import type { CompanyUser, LoginCredentials, AuthResponse } from '@/types'

interface UseAuthReturn {
  user: CompanyUser | null
  loading: boolean
  error: string | null
  login: (credentials: LoginCredentials) => Promise<AuthResponse>
  logout: () => Promise<void>
  refetch: () => Promise<void>
}

const AuthContext = createContext<UseAuthReturn | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<CompanyUser | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchUser = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      const profile = await authApi.getProfile()
      if (profile.account_type !== 'company_user' || profile.role !== 'super_admin') {
        throw new Error('هذه اللوحة مخصصة لمديري النظام فقط')
      }
      setUser(profile)
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
        throw new Error('هذه اللوحة مخصصة لمديري النظام فقط')
      }
      setUser(response.user)
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