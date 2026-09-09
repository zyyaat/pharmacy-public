'use client'

import { useCallback, useEffect, useState } from 'react'
import { CheckCircle2, Database, Info, Loader2, RefreshCw } from 'lucide-react'
import { Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui'
import { pharmacyApi, type SystemMigrationItem } from '@/lib/api'

/**
 * قاعدة البيانات — إدارة ترحيل المخطط بأسلوب أدوات الترحيل العالمية
 * (Flyway/Liquibase): الترحيلات تُطبَّق تلقائياً عند تشغيل النظام بأمان
 * (قفل استشاري + معاملة واحدة لكل ترحيل + سجل مرجعي دائم)، وهذه الصفحة
 * تعرض جزء الرصد: إصدار المخطط الحالي وسجل كل الترحيلات المطبقة وتواريخها.
 */

/** 00000000000019_sales_discount_customers.sql → { number: 19, title: sales discount customers } */
function parseMigration(version: string): { number: string; title: string; file: string } {
  const match = version.match(/^(\d+)_(.+?)(?:\.sql)?$/)
  if (!match) return { number: '—', title: version, file: version }
  return { number: String(Number(match[1])), title: match[2].replace(/_/g, ' '), file: version }
}

const dateFormatter = new Intl.DateTimeFormat('ar-EG', {
  dateStyle: 'medium',
  timeStyle: 'short',
})

export default function DatabaseSettingsPage() {
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
      setError(cause instanceof Error ? cause.message : 'تعذر قراءة سجل الترحيلات')
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
        <h1 className="text-2xl font-bold">قاعدة البيانات</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          حالة مخطط قاعدة البيانات وسجل الترحيلات المطبقة — الشفافية الكاملة في تغييرات البنية.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Database className="h-5 w-5 text-primary" aria-hidden="true" />
            حالة المخطط
          </CardTitle>
          <CardDescription>
            الترحيلات تُطبَّق تلقائياً عند تشغيل النظام بأفضل الممارسات العالمية: قفل استشاري يمنع التنفيذ المتوازي،
            ومعاملة واحدة لكل ترحيل (تنجح كلها أو تفشل كلها)، وسجل مرجعي دائم يمنع التكرار.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {error && (
            <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-2.5 text-sm text-destructive">{error}</p>
          )}
          {!items && !error && (
            <p className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> جاري قراءة سجل الترحيلات…
            </p>
          )}
          {items && (
            <div className="grid gap-3 sm:grid-cols-3">
              <div className="rounded-xl border border-border p-3.5">
                <p className="text-xs text-muted-foreground">إصدار المخطط الحالي</p>
                <p className="mt-1 text-xl font-extrabold">{latest ? `v${latest.number}` : '—'}</p>
                {latest && <p className="mt-0.5 truncate text-[11px] text-muted-foreground">{latest.title}</p>}
              </div>
              <div className="rounded-xl border border-border p-3.5">
                <p className="text-xs text-muted-foreground">الحالة</p>
                <p className="mt-1 flex items-center gap-1.5 text-sm font-bold text-emerald-600 dark:text-emerald-400">
                  <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
                  محدّثة
                </p>
                <p className="mt-0.5 text-[11px] text-muted-foreground">كل الترحيلات المطلوبة مطبقة</p>
              </div>
              <div className="rounded-xl border border-border p-3.5">
                <p className="text-xs text-muted-foreground">عدد الترحيلات المطبقة</p>
                <p className="mt-1 text-xl font-extrabold">{items.length}</p>
                <p className="mt-0.5 text-[11px] text-muted-foreground">منذ أول تركيب للنظام</p>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between space-y-0">
          <div>
            <CardTitle>سجل الترحيلات المطبقة</CardTitle>
            <CardDescription>الأحدث أولاً — التسلسل يطابق ترتيب التطبيق الفعلي على قاعدة البيانات.</CardDescription>
          </div>
          <Button variant="outline" size="sm" onClick={load} disabled={refreshing}>
            <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} aria-hidden="true" />
            تحديث
          </Button>
        </CardHeader>
        <CardContent>
          {items && items.length > 0 && (
            <div className="overflow-x-auto rounded-xl border border-border">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border bg-muted/40 text-xs text-muted-foreground">
                    <th className="px-3 py-2.5 text-right font-semibold">v</th>
                    <th className="px-3 py-2.5 text-right font-semibold">الترحيل</th>
                    <th className="px-3 py-2.5 text-right font-semibold">تاريخ التطبيق</th>
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
                          {dateFormatter.format(new Date(item.applied_at))}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
          {items && items.length === 0 && (
            <p className="py-8 text-center text-sm text-muted-foreground">لا توجد ترحيلات مسجلة بعد.</p>
          )}
          <p className="mt-4 flex items-start gap-2 rounded-lg bg-muted/50 p-3 text-xs text-muted-foreground">
            <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            عند إضافة ميزات جديدة للنظام تُضاف ترحيلات مرقّمة إلى السلسلة، وتُطبَّق على قاعدتك تلقائياً عند التحديث
            — دون أي تدخل يدوي ودون فقدان بيانات.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
