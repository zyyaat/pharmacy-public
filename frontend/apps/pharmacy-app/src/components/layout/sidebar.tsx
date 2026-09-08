'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useState } from 'react'
import { BarChart3, CalendarCheck, ChevronLeft, ChevronRight, LayoutDashboard, LogOut, Package, Settings, Store, Users, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui'

const items = [
  { title: 'لوحة التحكم', href: '/', icon: LayoutDashboard },
  { title: 'المخزون والأدوية', href: '/inventory', icon: Package, badge: '27' },
  { title: 'الموظفون', href: '/employees', icon: Users },
  { title: 'الحضور والانصراف', href: '/attendance', icon: CalendarCheck },
  { title: 'الفروع', href: '/branches', icon: Store },
  { title: 'التقارير', href: '/reports', icon: BarChart3 },
]

export default function Sidebar({ mobileOpen, onMobileClose }: { mobileOpen: boolean; onMobileClose: () => void }) {
  const pathname = usePathname()
  const [collapsed, setCollapsed] = useState(false)

  const content = (
    <div className={cn('flex h-full flex-col border-l border-border bg-card transition-all duration-300', collapsed ? 'w-[70px]' : 'w-[260px]')}>
      <div className="flex h-16 items-center justify-between border-b border-border px-4">
        {!collapsed && (
          <Link href="/" className="flex items-center gap-2">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary font-bold text-primary-foreground">P</div>
            <span className="gradient-text text-lg font-bold">Pharmacy OS</span>
          </Link>
        )}
        {collapsed && <div className="mx-auto flex h-9 w-9 items-center justify-center rounded-lg bg-primary font-bold text-primary-foreground">P</div>}
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
            <p className="mt-1 truncate text-sm font-semibold">صيدليات الأمل</p>
            <p className="mt-1 truncate text-xs text-muted-foreground">الفرع الرئيسي · القاهرة</p>
          </div>
        </div>
      )}

      <nav className="flex-1 space-y-1 overflow-y-auto p-3">
        <p className={cn('mb-2 text-xs font-medium text-muted-foreground', collapsed ? 'text-center' : 'px-3')}>{collapsed ? '•••' : 'القائمة الرئيسية'}</p>
        {items.map((item) => {
          const active = pathname === item.href || (item.href !== '/' && pathname.startsWith(item.href))
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
              {!collapsed && (
                <>
                  <span className="flex-1">{item.title}</span>
                  {item.badge && <span className={cn('rounded-full px-2 py-0.5 text-xs', active ? 'bg-primary/20 text-primary' : 'bg-muted text-muted-foreground')}>{item.badge}</span>}
                </>
              )}
              {collapsed && <div className="absolute right-full z-50 mr-2 hidden whitespace-nowrap rounded-lg border border-border bg-popover px-3 py-2 text-sm shadow-lg group-hover:block">{item.title}</div>}
            </Link>
          )
        })}
        <div className="mt-4 border-t border-border pt-4">
          <Link href="/settings" onClick={onMobileClose} className={cn('flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-all', pathname.startsWith('/settings') ? 'bg-primary/10 text-primary' : 'text-muted-foreground hover:bg-accent hover:text-foreground')}>
            <Settings className="h-5 w-5 shrink-0" />
            {!collapsed && <span>الإعدادات</span>}
          </Link>
        </div>
      </nav>

      <div className="border-t border-border p-4">
        <div className={cn('flex items-center gap-3', collapsed && 'justify-center')}>
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-sm font-medium text-primary">م</div>
          {!collapsed && (
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">محمد أحمد</p>
              <p className="truncate text-xs text-muted-foreground">مدير الصيدلية</p>
            </div>
          )}
          {!collapsed && <Button variant="ghost" size="icon" className="shrink-0 text-muted-foreground hover:text-destructive"><LogOut className="h-4 w-4" /></Button>}
        </div>
      </div>
    </div>
  )

  return (
    <>
      {mobileOpen && <div className="fixed inset-0 z-40 bg-black/50 lg:hidden" onClick={onMobileClose} />}
      <aside className={cn('fixed bottom-0 right-0 top-0 z-50 transition-transform duration-300 lg:sticky lg:block lg:h-screen', mobileOpen ? 'translate-x-0' : 'translate-x-full lg:translate-x-0')}>{content}</aside>
    </>
  )
}
