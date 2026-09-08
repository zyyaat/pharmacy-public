// Companies Hook - Real Implementation
import { useState, useEffect, useCallback } from 'react'
import { companiesApi } from '@/lib/api'
import type { Company, CreateCompanyRequest } from '@/types'

interface UseCompaniesReturn {
  companies: Company[]
  loading: boolean
  error: string | null
  total: number
  page: number
  limit: number
  fetchCompanies: (params?: { page?: number; search?: string; status?: string }) => Promise<void>
  createCompany: (data: CreateCompanyRequest) => Promise<Company>
  updateCompany: (id: string, data: Partial<Company>) => Promise<Company>
  deleteCompany: (id: string) => Promise<void>
}

export function useCompanies(): UseCompaniesReturn {
  const [companies, setCompanies] = useState<Company[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [limit] = useState(10)

  const fetchCompanies = useCallback(async (params?: { page?: number; search?: string; status?: string }) => {
    try {
      setLoading(true)
      setError(null)
      
      const response = await companiesApi.list({
        page: params?.page || page,
        limit,
        search: params?.search,
        status: params?.status,
      })
      
      setCompanies(response.data)
      setTotal(response.total)
      if (params?.page) setPage(params.page)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch companies'
      setError(message)
    } finally {
      setLoading(false)
    }
  }, [page, limit])

  const createCompany = async (data: CreateCompanyRequest): Promise<Company> => {
    try {
      setLoading(true)
      setError(null)
      
      const newCompany = await companiesApi.create(data)
      setCompanies(prev => [newCompany, ...prev])
      return newCompany
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to create company'
      setError(message)
      throw err
    } finally {
      setLoading(false)
    }
  }

  const updateCompany = async (id: string, data: Partial<Company>): Promise<Company> => {
    try {
      setLoading(true)
      setError(null)
      
      const updatedCompany = await companiesApi.update(id, data)
      setCompanies(prev => prev.map(c => c.id === id ? updatedCompany : c))
      return updatedCompany
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to update company'
      setError(message)
      throw err
    } finally {
      setLoading(false)
    }
  }

  const deleteCompany = async (id: string): Promise<void> => {
    try {
      setLoading(true)
      setError(null)
      
      await companiesApi.delete(id)
      setCompanies(prev => prev.filter(c => c.id !== id))
      setTotal(prev => prev - 1)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to delete company'
      setError(message)
      throw err
    } finally {
      setLoading(false)
    }
  }

  // Initial fetch
  useEffect(() => {
    fetchCompanies()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return {
    companies,
    loading,
    error,
    total,
    page,
    limit,
    fetchCompanies,
    createCompany,
    updateCompany,
    deleteCompany,
  }
}
