"use client"

import { FormEvent, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/hooks/useAuth'
import BrandSplash from '@/components/brand-splash'
import { ApiError } from '@/lib/api'
import { getSafeRedirectPath } from '@/lib/navigation'
import { useT } from '@/i18n/provider'

export default function LoginPage() {
  const router = useRouter()
  const { login, user, loading: authLoading } = useAuth()
  const t = useT('auth')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [redirectPath, setRedirectPath] = useState<string | null>(null)

  useEffect(() => {
    setRedirectPath(getSafeRedirectPath(new URLSearchParams(window.location.search).get('next')))
  }, [])

  useEffect(() => {
    // جلسة صالحة؟ التحويل للوحة فوراً — سواء مع ?next= أو بدون
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
      // Task 50 — تحميل كامل بعد الدخول: كاش الراوتر قد يحمل رسومًا مسبقة بلغة
      // ما قبل الدخول، والتنقل الكامل يضمن فرشاة خادم بلغة الحساب من قاعدة البيانات
      window.location.assign(redirectPath || '/')
    } catch (err) {
      if (err instanceof ApiError && err.code === 'EMAIL_NOT_VERIFIED') {
        router.replace(`/verify-email?email=${encodeURIComponent(email.trim())}`)
        return
      }
      setError(err instanceof Error ? err.message : t('login_failed'))
    } finally {
      setLoading(false)
    }
  }

  if (authLoading || user) {
    return <BrandSplash />
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4 py-8">
      <div className="absolute -start-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
      <div className="absolute -bottom-40 -end-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />
      <div className="relative grid w-full max-w-5xl overflow-hidden rounded-3xl border border-border bg-card shadow-2xl lg:grid-cols-[1.05fr_0.95fr]">
        <div className="hidden flex-col justify-between bg-primary p-10 text-primary-foreground lg:flex">
          <div>
            <div>
              <img src="/brand/pharmacy-os-logo-dark.svg" alt="Pharmacy OS" className="h-11 w-auto" width="260" height="64" />
              <p className="mt-2 text-xs text-primary-foreground/70">{t('brand_tagline')}</p>
            </div>
            <div className="mt-24">
              <p className="text-sm font-medium text-primary-foreground/70">{t('welcome_back')}</p>
              <h1 className="mt-3 text-4xl font-bold leading-tight">{t('hero_title_a')}<br />{t('hero_title_b')}</h1>
              <p className="mt-5 max-w-sm text-sm leading-7 text-primary-foreground/75">
                {t('hero_body')}
              </p>
            </div>
          </div>
          <p className="text-xs text-primary-foreground/60">{t('footer_version')}</p>
        </div>

        <div className="p-7 sm:p-10">
          <div className="mb-10 lg:hidden">
            <div>
              <img src="/brand/pharmacy-os-logo-light.svg" alt="Pharmacy OS" className="h-10 w-auto" width="260" height="64" />
              <p className="mt-2 text-xs text-muted-foreground">{t('mobile_tagline')}</p>
            </div>
          </div>
          <div>
            <p className="text-sm font-medium text-primary">{t('login_label')}</p>
            <h2 className="mt-2 text-2xl font-bold">{t('login_heading')}</h2>
            <p className="mt-2 text-sm text-muted-foreground">{t('login_subtext')}</p>
          </div>
          <form className="mt-8 space-y-5" autoComplete="on" onSubmit={handleSubmit}>
            {error && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
            <label className="block">
              <span className="mb-2 block text-sm font-medium">{t('email')}</span>
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
                <span className="text-sm font-medium">{t('password')}</span>
                <button className="text-xs font-medium text-primary hover:underline" type="button">{t('forgot_password')}</button>
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
              {t('remember_me')}
            </label>
            <button disabled={loading} className="h-12 w-full rounded-xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60" type="submit">
              {loading ? t('logging_in') : t('login_label')}
            </button>
          </form>
          <p className="mt-6 text-center text-sm text-muted-foreground">
            {t('no_account')}{' '}
            <Link className="font-medium text-primary hover:underline" href="/register">{t('create_account_link')}</Link>
          </p>
          <p className="mt-8 text-center text-xs text-muted-foreground">{t('need_help')}</p>
        </div>
      </div>
    </div>
  )
}
