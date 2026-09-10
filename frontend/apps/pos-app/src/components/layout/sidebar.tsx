'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { useState } from 'react'
import { ChevronLeft, ChevronRight, History, LogOut, ReceiptText, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui'
import { useAuth } from '@/hooks/useAuth'
import { usePharmacyContext } from '@/hooks/usePharmacyContext'
import { useAccess } from '@/components/permissions/gate'
import { SIDEBAR_PERMISSION_ROUTES } from '@/lib/permissions'

/**
 * قائمة تطبيق نقطة البيع — نفس نمط وقواعد التطبيق الرئيسي:
 * كل عنصر يخضع لنفس مفاتيح الصلاحيات (pos.access / sales.view)،
 * وهيكل عظمي حتى تحميل الصلاحيات كي لا يلمس الموظف المقيّد الممنوع.
 */
const items = [
  { title: 'نقطة البيع', href: '/pos', icon: ReceiptText },
  { title: 'سجل البيع', href: '/sales', icon: History },
]

/** الصلاحية المطلوبة لظهور كل عنصر في القائمة (مرتبة من الأكثر تحديدًا). */
function requiredPermissions(href: string): string[] | null {
  const match = SIDEBAR_PERMISSION_ROUTES.find((route) => href === route.href)
  return match ? match.anyOf : null
}

export default function Sidebar({ mobileOpen, onMobileClose }: { mobileOpen: boolean; onMobileClose: () => void }) {
  const pathname = usePathname()
  const router = useRouter()
  const { logout } = useAuth()
  const { context } = usePharmacyContext()
  // لا وميض للممنوع — حتى تحميل الصلاحيات نعرض هيكلًا عظميًا،
  // فالموظف المقيّد لا يرى الأقسام الممنوعة ولو لجزء من الثانية.
  const { ready, allowedAny } = useAccess()
  const [collapsed, setCollapsed] = useState(false)
  const [loggingOut, setLoggingOut] = useState(false)

  const visibleItems = items.filter((item) => {
    const required = requiredPermissions(item.href)
    if (!required) return true
    if (!ready) return false
    return allowedAny(required)
  })

  async function handleLogout() {
    if (loggingOut) return
    setLoggingOut(true)
    try {
      await logout()
    } finally {
      router.replace('/login')
    }
  }

  const content = (
    <div className={cn('flex h-full flex-col border-l border-border bg-card transition-all duration-300', collapsed ? 'w-[70px]' : 'w-[260px]')}>
      <div className="flex h-16 items-center justify-between border-b border-border px-4">
        {!collapsed && (
          <Link href="/pos" className="flex items-center gap-2">
            <img
              src="/brand/pharmacy-os-logo-light.svg"
              alt="Pharmacy POS"
              className="h-9 w-auto max-w-[170px] dark:hidden"
              width="260"
              height="64"
            />
            <img
              src="/brand/pharmacy-os-logo-dark.svg"
              alt="Pharmacy POS"
              className="hidden h-9 w-auto max-w-[170px] dark:block"
              width="260"
              height="64"
            />
          </Link>
        )}
        {collapsed && (
          <img
            src="/brand/pharmacy-os-icon.svg"
            alt="Pharmacy POS"
            className="mx-auto h-9 w-9"
            width="36"
            height="36"
          />
        )}
        <button className="rounded-lg p-1.5 hover:bg-accent lg:hidden" onClick={onMobileClose} aria-label="إغلاق القائمة">
          <X className="h-5 w-5" />
        </button>
        <button className="hidden rounded-lg p-1.5 hover:bg-accent lg:flex" onClick={() => setCollapsed(!collapsed)} aria-label="طي القائمة">
          {collapsed ? <ChevronLeft className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
        </button>
      </div>

      {!collapsed && (
        <div className="border-b border-border p-3">
          <div className="rounded-lg bg-primary/10 p-3">
            <p className="text-xs text-muted-foreground">الصيدلية الحالية</p>
            <p className="mt-1 truncate text-sm font-semibold">{context?.pharmacy.name || 'جاري تحميل الصيدلية...'}</p>
            <p className="mt-1 truncate text-xs text-muted-foreground">
              {context?.branch
                ? `${context.branch.name}${context.branch.city ? ` · ${context.branch.city}` : ''}`
                : context?.pharmacy.city || 'لا يوجد فرع محدد'}
            </p>
          </div>
        </div>
      )}

      <nav className="flex-1 space-y-1 overflow-y-auto p-3">
        <p className={cn('mb-2 text-xs font-medium text-muted-foreground', collapsed ? 'text-center' : 'px-3')}>{collapsed ? '•••' : 'نقطة البيع'}</p>
        {!ready && (
          <div className="space-y-2" aria-hidden="true">
            {Array.from({ length: 2 }, (_, i) => (
              <div key={i} className="h-11 animate-pulse rounded-lg bg-muted/60" />
            ))}
          </div>
        )}
        {ready && visibleItems.map((item) => {
          const active = pathname === item.href || pathname.startsWith(item.href + '/')
          const ItemIcon = item.icon
          return (
            <Link
              key={item.href}
              href={item.href}
              onClick={onMobileClose}
              className={cn('group relative flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-all duration-200', active ? 'bg-primary/10 text-primary' : 'text-muted-foreground hover:bg-accent hover:text-foreground')}
            >
              {active && <div className="absolute right-0 top-1/2 h-8 w-1 -translate-y-1/2 rounded-l-full bg-primary" />}
              <ItemIcon className={cn('h-5 w-5 shrink-0', active && 'text-primary')} />
              {!collapsed && <span className="flex-1">{item.title}</span>}
              {collapsed && <div className="absolute right-full z-50 mr-2 hidden whitespace-nowrap rounded-lg border border-border bg-popover px-3 py-2 text-sm shadow-lg group-hover:block">{item.title}</div>}
            </Link>
          )
        })}
      </nav>

      <div className="border-t border-border p-4">
        <div className={cn('flex items-center gap-3', collapsed && 'justify-center')}>
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-sm font-medium text-primary">م</div>
          {!collapsed && (
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">
                {context?.user.display_name || `${context?.user.first_name || ''} ${context?.user.last_name || ''}`.trim() || 'المستخدم'}
              </p>
              <p className="truncate text-xs text-muted-foreground">{context?.user.role || 'حساب الصيدلية'}</p>
            </div>
          )}
          <Button
            variant="ghost"
            size="icon"
            className="shrink-0 text-muted-foreground hover:text-destructive"
            onClick={handleLogout}
            disabled={loggingOut}
            aria-label="تسجيل الخروج"
            title="تسجيل الخروج"
          >
            <LogOut className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </div>
  )

  return (
    <>
      {mobileOpen && <div className="print-hidden fixed inset-0 z-40 bg-black/50 lg:hidden" onClick={onMobileClose} />}
      <aside className={cn('print-hidden fixed bottom-0 right-0 top-0 z-50 transition-transform duration-300 lg:sticky lg:block lg:h-screen', mobileOpen ? 'translate-x-0' : 'translate-x-full lg:translate-x-0')}>{content}</aside>
    </>
  )
}
