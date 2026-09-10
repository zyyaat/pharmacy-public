'use client'

import { useEffect, useState } from 'react'
import { CalendarCheck } from 'lucide-react'
import { pharmacyApi, type PharmacyAttendance } from '@/lib/api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui'
import { RequirePermission } from '@/components/permissions/gate'
import { fmtDateTime } from '@/i18n/format'
import { useT } from '@/i18n/provider'

export default function AttendancePage() {
  const t = useT('employees')
  const [items, setItems] = useState<PharmacyAttendance[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    pharmacyApi.getAttendance()
      .then((response) => setItems(response.data))
      .catch((err) => setError(err instanceof Error ? err.message : t('attendanceLoadErrorFallback')))
      .finally(() => setLoading(false))
  }, [t])

  return (
    <RequirePermission anyOf={['attendance.view']}>
    <div className="mx-auto max-w-[1500px] space-y-6">
      <div><h1 className="text-2xl font-bold">{t('attendanceTitle')}</h1><p className="mt-2 text-sm text-muted-foreground">{t('attendanceSubtitle')}</p></div>
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><CalendarCheck className="h-5 w-5 text-primary" />{t('attendanceListTitle')}</CardTitle></CardHeader>
        <CardContent>
          {loading && <p className="py-10 text-center text-muted-foreground">{t('loading')}</p>}
          {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
          {!loading && !error && items.length === 0 && <p className="py-10 text-center text-muted-foreground">{t('attendanceEmpty')}</p>}
          {!loading && !error && items.length > 0 && <div className="overflow-x-auto"><table className="w-full min-w-[720px] text-end text-sm"><thead className="border-b text-xs text-muted-foreground"><tr><th className="p-3">{t('thEmployee')}</th><th className="p-3">{t('thBranch')}</th><th className="p-3">{t('thClockIn')}</th><th className="p-3">{t('thClockOut')}</th><th className="p-3">{t('thStatus')}</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} className="border-b last:border-0"><td className="p-3 font-semibold">{item.employee_name}</td><td className="p-3">{item.branch_name || '—'}</td><td className="p-3">{fmtDateTime(item.clock_in)}</td><td className="p-3">{item.clock_out ? fmtDateTime(item.clock_out) : '—'}</td><td className="p-3">{item.status === 'active' ? t('nowActive') : item.status === 'completed' ? t('completed') : item.status}</td></tr>)}</tbody></table></div>}
        </CardContent>
      </Card>
    </div>
    </RequirePermission>
  )
}
