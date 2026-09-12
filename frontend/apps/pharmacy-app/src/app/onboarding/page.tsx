'use client'

// Task 57 — معالج إعداد الصيدلية بأسلوب Upwork: يُفتح تلقائيًا بعد التحقق
// من البريد (الجلسة تُفتح هناك فورًا)، سؤال واحد في كل شاشة، شريط تقدم،
// تخطي للخطوات الاختيارية، مراجعة أخيرة ثم احتفال بالدخول إلى اللوحة.
// البيانات تُحفظ مرة واحدة في النهاية عبر PUT /pharmacy/onboarding.
//
// Task 80 — درس شكوى «بيانات المعالج ليست الكاملة اللي في صفحة تعديل الفرع»:
// المعالج كان يجمع حقول الصيدلية الثمانية فقط ولا يلمس الفرع الرئيسي، فيفتح
// المالك صفحة تعديل الفرع بعده ويجد اسم الفرع وكوده فارغين. صار الخطوة الأولى
// تجمع اسم الفرع الرئيسي (إجباري) وكود الفرع (اختياري)، وخطوة التواصل تضيف
// بريد الصيدلية — مطابقة لحقول صفحة تعديل الفرع من أول مرة. كل حقل يُظهر
// حالته: نجمة حمراء للإجباري وكلمة «اختياري» لغيره، مع مفتاح تفسيري تحت
// رأس الخطوة ورأس مُعاد تنظيمه بسطر تصنيف بلون الهوية وخط فاصل — نفس لغة
// إصلاح تطبيق الجوال المرافق (mobile onboarding_screen.dart).

import { useEffect, useState, type KeyboardEvent } from 'react'
import { useRouter } from 'next/navigation'
import { ClipboardList, MapPin, Phone, Store } from 'lucide-react'
import BrandSplash from '@/components/brand-splash'
import { useAuth } from '@/hooks/useAuth'
import { ApiError, onboardingApi } from '@/lib/api'
import { useT } from '@/i18n/provider'

type Fields = {
  name: string
  branch_name: string
  branch_code: string
  phone: string
  email: string
  website: string
  address_line1: string
  address_line2: string
  city: string
  state_province: string
  postal_code: string
}

const emptyFields: Fields = {
  name: '',
  branch_name: '',
  branch_code: '',
  phone: '',
  email: '',
  website: '',
  address_line1: '',
  address_line2: '',
  city: '',
  state_province: '',
  postal_code: '',
}

