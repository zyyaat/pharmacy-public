"use client"

import { FormEvent, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { apiFetch } from '@/lib/api'

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
  const [form, setForm] = useState(initialForm)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  function update(field: keyof RegisterForm, value: string) {
    setForm((current) => ({ ...current, [field]: value }))
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')

    if (form.password !== form.confirmPassword) {
      setError('كلمتا المرور غير متطابقتين')
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
      setError(registrationError instanceof Error ? registrationError.message : 'تعذر إنشاء الحساب')
      setLoading(false)
    }
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4 py-8" dir="rtl">
      <div className="absolute -right-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
      <div className="absolute -bottom-40 -left-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />
      <div className="relative w-full max-w-2xl rounded-3xl border border-border bg-card p-7 shadow-2xl sm:p-10">
        <div className="mb-8">
          <img src="/brand/pharmacy-os-logo-light.svg" alt="Pharmacy OS" className="h-11 w-auto" width="260" height="64" />
          <p className="mt-2 text-xs text-muted-foreground">إنشاء مساحة الصيدلية</p>
        </div>

        <div>
          <p className="text-sm font-medium text-primary">ابدأ في دقائق</p>
          <h1 className="mt-2 text-3xl font-bold">أنشئ حساب صيدليتك</h1>
          <p className="mt-3 text-sm leading-7 text-muted-foreground">
            سننشئ الشركة والصيدلية والفرع الرئيسي تلقائيًا، ثم ندخلك إلى لوحة التحكم مباشرة.
          </p>
        </div>

        <form className="mt-8 grid gap-5" onSubmit={handleSubmit}>
          {error && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive" role="alert">{error}</p>}
          <label className="block">
            <span className="mb-2 block text-sm font-medium">اسم الصيدلية</span>
            <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required minLength={2} value={form.companyName} onChange={(event) => update('companyName', event.target.value)} placeholder="صيدلية الشفاء" />
          </label>
          <label className="block">
            <span className="mb-2 block text-sm font-medium">بريد الصيدلية</span>
            <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required type="email" value={form.companyEmail} onChange={(event) => update('companyEmail', event.target.value)} placeholder="pharmacy@example.com" />
          </label>
          <div className="grid gap-5 sm:grid-cols-2">
            <label className="block">
              <span className="mb-2 block text-sm font-medium">الاسم الأول</span>
              <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required value={form.firstName} onChange={(event) => update('firstName', event.target.value)} placeholder="أحمد" />
            </label>
            <label className="block">
              <span className="mb-2 block text-sm font-medium">اسم العائلة</span>
              <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required value={form.lastName} onChange={(event) => update('lastName', event.target.value)} placeholder="محمد" />
            </label>
          </div>
          <label className="block">
            <span className="mb-2 block text-sm font-medium">بريد صاحب الصيدلية</span>
            <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required type="email" autoComplete="email" value={form.email} onChange={(event) => update('email', event.target.value)} placeholder="owner@example.com" />
          </label>
          <div className="grid gap-5 sm:grid-cols-2">
            <label className="block">
              <span className="mb-2 block text-sm font-medium">كلمة المرور</span>
              <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required minLength={10} type="password" autoComplete="new-password" value={form.password} onChange={(event) => update('password', event.target.value)} placeholder="10 أحرف أو أكثر" />
            </label>
            <label className="block">
              <span className="mb-2 block text-sm font-medium">تأكيد كلمة المرور</span>
              <input className="h-12 w-full rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10" required minLength={10} type="password" autoComplete="new-password" value={form.confirmPassword} onChange={(event) => update('confirmPassword', event.target.value)} placeholder="أعد كتابة كلمة المرور" />
            </label>
          </div>
          <p className="text-xs text-muted-foreground">استخدم حرفًا كبيرًا وصغيرًا ورقمًا ورمزًا خاصًا.</p>
          <button className="h-12 rounded-xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60" disabled={loading} type="submit">
            {loading ? 'جاري إنشاء الحساب...' : 'إنشاء الحساب والبدء'}
          </button>
        </form>

        <p className="mt-8 text-center text-sm text-muted-foreground">
          لديك حساب بالفعل؟{' '}
          <Link className="font-medium text-primary hover:underline" href="/login">تسجيل الدخول</Link>
        </p>
      </div>
    </div>
  )
}