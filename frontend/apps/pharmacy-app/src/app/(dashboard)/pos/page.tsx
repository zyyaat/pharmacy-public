'use client'

import { useMemo, useRef, useState } from 'react'
import { Search, Minus, Plus, Printer, ReceiptText, Trash2 } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type POSProduct,
  type POSSaleItem,
} from '@/lib/api'
import { formatPiastres, stripPricePiastres } from '@/lib/money'
import { Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Select } from '@/components/ui'
import ProductSearch, { type AddSource } from '@/components/pos/product-search'
import { useReceiptSettings } from '@/hooks/useReceiptSettings'
import { usePharmacyContext } from '@/hooks/usePharmacyContext'
import ReceiptPrinter, { type ReceiptPrintJob } from '@/components/pos/receipt-printer'
import { saleDetailToReceipt } from '@/components/pos/receipt-template'

type CartLine = {
  product: POSProduct
  unitChoice: 'box' | number
  quantity: number
}

function unitLabel(line: CartLine) {
  if (line.unitChoice === 'box') return 'علبة كاملة'
  const total = line.quantity * line.unitChoice
  if (total === 1) return 'شريط واحد'
  if (total === 2) return 'شريطان'
  return `${total} شرائط`
}

/** Revenue of one line, exact in integer piastres. */
function lineTotalPiastres(line: CartLine): number {
  if (line.unitChoice === 'box') {
    return line.product.selling_price_piastres * line.quantity
  }
  return stripPricePiastres(line.product) * line.unitChoice * line.quantity
}

