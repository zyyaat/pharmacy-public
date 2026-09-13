'use client'

import { useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import Header from '@/components/layout/header'
import Sidebar from '@/components/layout/sidebar'
import BrandSplash from '@/components/brand-splash'
import { useAuth } from '@/hooks/useAuth'
import { useT } from '@/i18n/provider'
import { fmtDate } from '@/i18n/format'
import { PermissionsProvider } from '@/hooks/usePermissions'
import { useSubscription } from '@/hooks/useSubscription'
import { usePathname, useRouter } from 'next/navigation'

// Task 90 — لافتة حالة الاشتراك: تظهر فوق المحتوى عند قرب انتهاء
// التجربة أو انتهائها/تعليقها. الخادم هو الحاجب الحقيقي؛ هذه مجرد توجيه UX.
function SubscriptionBanner() {
  const { ready, subscription } = useSubscription()
  const t = useT('subscription')
  if (!ready || !subscription) return null
  const status = subscription.subscription?.status
  const daysLeft = subscription.subscription?.days_left ?? null
  // فترة السماح: الخادم يسمح بالوصول بعد الانتهاء — تحذير عاجل بدل حجب كامل
  if (subscription.subscription?.in_grace) {
    const ends = subscription.subscription.grace_ends_at
    return (
      <div className="rounded-lg border border-amber-500/50 bg-amber-500/10 px-4 py-2.5 text-sm text-amber-700">
        {t('grace_notice', { date: ends ? fmtDate(ends, { dateStyle: 'long' }) : '' })}
      </div>
    )
  }
  if (status === 'expired') {
    return (
      <div className="rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-2.5 text-sm text-destructive">
        {t('blocked_banner')}
      </div>
    )
  }
  if (status === 'suspended') {
    return (
      <div className="rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-2.5 text-sm text-destructive">
        {t('suspended_banner')}
      </div>
    )
  }
  if (status === 'trial' && daysLeft !== null && daysLeft <= 3) {
    return (
      <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-4 py-2.5 text-sm text-amber-700 dark:text-amber-400">
        {daysLeft <= 0 ? t('trial_banner_last') : t('trial_banner', { days: daysLeft })}
      </div>
    )
  }
  return null
}

export default function DashboardLayout({ children }: { children: ReactNode }) {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const { user, loading } = useAuth()
  const router = useRouter()
  const pathname = usePathname()

  useEffect(() => {
    if (loading) return
    if (!user) {
      router.replace(`/login?next=${encodeURIComponent(pathname)}`)
      return
    }
    // Task 57 — حساب جديد لم يُكمل إعداد صيدليته؟ المعالج أولًا مهما كان المسار.
    if (user.onboarding_required === true && pathname !== '/onboarding') {
      router.replace('/onboarding')
    }
  }, [loading, user, router, pathname])

  return (
    <>
      {/* شاشة الافتتاحية أثناء التحقق من الجلسة — بتختفي بنعومة فوق الواجهة */}
      <BrandSplash show={loading || !user} />
      {user && (
    <PermissionsProvider>
    <div className="flex min-h-screen overflow-hidden bg-background print:block print:overflow-visible" dir="rtl">
      <Sidebar mobileOpen={sidebarOpen} onMobileClose={() => setSidebarOpen(false)} />
      <div className="flex min-h-screen min-w-0 flex-1 flex-col print:block">
        <Header onMenuClick={() => setSidebarOpen(true)} />
        <main className="flex-1 overflow-y-auto p-4 lg:p-7 print:overflow-visible print:p-0">
          {pathname !== '/pos' && <div className="mb-4"><SubscriptionBanner /></div>}
          {children}
        </main>
      </div>
    </div>
    </PermissionsProvider>
      )}
    </>
  )
}
