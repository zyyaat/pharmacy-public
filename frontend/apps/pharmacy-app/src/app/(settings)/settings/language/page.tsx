'use client'

// Task 48 — قسم «اللغة» في إعدادات التطبيق الرئيسي (متاح لكل الحسابات بلا استثناء).
import { LanguageSetting } from '@/components/settings/language-setting'
import { useT } from '@/i18n/provider'

export default function LanguageSettingsPage() {
  const t = useT('settings')
  return (
    <div className="mx-auto w-full max-w-2xl space-y-6">
      <header className="space-y-1">
        <h1 className="text-xl font-bold lg:text-2xl">{t('language_title')}</h1>
        <p className="text-sm text-muted-foreground">{t('language_desc')}</p>
      </header>
      <LanguageSetting />
    </div>
  )
}
