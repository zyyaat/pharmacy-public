'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import { Search, Minus, Plus, Printer, ReceiptText, Trash2, PauseCircle, UserRound } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type POSProduct,
  type POSSaleItem,
  type POSSaleOptions,
  type PharmacyCustomer,
} from '@/lib/api'
import { formatPiastres, parseEGPToPiastres, stripPricePiastres } from '@/lib/money'
import { Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Input, Select } from '@/components/ui'
import ProductSearch, { type AddSource } from '@/components/pos/product-search'
import { useReceiptSettings } from '@/hooks/useReceiptSettings'
import { usePharmacyContext } from '@/hooks/usePharmacyContext'
import { extraStrengthLabel } from '@/lib/product'
import ReceiptPrinter, { type ReceiptPrintJob } from '@/components/pos/receipt-printer'
import { saleDetailToReceipt } from '@/components/pos/receipt-template'
import { RequirePermission, useAccess } from '@/components/permissions/gate'

type CartLine = {
  product: POSProduct
  unitChoice: 'box' | number
  quantity: number
}

/** فاتورة معلّقة (Task 39 رقم 7): تُحفظ في المتصفح وتُستأنف لاحقاً بنفس الأصناف */
type ParkedInvoice = {
  id: string
  label: string
  savedAt: string
  cart: CartLine[]
}

const PARKED_KEY = 'pos_parked_invoices_v1'

function loadParkedInvoices(): ParkedInvoice[] {
  try {
    const raw = typeof window !== 'undefined' ? window.localStorage.getItem(PARKED_KEY) : null
    const parsed = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? (parsed as ParkedInvoice[]) : []
  } catch {
    return []
  }
}

