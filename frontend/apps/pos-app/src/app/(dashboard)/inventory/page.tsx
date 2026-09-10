'use client'

import Link from 'next/link'
import { useCallback, useEffect, useState } from 'react'
import { Package, PackagePlus, Pencil, Plus, Search, ShoppingCart } from 'lucide-react'
import { pharmacyApi, type PharmacyInventoryItem } from '@/lib/api'
import { extraStrengthLabel } from '@/lib/product'
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Input, Modal } from '@/components/ui'
import { Can, RequirePermission, useAccess } from '@/components/permissions/gate'

const statusLabels: Record<string, { label: string; variant: 'destructive' | 'warning' | 'secondary' | 'success' | 'outline' }> = {
  out_of_stock: { label: 'نفذ', variant: 'destructive' },
  low_stock: { label: 'منخفض', variant: 'warning' },
  expiring_soon: { label: 'قريب الانتهاء', variant: 'secondary' },
  quarantined: { label: 'محجوز', variant: 'outline' },
  normal: { label: 'متوفر', variant: 'success' },
}

function formatQuantity(item: PharmacyInventoryItem): string {
  if (item.packaging_type === 'BOX_STRIP') {
    const boxes = Math.floor(item.quantity / item.units_per_box)
    const strips = item.quantity % item.units_per_box
    if (boxes === 0 && strips === 0) return 'نفذ من المخزون'
    if (boxes === 0) return `${new Intl.NumberFormat('ar-EG').format(strips)} شريط`
    if (strips === 0) return `${new Intl.NumberFormat('ar-EG').format(boxes)} علبة`
    return `${new Intl.NumberFormat('ar-EG').format(boxes)} علبة و${new Intl.NumberFormat('ar-EG').format(strips)} شريط`
  }
  return `${new Intl.NumberFormat('ar-EG').format(item.quantity)} عبوة`
}

// ---------------------------------------------------------------------------
// Edit product modal: opens with the REAL stored values (fetched fresh from
// GET /pharmacy/products/:id) and saves through PUT. Money edits go through
// parseEGPToPiastres so only exact integer piastres ever reach the backend.
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Stock control modal: every submit goes through the adjust endpoint, which
// writes a stock_movements row first - the movement ledger stays the single
// source of truth for quantities.
// ---------------------------------------------------------------------------
function AdjustStockModal({
  item,
  onClose,
  onSaved,
}: {
  item: PharmacyInventoryItem
  onClose: () => void
  onSaved: () => void
}) {
  const isBoxStrip = item.packaging_type === 'BOX_STRIP'
  const [direction, setDirection] = useState<'add' | 'remove'>('add')
  const [boxes, setBoxes] = useState('')
  const [strips, setStrips] = useState('')
  const [reason, setReason] = useState('')
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)

  const boxCount = Number.parseInt(boxes, 10) || 0
  const stripCount = Number.parseInt(strips, 10) || 0
  const amount = isBoxStrip ? boxCount * item.units_per_box + stripCount : boxCount
  const delta = amount * (direction === 'add' ? 1 : -1)
  const projected = item.quantity + delta

  const submit = async () => {
    setFormError(null)
    if (amount <= 0) {
      setFormError('أدخل كمية أكبر من صفر')
      return
    }
    setSaving(true)
    try {
      await pharmacyApi.adjustBatchStock(item.batch_id, delta, reason.trim(), crypto.randomUUID())
      onSaved()
      onClose()
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'تعذر تسجيل حركة المخزون')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal isOpen onClose={onClose}>
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-bold">التحكم في المخزون</h3>
          <Button variant="ghost" size="sm" onClick={onClose}>إغلاق</Button>
        </div>

        <p className="text-sm text-muted-foreground">
          {item.product_name} — التشغيلة {item.batch_number}
          <span className="mt-1 block font-semibold text-foreground">الكمية الحالية: {formatQuantity(item)}</span>
        </p>

        <div className="grid grid-cols-2 gap-2">
          <Button type="button" variant={direction === 'add' ? 'default' : 'outline'} size="sm" onClick={() => setDirection('add')}>+ إضافة كمية</Button>
          <Button type="button" variant={direction === 'remove' ? 'destructive' : 'outline'} size="sm" onClick={() => setDirection('remove')}>− خصم كمية</Button>
        </div>

        {isBoxStrip ? (
          <div className="grid grid-cols-2 gap-3">
            <Input label="عدد العلب" type="number" min={0} value={boxes} onChange={(e) => setBoxes(e.target.value)} inputMode="numeric" />
            <Input label="عدد الشرائح" type="number" min={0} value={strips} onChange={(e) => setStrips(e.target.value)} inputMode="numeric" />
          </div>
        ) : (
          <Input label="عدد العبوات" type="number" min={0} value={boxes} onChange={(e) => setBoxes(e.target.value)} inputMode="numeric" />
        )}

        <Input label="السبب (اختياري)" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="تالف / جرد / إعادة تعبئة..." />

        {amount > 0 && (
          <p className={`rounded-lg p-2.5 text-xs ${projected < 0 ? 'bg-destructive/10 text-destructive' : 'bg-muted text-muted-foreground'}`}>
            الكمية بعد الحركة: {new Intl.NumberFormat('ar-EG').format(projected)}
            {projected < 0 && ' — لا يمكن أن يصبح المخزون سالبًا'}
          </p>
        )}

        {formError && <p className="text-sm text-destructive">{formError}</p>}

        <div className="flex gap-2">
          <Button className="flex-1" loading={saving} onClick={submit} disabled={projected < 0}>
            {direction === 'add' ? 'إضافة للمخزون' : 'خصم من المخزون'}
          </Button>
          <Button variant="outline" onClick={onClose}>إلغاء</Button>
        </div>
      </div>
    </Modal>
  )
}

