// ============================================================================
// Pharmacy OS - API client with a detailed, deployment-friendly error system.
//
// Every failure throws an ApiError carrying:
//   - kind:          network | timeout | http | unknown
//   - status:        HTTP status code (when the server answered)
//   - code:          backend error code (e.g. INVALID_CREDENTIALS)
//   - requestId:     correlation id (matches backend log line + X-Request-ID)
//   - hint:          Arabic actionable fix instructions
//   - detail:        raw backend message / debug.internal_reason
//
// The login page renders these fields directly, so a broken deployment shows
// the REAL cause instead of a generic "API request failed".
// ============================================================================

const RAW_API_URL = process.env.NEXT_PUBLIC_API_URL

/** Base URL used for every request (trailing slashes trimmed). */
export const API_BASE_URL = (RAW_API_URL || '/api/v1').replace(/\/+$/, '')

/** True when NEXT_PUBLIC_API_URL is set at build time on Vercel. */
export const USING_CUSTOM_API_URL = Boolean(RAW_API_URL)

const REQUEST_TIMEOUT_MS = 20_000

export type ApiErrorKind = 'network' | 'timeout' | 'http' | 'unknown'

export interface ApiErrorJSON {
  name: 'ApiError'
  kind: ApiErrorKind
  message: string
  status: number | null
  code: string | null
  requestId: string | null
  url: string
  hint: string
  detail: string | null
  time: string
}

export class ApiError extends Error {
  readonly kind: ApiErrorKind
  readonly status: number | null
  readonly statusText: string
  readonly code: string | null
  readonly requestId: string | null
  readonly url: string
  readonly hint: string
  readonly detail: string | null
  readonly time: string

  constructor(fields: {
    kind: ApiErrorKind
    message: string
    url: string
    hint: string
    status?: number | null
    statusText?: string
    code?: string | null
    requestId?: string | null
    detail?: string | null
  }) {
    super(fields.message)
    this.name = 'ApiError'
    this.kind = fields.kind
    this.url = fields.url
    this.hint = fields.hint
    this.status = fields.status ?? null
    this.statusText = fields.statusText ?? ''
    this.code = fields.code ?? null
    this.requestId = fields.requestId ?? null
    this.detail = fields.detail ?? null
    this.time = new Date().toISOString()
  }

  toJSON(): ApiErrorJSON {
    return {
      name: 'ApiError',
      kind: this.kind,
      message: this.message,
      status: this.status,
      code: this.code,
      requestId: this.requestId,
      url: this.url,
      hint: this.hint,
      detail: this.detail,
      time: this.time,
    }
  }
}

// ---------------------------------------------------------------------------
// Arabic guidance per failure class
// ---------------------------------------------------------------------------

const NETWORK_HINT = [
  'السيرفر غير قابل للوصول من المتصفح. الأسباب الأكثر شيوعاً:',
  '1) NEXT_PUBLIC_API_URL غير مضبوط على Vercel (أو BACKEND_URL لو بتستخدم الوسيط) — أعد النشر بعد ضبطه.',
  '2) الباك اند متوقف — افتح https://pharmacyos.dockhosting.dev/health وتأكد أنه يرجع JSON.',
  '3) CORS: أضف دومين Vercel إلى CORS_ORIGINS على DockHosting (مثال: *.vercel.app).',
  '4) جرّب تعطيل مانع الإعلانات/VPN ثم أعد المحاولة.',
].join('\n')

const MIXED_CONTENT_HINT =
  'الصفحة تعمل على HTTPS لكن عنوان الـ API يستخدم HTTP — المتصفح يحجب هذا الطلب (mixed content). استخدم عنوان https:// للـ API.'

