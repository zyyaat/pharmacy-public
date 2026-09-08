'use client'

import Link from 'next/link'
import { AlertTriangle, BarChart3, CalendarCheck, Package, Pill, Plus, TrendingUp, Users } from 'lucide-react'
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from '@/components/ui'
import { usePharmacyDashboard } from '@/hooks/usePharmacyDashboard'

const formatNumber = (value: number) => new Intl.NumberFormat('ar-EG').format(value)

export default function DashboardPage() {
  const { stats, loading, error } = usePharmacyDashboard()

  const cards = stats
    ? [
        { label: 'إجمالي المنتجات', value: formatNumber(stats.totalProducts), icon: Package, tone: 'primary' },
        { label: 'منتجات منخفضة المخزون', value: formatNumber(stats.lowStockCount), icon: AlertTriangle, tone: 'warning' },
        { label: 'حركات البيع اليوم', value: formatNumber(stats.salesUnitsToday), icon: TrendingUp, tone: 'success' },
        { label: 'الحضور اليوم', value: `${formatNumber(stats.activeToday)} / ${formatNumber(stats.activeEmployees)}`, icon: Users, tone: 'info' },
      ]
    : []

  return (
    <div className="mx-auto max-w-[1500px] space-y-6 animate-fade-in">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h1 className="text-2xl font-bold">لوحة التحكم</h1>
          <p className="mt-2 text-sm text-muted-foreground">بيانات الصيدلية الحالية من قاعدة البيانات</p>
        </div>
        <Button asChild variant="gradient">
          <Link href="/inventory"><Plus className="h-4 w-4" />إضافة منتج</Link>
        </Button>
      </div>

      {loading && <Card><CardContent className="p-8 text-center text-muted-foreground">جاري تحميل بيانات الصيدلية...</CardContent></Card>}
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
              <CardHeader><CardTitle className="text-lg">حالة المخزون</CardTitle><p className="text-xs text-muted-foreground">الأصناف التي وصلت إلى حد إعادة الطلب</p></CardHeader>
              <CardContent className="space-y-4">
                {stats.lowStockItems.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">لا توجد أصناف منخفضة المخزون</p>}
                {stats.lowStockItems.map((product) => (
                  <div key={`${product.name}-${product.quantity}`} className="rounded-xl border border-border/80 p-3.5">
                    <div className="flex items-center gap-3">
                      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-amber-500/10 text-amber-600"><Pill className="h-5 w-5" /></div>
                      <div className="min-w-0 flex-1"><p className="truncate text-sm font-semibold">{product.name}</p><p className="mt-1 truncate text-xs text-muted-foreground">{product.generic_name}</p></div>
                      <Badge variant="warning">{formatNumber(product.quantity)}</Badge>
                    </div>
                    <p className="mt-2 text-[11px] text-muted-foreground">الحد الأدنى: {formatNumber(product.min_stock_level)} وحدة</p>
                  </div>
                ))}
              </CardContent>
            </Card>
            <Card>
              <CardHeader><CardTitle className="text-lg">إجراءات سريعة</CardTitle></CardHeader>
              <CardContent className="grid grid-cols-2 gap-3">
                {[
                  { label: 'المخزون', href: '/inventory', icon: Package },
                  { label: 'الموظفون', href: '/employees', icon: Users },
                  { label: 'الحضور', href: '/attendance', icon: CalendarCheck },
                  { label: 'التقارير', href: '/reports', icon: BarChart3 },
                ].map((action) => (
                  <Link key={action.label} href={action.href} className="flex flex-col items-center gap-2 rounded-xl border border-border bg-card px-3 py-4 text-center hover:border-primary/30">
                    <action.icon className="h-6 w-6 text-primary" /><span className="text-xs font-medium">{action.label}</span>
                  </Link>
                ))}
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </div>
  )
}