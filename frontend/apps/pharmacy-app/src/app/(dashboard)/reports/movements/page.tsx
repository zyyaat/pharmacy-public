'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowDownLeft, ArrowRight, ArrowUpRight, ArrowLeftRight, Printer, RotateCcw } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type MovementsReport,
  type PharmacyContext,
  type StockMovementRow,
  type StockMovementType,
} from '@/lib/api'
import {
  formatMovementQuantity,
  movementTypeLabel,
  movementTypeVariant,
} from '@/lib/movements'
import { presetRange, type PeriodPreset } from '@/lib/reports'
import {
  Badge,
  Button,
  Card,
  CardContent,
  Input,
  LoadingSpinner,
  Select,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import { RequirePermission } from '@/components/permissions/gate'
import {
  KpiCards,
  PeriodPicker,
  ReportSheet,
  useReportContext,
} from '@/components/reports'

const DETAILS_LIMIT = 200

const movementTypeOptions: Array<{ value: StockMovementType | 'all'; label: string }> = [
  { value: 'all', label: 'كل الأنواع' },
  { value: 'sale', label: 'بيع' },
  { value: 'return_from_customer', label: 'استرجاع من عميل' },
  { value: 'purchase', label: 'شراء' },
  { value: 'return_to_supplier', label: 'مرتجع للمورد' },
  { value: 'adjustment', label: 'تسوية مخزون' },
  { value: 'transfer_in', label: 'تحويل وارد' },
  { value: 'transfer_out', label: 'تحويل صادر' },
  { value: 'expiry_writeoff', label: 'إعدام منتهي الصلاحية' },
  { value: 'damage_writeoff', label: 'إعدام تالف' },
  { value: 'theft_loss', label: 'فقد/سرقة' },
  { value: 'production_input', label: 'استهلاك تصنيع' },
  { value: 'production_output', label: 'إنتاج' },
]

const directionOptions = [
  { value: 'all', label: 'داخل وخارج' },
  { value: 'in', label: 'داخل فقط (+)' },
  { value: 'out', label: 'خارج فقط (−)' },
]

export default function MovementsReportPage() {
  const { generatedAt, refreshTimestamp } = useReportContext()
  const [preset, setPreset] = useState<PeriodPreset>('last30')
  const [fromInput, setFromInput] = useState('')
  const [toInput, setToInput] = useState('')
  const [applied, setApplied] = useState<{ from: string; to: string } | null>(null)
  const [typeInput, setTypeInput] = useState<StockMovementType | 'all'>('all')
  const [directionInput, setDirectionInput] = useState<'all' | 'in' | 'out'>('all')

  const [report, setReport] = useState<MovementsReport | null>(null)
  const [details, setDetails] = useState<StockMovementRow[]>([])
  const [detailsTotal, setDetailsTotal] = useState(0)
  const [context, setContext] = useState<PharmacyContext | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(
    async (range: { from: string; to: string }, type: StockMovementType | 'all', direction: 'all' | 'in' | 'out') => {
      setLoading(true)
      setError(null)
      try {
        const [reportResponse, detailsResponse] = await Promise.all([
          pharmacyApi.getMovementsReport(range.from, range.to),
          pharmacyApi.listStockMovements(
            {
              from: range.from,
              to: range.to,
              type: type === 'all' ? '' : type,
              direction: direction === 'all' ? '' : direction,
            },
            DETAILS_LIMIT,
            0,
          ),
        ])
        setReport(reportResponse.data)
        setDetails(detailsResponse.data.movements)
        setDetailsTotal(detailsResponse.data.total)
        refreshTimestamp()
      } catch (cause) {
        setError(cause instanceof ApiError ? cause.message : 'تعذر تحميل تقرير حركات المخزون')
      } finally {
        setLoading(false)
      }
    },
    [refreshTimestamp],
  )

  useEffect(() => {
    const initial = presetRange('last30')!
    setFromInput(initial.from)
    setToInput(initial.to)
    setApplied(initial)
    load(initial, 'all', 'all')
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
    load(range, typeInput, directionInput)
  }

  function applyCustom() {
    if (!fromInput || !toInput || !applied) return
    const range = { from: fromInput, to: toInput }
    setApplied(range)
    load(range, typeInput, directionInput)
  }

  function applyDetailFilters() {
    if (!applied) return
    load(applied, typeInput, directionInput)
  }

  function resetDetailFilters() {
    setTypeInput('all')
    setDirectionInput('all')
    if (applied) load(applied, 'all', 'all')
  }

  const kpis = useMemo(() => {
    if (!report) return []
    const { totals } = report
    const net = totals.quantity_in - totals.quantity_out
    return [
      {
        label: 'عدد الحركات',
        value: totals.transactions.toLocaleString('ar-EG'),
        hint: 'حركة مخزون ضمن الفترة',
      },
      {
        label: 'إجمالي الوارد',
        value: `+${totals.quantity_in.toLocaleString('ar-EG')}`,
        tone: 'success' as const,
        hint: 'وحدة أساسية',
      },
      {
        label: 'إجمالي الصادر',
        value: `−${totals.quantity_out.toLocaleString('ar-EG')}`,
        tone: 'destructive' as const,
        hint: 'وحدة أساسية',
      },
      {
        label: 'صافي التغير',
        value: `${net >= 0 ? '+' : '−'}${Math.abs(net).toLocaleString('ar-EG')}`,
        tone: net >= 0 ? ('success' as const) : ('destructive' as const),
      },
    ]
  }, [report])

  return (
    <RequirePermission anyOf={['reports.movements']}>
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
            <h1 className="text-2xl font-bold">تقرير حركات المخزون</h1>
            <p className="mt-0.5 text-sm text-muted-foreground">
              ملخص الدخول والخروج حسب النوع مع تفاصيل الحركات
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
          title="تقرير حركات المخزون"
          subtitle="كل حركة دخول وخروج خلال الفترة"
          icon={<ArrowLeftRight className="h-5 w-5 text-primary" />}
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
          {kpis.length > 0 && <KpiCards items={kpis} />}

          {/* الملخص حسب النوع */}
          <section className="print-avoid-break">
            <h3 className="mb-3 text-sm font-bold">الملخص حسب نوع الحركة</h3>
            {report.by_type.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-8 text-center text-sm text-muted-foreground">
                لا توجد حركات في هذه الفترة
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>نوع الحركة</TableHead>
                      <TableHead className="w-[110px]">عدد الحركات</TableHead>
                      <TableHead className="w-[130px]">وارد</TableHead>
                      <TableHead className="w-[130px]">صادر</TableHead>
                      <TableHead className="w-[130px]">الصافي</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {report.by_type.map((row) => {
                      const net = row.quantity_in - row.quantity_out
                      return (
                        <TableRow key={row.movement_type}>
                          <TableCell>
                            <Badge variant={movementTypeVariant(row.movement_type)}>
                              {movementTypeLabel(row.movement_type)}
                            </Badge>
                          </TableCell>
                          <TableCell className="tabular-nums">
                            {row.transactions.toLocaleString('ar-EG')}
                          </TableCell>
                          <TableCell className="font-semibold tabular-nums text-emerald-600 dark:text-emerald-400">
                            {row.quantity_in > 0 ? `+${row.quantity_in.toLocaleString('ar-EG')}` : '—'}
                          </TableCell>
                          <TableCell className="font-semibold tabular-nums text-destructive">
                            {row.quantity_out > 0 ? `−${row.quantity_out.toLocaleString('ar-EG')}` : '—'}
                          </TableCell>
                          <TableCell className="tabular-nums">
                            {net >= 0 ? `+${net.toLocaleString('ar-EG')}` : `−${Math.abs(net).toLocaleString('ar-EG')}`}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>
            )}
            <p className="mt-2 text-xs text-muted-foreground">
              الكميات بالوحدة الأساسية (شريط للأدوية المعبأة بشرائط، عبوة لغير ذلك).
            </p>
          </section>

          {/* تفاصيل الحركات */}
          <section>
            {/* فلاتر التفاصيل — لا تُطبع */}
            <div className="print-hidden mb-3 flex flex-wrap items-center gap-2">
              <h3 className="text-sm font-bold">تفاصيل الحركات</h3>
              <div className="ms-auto flex flex-wrap items-center gap-2">
                <div className="w-[190px]">
                  <Select
                    value={typeInput}
                    onValueChange={(value) => setTypeInput(value as StockMovementType | 'all')}
                    options={movementTypeOptions}
                    aria-label="نوع الحركة"
                  />
                </div>
                <div className="w-[160px]">
                  <Select
                    value={directionInput}
                    onValueChange={(value) => setDirectionInput(value as 'all' | 'in' | 'out')}
                    options={directionOptions}
                    aria-label="اتجاه الحركة"
                  />
                </div>
                <Button type="button" variant="secondary" size="sm" onClick={applyDetailFilters} disabled={loading}>
                  تطبيق
                </Button>
                {(typeInput !== 'all' || directionInput !== 'all') && (
                  <Button type="button" variant="ghost" size="sm" onClick={resetDetailFilters}>
                    <RotateCcw className="h-4 w-4" /> مسح
                  </Button>
                )}
              </div>
            </div>

            <p className="print-hidden mb-3 text-xs text-muted-foreground">
              {detailsTotal > DETAILS_LIMIT
                ? `تُعرض أحدث ${DETAILS_LIMIT.toLocaleString('ar-EG')} من ${detailsTotal.toLocaleString('ar-EG')} حركة`
                : `${detailsTotal.toLocaleString('ar-EG')} حركة`}
            </p>

            {details.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border py-8 text-center text-sm text-muted-foreground">
                لا توجد حركات مطابقة
              </p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-[110px]">التاريخ</TableHead>
                      <TableHead>الدواء</TableHead>
                      <TableHead>التشغيلة</TableHead>
                      <TableHead>النوع</TableHead>
                      <TableHead className="w-[120px]">الكمية</TableHead>
                      <TableHead className="w-[100px]">الرصيد بعدها</TableHead>
                      <TableHead>بواسطة</TableHead>
                      <TableHead>الفرع</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {details.map((movement) => {
                      const incoming = movement.quantity >= 0
                      return (
                        <TableRow key={movement.id}>
                          <TableCell className="whitespace-nowrap">
                            <span className="flex flex-col leading-tight">
                              <span className="text-xs text-foreground/80">
                                {new Date(movement.created_at).toLocaleDateString('ar-EG', {
                                  day: 'numeric',
                                  month: 'short',
                                  year: 'numeric',
                                })}
                              </span>
                              <span className="text-[11px] tabular-nums text-muted-foreground">
                                {new Date(movement.created_at).toLocaleTimeString('ar-EG', {
                                  hour: '2-digit',
                                  minute: '2-digit',
                                })}
                              </span>
                            </span>
                          </TableCell>
                          <TableCell className="max-w-[260px]">
                            <p className="truncate font-medium" title={movement.product_name}>
                              {movement.product_name}
                            </p>
                            {(movement.reason || movement.notes) && (
                              <p
                                className="truncate text-xs text-muted-foreground"
                                title={movement.reason || movement.notes || ''}
                              >
                                {movement.reason || movement.notes}
                              </p>
                            )}
                          </TableCell>
                          <TableCell className="font-mono text-xs">
                            {movement.batch_number ? (
                              <span dir="ltr" className="inline-block">
                                {movement.batch_number}
                              </span>
                            ) : (
                              '—'
                            )}
                          </TableCell>
                          <TableCell>
                            <Badge variant={movementTypeVariant(movement.movement_type)}>
                              {movementTypeLabel(movement.movement_type)}
                            </Badge>
                          </TableCell>
                          <TableCell className="whitespace-nowrap">
                            <span
                              className={`inline-flex items-center gap-1 font-bold tabular-nums ${
                                incoming ? 'text-emerald-600' : 'text-destructive'
                              }`}
                            >
                              {incoming ? (
                                <ArrowDownLeft className="h-4 w-4" />
                              ) : (
                                <ArrowUpRight className="h-4 w-4" />
                              )}
                              {incoming ? '+' : '−'}
                              {formatMovementQuantity(movement.quantity, movement.unit)}
                            </span>
                          </TableCell>
                          <TableCell className="whitespace-nowrap text-xs tabular-nums">
                            {movement.quantity_after != null
                              ? formatMovementQuantity(movement.quantity_after, movement.unit)
                              : '—'}
                          </TableCell>
                          <TableCell className="text-xs">{movement.actor_name || '—'}</TableCell>
                          <TableCell className="text-xs">{movement.branch_name || '—'}</TableCell>
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
