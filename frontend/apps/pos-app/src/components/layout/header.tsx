'use client'

import { Menu, Moon, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'
import { Button } from '@/components/ui'
import { useT } from '@/i18n/provider'

/**
 * هيدر تطبيق نقطة البيع — أدنى ما يمكن كي تبقى شاشة البيع أوسع وأسرع:
 * زر القائمة للموبايل + زر الوضع الليلي فقط. الجرس والبحث العام
 * مقصوران على تطبيق الإدارة الرئيسي لأن صفحاتهما المقصودة غير موجودة هنا.
 */
export default function Header({ onMenuClick }: { onMenuClick?: () => void }) {
  const { theme, setTheme } = useTheme()
  const t = useT('nav')

  return (
    <header className="print-hidden sticky top-0 z-30 flex h-16 items-center gap-4 border-b border-border bg-background/80 px-4 backdrop-blur-md lg:px-6">
      <Button variant="ghost" size="icon" className="lg:hidden" onClick={onMenuClick}>
        <Menu className="h-5 w-5" />
      </Button>

      <p className="text-sm font-semibold">{t('pos')}</p>

      <div className="flex flex-1 items-center justify-end">
        <Button
          variant="ghost"
          size="icon"
          onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          title={theme === 'dark' ? t('light_mode') : t('dark_mode')}
        >
          <Sun className="h-5 w-5 rotate-0 scale-100 transition-all dark:-rotate-90 dark:scale-0" />
          <Moon className="absolute h-5 w-5 rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100" />
        </Button>
      </div>
    </header>
  )
}
