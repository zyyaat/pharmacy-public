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
        // Backend 500s carry only a machine code ({"error": "..."}); surface it
        // instead of a bare "API Error: 500" so a failing action is reportable.
        error.message || error.error || `API Error: ${response.status}`,
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
// SaaS Plans & Subscriptions (Task 90)
// ============================================

export type PlanRow = {
  id: string
  slug: string
  name: string
  name_ar: string
  description: string
  monthly_price_piastres: number
  yearly_price_piastres: number
  currency: string
  is_active: boolean
  is_public: boolean
  sort_order: number
  subscribers: number
}

export type PlanDetail = PlanRow & {
  features: string[]
  permissions: string[]
  limits: Record<string, number>
}

export type FeatureRow = {
  key: string
  name: string
  name_ar: string
  description: string
  sort_order: number
  is_active: boolean
  suggested_permissions: string[]
}

export type SubscriptionRow = {
  id: string
  company: { id: string; name: string; email: string }
  plan: { id: string; slug: string; name: string; name_ar: string }
  status: 'trial' | 'active' | 'expired' | 'cancelled' | 'suspended' | 'pending'
  billing_interval: string
  current_period_start: string | null
  current_period_end: string | null
  trial_ends_at: string | null
  cancel_at_period_end: boolean
  source: string
  created_at: string
  versions?: number
}

export type PlanPayload = {
  slug?: string
  name: string
  name_ar?: string
  description?: string
  monthly_price_piastres: number
  yearly_price_piastres: number
  currency?: string
  is_active?: boolean
  is_public?: boolean
  sort_order?: number
  features: string[]
  permissions: string[]
  limits: Record<string, number>
}

export const plansApi = {
  async list() {
    const response = await apiFetch<{ data: PlanRow[] }>('/platform-admin/plans')
    return response.data
  },

  async get(id: string) {
    const response = await apiFetch<{ data: PlanDetail }>(`/platform-admin/plans/${id}`)
    return response.data
  },

  async create(payload: PlanPayload) {
    const response = await apiFetch<{ data: { id: string } }>('/platform-admin/plans', {
      method: 'POST',
      body: JSON.stringify(payload),
    })
    return response.data
  },

  async update(id: string, payload: PlanPayload) {
    const response = await apiFetch<{ data: { id: string } }>(`/platform-admin/plans/${id}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    })
    return response.data
  },

  async setStatus(id: string, isActive: boolean) {
    await apiFetch(`/platform-admin/plans/${id}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ is_active: isActive }),
    })
  },

  async remove(id: string) {
    await apiFetch(`/platform-admin/plans/${id}`, { method: 'DELETE' })
  },
}

export const featuresApi = {
  async list() {
    const response = await apiFetch<{ data: FeatureRow[] }>('/platform-admin/features')
    return response.data
  },
}

// ============================================
// Account page API (Task 15 — per-company control + logs)
// ============================================

export type CompanyProfile = {
  id: string
  name: string
  name_ar: string
  email: string
  phone: string
  status: string
  legacy_plan: string
  max_users_per_account: number
  created_at: string
  subscription: SubscriptionRow | null
  usage: Record<string, number>
  active_overrides: number
}

export type EntitlementRow = {
  id: string
  kind: 'feature' | 'permission' | 'limit'
  key: string
  enabled: boolean | null
  value: number | null
  reason: string
  expires_at: string | null
  created_by: string
  created_at: string
  expired: boolean
  bundle_key: string
}

export type EntitlementPayload = {
  kind: 'feature' | 'permission' | 'limit'
  key: string
  enabled?: boolean
  value?: number
  reason?: string
  expires_at?: string
}

export type CompanyLogRow = {
  id: string
  action: string
  entity_type: string
  entity_id: string
  summary: string
  actor: string
  created_at: string
}

export const accountApi = {
  async profile(id: string) {
    const response = await apiFetch<{ data: CompanyProfile }>(`/platform-admin/companies/${id}`)
    return response.data
  },

  async entitlements(id: string) {
    const response = await apiFetch<{ data: EntitlementRow[] }>(
      `/platform-admin/companies/${id}/entitlements`)
    return response.data
  },

  async upsertEntitlement(id: string, payload: EntitlementPayload) {
    const response = await apiFetch<{ data: { id: string } }>(
      `/platform-admin/companies/${id}/entitlements`,
      { method: 'POST', body: JSON.stringify(payload) })
    return response.data
  },

  async deleteEntitlement(id: string, eid: string) {
    await apiFetch(`/platform-admin/companies/${id}/entitlements/${eid}`, { method: 'DELETE' })
  },

  async logs(id: string, page = 1) {
    const response = await apiFetch<{ data: CompanyLogRow[]; pagination: { total: number; page: number } }>(
      `/platform-admin/companies/${id}/logs?page=${page}&page_size=50`)
    return response
  },
}

export type PaymentRow = {
  id: string
  company: { id: string; name: string; email: string }
  plan: { id: string; slug: string; name: string; name_ar?: string }
  billing_interval: 'monthly' | 'yearly'
  amount_piastres: number
  currency: string
  provider: 'paymob' | 'manual'
  status: 'pending' | 'succeeded' | 'failed' | 'refunded' | 'voided' | 'cancelled'
  note?: string
  subscription_id?: string
  created_at: string
}

