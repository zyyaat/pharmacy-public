'use client'

import Link from 'next/link'
import { AlertTriangle, BarChart3, CalendarCheck, Package, Pill, Plus, TrendingUp, Users } from 'lucide-react'
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from '@/components/ui'
import { useT } from '@/i18n/provider'
import { fmtNumber } from '@/i18n/format'
import { usePharmacyDashboard } from '@/hooks/usePharmacyDashboard'
import { availabilityAr, boxWordAr } from '@/lib/product'
import { Can, RequirePermission, useAccess } from '@/components/permissions/gate'
import { firstAllowedPage } from '@/lib/permissions'

export default function DashboardPage() {
  const t = useT('dashboard')
  const { stats, loading, error } = usePharmacyDashboard()
  const { ready, allowedAny } = useAccess()

  const cards = stats
    ? [
        { label: t('total_products'), value: fmtNumber(stats.totalProducts), icon: Package, tone: 'primary' },
        { label: t('low_stock_products'), value: fmtNumber(stats.lowStockCount), icon: AlertTriangle, tone: 'warning' },
        { label: t('sales_units_today'), value: fmtNumber(stats.salesUnitsToday), icon: TrendingUp, tone: 'success' },
        { label: t('attendance_today'), value: `${fmtNumber(stats.activeToday)} / ${fmtNumber(stats.activeEmployees)}`, icon: Users, tone: 'info' },
      ]
    : []

  // الإجراءات السريعة تختفي إن لم تكن الصفحة نفسها متاحة للموظف
  const quickActions = [
    { label: t('nav_inventory'), href: '/inventory', icon: Package, anyOf: ['inventory.view'] },
    { label: t('nav_employees'), href: '/employees', icon: Users, anyOf: ['employees.view'] },
    { label: t('nav_attendance'), href: '/attendance', icon: CalendarCheck, anyOf: ['attendance.view'] },
    { label: t('nav_reports'), href: '/reports', icon: BarChart3, anyOf: ['reports.sales', 'reports.inventory', 'reports.movements', 'reports.financial', 'reports.employees'] },
  ].filter((action) => (ready ? allowedAny(action.anyOf) : false))

  return (
    <RequirePermission anyOf={['dashboard.view']} redirectTo={ready ? firstAllowedPage(allowedAny) : null}>
    <div className="mx-auto max-w-[1500px] space-y-6 animate-fade-in">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h1 className="text-2xl font-bold">{t('title')}</h1>
          <p className="mt-2 text-sm text-muted-foreground">{t('subtitle')}</p>
        </div>
        <Can anyOf={['inventory.manage_products']}>
          <Button asChild variant="gradient">
            <Link href="/inventory"><Plus className="h-4 w-4" />{t('add_product')}</Link>
          </Button>
        </Can>
      </div>

      {loading && <Card><CardContent className="p-8 text-center text-muted-foreground">{t('loading')}</CardContent></Card>}
      {error && !loading && <Card><CardContent className="p-8 text-center text-destructive">{error}</CardContent></Card>}

      {!loading && !error && stats && (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {cards.map((card) => (
              <Card key={card.label} className="relative overflow-hidden">
                <CardContent className="p-6">
                  <div className="flex items-start justify-between">
                    <div>
                      <p className="text-sm text-muted-foreground">{card.label}</p>
                      <p className="mt-3 text-2xl font-bold tracking-tight">{card.value}</p>
                    </div>
                    <div className={`rounded-xl p-3 ${card.tone === 'warning' ? 'bg-amber-500/10 text-amber-600' : card.tone === 'success' ? 'bg-emerald-500/10 text-emerald-600' : card.tone === 'info' ? 'bg-blue-500/10 text-blue-600' : 'bg-primary/10 text-primary'}`}>
                      <card.icon className="h-5 w-5" />
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>

          <div className="grid grid-cols-1 gap-6 xl:grid-cols-[1.55fr_1fr]">
            <Card>
              <CardHeader><CardTitle className="text-lg">{t('inventory_status')}</CardTitle><p className="text-xs text-muted-foreground">{t('inventory_status_desc')}</p></CardHeader>
              <CardContent className="space-y-4">
                {stats.lowStockItems.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">{t('no_low_stock')}</p>}
                {stats.lowStockItems.map((product) => (
                  <div key={`${product.name}-${product.quantity}`} className="rounded-xl border border-border/80 p-3.5">
                    <div className="flex items-center gap-3">
                      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-amber-500/10 text-amber-600"><Pill className="h-5 w-5" /></div>
                      <div className="min-w-0 flex-1"><p className="truncate text-sm font-semibold">{product.name}</p><p className="mt-1 truncate text-xs text-muted-foreground">{product.generic_name}</p></div>
                      <Badge variant="warning">{availabilityAr(product.quantity, product.strips)}</Badge>
                    </div>
                    <p className="mt-2 text-[11px] text-muted-foreground">{t('reorder_note', { min: boxWordAr(product.min_stock_level) })}</p>
                  </div>
                ))}
              </CardContent>
            </Card>
            <Card>
              <CardHeader><CardTitle className="text-lg">{t('quick_actions')}</CardTitle></CardHeader>
              <CardContent className="grid grid-cols-2 gap-3">
                {quickActions.map((action) => (
                  <Link key={action.label} href={action.href} className="flex flex-col items-center gap-2 rounded-xl border border-border bg-card px-3 py-4 text-center hover:border-primary/30">
                    <action.icon className="h-6 w-6 text-primary" /><span className="text-xs font-medium">{action.label}</span>
                  </Link>
                ))}
                {quickActions.length === 0 && (
                  <p className="col-span-2 py-6 text-center text-sm text-muted-foreground">{t('no_quick_actions')}</p>
                )}
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </div>
    </RequirePermission>
  )
}