export default function POSPage() {
  const [cart, setCart] = useState<CartLine[]>([])
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  // One idempotency key per invoice attempt chain: retries of the same
  // checkout reuse it, so a network hiccup can never create a second sale.
  const idempotencyKey = useRef<string | null>(null)
  // إعدادات الطباعة + بيانات الصيدلية لرأس الإيصال
  const { settings: printSettings } = useReceiptSettings()
  const { context } = usePharmacyContext()
  const [printJob, setPrintJob] = useState<ReceiptPrintJob | null>(null)
  const [printBusy, setPrintBusy] = useState(false)
  const lastSaleId = useRef<string | null>(null)

  /** إضافة منتج للفاتورة — من القائمة أو من الباركود (التام أو المصحح) */
  function addProductToCart(product: POSProduct, _source: AddSource) {
    setCart((current) => {
      const existing = current.find((line) => line.product.id === product.id && line.unitChoice === 'box')
      if (existing) {
        return current.map((line) => line === existing ? { ...line, quantity: line.quantity + 1 } : line)
      }
      return [...current, { product, unitChoice: 'box', quantity: 1 }]
    })
  }

  const total = useMemo(
    () => cart.reduce((sum, line) => sum + lineTotalPiastres(line), 0),
    [cart],
  )

  function updateLine(index: number, change: Partial<CartLine>) {
    setCart((current) => current.map((line, lineIndex) => lineIndex === index ? { ...line, ...change } : line))
  }

  function resetIdempotency() {
    idempotencyKey.current = null
  }

  async function checkout() {
    if (cart.length === 0 || checkoutLoading) return
    setCheckoutLoading(true)
    setError(null)
    setMessage(null)
    if (!idempotencyKey.current && typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
      idempotencyKey.current = crypto.randomUUID()
    }
    const items: POSSaleItem[] = cart.map((line) => {
      const isBox = line.unitChoice === 'box'
      // The frontend is a VIEW only: it sends product + unit + quantity.
      // The backend re-reads the authoritative prices and computes the
      // invoice; the displayed total below comes from the backend response.
      return {
        pharmacy_product_id: line.product.id,
        sale_unit: isBox ? 'box' : 'strip',
        quantity: isBox ? line.quantity : line.quantity * (line.unitChoice as number),
      }
    })
    try {
      const response = await pharmacyApi.createPOSSale(items, idempotencyKey.current || undefined)
      lastSaleId.current = response.data.sale_id
      setMessage(`تم حفظ الفاتورة بنجاح. الإجمالي ${formatPiastres(response.data.total_amount_piastres)}`)
      setCart([])
      resetIdempotency()
      // الطباعة التلقائية: تُجهّز بعد نجاح الحفظ مباشرة — وأي فشل فيها لا يمس الفاتورة
      if (printSettings.print_mode === 'auto') {
        void prepareReceiptPrint(response.data.sale_id)
      }
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : 'تعذر إتمام البيع')
    } finally {
      setCheckoutLoading(false)
    }
  }

  /** جلب تفاصيل الفاتورة وتركيب الإيصال ثم فتح نافذة الطباعة — كل شيء من المتصفح */
  async function prepareReceiptPrint(saleId: string) {
    setPrintBusy(true)
    try {
      const detail = await pharmacyApi.getPOSSale(saleId)
      setPrintJob({
        data: saleDetailToReceipt(detail.data),
        pharmacy: {
          name: context?.pharmacy.name ?? 'صيدلية',
          city: context?.pharmacy.city,
          address: context?.pharmacy.address,
          phone: context?.pharmacy.phone,
        },
        cashierName: context?.user.display_name || [context?.user.first_name, context?.user.last_name].filter(Boolean).join(' '),
        jobId: saleId,
      })
    } catch {
      setError('تم حفظ الفاتورة لكن تعذر تجهيز الطباعة — اضغط «طباعة الفاتورة» لإعادة المحاولة')
    } finally {
      setPrintBusy(false)
    }
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold">نقطة البيع</h1>
        <p className="mt-2 text-sm text-muted-foreground">امسح الباركود أو اكتب اسم الدواء — البحث يصحح الأخطاء ويقترح المنتجات المشابهة.</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Search className="h-5 w-5 text-primary" />إضافة منتج للفاتورة</CardTitle>
          <CardDescription>القائمة المنسدلة تقترح المنتجات أثناء الكتابة، وEnter بعد الفحص يضيف المنتج مباشرة — وإن أخطأ الماسح يصححه تلقائياً.</CardDescription>
        </CardHeader>
        <CardContent>
          <ProductSearch
            onAddProduct={addProductToCart}
            onMessage={setMessage}
            onError={setError}
            autoFocus
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2"><ReceiptText className="h-5 w-5 text-primary" />الفاتورة الحالية</CardTitle>
            <CardDescription>{cart.length ? `${cart.length} أصناف` : 'لم تتم إضافة أصناف بعد'}</CardDescription>
          </div>
          {cart.length > 0 && <Button variant="ghost" onClick={() => { setCart([]); resetIdempotency() }}>تفريغ الفاتورة</Button>}
        </CardHeader>
        <CardContent>
          {cart.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border py-14 text-center text-muted-foreground">ابدأ بالفحص أو بالبحث بالاسم</div>
          ) : (
            <div className="space-y-3">
              {cart.map((line, index) => {
                const lineTotal = lineTotalPiastres(line)
                const maxBase = line.product.stock
                const requestedBase = line.quantity * (line.unitChoice === 'box' ? line.product.units_per_box : line.unitChoice)
                return (
                  <div key={`${line.product.id}-${index}`} className="grid gap-4 rounded-xl border border-border p-4 md:grid-cols-[1fr_180px_130px_120px_40px] md:items-center">
                    <div>
                      <p className="font-semibold">{line.product.name}</p>
                      <p className="mt-1 text-xs text-muted-foreground">{line.product.barcode} · المتاح {line.product.packaging_type === 'BOX_STRIP' ? `${Math.floor(maxBase / line.product.units_per_box)} علبة و${maxBase % line.product.units_per_box} شريط` : `${maxBase} عبوة`}</p>
                    </div>
                    <div className="space-y-1">
                      <label className="text-xs text-muted-foreground">وحدة البيع</label>
                      <Select
                        value={String(line.unitChoice)}
                        onValueChange={(value) => updateLine(index, { unitChoice: value === 'box' ? 'box' : Number(value), quantity: 1 })}
                        aria-label="وحدة البيع"
                        options={[
                          { value: 'box', label: 'علبة كاملة' },
                          ...(line.product.packaging_type === 'BOX_STRIP'
                            ? Array.from({ length: Math.max(1, line.product.units_per_box - 1) }, (_, stripIndex) => {
                                const strips = stripIndex + 1
                                return { value: String(strips), label: strips === 1 ? 'شريط واحد' : strips === 2 ? 'شريطان' : `${strips} شرائط` }
                              })
                            : []),
                        ]}
                      />
                    </div>
                    <div className="space-y-1">
                      <label className="text-xs text-muted-foreground">الكمية</label>
                      <div className="flex h-10 items-center rounded-lg border border-input">
                        <button type="button" onClick={() => updateLine(index, { quantity: Math.max(1, line.quantity - 1) })} className="px-2 text-muted-foreground hover:text-foreground" aria-label="تقليل الكمية"><Minus className="h-4 w-4" /></button>
                        <span className="flex-1 text-center text-sm font-semibold">{line.quantity}</span>
                        <button type="button" onClick={() => updateLine(index, { quantity: line.quantity + 1 })} className="px-2 text-muted-foreground hover:text-foreground" aria-label="زيادة الكمية"><Plus className="h-4 w-4" /></button>
                      </div>
                    </div>
                    <div className="text-left md:text-right">
                      <p className="text-xs text-muted-foreground">{unitLabel(line)}</p>
                      <p className="mt-1 font-semibold">{formatPiastres(lineTotal)}</p>
                      {requestedBase > maxBase && <p className="mt-1 text-xs text-destructive">الكمية تتجاوز المخزون</p>}
                    </div>
                    <Button type="button" variant="ghost" size="icon" className="text-destructive" onClick={() => setCart((current) => current.filter((_, lineIndex) => lineIndex !== index))} aria-label="حذف الصنف"><Trash2 className="h-4 w-4" /></Button>
                  </div>
                )
              })}
              <div className="flex flex-col items-end gap-4 border-t border-border pt-5 sm:flex-row sm:items-center sm:justify-between">
                <div className="text-sm text-muted-foreground">الحساب هنا فوري للعرض، والباك إند يعيد التحقق من الأسعار والمخزون عند الاعتماد.</div>
                <div className="flex items-center gap-5">
                  <div><span className="text-sm text-muted-foreground">الإجمالي</span><p className="text-2xl font-bold text-primary">{formatPiastres(total)}</p></div>
                  <Button onClick={checkout} loading={checkoutLoading}>إتمام البيع</Button>
                </div>
              </div>
            </div>
          )}
          {error && <p className="mt-4 rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
          {message && (
            <div className="mt-4 rounded-lg border border-primary/30 bg-primary/10 p-3">
              <p className="text-sm text-primary">{message}</p>
              {lastSaleId.current && printSettings.print_mode === 'manual' && (
                <Button variant="outline" size="sm" className="mt-2" loading={printBusy} onClick={() => lastSaleId.current && void prepareReceiptPrint(lastSaleId.current)}>
                  <Printer className="h-4 w-4" /> طباعة الفاتورة
                </Button>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {/* مدير طباعة الإيصال — يفتح نافذة الطباعة على الإعدادات المحفوظة */}
      <ReceiptPrinter job={printJob} settings={printSettings} onDone={() => setPrintJob(null)} />
    </div>
  )
}
