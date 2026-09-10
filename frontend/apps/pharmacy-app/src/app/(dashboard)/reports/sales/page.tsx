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
        setError(cause instanceof ApiError ? cause.message : 'تعذر تحميل تقرير المبيعات')
      } finally {
        setLoading(false)
      }
    },
    [refreshTimestamp],
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
        label: 'إجمالي المبيعات',
        value: formatPiastres(sales.gross_piastres),
        hint: `${sales.invoices_count.toLocaleString('ar-EG-u-nu-latn')} فاتورة`,
      },
      {
        label: 'المرتجعات',
        value: formatPiastres(sales.returned_piastres),
        hint: `${sales.returns_count.toLocaleString('ar-EG-u-nu-latn')} إشعار مرتجع`,
        tone: sales.returned_piastres > 0 ? ('destructive' as const) : ('default' as const),
      },
      {
        label: 'صافي المبيعات',
        value: formatPiastres(sales.net_piastres),
        tone: 'success' as const,
      },
      {
        label: 'الوحدات المبيعة',
        value: sales.units_base.toLocaleString('ar-EG-u-nu-latn'),
        hint: 'وحدة أساسية (شريط/عبوة)',
      },
      {
        label: 'متوسط الفاتورة',
        value: formatPiastres(sales.avg_invoice_piastres),
        hint:
          sales.invoices_count > 0
            ? `كل فاتورة ${Math.round(sales.units_base / sales.invoices_count).toLocaleString('ar-EG-u-nu-latn')} وحدة تقريباً`
            : undefined,
      },
    ]
  }, [report])

  const chartPoints = useMemo(
    () =>
      (report?.daily ?? []).map((point) => ({
        label: dayLabel(point.day),
        value: Math.max(0, point.net_piastres),
        title: `${formatSaleDate(point.day)} — صافي ${formatPiastres(point.net_piastres)}`,
      })),
    [report],
  )

  return (
    <RequirePermission anyOf={['reports.sales']}>
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
            <h1 className="text-2xl font-bold">تقرير المبيعات</h1>
            <p className="mt-0.5 text-sm text-muted-foreground">
              مؤشرات البيع والمرتجعات خلال الفترة المختارة
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
            <Printer className="h-4 w-4" /> طباعة PDF
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
          title="تقرير المبيعات"
          subtitle="ملخص أداء البيع خلال الفترة"
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
            <h3 className="mb-3 text-sm font-bold">المبيعات اليومية (الصافي)</h3>
            <BarChart
              points={chartPoints}
              summary={`${report.daily.length.toLocaleString('ar-EG-u-nu-latn')} يوم ضمن الفترة`}
            />
          </section>

          {/* المنتجات الأكثر بيعاً */}
          <section className="print-avoid-break">
            <h3 className="mb-3 text-sm font-bold">المنتجات الأكثر بيعاً</h3>
            {report.top_products.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-8 text-center text-sm text-muted-foreground">
                لا توجد مبيعات في هذه الفترة
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-[50px]">#</TableHead>
                      <TableHead>الصنف</TableHead>
                      <TableHead className="w-[120px]">الكمية</TableHead>
                      <TableHead className="w-[140px]">الإيراد</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {report.top_products.map((product, index) => (
                      <TableRow key={product.product_id}>
                        <TableCell className="text-xs tabular-nums text-muted-foreground">
                          {(index + 1).toLocaleString('ar-EG-u-nu-latn')}
                        </TableCell>
                        <TableCell>
                          <p className="font-medium">{product.name}</p>
                          {product.generic_name && (
                            <p className="text-xs text-muted-foreground">{product.generic_name}</p>
                          )}
                        </TableCell>
                        <TableCell className="tabular-nums">
                          {product.quantity_base.toLocaleString('ar-EG-u-nu-latn')}
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
              <h3 className="text-sm font-bold">فواتير الفترة</h3>
              <p className="text-xs text-muted-foreground">
                {invoicesTotal > INVOICES_LIMIT
                  ? `تُعرض أحدث ${INVOICES_LIMIT.toLocaleString('ar-EG-u-nu-latn')} من ${invoicesTotal.toLocaleString('ar-EG-u-nu-latn')} فاتورة`
                  : `${invoicesTotal.toLocaleString('ar-EG-u-nu-latn')} فاتورة`}
              </p>
            </div>
            {invoices.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-8 text-center text-sm text-muted-foreground">
                لا توجد فواتير في هذه الفترة
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>الفاتورة</TableHead>
                      <TableHead>التاريخ</TableHead>
                      <TableHead>الحالة</TableHead>
                      <TableHead className="w-[90px]">الأصناف</TableHead>
                      <TableHead className="w-[110px]">الوحدات</TableHead>
                      <TableHead className="w-[120px]">الإجمالي</TableHead>
                      <TableHead className="w-[120px]">المسترجع</TableHead>
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
                          {sale.products_count.toLocaleString('ar-EG-u-nu-latn')}
                        </TableCell>
                        <TableCell className="tabular-nums">
                          {sale.total_quantity_base.toLocaleString('ar-EG-u-nu-latn')}
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
