// ============================================================================
// Connection diagnostics for the Pharmacy OS frontend.
//
// Runs a step-by-step probe of the deployment from the browser and reports
// exactly which layer is broken (config / reachability / CORS / auth route /
// cookies) in Arabic. Used by the login page diagnostics panel.
// ============================================================================

import { API_BASE_URL, USING_CUSTOM_API_URL, ApiError } from './api'

export type CheckStatus = 'pass' | 'fail' | 'warn'

export interface DiagnosticCheck {
  id: string
  label: string
  status: CheckStatus
  detail: string
}

export interface DiagnosticReport {
  ok: boolean
  checks: DiagnosticCheck[]
  finishedAt: string
}

const PROBE_TIMEOUT_MS = 10_000

async function probe(url: string, init: RequestInit = {}): Promise<{ response: Response | null; timedOut: boolean }> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS)
  try {
    const response = await fetch(url, { cache: 'no-store', ...init, signal: controller.signal })
    return { response, timedOut: false }
  } catch {
    return { response: null, timedOut: false }
  } finally {
    clearTimeout(timer)
  }
}

function healthUrl(): string {
  // /health is registered at the server root, outside /api/v1.
  return API_BASE_URL.replace(/\/api\/v1\/?$/, '') + '/health'
}

interface HealthBody {
  status?: string
  database?: {
    ok?: boolean
    error?: string
    migrations?: { ok?: boolean; applied?: number; versions?: string[]; error?: string }
    tables?: { ok?: boolean; missing?: string[]; error?: string }
  }
}

/**
 * Runs all diagnostics. Every check explains itself in Arabic so the panel
 * can point at the exact misconfigured layer.
 */
