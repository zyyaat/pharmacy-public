// Checkout كصفحة مستقلة — /settings/subscription/checkout?plan=<id>
// (المعيار العالمي: Stripe Checkout وReplit وHostinger يضعوا الدفع في
// صفحة كاملة لا في نافذة منبثقة). useSearchParams يتطلب Suspense boundary
// أثناء الـ prerender — المكوّن الفعلي داخله.
import { Suspense } from 'react'
import CheckoutClient from './CheckoutClient'

export default function SubscriptionCheckoutPage() {
  return (
    <Suspense fallback={<div className="min-h-[40vh]" />}>
      <CheckoutClient />
    </Suspense>
  )
}
