// Pharmacies Hook - Real Implementation
import { useState, useEffect, useCallback } from 'react'
import { accountsApi } from '@/lib/api'
import type { Account } from '@/types'

interface UsePharmaciesReturn {
  pharmacies: Account[]
  loading: boolean
  error: string | null
  total: number
  fetchPharmacies: (companyId: string) => Promise<void>
  createPharmacy: (companyId: string, data: { name: string; type: string }) => Promise<Account>
}

export function usePharmacies(): UsePharmaciesReturn {
  const [pharmacies, setPharmacies] = useState<Account[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [total, setTotal] = useState(0)
  const [currentCompanyId, setCurrentCompanyId] = useState<string>('')

  const fetchPharmacies = useCallback(async (companyId: string) => {
    try {
      setLoading(true)
      setError(null)
      setCurrentCompanyId(companyId)
      
      const response = await accountsApi.list(companyId)
      setPharmacies(response.data)
      setTotal(response.total)
    } catch (err) {
      setPharmacies([])
      setTotal(0)
      setError(err instanceof Error ? err.message : 'تعذر تحميل الحسابات')
    } finally {
      setLoading(false)
    }
  }, [])

  const createPharmacy = async (
    companyId: string,
    data: { name: string; type: string }
  ): Promise<Account> => {
    try {
      setLoading(true)
      setError(null)
      
      const newPharmacy = await accountsApi.create(companyId, data)
      setPharmacies(prev => [newPharmacy, ...prev])
      return newPharmacy
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to create pharmacy'
      setError(message)
      throw err
    } finally {
      setLoading(false)
    }
  }

  return {
    pharmacies,
    loading,
    error,
    total,
    fetchPharmacies,
    createPharmacy,
  }
}
