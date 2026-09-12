'use client'

// Task 90 + Phase G — صفحة الاشتراك: حالة الخطة الحالية + عدادات الاستهلاك
// + شبكة الخطط المتاحة (من إنشاء Super Admin). زر «اشترك الآن» يفتح مودال
// الدفع المضمّن: فورم Paymob داخل الموقع نفسه (بدون تحويل لصفحة خارجية)،
// والتأكيد الفعلي من ويبهوك Paymob الموثق. الصفحة ضمن allow-list الخادم:
// تعمل حتى مع اشتراك منتهٍ — مسار الاسترجاع.

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Check, Crown } from 'lucide-react'
import { Card, CardContent, Button, Badge } from '@/components/ui'
import { useSubscription } from '@/hooks/useSubscription'
import { useAccess } from '@/components/permissions/gate'
import { NoAccessCard } from '@/components/permissions/gate'
import { EmbeddedCheckoutModal } from '@/components/subscription/EmbeddedCheckoutModal'
import { useT } from '@/i18n/provider'
import { fmtDate, fmtNumber } from '@/i18n/format'
import type { PublicPlan } from '@/lib/api'

const LIMIT_LABELS: Record<string, string> = {
  branches: 'limit_branches',
  users: 'limit_users',
  employees: 'limit_employees',
  products: 'limit_products',
}

const FEATURE_LABELS: Record<string, string> = {
  pos: 'نقطة البيع', sales: 'المبيعات والفواتير', inventory: 'المخزون والأدوية',
  customers: 'حسابات العملاء', employees: 'الموظفون', attendance: 'الحضور والانصراف',
  branches: 'إدارة الفروع', reports: 'التقارير', multi_branch: 'فروع متعددة',
}

