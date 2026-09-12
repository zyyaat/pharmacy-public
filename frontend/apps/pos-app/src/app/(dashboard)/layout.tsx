'use client'

import { useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import Header from '@/components/layout/header'
import Sidebar from '@/components/layout/sidebar'
import BrandSplash from '@/components/brand-splash'
import { useAuth } from '@/hooks/useAuth'
import { PermissionsProvider } from '@/hooks/usePermissions'
import { SubscriptionProvider, useSubscription } from '@/hooks/useSubscription'
import { useT } from '@/i18n/provider'
import { usePathname, useRouter } from 'next/navigation'

// Task 90 — لافتة حالة الاشتراك (نفس سياسة pharmacy-app: الخادم يحجب،
// اللافتة توجيه UX فقط)
function SubscriptionBanner() {
  const { ready, status, daysLeft } = useSubscription()
  const t = useT('subscription')
  if (!ready || !status) return null
  if (status === 'expired') {
    return <div className="rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-2.5 text-sm text-destructive">{t('blocked_banner')}</div>
  }
  if (status === 'suspended') {
    return <div className="rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-2.5 text-sm text-destructive">{t('suspended_banner')}</div>
  }
  if (status === 'trial' && daysLeft !== null && daysLeft <= 3) {
    return <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-4 py-2.5 text-sm text-amber-700 dark:text-amber-400">{daysLeft <= 0 ? t('trial_banner_last') : t('trial_banner', { days: daysLeft })}</div>
  }
  return null
}

export default function DashboardLayout({ children }: { children: ReactNode }) {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const { user, loading } = useAuth()
  const router = useRouter()
  const pathname = usePathname()

  useEffect(() => {
    if (!loading && !user) {
      router.replace(`/login?next=${encodeURIComponent(pathname)}`)
    }
  }, [loading, user, router, pathname])

  return (
    <>
      {/* شاشة الافتتاحية أثناء التحقق من الجلسة — بتختفي بنعومة فوق الواجهة */}
      <BrandSplash show={loading || !user} />
      {user && (
    <PermissionsProvider>
    <SubscriptionProvider>
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
    </SubscriptionProvider>
    </PermissionsProvider>
      )}
    </>
  )
}