function arabicMessageFor(kind: ApiErrorKind, status: number | null, code: string | null, backendMessage: string | null): string {
  if (kind === 'network') return 'فشل الاتصال بسيرفر الـ API — لا يمكن الوصول إلى الخادم من المتصفح'
  if (kind === 'timeout') return 'انتهت مهلة الاتصال بالسيرفر (لم تصل استجابة خلال 20 ثانية)'

  switch (status) {
    case 400:
      return backendMessage
        ? `الطلب غير مقبول من السيرفر: ${backendMessage}`
        : 'الطلب غير مقبول من السيرفر (400)'
    case 401:
      return code === 'REFRESH_REQUIRED' || code === 'INVALID_REFRESH_SESSION'
        ? 'انتهت صلاحية الجلسة — سجّل الدخول من جديد'
        : 'البريد الإلكتروني أو كلمة المرور غير صحيحة (401)'
    case 403:
      if (code === 'EMAIL_NOT_VERIFIED') return 'لم يتم تفعيل البريد الإلكتروني — فعّل الحساب من رابط التفعيل المرسل (403)'
      if (code === 'ACCOUNT_INACTIVE') return 'الحساب غير مفعّل/موقوف — راجع مسؤول النظام (403)'
      return 'غير مسموح لك بتنفيذ هذا الطلب (403)'
    case 404:
      return 'المسار غير موجود على السيرفر (404) — تأكد من عنوان الـ API ومن أن نسخة الباك اند محدثة'
    case 423:
      return 'الحساب مقفول مؤقتاً بسبب 5 محاولات دخول خاطئة — انتظر 15 دقيقة ثم أعد المحاولة (423)'
    case 429:
      return 'عدد كبير جداً من المحاولات — انتظر قليلاً ثم أعد المحاولة (429)'
    case 500:
      return 'خطأ داخلي في السيرفر (500) — راجع لوجز DockHosting وابحث عن request_id الظاهر بالأسفل'
    case 502:
    case 503:
    case 504:
      return 'الباك اند غير متاح حالياً (' + status + ') — قد يكون قيد إعادة التشغيل أو متوقفاً على DockHosting'
    default:
      return backendMessage ? `فشل الطلب (${status}): ${backendMessage}` : `فشل الطلب (HTTP ${status ?? 'مجهول'})`
  }
}

