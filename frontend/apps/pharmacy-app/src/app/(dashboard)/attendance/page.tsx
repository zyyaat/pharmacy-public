'use client'

import { useEffect, useState } from 'react'
import { CalendarCheck } from 'lucide-react'
import { pharmacyApi, type PharmacyAttendance } from '@/lib/api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui'

export default function AttendancePage() {
  const [items, setItems] = useState<PharmacyAttendance[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    pharmacyApi.getAttendance()
      .then((response) => setItems(response.data))
      .catch((err) => setError(err instanceof Error ? err.message : 'تعذر تحميل الحضور'))
      .finally(() => setLoading(false))
  }, [])

  return (
    <div className="mx-auto max-w-[1500px] space-y-6">
      <div><h1 className="text-2xl font-bold">الحضور والانصراف</h1><p className="mt-2 text-sm text-muted-foreground">سجلات الحضور الحقيقية للصيدلية الحالية</p></div>
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><CalendarCheck className="h-5 w-5 text-primary" />سجل الحضور</CardTitle></CardHeader>
        <CardContent>
          {loading && <p className="py-10 text-center text-muted-foreground">جاري التحميل...</p>}
          {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
          {!loading && !error && items.length === 0 && <p className="py-10 text-center text-muted-foreground">لا توجد سجلات حضور بعد</p>}
          {!loading && !error && items.length > 0 && <div className="overflow-x-auto"><table className="w-full min-w-[720px] text-right text-sm"><thead className="border-b text-xs text-muted-foreground"><tr><th className="p-3">الموظف</th><th className="p-3">الفرع</th><th className="p-3">الدخول</th><th className="p-3">الخروج</th><th className="p-3">الحالة</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} className="border-b last:border-0"><td className="p-3 font-semibold">{item.employee_name}</td><td className="p-3">{item.branch_name || '—'}</td><td className="p-3">{new Date(item.clock_in).toLocaleString('ar-EG')}</td><td className="p-3">{item.clock_out ? new Date(item.clock_out).toLocaleString('ar-EG') : '—'}</td><td className="p-3">{item.status === 'active' ? 'حاضر الآن' : item.status === 'completed' ? 'مكتمل' : item.status}</td></tr>)}</tbody></table></div>}
        </CardContent>
      </Card>
    </div>
  )
}
