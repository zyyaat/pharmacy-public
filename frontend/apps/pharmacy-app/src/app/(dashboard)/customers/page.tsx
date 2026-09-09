'use client'

import { useCallback, useEffect, useState } from 'react'
import { NotebookPen, Phone, Plus, RotateCcw, UserRound } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type CustomerStatement,
  type CustomerStatementEntry,
  type PharmacyCustomer,
} from '@/lib/api'
import { formatPiastres, parseEGPToPiastres } from '@/lib/money'
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Input } from '@/components/ui'

function entryDate(iso: string) {
  return new Date(iso).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short', year: 'numeric' })
}

function entryTime(iso: string) {
  return new Date(iso).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })
}

function balanceBadge(balance: number) {
  if (balance > 0) return <Badge variant="destructive">مستحق عليه {formatPiastres(balance)}</Badge>
  if (balance < 0) return <Badge variant="success">له رصيد {formatPiastres(-balance)}</Badge>
  return <Badge variant="success">الحساب مسدد</Badge>
}

/**
 * حسابات العملاء (Task 39 رقم 5): قائمة العملاء بأرصدتهم، كشف حساب لكل عميل
 * (فواتير الآجل مديناً والتحصيلات دائناً برصيد جاري)، وتسجيل دفعة سداد.
 * الرصيد مشتق دائماً من الفواتير والمرتجعات والدفعات — لا يُخزن يدوياً.
 */
