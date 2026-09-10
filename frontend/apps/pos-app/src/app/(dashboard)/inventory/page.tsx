'use client'

import Link from 'next/link'
import { useCallback, useEffect, useState } from 'react'
import { Package, PackagePlus, Pencil, Plus, Search, ShoppingCart } from 'lucide-react'
import { pharmacyApi, type PharmacyInventoryItem } from '@/lib/api'
import { extraStrengthLabel } from '@/lib/product'
import { fmtNumber } from '@/i18n/format'
import { useT } from '@/i18n/provider'
import type { Translator } from '@/i18n/translator'
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Input, Modal } from '@/components/ui'
import { Can, RequirePermission, useAccess } from '@/components/permissions/gate'

const statusLabels: Record<string, { key: string; variant: 'destructive' | 'warning' | 'secondary' | 'success' | 'outline' }> = {
  out_of_stock: { key: 'status_out_of_stock', variant: 'destructive' },
  low_stock: { key: 'status_low_stock', variant: 'warning' },
  expiring_soon: { key: 'status_expiring_soon', variant: 'secondary' },
  quarantined: { key: 'status_quarantined', variant: 'outline' },
  normal: { key: 'status_normal', variant: 'success' },
}

function formatQuantity(item: PharmacyInventoryItem, t: Translator): string {
  if (item.packaging_type === 'BOX_STRIP') {
    const boxes = Math.floor(item.quantity / item.units_per_box)
    const strips = item.quantity % item.units_per_box
    if (boxes === 0 && strips === 0) return t('qty_out_of_stock')
    if (boxes === 0) return t('qty_strips_only', { count: fmtNumber(strips) })
    if (strips === 0) return t('qty_boxes_only', { count: fmtNumber(boxes) })
    return t('qty_box_and_strip', { boxes: fmtNumber(boxes), strips: fmtNumber(strips) })
  }
  return `${fmtNumber(item.quantity)} ${t('units_pack')}`
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
  const t = useT('inventory')
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
      setFormError(t('error_amount_positive'))
      return
    }
    setSaving(true)
    try {
      await pharmacyApi.adjustBatchStock(item.batch_id, delta, reason.trim(), crypto.randomUUID())
      onSaved()
      onClose()
    } catch (err) {
      setFormError(err instanceof Error ? err.message : t('error_adjust_failed'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal isOpen onClose={onClose}>
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-bold">{t('adjust_title')}</h3>
          <Button variant="ghost" size="sm" onClick={onClose}>{t('close')}</Button>
        </div>

        <p className="text-sm text-muted-foreground">
          {t('adjust_product_batch', { name: item.product_name, batch: item.batch_number })}
          <span className="mt-1 block font-semibold text-foreground">{t('adjust_current_quantity', { quantity: formatQuantity(item, t) })}</span>
        </p>

        <div className="grid grid-cols-2 gap-2">
          <Button type="button" variant={direction === 'add' ? 'default' : 'outline'} size="sm" onClick={() => setDirection('add')}>{t('adjust_add')}</Button>
          <Button type="button" variant={direction === 'remove' ? 'destructive' : 'outline'} size="sm" onClick={() => setDirection('remove')}>{t('adjust_remove')}</Button>
        </div>

        {isBoxStrip ? (
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('adjust_boxes')} type="number" min={0} value={boxes} onChange={(e) => setBoxes(e.target.value)} inputMode="numeric" />
            <Input label={t('adjust_strips')} type="number" min={0} value={strips} onChange={(e) => setStrips(e.target.value)} inputMode="numeric" />
          </div>
        ) : (
          <Input label={t('adjust_packs')} type="number" min={0} value={boxes} onChange={(e) => setBoxes(e.target.value)} inputMode="numeric" />
        )}

        <Input label={t('adjust_reason_label')} value={reason} onChange={(e) => setReason(e.target.value)} placeholder={t('adjust_reason_placeholder')} />

        {amount > 0 && (
          <p className={`rounded-lg p-2.5 text-xs ${projected < 0 ? 'bg-destructive/10 text-destructive' : 'bg-muted text-muted-foreground'}`}>
            {t('adjust_after_quantity', { quantity: fmtNumber(projected) })}
            {projected < 0 && t('adjust_negative_warning')}
          </p>
        )}

        {formError && <p className="text-sm text-destructive">{formError}</p>}

        <div className="flex gap-2">
          <Button className="flex-1" loading={saving} onClick={submit} disabled={projected < 0}>
            {direction === 'add' ? t('adjust_submit_add') : t('adjust_submit_remove')}
          </Button>
          <Button variant="outline" onClick={onClose}>{t('cancel')}</Button>
        </div>
      </div>
    </Modal>
  )
}