export type BillingOverview = {
  active_count: number
  trial_count: number
  terminal_count: number
  cancelling_count: number
  mrr_piastres: number
  payments_30d_count: number
  payments_30d_piastres: number
  expiring_within_7_days: Array<{
    id: string
    company_id: string
    company_name: string
    company_email: string
    plan_name: string
    plan_name_ar: string
    status: string
    ends_at: string | null
    cancel_at_period_end: boolean
  }>
}

export const subscriptionsApi = {

  async overview() {
    const response = await apiFetch<{ data: BillingOverview }>('/platform-admin/subscriptions/overview')
    return response.data
  },
  async list(params: { status?: string; search?: string; company_id?: string; page?: number; pageSize?: number; history?: boolean } = {}) {
    const query = new URLSearchParams()
    if (params.status) query.set('status', params.status)
    if (params.search) query.set('search', params.search)
    if (params.company_id) query.set('company_id', params.company_id)
    if (params.history) query.set('history', 'true')
    query.set('page', String(params.page ?? 1))
    query.set('page_size', String(params.pageSize ?? 50))
    const response = await apiFetch<{ data: SubscriptionRow[]; pagination: { total: number } }>(
      `/platform-admin/subscriptions?${query.toString()}`
    )
    return response
  },

  async assign(payload: {
    company_id: string
    plan_id: string
    billing_interval?: 'none' | 'monthly' | 'yearly'
    current_period_end?: string
    trial_days?: number
  }) {
    const response = await apiFetch<{ data: { id: string } }>('/platform-admin/subscriptions', {
      method: 'POST',
      body: JSON.stringify(payload),
    })
    return response.data
  },

  async action(id: string, payload: {
    action: 'extend' | 'set_period_end' | 'cancel' | 'suspend' | 'reactivate' | 'set_cancel_at_period_end'
    current_period_end?: string
    cancel_at_period_end?: boolean
  }) {
    const response = await apiFetch<{ data: { id: string } }>(`/platform-admin/subscriptions/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(payload),
    })
    return response.data
  },

  async manualPayment(payload: {
    company_id: string
    plan_id: string
    billing_interval: 'monthly' | 'yearly'
    amount_piastres?: number
    note?: string
    idempotency_key?: string
  }) {
    const response = await apiFetch<{ data: { payment_id: string; subscription_id: string; amount_piastres?: number; status?: string; duplicate?: boolean } }>(
      '/platform-admin/payments/manual',
      { method: 'POST', body: JSON.stringify(payload) }
    )
    return response.data
  },
}

export const paymentsApi = {
  async list(params: { status?: string; provider?: string; company_id?: string; search?: string; page?: number; pageSize?: number } = {}) {
    const query = new URLSearchParams()
    if (params.status) query.set('status', params.status)
    if (params.provider) query.set('provider', params.provider)
    if (params.company_id) query.set('company_id', params.company_id)
    if (params.search) query.set('search', params.search)
    query.set('page', String(params.page ?? 1))
    query.set('page_size', String(params.pageSize ?? 50))
    const response = await apiFetch<{ data: PaymentRow[]; pagination: { total: number } }>(
      `/platform-admin/payments?${query.toString()}`
    )
    return response
  },

  async refund(id: string, payload: { note?: string; shorten_subscription?: boolean }) {
    const response = await apiFetch<{ data: { id: string; status: string; shortened: boolean } }>(
      `/platform-admin/payments/${id}/refund`,
      { method: 'POST', body: JSON.stringify(payload) }
    )
    return response.data
  },
}

// ============================================
// Central product libraries («مكتبات المنتجات المركزية»)
// Named, country-targeted, versioned catalogs with the OFFICIAL regulated
// price living on the library entry (library_products), an append-only
// change log powering the pharmacy diff, and Excel bulk import for price
// bulletins. Backend: /platform-admin/libraries (+ /catalog/products).
// ============================================

export type LibraryRow = {
  id: string;
  name: string;
  description: string | null;
  country_code: string | null;
  currency: string;
  is_published: boolean;
  version: number;
  published_at: string | null;
  product_count: number;
  synced_pharmacies: number;
  draft_changes: number;
  created_at: string;
  updated_at: string;
};

export type LibraryPayload = {
  name: string;
  description?: string;
  country_code?: string;
  currency?: string;
};

export type LibraryProductRow = {
  id: string;
  global_product_id: string;
  official_price_piastres: number;
  notes: string | null;
  name: string;
  generic_name: string | null;
  strength: string | null;
  dosage_form: string;
  product_category: string;
  barcode: string | null;
  manufacturer_name: string | null;
  active_ingredient: string | null;
  requires_prescription: string;
  is_verified: boolean;
  updated_at: string;
};

export type LibraryChangeRow = {
  id: string;
  global_product_id: string;
  product_name: string;
  version: number;
  change_type: "added" | "price_changed" | "metadata_changed" | "removed";
  old_price_piastres: number | null;
  new_price_piastres: number | null;
  summary: string | null;
  created_at: string;
};

export type CatalogProductRow = {
  id: string;
  name: string;
  generic_name: string | null;
  strength: string | null;
  dosage_form: string;
  product_category: string;
  barcode: string | null;
  manufacturer_name: string | null;
  is_verified: boolean;
  source: string;
  is_active: boolean;
  libraries: Array<{ id: string; name: string }>;
};

export type LibraryImportPreview = {
  file_type: string;
  headers: string[];
  mapping: Record<string, number>;
  fields: string[];
  total_rows: number;
  valid_rows: number;
  invalid_rows: number;
  invalid_reasons: string[];
  sample: Record<string, string>[];
};

export type LibraryImportReport = {
  total_rows: number;
  added: number;
  price_updated: number;
  products_created: number;
  unchanged: number;
  failed: number;
  errors: string[];
};

export type Pagination = {
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
};

export type NewCatalogProduct = {
  name: string;
  generic_name?: string;
  brand_name?: string;
  dosage_form?: string;
  strength?: string;
  product_category?: string;
  requires_prescription?: string;
  barcode?: string;
  generate_barcode?: boolean;
  manufacturer_name?: string;
  manufacturer_country?: string;
  active_ingredient?: string;
  atc_code?: string;
  therapeutic_class?: string;
  storage_instructions?: string;
  description?: string;
};

export const librariesApi = {
  async list() {
    const response = await apiFetch<{ data: LibraryRow[] }>("/platform-admin/libraries");
    return response.data;
  },

  async get(id: string) {
    const response = await apiFetch<{ data: LibraryRow }>(`/platform-admin/libraries/${id}`);
    return response.data;
  },

  async create(payload: LibraryPayload) {
    const response = await apiFetch<{ data: LibraryRow }>("/platform-admin/libraries", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    return response.data;
  },

  async update(id: string, payload: LibraryPayload) {
    const response = await apiFetch<{ data: LibraryRow }>(`/platform-admin/libraries/${id}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    return response.data;
  },

  async remove(id: string) {
    await apiFetch(`/platform-admin/libraries/${id}`, { method: "DELETE" });
  },

  async publish(id: string) {
    const response = await apiFetch<{ data: { version: number; first_publish: boolean } }>(
      `/platform-admin/libraries/${id}/publish`,
      { method: "POST" }
    );
    return response.data;
  },

  async products(id: string, search: string, page: number, pageSize = 20) {
    const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
    if (search) params.set("search", search);
    const response = await apiFetch<{ data: LibraryProductRow[]; pagination: Pagination }>(
      `/platform-admin/libraries/${id}/products?${params}`
    );
    return { items: response.data, pagination: response.pagination };
  },

  async changes(id: string, page: number, pageSize = 20) {
    const response = await apiFetch<{ data: LibraryChangeRow[]; pagination: Pagination }>(
      `/platform-admin/libraries/${id}/changes?page=${page}&page_size=${pageSize}`
    );
    return { items: response.data, pagination: response.pagination };
  },

  async addProduct(id: string, payload: { global_product_id?: string; official_price_piastres?: number; notes?: string; new_product?: NewCatalogProduct }) {
    const response = await apiFetch<{ data: { global_product_id: string; action: string } }>(
      `/platform-admin/libraries/${id}/products`,
      { method: "POST", body: JSON.stringify(payload) }
    );
    return response.data;
  },

  async updateProduct(id: string, pid: string, payload: { official_price_piastres?: number; notes?: string }) {
    await apiFetch(`/platform-admin/libraries/${id}/products/${pid}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  },

  async removeProduct(id: string, pid: string) {
    await apiFetch(`/platform-admin/libraries/${id}/products/${pid}`, { method: "DELETE" });
  },

  async importPreview(id: string, file: File, mapping?: Record<string, number>) {
    const form = new FormData();
    form.append("file", file);
    if (mapping) form.append("mapping", JSON.stringify(mapping));
    const response = await apiFetch<{ data: LibraryImportPreview }>(
      `/platform-admin/libraries/${id}/import/preview`,
      { method: "POST", body: form }
    );
    return response.data;
  },

  async importExecute(id: string, file: File, mapping?: Record<string, number>) {
    const form = new FormData();
    form.append("file", file);
    if (mapping) form.append("mapping", JSON.stringify(mapping));
    const response = await apiFetch<{ data: LibraryImportReport }>(
      `/platform-admin/libraries/${id}/import/execute`,
      { method: "POST", body: form }
    );
    return response.data;
  },

  async catalogProducts(search: string, page: number, pageSize = 20) {
    const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
    if (search) params.set("search", search);
    const response = await apiFetch<{ data: CatalogProductRow[]; pagination: Pagination }>(
      `/platform-admin/catalog/products?${params}`
    );
    return { items: response.data, pagination: response.pagination };
  },

  async updateCatalogProduct(id: string, payload: Partial<NewCatalogProduct> & { is_verified?: boolean; is_active?: boolean }) {
    await apiFetch(`/platform-admin/catalog/products/${id}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  },
};

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
