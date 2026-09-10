'use client'

// Task 48 — منتقي لغة الواجهة، نفس المكون في كل التطبيقات:
// يعرض اللغات الأكثر استخدامًا عالميًا بأسمائها الأصلية، يحفظ الاختيار
// دائمًا على الحساب عبر الباكند، ثم يحدّث الكوكي وشجرة الخادم فورًا.
import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { Check, Languages, Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'
import { locales, LOCALE_META, type Locale } from '@/i18n/config'
import { useLocale, useT } from '@/i18n/provider'
import { changeLocale } from '@/i18n/change-locale'

export function LanguageSetting() {
  const t = useT('settings')
  const tCommon = useT('common')
  const locale = useLocale()
  const router = useRouter()
  const [pending, setPending] = useState<Locale | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function handleSelect(next: Locale) {
    if (next === locale || pending) return
    setPending(next)
    setError(null)
    try {
      await changeLocale(next)
      router.refresh() // إعادة رسم شجرة الخادم بالكوكي والقاموس الجديدين
    } catch {
      setError(tCommon('language_change_failed'))
    } finally {
      setPending(null)
    }
  }

  return (
    <section className="rounded-xl border border-border bg-card" aria-labelledby="language-setting-title">
      <div className="flex items-center gap-3 border-b border-border p-4">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
          <Languages className="h-5 w-5" aria-hidden="true" />
        </span>
        <div className="min-w-0">
          <h2 id="language-setting-title" className="text-sm font-bold">{t('language_title')}</h2>
          <p className="mt-0.5 text-xs text-muted-foreground">{t('language_desc')}</p>
        </div>
      </div>
      <ul className="grid gap-2 p-4 sm:grid-cols-2">
        {locales.map((code) => {
          const meta = LOCALE_META[code]
          const active = code === locale
          const busy = pending === code
          return (
            <li key={code}>
              <button
                type="button"
                onClick={() => void handleSelect(code)}
                disabled={pending !== null}
                aria-pressed={active}
                className={cn(
                  'flex w-full items-center justify-between gap-3 rounded-lg border p-3 text-start transition-colors',
                  active
                    ? 'border-primary bg-primary/10 text-primary'
                    : 'border-border text-foreground hover:bg-accent',
                )}
              >
                <span className="min-w-0">
                  <span className="block truncate text-sm font-semibold">{meta.nativeName}</span>
                  <span className="mt-0.5 block truncate text-xs text-muted-foreground">{meta.englishName}</span>
                </span>
                {busy ? (
                  <Loader2 className="h-4 w-4 shrink-0 animate-spin" aria-hidden="true" />
                ) : active ? (
                  <Check className="h-4 w-4 shrink-0" aria-hidden="true" />
                ) : null}
              </button>
            </li>
          )
        })}
      </ul>
      {error && <p className="px-4 pb-4 text-xs font-semibold text-destructive">{error}</p>}
    </section>
  )
}
