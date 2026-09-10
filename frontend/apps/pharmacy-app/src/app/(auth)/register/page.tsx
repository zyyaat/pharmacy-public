"use client"

import { FormEvent, useEffect, useState } from 'react'
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

export default function RegisterPage() {
  const router = useRouter()
  const { user, loading: authLoading } = useAuth()
  const t = useT('auth')
  const [form, setForm] = useState(initialForm)
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

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')

    if (form.password !== form.confirmPassword) {
      setError(t('password_mismatch'))
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

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4 py-8">
      <div className="absolute -start-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
      <div className="absolute -bottom-40 -end-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />
      <div className="relative w-full max-w-2xl rounded-3xl border border-border bg-card p-7 shadow-2xl sm:p-10">
        <div className="mb-8">
          <img src="/brand/pharmacy-os-logo-light.svg" alt="Pharmacy OS" className="h-11 w-auto" width="260" height="64" />
          <p className="mt-2 text-xs text-muted-foreground">{t('register_tagline')}</p>
        </div>

        <div>
          <p className="text-sm font-medium text-primary">{t('start_minutes')}</p>
          <h1 className="mt-2 text-3xl font-bold">{t('register_heading')}</h1>
          <p className="mt-3 text-sm leading-7 text-muted-foreground">
            {t('register_body')}
          </p>
        </div>

        <form className="mt-8 grid gap-5" onSubmit={handleSubmit}>
          {error && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive" role="alert">{error}</p>}
          <label className="block">
            <span className="mb-2 block text-sm font-medium">{t('pharmacy_name')}</span>
            <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required minLength={2} value={form.companyName} onChange={(event) => update('companyName', event.target.value)} placeholder={t('pharmacy_name_ph')} />
          </label>
          <label className="block">
            <span className="mb-2 block text-sm font-medium">{t('pharmacy_email')}</span>
            <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required type="email" value={form.companyEmail} onChange={(event) => update('companyEmail', event.target.value)} placeholder="pharmacy@example.com" />
          </label>
          <div className="grid gap-5 sm:grid-cols-2">
            <label className="block">
              <span className="mb-2 block text-sm font-medium">{t('first_name')}</span>
              <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required value={form.firstName} onChange={(event) => update('firstName', event.target.value)} placeholder={t('first_name_ph')} />
            </label>
            <label className="block">
              <span className="mb-2 block text-sm font-medium">{t('last_name')}</span>
              <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required value={form.lastName} onChange={(event) => update('lastName', event.target.value)} placeholder={t('last_name_ph')} />
            </label>
          </div>
          <label className="block">
            <span className="mb-2 block text-sm font-medium">{t('owner_email')}</span>
            <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required type="email" autoComplete="email" value={form.email} onChange={(event) => update('email', event.target.value)} placeholder="owner@example.com" />
          </label>
          <div className="grid gap-5 sm:grid-cols-2">
            <label className="block">
              <span className="mb-2 block text-sm font-medium">{t('password')}</span>
              <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required minLength={10} type="password" autoComplete="new-password" value={form.password} onChange={(event) => update('password', event.target.value)} placeholder={t('password_ph')} />
            </label>
            <label className="block">
              <span className="mb-2 block text-sm font-medium">{t('confirm_password')}</span>
              <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required minLength={10} type="password" autoComplete="new-password" value={form.confirmPassword} onChange={(event) => update('confirmPassword', event.target.value)} placeholder={t('confirm_password_ph')} />
            </label>
          </div>
          <p className="text-xs text-muted-foreground">{t('password_hint')}</p>
          <button className="h-12 rounded-xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60" disabled={loading} type="submit">
            {loading ? t('creating_account') : t('create_and_start')}
          </button>
        </form>

        <p className="mt-8 text-center text-sm text-muted-foreground">
          {t('have_account')}{' '}
          <Link className="font-medium text-primary hover:underline" href="/login">{t('login_label')}</Link>
        </p>
      </div>
    </div>
  )
}
