'use client'

import { useEffect } from 'react'
import { getPharmacyAppUrl } from '@/lib/app-links'

export default function RegisterRedirectPage() {
  useEffect(() => {
    // /start بوابة ذكية: جلسة صالحة → لوحة التحكم، وإلا → صفحة التسجيل
    window.location.replace(`${getPharmacyAppUrl()}/start`)
  }, [])

  return (
    <main className="auth-shell" dir="rtl">
      <section className="auth-card auth-status-card" aria-live="polite">
        <div className="status-icon">→</div>
        <p className="eyebrow">Pharmacy OS</p>
        <h1>جاري فتح تطبيق الصيدلية</h1>
        <p>جلسة صالحة؟ ستدخل لوحة التحكم مباشرة، وإلا سنوجّهك لإنشاء الحساب.</p>
      </section>
    </main>
  )
}