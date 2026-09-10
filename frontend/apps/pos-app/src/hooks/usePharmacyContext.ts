'use client'

import { useCallback, useEffect, useState } from 'react'
import { pharmacyApi, type PharmacyContext } from '@/lib/api'
import { runtimeTranslator } from '@/i18n/runtime'

export function usePharmacyContext() {
  const [context, setContext] = useState<PharmacyContext | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refetch = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      setContext(await pharmacyApi.getContext())
    } catch (err) {
      setContext(null)
      setError(err instanceof Error ? err.message : runtimeTranslator('common')('context_load_failed'))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void refetch()
  }, [refetch])

  return { context, loading, error, refetch }
}