'use client'

// Task 57 — معالج إعداد الصيدلية بأسلوب Upwork: يُفتح تلقائيًا بعد التحقق
// من البريد (الجلسة تُفتح هناك فورًا)، سؤال واحد في كل شاشة، شريط تقدم،
// تخطي للخطوات الاختيارية، مراجعة أخيرة ثم احتفال بالدخول إلى اللوحة.
// البيانات تُحفظ مرة واحدة في النهاية عبر PUT /pharmacy/onboarding.

import { useEffect, useState, type KeyboardEvent } from 'react'
import { useRouter } from 'next/navigation'
import { ClipboardList, MapPin, Phone, Store } from 'lucide-react'
import BrandSplash from '@/components/brand-splash'
import { useAuth } from '@/hooks/useAuth'
import { onboardingApi } from '@/lib/api'
import { useT } from '@/i18n/provider'

type Fields = {
  name: string
  phone: string
  website: string
  address_line1: string
  address_line2: string
  city: string
  state_province: string
  postal_code: string
}

const emptyFields: Fields = {
  name: '',
  phone: '',
  website: '',
  address_line1: '',
  address_line2: '',
  city: '',
  state_province: '',
  postal_code: '',
}

// أحجام نقاط الاحتفال: مواقع جانبية + ألوان الهوية + تأخيرات متدرجة
const CONFETTI = [
  { left: '18%', color: '#34d399', delay: '0s' },
  { left: '26%', color: '#22d3ee', delay: '0.15s' },
  { left: '34%', color: '#a3e635', delay: '0.3s' },
  { left: '46%', color: '#fbbf24', delay: '0.1s' },
  { left: '58%', color: '#34d399', delay: '0.25s' },
  { left: '68%', color: '#f472b6', delay: '0.05s' },
  { left: '76%', color: '#22d3ee', delay: '0.35s' },
  { left: '84%', color: '#a3e635', delay: '0.2s' },
]