function persistParkedInvoices(list: ParkedInvoice[]) {
  try {
    window.localStorage.setItem(PARKED_KEY, JSON.stringify(list))
  } catch {
    // وضع التصفح الخاص قد يمنع التخزين — الإيقاف المؤقت ميزة إضافية لا يفشل معها البيع
  }
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
  // البيع الآجل يحتاج بحث/اختيار عملاء — بلا صلاحية العرض نخفي الخيار كليًا
  const { allowed } = useAccess()
  const canUseCreditSales = allowed('customers.view')
  const canAddCustomers = allowed('customers.create')
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

  // ---- الخصم على مستوى الفاتورة (Task 39 رقم 4) ----
  const [discountKind, setDiscountKind] = useState<'amount' | 'percent'>('amount')
  const [discountInput, setDiscountInput] = useState('')

  // ---- البيع الآجل لحساب عميل (Task 39 رقم 5) ----
  const [paymentType, setPaymentType] = useState<'cash' | 'credit'>('cash')
  const [customerSearch, setCustomerSearch] = useState('')
  const [customerResults, setCustomerResults] = useState<PharmacyCustomer[]>([])
  const [selectedCustomer, setSelectedCustomer] = useState<PharmacyCustomer | null>(null)
  const [creatingCustomer, setCreatingCustomer] = useState(false)
  const [newCustomerName, setNewCustomerName] = useState('')
  const [newCustomerPhone, setNewCustomerPhone] = useState('')
  const [addingCustomer, setAddingCustomer] = useState(false)

  // ---- الفواتير المعلّقة (Task 39 رقم 7) ----
  const [parked, setParked] = useState<ParkedInvoice[]>([])
  useEffect(() => {
    setParked(loadParkedInvoices())
  }, [])

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

  const subtotal = useMemo(
    () => cart.reduce((sum, line) => sum + lineTotalPiastres(line), 0),
    [cart],
  )

  /** الخصم كما سيرسله الباكند: نسبة من الإجمالي أو مبلغ بالجنيه */
  const discountPiastres = useMemo(() => {
    const raw = discountInput.trim()
    if (!raw || cart.length === 0) return 0
    if (discountKind === 'percent') {
      const value = Number(raw)
      if (!Number.isFinite(value) || value <= 0 || value > 100) return 0
      return Math.min(Math.round((subtotal * value) / 100), subtotal)
    }
    const piastres = parseEGPToPiastres(raw)
    if (piastres === null || piastres <= 0) return 0
    return Math.min(piastres, subtotal)
  }, [discountInput, discountKind, subtotal, cart.length])

  const discountInvalid = discountInput.trim() !== '' && discountPiastres === 0
  const finalTotal = Math.max(0, subtotal - discountPiastres)

  function updateLine(index: number, change: Partial<CartLine>) {
    setCart((current) => current.map((line, lineIndex) => lineIndex === index ? { ...line, ...change } : line))
  }

  function resetIdempotency() {
    idempotencyKey.current = null
  }

  // بحث العملاء عند تفعيل البيع الآجل (مع تهدئة بسيطة للكتابة)
  useEffect(() => {
    if (!canUseCreditSales || paymentType !== 'credit' || selectedCustomer || creatingCustomer) {
      setCustomerResults([])
      return
    }
    const controller = new AbortController()
    const timer = setTimeout(() => {
      pharmacyApi.listCustomers(customerSearch.trim(), controller.signal)
        .then((response) => setCustomerResults(response.data.customers.slice(0, 6)))
        .catch(() => {})
    }, 200)
    return () => {
      controller.abort()
      clearTimeout(timer)
    }
  }, [canUseCreditSales, paymentType, customerSearch, selectedCustomer, creatingCustomer])

  async function addNewCustomer() {
    const name = newCustomerName.trim()
    if (!name) {
      setError('اكتب اسم العميل الجديد أولاً')
      return
    }
    setAddingCustomer(true)
    setError(null)
    try {
      const response = await pharmacyApi.createCustomer(name, newCustomerPhone.trim())
      setSelectedCustomer(response.data.customer)
      setCreatingCustomer(false)
      setNewCustomerName('')
      setNewCustomerPhone('')
      setMessage(null)
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : 'تعذر إضافة العميل')
    } finally {
      setAddingCustomer(false)
    }
  }

  // ---- إيقاف مؤقت / استئناف ----
  function parkInvoice() {
    if (cart.length === 0) return
    const invoice: ParkedInvoice = {
      id: typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : String(Date.now()),
      label: `${cart.length} ${cart.length === 1 ? 'صنف' : 'أصناف'} · ${formatPiastres(subtotal)}`,
      savedAt: new Date().toISOString(),
      cart,
    }
    const next = [...parked, invoice]
    setParked(next)
    persistParkedInvoices(next)
    setCart([])
    setDiscountInput('')
    setPaymentType('cash')
    setSelectedCustomer(null)
    resetIdempotency()
    setMessage(null)
    setError(null)
  }

  function resumeParked(id: string) {
    const invoice = parked.find((item) => item.id === id)
    if (!invoice) return
    if (cart.length > 0 && !window.confirm('الفاتورة الحالية بها أصناف — سيتم استبدالها بالفاتورة المعلّقة. متابعة؟')) return
    setCart(invoice.cart)
    const next = parked.filter((item) => item.id !== id)
    setParked(next)
    persistParkedInvoices(next)
    resetIdempotency()
  }

  function deleteParked(id: string) {
    const next = parked.filter((item) => item.id !== id)
    setParked(next)
    persistParkedInvoices(next)
  }

  async function checkout() {
    if (cart.length === 0 || checkoutLoading) return
    if (discountInvalid) {
      setError(discountKind === 'percent' ? 'اكتب نسبة خصم بين 0 و 100' : 'اكتب مبلغ خصم صحيحاً بالجنيه')
      return
    }
    if (paymentType === 'credit' && !selectedCustomer) {
      setError('البيع الآجل يتطلب اختيار عميل من القائمة أو إضافة عميل جديد')
      return
    }
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
    const options: POSSaleOptions = {}
    if (discountPiastres > 0) {
      options.discount = discountKind === 'percent'
        ? { kind: 'percent', value: Number(discountInput.trim()) }
        : { kind: 'amount', value: discountPiastres }
    }
    if (paymentType === 'credit' && selectedCustomer) {
      options.payment_type = 'credit'
      options.customer_id = selectedCustomer.id
    }
    try {
      const response = await pharmacyApi.createPOSSale(items, idempotencyKey.current || undefined, options)
      lastSaleId.current = response.data.sale_id
      if (paymentType === 'credit' && selectedCustomer) {
        setMessage(`تم تسجيل فاتورة آجل على حساب «${selectedCustomer.name}» بمبلغ ${formatPiastres(response.data.total_amount_piastres)} — تابعها من صفحة حسابات العملاء.`)
      } else {
        setMessage(`تم حفظ الفاتورة بنجاح. الإجمالي ${formatPiastres(response.data.total_amount_piastres)}`)
      }
      setCart([])
      setDiscountInput('')
      setPaymentType('cash')
      setSelectedCustomer(null)
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
    <RequirePermission anyOf={['pos.access']}>
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
          {cart.length > 0 && (
            <div className="flex items-center gap-2">
              <Button variant="outline" onClick={parkInvoice}><PauseCircle className="h-4 w-4" /> إيقاف مؤقت</Button>
              <Button variant="ghost" onClick={() => { setCart([]); setDiscountInput(''); resetIdempotency() }}>تفريغ الفاتورة</Button>
            </div>
          )}
        </CardHeader>
        <CardContent>
          {/* الفواتير المعلّقة — استئناف أو حذف */}
          {parked.length > 0 && (
            <div className="mb-4 flex flex-wrap items-center gap-2 rounded-xl bg-muted/40 p-3">
              <span className="text-xs font-semibold text-muted-foreground">فواتير معلّقة:</span>
              {parked.map((invoice) => (
                <span key={invoice.id} className="flex items-center gap-2 rounded-full border border-border bg-background px-3 py-1 text-xs">
                  <button type="button" className="font-semibold hover:text-primary" onClick={() => resumeParked(invoice.id)}>
                    {invoice.label}
                  </button>
                  <button type="button" aria-label="حذف الفاتورة المعلقة" onClick={() => deleteParked(invoice.id)}>
                    <Trash2 className="h-3 w-3 text-muted-foreground hover:text-destructive" />
                  </button>
                </span>
              ))}
            </div>
          )}
          {cart.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border py-14 text-center text-muted-foreground">ابدأ بالفحص أو بالبحث بالاسم</div>
          ) : (
            <div className="space-y-3">
              {cart.map((line, index) => {
                const lineTotal = lineTotalPiastres(line)
                const maxBase = line.product.stock
                const requestedBase = line.quantity * (line.unitChoice === 'box' ? line.product.units_per_box : line.unitChoice)
                const strengthLabel = extraStrengthLabel(line.product.name, line.product.strength)
                return (
                  <div key={`${line.product.id}-${index}`} className="grid gap-4 rounded-xl border border-border p-4 md:grid-cols-[1fr_180px_130px_120px_40px] md:items-center">
                    <div>
                      <p className="font-semibold">
                        {line.product.name}
                        {strengthLabel && <span className="ms-1 text-xs font-normal text-muted-foreground">{strengthLabel}</span>}
                      </p>
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

              {/* الخصم + طريقة الدفع */}
              <div className="grid gap-4 rounded-xl border border-border p-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <label className="text-xs font-medium text-muted-foreground">خصم على الفاتورة</label>
                  <div className="flex gap-2">
                    <Input
                      value={discountInput}
                      onChange={(event) => setDiscountInput(event.target.value)}
                      placeholder={discountKind === 'percent' ? 'نسبة مثل 10' : 'مبلغ مثل 5.00'}
                      inputMode="decimal"
                      aria-label="قيمة الخصم"
                      className={discountInvalid ? 'border-destructive' : ''}
                    />
                    <div className="w-28 shrink-0">
                      <Select
                        value={discountKind}
                        onValueChange={(value) => { setDiscountKind(value as 'amount' | 'percent'); setDiscountInput('') }}
                        aria-label="نوع الخصم"
                        options={[{ value: 'amount', label: 'جنيه' }, { value: 'percent', label: 'نسبة %' }]}
                      />
                    </div>
                  </div>
                  {discountInvalid && <p className="text-xs text-destructive">اكتب قيمة صحيحة {discountKind === 'percent' ? 'بين 0 و 100' : 'بالجنيه'}</p>}
                </div>
                <div className="space-y-2">
                  <label className="text-xs font-medium text-muted-foreground">طريقة الدفع</label>
                  <Select
                    value={paymentType}
                    onValueChange={(value) => setPaymentType(value as 'cash' | 'credit')}
                    aria-label="طريقة الدفع"
                    options={canUseCreditSales
                      ? [{ value: 'cash', label: 'نقدي' }, { value: 'credit', label: 'آجل (على الحساب)' }]
                      : [{ value: 'cash', label: 'نقدي' }]}
                  />
                </div>
              </div>

              {/* اختيار العميل للبيع الآجل */}
              {paymentType === 'credit' && canUseCreditSales && (
                <div className="space-y-3 rounded-xl border border-primary/30 bg-primary/5 p-4">
                  {selectedCustomer ? (
                    <div className="flex items-center justify-between gap-3">
                      <div className="flex items-center gap-2">
                        <UserRound className="h-5 w-5 text-primary" />
                        <div>
                          <p className="font-semibold">{selectedCustomer.name}</p>
                          <p className="text-xs text-muted-foreground">
                            {selectedCustomer.phone || 'بدون رقم هاتف'}
                            {selectedCustomer.balance_piastres !== 0 && ` · رصيد سابق ${formatPiastres(selectedCustomer.balance_piastres)}`}
                          </p>
                        </div>
                      </div>
                      <Button variant="ghost" size="sm" onClick={() => setSelectedCustomer(null)}>تغيير العميل</Button>
                    </div>
                  ) : creatingCustomer ? (
                    <div className="space-y-2">
                      <div className="grid gap-2 sm:grid-cols-[1fr_180px_auto_auto]">
                        <Input value={newCustomerName} onChange={(event) => setNewCustomerName(event.target.value)} placeholder="اسم العميل" aria-label="اسم العميل الجديد" />
                        <Input value={newCustomerPhone} onChange={(event) => setNewCustomerPhone(event.target.value)} placeholder="الهاتف (اختياري)" inputMode="tel" aria-label="هاتف العميل الجديد" />
                        <Button type="button" size="sm" loading={addingCustomer} onClick={addNewCustomer}>إضافة</Button>
                        <Button type="button" variant="ghost" size="sm" onClick={() => setCreatingCustomer(false)}>إلغاء</Button>
                      </div>
                      <p className="text-xs text-muted-foreground">سيُضاف العميل إلى حسابات العملاء تلقائياً وتُقيّد عليه الفاتورة آجلاً.</p>
                    </div>
                  ) : (
                    <div className="space-y-2">
                      <Input
                        value={customerSearch}
                        onChange={(event) => setCustomerSearch(event.target.value)}
                        placeholder="ابحث عن العميل بالاسم أو الهاتف…"
                        aria-label="بحث عن العميل"
                      />
                      {customerResults.length > 0 && (
                        <div className="max-h-44 divide-y divide-border overflow-y-auto rounded-lg border border-border bg-background">
                          {customerResults.map((customer) => (
                            <button
                              key={customer.id}
                              type="button"
                              className="flex w-full items-center justify-between gap-3 p-2.5 text-sm hover:bg-accent"
                              onClick={() => { setSelectedCustomer(customer); setCustomerResults([]); setCustomerSearch('') }}
                            >
                              <span className="font-semibold">{customer.name}</span>
                              <span className="text-xs text-muted-foreground">
                                {customer.phone || 'بدون رقم'}
                                {customer.balance_piastres !== 0 && ` · رصيد ${formatPiastres(customer.balance_piastres)}`}
                              </span>
                            </button>
                          ))}
                        </div>
                      )}
                      {customerResults.length === 0 && customerSearch.trim() && (
                        <p className="text-xs text-muted-foreground">لا نتائج مطابقة — يمكنك إضافة عميل جديد.</p>
                      )}
                      {canAddCustomers && (
                        <button type="button" className="text-xs font-bold text-primary hover:underline" onClick={() => setCreatingCustomer(true)}>
                          + إضافة عميل جديد
                        </button>
                      )}
                    </div>
                  )}
                </div>
              )}

              <div className="flex flex-col gap-4 border-t border-border pt-5 sm:flex-row sm:items-center sm:justify-between">
                <div className="text-sm text-muted-foreground">الحساب هنا فوري للعرض، والباك إند يعيد التحقق من الأسعار والمخزون عند الاعتماد.</div>
                <div className="flex items-center gap-5">
                  <div className="text-end">
                    {discountPiastres > 0 && (
                      <>
                        <p className="text-xs text-muted-foreground">قبل الخصم {formatPiastres(subtotal)}</p>
                        <p className="text-xs font-semibold text-destructive">الخصم −{formatPiastres(discountPiastres)}</p>
                      </>
                    )}
                    <span className="text-sm text-muted-foreground">الإجمالي</span>
                    <p className="text-2xl font-bold text-primary">{formatPiastres(finalTotal)}</p>
                  </div>
                  <Button onClick={checkout} loading={checkoutLoading}>{paymentType === 'credit' ? 'إتمام البيع الآجل' : 'إتمام البيع'}</Button>
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
    </RequirePermission>
  )
}
