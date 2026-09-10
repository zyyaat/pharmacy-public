'use client'

import { useCallback, useEffect, useState } from 'react'
import { CheckCircle2, Database, Info, Loader2, RefreshCw } from 'lucide-react'
import { Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui'
import { pharmacyApi, type SystemMigrationItem } from '@/lib/api'
import { fmtDate } from '@/i18n/format'
import { useT } from '@/i18n/provider'

/**
 * قاعدة البيانات — إدارة ترحيل المخطط بأسلوب أدوات الترحيل العالمية
 * (Flyway/Liquibase): الترحيلات تُطبَّق تلقائياً عند تشغيل النظام بأمان
 * (قفل استشاري + معاملة واحدة لكل ترحيل + سجل مرجعي دائم)، وهذه الصفحة
 * تعرض جزء الرصد: {t('schemaVersionLabel')} وسجل كل الترحيلات المطبقة وتواريخها.
 */

/** 00000000000019_sales_discount_customers.sql → { number: 19, title: sales discount customers } */
function parseMigration(version: string): { number: string; title: string; file: string } {
  const match = version.match(/^(\d+)_(.+?)(?:\.sql)?$/)
  if (!match) return { number: '—', title: version, file: version }
  return { number: String(Number(match[1])), title: match[2].replace(/_/g, ' '), file: version }
}

export default function DatabaseSettingsPage() {
  const t = useT('settings')
  const [items, setItems] = useState<SystemMigrationItem[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    setRefreshing(true)
    setError(null)
    try {
      const response = await pharmacyApi.getSystemMigrations()
      setItems(response.data.items)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : t('migrationsErrorFallback'))
    } finally {
      setRefreshing(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const latest = items && items.length > 0 ? parseMigration(items[items.length - 1].version) : null

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold">{t('databaseTitle')}</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          {t('databaseSubtitle')}
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Database className="h-5 w-5 text-primary" aria-hidden="true" />
            {t('schemaStatusTitle')}
          </CardTitle>
          <CardDescription>
            {t('schemaStatusDesc')}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {error && (
            <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-2.5 text-sm text-destructive">{error}</p>
          )}
          {!items && !error && (
            <p className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> {t('migrationsLoading')}
            </p>
          )}
          {items && (
            <div className="grid gap-3 sm:grid-cols-3">
              <div className="rounded-xl border border-border p-3.5">
                <p className="text-xs text-muted-foreground">{t('schemaVersionLabel')}</p>
                <p className="mt-1 text-xl font-extrabold">{latest ? `v${latest.number}` : '—'}</p>
                {latest && <p className="mt-0.5 truncate text-[11px] text-muted-foreground">{latest.title}</p>}
              </div>
              <div className="rounded-xl border border-border p-3.5">
                <p className="text-xs text-muted-foreground">{t('statusLabel')}</p>
                <p className="mt-1 flex items-center gap-1.5 text-sm font-bold text-emerald-600 dark:text-emerald-400">
                  <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
                  {t('statusUpToDate')}
                </p>
                <p className="mt-0.5 text-[11px] text-muted-foreground">{t('allAppliedNote')}</p>
              </div>
              <div className="rounded-xl border border-border p-3.5">
                <p className="text-xs text-muted-foreground">{t('appliedCountLabel')}</p>
                <p className="mt-1 text-xl font-extrabold">{items.length}</p>
                <p className="mt-0.5 text-[11px] text-muted-foreground">{t('sinceFirstInstall')}</p>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between space-y-0">
          <div>
            <CardTitle>{t('historyTitle')}</CardTitle>
            <CardDescription>{t('historyDesc')}</CardDescription>
          </div>
          <Button variant="outline" size="sm" onClick={load} disabled={refreshing}>
            <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} aria-hidden="true" />
            {t('refresh')}
          </Button>
        </CardHeader>
        <CardContent>
          {items && items.length > 0 && (
            <div className="overflow-x-auto rounded-xl border border-border">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border bg-muted/40 text-xs text-muted-foreground">
                    <th className="px-3 py-2.5 text-start font-semibold">v</th>
                    <th className="px-3 py-2.5 text-start font-semibold">{t('thMigration')}</th>
                    <th className="px-3 py-2.5 text-start font-semibold">{t('thAppliedAt')}</th>
                  </tr>
                </thead>
                <tbody>
                  {[...items].reverse().map((item) => {
                    const parsed = parseMigration(item.version)
                    return (
                      <tr key={item.version} className="border-b border-border/60 last:border-0">
                        <td className="px-3 py-2.5 font-bold">{parsed.number}</td>
                        <td className="px-3 py-2.5">
                          <span className="block font-semibold">{parsed.title}</span>
                          <code dir="ltr" className="mt-0.5 block text-[11px] text-muted-foreground">{parsed.file}</code>
                        </td>
                        <td className="whitespace-nowrap px-3 py-2.5 text-muted-foreground">
                          {fmtDate(new Date(item.applied_at), { dateStyle: 'medium', timeStyle: 'short' })}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
          {items && items.length === 0 && (
            <p className="py-8 text-center text-sm text-muted-foreground">{t('noMigrationsYet')}</p>
          )}
          <p className="mt-4 flex items-start gap-2 rounded-lg bg-muted/50 p-3 text-xs text-muted-foreground">
            <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            {t('autoMigrationsNote')}
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
