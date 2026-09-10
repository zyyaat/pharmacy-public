"use client"

// بوصلة النشر العامة (Task 55) — ردًا على «الخطأ لسا موجود»: اكتشف الفحص
// العميق أن الفرونت المنشور كان عاجزًا عن الوصول للباكند نهائيًا
// (DNS_HOSTNAME_RESOLVED_PRIVATE من كل مسارات /api/v1) بلا أي أداة يرى بها
// المستخدم السبب. هذه الصفحة تشخّص الاتصال من داخل المتصفح وتعطي الخطوات
// التصحيحية مباشرة.
//
// ملاحظة i18n: هذه صفحة أداة تشخيصية عامة بنصوص ثنائية اللغة (العربية
// أساسًا) — سبق ذلك في المستودع برسائل api.ts الثابتة، ولا تخضع لشجرة
// الترجمات لتفادي تضخيم 8 لغات برسائل تشخيص تقنية.

import { FormEvent, useState } from 'react'

const API_BASE = (process.env.NEXT_PUBLIC_API_URL || '/api/v1').replace(/\/+$/, '')
// يُحدَّث يدويًا مع كل bump لـ APILevel في backend/internal/handlers/handler.go
const EXPECTED_API_LEVEL = 55

type AppProbe = {
  kind: 'idle' | 'loading' | 'ok' | 'stale' | 'fail'
  status?: number
  apiLevel?: number
  detail?: string
  dnsPrivate?: boolean
}

type DirectProbe = {
  kind: 'idle' | 'loading' | 'readable' | 'opaque' | 'unreachable' | 'bad-url'
  status?: number
  apiLevel?: number
  detail?: string
}