export default function InventoryPage() {
  // أعمدة/أزرار الإجراءات تختفي كليًا عمن لا يملك أي صلاحية تعديل
  const { allowed } = useAccess()
  const canManageProducts = allowed('inventory.manage_products')
  const canAdjustStock = allowed('inventory.adjust')
  const canSeeActions = canManageProducts || canAdjustStock
  const [items, setItems] = useState<PharmacyInventoryItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')
  const [adjustTarget, setAdjustTarget] = useState<PharmacyInventoryItem | null>(null)

  const load = useCallback(() => {
    setLoading(true)
    pharmacyApi
      .getInventory()
      .then((response) => setItems(response.data))
      .catch((err) => setError(err instanceof Error ? err.message : 'تعذر تحميل المخزون'))
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => {
    load()
  }, [load])

  // البحث يشمل التركيز أيضاً — لو في أكثر من تركيز لنفس العلاج يسهّل الوصول للصنف المطلوب
  const filteredItems = items.filter((item) =>
    [item.product_name, item.generic_name, item.brand_name, item.strength, item.barcode, item.batch_number]
      .join(' ')
      .toLowerCase()
      .includes(search.toLowerCase()),
  )

  return (
    <RequirePermission anyOf={['inventory.view']}>
    <div className="mx-auto max-w-[1500px] space-y-6">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h1 className="text-2xl font-bold">المخزون والأدوية</h1>
          <p className="mt-2 text-sm text-muted-foreground">البيانات الفعلية للصيدلية الحالية فقط</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Can perm="pos.access">
            <Button asChild variant="outline"><Link href="/pos"><ShoppingCart className="h-4 w-4" />فتح نقطة البيع</Link></Button>
          </Can>
          <Can perm="inventory.manage_products">
            <Button asChild><Link href="/inventory/new"><Plus className="h-4 w-4" />إضافة منتج</Link></Button>
          </Can>
        </div>
      </div>

      <Card>
        <CardHeader className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <CardTitle className="flex items-center gap-2"><Package className="h-5 w-5 text-primary" />كل الأصناف</CardTitle>
          <div className="relative w-full sm:max-w-xs">
            <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="بحث بالاسم أو الباركود" className="h-10 w-full rounded-lg border border-input bg-background pl-3 pr-10 text-sm outline-none focus:ring-2 focus:ring-ring" />
          </div>
        </CardHeader>
        <CardContent>
          {loading && <p className="py-10 text-center text-muted-foreground">جاري تحميل المخزون...</p>}
          {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
          {!loading && !error && filteredItems.length === 0 && <p className="py-10 text-center text-muted-foreground">لا توجد أصناف مطابقة</p>}
          {!loading && !error && filteredItems.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[900px] text-right text-sm">
                <thead className="border-b text-xs text-muted-foreground">
                  <tr><th className="p-3">المنتج</th><th className="p-3">التشغيلة</th><th className="p-3">الفرع</th><th className="p-3">الكمية</th><th className="p-3">الصلاحية</th><th className="p-3">الحالة</th>{canSeeActions && <th className="p-3">الإجراءات</th>}</tr>
                </thead>
                <tbody>
                  {filteredItems.map((item) => {
                    // نفس قاعدة POS والفاتورة: التركيز يُلحق بجانب الاسم فقط لو الاسم نفسه ما يحملش جرعة
                    const strengthLabel = extraStrengthLabel(item.product_name, item.strength)
                    return (
                    <tr key={item.batch_id} className="border-b last:border-0">
                      <td className="p-3">
                        <Link href={`/inventory/${item.batch_id}`} className="font-semibold hover:text-primary">{item.product_name}</Link>
                        {strengthLabel && <span className="ms-1 text-xs font-normal text-muted-foreground">{strengthLabel}</span>}
                        <span className="mt-1 block text-xs text-muted-foreground">{item.generic_name || item.brand_name}</span>
                      </td>
                      <td className="p-3">{item.batch_number}</td>
                      <td className="p-3">{item.branch_name || 'كل الفروع'}</td>
                      <td className="p-3 font-semibold">
                        {item.quantity <= 0
                          ? <span className="text-destructive">نفذ من المخزون</span>
                          : formatQuantity(item)}
                      </td>
                      <td className="p-3">{item.expiry_date || '—'}</td>
                      <td className="p-3">
                        <Badge variant={statusLabels[item.status]?.variant ?? 'outline'}>
                          {statusLabels[item.status]?.label ?? item.status}
                        </Badge>
                      </td>
                      {canSeeActions && (
                      <td className="p-3">
                        <div className="flex gap-1.5">
                          {canManageProducts && (
                            <Button asChild variant="outline" size="sm" title="تعديل بيانات المنتج">
                              <Link href={`/inventory/edit/${item.pharmacy_product_id}`}>
                                <Pencil className="h-3.5 w-3.5" />تعديل
                              </Link>
                            </Button>
                          )}
                          {canAdjustStock && (
                            <Button variant={item.quantity <= 0 ? 'default' : 'ghost'} size="sm" onClick={() => setAdjustTarget(item)} title="التحكم في مخزون التشغيلة">
                              <PackagePlus className="h-3.5 w-3.5" />مخزون
                            </Button>
                          )}
                        </div>
                      </td>
                      )}
                    </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {adjustTarget && (
        <AdjustStockModal item={adjustTarget} onClose={() => setAdjustTarget(null)} onSaved={load} />
      )}
    </div>
    </RequirePermission>
  )
}
