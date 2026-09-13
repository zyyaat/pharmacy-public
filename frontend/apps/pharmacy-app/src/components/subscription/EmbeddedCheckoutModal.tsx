'use client'

// Phase G — مودال الدفع المضمّن عبر **Pixel SDK** — الطريقة الرسمية من
// Paymob لتضمين الدفع داخل الصفحة (وليس iframe يدوي): الحقول تُصيَّر في
// Shadow DOM داخل عنصرنا، بأنماط وخطوط مضمّنة في الـ SDK نفسه، فتأخذ عرض
// الحاوية الطبيعي وتستجيب للـ RTL/اللغة — نفس تجربة Stripe Elements.
// العميل لا يخرج من الموقع إطلاقًا، وبيانات البطاقة لا تلمس خوادمنا (PCI
// على Paymob). التفعيل الفعلي يحدث حصرًا من ويبهوك Paymob الموثق خادميًا؛
// الـ polling هنا للعرض فقط. عند فشل تحميل الـ SDK (حجب CDN مثلًا) نرجع
// للـ iframe الرسمي (embed_url) كخطة بديلة حتى لا تتعطل الدفعة أبدًا.

import { useCallback, useEffect, useRef, useState } from 'react'
import { CheckCircle2, CreditCard, Lock, ShieldAlert, X } from 'lucide-react'
import { Button } from '@/components/ui'
import {
  subscriptionApi, type CheckoutResponse, type PublicPlan,
} from '@/lib/api'
import { useT } from '@/i18n/provider'
import { fmtNumber } from '@/i18n/format'

type Phase = 'cycle' | 'creating' | 'form' | 'succeeded' | 'failed' | 'error'

const POLL_INTERVAL_MS = 3000
const POLL_MAX_MS = 10 * 60 * 1000 // 10 دقائق ثم إيقاف الـ polling

// Pixel SDK الرسمي — إصدار مثبت للإنتاج (ترقيته قرار مقصود لا تلقائي).
// الحزمة self-contained: أنماط وخطوط وأيقونات مضمّنة، وتسجّل window.Pixel.
const PIXEL_SDK_URL = 'https://cdn.jsdelivr.net/npm/paymob-pixel@1.2.7/main.js'

type PixelOptions = {
  publicKey: string
  clientSecret: string
  paymentMethods: string[]
  elementId: string
  showSaveCard?: boolean
  customStyle?: Record<string, unknown>
  afterPaymentComplete?: (result: unknown) => void
  onPaymentCancel?: () => void
  cardValidationChanged?: (isValid: boolean) => void
}

declare global {
  interface Window {
    Pixel?: new (options: PixelOptions) => unknown
  }
}

let pixelLoader: Promise<void> | null = null

