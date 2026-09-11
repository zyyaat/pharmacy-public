"use client"

// Task 57 — التسجيل الذكي بأسلوب Upwork: سؤال واحد في كل شاشة مع شريط
// تقدم ومتابعة سلسة، بدل النموذج الطويل الوحيد. نفس نقطة النهاية
// /auth/register تمامًا — التغيير تجربة استخدام فقط.

import { FormEvent, KeyboardEvent, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/hooks/useAuth'
import BrandSplash from '@/components/brand-splash'
import { apiFetch } from '@/lib/api'
import { useT } from '@/i18n/provider'

type RegisterForm = {
  companyName: string
  companyEmail: string
  firstName: string
  lastName: string
  email: string
  password: string
  confirmPassword: string
}

const initialForm: RegisterForm = {
  companyName: '',
  companyEmail: '',
  firstName: '',
  lastName: '',
  email: '',
  password: '',
  confirmPassword: '',
}

const STEPS = 4
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export default function RegisterPage() {
  const router = useRouter()
  const { user, loading: authLoading } = useAuth()
  const t = useT('auth')
  const [form, setForm] = useState(initialForm)
  const [step, setStep] = useState(0)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    // مسجل دخوله بالفعل؟ لا داعي لصفحة التسجيل — نحوّله للوحة
    if (!authLoading && user) {
      router.replace('/')
    }
  }, [authLoading, user, router])

  if (authLoading || user) {
    return <BrandSplash />
  }

  function update(field: keyof RegisterForm, value: string) {
    setForm((current) => ({ ...current, [field]: value }))
  }

  function validateStep(target: number): string {
    if (target === 0 && form.companyName.trim().length < 2) return t('reg_err_name')
    if (target === 1) {
      if (!form.firstName.trim()) return t('reg_err_first')
      if (!form.lastName.trim()) return t('reg_err_last')
    }
    if (target === 2) {
      if (!EMAIL_RE.test(form.companyEmail.trim())) return t('reg_err_email')
      if (!EMAIL_RE.test(form.email.trim())) return t('reg_err_email')
    }
    if (target === 3 && form.password !== form.confirmPassword) return t('password_mismatch')
    return ''
  }

  function advance() {
    const problem = validateStep(step)
    if (problem) {
      setError(problem)
      return
    }
    setError('')
    setStep((current) => Math.min(current + 1, STEPS - 1))
  }

  function back() {
    setError('')
    setStep((current) => Math.max(current - 1, 0))
  }

  // Enter = متابعة للخطوة التالية في كل الخطوات (والخطوة الأخيرة تُرسل النموذج)
  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === 'Enter' && step < STEPS - 1) {
      event.preventDefault()
      advance()
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')

    const problem = validateStep(3) || validateStep(2) || validateStep(1) || validateStep(0)
    if (problem) {
      setError(problem)
      return
    }

    setLoading(true)
    try {
      const body = await apiFetch<{ email_verification_sent?: boolean }>('/auth/register', {
        method: 'POST',
        body: JSON.stringify({
          company_name: form.companyName,
          company_email: form.companyEmail,
          first_name: form.firstName,
          last_name: form.lastName,
          email: form.email,
          password: form.password,
        }),
      })
      const verificationSent = body.email_verification_sent !== false
      router.replace(
        `/verify-email?email=${encodeURIComponent(form.email.trim())}&sent=${verificationSent ? '1' : '0'}`,
      )
    } catch (registrationError) {
      setError(registrationError instanceof Error ? registrationError.message : t('register_failed'))
      setLoading(false)
    }
  }

  const inputClass =
    'h-14 w-full rounded-2xl border border-input bg-background px-5 text-base outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/10'
  const titles = [t('reg_q1_title'), t('reg_q2_title'), t('reg_q3_title'), t('reg_q4_title')]
  const subtitles = [t('reg_q1_sub'), t('reg_q2_sub'), t('reg_q3_sub'), t('reg_q4_sub')]

  return (
    <div className="relative flex min-h-screen flex-col overflow-hidden bg-background px-4 py-6 sm:py-10">
      <div className="absolute -start-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
      <div className="absolute -bottom-40 -end-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />

      {/* الشريط العلوي: الهوية + شريط التقدم بأسلوب Upwork */}
      <header className="relative mx-auto flex w-full max-w-xl items-center gap-4">
        <img src="/brand/pharmacy-os-logo-light.svg" alt="Pharmacy OS" className="h-9 w-auto" width="200" height="48" />
        <div className="ms-auto flex items-center gap-3">
          <span className="text-xs font-medium text-muted-foreground">
            {t('reg_step')} {step + 1} {t('reg_of')} {STEPS}
          </span>
          <div className="h-1.5 w-32 overflow-hidden rounded-full bg-muted sm:w-44">
            <div
              className="h-full rounded-full bg-primary transition-all duration-500 ease-out"
              style={{ width: `${((step + 1) / STEPS) * 100}%` }}
            />
          </div>
        </div>
      </header>

      {/* بطاقة الخطوة الواحدة */}
      <main className="relative mx-auto flex w-full max-w-xl flex-1 items-center">
        <div key={step} className="animate-fade-in w-full rounded-3xl border border-border bg-card p-7 shadow-2xl sm:p-10">
          <h1 className="text-2xl font-bold leading-relaxed sm:text-3xl">{titles[step]}</h1>
          <p className="mt-3 text-sm leading-7 text-muted-foreground">{subtitles[step]}</p>

          <form className="mt-8 grid gap-5" onSubmit={handleSubmit}>
            {error && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive" role="alert">{error}</p>}

            {step === 0 && (
              <label className="block">
                <span className="sr-only">{t('pharmacy_name')}</span>
                <input
                  className={inputClass}
                  autoFocus
                  required
                  minLength={2}
                  value={form.companyName}
                  onChange={(event) => update('companyName', event.target.value)}
                  onKeyDown={onKeyDown}
                  placeholder={t('pharmacy_name_ph')}
                />
              </label>
            )}

            {step === 1 && (
              <div className="grid gap-5 sm:grid-cols-2">
                <label className="block">
                  <span className="mb-2 block text-sm font-medium">{t('first_name')}</span>
                  <input
                    className={inputClass}
                    autoFocus
                    required
                    value={form.firstName}
                    onChange={(event) => update('firstName', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder={t('first_name_ph')}
                  />
                </label>
                <label className="block">
                  <span className="mb-2 block text-sm font-medium">{t('last_name')}</span>
                  <input
                    className={inputClass}
                    required
                    value={form.lastName}
                    onChange={(event) => update('lastName', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder={t('last_name_ph')}
                  />
                </label>
              </div>
            )}

            {step === 2 && (
              <>
                <label className="block">
                  <span className="mb-2 block text-sm font-medium">{t('pharmacy_email')}</span>
                  <input
                    className={`${inputClass} text-start`}
                    dir="ltr"
                    autoFocus
                    required
                    type="email"
                    value={form.companyEmail}
                    onChange={(event) => update('companyEmail', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder="pharmacy@example.com"
                  />
                  <span className="mt-2 block text-xs text-muted-foreground">{t('reg_email_pharmacy_hint')}</span>
                </label>
                <label className="block">
                  <span className="mb-2 block text-sm font-medium">{t('owner_email')}</span>
                  <input
                    className={inputClass}
                    dir="ltr"
                    required
                    type="email"
                    autoComplete="email"
                    value={form.email}
                    onChange={(event) => update('email', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder="owner@example.com"
                  />
                  <span className="mt-2 block text-xs text-muted-foreground">{t('reg_email_owner_hint')}</span>
                </label>
              </>
            )}

            {step === 3 && (
              <>
                <div className="grid gap-5 sm:grid-cols-2">
                  <label className="block">
                    <span className="mb-2 block text-sm font-medium">{t('password')}</span>
                    <input
                      className={inputClass}
                      autoFocus
                      required
                      minLength={10}
                      type="password"
                      autoComplete="new-password"
                      value={form.password}
                      onChange={(event) => update('password', event.target.value)}
                      placeholder={t('password_ph')}
                    />
                  </label>
                  <label className="block">
                    <span className="mb-2 block text-sm font-medium">{t('confirm_password')}</span>
                    <input
                      className={inputClass}
                      required
                      minLength={10}
                      type="password"
                      autoComplete="new-password"
                      value={form.confirmPassword}
                      onChange={(event) => update('confirmPassword', event.target.value)}
                      placeholder={t('confirm_password_ph')}
                    />
                  </label>
                </div>
                <p className="text-xs text-muted-foreground">{t('password_hint')}</p>
              </>
            )}

            <div className="mt-2 flex items-center gap-3">
              {step > 0 && (
                <button
                  className="h-13 rounded-2xl border border-border px-6 text-sm font-semibold transition hover:bg-muted"
                  type="button"
                  onClick={back}
                >
                  {t('reg_back')}
                </button>
              )}
              {step < STEPS - 1 ? (
                <button
                  className="h-13 flex-1 rounded-2xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90"
                  type="button"
                  onClick={advance}
                >
                  {t('reg_continue')}
                </button>
              ) : (
                <button
                  className="h-13 flex-1 rounded-2xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60"
                  disabled={loading}
                  type="submit"
                >
                  {loading ? t('creating_account') : t('create_and_start')}
                </button>
              )}
            </div>
          </form>
        </div>
      </main>

      <footer className="relative mx-auto w-full max-w-xl pb-2 text-center text-sm text-muted-foreground">
        {t('have_account')}{' '}
        <Link className="font-medium text-primary hover:underline" href="/login">{t('login_label')}</Link>
      </footer>
    </div>
  )
}
