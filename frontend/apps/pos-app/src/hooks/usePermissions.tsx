'use client'

// مزوّد الصلاحيات (Task 42): يجلب صلاحيات المستخدم الحالي مرة واحدة عند فتح
// لوحة التحكم ويعرضها للقائمة الجانبية والصفحات عبر usePermissions().

import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { pharmacyApi, type MyPermissions } from '@/lib/api'

interface PermissionsContextValue {
  data: MyPermissions | null
  loading: boolean
  /** هل يملك المستخدم هذه الصلاحية (أو صلاحية مدير كاملة)؟ */
  can: (key: string) => boolean
  /** هل يملك أيًا من هذه الصلاحيات؟ */
  canAny: (keys: string[]) => boolean
  refetch: () => Promise<void>
}

const PermissionsContext = createContext<PermissionsContextValue | null>(null)

export function PermissionsProvider({ children }: { children: ReactNode }) {
  const [data, setData] = useState<MyPermissions | null>(null)
  const [loading, setLoading] = useState(true)

  const refetch = useCallback(async () => {
    try {
      setLoading(true)
      const response = await pharmacyApi.getMyPermissions()
      setData(response)
    } catch {
      // عند الفشل نمنع الاعتماد على الصلاحيات لكن لا نكسر الواجهة —
      // الصلاحيات الحقيقية مفروضة في الباكند على أي حال.
      setData(null)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void refetch()
  }, [refetch])

  const can = useCallback(
    (key: string) => {
      if (!data) return false
      if (data.full_access) return true
      return data.permissions.includes(key)
    },
    [data],
  )

  const canAny = useCallback(
    (keys: string[]) => keys.some((key) => can(key)),
    [can],
  )

  return (
    <PermissionsContext.Provider value={{ data, loading, can, canAny, refetch }}>
      {children}
    </PermissionsContext.Provider>
  )
}

export function usePermissions(): PermissionsContextValue {
  const ctx = useContext(PermissionsContext)
  if (!ctx) {
    throw new Error('usePermissions must be used within PermissionsProvider')
  }
  return ctx
}
