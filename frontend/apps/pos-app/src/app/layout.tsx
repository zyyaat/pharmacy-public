import type { Metadata } from 'next'
import { Geist, Geist_Mono } from 'next/font/google'
import { ThemeProvider } from 'next-themes'
import './globals.css'
import { AuthProvider } from '@/hooks/useAuth'
import { I18nProvider } from '@/i18n/provider'
import { getServerI18n } from '@/i18n/server'

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
})

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
})

// Task 48 — العنوان يتبع لغة الواجهة المحفوظة على الحساب/الكوكي
export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getServerI18n()
  return {
    title: t('common.meta_title'),
    description: t('common.meta_description'),
  }
}

// Task 48 — lang/dir والقاموس يُقرآن من الكوكي (الافتراضي العربية RTL)
export default async function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const { locale, dir, messages } = await getServerI18n()
  return (
    <html lang={locale} dir={dir} suppressHydrationWarning>
      <body className={`${geistSans.variable} ${geistMono.variable} font-[family-name:var(--font-geist-sans)] antialiased bg-background text-foreground`}>
        <ThemeProvider attribute="class" defaultTheme="dark" enableSystem disableTransitionOnChange>
          <I18nProvider locale={locale} messages={messages}>
            <AuthProvider>{children}</AuthProvider>
          </I18nProvider>
        </ThemeProvider>
      </body>
    </html>
  )
}
