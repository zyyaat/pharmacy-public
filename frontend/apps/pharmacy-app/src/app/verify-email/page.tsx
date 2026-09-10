'use client'

import { FormEvent, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/hooks/useAuth'
import BrandSplash from '@/components/brand-splash'
import { authApi } from '@/lib/api'
import { getSafeRedirectPath } from '@/lib/navigation'
import { useT } from '@/i18n/provider'

export default function VerifyEmailPage() {
  const router = useRouter()
  const { user, loading: authLoading } = useAuth()
  const t = useT('auth')
  const [email, setEmail] = useState('')
  const [code, setCode] = useState('')
  const [message, setMessage] = useState<string>(t('verify_default_message'))
  const [error, setError] = useState(false)
  const [sending, setSending] = useState(false)
  const [verifying, setVerifying] = useState(false)
  const [sent, setSent] = useState(false)

  useEffect(() => {
    if (!authLoading && user) {
      router.replace(getSafeRedirectPath(new URLSearchParams(window.location.search).get('next')))
    }
  }, [authLoading, router, user])

  useEffect(() => {
    if (authLoading || user) return
    const params = new URLSearchParams(window.location.search)
    const pendingEmail = params.get('email')?.trim() || ''
    setEmail(pendingEmail)
    if (params.get('sent') === '0') {
      setError(true)
      setMessage(t('verify_send_failed_on_create'))
    }
    if (!pendingEmail) return

    let cancelled = false
    setSending(true)
    void authApi.resendVerification(pendingEmail)
      .then((response) => {
        if (cancelled) return
        setSent(response.sent !== false)
        setError(false)
        setMessage(
          response.sent === false
            ? t('verify_code_exists')
            : t('verify_code_sent'),
        )
      })
      .catch((resendError) => {
        if (cancelled) return
        setError(true)
        setMessage(resendError instanceof Error ? resendError.message : t('verify_resend_failed'))
      })
      .finally(() => {
        if (!cancelled) setSending(false)
      })
    return () => {
      cancelled = true
    }
  }, [authLoading, user])

  async function verifyEmail(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (code.length !== 6 || !/^\d{6}$/.test(code)) {
      setError(true)
      setMessage(t('verify_default_message'))
      return
    }
    if (!email) {
      setError(true)
      setMessage(t('verify_email_first'))
      return
    }

    setVerifying(true)
    setError(false)
    try {
      await authApi.verifyEmail(email, code)
      setMessage(t('verify_success'))
      window.setTimeout(() => window.location.assign('/login'), 900)
    } catch (verificationError) {
      setError(true)
      setMessage(verificationError instanceof Error ? verificationError.message : t('verify_failed'))
    } finally {
      setVerifying(false)
    }
  }

  async function resendVerification() {
    if (!email || sending) return
    setSending(true)
    setError(false)
    setSent(false)
    try {
      const response = await authApi.resendVerification(email)
      setSent(response.sent !== false)
      setMessage(
        response.sent === false
          ? t('verify_code_exists')
          : t('verify_code_sent'),
      )
    } catch (resendError) {
      setError(true)
      setMessage(resendError instanceof Error ? resendError.message : t('verify_resend_failed'))
    } finally {
      setSending(false)
    }
  }

  if (authLoading || user) {
    return <BrandSplash />
  }

  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4 py-8">
      <div className="absolute -start-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
      <div className="absolute -bottom-40 -end-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />
      <section className="relative w-full max-w-lg rounded-3xl border border-border bg-card p-8 text-center shadow-2xl sm:p-12" aria-live="polite">
        <div className={`mx-auto flex h-16 w-16 items-center justify-center rounded-2xl text-2xl font-black ${error ? 'bg-destructive/10 text-destructive' : 'bg-primary/10 text-primary'}`}>
          {error ? '!' : '✓'}
        </div>
        <p className="mt-6 text-sm font-medium text-primary">Pharmacy OS</p>
        <h1 className="mt-3 text-2xl font-bold leading-relaxed">{t('verify_heading')}</h1>
        <p className={`mt-3 text-sm leading-7 ${error ? 'text-destructive' : 'text-muted-foreground'}`}>{message}</p>

        <form className="mt-8 space-y-4 text-start" onSubmit={verifyEmail}>
          <label className="block">
            <span className="mb-2 block text-sm font-medium">{t('email')}</span>
            <input
              className="h-12 w-full rounded-xl border border-input bg-background px-4 text-left text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10"
              dir="ltr"
              type="email"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="name@pharmacy.com"
            />
          </label>
          <label className="block">
            <span className="mb-2 block text-sm font-medium">{t('code_label')}</span>
            <input
              className="h-14 w-full rounded-xl border border-input bg-background px-4 text-center text-2xl font-bold tracking-[0.6em] outline-none focus:border-primary focus:ring-4 focus:ring-primary/10"
              dir="ltr"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              pattern="[0-9]{6}"
              required
              value={code}
              onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
              placeholder="000000"
            />
          </label>
          <button
            className="h-12 w-full rounded-xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60"
            type="submit"
            disabled={verifying}
          >
            {verifying ? t('verifying') : t('verify_button')}
          </button>
        </form>

        <button
          className="mt-4 text-sm font-medium text-primary hover:underline disabled:cursor-not-allowed disabled:opacity-50"
          type="button"
          onClick={resendVerification}
          disabled={!email || sending}
        >
          {sending ? t('sending_code') : t('resend_button')}
        </button>
        {sent && <p className="mt-3 text-sm text-emerald-600">{t('check_inbox')}</p>}

        <Link className="mt-8 inline-flex h-11 items-center rounded-xl border border-border px-6 text-sm font-semibold transition hover:bg-muted" href="/login">
          {t('back_to_login')}
        </Link>
      </section>
    </main>
  )
}
