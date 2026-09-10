'use client'

import { useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import Header from '@/components/layout/header'
import Sidebar from '@/components/layout/sidebar'
import BrandSplash from '@/components/brand-splash'
import { useAuth } from '@/hooks/useAuth'
import { PermissionsProvider } from '@/hooks/usePermissions'
import { usePathname, useRouter } from 'next/navigation'

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
    <div className="flex min-h-screen overflow-hidden bg-background print:block print:overflow-visible" dir="rtl">
      <Sidebar mobileOpen={sidebarOpen} onMobileClose={() => setSidebarOpen(false)} />
      <div className="flex min-h-screen min-w-0 flex-1 flex-col print:block">
        <Header onMenuClick={() => setSidebarOpen(true)} />
        <main className="flex-1 overflow-y-auto p-4 lg:p-7 print:overflow-visible print:p-0">{children}</main>
      </div>
    </div>
    </PermissionsProvider>
      )}
    </>
  )
}
