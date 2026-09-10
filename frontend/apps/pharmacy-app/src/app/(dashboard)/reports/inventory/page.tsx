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
import { useT } from '@/i18n/provider'
import { fmtNumber } from '@/i18n/format'
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

const statusBadgeKeys: Record<string, { key: string; variant: 'success' | 'warning' | 'destructive' }> = {
  normal: { key: 'status_normal', variant: 'success' },
  low_stock: { key: 'status_low', variant: 'warning' },
  out_of_stock: { key: 'status_out', variant: 'destructive' },
  expiring_soon: { key: 'status_expiring_soon', variant: 'warning' },
  quarantined: { key: 'status_quarantined', variant: 'warning' },
}

/** لون شدة قرب انتهاء الصلاحية */
function expiryTone(days: number): 'destructive' | 'warning' | 'secondary' {
  if (days <= 0) return 'destructive'
  if (days <= 30) return 'warning'
  return 'secondary'
}

export default function InventoryReportPage() {
  const t = useT('reports')
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
        if (active) setError(cause instanceof ApiError ? cause.message : t('error_load_inventory'))
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
        label: t('kpi_cost_value'),
        value: formatPiastres(totals.cost_value_piastres),
        hint: t('hint_batches_products', {
          batches: fmtNumber(totals.batches_count),
          products: fmtNumber(totals.products_count),
        }),
      },
      {
        label: t('kpi_retail_value'),
        value: formatPiastres(totals.retail_value_piastres),
        tone: 'success' as const,
        hint: t('hint_units_base', { count: fmtNumber(totals.units_base) }),
      },
      {
        label: t('kpi_low_items'),
        value: fmtNumber(totals.low_stock_count),
        tone: totals.low_stock_count > 0 ? ('warning' as const) : ('default' as const),
        hint: t('hint_at_or_below_min'),
      },
      {
        label: t('kpi_out_items'),
        value: fmtNumber(totals.out_of_stock_count),
        tone: totals.out_of_stock_count > 0 ? ('destructive' as const) : ('default' as const),
      },
    ]
  }, [report, t])

  const expiryBuckets = useMemo(() => {
    if (!report) return []
    const { expiry } = report
    return [
      {
        icon: PackageX,
        label: t('expiry_expired'),
        count: expiry.expired_count,
        tone: 'text-destructive',
        bg: 'bg-destructive/10',
      },
      {
        icon: CalendarClock,
        label: t('expiry_30'),
        count: expiry.expiring_30_count,
        tone: 'text-amber-600 dark:text-amber-400',
        bg: 'bg-amber-500/10',
      },
      {
        icon: CalendarClock,
        label: t('expiry_31_60'),
        count: expiry.expiring_60_count,
        tone: 'text-foreground',
        bg: 'bg-muted',
      },
      {
        icon: CalendarClock,
        label: t('expiry_61_90'),
        count: expiry.expiring_90_count,
        tone: 'text-foreground',
        bg: 'bg-muted',
      },
    ]
  }, [report, t])

  return (
    <RequirePermission anyOf={['reports.inventory']}>
    <div className="space-y-5">
      {/* شريط التحكم — لا يظهر عند الطباعة */}
      <div className="print-hidden flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Button asChild variant="ghost" size="icon">
            <Link href="/reports" aria-label={t('back_to_reports')}>
              <ArrowRight className="h-5 w-5 rtl-flip" />
            </Link>
          </Button>
          <div>
            <h1 className="text-2xl font-bold">{t('inventory_title')}</h1>
            <p className="mt-0.5 text-sm text-muted-foreground">
              {t('inventory_subtitle')}
            </p>
          </div>
        </div>
        <Button onClick={() => window.print()} disabled={loading}>
          <Printer className="h-4 w-4" /> {t('print_pdf')}
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
          title={t('inventory_title')}
          subtitle={t('sheet_inventory_subtitle')}
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
            <h3 className="mb-3 text-sm font-bold">{t('expiry_section')}</h3>
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
                      {t('hint_batches', { count: fmtNumber(bucket.count) })}
                    </p>
                  </div>
                )
              })}
            </div>
            {(report.expiry.expired_value_piastres > 0 || report.expiry.expiring_value_piastres > 0) && (
              <p className="mt-2 text-xs text-muted-foreground">
                {t('expired_value_label')}{' '}
                <span className="font-semibold text-destructive">
                  {formatPiastres(report.expiry.expired_value_piastres)}
                </span>{' '}
                · {t('expiring_value_label')}{' '}
                <span className="font-semibold">{formatPiastres(report.expiry.expiring_value_piastres)}</span>
              </p>
            )}
          </section>

          {/* النواقص */}
          <section className="print-avoid-break">
            <h3 className="mb-3 flex items-center gap-2 text-sm font-bold">
              <AlertTriangle className="h-4 w-4 text-amber-500" />
              {t('low_stock_list')}
            </h3>
            {report.low_stock_items.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-6 text-center text-sm text-muted-foreground">
                {t('no_low_stock_items')}
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('col_item')}</TableHead>
                      <TableHead>{t('col_batch')}</TableHead>
                      <TableHead>{t('col_branch')}</TableHead>
                      <TableHead className="w-[90px]">{t('col_available')}</TableHead>
                      <TableHead className="w-[110px]">{t('col_min')}</TableHead>
                      <TableHead className="w-[90px]">{t('col_status')}</TableHead>
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
                          {fmtNumber(item.quantity)}
                        </TableCell>
                        <TableCell className="tabular-nums text-muted-foreground">
                          {fmtNumber(item.threshold)}
                        </TableCell>
                        <TableCell>
                          <Badge variant={item.quantity <= 0 ? 'destructive' : 'warning'}>
                            {item.quantity <= 0 ? t('status_out') : t('status_low')}
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
              {t('expiry_list')}
            </h3>
            {report.expiring_items.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-6 text-center text-sm text-muted-foreground">
                {t('no_expiring_items')}
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('col_item')}</TableHead>
                      <TableHead>{t('col_batch')}</TableHead>
                      <TableHead className="w-[90px]">{t('col_available')}</TableHead>
                      <TableHead className="w-[130px]">{t('col_expiry_date')}</TableHead>
                      <TableHead className="w-[110px]">{t('col_days_left')}</TableHead>
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
                          {fmtNumber(item.quantity)}
                        </TableCell>
                        <TableCell className="whitespace-nowrap text-xs tabular-nums">
                          {item.extra_date ? formatArabicDate(String(item.extra_date).slice(0, 10)) : '—'}
                        </TableCell>
                        <TableCell>
                          <Badge variant={expiryTone(item.threshold)}>
                            {item.threshold <= 0
                              ? t('batch_expired')
                              : t('days_left', { count: fmtNumber(item.threshold) })}
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
              <h3 className="text-sm font-bold">{t('current_inventory')}</h3>
              {items.length >= 500 && (
                <p className="text-xs text-muted-foreground">{t('first_500')}</p>
              )}
            </div>
            {items.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-8 text-center text-sm text-muted-foreground">
                {t('no_inventory')}
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('col_item')}</TableHead>
                      <TableHead>{t('col_batch')}</TableHead>
                      <TableHead>{t('col_branch')}</TableHead>
                      <TableHead className="w-[90px]">{t('col_available')}</TableHead>
                      <TableHead className="w-[120px]">{t('col_sale_price')}</TableHead>
                      <TableHead className="w-[130px]">{t('col_total_cost')}</TableHead>
                      <TableHead className="w-[120px]">{t('col_expiry')}</TableHead>
                      <TableHead className="w-[90px]">{t('col_status')}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {items.map((item) => {
                      const status = statusBadgeKeys[item.status] ?? statusBadgeKeys.normal
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
                            {fmtNumber(item.quantity)}
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
                            <Badge variant={status.variant}>{t(status.key)}</Badge>
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
