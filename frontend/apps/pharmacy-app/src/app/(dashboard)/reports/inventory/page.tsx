'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { AlertTriangle, ArrowRight, CalendarClock, Boxes, PackageX, Printer } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type InventoryReport,
  type PharmacyContext,
  type PharmacyInventoryItem,
} from '@/lib/api'
import { formatPiastres } from '@/lib/money'
import { formatArabicDate } from '@/lib/reports'
import {
  Badge,
  Button,
  Card,
  CardContent,
  LoadingSpinner,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import { RequirePermission } from '@/components/permissions/gate'
import { KpiCards, ReportSheet, useReportContext } from '@/components/reports'

const statusBadges: Record<string, { label: string; variant: 'success' | 'warning' | 'destructive' }> = {
  normal: { label: 'متوفر', variant: 'success' },
  low_stock: { label: 'منخفض', variant: 'warning' },
  out_of_stock: { label: 'نفذ', variant: 'destructive' },
  expiring_soon: { label: 'قريب الانتهاء', variant: 'warning' },
  quarantined: { label: 'حجر صحي', variant: 'warning' },
}

/** لون شدة قرب انتهاء الصلاحية */
function expiryTone(days: number): 'destructive' | 'warning' | 'secondary' {
  if (days <= 0) return 'destructive'
  if (days <= 30) return 'warning'
  return 'secondary'
}

export default function InventoryReportPage() {
  const { generatedAt } = useReportContext()
  const [report, setReport] = useState<InventoryReport | null>(null)
  const [items, setItems] = useState<PharmacyInventoryItem[]>([])
  const [context, setContext] = useState<PharmacyContext | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    async function loadAll() {
      setLoading(true)
      setError(null)
      try {
        const [reportResponse, inventoryResponse, contextResponse] = await Promise.all([
          pharmacyApi.getInventoryReport(),
          pharmacyApi.getInventory(),
          pharmacyApi.getContext().catch(() => null),
        ])
        if (!active) return
        setReport(reportResponse.data)
        setItems(inventoryResponse.data)
        if (contextResponse) setContext(contextResponse)
      } catch (cause) {
        if (active) setError(cause instanceof ApiError ? cause.message : 'تعذر تحميل تقرير المخزون')
      } finally {
        if (active) setLoading(false)
      }
    }
    loadAll()
    return () => {
      active = false
    }
  }, [])

  const kpis = useMemo(() => {
    if (!report) return []
    const { totals } = report
    return [
      {
        label: 'قيمة المخزون (تكلفة)',
        value: formatPiastres(totals.cost_value_piastres),
        hint: `${totals.batches_count.toLocaleString('ar-EG')} تشغيلة · ${totals.products_count.toLocaleString('ar-EG')} صنف`,
      },
      {
        label: 'قيمة البيع المتوقعة',
        value: formatPiastres(totals.retail_value_piastres),
        tone: 'success' as const,
        hint: `${totals.units_base.toLocaleString('ar-EG')} وحدة أساسية`,
      },
      {
        label: 'أصناف منخفضة',
        value: totals.low_stock_count.toLocaleString('ar-EG'),
        tone: totals.low_stock_count > 0 ? ('warning' as const) : ('default' as const),
        hint: 'عند أو تحت الحد الأدنى',
      },
      {
        label: 'أصناف نافدة',
        value: totals.out_of_stock_count.toLocaleString('ar-EG'),
        tone: totals.out_of_stock_count > 0 ? ('destructive' as const) : ('default' as const),
      },
    ]
  }, [report])

  const expiryBuckets = useMemo(() => {
    if (!report) return []
    const { expiry } = report
    return [
      {
        icon: PackageX,
        label: 'منتهية الصلاحية',
        count: expiry.expired_count,
        tone: 'text-destructive',
        bg: 'bg-destructive/10',
      },
      {
        icon: CalendarClock,
        label: 'خلال 30 يوم',
        count: expiry.expiring_30_count,
        tone: 'text-amber-600 dark:text-amber-400',
        bg: 'bg-amber-500/10',
      },
      {
        icon: CalendarClock,
        label: '31 – 60 يوم',
        count: expiry.expiring_60_count,
        tone: 'text-foreground',
        bg: 'bg-muted',
      },
      {
        icon: CalendarClock,
        label: '61 – 90 يوم',
        count: expiry.expiring_90_count,
        tone: 'text-foreground',
        bg: 'bg-muted',
      },
    ]
  }, [report])

  return (
    <RequirePermission anyOf={['reports.inventory']}>
    <div className="space-y-5">
      {/* شريط التحكم — لا يظهر عند الطباعة */}
      <div className="print-hidden flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Button asChild variant="ghost" size="icon">
            <Link href="/reports" aria-label="العودة للتقارير">
              <ArrowRight className="h-5 w-5" />
            </Link>
          </Button>
          <div>
            <h1 className="text-2xl font-bold">تقرير المخزون</h1>
            <p className="mt-0.5 text-sm text-muted-foreground">
              قيمة المخزون والنواقص والصلاحيات لحظة الإنشاء
            </p>
          </div>
        </div>
        <Button onClick={() => window.print()} disabled={loading}>
          <Printer className="h-4 w-4" /> طباعة PDF
        </Button>
      </div>

      {error && (
        <Card>
          <CardContent className="p-4 text-sm text-destructive">{error}</CardContent>
        </Card>
      )}

      {loading && !report ? (
        <div className="flex items-center justify-center py-20">
          <LoadingSpinner />
        </div>
      ) : report ? (
        <ReportSheet
          title="تقرير المخزون"
          subtitle="حالة المخزون الحالية وقيمته"
          icon={<Boxes className="h-5 w-5 text-primary" />}
          period={null}
          pharmacy={
            context
              ? {
                  name: context.pharmacy.name,
                  city: context.pharmacy.city,
                  branchName: context.branch?.name,
                  userName: context.user.display_name,
                }
              : null
          }
          generatedAt={generatedAt}
        >
          {kpis.length > 0 && <KpiCards items={kpis} />}

          {/* مجموعات الصلاحية */}
          <section className="print-avoid-break">
            <h3 className="mb-3 text-sm font-bold">الصلاحيات (خلال 90 يوم)</h3>
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
              {expiryBuckets.map((bucket) => {
                const Icon = bucket.icon
                return (
                  <div
                    key={bucket.label}
                    className="print-avoid-break rounded-xl border border-border bg-card p-4"
                  >
                    <div className="flex items-center gap-2">
                      <span className={`flex h-8 w-8 items-center justify-center rounded-lg ${bucket.bg}`}>
                        <Icon className={`h-4 w-4 ${bucket.tone}`} />
                      </span>
                      <p className="text-xs font-medium text-muted-foreground">{bucket.label}</p>
                    </div>
                    <p className={`mt-2 text-xl font-bold tabular-nums ${bucket.tone}`}>
                      {bucket.count.toLocaleString('ar-EG')} تشغيلة
                    </p>
                  </div>
                )
              })}
            </div>
            {(report.expiry.expired_value_piastres > 0 || report.expiry.expiring_value_piastres > 0) && (
              <p className="mt-2 text-xs text-muted-foreground">
                قيمة المخزون المنتهي:{' '}
                <span className="font-semibold text-destructive">
                  {formatPiastres(report.expiry.expired_value_piastres)}
                </span>{' '}
                · قيمة المخزون ضمن 90 يوم قادمة:{' '}
                <span className="font-semibold">{formatPiastres(report.expiry.expiring_value_piastres)}</span>
              </p>
            )}
          </section>

          {/* النواقص */}
          <section className="print-avoid-break">
            <h3 className="mb-3 flex items-center gap-2 text-sm font-bold">
              <AlertTriangle className="h-4 w-4 text-amber-500" />
              قائمة النواقص (أول 20)
            </h3>
            {report.low_stock_items.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-6 text-center text-sm text-muted-foreground">
                لا توجد نواقص — المخزون فوق الحد الأدنى
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>الصنف</TableHead>
                      <TableHead>التشغيلة</TableHead>
                      <TableHead>الفرع</TableHead>
                      <TableHead className="w-[90px]">المتاح</TableHead>
                      <TableHead className="w-[110px]">الحد الأدنى</TableHead>
                      <TableHead className="w-[90px]">الحالة</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {report.low_stock_items.map((item, index) => (
                      <TableRow key={`${item.name}-${item.batch_number}-${index}`}>
                        <TableCell>
                          <p className="font-medium">{item.name}</p>
                          {item.generic_name && (
                            <p className="text-xs text-muted-foreground">{item.generic_name}</p>
                          )}
                        </TableCell>
                        <TableCell className="font-mono text-xs">
                          {item.batch_number ? (
                            <span dir="ltr" className="inline-block">
                              {item.batch_number}
                            </span>
                          ) : (
                            '—'
                          )}
                        </TableCell>
                        <TableCell className="text-xs">{item.branch_name || '—'}</TableCell>
                        <TableCell className="font-semibold tabular-nums">
                          {item.quantity.toLocaleString('ar-EG')}
                        </TableCell>
                        <TableCell className="tabular-nums text-muted-foreground">
                          {item.threshold.toLocaleString('ar-EG')}
                        </TableCell>
                        <TableCell>
                          <Badge variant={item.quantity <= 0 ? 'destructive' : 'warning'}>
                            {item.quantity <= 0 ? 'نفذ' : 'منخفض'}
                          </Badge>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </section>

          {/* الصلاحيات القريبة */}
          <section className="print-avoid-break">
            <h3 className="mb-3 flex items-center gap-2 text-sm font-bold">
              <CalendarClock className="h-4 w-4 text-amber-500" />
              صلاحيات قريبة أو منتهية (أول 20)
            </h3>
            {report.expiring_items.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-6 text-center text-sm text-muted-foreground">
                لا توجد تشغيلات منتهية أو قريبة الانتهاء خلال 90 يوم
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>الصنف</TableHead>
                      <TableHead>التشغيلة</TableHead>
                      <TableHead className="w-[90px]">المتاح</TableHead>
                      <TableHead className="w-[130px]">تاريخ الانتهاء</TableHead>
                      <TableHead className="w-[110px]">الأيام المتبقية</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {report.expiring_items.map((item, index) => (
                      <TableRow key={`${item.name}-${item.batch_number}-${index}`}>
                        <TableCell>
                          <p className="font-medium">{item.name}</p>
                          {item.generic_name && (
                            <p className="text-xs text-muted-foreground">{item.generic_name}</p>
                          )}
                        </TableCell>
                        <TableCell className="font-mono text-xs">
                          {item.batch_number ? (
                            <span dir="ltr" className="inline-block">
                              {item.batch_number}
                            </span>
                          ) : (
                            '—'
                          )}
                        </TableCell>
                        <TableCell className="tabular-nums">
                          {item.quantity.toLocaleString('ar-EG')}
                        </TableCell>
                        <TableCell className="whitespace-nowrap text-xs tabular-nums">
                          {item.extra_date ? formatArabicDate(String(item.extra_date).slice(0, 10)) : '—'}
                        </TableCell>
                        <TableCell>
                          <Badge variant={expiryTone(item.threshold)}>
                            {item.threshold <= 0
                              ? 'منتهية'
                              : `${item.threshold.toLocaleString('ar-EG')} يوم`}
                          </Badge>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </section>

          {/* تفاصيل المخزون الحالي */}
          <section>
            <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
              <h3 className="text-sm font-bold">تفاصيل المخزون الحالي</h3>
              {items.length >= 500 && (
                <p className="text-xs text-muted-foreground">تُعرض أول 500 تشغيلة</p>
              )}
            </div>
            {items.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-8 text-center text-sm text-muted-foreground">
                لا يوجد مخزون حالياً
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>الصنف</TableHead>
                      <TableHead>التشغيلة</TableHead>
                      <TableHead>الفرع</TableHead>
                      <TableHead className="w-[90px]">المتاح</TableHead>
                      <TableHead className="w-[120px]">سعر البيع</TableHead>
                      <TableHead className="w-[130px]">إجمالي التكلفة</TableHead>
                      <TableHead className="w-[120px]">الصلاحية</TableHead>
                      <TableHead className="w-[90px]">الحالة</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {items.map((item) => {
                      const status = statusBadges[item.status] ?? statusBadges.normal
                      return (
                        <TableRow key={item.batch_id}>
                          <TableCell className="max-w-[240px]">
                            <p className="truncate font-medium" title={item.product_name}>
                              {item.product_name}
                            </p>
                            {item.generic_name && (
                              <p className="truncate text-xs text-muted-foreground">
                                {item.generic_name}
                              </p>
                            )}
                          </TableCell>
                          <TableCell className="font-mono text-xs">
                            {item.batch_number ? (
                              <span dir="ltr" className="inline-block">
                                {item.batch_number}
                              </span>
                            ) : (
                              '—'
                            )}
                          </TableCell>
                          <TableCell className="text-xs">{item.branch_name || '—'}</TableCell>
                          <TableCell className="font-semibold tabular-nums">
                            {item.quantity.toLocaleString('ar-EG')}
                          </TableCell>
                          <TableCell className="tabular-nums">
                            {formatPiastres(item.selling_price_piastres)}
                          </TableCell>
                          <TableCell className="tabular-nums">
                            {formatPiastres(item.total_cost_piastres)}
                          </TableCell>
                          <TableCell className="whitespace-nowrap text-xs tabular-nums">
                            {item.expiry_date ? formatArabicDate(item.expiry_date.slice(0, 10)) : '—'}
                          </TableCell>
                          <TableCell>
                            <Badge variant={status.variant}>{status.label}</Badge>
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>
            )}
          </section>
        </ReportSheet>
      ) : null}
    </div>
    </RequirePermission>
  )
}
