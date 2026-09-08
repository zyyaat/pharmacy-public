const API_BASE_URL = (process.env.NEXT_PUBLIC_API_URL || '/api/v1').replace(/\/+$/, '')
const AUTH_BASE_PATH = '/auth/pharmacy'
const CSRF_COOKIE_NAME = 'pharmacy_csrf'

function csrfHeaders(): HeadersInit {
  if (typeof document === 'undefined') return {}
  const csrf = document.cookie.match(new RegExp(`(?:^|; )${CSRF_COOKIE_NAME}=([^;]+)`))?.[1]
  return csrf ? { 'X-CSRF-Token': decodeURIComponent(csrf) } : {}
}

let refreshPromise: Promise<boolean> | null = null

export class ApiError extends Error {
  code: string
  status: number
  payload: Record<string, unknown>

  constructor(message: string, code: string, status: number, payload: Record<string, unknown> = {}) {
    super(message)
    this.name = 'ApiError'
    this.code = code
    this.status = status
    this.payload = payload
  }
}

async function refreshSession(): Promise<boolean> {
  if (!refreshPromise) {
    refreshPromise = fetch(`${API_BASE_URL}${AUTH_BASE_PATH}/refresh`, {
      method: 'POST',
      credentials: 'include',
      headers: csrfHeaders(),
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

export async function apiFetch<T>(endpoint: string, options: RequestInit = {}, canRefresh = true): Promise<T> {
  let response: Response
  try {
    response = await fetch(`${API_BASE_URL}${endpoint}`, {
      ...options,
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json',
        ...(options.method && options.method !== 'GET' ? csrfHeaders() : {}),
        ...(options.headers || {}),
      },
    })
  } catch {
    throw new ApiError(
      'تعذر الاتصال بخادم النظام. راجع NEXT_PUBLIC_API_URL وإعدادات CORS في الـ backend.',
      'API_UNREACHABLE',
      0,
    )
  }
  if (response.status === 401 && canRefresh && shouldRefreshSession(endpoint)) {
    if (await refreshSession()) return apiFetch<T>(endpoint, options, false)
  }
  const body = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new ApiError(
      body.message || 'API request failed',
      body.code || body.error || 'API_ERROR',
      response.status,
      body,
    )
  }
  return body as T
}

export const authApi = {
  login(email: string, password: string) {
    return apiFetch<{ user: Record<string, unknown>; expires_in: number }>(`${AUTH_BASE_PATH}/login`, {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    })
  },
  resendVerification(email: string) {
    return apiFetch<{ message: string; sent?: boolean }>('/auth/resend-verification', {
      method: 'POST',
      body: JSON.stringify({ email }),
    })
  },
  verifyEmail(email: string, code: string) {
    return apiFetch<{ message: string }>('/auth/verify-email', {
      method: 'POST',
      body: JSON.stringify({ email, code }),
    })
  },
  me() {
    return apiFetch<{ user: Record<string, unknown> }>(`${AUTH_BASE_PATH}/me`)
  },
  logout() {
    return apiFetch(`${AUTH_BASE_PATH}/logout`, { method: 'POST' })
  },
}

export interface PharmacyDashboardStats {
  totalProducts: number
  lowStockCount: number
  activeEmployees: number
  activeToday: number
  salesUnitsToday: number
  lowStockItems: Array<{
    name: string
    generic_name: string
    quantity: number
    min_stock_level: number
    status: string
  }>
}

export interface PharmacyContext {
  pharmacy: {
    id: string
    name: string
    city: string
    address: string
    phone: string
    product_count: number
  }
  branch: {
    id: string
    name: string
    city: string
  } | null
  user: {
    id: string
    email: string
    first_name: string
    last_name: string
    display_name: string
    role: string
  }
}

export interface PharmacyInventoryItem {
  batch_id: string
  pharmacy_product_id: string
  global_product_id: string
  product_name: string
  generic_name: string
  brand_name: string
  barcode: string
  dosage_form: string
  strength: string
  batch_number: string
  unit: string
  quantity: number
  cost_per_unit_piastres: number
  total_cost_piastres: number
  expiry_date: string | null
  days_until_expiry: number | null
  selling_price_piastres: number
  partial_selling_price_piastres: number
  packaging_type: 'WHOLE_ONLY' | 'BOX_STRIP'
  units_per_box: number
  min_stock_level: number
  branch_name: string
  status: string
}

export interface PharmacyEmployee {
  id: string
  first_name: string
  last_name: string
  display_name: string
  email: string
  phone: string
  job_title: string
  status: string
  branch_id: string
  branch_name: string
  created_at: string
}

export interface PharmacyBranch {
  id: string
  name: string
  code: string
  phone: string
  email: string
  address: string
  city: string
  is_active: boolean
  manager_name: string
}

export interface PharmacyAttendance {
  id: string
  employee_id: string
  employee_name: string
  branch_id: string
  branch_name: string
  clock_in: string
  clock_out?: string
  total_minutes?: number
  status: string
}

export const pharmacyApi = {
  getContext() {
    return apiFetch<PharmacyContext>('/pharmacy/context')
  },
  getDashboardStats() {
    return apiFetch<PharmacyDashboardStats>('/pharmacy/dashboard/stats')
  },
  getDashboardActivity() {
    return apiFetch<{ data: Array<Record<string, unknown>> }>('/pharmacy/dashboard/activity')
  },
  getInventory() {
    return apiFetch<{ data: PharmacyInventoryItem[] }>('/pharmacy/inventory')
  },
  listProducts(search = '') {
    return apiFetch<{ data: PharmacyProduct[] }>(`/pharmacy/products${search ? `?search=${encodeURIComponent(search)}` : ''}`)
  },
  createProduct(input: CreatePharmacyProductInput) {
    return apiFetch<{ data: { id: string; initial_base_quantity: number } }>('/pharmacy/products', {
      method: 'POST',
      body: JSON.stringify(input),
    })
  },
  lookupPOSProduct(barcode: string) {
    return apiFetch<{ data: POSProduct }>(`/pharmacy/pos/products?barcode=${encodeURIComponent(barcode)}`)
  },
  createPOSSale(items: POSSaleItem[], idempotencyKey?: string) {
    return apiFetch<{ data: { sale_id: string; total_amount_piastres: number; replayed: boolean } }>('/pharmacy/pos/sales', {
      method: 'POST',
      body: JSON.stringify({ items, idempotency_key: idempotencyKey }),
    })
  },
  getEmployees() {
    return apiFetch<{ data: PharmacyEmployee[]; total: number }>('/pharmacy/employees')
  },
  getBranches() {
    return apiFetch<{ data: PharmacyBranch[]; total: number }>('/pharmacy/branches')
  },
  getAttendance() {
    return apiFetch<{ data: PharmacyAttendance[]; total: number }>('/pharmacy/attendance')
  },
}

export interface PharmacyProduct {
  id: string
  name: string
  generic_name: string
  barcode: string
  packaging_type: 'WHOLE_ONLY' | 'BOX_STRIP'
  units_per_box: number
  selling_price_piastres: number
  partial_selling_price_piastres: number
  stock: number
}

export interface POSProduct extends PharmacyProduct {}

export interface CreatePharmacyProductInput {
  name: string
  generic_name: string
  dosage_form: string
  strength: string
  barcode: string
  packaging_type: 'WHOLE_ONLY' | 'BOX_STRIP'
  units_per_box: number
  cost_price_piastres: number
  selling_price_piastres: number
  partial_selling_price_piastres: number | null
  min_stock_level: number
  initial_boxes: number
  initial_strips: number
  batch_number: string
  expiry_date: string
}

export interface POSSaleItem {
  pharmacy_product_id: string
  sale_unit: 'box' | 'strip'
  quantity: number
  expected_unit_price_piastres?: number
  expected_line_total_piastres?: number
}

export interface PriceChangedItem {
  index: number
  pharmacy_product_id: string
  sale_unit: 'box' | 'strip'
  quantity: number
  unit_price_piastres: number
  line_total_piastres: number
}
