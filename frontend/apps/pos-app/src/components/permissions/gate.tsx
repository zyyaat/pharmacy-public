'use client'

// بوابة الصلاحيات للواجهة (Task 43) — الإخفاء الكامل بدل «يضغط فيتفاجئ أنه ممنوع».
//
// أفضل الممارسات المتبعة هنا:
// 1) الإخفاء لا التعطيل: الصلاحية الدائمة الممنوعة يعني العنصر يختفي تمامًا
//    (زر/قسم/صفحة) — لا زر رمادي يربك المستخدم (أنظمة التصميم: Helios وNN/g).
// 2) لا وميض للممنوع: أثناء جلب الصلاحيات الأولى لا يُرسم شيء بدل رسم كل شيء
//    ثم إخفاؤه أمام المستخدم (flash of unauthorized content).
// 3) حماية المسارات: إخفاء القائمة لا يكفي — الدخول المباشر بالرابط يعرض
//    بطاقة «غير متاحة» بدل الصفحة الممنوعة.
// 4) الدفاع في العمق: كل ما هنا تجميلي — الفرض الحقيقي في الباكند على كل مسار
//    (requirePharmacyPermission). عند فشل جلب الصلاحيات نفتح الواجهة
//    (fail-open) كي لا يُقفل المالك خارجها لعطل شبكة عابر.

import { useRouter } from 'next/navigation'
import type { ReactNode } from 'react'
import { ShieldOff } from 'lucide-react'
import { Button, LoadingSpinner } from '@/components/ui'
import { usePermissions } from '@/hooks/usePermissions'

export function useAccess() {
  const { data, loading, can, canAny } = usePermissions()
  const ready = !loading
  // فشل الجلب (data=null بعد انتهاء التحميل) → نسمح بالعرض كالوضع القديم،
  // والباكند يرفض فعليًا أي طلب غير مصرح به.
  const allowed = (key: string) => (ready && !data) || can(key)
  const allowedAny = (keys: string[]) => (ready && !data) || canAny(keys)
  return { ready, allowed, allowedAny, fullAccess: data?.full_access ?? false }
}

/** يخفي المحتوى كليًا ما لم يملك المستخدم الصلاحية المطلوبة */
export function Can({
  perm,
  anyOf,
  children,
  fallback = null,
}: {
  perm?: string
  anyOf?: string[]
  children: ReactNode
  fallback?: ReactNode
}) {
  const { ready, allowed, allowedAny } = useAccess()
  if (!ready) return null
  const ok = perm ? allowed(perm) : allowedAny(anyOf ?? [])
  return <>{ok ? children : fallback}</>
}

/** بطاقة «الصفحة غير متاحة» — تُعرض عند الدخول المباشر لرابط ممنوع */
export function NoAccessCard({ title }: { title?: string }) {
  const router = useRouter()
  return (
    <div className="flex min-h-[50vh] items-center justify-center py-16">
      <div className="mx-auto max-w-md space-y-4 rounded-2xl border border-border bg-card p-8 text-center shadow-sm">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-muted">
          <ShieldOff className="h-7 w-7 text-muted-foreground" />
        </div>
        <h1 className="text-xl font-bold">{title || 'هذه الصفحة غير متاحة لحسابك'}</h1>
        <p className="text-sm leading-relaxed text-muted-foreground">
          لم يمنحك مالك الصيدلية صلاحية الوصول لهذا القسم.
          إذا كنت تحتاجه في عملك فتواصل معه ليمنحك الصلاحية المناسبة.
        </p>
        <Button variant="outline" onClick={() => router.push('/')}>العودة للرئيسية</Button>
      </div>
    </div>
  )
}

function GuardLoading() {
  return (
    <div className="flex items-center justify-center py-24">
      <LoadingSpinner />
    </div>
  )
}

/** حارس المسارات: لا شيء يُرسم من الصفحة الممنوعة — لا حتى هوكل البيانات */
export function RequirePermission({
  anyOf,
  children,
  redirectTo,
}: {
  anyOf: string[]
  children: ReactNode
  /** اختياري: تحويل صامت لأول صفحة مسموحة بدل بطاقة الرفض (مفيد للرئيسية) */
  redirectTo?: string | null
}) {
  const router = useRouter()
  const { ready, allowedAny } = useAccess()

  if (!ready) return <GuardLoading />

  if (!allowedAny(anyOf)) {
    if (redirectTo) {
      router.replace(redirectTo)
      return <GuardLoading />
    }
    return <NoAccessCard />
  }

  return <>{children}</>
}