// Task 80 — عنوان الحقل بحالته الصريحة: نجمة حمراء للإجباري وكلمة
// «اختياري» لغيره — كي لا يخمّن المستخدم أبدًا ما هو مطلوب منه.
function FieldLabel({ text, required, optionalLabel }: { text: string; required?: boolean; optionalLabel?: string }) {
  return (
    <span className="mb-2 block text-sm font-medium">
      {text}
      {required && <span className="text-destructive" aria-hidden="true"> *</span>}
      {optionalLabel && <span className="text-xs font-normal text-muted-foreground"> ({optionalLabel})</span>}
    </span>
  )
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

  // التعبئة المسبقة من ملف الصيدلية الحالي + الفرع الرئيسي (Task 80)
  // — نفس مصادر صفحة تعديل الفرع. branch محصّن ضد خوادم قديمة لا تُعيده.
  useEffect(() => {
    if (authLoading || !user) return
    let cancelled = false
    onboardingApi.get()
      .then((response) => {
        if (cancelled) return
        const pharmacy = response.data.pharmacy
        const branch = response.data.branch ?? { name: '', code: '', email: '' }
        setFields({
          name: pharmacy.name ?? '',
          branch_name: branch.name ?? '',
          branch_code: branch.code ?? '',
          phone: pharmacy.phone ?? '',
          email: branch.email || pharmacy.email || '',
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

  // Task 80 — تحقق الخطوة الأولى: اسم الصيدلية واسم الفرع الرئيسي كلاهما
  // إجباري (مطابق لنموذج تعديل الفرع: name + pharmacy_name مطلوبان).
  function validateStep(target: number): string {
    if (target === 0) {
      if (fields.name.trim().length < 2) return t('ob_name_required')
      if (!fields.branch_name.trim()) return t('ob_branch_required')
    }
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
      await onboardingApi.update({
        name: fields.name,
        branch_name: fields.branch_name,
        branch_code: fields.branch_code,
        phone: fields.phone,
        email: fields.email,
        website: fields.website,
        address_line1: fields.address_line1,
        address_line2: fields.address_line2,
        city: fields.city,
        state_province: fields.state_province,
        postal_code: fields.postal_code,
        complete: true,
      })
      setStep(4)
    } catch (cause) {
      // تعارض كود الفرع له رسالته الخاصة — رسالة عامة لغيره
      setError(
        cause instanceof ApiError && cause.code === 'branch_code_conflict'
          ? t('ob_code_conflict')
          : t('ob_err_save'),
      )
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
  // Task 80 — سطر التصنيف العلوي لكل خطوة: يضبط سياق العنوان قبل قراءته
  const stepCats = [t('ob_s1_cat'), t('ob_s2_cat'), t('ob_s3_cat'), t('ob_s4_cat')]

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
    { label: t('ob_branch_name_short'), value: fields.branch_name, target: 0 },
    { label: t('ob_branch_code'), value: fields.branch_code, target: 0 },
    { label: t('ob_phone'), value: fields.phone, target: 1 },
    { label: t('ob_email'), value: fields.email, target: 1 },
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
          {/* رأس الخطوة — Task 80: سطر تصنيف بلون الهوية (التعريف/التواصل/الموقع/
          المراجعة) فوق العنوان، ثم خط فاصل يفصل الرأس عن الحقول — هيكل واضح */}
          <div className="flex items-center gap-4">
            <div className="flex h-13 w-13 shrink-0 items-center justify-center rounded-2xl bg-primary/10 text-primary">
              {stepIcons[step]}
            </div>
            <div className="min-w-0">
              <p className="text-[11px] font-extrabold text-primary">{stepCats[step]}</p>
              <h1 className="mt-0.5 text-xl font-extrabold leading-snug sm:text-2xl">{stepTitles[step]}</h1>
              <p className="mt-1 text-sm leading-6 text-muted-foreground">{stepSubs[step]}</p>
            </div>
          </div>

          <div className="mt-6 border-t border-border" aria-hidden="true" />

          {/* المفتاح التفسيري: الحقول المعلّمة بـ * إجبارية — مرجع سريع قبل الحقول */}
          <p className="mt-4 flex items-start gap-1.5 text-xs leading-5 text-muted-foreground">
            <span className="text-sm font-extrabold leading-5 text-destructive" aria-hidden="true">*</span>
            {t('ob_required_legend')}
          </p>

          <div className="mt-5 grid gap-5">
            {error && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive" role="alert">{error}</p>}

            {step === 0 && (
              <>
                <label className="block">
                  <FieldLabel text={`${t('ob_welcome')} ${firstName}، ${t('ob_app_label')}`} required />
                  <input
                    className={inputClass}
                    autoFocus
                    value={fields.name}
                    onChange={(event) => update('name', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder={t('pharmacy_name_ph')}
                  />
                </label>
                {/* Task 80 — الفرع الرئيسي من أول مرة: الاسم إجباري والكود اختياري
                — نفس حقول صفحة تعديل الفرع حتى لا تتفاجأ صفحة الفرع لاحقًا */}
                <label className="block">
                  <FieldLabel text={t('ob_branch_name')} required />
                  <input
                    className={inputClass}
                    value={fields.branch_name}
                    onChange={(event) => update('branch_name', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder={t('ob_branch_name_ph')}
                  />
                </label>
                <label className="block">
                  <FieldLabel text={t('ob_branch_code')} optionalLabel={t('ob_optional')} />
                  <input
                    className={`${inputClass} text-end`}
                    dir="ltr"
                    value={fields.branch_code}
                    onChange={(event) => update('branch_code', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder={t('ob_branch_code_ph')}
                  />
                </label>
              </>
            )}

            {step === 1 && (
              <>
                <label className="block">
                  <FieldLabel text={t('ob_phone')} optionalLabel={t('ob_optional')} />
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
                  <FieldLabel text={t('ob_email')} optionalLabel={t('ob_optional')} />
                  <input
                    className={`${inputClass} text-end`}
                    dir="ltr"
                    type="email"
                    value={fields.email}
                    onChange={(event) => update('email', event.target.value)}
                    onKeyDown={onKeyDown}
                    placeholder={t('ob_email_ph')}
                  />
                </label>
                <label className="block">
                  <FieldLabel text={t('ob_website')} optionalLabel={t('ob_optional')} />
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
                    <FieldLabel text={t('ob_city')} optionalLabel={t('ob_optional')} />
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
                    <FieldLabel text={t('ob_state')} optionalLabel={t('ob_optional')} />
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
                  <FieldLabel text={t('ob_address1')} optionalLabel={t('ob_optional')} />
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
                    <FieldLabel text={t('ob_address2')} optionalLabel={t('ob_optional')} />
                    <input
                      className={inputClass}
                      value={fields.address_line2}
                      onChange={(event) => update('address_line2', event.target.value)}
                      onKeyDown={onKeyDown}
                      placeholder={t('ob_address2_ph')}
                    />
                  </label>
                  <label className="block">
                    <FieldLabel text={t('ob_postal')} optionalLabel={t('ob_optional')} />
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
                    <span className="w-32 shrink-0 text-muted-foreground sm:w-40">{row.label}</span>
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
