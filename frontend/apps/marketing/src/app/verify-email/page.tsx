'use client'

import { useEffect, useState } from 'react'
import { getPharmacyAppUrl } from '@/lib/app-links'

export default function VerifyEmailPage() {
  const [message, setMessage] = useState('جاري تأكيد البريد الإلكتروني...')
  const [error, setError] = useState(false)

  useEffect(() => {
    const token = new URLSearchParams(window.location.search).get('token')
    if (!token) {
      setError(true)
      setMessage('رابط تأكيد البريد غير صالح')
      return
    }

    fetch('/api/v1/auth/verify-email', {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token }),
    })
      .then(async (response) => {
        const body = await response.json().catch(() => ({}))
        if (!response.ok) throw new Error(body.message || 'تعذر تأكيد البريد')
        setMessage('تم تأكيد البريد بنجاح. جاري فتح تطبيق الصيدلية...')
        window.setTimeout(() => window.location.assign(getPharmacyAppUrl()), 900)
      })
      .catch((verificationError) => {
        setError(true)
        setMessage(verificationError instanceof Error ? verificationError.message : 'تعذر تأكيد البريد')
      })
  }, [])

  return (
    <main className="auth-shell" dir="rtl">
      <section className="auth-card auth-status-card" aria-live="polite">
        <div className={`status-icon ${error ? 'status-icon-error' : ''}`}>{error ? '!' : '✓'}</div>
        <p className="eyebrow">Pharmacy OS</p>
        <h1>{message}</h1>
        {error && <a className="button button-primary" href="/register">العودة إلى التسجيل</a>}
      </section>
    </main>
  )
}