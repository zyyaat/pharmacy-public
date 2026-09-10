'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { Activity, ArrowUpRight, Building2, CheckCircle, CreditCard, Store, Users, ShieldAlert } from 'lucide-react'
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from '@/components/ui'
import { companiesApi } from '@/lib/api'
import { companyStatusLabel } from '@/lib/utils'
import { useAnalytics } from '@/hooks/useAnalytics'
import { useT } from '@/i18n/provider'
import { fmtDateTime, fmtNumber } from '@/i18n/format'
import type { Company } from '@/types'

export default function DashboardPage() {
  const { stats, loading, error } = useAnalytics()
  const t = useT('dashboard')
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
        if (!cancelled) setCompaniesError(err instanceof Error ? err.message : t('companies_error'))
      })
      .finally(() => {
        if (!cancelled) setCompaniesLoading(false)
      })
    return () => { cancelled = true }
  }, [t])

  const cards = stats
    ? [
        { label: t('stat_total_companies'), value: stats.totalCompanies, icon: Building2 },
        { label: t('stat_active_companies'), value: stats.activeCompanies, icon: CheckCircle },
        { label: t('stat_suspended_companies'), value: stats.suspendedCompanies, icon: ShieldAlert },
        { label: t('stat_total_pharmacies'), value: stats.totalPharmacies, icon: Store },
        { label: t('stat_total_users'), value: stats.totalUsers, icon: Users },
        { label: t('stat_active_users'), value: stats.activeUsers, icon: CheckCircle },
      ]
    : []

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-bold">{t('title')}</h1>
        <p className="mt-1 text-muted-foreground">{t('subtitle')}</p>
      </div>

      {(loading || companiesLoading) && <Card><CardContent className="p-8 text-center text-muted-foreground">{t('loading')}</CardContent></Card>}
      {error && !loading && <Card><CardContent className="p-8 text-center text-destructive">{error}</CardContent></Card>}
      {companiesError && !companiesLoading && <Card><CardContent className="p-8 text-center text-destructive">{companiesError}</CardContent></Card>}

      {!loading && !error && stats && (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
            {cards.map((card) => (
              <Card key={card.label}>
                <CardContent className="flex items-center justify-between p-6">
                  <div><p className="text-sm text-muted-foreground">{card.label}</p><p className="mt-3 text-3xl font-bold">{fmtNumber(card.value)}</p></div>
                  <div className="rounded-xl bg-primary/10 p-3 text-primary"><card.icon className="h-5 w-5" /></div>
                </CardContent>
              </Card>
            ))}
          </div>

          <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
            <Card className="lg:col-span-2">
              <CardHeader className="flex flex-row items-center justify-between">
                <CardTitle className="text-lg">{t('latest_companies')}</CardTitle>
                <Link href="/companies"><Button variant="ghost" size="sm">{t('view_all')} <ArrowUpRight className="ms-1 h-4 w-4 rotate-180 rtl-flip" /></Button></Link>
              </CardHeader>
              <CardContent>
                {companies.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">{t('no_companies')}</p>}
                <div className="space-y-3">
                  {companies.map((company) => (
                    <div key={company.id} className="flex items-center justify-between rounded-lg bg-background p-4">
                      <div className="flex items-center gap-3">
                        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 font-bold text-primary">{company.name.charAt(0)}</div>
                        <div><p className="font-medium">{company.name}</p><p className="text-sm text-muted-foreground">{t('users_count', { count: company.currentUsersCount })}</p></div>
                      </div>
                      <Badge variant={company.status === 'active' ? 'success' : company.status === 'suspended' ? 'destructive' : 'warning'}>{companyStatusLabel(company.status)}</Badge>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader><CardTitle className="text-lg">{t('recent_activity')}</CardTitle></CardHeader>
              <CardContent>
                {stats.recentActivity.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">{t('no_activity')}</p>}
                <div className="space-y-4">
                  {stats.recentActivity.map((item) => (
                    <div key={item.id} className="flex gap-3">
                      <div className="rounded-lg bg-primary/10 p-2 text-primary"><Activity className="h-4 w-4" /></div>
                      <div className="min-w-0 flex-1"><p className="text-sm">{item.description}</p><p className="mt-1 text-xs text-muted-foreground">{item.userName} · {fmtDateTime(item.timestamp)}</p></div>
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
