'use client'

import { useEffect, type ReactNode } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { ArrowRight, Database, FileSpreadsheet, Languages, ReceiptText } from 'lucide-react'
import BrandSplash from '@/components/brand-splash'
import { useT } from '@/i18n/provider'
import { useAuth } from '@/hooks/useAuth'
import { PermissionsProvider } from '@/hooks/usePermissions'
import { NoAccessCard, useAccess } from '@/components/permissions/gate'
import { SETTINGS_SECTION_PERMISSIONS } from '@/lib/permissions'

/**
 * منطقة الإعدادات المستقلة — نمط احترافي (زي GitHub/GitLab settings):
 * مكان كامل بعيد عن القائمة الجانبية الرئيسية، ليه شريط علوي فيه
 * «العودة للرئيسية» وقائمة جانبية خاصة بأقسام الإعدادات.
 *
 * Task 43: أقسام الإعدادات نفسها تختفي عن من لا يملك صلاحيتها، والدخول
 * المباشر برابط قسم ممنوع يعرض بطاقة «غير متاحة» بدل محتواه.
 * Task 48: قسم «اللغة» ظاهر دائمًا لكل المستخدمين (تغيير لغة الواجهة).
 */
const SECTIONS = [
  { key: 'import', href: '/settings/import', icon: FileSpreadsheet },
  { key: 'receipts', href: '/settings/receipts', icon: ReceiptText },
  { key: 'database', href: '/settings/database', icon: Database },
  { key: 'language', href: '/settings/language', icon: Languages },
] as const

function sectionAllowed(href: string, allowedAny: (keys: string[]) => boolean, fullAccess: boolean): boolean {
  // قسم اللغة متاح دائمًا — كل مستخدم يحتاج تغيير لغة الواجهة
  if (href === '/settings/language') return true
  const required = SETTINGS_SECTION_PERMISSIONS[href]
  // قسم بلا صلاحية محددة (قاعدة البيانات) للمالك الكامل فقط
  if (!required || required.length === 0) return fullAccess
  return allowedAny(required)
}

function SettingsChrome({ children }: { children: ReactNode }) {
  const t = useT('settings')
  const pathname = usePathname()
  const { ready, allowedAny, fullAccess } = useAccess()

  const visibleSections = SECTIONS.filter((section) => {
    if (!ready) return false
    return sectionAllowed(section.href, allowedAny, fullAccess)
  })

  // الدخول المباشر برابط قسم ممنوع → بطاقة بدل محتوى القسم
  const currentSection = SECTIONS.find((section) => pathname === section.href || pathname.startsWith(`${section.href}/`))
  const currentAllowed = !ready || !currentSection || sectionAllowed(currentSection.href, allowedAny, fullAccess)

  const isActive = (href: string) => pathname === href || pathname.startsWith(`${href}/`)

  return (
    <div className="min-h-screen bg-background">
      {/* الشريط العلوي: العودة للرئيسية + مسار الإعدادات */}
      <header className="sticky top-0 z-30 border-b border-border bg-background/90 backdrop-blur-md">
        <div className="mx-auto flex h-14 max-w-6xl items-center gap-3 px-4 lg:px-6">
          <Link
            href="/"
            className="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-bold text-primary transition-colors hover:bg-primary/10"
          >
            <ArrowRight className="h-4 w-4 rtl-flip" aria-hidden="true" />
            {t('backToHome')}
          </Link>
          <span className="text-muted-foreground" aria-hidden="true">/</span>
          <span className="text-sm font-semibold text-muted-foreground">{t('breadcrumb')}</span>
        </div>
      </header>

      <div className="mx-auto flex max-w-6xl gap-8 px-4 py-6 lg:px-6">
        {/* القائمة الجانبية الخاصة بالإعدادات */}
        <nav aria-label={t('navAria')} className="hidden w-64 shrink-0 md:block">
          <div className="sticky top-20 space-y-1">
            {visibleSections.map((section) => {
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
                    <span className="block text-sm font-bold">{t(`${section.key}NavLabel`)}</span>
                    <span className="mt-0.5 block text-xs text-muted-foreground">{t(`${section.key}NavDesc`)}</span>
                  </span>
                </Link>
              )
            })}
          </div>
        </nav>

        <div className="min-w-0 flex-1">
          {/* نسخة موبايل: شرائح أفقية قابلة للتمرير */}
          <nav aria-label={t('navAriaCompact')} className="mb-5 flex gap-2 overflow-x-auto pb-1 md:hidden">
            {visibleSections.map((section) => {
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
                  {t(`${section.key}NavLabel`)}
                </Link>
              )
            })}
          </nav>
          {currentAllowed ? children : <NoAccessCard />}
        </div>
      </div>
    </div>
  )
}

export default function SettingsLayout({ children }: { children: ReactNode }) {
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
      <BrandSplash show={loading || !user} />
      {user && (
        <PermissionsProvider>
          <SettingsChrome>{children}</SettingsChrome>
        </PermissionsProvider>
      )}
    </>
  )
}