export default function InventoryPage() {
  const t = useT('inventory')
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
      .catch((err) => setError(err instanceof Error ? err.message : t('error_load_failed')))
      .finally(() => setLoading(false))
  }, [t])

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
          <h1 className="text-2xl font-bold">{t('title')}</h1>
          <p className="mt-2 text-sm text-muted-foreground">{t('subtitle')}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Can perm="pos.access">
            <Button asChild variant="outline"><Link href="/pos"><ShoppingCart className="h-4 w-4" />{t('open_pos')}</Link></Button>
          </Can>
          <Can perm="inventory.manage_products">
            <Button asChild><Link href="/inventory/new"><Plus className="h-4 w-4" />{t('add_product')}</Link></Button>
          </Can>
        </div>
      </div>

      <Card>
        <CardHeader className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <CardTitle className="flex items-center gap-2"><Package className="h-5 w-5 text-primary" />{t('all_items')}</CardTitle>
          <div className="relative w-full sm:max-w-xs">
            <Search className="absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder={t('search_placeholder')} className="h-10 w-full rounded-lg border border-input bg-background ps-3 pe-10 text-sm outline-none focus:ring-2 focus:ring-ring" />
          </div>
        </CardHeader>
        <CardContent>
          {loading && <p className="py-10 text-center text-muted-foreground">{t('loading')}</p>}
          {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
          {!loading && !error && filteredItems.length === 0 && <p className="py-10 text-center text-muted-foreground">{t('no_matches')}</p>}
          {!loading && !error && filteredItems.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[900px] text-end text-sm">
                <thead className="border-b text-xs text-muted-foreground">
                  <tr><th className="p-3">{t('th_product')}</th><th className="p-3">{t('th_batch')}</th><th className="p-3">{t('th_branch')}</th><th className="p-3">{t('th_quantity')}</th><th className="p-3">{t('th_expiry')}</th><th className="p-3">{t('th_status')}</th>{canSeeActions && <th className="p-3">{t('th_actions')}</th>}</tr>
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
                      <td className="p-3">{item.branch_name || t('all_branches')}</td>
                      <td className="p-3 font-semibold">
                        {item.quantity <= 0
                          ? <span className="text-destructive">{t('qty_out_of_stock')}</span>
                          : formatQuantity(item, t)}
                      </td>
                      <td className="p-3">{item.expiry_date || '—'}</td>
                      <td className="p-3">
                        <Badge variant={statusLabels[item.status]?.variant ?? 'outline'}>
                          {statusLabels[item.status] ? t(statusLabels[item.status].key) : item.status}
                        </Badge>
                      </td>
                      {canSeeActions && (
                      <td className="p-3">
                        <div className="flex gap-1.5">
                          {canManageProducts && (
                            <Button asChild variant="outline" size="sm" title={t('edit_title_attr')}>
                              <Link href={`/inventory/edit/${item.pharmacy_product_id}`}>
                                <Pencil className="h-3.5 w-3.5" />{t('edit')}
                              </Link>
                            </Button>
                          )}
                          {canAdjustStock && (
                            <Button variant={item.quantity <= 0 ? 'default' : 'ghost'} size="sm" onClick={() => setAdjustTarget(item)} title={t('stock_button_title')}>
                              <PackagePlus className="h-3.5 w-3.5" />{t('stock_button')}
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
