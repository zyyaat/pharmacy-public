// API Client for Backend (Go) - Real Implementation
// This client connects to our Go backend for: CRUD operations, Admin tasks

import type { Company, CompanyUser, DashboardStats, Account, ActivityItem, PlatformUser, PlatformPermission, PlatformRole } from '@/types'

const API_BASE_URL = (process.env.NEXT_PUBLIC_API_URL || '/api/v1').replace(/\/+$/, '')
const AUTH_BASE_PATH = '/auth/platform'
const CSRF_COOKIE_NAME = 'platform_csrf'
let refreshPromise: Promise<boolean> | null = null

export class ApiError extends Error {
  code: string
  status: number

  constructor(message: string, code: string, status: number) {
    super(message)
    this.name = 'ApiError'
    this.code = code
    this.status = status
  }
}

// Generic fetch wrapper with auth
async function refreshSession(): Promise<boolean> {
  if (!refreshPromise) {
    refreshPromise = fetch(`${API_BASE_URL}${AUTH_BASE_PATH}/refresh`, {
      method: 'POST',
      credentials: 'include',
      headers: typeof document === 'undefined'
        ? {}
        : {
            'X-CSRF-Token': decodeURIComponent(
              document.cookie.match(new RegExp(`(?:^|; )${CSRF_COOKIE_NAME}=([^;]+)`))?.[1] || ''
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

function shouldRefreshSession(endpoint: string): boolean {
  return endpoint === `${AUTH_BASE_PATH}/me` || !endpoint.startsWith('/auth/')
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
    const csrf = document.cookie.match(new RegExp(`(?:^|; )${CSRF_COOKIE_NAME}=([^;]+)`))?.[1]
    if (csrf) headers['X-CSRF-Token'] = decodeURIComponent(csrf)
  }

  try {
    const response = await fetch(url, {
      ...options,
      headers,
      credentials: 'include',
    })

    if (response.status === 401 && canRefresh && shouldRefreshSession(endpoint)) {
      if (await refreshSession()) return apiFetch<T>(endpoint, options, false)
    }

    if (!response.ok) {
      const error = await response.json().catch(() => ({ message: 'Request failed' }))
      throw new ApiError(
        error.message || `API Error: ${response.status}`,
        error.code || error.error || 'API_ERROR',
        response.status,
      )
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
    }>(`${AUTH_BASE_PATH}/login`, {
      method: 'POST',
      body: JSON.stringify({ email, password, account_type: 'company_user' }),
    })
    const rawUser = response.data?.user || response.user
    const user = rawUser && normalizeCompanyUser(rawUser)
    if (!user) throw new Error('Login response did not include a user')
    return {
      user,
      token: '',
      expiresIn: response.data?.expires_in || response.expires_in || 0,
    }
  },

  async logout() {
    return apiFetch(`${AUTH_BASE_PATH}/logout`, { method: 'POST' })
  },

  /** Task 48 — الحفظ الدائم للغة الواجهة على الحساب (نقطة نهاية platform realm). */
  async setMyLocale(locale: string) {
    return apiFetch<{ locale: string }>(`${AUTH_BASE_PATH}/locale`, {
      method: 'PATCH',
      body: JSON.stringify({ locale }),
    })
  },

  async resendVerification(email: string) {
    return apiFetch<{ message: string; sent?: boolean }>('/auth/resend-verification', {
      method: 'POST',
      body: JSON.stringify({ email, account_type: 'company_user' }),
    })
  },

  async verifyEmail(email: string, code: string) {
    return apiFetch<{ message: string }>('/auth/verify-email', {
      method: 'POST',
      body: JSON.stringify({ email, code }),
    })
  },

  async getProfile() {
    const response = await apiFetch<{ user: CompanyUser }>(`${AUTH_BASE_PATH}/me`)
    return normalizeCompanyUser(response.user)
  },

  async changePassword(currentPassword: string, newPassword: string) {
    return apiFetch(`${AUTH_BASE_PATH}/change-password`, {
      method: 'POST',
      body: JSON.stringify({ current_password: currentPassword, new_password: newPassword }),
    })
  },
}

function normalizeCompanyUser(user: unknown): CompanyUser {
  const raw = (user || {}) as Record<string, unknown>
  return {
    ...(raw as Partial<CompanyUser>),
    locale: raw.locale ? String(raw.locale) : undefined,
    id: String(raw.id || ''),
    email: String(raw.email || ''),
    displayName: String(raw.displayName || raw.display_name || `${raw.first_name || ''} ${raw.last_name || ''}`.trim() || raw.email),
    companyId: String(raw.companyId || raw.company_id || ''),
    avatarUrl: raw.avatarUrl as string | undefined || raw.avatar_url as string | undefined,
    isActive: Boolean(raw.isActive ?? raw.is_active),
    lastLoginAt: raw.lastLoginAt as string | undefined || raw.last_login_at as string | undefined,
    createdAt: String(raw.createdAt || raw.created_at || ''),
    account_type: (raw.account_type || 'company_user') as CompanyUser['account_type'],
    role: raw.role as CompanyUser['role'],
  }
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
       summary: { total: number; active: number; trial: number; suspended: number }
    }>(`/platform-admin/companies${query ? `?${query}` : ''}`)

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
      summary: response.summary,
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
  async listPlatform(params?: { page?: number; limit?: number; search?: string; role?: string }) {
    const queryParams = new URLSearchParams()
    if (params?.page) queryParams.set('page', String(params.page))
    if (params?.limit) queryParams.set('page_size', String(params.limit))
    if (params?.search) queryParams.set('search', params.search)
    if (params?.role) queryParams.set('role', params.role)
    const query = queryParams.toString()
    const response = await apiFetch<{ data: Array<Record<string, unknown>>; pagination: { total: number; page: number; page_size: number; total_pages: number } }>(
      `/platform-admin/users${query ? `?${query}` : ''}`
    )
    return {
      data: response.data.map((user) => ({
        id: String(user.id),
        accountType: user.account_type as PlatformUser['accountType'],
        email: String(user.email || ''),
        displayName: String(user.display_name || user.email || ''),
        companyName: String(user.company_name || '—'),
        role: String(user.role || ''),
        isActive: Boolean(user.is_active),
        lastLoginAt: user.last_login_at as string | undefined,
        createdAt: user.created_at as string | undefined,
        permissionsCount: Number(user.permissions_count || 0),
      } satisfies PlatformUser)),
      ...response.pagination,
    }
  },

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
  async listPlatform(params?: { page?: number; limit?: number; search?: string }) {
    const queryParams = new URLSearchParams()
    if (params?.page) queryParams.set('page', String(params.page))
    if (params?.limit) queryParams.set('page_size', String(params.limit))
    if (params?.search) queryParams.set('search', params.search)
    const query = queryParams.toString()
    const response = await apiFetch<{ data: Array<Record<string, unknown>>; pagination: { total: number; page: number; page_size: number; total_pages: number } }>(
      `/platform-admin/accounts${query ? `?${query}` : ''}`
    )
    return {
      data: response.data.map((account) => ({
        id: String(account.id),
        companyId: String(account.company_id || ''),
        companyName: String(account.company_name || '—'),
        name: String(account.name || '—'),
        status: String(account.status || 'unknown'),
        plan: String(account.plan || ''),
        pharmacyCount: Number(account.pharmacy_count || 0),
        branchesCount: Number(account.branch_count || 0),
        email: String(account.email || ''),
        phone: String(account.phone || ''),
        createdAt: String(account.created_at || ''),
      } satisfies Account)),
      ...response.pagination,
    }
  },

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
    return apiFetch<DashboardStats>('/platform-admin/stats')
  },

  async getRecentActivity(limit = 10) {
    return apiFetch<{ data: ActivityItem[] }>(`/dashboard/activity?limit=${limit}`)
  },
}

export const permissionsApi = {
  async list() {
    const response = await apiFetch<{
      permissions: Array<Record<string, unknown>>
      roles: Array<Record<string, unknown>>
    }>('/platform-admin/permissions')
    return {
      permissions: response.permissions.map((permission) => ({
        key: String(permission.key),
        name: String(permission.name || permission.key),
        description: String(permission.description || ''),
        module: String(permission.module || 'other'),
        category: String(permission.category || ''),
        isSystem: Boolean(permission.is_system),
        sortOrder: Number(permission.sort_order || 0),
      } satisfies PlatformPermission)),
      roles: response.roles.map((role) => ({
        id: String(role.id),
        name: String(role.name),
        description: String(role.description || ''),
        isSystem: Boolean(role.is_system),
        userCount: Number(role.user_count || 0),
        permissionKeys: Array.isArray(role.permission_keys) ? role.permission_keys.map(String) : [],
      } satisfies PlatformRole)),
    }
  },
}

export const platformSettingsApi = {
  async getTrialSettings() {
    const response = await apiFetch<{ data: { default_trial_days: number } }>('/platform-admin/settings')
    return response.data
  },

  async updateTrialSettings(defaultTrialDays: number) {
    const response = await apiFetch<{ data: { default_trial_days: number } }>('/platform-admin/settings', {
      method: 'PATCH',
      body: JSON.stringify({ default_trial_days: defaultTrialDays }),
    })
    return response.data
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
  permissions: permissionsApi,
  platformSettings: platformSettingsApi,
  healthCheck,
}