export async function runConnectionDiagnostics(): Promise<DiagnosticReport> {
  const checks: DiagnosticCheck[] = []

  // ------------------------------------------------------------------ 1) config
  const pageIsHttps = typeof window !== 'undefined' && window.location.protocol === 'https:'
  if (!USING_CUSTOM_API_URL) {
    checks.push({
      id: 'config',
      label: 'إعدادات عنوان الـ API',
      status: 'warn',
      detail:
        `NEXT_PUBLIC_API_URL غير مضبوط — الطلبات تمر عبر وسيط Next (${API_BASE_URL}). ` +
        'على Vercel يجب ضبط BACKEND_URL=https://pharmacyos.dockhosting.dev (بدون /api/v1) وإلا سيحاول الوسيط الوصول إلى 127.0.0.1:8080 داخل سيرفرات Vercel ويفشل. ' +
        'الطريقة الأبسط: اضبط NEXT_PUBLIC_API_URL=https://pharmacyos.dockhosting.dev/api/v1 (لاحظ نهاية /api/v1) وأعد النشر.',
    })
  } else if (pageIsHttps && API_BASE_URL.startsWith('http://')) {
    checks.push({
      id: 'config',
      label: 'إعدادات عنوان الـ API',
      status: 'fail',
      detail: `عنوان الـ API يستخدم HTTP بينما الصفحة HTTPS: ${API_BASE_URL} — المتصفح سيحجب الطلب (mixed content). استخدم https://.`,
    })
  } else {
    checks.push({
      id: 'config',
      label: 'إعدادات عنوان الـ API',
      status: 'pass',
      detail: `NEXT_PUBLIC_API_URL مضبوط: ${API_BASE_URL}`,
    })
  }

  // -------------------------------------------------------------- 2) health/db
  const health = await probe(healthUrl(), { credentials: 'include' })
  if (health.response && health.response.ok) {
    const body = (await health.response.json().catch(() => null)) as HealthBody | null
    const db = body?.database
    if (body?.status === 'degraded' || (db && db.ok === false)) {
      checks.push({
        id: 'health',
        label: 'السيرفر + قاعدة البيانات',
        status: 'fail',
        detail: `السيرفر يعمل لكن قاعدة البيانات/to_regclass بها مشكلة: ${db?.error ?? 'غير معروف'}. افتح ${healthUrl()} لرؤية التقرير الكامل.`,
      })
    } else if (db?.tables && db.tables.ok === false && db.tables.missing?.length) {
      checks.push({
        id: 'health',
        label: 'السيرفر + قاعدة البيانات',
        status: 'fail',
        detail: `الاتصال بقاعدة البيانات يعمل لكن جداول ناقصة: ${db.tables.missing.join(', ')} — المايجريشن لم تكتمل. راجع لوجز إقلاع التطبيق على DockHosting.`,
      })
    } else {
      const applied = db?.migrations?.applied ?? '؟'
      checks.push({
        id: 'health',
        label: 'السيرفر + قاعدة البيانات',
        status: 'pass',
        detail: `السيرفر يعمل وقاعدة البيانات متصلة (مايجريشن مطبقة: ${applied}). حالة عامة: ${body?.status ?? 'healthy'}`,
      })
    }
  } else if (health.response) {
    checks.push({
      id: 'health',
      label: 'السيرفر + قاعدة البيانات',
      status: 'fail',
      detail: `/health رجع حالة غير طبيعية: HTTP ${health.response.status} — راجع لوجز DockHosting.`,
    })
  } else {
    // Distinguish "server down" from "CORS blocking" with a no-cors probe:
    // no-cors resolves (opaque) whenever the server answers, CORS or not.
    const opaque = await probe(healthUrl(), { mode: 'no-cors' })
    if (opaque.response) {
      checks.push({
        id: 'health',
        label: 'السيرفر + قاعدة البيانات',
        status: 'fail',
        detail:
          `السيرفر يعمل لكن المتصفح يحجب الطلب — هذا CORS تقريباً. ` +
          `أضف ${typeof window !== 'undefined' ? window.location.origin : '(دومين Vercel)'} أو *.vercel.app إلى CORS_ORIGINS في متغيرات DockHosting ثم أعد النشر.`,
      })
    } else {
      checks.push({
        id: 'health',
        label: 'السيرفر + قاعدة البيانات',
        status: 'fail',
        detail:
          `لا يمكن الوصول إلى ${healthUrl()} نهائياً (لا استجابة ولا CORS). ` +
          'الأسباب المحتملة: الباك اند متوقف على DockHosting، أو عنوان الـ API خاطئ، أو مشكلة DNS/شبكة. جرّب فتح الرابط في تبويب جديد.',
      })
    }
  }

  // --------------------------------------------------------- 3) auth endpoint
  const loginProbe = await probe(`${API_BASE_URL}/auth/login`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'diagnostic@probe.invalid', password: 'diagnostic-probe' }),
  })
  if (loginProbe.response) {
    const status = loginProbe.response.status
    if (status === 400 || status === 401) {
      checks.push({
        id: 'auth-route',
        label: 'مسار تسجيل الدخول',
        status: 'pass',
        detail: `المسار يستجيب بشكل سليم (HTTP ${status} = بيانات اختبارية مرفوضة كما هو متوقع). أي خطأ تالٍ سيكون سببه بيانات الدخول أو الحساب نفسه.`,
      })
    } else {
      checks.push({
        id: 'auth-route',
        label: 'مسار تسجيل الدخول',
        status: 'warn',
        detail: `المسار استجاب بحالة غير معتادة: HTTP ${status} — انسخ التفاصيل من الرد عند محاولة دخول حقيقية.`,
      })
    }
  } else {
    checks.push({
      id: 'auth-route',
      label: 'مسار تسجيل الدخول',
      status: 'fail',
      detail: `POST /auth/login محجوب (خطأ شبكة/CORS) بينما قد تكون الفحوصات السابقة نجحت — أضف الترويسة المخصصة إلى Access-Control-Allow-Headers أو تأكد من CORS_ORIGINS.`,
    })
  }

  // ------------------------------------------------------------- 4) session cookies
  const hasSessionCookie = typeof document !== 'undefined' && /(?:^|; )pharmacy_csrf=/.test(document.cookie)
  checks.push({
    id: 'cookies',
    label: 'كوكيز الجلسة',
    status: hasSessionCookie ? 'pass' : 'warn',
    detail: hasSessionCookie
      ? 'كوكيز الجلسة موجودة في المتصفح.'
      : 'لا توجد كوكيز جلسة بعد (طبيعي قبل أول دخول ناجح). لو استمرت بعد دخول ناجح: تأكد أن APP_ENV=production على DockHosting حتى تُرسل الكوكيز بـ Secure + SameSite=None (ضروري عبر دومينين مختلفين).',
  })

  const ok = checks.every((check) => check.status !== 'fail')
  return { ok, checks, finishedAt: new Date().toISOString() }
}

/** Convenience helper for console debugging: window.__diagnose(). */
export function installDiagnosticsHelper(): void {
  if (typeof window === 'undefined') return
  ;(window as unknown as { __diagnose?: () => Promise<DiagnosticReport> }).__diagnose = async () => {
    const report = await runConnectionDiagnostics()
    /* eslint-disable no-console */
    console.table(report.checks.map(({ id, status, detail }) => ({ id, status, detail })))
    console.log('تفاصيل أكثر في الكائن المرجَع من __diagnose()', report)
    return report
  }
}

/** True when the thrown value is a network/timeout ApiError. */
export function isConnectivityError(error: unknown): boolean {
  return error instanceof ApiError && (error.kind === 'network' || error.kind === 'timeout')
}
