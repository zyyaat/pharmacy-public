'use client'

import { useParams, useRouter } from 'next/navigation'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { ArrowRight, RotateCcw } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type POSReturnItemInput,
  type POSSaleDetail,
  type POSSaleItemRow,
} from '@/lib/api'
import { formatPiastres } from '@/lib/money'
import { extraStrengthLabel } from '@/lib/product'
import {
  baseUnitLabel,
  boxConversionHint,
  formatSaleDate,
  formatSaleTime,
  formatSoldQuantity,
  saleStatusLabel,
  saleStatusVariant,
} from '@/lib/sales'
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Input, LoadingSpinner, Modal, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'

export default function SaleDetailPage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const saleId = params?.id

  const [detail, setDetail] = useState<POSSaleDetail | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [returnOpen, setReturnOpen] = useState(false)
  const [quantities, setQuantities] = useState<Record<string, number>>({})
  const [reason, setReason] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)
  // One idempotency key per return attempt chain: retries reuse it, so a
  // network hiccup can never create a second credit note.
  const idempotencyKey = useRef<string | null>(null)

  const load = useCallback(async () => {
    if (!saleId) return
    setLoading(true)
    setError(null)
    try {
      const response = await pharmacyApi.getPOSSale(saleId)
      setDetail(response.data)
    } catch (err) {
      const message = err instanceof ApiError ? err.message : 'تعذر تحميل الفاتورة'
      setError(message)
    } finally {
      setLoading(false)
    }
  }, [saleId])

  useEffect(() => {
    load()
  }, [load])

  const returnableRows = useMemo(
    () => detail?.items.filter((item) => item.returnable_quantity_base > 0) ?? [],
    [detail],
  )

  const hasSelection = Object.values(quantities).some((value) => value > 0)

  function openReturnModal() {
    setQuantities({})
    setReason('')
    setSubmitError(null)
    setSuccessMessage(null)
    idempotencyKey.current = crypto.randomUUID()
    setReturnOpen(true)
  }

  function setQuantity(item: POSSaleItemRow, value: number) {
    setQuantities((current) => ({
      ...current,
      [item.sale_item_id]: Math.max(0, Math.min(item.returnable_quantity_base, Math.trunc(value) || 0)),
    }))
  }

  function fillAll() {
    const next: Record<string, number> = {}
    for (const item of returnableRows) next[item.sale_item_id] = item.returnable_quantity_base
    setQuantities(next)
  }

  async function submitReturn() {
    if (!detail || !saleId || !hasSelection || submitting) return
    const items: POSReturnItemInput[] = Object.entries(quantities)
      .filter(([, quantity]) => quantity > 0)
      .map(([saleItemId, quantity]) => ({ sale_item_id: saleItemId, quantity }))
    if (items.length === 0) return

    setSubmitting(true)
    setSubmitError(null)
    try {
      const response = await pharmacyApi.createPOSSaleReturn(
        saleId,
        items,
        reason.trim(),
        idempotencyKey.current ?? undefined,
      )
      const refunded = response.data.total_amount_piastres
      setSuccessMessage(
        `تم إنشاء فاتورة الاسترجاع RET-${String(response.data.return_number).padStart(6, '0')} بمبلغ ${formatPiastres(refunded)} — والكميات رجعت للمخزون`,
      )
      idempotencyKey.current = null
      setReturnOpen(false)
      await load()
    } catch (err) {
      if (err instanceof ApiError && err.code === 'return_exceeds_sold') {
        setSubmitError('الكمية المطلوبة أكبر من المتاح للاسترجاع (اتغيرت بعد آخر تحديث) — هتم تحديث الفاتورة')
        await load()
      } else {
        setSubmitError(err instanceof ApiError ? err.message : 'تعذر تنفيذ الاسترجاع')
      }
    } finally {
      setSubmitting(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-16">
        <LoadingSpinner />
      </div>
    )
  }

  if (error || !detail) {
    return (
      <div className="space-y-4">
        <Button variant="ghost" size="sm" onClick={() => router.push('/sales')}>
          <ArrowRight className="h-4 w-4" /> رجوع لسجل البيع
        </Button>
        <Card>
          <CardContent className="p-6 text-sm text-destructive">{error || 'الفاتورة غير موجودة'}</CardContent>
        </Card>
      </div>
    )
  }

  const { sale, items } = detail
  const netAmount = sale.total_amount_piastres - sale.returned_amount_piastres

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => router.push('/sales')} aria-label="رجوع">
            <ArrowRight className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="font-mono text-2xl font-bold" dir="ltr">INV-{String(sale.invoice_number).padStart(6, '0')}</h1>
            <p className="mt-0.5 text-sm text-muted-foreground">
              {formatSaleDate(sale.created_at)} · {formatSaleTime(sale.created_at)}
            </p>
          </div>
          <Badge variant={saleStatusVariant(sale.status)}>{saleStatusLabel(sale.status)}</Badge>
        </div>
        {returnableRows.length > 0 && (
          <Button onClick={openReturnModal}>
            <RotateCcw className="h-4 w-4" /> استرجاع أصناف
          </Button>
        )}
      </div>

      {successMessage && (
        <Card className="border-emerald-500/40 bg-emerald-500/5">
          <CardContent className="flex items-start gap-2 p-4 text-sm text-emerald-700 dark:text-emerald-400">
            <RotateCcw className="mt-0.5 h-4 w-4 shrink-0" />
            {successMessage}
          </CardContent>
        </Card>
      )}

      <div className="grid gap-4 sm:grid-cols-3">
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">إجمالي الفاتورة</p>
            <p className="mt-1 text-xl font-bold">{formatPiastres(sale.total_amount_piastres)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">إجمالي المسترجع</p>
            <p className={`mt-1 text-xl font-bold ${sale.returned_amount_piastres > 0 ? 'text-destructive' : ''}`}>
              {formatPiastres(sale.returned_amount_piastres)}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">الصافي بعد الاسترجاع</p>
            <p className="mt-1 text-xl font-bold">{formatPiastres(netAmount)}</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">أصناف الفاتورة</CardTitle>
        </CardHeader>
        <CardContent className="px-0 pb-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>الصنف</TableHead>
                <TableHead>الدفعة</TableHead>
                <TableHead>الكمية المبيعة</TableHead>
                <TableHead>سعر الوحدة</TableHead>
                <TableHead>الإجمالي</TableHead>
                <TableHead>المسترجع</TableHead>
                <TableHead>متاح للاسترجاع</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((item) => (
                <TableRow key={item.sale_item_id}>
                  <TableCell>
                    <p className="font-medium">
                      {item.product_name}
                      {extraStrengthLabel(item.product_name, item.strength) && (
                        <span className="text-xs font-normal text-muted-foreground"> {extraStrengthLabel(item.product_name, item.strength)}</span>
                      )}
                    </p>
                    {item.generic_name && <p className="text-xs text-muted-foreground">{item.generic_name}</p>}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">{item.batch_number || '—'}</TableCell>
                  <TableCell>{formatSoldQuantity(item.sale_unit, item.packaging_type, item.units_per_box, item.quantity_base)}</TableCell>
                  <TableCell>{formatPiastres(item.unit_price_piastres)}</TableCell>
                  <TableCell className="font-semibold">{formatPiastres(item.amount_piastres)}</TableCell>
                  <TableCell className={item.returned_quantity_base > 0 ? 'font-medium text-destructive' : 'text-muted-foreground'}>
                    {item.returned_quantity_base > 0
                      ? formatSoldQuantity(item.sale_unit, item.packaging_type, item.units_per_box, item.returned_quantity_base)
                      : '—'}
                  </TableCell>
                  <TableCell>
                    {item.returnable_quantity_base > 0
                      ? formatSoldQuantity(item.sale_unit, item.packaging_type, item.units_per_box, item.returnable_quantity_base)
                      : <span className="text-xs text-muted-foreground">لا يوجد</span>}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {sale.returns.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">فواتير الاسترجاع ({sale.returns.length})</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {sale.returns.map((ret) => (
              <div key={ret.id} className="rounded-lg border border-destructive/30 bg-destructive/5 p-3">
                <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
                  <RotateCcw className="h-4 w-4 text-destructive" />
                  <span className="font-mono font-semibold text-destructive" dir="ltr">
                    RET-{String(ret.return_number).padStart(6, '0')}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {formatSaleDate(ret.created_at)} · {formatSaleTime(ret.created_at)}
                  </span>
                  {typeof ret.quantity_base === 'number' && (
                    <span className="text-xs text-muted-foreground">{ret.quantity_base} وحدات مرتجعة</span>
                  )}
                  <span className="ms-auto font-bold text-destructive">
                    -{formatPiastres(ret.total_amount_piastres)}
                  </span>
                </div>
                {ret.reason && <p className="mt-1 text-xs text-muted-foreground">السبب: {ret.reason}</p>}
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <Modal isOpen={returnOpen} onClose={submitting ? () => {} : () => setReturnOpen(false)}>
        <div className="space-y-4">
          <div>
            <h2 className="text-lg font-bold">استرجاع أصناف من الفاتورة</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              حدد الكمية المرتجعة من كل صنف (بعدد الشرائط). اتركها صفر إذا لم ترجع شيئاً منه.
            </p>
          </div>

          {returnableRows.length > 1 && (
            <Button variant="secondary" size="sm" onClick={fillAll} type="button">
              تعبئة كل الكميات المتاحة (استرجاع الفاتورة بالكامل)
            </Button>
          )}

          <div className="max-h-[45vh] space-y-3 overflow-y-auto pe-1">
            {returnableRows.map((item) => {
              const hint = boxConversionHint(item.packaging_type, item.units_per_box)
              const value = quantities[item.sale_item_id] ?? 0
              return (
                <div key={item.sale_item_id} className="rounded-lg border border-border p-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <p className="text-sm font-semibold">
                        {item.product_name}
                        {extraStrengthLabel(item.product_name, item.strength) && (
                          <span className="text-xs font-normal text-muted-foreground"> {extraStrengthLabel(item.product_name, item.strength)}</span>
                        )}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        مبيع: {formatSoldQuantity(item.sale_unit, item.packaging_type, item.units_per_box, item.quantity_base)}
                        {hint ? ` · ${hint}` : ''}
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      <Input
                        type="number"
                        inputMode="numeric"
                        min={0}
                        max={item.returnable_quantity_base}
                        value={value === 0 ? '' : value}
                        placeholder="0"
                        onChange={(event) => setQuantity(item, Number(event.target.value))}
                        className="w-24 text-center"
                        aria-label={`كمية الاسترجاع من ${item.product_name}`}
                      />
                      <span className="text-xs text-muted-foreground">{baseUnitLabel(item.packaging_type)}</span>
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={() => setQuantity(item, item.returnable_quantity_base)}
                      >
                        الكل
                      </Button>
                    </div>
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">
                    متاح: {item.returnable_quantity_base} · الإجمالي المبيعة لهذا السطر: {formatPiastres(item.amount_piastres)}
                  </p>
                </div>
              )
            })}
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium" htmlFor="return-reason">سبب الاسترجاع (اختياري)</label>
            <Input
              id="return-reason"
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              placeholder="مثال: المنتج لم يتناسب مع حالة المريض"
              maxLength={500}
            />
          </div>

          {submitError && <p className="text-sm text-destructive">{submitError}</p>}

          <div className="flex justify-end gap-2 border-t border-border pt-3">
            <Button variant="ghost" onClick={() => setReturnOpen(false)} disabled={submitting}>
              إلغاء
            </Button>
            <Button onClick={submitReturn} disabled={!hasSelection || submitting}>
              {submitting ? <LoadingSpinner /> : 'تأكيد الاسترجاع'}
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}