export default function SubscriptionPage() {
  const t = useT('subscription')
  const router = useRouter()
  const { ready: permsReady, allowedAny, fullAccess } = useAccess()
  const {
    ready, subscription, plans, status, daysLeft, limits, usage, reload,
  } = useSubscription()
  const [checkoutPlan, setCheckoutPlan] = useState<PublicPlan | null>(null)

  // نفس نمط أقسام الإعدادات: قسم محمي بصلاحية settings.billing
  useEffect(() => {
    if (permsReady && !fullAccess && !allowedAny(['settings.billing'])) {
      router.replace('/')
    }
  }, [permsReady, fullAccess, allowedAny, router])

  if (!permsReady) return null
  if (!fullAccess && !allowedAny(['settings.billing'])) return <NoAccessCard />

  const plan = subscription?.plan
  const currency = plan?.currency ?? 'EGP'
  const egp = (piastres: number) => fmtNumber(piastres / 100) + ' ' + currency

  const statusBadge = (s: string | null) => {
    if (!s) return null
    const variant = s === 'active' ? 'success' : s === 'trial' ? 'warning'
      : s === 'expired' || s === 'suspended' ? 'destructive' : 'secondary'
    return <Badge variant={variant}>{t(`status_${s}`)}</Badge>
  }

  const deadline = status === 'trial' ? subscription?.subscription?.trial_ends_at
    : subscription?.subscription?.current_period_end

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold">{t('title')}</h1>
        <p className="text-muted-foreground mt-1">{t('subtitle')}</p>
      </div>

      {/* الخطة الحالية */}
      <Card>
        <CardContent className="p-5 space-y-4">
          <div className="flex flex-wrap items-center gap-3">
            <Crown className="h-5 w-5 text-primary" />
            <h2 className="text-lg font-semibold">{t('plan_label')}</h2>
            {statusBadge(status)}
            {status === 'trial' && daysLeft !== null && (
              <span className="text-sm text-muted-foreground">
                {daysLeft <= 1 ? t('days_left_last') : t('days_left', { days: daysLeft })}
              </span>
            )}
          </div>
          {plan && (
            <>
              <div className="text-2xl font-bold">{plan.name_ar || plan.name}</div>
              {deadline && (
                <p className="text-sm text-muted-foreground">
                  {status === 'trial'
                    ? t('trial_ends', { date: fmtDate(deadline, { dateStyle: 'long' }) })
                    : t('renews_on', { date: fmtDate(deadline, { dateStyle: 'long' }) })}
                </p>
              )}
            </>
          )}

          {/* عدادات الاستهلاك */}
          {limits && usage && (
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 pt-2">
              {Object.entries(LIMIT_LABELS).map(([key, labelKey]) => {
                const limit = limits[key]
                const used = usage[key] ?? 0
                if (limit === undefined) return null
                const pct = limit > 0 ? Math.min(100, Math.round((used / limit) * 100)) : 0
                return (
                  <div key={key} className="rounded-lg border border-border p-3">
                    <div className="flex items-baseline justify-between text-sm">
                      <span className="text-muted-foreground">{t(labelKey)}</span>
                      <span className="font-semibold">
                        {fmtNumber(used)}
                        <span className="text-muted-foreground">
                          {' / '}{limit === -1 ? t('unlimited') : fmtNumber(limit)}
                        </span>
                      </span>
                    </div>
                    {limit > 0 && (
                      <div className="mt-2 h-1.5 rounded-full bg-muted overflow-hidden">
                        <div
                          className={`h-full rounded-full ${pct >= 100 ? 'bg-destructive' : pct >= 80 ? 'bg-amber-500' : 'bg-primary'}`}
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* الخطط المتاحة */}
      <div>
        <h2 className="text-lg font-semibold">{t('plans_title')}</h2>
        <p className="text-sm text-muted-foreground mt-0.5">{t('plans_subtitle')}</p>
      </div>

      {!ready ? (
        <div className="py-10 text-center text-muted-foreground">…</div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
          {plans.map((p) => {
            const isCurrent = plan?.id === p.id
            return (
              <Card key={p.id} className={isCurrent ? 'border-primary ring-1 ring-primary' : ''}>
                <CardContent className="p-5 space-y-3">
                  <div className="flex items-center justify-between">
                    <h3 className="font-bold">{p.name_ar || p.name}</h3>
                    {isCurrent && <Badge variant="default">{t('current_plan')}</Badge>}
                  </div>
                  <div>
                    <span className="text-2xl font-extrabold">{egp(p.monthly_price_piastres)}</span>
                    <span className="text-sm text-muted-foreground">{t('per_month')}</span>
                  </div>
                  <div className="text-xs text-muted-foreground">
                    {egp(p.yearly_price_piastres)}{t('per_year')}
                  </div>

                  {/* الميزات */}
                  <ul className="space-y-1.5 pt-1">
                    {(p.features ?? []).map((feature) => (
                      <li key={feature} className="flex items-center gap-2 text-sm">
                        <Check className="h-4 w-4 text-primary shrink-0" />
                        {FEATURE_LABELS[feature] ?? feature}
                      </li>
                    ))}
                  </ul>

                  {/* الحدود */}
                  <div className="flex flex-wrap gap-1.5 pt-1">
                    {Object.entries(p.limits ?? {}).map(([key, value]) => (
                      <span key={key} className="rounded-full bg-muted px-2 py-0.5 text-xs">
                        {t(LIMIT_LABELS[key] ?? key)}: {value === -1 ? t('unlimited') : fmtNumber(value)}
                      </span>
                    ))}
                  </div>

                  {isCurrent ? (
                    <Button className="w-full" disabled>{t('current_plan')}</Button>
                  ) : (
                    <Button
                      className="w-full"
                      variant={p.sort_order >= (plan?.slug === 'enterprise' ? 4 : 0) ? 'default' : 'outline'}
                      onClick={() => setCheckoutPlan(p)}
                    >
                      {t('subscribe_cta')}
                    </Button>
                  )}
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      <p className="text-xs text-muted-foreground text-center pb-4">{t('contact_owner')}</p>

      {/* الدفع المضمّن — فورم Paymob داخل الموقع نفسه */}
      <EmbeddedCheckoutModal
        isOpen={checkoutPlan !== null}
        plan={checkoutPlan}
        onClose={() => setCheckoutPlan(null)}
        onActivated={() => void reload()}
      />
    </div>
  )
}
