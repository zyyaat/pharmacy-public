'use client'

import { FormEvent, useMemo, useRef, useState } from 'react'
import { Barcode, Minus, Plus, ReceiptText, Trash2 } from 'lucide-react'
import { ApiError, pharmacyApi, type POSProduct, type POSSaleItem } from '@/lib/api'
import { Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Input } from '@/components/ui'

type CartLine = {
  product: POSProduct
  unitChoice: 'box' | number
  quantity: number
}

function unitLabel(line: CartLine) {
  if (line.unitChoice === 'box') return 'علبة كاملة'
  if (line.unitChoice === 1) return `${line.quantity} شريط`
  if (line.unitChoice === 2) return `${line.quantity * 2} شريطين`
  return `${line.quantity * line.unitChoice} شرائط`
}

export default function POSPage() {
  const [barcode, setBarcode] = useState('')
  const [cart, setCart] = useState<CartLine[]>([])
  const [loading, setLoading] = useState(false)
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const barcodeInput = useRef<HTMLInputElement>(null)

  async function addByBarcode(event?: FormEvent) {
    event?.preventDefault()
    const value = barcode.trim()
    if (!value || loading) return
    setLoading(true)
    setError(null)
    setMessage(null)
    try {
      const response = await pharmacyApi.lookupPOSProduct(value)
      setCart((current) => {
        const existing = current.find((line) => line.product.id === response.data.id && line.unitChoice === 'box')
        if (existing) {
          return current.map((line) => line === existing ? { ...line, quantity: line.quantity + 1 } : line)
        }
        return [...current, { product: response.data, unitChoice: 'box', quantity: 1 }]
      })
      setBarcode('')
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : 'تعذر العثور على المنتج')
    } finally {
      setLoading(false)
      barcodeInput.current?.focus()
    }
  }

  const total = useMemo(() => cart.reduce((sum, line) => {
    const price = line.unitChoice === 'box'
      ? line.product.selling_price
      : (line.product.partial_selling_price || line.product.selling_price / line.product.units_per_box) * line.unitChoice
    return sum + price * line.quantity
  }, 0), [cart])

  function updateLine(index: number, change: Partial<CartLine>) {
    setCart((current) => current.map((line, lineIndex) => lineIndex === index ? { ...line, ...change } : line))
  }

  async function checkout() {
    if (cart.length === 0 || checkoutLoading) return
    setCheckoutLoading(true)
    setError(null)
    setMessage(null)
    const items: POSSaleItem[] = cart.map((line) => ({
      pharmacy_product_id: line.product.id,
      sale_unit: line.unitChoice === 'box' ? 'box' : 'strip',
      quantity: line.unitChoice === 'box' ? line.quantity : line.quantity * line.unitChoice,
    }))
    try {
      const response = await pharmacyApi.createPOSSale(items)
      setMessage(`تم حفظ الفاتورة بنجاح. الإجمالي ${new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP' }).format(response.data.total_amount)}`)
      setCart([])
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : 'تعذر إتمام البيع')
    } finally {
      setCheckoutLoading(false)
    }
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold">نقطة البيع</h1>
        <p className="mt-2 text-sm text-muted-foreground">افحص باركود العلاج، ثم اختر علبة كاملة أو عدد الشرائط.</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Barcode className="h-5 w-5 text-primary" />إضافة منتج بالفحص</CardTitle>
          <CardDescription>اضغط Enter بعد الفحص لإضافة المنتج إلى الفاتورة.</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={addByBarcode} className="flex gap-3">
            <Input ref={barcodeInput} value={barcode} onChange={(event) => setBarcode(event.target.value)} placeholder="امسح الباركود هنا" autoFocus />
            <Button type="submit" loading={loading}>إضافة</Button>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2"><ReceiptText className="h-5 w-5 text-primary" />الفاتورة الحالية</CardTitle>
            <CardDescription>{cart.length ? `${cart.length} أصناف` : 'لم تتم إضافة أصناف بعد'}</CardDescription>
          </div>
          {cart.length > 0 && <Button variant="ghost" onClick={() => setCart([])}>تفريغ الفاتورة</Button>}
        </CardHeader>
        <CardContent>
          {cart.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border py-14 text-center text-muted-foreground">ابدأ بفحص باركود المنتج</div>
          ) : (
            <div className="space-y-3">
              {cart.map((line, index) => {
                const price = line.unitChoice === 'box'
                  ? line.product.selling_price
                  : (line.product.partial_selling_price || line.product.selling_price / line.product.units_per_box) * line.unitChoice
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
                      <select value={String(line.unitChoice)} onChange={(event) => updateLine(index, { unitChoice: event.target.value === 'box' ? 'box' : Number(event.target.value), quantity: 1 })} className="h-10 w-full rounded-lg border border-input bg-background px-3 text-sm">
                        <option value="box">علبة كاملة</option>
                        {line.product.packaging_type === 'BOX_STRIP' && Array.from({ length: Math.max(1, line.product.units_per_box - 1) }, (_, stripIndex) => {
                          const strips = stripIndex + 1
                          return <option key={strips} value={strips}>{strips === 1 ? 'شريط واحد' : strips === 2 ? 'شريطان' : `${strips} شرائط`}</option>
                        })}
                      </select>
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
                      <p className="mt-1 font-semibold">{new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP' }).format(price * line.quantity)}</p>
                      {requestedBase > maxBase && <p className="mt-1 text-xs text-destructive">الكمية تتجاوز المخزون</p>}
                    </div>
                    <Button type="button" variant="ghost" size="icon" className="text-destructive" onClick={() => setCart((current) => current.filter((_, lineIndex) => lineIndex !== index))} aria-label="حذف الصنف"><Trash2 className="h-4 w-4" /></Button>
                  </div>
                )
              })}
              <div className="flex flex-col items-end gap-4 border-t border-border pt-5 sm:flex-row sm:items-center sm:justify-between">
                <div className="text-sm text-muted-foreground">سيعيد الباك إند التحقق من المخزون قبل الخصم.</div>
                <div className="flex items-center gap-5">
                  <div><span className="text-sm text-muted-foreground">الإجمالي</span><p className="text-2xl font-bold text-primary">{new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP' }).format(total)}</p></div>
                  <Button onClick={checkout} loading={checkoutLoading}>إتمام البيع</Button>
                </div>
              </div>
            </div>
          )}
          {error && <p className="mt-4 rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
          {message && <p className="mt-4 rounded-lg border border-primary/30 bg-primary/10 p-3 text-sm text-primary">{message}</p>}
        </CardContent>
      </Card>
    </div>
  )
}