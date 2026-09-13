'use client'

// Task 90 + Phase G + Standalone Checkout — صفحة الاشتراك: حالة الخطة
// الحالية + عدادات الاستهلاك + شبكة الخطط المتاحة (من إنشاء Super Admin).
// زر «اشترك الآن» ينقل لصفحة الدفع المستقلة كاملة (المعيار العالمي:
// Stripe Checkout وReplit وHostinger — لا نوافذ منبثقة): فورم Paymob
// داخل الموقع نفسه (بدون تحويل لصفحة خارجية)، والتأكيد الفعلي من ويبهوك
// Paymob الموثق. الصفحة ضمن allow-list الخادم: تعمل حتى مع اشتراك
// منتهٍ — مسار الاسترجاع.

import { useCallback, useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { AlertTriangle, Check, Crown, ReceiptText, RotateCcw, XCircle } from 'lucide-react'
import { Card, CardContent, Button, Badge } from '@/components/ui'
import { useSubscription } from '@/hooks/useSubscription'
import { useAccess } from '@/components/permissions/gate'
import { NoAccessCard } from '@/components/permissions/gate'
import { useT } from '@/i18n/provider'
import { fmtDate, fmtNumber } from '@/i18n/format'
import { subscriptionApi, type SubscriptionPayment } from '@/lib/api'

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
  const [payments, setPayments] = useState<SubscriptionPayment[]>([])
  const [capBusy, setCapBusy] = useState(false)
  const [capError, setCapError] = useState(false)

  const loadPayments = useCallback(async () => {
    try {
      const res = await subscriptionApi.payments()
      setPayments(res.data)
    } catch { /* السجل للعرض فقط — لا يعطل الصفحة */ }
  }, [])

  useEffect(() => { void loadPayments() }, [loadPayments])

  const toggleCancel = async () => {
    if (!subscription) return
    const cancelling = subscription.subscription?.cancel_at_period_end
    if (!cancelling && !window.confirm(t('cancel_confirm'))) return
    setCapBusy(true)
    try {
      if (cancelling) await subscriptionApi.resumeSubscription()
      else await subscriptionApi.cancelSubscription()
      setCapError(false)
      await reload()
      void loadPayments()
    } catch {
      setCapError(true)
    } finally {
      setCapBusy(false)
    }
  }

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
  const sub = subscription?.subscription
  const inGrace = !!sub?.in_grace
  const cancelling = !!sub?.cancel_at_period_end
  const canSelfService = (status === 'active' || status === 'trial') && !!sub

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

          {/* فترة السماح بعد الانتهاء — الوصول مستمر والتجديد عاجل */}
          {inGrace && (
            <div className="flex items-start gap-2 rounded-lg border border-amber-500/50 bg-amber-500/10 p-3 text-sm">
              <AlertTriangle className="h-4 w-4 text-amber-600 mt-0.5 shrink-0" />
              <span>
                {t('grace_notice', {
                  date: sub?.grace_ends_at ? fmtDate(sub.grace_ends_at, { dateStyle: 'long' }) : '',
                })}
              </span>
            </div>
          )}

          {/* الإلغاء الذاتي عند نهاية الفترة + الاستئناف */}
          {canSelfService && (
            <div className="space-y-2">
              <div className="flex flex-wrap items-center gap-3">
                {cancelling ? (
                  <>
                    <Badge variant="secondary">{t('cancel_pending')}</Badge>
                    <Button variant="outline" size="sm" disabled={capBusy} onClick={() => void toggleCancel()}>
                      <RotateCcw className="h-4 w-4 ms-1" />
                      {t('resume_cta')}
                    </Button>
                  </>
                ) : (
                  <Button variant="ghost" size="sm" className="text-destructive" disabled={capBusy} onClick={() => void toggleCancel()}>
                    <XCircle className="h-4 w-4 ms-1" />
                    {t('cancel_cta')}
                  </Button>
                )}
              </div>
              {capError && <p className="text-xs text-destructive">{t('cancel_failed')}</p>}
            </div>
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
                  {/* السعر: الشهرية إن وُجدت وإلا السنوية — الخطة بلا سعر
                      لا تُقدَّم للدفع إطلاقًا (بديلها: تواصل مع الدعم) */}
                  {p.monthly_price_piastres > 0 ? (
                    <div>
                      <span className="text-2xl font-extrabold">{egp(p.monthly_price_piastres)}</span>
                      <span className="text-sm text-muted-foreground">{t('per_month')}</span>
                    </div>
                  ) : p.yearly_price_piastres > 0 ? (
                    <div>
                      <span className="text-2xl font-extrabold">{egp(p.yearly_price_piastres)}</span>
                      <span className="text-sm text-muted-foreground">{t('per_year')}</span>
                    </div>
                  ) : (
                    <p className="text-sm font-medium text-muted-foreground">{t('plan_unpriced')}</p>
                  )}
                  {p.monthly_price_piastres > 0 && p.yearly_price_piastres > 0 && (
                    <div className="text-xs text-muted-foreground">
                      {egp(p.yearly_price_piastres)}{t('per_year')}
                    </div>
                  )}

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
                  ) : (p.monthly_price_piastres <= 0 && p.yearly_price_piastres <= 0) ? (
                    // خطة بلا سعر: لا زر اشتراك أصلًا — بدل زر ينتهي بخطأ
                    <p className="text-center text-xs text-muted-foreground">{t('plan_unpriced')}</p>
                  ) : (
                    <Button
                      className="w-full"
                      variant={p.sort_order >= (plan?.slug === 'enterprise' ? 4 : 0) ? 'default' : 'outline'}
                      onClick={() => router.push(`/settings/subscription/checkout?plan=${p.id}`)}
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

      {/* سجل المدفوعات — إيصالات هذا الحساب (أونلاين ويدوي) */}
      {payments.length > 0 && (
        <Card>
          <CardContent className="p-5 space-y-3">
            <div className="flex items-center gap-2">
              <ReceiptText className="h-5 w-5 text-primary" />
              <h2 className="text-lg font-semibold">{t('payments_title')}</h2>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-start text-muted-foreground border-b border-border">
                    <th className="py-2 text-start font-medium">{t('payments_col_date')}</th>
                    <th className="py-2 text-start font-medium">{t('payments_col_plan')}</th>
                    <th className="py-2 text-start font-medium">{t('payments_col_amount')}</th>
                    <th className="py-2 text-start font-medium">{t('payments_col_status')}</th>
                  </tr>
                </thead>
                <tbody>
                  {payments.map((p) => (
                    <tr key={p.id} className="border-b border-border/60">
                      <td className="py-2">{fmtDate(p.created_at, { dateStyle: 'medium' })}</td>
                      <td className="py-2">{p.plan.name_ar || p.plan.name}</td>
                      <td className="py-2 font-semibold">{egp(p.amount_piastres)}</td>
                      <td className="py-2">
                        <Badge variant={p.status === 'succeeded' ? 'success' : p.status === 'pending' ? 'warning' : p.status === 'refunded' ? 'secondary' : 'destructive'}>
                          {t(`payment_${p.status}`)}
                        </Badge>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}

      <p className="text-xs text-muted-foreground text-center pb-4">{t('contact_owner')}</p>
    </div>
  )
}