export default function DiagPage() {
  const [app, setApp] = useState<AppProbe>({ kind: 'idle' })
  const [backendUrl, setBackendUrl] = useState('')
  const [direct, setDirect] = useState<DirectProbe>({ kind: 'idle' })

  async function probeAppPath() {
    setApp({ kind: 'loading' })
    try {
      const response = await fetch(`${API_BASE}/health`, { credentials: 'include', cache: 'no-store' })
      const text = await response.text()
      let body: { status?: string; api_level?: number } | null = null
      try {
        body = JSON.parse(text)
      } catch {
        body = null
      }
      if (response.ok && body?.status === 'healthy' && typeof body.api_level === 'number') {
        setApp({
          kind: body.api_level >= EXPECTED_API_LEVEL ? 'ok' : 'stale',
          status: response.status,
          apiLevel: body.api_level,
        })
      } else if (text.includes('DNS_HOSTNAME_RESOLVED_PRIVATE')) {
        setApp({ kind: 'fail', status: response.status, dnsPrivate: true, detail: text.slice(0, 200) })
      } else {
        setApp({ kind: 'fail', status: response.status, detail: text.slice(0, 200) })
      }
    } catch (error) {
      setApp({ kind: 'fail', detail: error instanceof Error ? error.message : String(error) })
    }
  }

  async function probeDirect(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const clean = backendUrl.trim().replace(/\/+$/, '')
    if (!/^https:\/\/.+/.test(clean)) {
      setDirect({ kind: 'bad-url' })
      return
    }
    setDirect({ kind: 'loading' })
    // المحاولة الأولى: قراءة كاملة (تتطلب CORS يسمح بدومين الفرونت)
    try {
      const response = await fetch(`${clean}/api/v1/health`, { credentials: 'omit', cache: 'no-store' })
      const body = await response.json().catch(() => null)
      setDirect({
        kind: 'readable',
        status: response.status,
        apiLevel: typeof body?.api_level === 'number' ? body.api_level : undefined,
      })
      return
    } catch {
      // المحاولة الثانية: فحص وصول معتم (no-cors) — يثبت DNS وTLS والخادم بلا قراءة
      try {
        await fetch(`${clean}/api/v1/health`, { mode: 'no-cors', credentials: 'omit', cache: 'no-store' })
        setDirect({ kind: 'opaque' })
      } catch (error) {
        setDirect({ kind: 'unreachable', detail: error instanceof Error ? error.message : String(error) })
      }
    }
  }

  const card = 'rounded-2xl border border-border bg-card p-5 shadow-sm'
  const code = 'rounded-lg bg-muted px-2 py-0.5 font-mono text-[0.85em]'

  return (
    <div className="mx-auto flex min-h-screen w-full max-w-3xl flex-col gap-6 px-4 py-10">
      <header>
        <h1 className="text-2xl font-bold">بوصلة النشر — تشخيص اتصال الباكند</h1>
        <p className="mt-2 text-sm leading-7 text-muted-foreground">
          صفحة عامة للتحقق من وصول هذا التطبيق المنشور إلى خادم الـ API، وما هو مستوى كوده
          (<span className={code}>api_level</span>). لا تعرض أي بيانات دخول ولا تحتاج حسابًا.
        </p>
        <p className="mt-1 text-xs text-muted-foreground">
          مسار الـ API في هذا البناء: <span className={code}>{API_BASE}</span> — هدف البروكسي على الخادم
          يأتي من متغير <span className={code}>BACKEND_INTERNAL_URL</span> في Vercel.
        </p>
      </header>

      <section className={card}>
        <div className="flex items-center justify-between gap-4">
          <h2 className="font-semibold">1) فحص مسار التطبيق (نفس ما يستخدمه المتصفح فعليًا)</h2>
          <button
            type="button"
            onClick={probeAppPath}
            disabled={app.kind === 'loading'}
            className="h-10 shrink-0 rounded-xl bg-primary px-4 text-sm font-medium text-primary-foreground disabled:opacity-60"
          >
            {app.kind === 'loading' ? '…جارٍ الفحص' : 'افحص الآن'}
          </button>
        </div>

        {app.kind === 'ok' && (
          <p className="mt-3 rounded-xl bg-emerald-500/10 p-3 text-sm text-emerald-700">
            الاتصال سليم، والباكند حديث (<span className={code}>api_level: {app.apiLevel}</span>).
            إن كانت البيانات ناقصة في الصفحات فهي ليست مشكلة اتصال — راجع بيانات قاعدة البيانات نفسها.
          </p>
        )}
        {app.kind === 'stale' && (
          <p className="mt-3 rounded-xl bg-amber-500/10 p-3 text-sm text-amber-700">
            الاتصال سليم لكن الباكند قديم (<span className={code}>api_level: {app.apiLevel}</span> والمتوقع
            ≥ {EXPECTED_API_LEVEL}). أعد نشر خدمة الباكند على DockHosting (Rebuild من المستودع)، ثم أعد الفحص.
          </p>
        )}
        {app.kind === 'fail' && (
          <div className="mt-3 rounded-xl bg-destructive/10 p-3 text-sm leading-7 text-destructive">
            <p className="font-semibold">مسار الـ API لا يستجيب من هذا النشر{app.status ? ` (HTTP ${app.status})` : ''}.</p>
            {app.dnsPrivate ? (
              <p>
                السبب المكتشف: <span className={code}>DNS_HOSTNAME_RESOLVED_PRIVATE</span> — أي أن
                {' '}<span className={code}>BACKEND_INTERNAL_URL</span> في Vercel غير مضبوط أو يشير إلى عنوان
                داخلي/محلي. الحل: ضع في Vercel الرابط <strong>العام</strong> للباكند على DockHosting
                (يبدأ بـ <span className={code}>https://</span> وبلا لاحقة <span className={code}>/api/v1</span>)
                ثم <strong>أعد نشر الفرونت</strong> — تغيير المتغيرات لا يسري إلا بنشر جديد.
              </p>
            ) : (
              <p>
                جرّب الفحص المباشر أدناه برابط الباكند للتأكد من الخادم نفسه أولًا، ثم راجع
                {' '}<span className={code}>BACKEND_INTERNAL_URL</span> في Vercel (رابط عام بلا لاحقة
                {' '}<span className={code}>/api/v1</span>) وأعد نشر الفرونت بعد أي تغيير.
              </p>
            )}
            {app.detail && <p className="mt-2 break-all font-mono text-xs opacity-70">{app.detail}</p>}
          </div>
        )}
      </section>

      <section className={card}>
        <h2 className="font-semibold">2) فحص مباشر لرابط الباكند (يتجاوز إعدادات Vercel)</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          ألصق الرابط العام للباكند على DockHosting — مثل <span className={code}>https://pharmacy-api.example.dockhosting.app</span>
        </p>
        <form className="mt-3 flex flex-wrap gap-3" onSubmit={probeDirect}>
          <input
            className="h-11 min-w-0 flex-1 rounded-xl border border-input bg-background px-4 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10"
            type="url"
            dir="ltr"
            required
            value={backendUrl}
            onChange={(event) => setBackendUrl(event.target.value)}
            placeholder="https://your-backend-host"
          />
          <button
            type="submit"
            disabled={direct.kind === 'loading'}
            className="h-11 shrink-0 rounded-xl border border-border bg-background px-4 text-sm font-medium disabled:opacity-60"
          >
            {direct.kind === 'loading' ? '…جارٍ الفحص' : 'افحص الرابط'}
          </button>
        </form>

        {direct.kind === 'bad-url' && (
          <p className="mt-3 rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
            أدخل رابطًا يبدأ بـ <span className={code}>https://</span> — المتصفح يحجب فحص http من صفحة https.
          </p>
        )}
        {direct.kind === 'readable' && (
          <p className="mt-3 rounded-xl bg-emerald-500/10 p-3 text-sm text-emerald-700">
            الخادم يستجيب ويُقرأ كاملًا (<span className={code}>api_level: {direct.apiLevel ?? '؟'}</span>).
            إن فشل «فحص مسار التطبيق» أعلاه مع نجاح هذا فالمشكلة حصريًا في إعدادات Vercel:
            {' '}<span className={code}>BACKEND_INTERNAL_URL</span> = هذا الرابط، ثم إعادة نشر الفرونت.
          </p>
        )}
        {direct.kind === 'opaque' && (
          <p className="mt-3 rounded-xl bg-amber-500/10 p-3 text-sm text-amber-700">
            الخادم يعمل ويستجيب، لكن CORS يمنع قراءة الرد من دومين الفرونت هذا. أضف دومين الفرونت
            إلى <span className={code}>CORS_ORIGINS</span> في الباكند (أصول كاملة بلا مسارات).
          </p>
        )}
        {direct.kind === 'unreachable' && (
          <p className="mt-3 rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
            الخادم غير متاح من متصفحك أصلًا. تأكد أن خدمة الباكند تعمل على DockHosting وأن الرابط
            هو العام الصحيح{direct.detail ? ` — ${direct.detail}` : ''}.
          </p>
        )}
      </section>

      <section className={card}>
        <h2 className="font-semibold">3) خطوات الإصلاح القياسية (بالترتيب)</h2>
        <ol className="mt-2 list-decimal space-y-2 ps-6 text-sm leading-7">
          <li>
            افتح <span className={code}>https://&lt;رابط-الباكند&gt;/api/v1/health</span> في المتصفح —
            يجب أن ترى <span className={code}>api_level</span>. إن لم تفتح أصلًا فالمشكلة في الباكند على
            DockHosting (أعد بناءه من المستودع).
          </li>
          <li>
            في Vercel: <span className={code}>BACKEND_INTERNAL_URL</span> = الرابط العام للباكند
            (https وبلا <span className={code}>/api/v1</span> بالنهاية) في بيئة Production.
          </li>
          <li>أعد نشر تطبيقات الفرونت الثلاثة على Vercel بعد أي تغيير متغيرات.</li>
          <li>
            في الباكند: <span className={code}>CORS_ORIGINS</span> يتضمن كل دومينات Vercel كاملة،
            و<span className={code}>AUTH_COOKIE_SECURE=true</span>.
          </li>
          <li>أعد الفحص الأول أعلاه — يجب أن يصبح أخضر بـ <span className={code}>api_level ≥ {EXPECTED_API_LEVEL}</span>.</li>
        </ol>
      </section>
    </div>
  )
}