export default function CustomersPage() {
  const [customers, setCustomers] = useState<PharmacyCustomer[]>([])
  const [search, setSearch] = useState('')
  const [listLoading, setListLoading] = useState(true)
  const [selected, setSelected] = useState<PharmacyCustomer | null>(null)
  const [statement, setStatement] = useState<CustomerStatement | null>(null)
  const [statementLoading, setStatementLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // عميل جديد
  const [creating, setCreating] = useState(false)
  const [newName, setNewName] = useState('')
  const [newPhone, setNewPhone] = useState('')
  const [creatingCustomer, setCreatingCustomer] = useState(false)

  // دفعة سداد
  const [paymentInput, setPaymentInput] = useState('')
  const [paymentNote, setPaymentNote] = useState('')
  const [savingPayment, setSavingPayment] = useState(false)

  const loadCustomers = useCallback((searchValue: string) => {
    const controller = new AbortController()
    setListLoading(true)
    pharmacyApi.listCustomers(searchValue.trim(), controller.signal)
      .then((response) => setCustomers(response.data.customers))
      .catch((cause) => {
        if (controller.signal.aborted) return
        setError(cause instanceof ApiError ? cause.message : 'تعذر قراءة حسابات العملاء')
      })
      .finally(() => {
        if (!controller.signal.aborted) setListLoading(false)
      })
    return () => controller.abort()
  }, [])

  useEffect(() => {
    const timer = setTimeout(() => {
      const abort = loadCustomers(search)
      return () => abort()
    }, 200)
    return () => clearTimeout(timer)
  }, [search, loadCustomers])

  const selectCustomer = useCallback((customer: PharmacyCustomer) => {
    setSelected(customer)
    setStatement(null)
    setPaymentInput('')
    setPaymentNote('')
    setStatementLoading(true)
    pharmacyApi.getCustomerStatement(customer.id)
      .then((response) => setStatement(response.data))
      .catch((cause) => setError(cause instanceof ApiError ? cause.message : 'تعذر قراءة كشف الحساب'))
      .finally(() => setStatementLoading(false))
  }, [])

  async function addCustomer() {
    const name = newName.trim()
    if (!name) {
      setError('اكتب اسم العميل أولاً')
      return
    }
    setCreatingCustomer(true)
    setError(null)
    try {
      const response = await pharmacyApi.createCustomer(name, newPhone.trim())
      setCreating(false)
      setNewName('')
      setNewPhone('')
      setCustomers((current) => [response.data.customer, ...current])
      selectCustomer(response.data.customer)
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : 'تعذر إضافة العميل')
    } finally {
      setCreatingCustomer(false)
    }
  }

  async function recordPayment() {
    if (!selected || !statement) return
    const piastres = parseEGPToPiastres(paymentInput)
    if (piastres === null || piastres <= 0) {
      setError('اكتب مبلغ الدفعة بالجنيه مثل 50.00')
      return
    }
    setSavingPayment(true)
    setError(null)
    try {
      await pharmacyApi.createCustomerPayment(selected.id, piastres, paymentNote.trim())
      setPaymentInput('')
      setPaymentNote('')
      // تحديث الكشف والقائمة معاً
      const refreshed = await pharmacyApi.getCustomerStatement(selected.id)
      setStatement(refreshed.data)
      loadCustomers(search)
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : 'تعذر تسجيل الدفعة')
    } finally {
      setSavingPayment(false)
    }
  }

  const entries: CustomerStatementEntry[] = statement?.entries ?? []

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold"><NotebookPen className="h-6 w-6 text-primary" />حسابات العملاء</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          سجّل فواتير الآجل على حساب العميل من نقطة البيع، وتابع المستحقات هنا وسجّل دفعات السداد — الرصيد يُحسب تلقائياً من الفواتير والمرتجعات والدفعات.
        </p>
      </div>

      {error && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}

      <div className="grid gap-6 lg:grid-cols-[340px_1fr]">
        {/* قائمة العملاء */}
        <Card className="self-start">
          <CardHeader className="pb-3">
            <div className="flex items-center justify-between gap-2">
              <CardTitle className="text-base">العملاء</CardTitle>
              <Button variant="outline" size="sm" onClick={() => setCreating((value) => !value)}>
                <Plus className="h-4 w-4" /> عميل جديد
              </Button>
            </div>
            <CardDescription>ابحث بالاسم أو رقم الهاتف</CardDescription>
            <Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="بحث…" aria-label="بحث في العملاء" />
          </CardHeader>
          <CardContent className="space-y-2">
            {creating && (
              <div className="space-y-2 rounded-xl border border-primary/30 bg-primary/5 p-3">
                <Input value={newName} onChange={(event) => setNewName(event.target.value)} placeholder="اسم العميل" aria-label="اسم العميل الجديد" />
                <Input value={newPhone} onChange={(event) => setNewPhone(event.target.value)} placeholder="الهاتف (اختياري)" inputMode="tel" aria-label="هاتف العميل الجديد" />
                <div className="flex gap-2">
                  <Button size="sm" loading={creatingCustomer} onClick={addCustomer}>إضافة</Button>
                  <Button variant="ghost" size="sm" onClick={() => setCreating(false)}>إلغاء</Button>
                </div>
              </div>
            )}
            {listLoading && customers.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">جاري التحميل…</p>
            ) : customers.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">
                لا يوجد عملاء بعد — أضف عميلاً أو سجّل فاتورة آجل من نقطة البيع.
              </p>
            ) : (
              customers.map((customer) => (
                <button
                  key={customer.id}
                  type="button"
                  onClick={() => selectCustomer(customer)}
                  className={`w-full rounded-xl border p-3 text-start transition ${selected?.id === customer.id ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/40'}`}
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="flex items-center gap-2 font-semibold"><UserRound className="h-4 w-4 text-muted-foreground" />{customer.name}</span>
                    {balanceBadge(customer.balance_piastres)}
                  </div>
                  {customer.phone && (
                    <span className="mt-1 flex items-center gap-1 text-xs text-muted-foreground" dir="ltr"><Phone className="h-3 w-3" />{customer.phone}</span>
                  )}
                </button>
              ))
            )}
          </CardContent>
        </Card>

        {/* كشف الحساب */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">{statement ? `كشف حساب: ${statement.customer.name}` : 'كشف الحساب'}</CardTitle>
            {statement && (
              <CardDescription>
                {statement.customer.phone || 'بدون رقم هاتف'} · الرصيد الحالي{' '}
                <span className={statement.balance_piastres > 0 ? 'font-bold text-destructive' : 'font-bold text-emerald-600 dark:text-emerald-400'}>
                  {formatPiastres(statement.balance_piastres)}
                </span>
              </CardDescription>
            )}
          </CardHeader>
          <CardContent className="space-y-5">
            {!selected ? (
              <p className="py-14 text-center text-sm text-muted-foreground">اختر عميلاً من القائمة لعرض كشف حسابه وتسجيل دفعات السداد.</p>
            ) : statementLoading ? (
              <p className="py-14 text-center text-sm text-muted-foreground">جاري تحميل الكشف…</p>
            ) : (
              <>
                {entries.length === 0 ? (
                  <p className="py-10 text-center text-sm text-muted-foreground">لا حركات بعد — أول فاتورة آجل لهذا العميل ستظهر هنا.</p>
                ) : (
                  <div className="overflow-x-auto rounded-xl border border-border">
                    <table className="w-full text-sm">
                      <thead className="bg-muted/50 text-xs text-muted-foreground">
                        <tr>
                          <th className="p-3 text-start font-semibold">التاريخ</th>
                          <th className="p-3 text-start font-semibold">البيان</th>
                          <th className="p-3 text-start font-semibold">عليه</th>
                          <th className="p-3 text-start font-semibold">سداد</th>
                          <th className="p-3 text-start font-semibold">الرصيد</th>
                        </tr>
                      </thead>
                      <tbody>
                        {entries.map((entry) => (
                          <tr key={`${entry.kind}-${entry.id}`} className="border-t border-border/60">
                            <td className="whitespace-nowrap p-3 text-xs text-muted-foreground">
                              {entryDate(entry.created_at)}
                              <span className="block">{entryTime(entry.created_at)}</span>
                            </td>
                            <td className="p-3">
                              {entry.kind === 'credit_sale' ? (
                                <>
                                  <span className="font-semibold">فاتورة آجل <span dir="ltr" className="font-mono text-xs">INV-{String(entry.invoice_number ?? 0).padStart(6, '0')}</span></span>
                                  {!!entry.returned_amount_piastres && entry.returned_amount_piastres > 0 && (
                                    <span className="mt-0.5 flex items-center gap-1 text-xs text-muted-foreground">
                                      <RotateCcw className="h-3 w-3" /> مرتجع {formatPiastres(entry.returned_amount_piastres)}
                                    </span>
                                  )}
                                </>
                              ) : (
                                <span className="font-semibold">سداد نقدي{entry.note ? ` — ${entry.note}` : ''}</span>
                              )}
                            </td>
                            <td className="p-3 font-semibold text-destructive">
                              {entry.kind === 'credit_sale' ? formatPiastres(entry.due_amount_piastres ?? 0) : '—'}
                            </td>
                            <td className="p-3 font-semibold text-emerald-600 dark:text-emerald-400">
                              {entry.kind === 'payment' ? formatPiastres(entry.amount_piastres ?? 0) : '—'}
                            </td>
                            <td className="p-3 font-bold">{formatPiastres(entry.balance_piastres)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}

                {/* تسجيل دفعة */}
                <div className="space-y-3 rounded-xl border border-border bg-muted/30 p-4">
                  <p className="text-sm font-bold">تسجيل دفعة سداد</p>
                  <div className="grid gap-2 sm:grid-cols-[160px_1fr_auto]">
                    <Input
                      value={paymentInput}
                      onChange={(event) => setPaymentInput(event.target.value)}
                      placeholder="المبلغ مثل 50.00"
                      inputMode="decimal"
                      aria-label="مبلغ الدفعة بالجنيه"
                    />
                    <Input
                      value={paymentNote}
                      onChange={(event) => setPaymentNote(event.target.value)}
                      placeholder="ملاحظة (اختياري)"
                      aria-label="ملاحظة الدفعة"
                    />
                    <Button loading={savingPayment} onClick={recordPayment}>تسجيل الدفعة</Button>
                  </div>
                  <p className="text-xs text-muted-foreground">المبلغ بالجنيه ويُحوَّل داخلياً إلى قروش — يظهر في الكشف فوراً ويخصم من رصيد العميل.</p>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
