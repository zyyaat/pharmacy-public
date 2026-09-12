'use client'

// Phase G — مودال الدفع المضمّن (Embedded / Pixel): فورم Paymob يُصيَّر
// داخل iframe في صفحة الاشتراك نفسها — العميل لا يخرج من الموقع إطلاقًا،
// وبيانات البطاقة لا تلمس خوادمنا (PCI على Paymob). التفعيل الفعلي يحدث
// حصرًا من ويبهوك Paymob الموثق خادميًا؛ الـ polling هنا للعرض فقط.

import { useCallback, useEffect, useRef, useState } from 'react'
import { CheckCircle2, CreditCard, Lock, ShieldAlert, X } from 'lucide-react'
import { Button } from '@/components/ui'
import {
  subscriptionApi, type CheckoutResponse, type PublicPlan,
} from '@/lib/api'
import { useT } from '@/i18n/provider'
import { fmtNumber } from '@/i18n/format'

type Phase = 'cycle' | 'creating' | 'iframe' | 'succeeded' | 'failed' | 'error'

const POLL_INTERVAL_MS = 3000
const POLL_MAX_MS = 10 * 60 * 1000 // 10 دقائق ثم إيقاف الـ polling

export function EmbeddedCheckoutModal({
  isOpen, plan, onClose, onActivated,
}: {
  isOpen: boolean
  plan: PublicPlan | null
  onClose: () => void
  onActivated: () => void
}) {
  const t = useT('subscription')
  const [phase, setPhase] = useState<Phase>('cycle')
  const [checkout, setCheckout] = useState<CheckoutResponse | null>(null)
  const [errorCode, setErrorCode] = useState<string | null>(null)
  const pollTimer = useRef<ReturnType<typeof setInterval> | null>(null)
  const startedAt = useRef(0)

  const stopPolling = useCallback(() => {
    if (pollTimer.current) {
      clearInterval(pollTimer.current)
      pollTimer.current = null
    }
  }, [])

  const reset = useCallback(() => {
    stopPolling()
    setPhase('cycle')
    setCheckout(null)
    setErrorCode(null)
  }, [stopPolling])

  const close = useCallback(() => {
    stopPolling()
    onClose()
  }, [onClose, stopPolling])

  // إغلاق المودال يعيد الحالة — جاهزًا لمحاولة جديدة
  useEffect(() => {
    if (!isOpen) reset()
  }, [isOpen, reset])

  useEffect(() => () => stopPolling(), [stopPolling])

  const startPolling = useCallback((paymentId: string) => {
    stopPolling()
    startedAt.current = Date.now()
    pollTimer.current = setInterval(async () => {
      if (Date.now() - startedAt.current > POLL_MAX_MS) {
        stopPolling()
        return
      }
      try {
        const res = await subscriptionApi.paymentStatus(paymentId)
        const status = res.data.status
        if (status === 'succeeded') {
          stopPolling()
          setPhase('succeeded')
          onActivated()
        } else if (status === 'failed' || status === 'cancelled' || status === 'voided') {
          stopPolling()
          setPhase('failed')
        }
      } catch {
        // هفحة شبكة أثناء الـ polling — نحاول مرة أخرى في الدورة القادمة
      }
    }, POLL_INTERVAL_MS)
  }, [onActivated, stopPolling])

  const startCheckout = useCallback(async (billingInterval: 'monthly' | 'yearly') => {
    if (!plan) return
    setPhase('creating')
    setErrorCode(null)
    try {
      const res = await subscriptionApi.checkout(plan.id, billingInterval)
      setCheckout(res.data)
      setPhase('iframe')
      startPolling(res.data.payment_id)
    } catch (err) {
      setErrorCode(err instanceof Error ? (err as { code?: string }).code ?? 'checkout_error' : 'checkout_error')
      setPhase('error')
    }
  }, [plan, startPolling])

  if (!isOpen || !plan) return null

  const currency = plan.currency || 'EGP'
  const egp = (piastres: number) => fmtNumber(piastres / 100) + ' ' + currency

  return (
    <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4" role="dialog" aria-modal="true">
      <div className="bg-background rounded-xl w-full max-w-lg max-h-[92vh] overflow-y-auto shadow-xl">
        <div className="flex items-center justify-between p-4 border-b border-border">
          <div className="flex items-center gap-2">
            <CreditCard className="h-5 w-5 text-primary" />
            <h3 className="font-bold">
              {phase === 'succeeded' ? t('checkout_success_title') : t('checkout_title')}
            </h3>
          </div>
          <button
            onClick={close}
            className="rounded-md p-1 hover:bg-muted transition-colors"
            aria-label={t('close')}
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="p-4 space-y-4">
          {/* اختيار دورة الفوترة */}
          {phase === 'cycle' && (
            <>
              <p className="text-sm text-muted-foreground">
                {t('cycle_title')}: <span className="font-semibold text-foreground">{plan.name_ar || plan.name}</span>
              </p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <button
                  onClick={() => void startCheckout('monthly')}
                  className="rounded-lg border border-border p-4 text-start hover:border-primary hover:ring-1 hover:ring-primary transition-all"
                >
                  <div className="text-sm text-muted-foreground">{t('month')}</div>
                  <div className="text-xl font-extrabold">{egp(plan.monthly_price_piastres)}</div>
                  <div className="text-xs text-muted-foreground mt-1">{t('per_month')}</div>
                </button>
                <button
                  onClick={() => void startCheckout('yearly')}
                  className="rounded-lg border border-border p-4 text-start hover:border-primary hover:ring-1 hover:ring-primary transition-all"
                >
                  <div className="text-sm text-muted-foreground">{t('year')}</div>
                  <div className="text-xl font-extrabold">{egp(plan.yearly_price_piastres)}</div>
                  <div className="text-xs text-muted-foreground mt-1">{t('per_year')}</div>
                </button>
              </div>
              <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <Lock className="h-3.5 w-3.5" />
                {t('checkout_secure_hint')}
              </p>
            </>
          )}

          {/* إنشاء النية */}
          {phase === 'creating' && (
            <div className="py-10 text-center text-muted-foreground animate-pulse">
              {t('checkout_loading')}
            </div>
          )}

          {/* الفورم المضمّن — قلب الطريقة المطلوبة */}
          {phase === 'iframe' && checkout && (
            <>
              <div className="rounded-lg overflow-hidden border border-border">
                <iframe
                  src={checkout.embed_url}
                  title={t('checkout_title')}
                  className="w-full h-[480px] bg-white"
                  allow="payment *; clipboard-write"
                />
              </div>
              <p className="flex items-center justify-center gap-2 text-sm text-muted-foreground animate-pulse">
                <span className="h-2 w-2 rounded-full bg-primary animate-ping" />
                {t('checkout_waiting')}
              </p>
            </>
          )}

          {/* النجاح */}
          {phase === 'succeeded' && (
            <div className="py-8 text-center space-y-4">
              <CheckCircle2 className="h-14 w-14 text-green-600 mx-auto" />
              <p className="text-lg font-semibold">{t('checkout_success')}</p>
              <p className="text-sm text-muted-foreground">{t('checkout_success_hint')}</p>
              <Button className="w-full" onClick={() => { onActivated(); close() }}>
                {t('done')}
              </Button>
            </div>
          )}

          {/* فشل الدفع — إعادة المحاولة ممكنة */}
          {phase === 'failed' && (
            <div className="py-8 text-center space-y-4">
              <ShieldAlert className="h-12 w-12 text-amber-600 mx-auto" />
              <p className="font-semibold">{t('checkout_failed')}</p>
              <div className="grid grid-cols-2 gap-2">
                <Button variant="outline" onClick={reset}>{t('retry')}</Button>
                <Button variant="outline" onClick={close}>{t('close')}</Button>
              </div>
            </div>
          )}

          {/* خطأ بدء الدفع (شبكة/إعداد) */}
          {phase === 'error' && (
            <div className="py-8 text-center space-y-4">
              <ShieldAlert className="h-12 w-12 text-destructive mx-auto" />
              <p className="font-semibold">
                {errorCode === 'paymob_not_configured'
                  ? t('paymob_not_configured')
                  : t('checkout_error')}
              </p>
              <div className="grid grid-cols-2 gap-2">
                {errorCode !== 'paymob_not_configured' && (
                  <Button variant="outline" onClick={reset}>{t('retry')}</Button>
                )}
                <Button variant="outline" onClick={close}>{t('close')}</Button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
