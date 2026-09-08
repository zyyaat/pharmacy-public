'use client'

import { useCallback, useEffect, useState } from 'react'
import { pharmacyApi, type PharmacyDashboardStats } from '@/lib/api'

interface PharmacyDashboardState {
  stats: PharmacyDashboardStats | null
  activity: Array<Record<string, unknown>>
  loading: boolean
  error: string | null
  refetch: () => Promise<void>
}

export function usePharmacyDashboard(): PharmacyDashboardState {
  const [stats, setStats] = useState<PharmacyDashboardStats | null>(null)
  const [activity, setActivity] = useState<Array<Record<string, unknown>>>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refetch = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      const [nextStats, nextActivity] = await Promise.all([
        pharmacyApi.getDashboardStats(),
        pharmacyApi.getDashboardActivity(),
      ])
      setStats(nextStats)
      setActivity(nextActivity.data)
    } catch (err) {
      setStats(null)
      setActivity([])
      setError(err instanceof Error ? err.message : 'تعذر تحميل بيانات لوحة التحكم')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void refetch()
  }, [refetch])

  return { stats, activity, loading, error, refetch }
}