function hintFor(kind: ApiErrorKind, status: number | null): string {
  if (kind === 'network') return NETWORK_HINT
  if (kind === 'timeout') return 'السيرفر بطيء جداً أو معلّق. راجع لوجز DockHosting: قد يكون الاتصال بقاعدة البيانات معلقاً عند الإقلاع.'
  if (status === 401) return 'تأكد من البريد وكلمة المرور. لو نسيتها استخدم "نسيت كلمة المرور". لو متأكد منها، تأكد أن الحساب موجود في قاعدة بيانات DockHosting.'
  if (status === 403 || status === 423) return 'اتبع الرسالة أعلاه؛ التفاصيل التقنية توضح كود الخطأ الدقيق.'
  if (status === 404) return 'المسار غير موجود — تأكد أن NEXT_PUBLIC_API_URL يشير إلى الجذر الصحيح وأن نسخة الباك اند تعمل.'
  if (status === 500) return 'افتح لوجز التطبيق في لوحة DockHosting وابحث عن request_id نفسه — السطر الذي يحمله هو السبب الحقيقي.'
  if (status === 502 || status === 503 || status === 504) return 'افتح https://pharmacyos.dockhosting.dev/health — لو لا يستجيب فالتطبيق متوقف، راجع لوجز النشر.'
  return 'راجع التفاصيل التقنية بالأسفل.'
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

interface ErrorBody {
  message?: unknown
  error?: unknown
  code?: unknown
  request_id?: unknown
  debug?: { internal_reason?: unknown } | null
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null
}

function isMixedContent(url: string): boolean {
  if (typeof window === 'undefined') return false
  return window.location.protocol === 'https:' && url.startsWith('http://')
}

function buildNetworkError(url: string, timedOut: boolean): ApiError {
  if (timedOut) {
    return new ApiError({ kind: 'timeout', url, message: arabicMessageFor('timeout', null, null, ''), hint: hintFor('timeout', null) })
  }
  if (isMixedContent(url)) {
    return new ApiError({
      kind: 'network',
      url,
      message: 'طلب محجوب من المتصفح: مزج HTTPS مع HTTP غير مسموح (mixed content)',
      hint: MIXED_CONTENT_HINT,
    })
  }
  return new ApiError({ kind: 'network', url, message: arabicMessageFor('network', null, null, ''), hint: NETWORK_HINT })
}

function buildHttpError(url: string, response: Response, body: ErrorBody | null): ApiError {
  const backendMessage = asString(body?.message)
  const code = asString(body?.code) ?? asString(body?.error)
  const requestId = asString(body?.request_id) ?? response.headers.get('x-request-id')
  const internalReason = asString(body?.debug?.internal_reason)
  const status = response.status

  const message = arabicMessageFor('http', status, code, backendMessage)
  const detailParts: string[] = []
  if (backendMessage) detailParts.push(`server_message: ${backendMessage}`)
  if (internalReason) detailParts.push(`internal_reason: ${internalReason}`)
  if (!detailParts.length) detailParts.push(`(لم يرجع السيرفر تفاصيل إضافية) body: ${JSON.stringify(body ?? {})}`)

  let hint = 'راجع التفاصيل التقنية بالأسفل.'
  if (status === 401) hint = 'تأكد من البريد وكلمة المرور، ومن أن الحساب موجود فعلاً في قاعدة البيانات المتصلة بالباك اند.'
  else if (status === 403 || status === 423) hint = 'اتبع الرسالة أعلاه؛ التفاصيل التقنية توضح كود الخطأ الدقيق.'
  else if (status === 404) hint = `المسار ${url} غير موجود — تأكد أن NEXT_PUBLIC_API_URL يشير إلى الجذر الصحيح وأن نسخة الباك اند تعمل.`
  else if (status >= 500) hint = 'افتح لوجز التطبيق في لوحة DockHosting وابحث عن request_id نفسه — السطر الذي يحمله هو السبب الحقيقي.'

  return new ApiError({
    kind: 'http',
    url,
    message,
    hint,
    status,
    statusText: response.statusText,
    code,
    requestId,
    detail: detailParts.join(' | '),
  })
}

// ---------------------------------------------------------------------------
// CSRF + refresh session (same behaviour as before, now with diagnostics)
// ---------------------------------------------------------------------------

function csrfHeaders(): HeadersInit {
  if (typeof document === 'undefined') return {}
  const csrf = document.cookie.match(/(?:^|; )pharmacy_csrf=([^;]+)/)?.[1]
  return csrf ? { 'X-CSRF-Token': decodeURIComponent(csrf) } : {}
}

let refreshPromise: Promise<boolean> | null = null

async function refreshSession(): Promise<boolean> {
  if (!refreshPromise) {
    refreshPromise = fetch(`${API_BASE_URL}/auth/refresh`, {
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

// ---------------------------------------------------------------------------
// Core fetch wrapper
// ---------------------------------------------------------------------------

export async function apiFetch<T>(
  endpoint: string,
  options: RequestInit = {},
  canRefresh = true,
): Promise<T> {
  const url = `${API_BASE_URL}${endpoint}`

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS)
  let timedOut = false

  let response: Response
  try {
    response = await fetch(url, {
      ...options,
      credentials: 'include',
      signal: options.signal ?? controller.signal,
      headers: {
        'Content-Type': 'application/json',
        ...(options.method && options.method !== 'GET' ? csrfHeaders() : {}),
        ...(options.headers || {}),
      },
    })
  } catch (fetchError) {
    // fetch() only rejects for network-level failures: DNS, refused, CORS
    // blocked, mixed content, offline or our own timeout abort.
    if (fetchError instanceof DOMException && fetchError.name === 'AbortError') timedOut = true
    throw buildNetworkError(url, timedOut)
  } finally {
    clearTimeout(timer)
  }

  if (response.status === 401 && canRefresh && !endpoint.startsWith('/auth/')) {
    if (await refreshSession()) return apiFetch<T>(endpoint, options, false)
  }

  const body = (await response.json().catch(() => null)) as ErrorBody | null

  if (!response.ok) {
    throw buildHttpError(url, response, body)
  }

  return body as T
}

// ---------------------------------------------------------------------------
// Auth API (same public shape as before)
// ---------------------------------------------------------------------------

export interface LoginResponse {
  user: Record<string, unknown>
  expires_in: number
}

export interface RegisterInput {
  companyName: string
  companyEmail: string
  firstName: string
  lastName: string
  email: string
  password: string
}

export const authApi = {
  register(input: RegisterInput) {
    return apiFetch<{ user?: Record<string, unknown>; message?: string; email_verified?: boolean }>(
      '/auth/register',
      {
        method: 'POST',
        body: JSON.stringify({
          company_name: input.companyName,
          company_email: input.companyEmail,
          first_name: input.firstName,
          last_name: input.lastName,
          email: input.email,
          password: input.password,
        }),
      },
    )
  },
  login(email: string, password: string) {
    // account_type intentionally omitted: the backend tries the owner and
    // employee tables when no type is given, so both can sign in here.
    return apiFetch<LoginResponse>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    })
  },
  me() {
    return apiFetch<{ user: Record<string, unknown> }>('/auth/me')
  },
  logout() {
    return apiFetch('/auth/logout', { method: 'POST' })
  },
}
