'use client'

// Task 48 — مزود i18n للعميل: يستقبل اللغة والقاموس من الخادم (root layout)
// ويوزعهما على كل المكونات عبر useT/useLocale، مع مزامنة الوحدات غير
// القابلة للسياق (api/money) عبر runtime.
import { createContext, useContext, useEffect, useMemo, type ReactNode } from 'react'
import { DEFAULT_LOCALE, type Locale } from './config'
import type { Messages } from './messages'
import { createTranslator, type Translator } from './translator'
import { setRuntimeLocale } from './runtime'

interface I18nContextValue {
  locale: Locale
  messages: Messages
}

const I18nContext = createContext<I18nContextValue | null>(null)

export function I18nProvider({
  locale,
  messages,
  children,
}: {
  locale: Locale
  messages: Messages
  children: ReactNode
}) {
  // مزامنة فورية (أثناء الرسم) + بعد الالتزام — مهمة للوحدات خارج React.
  setRuntimeLocale(locale)
  useEffect(() => {
    setRuntimeLocale(locale)
  }, [locale])

  const value = useMemo(() => ({ locale, messages }), [locale, messages])
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

function useI18nContext(): I18nContextValue {
  const ctx = useContext(I18nContext)
  if (!ctx) throw new Error('i18n: I18nProvider مفقود فوق شجرة المكونات')
  return ctx
}

export function useLocale(): Locale {
  return useI18nContext().locale
}

/** مترجم مساحة نصوص واحدة — مثال: const t = useT('inventory') ثم t('title') */
export function useT(namespace?: string): Translator {
  const { messages } = useI18nContext()
  return useMemo(() => createTranslator(messages, namespace), [messages, namespace])
}
