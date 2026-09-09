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
  getProduct(productId: string) {
    return apiFetch<{ data: PharmacyProductDetail }>(`/pharmacy/products/${productId}`)
  },
  updateProduct(productId: string, input: UpdatePharmacyProductInput) {
    return apiFetch<{ data: PharmacyProductDetail }>(`/pharmacy/products/${productId}`, {
      method: 'PUT',
      body: JSON.stringify(input),
    })
  },
  adjustBatchStock(batchId: string, delta: number, reason: string, idempotencyKey: string) {
    return apiFetch<{ data: { movement_id: string; new_quantity: number; replayed: boolean } }>(
      `/pharmacy/inventory/${batchId}/adjust`,
      {
        method: 'POST',
        headers: { 'Idempotency-Key': idempotencyKey },
        body: JSON.stringify({ delta, reason }),
      },
    )
  },
  lookupPOSProduct(barcode: string) {
    return apiFetch<{ data: POSProduct }>(`/pharmacy/pos/products?barcode=${encodeURIComponent(barcode)}`)
  },
  searchPOSProducts(query: string, limit = 8, signal?: AbortSignal) {
    const params = new URLSearchParams({ q: query, limit: String(limit) })
    return apiFetch<{ data: POSProductSuggestion[] }>(`/pharmacy/pos/search?${params.toString()}`, { signal })
  },
  createPOSSale(items: POSSaleItem[], idempotencyKey?: string) {
    return apiFetch<{ data: { sale_id: string; total_amount_piastres: number; replayed: boolean } }>('/pharmacy/pos/sales', {
      method: 'POST',
      body: JSON.stringify({ items, idempotency_key: idempotencyKey }),
    })
  },
  listPOSSales(limit = 20, offset = 0, search = '', dateRange?: { from?: string; to?: string }) {
    const params = new URLSearchParams({ limit: String(limit), offset: String(offset) })
    if (search) params.set('search', search)
    if (dateRange?.from) params.set('from', dateRange.from)
    if (dateRange?.to) params.set('to', dateRange.to)
    return apiFetch<{ data: POSSalesPage }>(`/pharmacy/pos/sales?${params.toString()}`)
  },
  getSalesReport(from?: string, to?: string) {
    const params = new URLSearchParams()
    if (from) params.set('from', from)
    if (to) params.set('to', to)
    return apiFetch<{ data: SalesReport }>(`/pharmacy/reports/sales?${params.toString()}`)
  },
  getInventoryReport() {
    return apiFetch<{ data: InventoryReport }>('/pharmacy/reports/inventory')
  },
  getMovementsReport(from?: string, to?: string) {
    const params = new URLSearchParams()
    if (from) params.set('from', from)
    if (to) params.set('to', to)
    return apiFetch<{ data: MovementsReport }>(`/pharmacy/reports/movements?${params.toString()}`)
  },
  listStockMovements(filters: StockMovementFilters, limit = 50, offset = 0) {
    const params = new URLSearchParams({ limit: String(limit), offset: String(offset) })
    if (filters.type) params.set('type', filters.type)
    if (filters.search) params.set('search', filters.search)
    if (filters.from) params.set('from', filters.from)
    if (filters.to) params.set('to', filters.to)
    if (filters.direction) params.set('direction', filters.direction)
    return apiFetch<{ data: StockMovementsPage }>(`/pharmacy/inventory/movements?${params.toString()}`)
  },
  getPOSSale(saleId: string) {
    return apiFetch<{ data: POSSaleDetail }>(`/pharmacy/pos/sales/${encodeURIComponent(saleId)}`)
  },
  getPharmacySettings() {
    return apiFetch<{ data: { receipt: ReceiptSettings } }>('/pharmacy/settings')
  },
  updatePharmacySettings(receipt: Partial<ReceiptSettings>) {
    return apiFetch<{ data: { receipt: ReceiptSettings } }>('/pharmacy/settings', {
      method: 'PUT',
      body: JSON.stringify({ receipt }),
    })
  },
  createPOSSaleReturn(saleId: string, items: POSReturnItemInput[], reason: string, idempotencyKey?: string) {
    return apiFetch<{ data: POSReturnResult }>(`/pharmacy/pos/sales/${encodeURIComponent(saleId)}/returns`, {
      method: 'POST',
      body: JSON.stringify({ items, reason, idempotency_key: idempotencyKey }),
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

export type POSMatchType =
  | 'barcode_exact'
  | 'barcode_prefix'
  | 'barcode_fuzzy'
  | 'name_prefix'
  | 'name_substring'
  | 'name_fuzzy'
  | 'generic_fuzzy'

export interface POSProductSuggestion extends POSProduct {
  match_type: POSMatchType
  score: number
}

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

export interface PharmacyProductDetail {
  id: string
  name: string
  generic_name: string
  barcode: string
  packaging_type: 'WHOLE_ONLY' | 'BOX_STRIP'
  units_per_box: number
  cost_price_piastres: number
  selling_price_piastres: number
  partial_selling_price_piastres: number | null
  min_stock_level: number
  is_active: boolean
}

export interface UpdatePharmacyProductInput {
  name: string
  generic_name: string
  barcode: string
  packaging_type: 'WHOLE_ONLY' | 'BOX_STRIP'
  units_per_box: number
  cost_price_piastres: number
  selling_price_piastres: number
  partial_selling_price_piastres: number | null
  min_stock_level: number
  is_active?: boolean
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

// ---------------------------------------------------------------------------
// Sales history + returns (credit notes)
// ---------------------------------------------------------------------------

export type POSSaleStatus = 'completed' | 'partially_returned' | 'returned'

export interface POSSaleReturnSummary {
  id: string
  return_number: number
  total_amount_piastres: number
  reason: string
  created_at: string
  quantity_base?: number
}

export interface POSSaleSummary {
  id: string
  invoice_number: number
  status: POSSaleStatus
  total_amount_piastres: number
  created_at: string
  products_count: number
  total_quantity_base: number
  returned_amount_piastres: number
  returns: POSSaleReturnSummary[]
}

export interface POSSalesPage {
  sales: POSSaleSummary[]
  total: number
  limit: number
  offset: number
}

export interface POSSaleItemRow {
  sale_item_id: string
  pharmacy_product_id: string
  product_name: string
  generic_name: string
  barcode: string
  packaging_type: 'WHOLE_ONLY' | 'BOX_STRIP'
  units_per_box: number
  sale_unit: 'box' | 'strip'
  batch_number: string
  quantity_base: number
  unit_price_piastres: number
  amount_piastres: number
  returned_quantity_base: number
  returnable_quantity_base: number
  returned_amount_piastres: number
}

export interface POSSaleDetail {
  sale: {
    id: string
    invoice_number: number
    status: POSSaleStatus
    total_amount_piastres: number
    created_at: string
    returned_amount_piastres: number
    returns: POSSaleReturnSummary[]
  }
  items: POSSaleItemRow[]
}

// ---------------------------------------------------------------------------
// Pharmacy settings (receipt / printing)
// ---------------------------------------------------------------------------

export interface ReceiptSettings {
  /** ورق الطابعة الحرارية: 58mm أو 80mm */
  paper_width_mm: 58 | 80
  /** تلقائي: نافذة الطباعة تفتح بعد الحفظ مباشرة — يدوي: زر طباعة بعد الحفظ */
  print_mode: 'auto' | 'manual'
  /** نسخة عميل أو نسختان (عميل + صيدلية) */
  copies: 1 | 2
  show_phone: boolean
  show_address: boolean
  show_cashier: boolean
  show_thank_you: boolean
  thank_you_text: string
  show_return_policy: boolean
  return_policy_text: string
}

export interface POSReturnItemInput {
  sale_item_id: string
  quantity: number
}

export interface POSReturnResult {
  return_id: string
  return_number: number
  total_amount_piastres: number
  sale_status: POSSaleStatus
  replayed: boolean
  items?: Array<{ sale_item_id: string; quantity: number; amount_piastres: number }>
}

export type StockMovementType =
  | 'purchase'
  | 'sale'
  | 'return_to_supplier'
  | 'return_from_customer'
  | 'adjustment'
  | 'transfer_in'
  | 'transfer_out'
  | 'expiry_writeoff'
  | 'damage_writeoff'
  | 'theft_loss'
  | 'production_input'
  | 'production_output'

export interface StockMovementFilters {
  type?: StockMovementType | ''
  search?: string
  from?: string
  to?: string
  direction?: 'in' | 'out' | ''
}

export interface StockMovementRow {
  id: string
  created_at: string
  movement_type: StockMovementType
  quantity: number
  unit: string
  product_name: string
  generic_name: string | null
  batch_number: string | null
  branch_name: string | null
  actor_name: string | null
  reference_type: string | null
  reason: string | null
  notes: string | null
  quantity_after: number | null
}

export interface StockMovementsPage {
  movements: StockMovementRow[]
  total: number
}

// ---------------------------------------------------------------------------
// Reports (التقارير)
// ---------------------------------------------------------------------------

export interface ReportPeriod {
  from: string
  to: string
}

export interface SalesReportPoint {
  day: string
  invoices_count: number
  gross_piastres: number
  returned_piastres: number
  net_piastres: number
}

export interface SalesReportTopProduct {
  product_id: string
  name: string
  generic_name: string
  quantity_base: number
  amount_piastres: number
}

export interface SalesReport {
  period: ReportPeriod
  sales: {
    invoices_count: number
    gross_piastres: number
    units_base: number
    returns_count: number
    returned_piastres: number
    net_piastres: number
    avg_invoice_piastres: number
  }
  daily: SalesReportPoint[]
  top_products: SalesReportTopProduct[]
}

export interface InventoryAlertItem {
  name: string
  generic_name: string
  batch_number: string
  branch_name: string
  quantity: number
  /** النواقص: الحد الأدنى — الصلاحيات: الأيام المتبقية */
  threshold: number
  selling_price_piastres: number
  status: string
  /** الصلاحيات: تاريخ انتهاء التشغيلة — النواقص: null */
  extra_date?: string | null
}

export interface InventoryReport {
  totals: {
    batches_count: number
    products_count: number
    units_base: number
    cost_value_piastres: number
    retail_value_piastres: number
    low_stock_count: number
    out_of_stock_count: number
  }
  expiry: {
    expired_count: number
    expiring_30_count: number
    expiring_60_count: number
    expiring_90_count: number
    expired_value_piastres: number
    expiring_value_piastres: number
  }
  low_stock_items: InventoryAlertItem[]
  expiring_items: InventoryAlertItem[]
}

export interface MovementsReportByType {
  movement_type: StockMovementType
  transactions: number
  quantity_in: number
  quantity_out: number
}

export interface MovementsReport {
  period: ReportPeriod
  by_type: MovementsReportByType[]
  totals: {
    transactions: number
    quantity_in: number
    quantity_out: number
  }
}