// تحميل الـ SDK مرة واحدة لكل صفحة (module script يسجّل window.Pixel).
function loadPixelSDK(): Promise<void> {
  if (typeof window === 'undefined') return Promise.reject(new Error('no_window'))
  if (window.Pixel) return Promise.resolve()
  if (pixelLoader) return pixelLoader
  pixelLoader = new Promise<void>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = PIXEL_SDK_URL
    script.type = 'module'
    script.async = true
    script.onload = () => {
      // بعض المتصفحات تشعل onload قبل اكتمال تقييم الـ module — ننتظر الرمز
      const deadline = Date.now() + 5000
      const check = () => {
        if (window.Pixel) resolve()
        else if (Date.now() > deadline) {
          pixelLoader = null
          reject(new Error('pixel_sdk_missing'))
        } else setTimeout(check, 50)
      }
      check()
    }
    script.onerror = () => {
      pixelLoader = null
      reject(new Error('pixel_sdk_load_failed'))
    }
    document.head.appendChild(script)
  })
  return pixelLoader
}

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
  const [sdkFailed, setSdkFailed] = useState(false)
  const pollTimer = useRef<ReturnType<typeof setInterval> | null>(null)
  const startedAt = useRef(0)
  const pixelRef = useRef<unknown>(null)
  // حاوية الـ Pixel: React يمتلك العنصر ويفرغه عند الخروج — ما يحقنه
  // الـ SDK داخله (Shadow DOM) يُزال معه تلقائيًا
  const pixelMountRef = useRef<HTMLDivElement | null>(null)

  const stopPolling = useCallback(() => {
    if (pollTimer.current) {
      clearInterval(pollTimer.current)
      pollTimer.current = null
    }
  }, [])

  const reset = useCallback(() => {
    stopPolling()
    pixelRef.current = null
    setPhase('cycle')
    setCheckout(null)
    setErrorCode(null)
    setSdkFailed(false)
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

  const checkOnce = useCallback(async (paymentId: string) => {
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
      // صفحة شبكة أثناء الـ polling — نحاول مرة أخرى في الدورة القادمة
    }
  }, [onActivated, stopPolling])

  const startPolling = useCallback((paymentId: string) => {
    stopPolling()
    startedAt.current = Date.now()
    pollTimer.current = setInterval(() => {
      if (Date.now() - startedAt.current > POLL_MAX_MS) {
        stopPolling()
        return
      }
      void checkOnce(paymentId)
    }, POLL_INTERVAL_MS)
  }, [checkOnce, stopPolling])

  const startCheckout = useCallback(async (billingInterval: 'monthly' | 'yearly') => {
    if (!plan) return
    setPhase('creating')
    setErrorCode(null)
    try {
      const res = await subscriptionApi.checkout(plan.id, billingInterval)
      setCheckout(res.data)
      setSdkFailed(false)
      setPhase('form')
      startPolling(res.data.payment_id)
    } catch (err) {
      setErrorCode(err instanceof Error ? (err as { code?: string }).code ?? 'checkout_error' : 'checkout_error')
      setPhase('error')
    }
  }, [plan, startPolling])

  // تركيب الـ Pixel الرسمي بمجرد دخول طور الدفع — الحقول تُصيَّر داخل
  // حاويتنا (Shadow DOM) بعرض كامل ولغة/اتجاه الصفحة نفسها.
  useEffect(() => {
    if (phase !== 'form' || !checkout) return
    let cancelled = false

    const dir: 'rtl' | 'ltr' =
      typeof document !== 'undefined' && document.documentElement.dir === 'ltr' ? 'ltr' : 'rtl'
    const ar = dir === 'rtl'

    loadPixelSDK()
      .then(() => {
        if (cancelled) return
        const container = pixelMountRef.current
        if (!container || !window.Pixel) {
          setSdkFailed(true)
          return
        }
        const elId = 'paymob-pixel-' + Math.random().toString(36).slice(2, 10)
        container.id = elId
        pixelRef.current = new window.Pixel({
          publicKey: checkout.public_key,
          clientSecret: checkout.client_secret,
          paymentMethods: ['card'],
          elementId: elId,
          showSaveCard: false,
          customStyle: {
            Direction: dir,
            Radius_Border: '12',
            Color_Primary: '#047857',            // أخضر الهوية
            Color_Container: '#ffffff',
            Color_Input_Fields: '#ffffff',
            Color_For_Text_Placeholder: '#9ca3af',
            Width_of_Container: '100%',
            Container_Padding: '0',
            Vertical_Padding: '8',
            Vertical_Spacing_between_components: '12',
            Font_Size_Label: '14',
            Font_Size_Input_Fields: '16',
            Font_Size_Payment_Button: '16',
            ...(ar
              ? {
                  Label_Text: {
                    cardLabel: 'بيانات البطاقة',
                    savedCardsLabel: 'البطاقات المحفوظة',
                    saveCardConsentLabel: 'حفظ البطاقة للدفع لاحقًا',
                    cardEndingLabel: 'تنتهي بـ',
                  },
                  Placeholder_Text: {
                    holderName: 'الاسم على البطاقة',
                    cardNumber: 'رقم البطاقة',
                    expiryDate: 'شهر / سنة',
                    securityCode: 'الرمز الأمني (CVV)',
                  },
                  Error_Text: {
                    cardNumber: { required: 'مطلوب رقم البطاقة', invalid: 'رقم البطاقة غير صحيح' },
                    expiryDate: { required: 'مطلوب تاريخ الانتهاء', invalid: 'تاريخ الانتهاء غير صحيح' },
                    securityCode: 'مطلوب الرمز الأمني (CVV)',
                    holderName: 'مطلوب اسم حامل البطاقة',
                  },
                  Button_Text: {
                    viewSavedCardsBtn: 'عرض البطاقات المحفوظة',
                    addNewCardBtn: 'إضافة بطاقة جديدة',
                    payBtn: 'ادفع الآن',
                  },
                  Hint_Text: {
                    saveCardConsentHint: 'سيتم حفظ تفاصيل البطاقة للاستخدام لاحقًا.',
                    cvvModalTitle: 'رمز CVV',
                    cvvVisaMastercardQuestion: 'هل لديك بطاقة ماستركارد أو فيزا؟',
                    cvvVisaMastercardHint: 'هو رمز مكوّن من 3 أرقام موجود على ظهر البطاقة.',
                    cvvAmexQuestion: 'هل لديك بطاقة أمريكان إكسبريس؟',
                    cvvAmexHint: 'هو رمز مكوّن من 4 أرقام موجود على وجه البطاقة.',
                  },
                }
              : {
                  Label_Text: {
                    cardLabel: 'Card details',
                    savedCardsLabel: 'Saved cards',
                    saveCardConsentLabel: 'Save card for future payments',
                    cardEndingLabel: 'Ending with',
                  },
                  Placeholder_Text: {
                    holderName: 'Cardholder name',
                    cardNumber: 'Card number',
                    expiryDate: 'MM / YY',
                    securityCode: 'Security code (CVV)',
                  },
                  Error_Text: {
                    cardNumber: { required: 'Card number is required', invalid: 'Invalid card number' },
                    expiryDate: { required: 'Expiry date is required', invalid: 'Invalid expiry date' },
                    securityCode: 'CVV is required',
                    holderName: 'Cardholder name is required',
                  },
                  Button_Text: {
                    viewSavedCardsBtn: 'View saved cards',
                    addNewCardBtn: 'Add new card',
                    payBtn: 'Pay now',
                  },
                  Hint_Text: {
                    saveCardConsentHint: 'Card details will be stored for future use.',
                    cvvModalTitle: 'CVV code',
                    cvvVisaMastercardQuestion: 'Do you have a Mastercard or Visa?',
                    cvvVisaMastercardHint: 'A 3-digit code on the back of the card.',
                    cvvAmexQuestion: 'Do you have an American Express card?',
                    cvvAmexHint: 'A 4-digit code on the front of the card.',
                  },
                }),
          },
          // إشارة UI فقط — الحقيقة تبقى من الويبهوك الموثق عبر الـ polling
          afterPaymentComplete: () => { void checkOnce(checkout.payment_id) },
          onPaymentCancel: () => { /* يبقى الفورم مفتوحًا لإعادة المحاولة */ },
        })
      })
      .catch(() => {
        if (!cancelled) setSdkFailed(true) // خطة بديلة: iframe الرسمي
      })

    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, checkout])

  if (!isOpen || !plan) return null

  const currency = plan.currency || 'EGP'
  const egp = (piastres: number) => fmtNumber(piastres / 100) + ' ' + currency

  return (
    // موبايل: ورقة بيضاء بملء الشاشة (المعيار العالمي للدفع المضمّن) —
    // دسكتوب: بطاقة مركزية بهوامش مريحة. سطح أبيض دائمًا: فورم الدفع أبيض
    // ومقروء فوقه مهما كان ثيم التطبيق.
    <div
      className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center sm:p-4"
      role="dialog"
      aria-modal="true"
    >
      <div className="bg-white w-full sm:max-w-md h-full sm:h-auto sm:max-h-[92vh] rounded-t-2xl sm:rounded-2xl shadow-xl flex flex-col overflow-hidden">
        {/* الرأس: الخطة + المبلغ + شارة الأمان — يظل مرئيًا أثناء التمرير */}
        <div className="shrink-0 px-4 py-3 border-b border-gray-100 bg-white">
          <div className="flex items-center justify-between gap-3">
            <button
              onClick={close}
              className="rounded-full p-2 text-gray-500 hover:bg-gray-100 transition-colors"
              aria-label={t('close')}
            >
              <X className="h-5 w-5" />
            </button>
            <div className="text-center min-w-0">
              <div className="text-sm font-bold text-gray-900 truncate">
                {phase === 'succeeded' ? t('checkout_success_title') : (plan.name_ar || plan.name)}
              </div>
              <div className="text-xs text-gray-500" dir="ltr">
                {egp(checkout?.amount_piastres ?? plan.monthly_price_piastres)}
              </div>
            </div>
            <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-50">
              <Lock className="h-4 w-4 text-emerald-700" />
            </div>
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {/* اختيار دورة الفوترة */}
          {phase === 'cycle' && (
            <>
              <p className="text-sm text-gray-500">
                {t('cycle_title')}: <span className="font-semibold text-gray-900">{plan.name_ar || plan.name}</span>
              </p>
              <div className="grid grid-cols-1 gap-3">
                <button
                  onClick={() => void startCheckout('monthly')}
                  className="flex items-center justify-between rounded-xl border border-gray-200 p-4 text-start hover:border-emerald-600 hover:ring-1 hover:ring-emerald-600 transition-all"
                >
                  <div>
                    <div className="text-sm font-semibold text-gray-900">{t('month')}</div>
                    <div className="text-xs text-gray-500 mt-0.5">{t('per_month')}</div>
                  </div>
                  <div className="text-lg font-extrabold text-gray-900">{egp(plan.monthly_price_piastres)}</div>
                </button>
                <button
                  onClick={() => void startCheckout('yearly')}
                  className="flex items-center justify-between rounded-xl border border-gray-200 p-4 text-start hover:border-emerald-600 hover:ring-1 hover:ring-emerald-600 transition-all"
                >
                  <div>
                    <div className="text-sm font-semibold text-gray-900">{t('year')}</div>
                    <div className="text-xs text-gray-500 mt-0.5">{t('per_year')}</div>
                  </div>
                  <div className="text-lg font-extrabold text-gray-900">{egp(plan.yearly_price_piastres)}</div>
                </button>
              </div>
              <p className="flex items-center gap-1.5 text-xs text-gray-500">
                <CreditCard className="h-3.5 w-3.5" />
                {t('checkout_secure_hint')}
              </p>
            </>
          )}

          {/* إنشاء النية */}
          {phase === 'creating' && (
            <div className="py-14 text-center text-gray-500 animate-pulse">
              {t('checkout_loading')}
            </div>
          )}

          {/* الفورم الرسمي المضمّن — Pixel SDK داخل الصفحة نفسها */}
          {phase === 'form' && checkout && (
            <>
              {sdkFailed ? (
                // خطة بديلة عند تعذّر تحميل الـ SDK: iframe Unified Checkout
                <div className="rounded-xl overflow-hidden border border-gray-200">
                  <iframe
                    src={checkout.embed_url}
                    title={t('checkout_title')}
                    className="w-full h-[480px] bg-white"
                    allow="payment *; clipboard-write"
                  />
                </div>
              ) : (
                <div ref={pixelMountRef} className="min-h-[300px]" aria-busy="true" />
              )}
              <p className="flex items-center justify-center gap-2 text-sm text-gray-500">
                <span className="h-2 w-2 rounded-full bg-emerald-600 animate-ping" />
                {t('checkout_waiting')}
              </p>
            </>
          )}

          {/* النجاح */}
          {phase === 'succeeded' && (
            <div className="py-10 text-center space-y-4">
              <CheckCircle2 className="h-14 w-14 text-emerald-600 mx-auto" />
              <p className="text-lg font-semibold text-gray-900">{t('checkout_success')}</p>
              <p className="text-sm text-gray-500">{t('checkout_success_hint')}</p>
              <Button className="w-full" onClick={() => { onActivated(); close() }}>
                {t('done')}
              </Button>
            </div>
          )}

          {/* فشل الدفع — إعادة المحاولة ممكنة */}
          {phase === 'failed' && (
            <div className="py-10 text-center space-y-4">
              <ShieldAlert className="h-12 w-12 text-amber-600 mx-auto" />
              <p className="font-semibold text-gray-900">{t('checkout_failed')}</p>
              <div className="grid grid-cols-2 gap-2">
                <Button variant="outline" onClick={reset}>{t('retry')}</Button>
                <Button variant="outline" onClick={close}>{t('close')}</Button>
              </div>
            </div>
          )}

          {/* خطأ بدء الدفع (شبكة/إعداد) */}
          {phase === 'error' && (
            <div className="py-10 text-center space-y-4">
              <ShieldAlert className="h-12 w-12 text-red-600 mx-auto" />
              <p className="font-semibold text-gray-900">
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
