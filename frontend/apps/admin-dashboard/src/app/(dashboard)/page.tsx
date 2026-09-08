'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { Activity, ArrowUpRight, Building2, CheckCircle, CreditCard, Store, Users, ShieldAlert } from 'lucide-react'
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from '@/components/ui'
import { companiesApi } from '@/lib/api'
import { useAnalytics } from '@/hooks/useAnalytics'
import type { Company } from '@/types'

const labels: Record<string, string> = {
  active: 'نشط',
  trial: 'تجريبي',
  suspended: 'موقوف',
  cancelled: 'ملغي',
}

const formatNumber = (value: number) => new Intl.NumberFormat('ar-EG').format(value)

export default function DashboardPage() {
  const { stats, loading, error } = useAnalytics()
  const [companies, setCompanies] = useState<Company[]>([])
  const [companiesLoading, setCompaniesLoading] = useState(true)
  const [companiesError, setCompaniesError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    companiesApi.list({ page: 1, limit: 5 })
      .then((response) => {
        if (!cancelled) {
          setCompanies(response.data)
          setCompaniesError(null)
        }
      })
      .catch((err) => {
        if (!cancelled) setCompaniesError(err instanceof Error ? err.message : 'تعذر تحميل الشركات')
      })
      .finally(() => {
        if (!cancelled) setCompaniesLoading(false)
      })
    return () => { cancelled = true }
  }, [])

  const cards = stats
    ? [
        { label: 'إجمالي الشركات', value: stats.totalCompanies, icon: Building2 },
        { label: 'الشركات النشطة', value: stats.activeCompanies, icon: CheckCircle },
        { label: 'الشركات الموقوفة', value: stats.suspendedCompanies, icon: ShieldAlert },
        { label: 'إجمالي الصيدليات', value: stats.totalPharmacies, icon: Store },
        { label: 'إجمالي المستخدمين', value: stats.totalUsers, icon: Users },
        { label: 'المستخدمون النشطون', value: stats.activeUsers, icon: CheckCircle },
      ]
    : []

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-bold">لوحة التحكم</h1>
        <p className="mt-1 text-muted-foreground">نظرة عامة على منصة Pharmacy OS بالكامل</p>
      </div>

      {(loading || companiesLoading) && <Card><CardContent className="p-8 text-center text-muted-foreground">جاري تحميل بيانات لوحة التحكم...</CardContent></Card>}
      {error && !loading && <Card><CardContent className="p-8 text-center text-destructive">{error}</CardContent></Card>}
      {companiesError && !companiesLoading && <Card><CardContent className="p-8 text-center text-destructive">{companiesError}</CardContent></Card>}

      {!loading && !error && stats && (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
            {cards.map((card) => (
              <Card key={card.label}>
                <CardContent className="flex items-center justify-between p-6">
                  <div><p className="text-sm text-muted-foreground">{card.label}</p><p className="mt-3 text-3xl font-bold">{formatNumber(card.value)}</p></div>
                  <div className="rounded-xl bg-primary/10 p-3 text-primary"><card.icon className="h-5 w-5" /></div>
                </CardContent>
              </Card>
            ))}
          </div>

          <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
            <Card className="lg:col-span-2">
              <CardHeader className="flex flex-row items-center justify-between">
                <CardTitle className="text-lg">أحدث الشركات</CardTitle>
                <Link href="/companies"><Button variant="ghost" size="sm">عرض الكل <ArrowUpRight className="mr-1 h-4 w-4 rotate-180" /></Button></Link>
              </CardHeader>
              <CardContent>
                {companies.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">لا توجد شركات مسجلة</p>}
                <div className="space-y-3">
                  {companies.map((company) => (
                    <div key={company.id} className="flex items-center justify-between rounded-lg bg-background p-4">
                      <div className="flex items-center gap-3">
                        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 font-bold text-primary">{company.name.charAt(0)}</div>
                        <div><p className="font-medium">{company.name}</p><p className="text-sm text-muted-foreground">{company.currentUsersCount} مستخدم</p></div>
                      </div>
                      <Badge variant={company.status === 'active' ? 'success' : company.status === 'suspended' ? 'destructive' : 'warning'}>{labels[company.status] || company.status}</Badge>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader><CardTitle className="text-lg">النشاط الأخير</CardTitle></CardHeader>
              <CardContent>
                {stats.recentActivity.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">لا يوجد نشاط مسجل</p>}
                <div className="space-y-4">
                  {stats.recentActivity.map((item) => (
                    <div key={item.id} className="flex gap-3">
                      <div className="rounded-lg bg-primary/10 p-2 text-primary"><Activity className="h-4 w-4" /></div>
                      <div className="min-w-0 flex-1"><p className="text-sm">{item.description}</p><p className="mt-1 text-xs text-muted-foreground">{item.userName} · {new Date(item.timestamp).toLocaleString('ar-EG')}</p></div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </div>
  )
}