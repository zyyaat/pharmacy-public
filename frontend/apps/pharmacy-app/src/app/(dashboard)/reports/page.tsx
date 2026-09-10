'use client'

import Link from 'next/link'
import { ArrowLeftRight, Boxes, ChevronLeft, ReceiptText } from 'lucide-react'
import { Card, CardContent } from '@/components/ui'
import { useAccess, RequirePermission } from '@/components/permissions/gate'

const reportCards = [
  {
    href: '/reports/sales',
    perm: 'reports.sales',
    icon: ReceiptText,
    title: 'تقرير المبيعات',
    description:
      'إجمالي المبيعات والمرتجعات والصافي، متوسط الفاتورة، رسم بياني يومي، والمنتجات الأكثر بيعاً خلال أي فترة.',
  },
  {
    href: '/reports/inventory',
    perm: 'reports.inventory',
    icon: Boxes,
    title: 'تقرير المخزون',
    description:
      'قيمة المخزون بالتكلفة وبسعر البيع، النواقص والنافد، مجموعات الصلاحية، وجدول بالمخزون الحالي.',
  },
  {
    href: '/reports/movements',
    perm: 'reports.movements',
    icon: ArrowLeftRight,
    title: 'تقرير حركات المخزون',
    description:
      'ملخص كل حركات الدخول والخروج حسب النوع (بيع، شراء، استرجاع، تسويات…) مع تفاصيل الحركات.',
  },
]

export default function ReportsPage() {
  // Task 43: كل تقرير يختفي كليًا عن من لا يملك صلاحيته — لا بطاقة «ممنوع»
  const { ready, allowed } = useAccess()
  const visible = ready ? reportCards.filter((card) => allowed(card.perm)) : []

  return (
    <RequirePermission anyOf={['reports.sales', 'reports.inventory', 'reports.movements', 'reports.financial', 'reports.employees']}>
    <div className="mx-auto max-w-5xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold">التقارير</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          تقارير جاهزة بأفضل المقاييس — كل تقرير قابل للطباعة أو الحفظ PDF بنفس هوية الموقع.
        </p>
      </div>

      {ready && visible.length === 0 ? (
        <Card>
          <CardContent className="py-14 text-center text-sm text-muted-foreground">
            لا تقارير متاحة لحسابك حاليًا — تواصل مع مالك الصيدلية لمنحك صلاحية التقارير المناسبة.
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {visible.map((report) => {
            const Icon = report.icon
            return (
              <Link key={report.href} href={report.href} className="group block">
                <Card className="h-full transition-colors group-hover:border-primary/40">
                  <CardContent className="flex h-full flex-col gap-3 p-5">
                    <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
                      <Icon className="h-5 w-5" />
                    </span>
                    <h2 className="text-base font-bold">{report.title}</h2>
                    <p className="flex-1 text-sm leading-relaxed text-muted-foreground">
                      {report.description}
                    </p>
                    <span className="inline-flex items-center gap-1 text-sm font-semibold text-primary">
                      فتح التقرير
                      <ChevronLeft className="h-4 w-4 transition-transform group-hover:-translate-x-0.5" />
                    </span>
                  </CardContent>
                </Card>
              </Link>
            )
          })}
        </div>
      )}
    </div>
    </RequirePermission>
  )
}
