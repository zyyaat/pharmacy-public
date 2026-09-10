"use client"

import { FormEvent, useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/hooks/useAuth'
import BrandSplash from '@/components/brand-splash'
import { ApiError } from '@/lib/api'
import { getSafeRedirectPath } from '@/lib/navigation'

export default function LoginPage() {
  const router = useRouter()
  const { login, user, loading: authLoading } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [redirectPath, setRedirectPath] = useState<string | null>(null)

  useEffect(() => {
    setRedirectPath(getSafeRedirectPath(new URLSearchParams(window.location.search).get('next')))
  }, [])

  useEffect(() => {
    // جلسة صالحة؟ التحويل لنقطة البيع فوراً — سواء مع ?next= أو بدون
    if (!authLoading && user) {
      router.replace(redirectPath || '/')
    }
  }, [authLoading, redirectPath, router, user])

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setError('')
    setLoading(true)
    try {
      await login(email, password)
      router.replace(redirectPath || '/')
    } catch (err) {
      if (err instanceof ApiError && err.code === 'EMAIL_NOT_VERIFIED') {
        setError('هذا البريد غير موثق — أكمل توثيق الحساب من تطبيق الإدارة الرئيسي أولًا')
        return
      }
      setError(err instanceof Error ? err.message : 'فشل تسجيل الدخول')
    } finally {
      setLoading(false)
    }
  }

  if (authLoading || user) {
    return <BrandSplash />
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4 py-8">
      <div className="absolute -right-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
      <div className="absolute -bottom-40 -left-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />
      <div className="relative grid w-full max-w-5xl overflow-hidden rounded-3xl border border-border bg-card shadow-2xl lg:grid-cols-[1.05fr_0.95fr]">
        <div className="hidden flex-col justify-between bg-primary p-10 text-primary-foreground lg:flex">
          <div>
            <div>
              <img src="/brand/pharmacy-os-logo-dark.svg" alt="Pharmacy POS" className="h-11 w-auto" width="260" height="64" />
              <p className="mt-2 text-xs text-primary-foreground/70">نقطة البيع — سريعة وخفيفة</p>
            </div>
            <div className="mt-24">
              <p className="text-sm font-medium text-primary-foreground/70">مرحبًا بعودتك</p>
              <h1 className="mt-3 text-4xl font-bold leading-tight">بيع أسرع،<br />وفواتير بلا انتظار.</h1>
              <p className="mt-5 max-w-sm text-sm leading-7 text-primary-foreground/75">
                شاشة بيع مخصصة للكاشير: بحث بالباركود، إيصالات فورية، والبيع الآجل — بنفس صلاحيات صيدليتك.
              </p>
            </div>
          </div>
          <p className="text-xs text-primary-foreground/60">© 2024 Pharmacy OS · نقطة البيع</p>
        </div>

        <div className="p-7 sm:p-10">
          <div className="mb-10 lg:hidden">
            <div>
              <img src="/brand/pharmacy-os-logo-light.svg" alt="Pharmacy POS" className="h-10 w-auto" width="260" height="64" />
              <p className="mt-2 text-xs text-muted-foreground">نقطة البيع</p>
            </div>
          </div>
          <div>
            <p className="text-sm font-medium text-primary">تسجيل الدخول</p>
            <h2 className="mt-2 text-2xl font-bold">أهلًا بك من جديد</h2>
            <p className="mt-2 text-sm text-muted-foreground">سجّل دخولك بحسابك في الصيدلية للوصول إلى نقطة البيع.</p>
          </div>
          <form className="mt-8 space-y-5" autoComplete="on" onSubmit={handleSubmit}>
            {error && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
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
          <p className="mt-8 text-center text-xs text-muted-foreground">تحتاج مساعدة؟ تواصل مع صاحب الصيدلية</p>
        </div>
      </div>
    </div>
  )
}
