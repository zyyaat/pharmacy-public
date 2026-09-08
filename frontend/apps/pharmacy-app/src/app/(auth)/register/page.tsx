"use client"

import { FormEvent, useState } from 'react'
import Link from 'next/link'
import { ApiError, authApi } from '@/lib/api'

const PASSWORD_HINT =
  'كلمة المرور: 10 أحرف على الأقل وتشمل حرف كبير (A-Z) + حرف صغير (a-z) + رقم (0-9) + رمز خاص (!@#...)'

export default function RegisterPage() {
  const [form, setForm] = useState({
    companyName: '',
    companyEmail: '',
    firstName: '',
    lastName: '',
    email: '',
    password: '',
  })
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState<ApiError | null>(null)
  const [genericError, setGenericError] = useState('')
  const [successMessage, setSuccessMessage] = useState('')
  const [loading, setLoading] = useState(false)

  function setField(key: keyof typeof form, value: string) {
    setForm((prev) => ({ ...prev, [key]: value }))
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setError(null)
    setGenericError('')
    setSuccessMessage('')

    if (!form.companyName || !form.companyEmail || !form.firstName || !form.lastName || !form.email || !form.password) {
      setGenericError('يرجى تعبئة جميع الحقول')
      return
    }

    setLoading(true)
    try {
      const response = await authApi.register({
        companyName: form.companyName,
        companyEmail: form.companyEmail,
        firstName: form.firstName,
        lastName: form.lastName,
        email: form.email,
        password: form.password,
      })
      setSuccessMessage(response?.message || 'تم إنشاء الحساب بنجاح. يمكنك تسجيل الدخول الآن.')
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err)
      } else {
        setGenericError(err instanceof Error ? err.message : 'فشل إنشاء الحساب')
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4 py-8">
      <div className="absolute -right-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
      <div className="absolute -bottom-40 -left-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />

      <div className="relative w-full max-w-lg rounded-3xl border border-border bg-card p-7 shadow-2xl sm:p-10">
        {/* Header */}
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-primary text-xl font-black text-primary-foreground">P</div>
          <p className="text-sm font-medium text-primary">إنشاء حساب جديد</p>
          <h1 className="mt-2 text-2xl font-bold">أنشئ شركتك وابدأ الإدارة</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            سيتم إنشاء شركة جديدة مع حساب مالك تستخدمه لتسجيل الدخول
          </p>
        </div>

        {/* Success */}
        {successMessage && (
          <div className="mb-6 rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-4" role="status">
            <p className="text-sm font-semibold text-emerald-600 dark:text-emerald-400">{successMessage}</p>
            <Link
              href="/login"
              className="mt-3 flex h-11 w-full items-center justify-center rounded-xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90"
            >
              الذهاب لتسجيل الدخول
            </Link>
          </div>
        )}

        {/* Form */}
        {!successMessage && (
          <form className="space-y-5" onSubmit={handleSubmit}>
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
                <details className="mt-3 rounded-lg bg-background/60 p-2">
                  <summary className="cursor-pointer text-xs font-medium text-destructive">التفاصيل التقنية الكاملة</summary>
                  <pre className="mt-2 max-h-44 overflow-auto whitespace-pre-wrap break-all text-[11px] leading-5 text-muted-foreground" dir="ltr">
{JSON.stringify(error.toJSON(), null, 2)}
                  </pre>
                </details>
              </div>
            )}
            {!error && genericError && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{genericError}</p>}

            <label className="block">
              <span className="mb-2 block text-sm font-medium">اسم الشركة</span>
              <input
                className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none transition-all placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10"
                placeholder="مثال: صيدليات النور"
                type="text"
                value={form.companyName}
                onChange={(event) => setField('companyName', event.target.value)}
              />
            </label>

            <label className="block">
              <span className="mb-2 block text-sm font-medium">بريد الشركة</span>
              <input
                className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none transition-all placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10"
                placeholder="info@pharmacy.com"
                autoComplete="email"
                dir="ltr"
                type="email"
                value={form.companyEmail}
                onChange={(event) => setField('companyEmail', event.target.value)}
              />
            </label>

            <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
              <label className="block">
                <span className="mb-2 block text-sm font-medium">الاسم الأول</span>
                <input
                  className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none transition-all placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10"
                  placeholder="محمد"
                  type="text"
                  value={form.firstName}
                  onChange={(event) => setField('firstName', event.target.value)}
                />
              </label>
              <label className="block">
                <span className="mb-2 block text-sm font-medium">اسم العائلة</span>
                <input
                  className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none transition-all placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10"
                  placeholder="أحمد"
                  type="text"
                  value={form.lastName}
                  onChange={(event) => setField('lastName', event.target.value)}
                />
              </label>
            </div>

            <label className="block">
              <span className="mb-2 block text-sm font-medium">بريد المالك (للتسجيل دخول)</span>
              <input
                className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none transition-all placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10"
                placeholder="owner@pharmacy.com"
                autoComplete="email"
                dir="ltr"
                type="email"
                value={form.email}
                onChange={(event) => setField('email', event.target.value)}
              />
            </label>

            <label className="block">
              <span className="mb-2 block text-sm font-medium">كلمة المرور</span>
              <div className="relative">
                <input
                  className="h-12 w-full rounded-xl border border-input bg-background px-4 pl-12 text-sm outline-none transition-all placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10"
                  placeholder="••••••••"
                  autoComplete="new-password"
                  dir="ltr"
                  type={showPassword ? 'text' : 'password'}
                  value={form.password}
                  onChange={(event) => setField('password', event.target.value)}
                />
                <button
                  className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-medium text-primary hover:underline"
                  onClick={() => setShowPassword((value) => !value)}
                  type="button"
                >
                  {showPassword ? 'إخفاء' : 'إظهار'}
                </button>
              </div>
              <span className="mt-2 block text-xs leading-5 text-muted-foreground">{PASSWORD_HINT}</span>
            </label>

            <button
              disabled={loading}
              className="h-12 w-full rounded-xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60"
              type="submit"
            >
              {loading ? 'جاري إنشاء الحساب...' : 'إنشاء الحساب'}
            </button>
          </form>
        )}

        <p className="mt-6 text-center text-sm text-muted-foreground">
          لديك حساب بالفعل؟{' '}
          <Link className="font-medium text-primary hover:underline" href="/login">
            تسجيل الدخول
          </Link>
        </p>
      </div>
    </div>
  )
}
