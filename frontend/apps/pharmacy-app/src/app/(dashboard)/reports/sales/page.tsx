'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowRight, Printer, ReceiptText } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type PharmacyContext,
  type POSSaleSummary,
  type SalesReport,
} from '@/lib/api'
import { formatPiastres } from '@/lib/money'
import { saleStatusLabel, saleStatusVariant, formatSaleDate, formatSaleTime } from '@/lib/sales'
import { dayLabel, presetRange, type PeriodPreset } from '@/lib/reports'
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
import {
  BarChart,
  KpiCards,
  PeriodPicker,
  ReportSheet,
  useReportContext,
} from '@/components/reports'

const INVOICES_LIMIT = 100

export default function SalesReportPage() {
  const t = useT('reports')
  const { generatedAt, refreshTimestamp } = useReportContext()
  const [preset, setPreset] = useState<PeriodPreset>('last30')
  const [fromInput, setFromInput] = useState('')
  const [toInput, setToInput] = useState('')
  const [applied, setApplied] = useState<{ from: string; to: string } | null>(null)
  const [report, setReport] = useState<SalesReport | null>(null)
  const [invoices, setInvoices] = useState<POSSaleSummary[]>([])
  const [invoicesTotal, setInvoicesTotal] = useState(0)
  const [context, setContext] = useState<PharmacyContext | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(
    async (range: { from: string; to: string }) => {
      setLoading(true)
      setError(null)
      try {
        const [reportResponse, invoicesResponse] = await Promise.all([
          pharmacyApi.getSalesReport(range.from, range.to),
          pharmacyApi.listPOSSales(INVOICES_LIMIT, 0, '', range),
        ])
        setReport(reportResponse.data)
        setInvoices(invoicesResponse.data.sales)
        setInvoicesTotal(invoicesResponse.data.total)
        refreshTimestamp()
      } catch (cause) {
        setError(cause instanceof ApiError ? cause.message : t('error_load_sales'))
      } finally {
        setLoading(false)
      }
    },
    [refreshTimestamp, t],
  )

  // أول تحميل: آخر 30 يوم + بيانات الترويسة
  useEffect(() => {
    const initial = presetRange('last30')!
    setFromInput(initial.from)
    setToInput(initial.to)
    setApplied(initial)
    load(initial)
  }, [load])

  useEffect(() => {
    let active = true
    pharmacyApi
      .getContext()
      .then((value) => {
        if (active) setContext(value)
      })
      .catch(() => {})
    return () => {
      active = false
    }
  }, [])

  function changePreset(next: PeriodPreset) {
    setPreset(next)
    if (next === 'custom') return
    const range = presetRange(next)
    if (!range) return
    setFromInput(range.from)
    setToInput(range.to)
    setApplied(range)
    load(range)
  }

  function applyCustom() {
    if (!fromInput || !toInput) return
    const range = { from: fromInput, to: toInput }
    setApplied(range)
    load(range)
  }

  const kpis = useMemo(() => {
    if (!report) return []
    const { sales } = report
    return [
      {
        label: t('kpi_gross_sales'),
        value: formatPiastres(sales.gross_piastres),
        hint: t('hint_invoices', { count: fmtNumber(sales.invoices_count) }),
      },
      {
        label: t('kpi_returns'),
        value: formatPiastres(sales.returned_piastres),
        hint: t('hint_return_notes', { count: fmtNumber(sales.returns_count) }),
        tone: sales.returned_piastres > 0 ? ('destructive' as const) : ('default' as const),
      },
      {
        label: t('kpi_net_sales'),
        value: formatPiastres(sales.net_piastres),
        tone: 'success' as const,
      },
      {
        label: t('kpi_units_sold'),
        value: fmtNumber(sales.units_base),
        hint: t('hint_base_units'),
      },
      {
        label: t('kpi_avg_invoice'),
        value: formatPiastres(sales.avg_invoice_piastres),
        hint:
          sales.invoices_count > 0
            ? t('hint_avg_invoice', { count: fmtNumber(Math.round(sales.units_base / sales.invoices_count)) })
            : undefined,
      },
    ]
  }, [report, t])

  const chartPoints = useMemo(
    () =>
      (report?.daily ?? []).map((point) => ({
        label: dayLabel(point.day),
        value: Math.max(0, point.net_piastres),
        title: t('chart_point_title', {
          date: formatSaleDate(point.day),
          value: formatPiastres(point.net_piastres),
        }),
      })),
    [report, t],
  )

  return (
    <RequirePermission anyOf={['reports.sales']}>
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
            <h1 className="text-2xl font-bold">{t('sales_title')}</h1>
            <p className="mt-0.5 text-sm text-muted-foreground">
              {t('sales_subtitle')}
            </p>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <PeriodPicker
            preset={preset}
            onPresetChange={changePreset}
            from={fromInput}
            to={toInput}
            onFromChange={setFromInput}
            onToChange={setToInput}
            onApply={applyCustom}
            loading={loading}
          />
          <Button onClick={() => window.print()} disabled={loading}>
            <Printer className="h-4 w-4" /> {t('print_pdf')}
          </Button>
        </div>
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
          title={t('sales_title')}
          subtitle={t('sheet_sales_subtitle')}
          icon={<ReceiptText className="h-5 w-5 text-primary" />}
          period={report.period}
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
          {kpis.length > 0 && <KpiCards items={kpis} columns={5} />}

          {/* المبيعات اليومية */}
          <section className="print-avoid-break">
            <h3 className="mb-3 text-sm font-bold">{t('daily_net_sales')}</h3>
            <BarChart
              points={chartPoints}
              summary={t('chart_summary_days', { count: fmtNumber(report.daily.length) })}
            />
          </section>

          {/* المنتجات الأكثر بيعاً */}
          <section className="print-avoid-break">
            <h3 className="mb-3 text-sm font-bold">{t('top_products')}</h3>
            {report.top_products.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-8 text-center text-sm text-muted-foreground">
                {t('no_sales_in_period')}
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-[50px]">#</TableHead>
                      <TableHead>{t('col_item')}</TableHead>
                      <TableHead className="w-[120px]">{t('col_quantity')}</TableHead>
                      <TableHead className="w-[140px]">{t('col_revenue')}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {report.top_products.map((product, index) => (
                      <TableRow key={product.product_id}>
                        <TableCell className="text-xs tabular-nums text-muted-foreground">
                          {fmtNumber(index + 1)}
                        </TableCell>
                        <TableCell>
                          <p className="font-medium">{product.name}</p>
                          {product.generic_name && (
                            <p className="text-xs text-muted-foreground">{product.generic_name}</p>
                          )}
                        </TableCell>
                        <TableCell className="tabular-nums">
                          {fmtNumber(product.quantity_base)}
                        </TableCell>
                        <TableCell className="font-semibold tabular-nums">
                          {formatPiastres(product.amount_piastres)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </section>

          {/* فواتير الفترة */}
          <section>
            <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
              <h3 className="text-sm font-bold">{t('period_invoices')}</h3>
              <p className="text-xs text-muted-foreground">
                {invoicesTotal > INVOICES_LIMIT
                  ? t('invoices_showing', { limit: fmtNumber(INVOICES_LIMIT), total: fmtNumber(invoicesTotal) })
                  : t('invoices_count', { count: fmtNumber(invoicesTotal) })}
              </p>
            </div>
            {invoices.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-8 text-center text-sm text-muted-foreground">
                {t('no_invoices_in_period')}
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('col_invoice')}</TableHead>
                      <TableHead>{t('col_date')}</TableHead>
                      <TableHead>{t('col_status')}</TableHead>
                      <TableHead className="w-[90px]">{t('col_items')}</TableHead>
                      <TableHead className="w-[110px]">{t('col_units')}</TableHead>
                      <TableHead className="w-[120px]">{t('col_total')}</TableHead>
                      <TableHead className="w-[120px]">{t('col_returned')}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {invoices.map((sale) => (
                      <TableRow key={sale.id}>
                        <TableCell className="font-mono text-xs font-bold">
                          <span dir="ltr" className="inline-block">
                            INV-{String(sale.invoice_number).padStart(6, '0')}
                          </span>
                        </TableCell>
                        <TableCell className="whitespace-nowrap">
                          <span className="flex flex-col leading-tight">
                            <span className="text-xs text-foreground/80">
                              {formatSaleDate(sale.created_at)}
                            </span>
                            <span className="text-[11px] tabular-nums text-muted-foreground">
                              {formatSaleTime(sale.created_at)}
                            </span>
                          </span>
                        </TableCell>
                        <TableCell>
                          <Badge variant={saleStatusVariant(sale.status)}>
                            {saleStatusLabel(sale.status)}
                          </Badge>
                        </TableCell>
                        <TableCell className="tabular-nums">
                          {fmtNumber(sale.products_count)}
                        </TableCell>
                        <TableCell className="tabular-nums">
                          {fmtNumber(sale.total_quantity_base)}
                        </TableCell>
                        <TableCell className="font-semibold tabular-nums">
                          {formatPiastres(sale.total_amount_piastres)}
                        </TableCell>
                        <TableCell
                          className={`tabular-nums ${
                            sale.returned_amount_piastres > 0
                              ? 'font-medium text-destructive'
                              : 'text-muted-foreground'
                          }`}
                        >
                          {sale.returned_amount_piastres > 0
                            ? formatPiastres(sale.returned_amount_piastres)
                            : '—'}
                        </TableCell>
                      </TableRow>
                    ))}
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
