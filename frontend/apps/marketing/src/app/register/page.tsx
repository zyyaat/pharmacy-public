'use client'

import { useEffect } from 'react'
import { getPharmacyAppUrl } from '@/lib/app-links'

export default function RegisterRedirectPage() {
  useEffect(() => {
    window.location.replace(`${getPharmacyAppUrl()}/register`)
  }, [])

  return (
    <main className="auth-shell" dir="rtl">
      <section className="auth-card auth-status-card" aria-live="polite">
        <div className="status-icon">→</div>
        <p className="eyebrow">Pharmacy OS</p>
        <h1>جاري فتح تطبيق الصيدلية</h1>
        <p>سيتم تنفيذ التسجيل وتسجيل الدخول من داخل التطبيق.</p>
      </section>
    </main>
  )
}