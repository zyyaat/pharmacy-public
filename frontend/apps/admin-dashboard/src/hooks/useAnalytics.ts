// Dashboard Analytics Hook - Real Implementation
import { useState, useEffect, useCallback } from 'react'
import { dashboardApi } from '@/lib/api'
import type { DashboardStats } from '@/types'

interface UseAnalyticsReturn {
  stats: DashboardStats | null
  loading: boolean
  error: string | null
  refetch: () => Promise<void>
}

export function useAnalytics(): UseAnalyticsReturn {
  const [stats, setStats] = useState<DashboardStats | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchStats = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      
      const data = await dashboardApi.getStats()
      setStats(data)
    } catch (err) {
      setStats(null)
      setError(err instanceof Error ? err.message : 'تعذر تحميل إحصاءات لوحة التحكم')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchStats()
  }, [fetchStats])

  return {
    stats,
    loading,
    error,
    refetch: fetchStats,
  }
}
