'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { Package, Plus, Search, ShoppingCart } from 'lucide-react'
import { pharmacyApi, type PharmacyInventoryItem } from '@/lib/api'
import { Button, Card, CardContent, CardHeader, CardTitle } from '@/components/ui'

export default function InventoryPage() {
  const [items, setItems] = useState<PharmacyInventoryItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')

  useEffect(() => {
    pharmacyApi.getInventory()
      .then((response) => setItems(response.data))
      .catch((err) => setError(err instanceof Error ? err.message : 'تعذر تحميل المخزون'))
      .finally(() => setLoading(false))
  }, [])

  const filteredItems = items.filter((item) =>
    [item.product_name, item.generic_name, item.brand_name, item.barcode, item.batch_number]
      .join(' ')
      .toLowerCase()
      .includes(search.toLowerCase()),
  )

  return (
    <div className="mx-auto max-w-[1500px] space-y-6">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h1 className="text-2xl font-bold">المخزون والأدوية</h1>
          <p className="mt-2 text-sm text-muted-foreground">البيانات الفعلية للصيدلية الحالية فقط</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button asChild variant="outline"><Link href="/pos"><ShoppingCart className="h-4 w-4" />فتح نقطة البيع</Link></Button>
          <Button asChild><Link href="/inventory/new"><Plus className="h-4 w-4" />إضافة منتج</Link></Button>
        </div>
      </div>

      <Card>
        <CardHeader className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <CardTitle className="flex items-center gap-2"><Package className="h-5 w-5 text-primary" />الأصناف المتاحة</CardTitle>
          <div className="relative w-full sm:max-w-xs">
            <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="بحث بالاسم أو الباركود" className="h-10 w-full rounded-lg border border-input bg-background pl-3 pr-10 text-sm outline-none focus:ring-2 focus:ring-ring" />
          </div>
        </CardHeader>
        <CardContent>
          {loading && <p className="py-10 text-center text-muted-foreground">جاري تحميل المخزون...</p>}
          {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
          {!loading && !error && filteredItems.length === 0 && <p className="py-10 text-center text-muted-foreground">لا توجد أصناف مسجلة في هذه الصيدلية</p>}
          {!loading && !error && filteredItems.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[760px] text-right text-sm">
                <thead className="border-b text-xs text-muted-foreground">
                  <tr><th className="p-3">المنتج</th><th className="p-3">التشغيلة</th><th className="p-3">الفرع</th><th className="p-3">الكمية</th><th className="p-3">الصلاحية</th><th className="p-3">الحالة</th></tr>
                </thead>
                <tbody>
                  {filteredItems.map((item) => (
                    <tr key={item.batch_id} className="border-b last:border-0">
                      <td className="p-3"><Link href={`/inventory/${item.batch_id}`} className="font-semibold hover:text-primary">{item.product_name}</Link><span className="mt-1 block text-xs text-muted-foreground">{item.generic_name || item.brand_name || item.strength}</span></td>
                      <td className="p-3">{item.batch_number}</td>
                      <td className="p-3">{item.branch_name || 'كل الفروع'}</td>
                      <td className="p-3 font-semibold">
                        {item.packaging_type === 'BOX_STRIP'
                          ? `${Math.floor(item.quantity / item.units_per_box)} علبة و${item.quantity % item.units_per_box} شريط`
                          : `${new Intl.NumberFormat('ar-EG').format(item.quantity)} عبوة`}
                      </td>
                      <td className="p-3">{item.expiry_date || '—'}</td>
                      <td className="p-3">{item.status === 'low_stock' ? 'منخفض' : item.status === 'expiring_soon' ? 'قريب الانتهاء' : item.status === 'quarantined' ? 'محجوز' : 'طبيعي'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
