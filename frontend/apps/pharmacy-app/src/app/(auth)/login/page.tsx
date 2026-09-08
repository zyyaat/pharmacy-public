"use client"

import { FormEvent, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/hooks/useAuth'
import { ApiError } from '@/lib/api'
import { isConnectivityError } from '@/lib/diagnostics'
import { ConnectionDiagnostics } from '@/components/diagnostics-panel'

export default function LoginPage() {
  const router = useRouter()
  const { login } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<ApiError | null>(null)
  const [genericError, setGenericError] = useState('')
  const [diagnosticsKey, setDiagnosticsKey] = useState(0)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setError(null)
    setGenericError('')
    setLoading(true)
    try {
      await login(email, password)
      router.push('/')
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err)
        // Connectivity problems (server down / CORS / wrong URL) trigger the
        // automatic diagnostics run inside the panel.
        if (isConnectivityError(err)) setDiagnosticsKey((key) => key + 1)
      } else {
        setGenericError(err instanceof Error ? err.message : 'فشل تسجيل الدخول')
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4 py-8">
      <div className="absolute -right-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
      <div className="absolute -bottom-40 -left-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />
      <div className="relative grid w-full max-w-5xl overflow-hidden rounded-3xl border border-border bg-card shadow-2xl lg:grid-cols-[1.05fr_0.95fr]">
        <div className="hidden flex-col justify-between bg-primary p-10 text-primary-foreground lg:flex">
          <div>
            <div className="flex items-center gap-3">
              <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-white/15 text-xl font-black">P</div>
              <div>
                <p className="text-lg font-bold">Pharmacy OS</p>
                <p className="text-xs text-primary-foreground/70">إدارة الصيدلية بذكاء</p>
              </div>
            </div>
            <div className="mt-24">
              <p className="text-sm font-medium text-primary-foreground/70">مرحبًا بعودتك</p>
              <h1 className="mt-3 text-4xl font-bold leading-tight">كل ما تحتاجه<br />لإدارة صيدليتك.</h1>
              <p className="mt-5 max-w-sm text-sm leading-7 text-primary-foreground/75">
                تابع المخزون، الموظفين، المبيعات والفروع من مكان واحد وبطريقة أبسط.
              </p>
            </div>
          </div>
          <p className="text-xs text-primary-foreground/60">© 2024 Pharmacy OS · إصدار المؤسسات</p>
        </div>

        <div className="p-7 sm:p-10">
          <div className="mb-10 lg:hidden">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary text-lg font-black text-primary-foreground">P</div>
              <div>
                <p className="font-bold">Pharmacy OS</p>
                <p className="text-xs text-muted-foreground">إدارة الصيدلية</p>
              </div>
            </div>
          </div>
          <div>
            <p className="text-sm font-medium text-primary">تسجيل الدخول</p>
            <h2 className="mt-2 text-2xl font-bold">أهلًا بك من جديد</h2>
            <p className="mt-2 text-sm text-muted-foreground">سجّل دخولك للوصول إلى لوحة الصيدلية.</p>
          </div>
          <form className="mt-8 space-y-5" autoComplete="on" onSubmit={handleSubmit}>
            {error && (
              <div className="rounded-xl border border-destructive/30 bg-destructive/10 p-4" role="alert">
                <p className="text-sm font-semibold text-destructive">{error.message}</p>

                <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-1 text-[11px] text-muted-foreground sm:grid-cols-3">
                  <span>النوع: <b className="font-mono">{error.kind}</b></span>
                  <span>الحالة: <b className="font-mono">{error.status ?? '—'}</b></span>
                  <span>الكود: <b className="font-mono">{error.code ?? '—'}</b></span>
                  <span className="col-span-2 sm:col-span-3 truncate">الطلب: <b className="font-mono">{error.url}</b></span>
                  {error.requestId && (
                    <span className="col-span-2 sm:col-span-3">request_id: <b className="font-mono">{error.requestId}</b></span>
                  )}
                </div>

                <details className="mt-3 rounded-lg bg-background/60 p-2" open={Boolean(error.detail)}>
                  <summary className="cursor-pointer text-xs font-medium text-destructive">التفاصيل التقنية الكاملة</summary>
                  <pre className="mt-2 max-h-44 overflow-auto whitespace-pre-wrap break-all text-[11px] leading-5 text-muted-foreground" dir="ltr">
{JSON.stringify(error.toJSON(), null, 2)}
                  </pre>
                </details>
              </div>
            )}
            {!error && genericError && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{genericError}</p>}
            <label className="block">
              <span className="mb-2 block text-sm font-medium">البريد الإلكتروني</span>
              <input
                className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none transition-all placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10"
                placeholder="name@pharmacy.com"
                autoComplete="email"
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
            </label>
            <label className="block">
              <div className="mb-2 flex items-center justify-between">
                <span className="text-sm font-medium">كلمة المرور</span>
                <button className="text-xs font-medium text-primary hover:underline" type="button">نسيت كلمة المرور؟</button>
              </div>
              <input
                className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none transition-all placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10"
                placeholder="••••••••"
                autoComplete="current-password"
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </label>
            <label className="flex items-center gap-2 text-sm text-muted-foreground">
              <input className="h-4 w-4 rounded border-input accent-primary" type="checkbox" />
              تذكرني على هذا الجهاز
            </label>
            <button disabled={loading} className="h-12 w-full rounded-xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60" type="submit">
              {loading ? 'جاري تسجيل الدخول...' : 'تسجيل الدخول'}
            </button>
          </form>

          <div className="mt-6">
            <ConnectionDiagnostics autoRunKey={diagnosticsKey} />
          </div>

          <p className="mt-6 text-center text-xs text-muted-foreground">تحتاج مساعدة؟ تواصل مع مسؤول النظام</p>
        </div>
      </div>
    </div>
  )
}
