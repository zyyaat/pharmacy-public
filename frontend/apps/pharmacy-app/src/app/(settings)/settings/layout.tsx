'use client'

import { useEffect, type ReactNode } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { ArrowRight, Database, ReceiptText } from 'lucide-react'
import BrandSplash from '@/components/brand-splash'
import { useAuth } from '@/hooks/useAuth'

/**
 * منطقة الإعدادات المستقلة — نمط احترافي (زي GitHub/GitLab settings):
 * مكان كامل بعيد عن القائمة الجانبية الرئيسية، ليه شريط علوي فيه
 * «العودة للرئيسية» وقائمة جانبية خاصة بأقسام الإعدادات.
 */
const SECTIONS = [
  { href: '/settings/receipts', label: 'الفواتير والطباعة', icon: ReceiptText, desc: 'شكل الفاتورة وسلوك الطباعة' },
  { href: '/settings/database', label: 'قاعدة البيانات', icon: Database, desc: 'حالة المخطط وسجل الترحيلات' },
] as const

export default function SettingsLayout({ children }: { children: ReactNode }) {
  const { user, loading } = useAuth()
  const router = useRouter()
  const pathname = usePathname()

  useEffect(() => {
    if (!loading && !user) {
      router.replace(`/login?next=${encodeURIComponent(pathname)}`)
    }
  }, [loading, user, router, pathname])

  const isActive = (href: string) => pathname === href || pathname.startsWith(`${href}/`)

  return (
    <>
      <BrandSplash show={loading || !user} />
      {user && (
        <div className="min-h-screen bg-background" dir="rtl">
          {/* الشريط العلوي: العودة للرئيسية + مسار الإعدادات */}
          <header className="sticky top-0 z-30 border-b border-border bg-background/90 backdrop-blur-md">
            <div className="mx-auto flex h-14 max-w-6xl items-center gap-3 px-4 lg:px-6">
              <Link
                href="/"
                className="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-bold text-primary transition-colors hover:bg-primary/10"
              >
                <ArrowRight className="h-4 w-4" aria-hidden="true" />
                العودة للرئيسية
              </Link>
              <span className="text-muted-foreground" aria-hidden="true">/</span>
              <span className="text-sm font-semibold text-muted-foreground">الإعدادات</span>
            </div>
          </header>

          <div className="mx-auto flex max-w-6xl gap-8 px-4 py-6 lg:px-6">
            {/* القائمة الجانبية الخاصة بالإعدادات */}
            <nav aria-label="أقسام الإعدادات" className="hidden w-64 shrink-0 md:block">
              <div className="sticky top-20 space-y-1">
                {SECTIONS.map((section) => {
                  const active = isActive(section.href)
                  return (
                    <Link
                      key={section.href}
                      href={section.href}
                      aria-current={active ? 'page' : undefined}
                      className={`flex items-start gap-3 rounded-xl px-3.5 py-3 transition-colors ${
                        active
                          ? 'bg-primary/10 text-primary ring-1 ring-primary/20'
                          : 'text-muted-foreground hover:bg-accent hover:text-foreground'
                      }`}
                    >
                      <section.icon className="mt-0.5 h-5 w-5 shrink-0" aria-hidden="true" />
                      <span>
                        <span className="block text-sm font-bold">{section.label}</span>
                        <span className="mt-0.5 block text-xs text-muted-foreground">{section.desc}</span>
                      </span>
                    </Link>
                  )
                })}
              </div>
            </nav>

            <div className="min-w-0 flex-1">
              {/* نسخة موبايل: شرائح أفقية قابلة للتمرير */}
              <nav aria-label="أقسام الإعدادات المختصرة" className="mb-5 flex gap-2 overflow-x-auto pb-1 md:hidden">
                {SECTIONS.map((section) => {
                  const active = isActive(section.href)
                  return (
                    <Link
                      key={section.href}
                      href={section.href}
                      aria-current={active ? 'page' : undefined}
                      className={`flex shrink-0 items-center gap-1.5 rounded-full border px-4 py-2 text-sm font-semibold transition-colors ${
                        active
                          ? 'border-primary bg-primary/10 text-primary'
                          : 'border-border text-muted-foreground hover:text-foreground'
                      }`}
                    >
                      <section.icon className="h-4 w-4" aria-hidden="true" />
                      {section.label}
                    </Link>
                  )
                })}
              </nav>
              {children}
            </div>
          </div>
        </div>
      )}
    </>
  )
}
