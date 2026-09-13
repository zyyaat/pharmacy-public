'use client'

// عميل صفحة الدفع المستقلة: يقرأ ?plan= ويجلب بيانات الخطة العامة ثم
// يصيّر CheckoutView. نفس حارس صلاحية قسم الاشتراك (settings.billing) —
// وضمن قسم /settings/subscription فالقسم يرث الحماية من layout الإعدادات.
// رابط بلا خطة أو بخطة غير معروفة → رجوع لصفحة الاشتراك.

import { useEffect, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { CheckoutView } from '@/components/subscription/CheckoutView'
import { NoAccessCard, useAccess } from '@/components/permissions/gate'
import { subscriptionApi, type PublicPlan } from '@/lib/api'

export default function CheckoutClient() {
  const router = useRouter()
  const params = useSearchParams()
  const planId = params.get('plan') ?? ''
  const { ready: permsReady, allowedAny, fullAccess } = useAccess()
  const [plan, setPlan] = useState<PublicPlan | null>(null)
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    if (permsReady && !fullAccess && !allowedAny(['settings.billing'])) {
      router.replace('/')
    }
  }, [permsReady, fullAccess, allowedAny, router])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const res = await subscriptionApi.listPlans()
        if (cancelled) return
        const found = res.data.find((p) => p.id === planId) ?? null
        setPlan(found)
        setLoaded(true)
        if (!found) router.replace('/settings/subscription')
      } catch {
        if (!cancelled) {
          setLoaded(true)
          router.replace('/settings/subscription')
        }
      }
    })()
    return () => { cancelled = true }
  }, [planId, router])

  if (!permsReady || !loaded || !plan) return null
  if (!fullAccess && !allowedAny(['settings.billing'])) return <NoAccessCard />

  return (
    <CheckoutView
      plan={plan}
      onBack={() => router.replace('/settings/subscription')}
      // التفعيل الفعلي وصل من ويبهوك Paymob — صفحة الاشتراك تعيد الجلب
      // كاملًا عند العودة إليها، فلا داعي لعمل هنا.
      onActivated={() => {}}
    />
  )
}
