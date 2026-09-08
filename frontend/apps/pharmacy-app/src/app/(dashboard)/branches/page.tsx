'use client'

import { useEffect, useState } from 'react'
import { Store } from 'lucide-react'
import { pharmacyApi, type PharmacyBranch } from '@/lib/api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui'

export default function BranchesPage() {
  const [items, setItems] = useState<PharmacyBranch[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    pharmacyApi.getBranches()
      .then((response) => setItems(response.data))
      .catch((err) => setError(err instanceof Error ? err.message : 'تعذر تحميل الفروع'))
      .finally(() => setLoading(false))
  }, [])

  return (
    <div className="mx-auto max-w-[1500px] space-y-6">
      <div><h1 className="text-2xl font-bold">الفروع</h1><p className="mt-2 text-sm text-muted-foreground">فروع الصيدلية الحالية فقط</p></div>
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><Store className="h-5 w-5 text-primary" />الفروع المسجلة</CardTitle></CardHeader>
        <CardContent>
          {loading && <p className="py-10 text-center text-muted-foreground">جاري التحميل...</p>}
          {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
          {!loading && !error && items.length === 0 && <p className="py-10 text-center text-muted-foreground">لا توجد فروع مسجلة</p>}
          {!loading && !error && items.length > 0 && <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{items.map((item) => <div key={item.id} className="rounded-xl border border-border p-4"><div className="flex items-start justify-between gap-3"><div><h2 className="font-semibold">{item.name}</h2><p className="mt-1 text-sm text-muted-foreground">{item.city || item.address || 'بدون عنوان'}</p></div><span className="rounded-full bg-primary/10 px-2 py-1 text-xs text-primary">{item.is_active ? 'نشط' : 'متوقف'}</span></div><div className="mt-4 space-y-1 text-xs text-muted-foreground"><p>الكود: {item.code || '—'}</p><p>المدير: {item.manager_name || 'غير محدد'}</p><p>الهاتف: {item.phone || '—'}</p></div></div>)}</div>}
        </CardContent>
      </Card>
    </div>
  )
}
