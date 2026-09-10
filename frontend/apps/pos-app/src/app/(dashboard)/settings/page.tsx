'use client'

// Task 48 — صفحة الإعدادات في تطبيق نقطة البيع: اللغة أول تفضيل دائم على الحساب.
import { LanguageSetting } from '@/components/settings/language-setting'
import { useT } from '@/i18n/provider'

export default function SettingsPage() {
  const t = useT('settings')
  return (
    <div className="mx-auto w-full max-w-2xl space-y-6 p-4 lg:p-6">
      <header className="space-y-1">
        <h1 className="text-xl font-bold lg:text-2xl">{t('title')}</h1>
        <p className="text-sm text-muted-foreground">{t('subtitle')}</p>
      </header>
      <LanguageSetting />
    </div>
  )
}
