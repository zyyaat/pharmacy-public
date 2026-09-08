'use client'

import { useEffect, useState } from 'react'
import { Users } from 'lucide-react'
import { pharmacyApi, type PharmacyEmployee } from '@/lib/api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui'

export default function EmployeesPage() {
  const [items, setItems] = useState<PharmacyEmployee[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    pharmacyApi.getEmployees()
      .then((response) => setItems(response.data))
      .catch((err) => setError(err instanceof Error ? err.message : 'تعذر تحميل الموظفين'))
      .finally(() => setLoading(false))
  }, [])

  return (
    <div className="mx-auto max-w-[1500px] space-y-6">
      <div><h1 className="text-2xl font-bold">الموظفون</h1><p className="mt-2 text-sm text-muted-foreground">موظفو الصيدلية الحالية فقط</p></div>
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><Users className="h-5 w-5 text-primary" />قائمة الموظفين</CardTitle></CardHeader>
        <CardContent>
          {loading && <p className="py-10 text-center text-muted-foreground">جاري التحميل...</p>}
          {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
          {!loading && !error && items.length === 0 && <p className="py-10 text-center text-muted-foreground">لا يوجد موظفون مسجلون</p>}
          {!loading && !error && items.length > 0 && <div className="overflow-x-auto"><table className="w-full min-w-[680px] text-right text-sm"><thead className="border-b text-xs text-muted-foreground"><tr><th className="p-3">الاسم</th><th className="p-3">البريد</th><th className="p-3">الوظيفة</th><th className="p-3">الفرع</th><th className="p-3">الحالة</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} className="border-b last:border-0"><td className="p-3 font-semibold">{item.display_name || `${item.first_name} ${item.last_name}`}</td><td className="p-3">{item.email}</td><td className="p-3">{item.job_title || '—'}</td><td className="p-3">{item.branch_name || '—'}</td><td className="p-3">{item.status === 'active' ? 'نشط' : 'غير نشط'}</td></tr>)}</tbody></table></div>}
        </CardContent>
      </Card>
    </div>
  )
}
