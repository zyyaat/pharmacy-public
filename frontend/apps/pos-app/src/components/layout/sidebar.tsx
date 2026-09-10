'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { useState } from 'react'
import { ArrowLeftRight, ChevronLeft, ChevronRight, History, LogOut, Package, ReceiptText, Settings, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui'
import { useAuth } from '@/hooks/useAuth'
import { usePharmacyContext } from '@/hooks/usePharmacyContext'
import { useAccess } from '@/components/permissions/gate'
import { SIDEBAR_PERMISSION_ROUTES } from '@/lib/permissions'
import { useT } from '@/i18n/provider'

/**
 * قائمة تطبيق نقطة البيع — نفس نمط وقواعد التطبيق الرئيسي:
 * كل عنصر يخضع لنفس مفاتيح الصلاحيات (pos.access / sales.view /
 * inventory.view / inventory.movements.view)، وهيكل عظمي حتى تحميل
 * الصلاحيات كي لا يلمس الموظف المقيّد الممنوع.
 * عناوين العناصر مفاتيح ترجمة (Task 48) تُرسم داخل المكون عبر useT('nav')،
 * و«الإعدادات» ليست في SIDEBAR_PERMISSION_ROUTES فتظهر دائمًا لكل من يدخل.
 */
const items = [
  { key: 'pos', href: '/pos', icon: ReceiptText },
  { key: 'sales', href: '/sales', icon: History },
  { key: 'inventory', href: '/inventory', icon: Package },
  { key: 'movements', href: '/inventory/movements', icon: ArrowLeftRight },
  { key: 'settings', href: '/settings', icon: Settings },
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
  const t = useT('nav')
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

  // الحرف الأول من اسم العرض عند توفره، وإلا «م» (Task 48)
  const resolvedName = context?.user.display_name || `${context?.user.first_name || ''} ${context?.user.last_name || ''}`.trim()
  const avatarLetter = resolvedName ? resolvedName.charAt(0) : t('avatar_initial')

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
    <div className={cn('flex h-full flex-col border-e border-border bg-card transition-all duration-300', collapsed ? 'w-[70px]' : 'w-[260px]')}>
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
        <button className="rounded-lg p-1.5 hover:bg-accent lg:hidden" onClick={onMobileClose} aria-label={t('close_menu')}>
          <X className="h-5 w-5" />
        </button>
        <button className="hidden rounded-lg p-1.5 hover:bg-accent lg:flex" onClick={() => setCollapsed(!collapsed)} aria-label={t('collapse_menu')}>
          {collapsed ? <ChevronLeft className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
        </button>
      </div>

      {!collapsed && (
        <div className="border-b border-border p-3">
          <div className="rounded-lg bg-primary/10 p-3">
            <p className="text-xs text-muted-foreground">{t('current_pharmacy')}</p>
            <p className="mt-1 truncate text-sm font-semibold">{context?.pharmacy.name || t('loading_pharmacy')}</p>
            <p className="mt-1 truncate text-xs text-muted-foreground">
              {context?.branch
                ? `${context.branch.name}${context.branch.city ? ` · ${context.branch.city}` : ''}`
                : context?.pharmacy.city || t('no_branch')}
            </p>
          </div>
        </div>
      )}

      <nav className="flex-1 space-y-1 overflow-y-auto p-3">
        <p className={cn('mb-2 text-xs font-medium text-muted-foreground', collapsed ? 'text-center' : 'px-3')}>{collapsed ? '•••' : t('sections')}</p>
        {!ready && (
          <div className="space-y-2" aria-hidden="true">
            {Array.from({ length: items.length }, (_, i) => (
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
              {active && <div className="absolute end-0 top-1/2 h-8 w-1 -translate-y-1/2 rounded-e-full bg-primary" />}
              <ItemIcon className={cn('h-5 w-5 shrink-0', active && 'text-primary')} />
              {!collapsed && <span className="flex-1">{t(item.key)}</span>}
              {collapsed && <div className="absolute end-full z-50 me-2 hidden whitespace-nowrap rounded-lg border border-border bg-popover px-3 py-2 text-sm shadow-lg group-hover:block">{t(item.key)}</div>}
            </Link>
          )
        })}
      </nav>

      <div className="border-t border-border p-4">
        <div className={cn('flex items-center gap-3', collapsed && 'justify-center')}>
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-sm font-medium text-primary">{avatarLetter}</div>
          {!collapsed && (
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">
                {resolvedName || t('user_fallback')}
              </p>
              <p className="truncate text-xs text-muted-foreground">{context?.user.role || t('pharmacy_account')}</p>
            </div>
          )}
          <Button
            variant="ghost"
            size="icon"
            className="shrink-0 text-muted-foreground hover:text-destructive"
            onClick={handleLogout}
            disabled={loggingOut}
            aria-label={t('logout')}
            title={t('logout')}
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
      <aside className={cn('print-hidden fixed bottom-0 start-0 top-0 z-50 transition-transform duration-300 lg:sticky lg:block lg:h-screen', mobileOpen ? 'translate-x-0' : 'rtl:translate-x-full ltr:-translate-x-full lg:translate-x-0')}>{content}</aside>
    </>
  )
}
