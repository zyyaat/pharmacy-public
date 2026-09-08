// API Client for Backend (Go) - Real Implementation
// This client connects to our Go backend for: CRUD operations, Admin tasks

import type { Company, CompanyUser, DashboardStats, Account, ActivityItem } from '@/types'

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || '/api/v1'
let refreshPromise: Promise<boolean> | null = null

// Generic fetch wrapper with auth
async function refreshSession(): Promise<boolean> {
  if (!refreshPromise) {
    refreshPromise = fetch(`${API_BASE_URL}/auth/refresh`, {
      method: 'POST',
      credentials: 'include',
      headers: typeof document === 'undefined'
        ? {}
        : {
            'X-CSRF-Token': decodeURIComponent(
              document.cookie.match(/(?:^|; )pharmacy_csrf=([^;]+)/)?.[1] || ''
            ),
          },
    })
      .then((response) => response.ok)
      .catch(() => false)
      .finally(() => {
        refreshPromise = null
      })
  }
  return refreshPromise
}

async function apiFetch<T>(
  endpoint: string,
  options: RequestInit = {},
  canRefresh = true
): Promise<T> {
  const url = `${API_BASE_URL}${endpoint}`
  
  const headers: HeadersInit = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string>),
  }

  if (typeof window !== 'undefined' && options.method && options.method !== 'GET') {
    const csrf = document.cookie.match(/(?:^|; )pharmacy_csrf=([^;]+)/)?.[1]
    if (csrf) headers['X-CSRF-Token'] = decodeURIComponent(csrf)
  }

  try {
    const response = await fetch(url, {
      ...options,
      headers,
      credentials: 'include',
    })

    if (response.status === 401 && canRefresh && !endpoint.startsWith('/auth/')) {
      if (await refreshSession()) return apiFetch<T>(endpoint, options, false)
    }

    if (!response.ok) {
      const error = await response.json().catch(() => ({ message: 'Request failed' }))
      throw new Error(error.message || `API Error: ${response.status}`)
    }

    return await response.json()
  } catch (error) {
    console.error(`API Error [${endpoint}]:`, error)
    throw error
  }
}

// ============================================
// Auth API
// ============================================

export const authApi = {
  async login(email: string, password: string) {
    const response = await apiFetch<{
      data?: { user: CompanyUser; expires_in: number }
      user?: CompanyUser
      expires_in?: number
    }>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password, account_type: 'company_user' }),
    })
    const user = response.data?.user || response.user
    if (!user) throw new Error('Login response did not include a user')
    return {
      user,
      token: '',
      expiresIn: response.data?.expires_in || response.expires_in || 0,
    }
  },

  async logout() {
    return apiFetch('/auth/logout', { method: 'POST' })
  },

  async getProfile() {
    const response = await apiFetch<{ user: CompanyUser }>('/auth/me')
    return response.user
  },

  async changePassword(currentPassword: string, newPassword: string) {
    return apiFetch('/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({ current_password: currentPassword, new_password: newPassword }),
    })
  },
}

// ============================================
// Companies API
// ============================================

export const companiesApi = {
  async list(params?: { page?: number; limit?: number; search?: string; status?: string }) {
    const queryParams = new URLSearchParams()
    if (params?.page) queryParams.set('page', String(params.page))
    if (params?.limit) queryParams.set('page_size', String(params.limit))
    if (params?.search) queryParams.set('search', params.search)
    if (params?.status) queryParams.set('status', params.status)

    const query = queryParams.toString()
    const response = await apiFetch<{
      data: Array<{
        id: string
        name: string
        name_ar?: string
        email: string
        phone?: string
        status: Company['status']
        plan: Company['plan']
        max_accounts: number
        max_users_per_account: number
        created_at: string
        total_users?: number
      }>
      pagination: { total: number; page: number; page_size: number; total_pages: number }
    }>(`/companies${query ? `?${query}` : ''}`)

    return {
      data: response.data.map((company) => ({
        id: company.id,
        name: company.name_ar || company.name,
        nameEn: company.name_ar ? company.name : undefined,
        email: company.email,
        phone: company.phone,
        status: company.status,
        plan: company.plan,
        maxUsers: company.max_users_per_account,
        currentUsersCount: company.total_users || 0,
        createdAt: company.created_at,
        updatedAt: company.created_at,
      })),
      total: response.pagination.total,
      page: response.pagination.page,
      limit: response.pagination.page_size,
    }
  },

  async getById(id: string) {
    return apiFetch<Company>(`/companies/${id}`)
  },

  async create(data: { name: string; name_en?: string; plan: string; max_users?: number }) {
    return apiFetch<Company>('/companies', {
      method: 'POST',
      body: JSON.stringify(data),
    })
  },

  async update(id: string, data: Partial<Company>) {
    return apiFetch<Company>(`/companies/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    })
  },

  async delete(id: string) {
    return apiFetch(`/companies/${id}`, { method: 'DELETE' })
  },
}

// ============================================
// Users API
// ============================================

export const usersApi = {
  async list(companyId: string, params?: { page?: number; limit?: number; role?: string }) {
    const queryParams = new URLSearchParams()
    if (params?.page) queryParams.set('page', String(params.page))
    if (params?.limit) queryParams.set('limit', String(params.limit))
    if (params?.role) queryParams.set('role', params.role)

    const query = queryParams.toString()
    return apiFetch<{ data: CompanyUser[]; total: number }>(
      `/companies/${companyId}/users${query ? `?${query}` : ''}`
    )
  },

  async create(companyId: string, data: {
    email: string
    first_name: string
    last_name: string
    role: string
    password?: string
  }) {
    return apiFetch<CompanyUser>(`/companies/${companyId}/users`, {
      method: 'POST',
      body: JSON.stringify(data),
    })
  },

  async update(companyId: string, userId: string, data: Partial<CompanyUser>) {
    return apiFetch<CompanyUser>(`/companies/${companyId}/users/${userId}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    })
  },

  async delete(companyId: string, userId: string) {
    return apiFetch(`/companies/${companyId}/users/${userId}`, { method: 'DELETE' })
  },
}

// ============================================
// Accounts (Pharmacies) API
// ============================================

export const accountsApi = {
  async list(companyId: string, params?: { page?: number; limit?: number }) {
    const queryParams = new URLSearchParams()
    if (params?.page) queryParams.set('page', String(params.page))
    if (params?.limit) queryParams.set('limit', String(params.limit))

    const query = queryParams.toString()
    return apiFetch<{ data: Account[]; total: number }>(
      `/companies/${companyId}/accounts${query ? `?${query}` : ''}`
    )
  },

  async create(companyId: string, data: { name: string; type: string }) {
    return apiFetch<Account>(`/companies/${companyId}/accounts`, {
      method: 'POST',
      body: JSON.stringify(data),
    })
  },
}

// ============================================
// Dashboard API
// ============================================

export const dashboardApi = {
  async getStats() {
    return apiFetch<DashboardStats>('/dashboard/stats')
  },

  async getRecentActivity(limit = 10) {
    return apiFetch<{ data: ActivityItem[] }>(`/dashboard/activity?limit=${limit}`)
  },
}

// ============================================
// Health Check
// ============================================

export async function healthCheck(): Promise<boolean> {
  try {
    const response = await fetch(`${API_BASE_URL.replace('/api/v1', '')}/health`)
    return response.ok
  } catch {
    return false
  }
}

// Export default API object
export const api = {
  auth: authApi,
  companies: companiesApi,
  users: usersApi,
  accounts: accountsApi,
  dashboard: dashboardApi,
  healthCheck,
}