export default function OnboardingPage() {
  const router = useRouter()
  const { user, loading: authLoading } = useAuth()
  const t = useT('auth')
  const [step, setStep] = useState(0) // 0 الاسم، 1 التواصل، 2 الموقع، 3 المراجعة، 4 النجاح
  const [fields, setFields] = useState<Fields>(emptyFields)
  const [loadState, setLoadState] = useState<'loading' | 'ready' | 'error'>('loading')
  const [reloadKey, setReloadKey] = useState(0)
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)

  // الحواجز: بلا جلسة → الدخول؛ جلسة مكتملة الإعداد → اللوحة مباشرة
  useEffect(() => {
    if (authLoading) return
    if (!user) {
      router.replace('/login?next=/onboarding')
      return
    }
    if (user.onboarding_required === false) {
      router.replace('/')
    }
  }, [authLoading, user, router])

  // التعبئة المسبقة من ملف الصيدلية الحالي (اسم التسجيل موجود أصلًا)
  useEffect(() => {
    if (authLoading || !user) return
    let cancelled = false
    onboardingApi.get()
      .then((response) => {
        if (cancelled) return
        const pharmacy = response.data.pharmacy
        setFields({
          name: pharmacy.name ?? '',
          phone: pharmacy.phone ?? '',
          website: pharmacy.website ?? '',
          address_line1: pharmacy.address_line1 ?? '',
          address_line2: pharmacy.address_line2 ?? '',
          city: pharmacy.city ?? '',
          state_province: pharmacy.state_province ?? '',
          postal_code: pharmacy.postal_code ?? '',
        })
        setLoadState('ready')
      })
      .catch(() => {
        if (!cancelled) setLoadState('error')
      })
    return () => {
      cancelled = true
    }
  }, [authLoading, user, reloadKey])

  if (authLoading || !user || loadState === 'loading') {
    return <BrandSplash />
  }

  const firstName = typeof user.first_name === 'string' ? user.first_name : ''

  function update(field: keyof Fields, value: string) {
    setFields((current) => ({ ...current, [field]: value }))
  }

  function validateStep(target: number): string {
    if (target === 0 && fields.name.trim().length < 2) return t('ob_name_required')
    return ''
  }

  function advance() {
    const problem = validateStep(step)
    if (problem) {
      setError(problem)
      return
    }
    setError('')
    setStep((current) => Math.min(current + 1, 3))
  }

  // تخطي الخطوات الاختيارية (التواصل/الموقع) دون فشل التحقق
  function skip() {
    setError('')
    setStep((current) => Math.min(current + 1, 3))
  }

  function back() {
    setError('')
    setStep((current) => Math.max(current - 1, 0))
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === 'Enter' && step < 3) {
      event.preventDefault()
      advance()
    }
  }

  async function finish() {
    setSaving(true)
    setError('')
    try {
      await onboardingApi.update({ ...fields, complete: true })
      setStep(4)
    } catch {
      setError(t('ob_err_save'))
    } finally {
      setSaving(false)
    }
  }

  const inputClass =
    'h-14 w-full rounded-2xl border border-input bg-background px-5 text-base outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/10'
  const stepIcons = [
    <Store key="s0" className="h-7 w-7" strokeWidth={2.2} />,
    <Phone key="s1" className="h-7 w-7" strokeWidth={2.2} />,
    <MapPin key="s2" className="h-7 w-7" strokeWidth={2.2} />,
    <ClipboardList key="s3" className="h-7 w-7" strokeWidth={2.2} />,
  ]
  const stepTitles = [t('ob_s1_title'), t('ob_s2_title'), t('ob_s3_title'), t('ob_s4_title')]
  const stepSubs = [t('ob_s1_sub'), t('ob_s2_sub'), t('ob_s3_sub'), t('ob_s4_sub')]

  if (loadState === 'error') {
    return (
      <main className="flex min-h-screen items-center justify-center bg-background px-4">
        <div className="w-full max-w-md rounded-3xl border border-border bg-card p-10 text-center shadow-2xl">
          <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-destructive/10 text-2xl font-black text-destructive">!</div>
          <p className="mt-6 text-sm leading-7 text-muted-foreground">{t('ob_err_load')}</p>
          <button
            className="mt-6 h-12 w-full rounded-2xl bg-primary text-sm font-semibold text-primary-foreground transition hover:bg-primary/90"
            onClick={() => { setLoadState('loading'); setReloadKey((key) => key + 1) }}
          >
            {t('ob_continue')}
          </button>
        </div>
      </main>
    )
  }

  // شاشة النجاح — علامة تنبض + نقاط احتفال تتصاعد
  if (step === 4) {
    return (
      <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4">
        <div className="absolute -start-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
        <div className="absolute -bottom-40 -end-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />
        <section className="relative w-full max-w-lg rounded-3xl border border-border bg-card p-10 text-center shadow-2xl sm:p-14">
          <div className="relative mx-auto h-24 w-24">
            {CONFETTI.map((dot, index) => (
              <span
                key={index}
                className="confetti-dot bottom-6"
                style={{ left: dot.left, backgroundColor: dot.color, animationDelay: dot.delay }}
              />
            ))}
            <div className="animate-pop-in flex h-24 w-24 items-center justify-center rounded-full bg-primary text-4xl font-black text-primary-foreground shadow-xl shadow-primary/30">
              ✓
            </div>
          </div>
          <h1 className="mt-8 text-3xl font-bold">{t('ob_success_title')}</h1>
          <p className="mt-3 text-sm leading-7 text-muted-foreground">{t('ob_success_sub')}</p>
          <button
            className="mt-8 h-13 w-full rounded-2xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90"
            onClick={() => window.location.assign('/')}
          >
            {t('ob_enter')}
          </button>
        </section>
      </main>
    )
  }

  const reviewRows: { label: string; value: string; target: number }[] = [
    { label: t('pharmacy_name'), value: fields.name, target: 0 },
    { label: t('ob_phone'), value: fields.phone, target: 1 },
    { label: t('ob_website'), value: fields.website, target: 1 },
    { label: t('ob_city'), value: fields.city, target: 2 },
    { label: t('ob_state'), value: fields.state_province, target: 2 },
    { label: t('ob_address1'), value: fields.address_line1, target: 2 },
    { label: t('ob_address2'), value: fields.address_line2, target: 2 },
    { label: t('ob_postal'), value: fields.postal_code, target: 2 },
  ]

  return (
    <div className="relative flex min-h-screen flex-col overflow-hidden bg-background px-4 py-6 sm:py-10">
      <div className="absolute -start-32 -top-32 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
      <div className="absolute -bottom-40 -end-24 h-96 w-96 rounded-full bg-emerald-400/10 blur-3xl" />

      <header className="relative mx-auto flex w-full max-w-xl items-center gap-4">
        <img src="/brand/pharmacy-os-logo-light.svg" alt="Pharmacy OS" className="h-9 w-auto" width="200" height="48" />
        <div className="ms-auto flex items-center gap-3">
          <span className="text-xs font-medium text-muted-foreground">
            {t('reg_step')} {step + 1} {t('reg_of')} 4
          </span>
          <div className="h-1.5 w-32 overflow-hidden rounded-full bg-muted sm:w-44">
            <div
              className="h-full rounded-full bg-primary transition-all duration-500 ease-out"
              style={{ width: `${((step + 1) / 4) * 100}%` }}
            />
          </div>
        </div>
      </header>

      <main className="relative mx-auto flex w-full max-w-xl flex-1 items-center">
        <div key={step} className="animate-fade-in w-full rounded-3xl border border-border bg-card p-7 shadow-2xl sm:p-10">
          <div className="flex items-center gap-4">
            <div className="flex h-13 w-13 shrink-0 items-center justify-center rounded-2xl bg-primary/10 text-primary">
              {stepIcons[step]}
            </div>
            <div className="min-w-0">
              <h1 className="text-xl font-bold leading-relaxed sm:text-2xl">{stepTitles[step]}</h1>
              <p className="mt-1 text-sm leading-6 text-muted-foreground">{stepSubs[step]}</p>
            </div>
          </div>

          <div className="mt-8 grid gap-5">
            {error && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive" role="alert">{error}</p>}

            {step === 0 && (
              <label className="block">
                <span className="mb-2 block text-sm font-medium">
                  {t('ob_welcome')} {firstName}، {t('ob_app_label')}
                </span>
                <input
                  className={inputClass}
                  autoFocus
                  value={fields.name}
                  onChange={(event) => update('name', event.target.value)}
                  onKeyDown={onKeyDown}
                  placeholder={t('pharmacy_name_ph')}
                />
              </label>
            )}

            {step === 1 && (
              <>
                <label className="block">
                  <span className="mb-2 block text-sm font-medium">{t('ob_phone')}</span>
                  <input
                    className={`${inputClass} text-end`}
                    dir="ltr"
                    inputMode="tel"
                    autoFocus
                    value={fields.phone}
                    onChange={(event) => update('phone', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder={t('ob_phone_ph')}
                  />
                </label>
                <label className="block">
                  <span className="mb-2 block text-sm font-medium">
                    {t('ob_website')} <span className="text-xs font-normal text-muted-foreground">({t('ob_optional')})</span>
                  </span>
                  <input
                    className={`${inputClass} text-end`}
                    dir="ltr"
                    value={fields.website}
                    onChange={(event) => update('website', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder={t('ob_website_ph')}
                  />
                </label>
              </>
            )}

            {step === 2 && (
              <>
                <div className="grid gap-5 sm:grid-cols-2">
                  <label className="block">
                    <span className="mb-2 block text-sm font-medium">{t('ob_city')}</span>
                    <input
                      className={inputClass}
                      autoFocus
                      value={fields.city}
                      onChange={(event) => update('city', event.target.value)}
                      onKeyDown={onKeyDown}
                      placeholder={t('ob_city_ph')}
                    />
                  </label>
                  <label className="block">
                    <span className="mb-2 block text-sm font-medium">
                      {t('ob_state')} <span className="text-xs font-normal text-muted-foreground">({t('ob_optional')})</span>
                    </span>
                    <input
                      className={inputClass}
                      value={fields.state_province}
                      onChange={(event) => update('state_province', event.target.value)}
                      onKeyDown={onKeyDown}
                      placeholder={t('ob_state_ph')}
                    />
                  </label>
                </div>
                <label className="block">
                  <span className="mb-2 block text-sm font-medium">
                    {t('ob_address1')} <span className="text-xs font-normal text-muted-foreground">({t('ob_optional')})</span>
                  </span>
                  <input
                    className={inputClass}
                    value={fields.address_line1}
                    onChange={(event) => update('address_line1', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder={t('ob_address1_ph')}
                  />
                </label>
                <div className="grid gap-5 sm:grid-cols-2">
                  <label className="block">
                    <span className="mb-2 block text-sm font-medium">
                      {t('ob_address2')} <span className="text-xs font-normal text-muted-foreground">({t('ob_optional')})</span>
                    </span>
                    <input
                      className={inputClass}
                      value={fields.address_line2}
                      onChange={(event) => update('address_line2', event.target.value)}
                      onKeyDown={onKeyDown}
                      placeholder={t('ob_address2_ph')}
                    />
                  </label>
                  <label className="block">
                    <span className="mb-2 block text-sm font-medium">
                      {t('ob_postal')} <span className="text-xs font-normal text-muted-foreground">({t('ob_optional')})</span>
                    </span>
                    <input
                      className={`${inputClass} text-end`}
                      dir="ltr"
                      value={fields.postal_code}
                      onChange={(event) => update('postal_code', event.target.value)}
                      onKeyDown={onKeyDown}
                      placeholder={t('ob_postal_ph')}
                    />
                  </label>
                </div>
              </>
            )}

            {step === 3 && (
              <div className="overflow-hidden rounded-2xl border border-border">
                {reviewRows.map((row, index) => (
                  <div
                    key={row.label}
                    className={`flex items-center gap-3 px-4 py-3 text-sm ${index > 0 ? 'border-t border-border' : ''} ${index % 2 === 1 ? 'bg-muted/40' : ''}`}
                  >
                    <span className="w-28 shrink-0 text-muted-foreground sm:w-36">{row.label}</span>
                    <span className="min-w-0 flex-1 truncate font-medium" title={row.value}>
                      {row.value.trim() ? row.value : '—'}
                    </span>
                    <button
                      className="shrink-0 rounded-lg px-2 py-1 text-xs font-semibold text-primary transition hover:bg-primary/10"
                      type="button"
                      onClick={() => setStep(row.target)}
                    >
                      {t('ob_edit')}
                    </button>
                  </div>
                ))}
              </div>
            )}

            <div className="mt-2 flex items-center gap-3">
              {step > 0 && (
                <button
                  className="h-13 rounded-2xl border border-border px-6 text-sm font-semibold transition hover:bg-muted"
                  type="button"
                  onClick={back}
                >
                  {t('ob_back')}
                </button>
              )}
              {step < 3 ? (
                <button
                  className="h-13 flex-1 rounded-2xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90"
                  type="button"
                  onClick={advance}
                >
                  {t('ob_continue')}
                </button>
              ) : (
                <button
                  className="h-13 flex-1 rounded-2xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60"
                  type="button"
                  onClick={finish}
                  disabled={saving}
                >
                  {saving ? t('ob_saving') : t('ob_finish')}
                </button>
              )}
            </div>

            {(step === 1 || step === 2) && (
              <button
                className="mx-auto text-sm font-medium text-muted-foreground transition hover:text-foreground"
                type="button"
                onClick={skip}
              >
                {t('ob_skip')}
              </button>
            )}
          </div>
        </div>
      </main>
    </div>
  )
}
