'use client'

// Task 90 — subscription awareness for the pharmacy frontend.
// The backend is the real gate; this provider only powers UX: banners,
// feature-aware sidebar hiding and the subscription page. Fetch failure
// fails open (same policy as usePermissions) so a hiccup never locks an
// entitled user out — the server still enforces everything.

import {
  createContext, useCallback, useContext, useEffect, useMemo, useState,
  type ReactNode,
} from 'react'
import { subscriptionApi, type MySubscription, type PublicPlan } from '@/lib/api'
import { useAuth } from '@/hooks/useAuth'

type SubscriptionState = {
  ready: boolean
  status: string | null
  statusLabel: string | null
  daysLeft: number | null
  planSlug: string | null
  features: string[] | null
  limits: Record<string, number> | null
  usage: Record<string, number> | null
  subscription: MySubscription | null
  plans: PublicPlan[]
  featureOn: (key: string) => boolean
  reload: () => Promise<void>
}

const SubscriptionContext = createContext<SubscriptionState | null>(null)

export function SubscriptionProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false)
  const [subscription, setSubscription] = useState<MySubscription | null>(null)
  const [plans, setPlans] = useState<PublicPlan[]>([])
  const { user } = useAuth()

  const reload = useCallback(async () => {
    if (!user) return
    try {
      const [sub, planList] = await Promise.all([
        subscriptionApi.get(),
        subscriptionApi.listPlans(),
      ])
      setSubscription(sub.data)
      setPlans(planList.data)
    } catch {
      // fail-open: leave previous state, mark ready so UI never stalls
      setSubscription((prev) => prev)
    } finally {
      setReady(true)
    }
  }, [user])

  useEffect(() => {
    if (!user) {
      // جلسة غير موجودة — صفّر الحالة (خروج/انتهاء جلسة)
      setSubscription(null)
      setPlans([])
      setReady(false)
      return
    }
    void reload()
  }, [user, reload])

  // Global subscription-blocked signal: apiFetch dispatches a window event
  // whenever the backend answers with subscription_expired/suspended/pending.
  // The provider reloads so banners reflect reality immediately.
  useEffect(() => {
    const handler = () => { void reload() }
    window.addEventListener('pharmacy:subscription-blocked', handler)
    return () => window.removeEventListener('pharmacy:subscription-blocked', handler)
  }, [reload])

  const value = useMemo<SubscriptionState>(() => {
    const status = subscription?.subscription?.status ?? null
    const features = subscription?.plan?.features ?? null
    return {
      ready,
      status,
      statusLabel: status,
      daysLeft: subscription?.subscription?.days_left ?? null,
      planSlug: subscription?.plan?.slug ?? null,
      features,
      limits: subscription?.plan?.limits ?? null,
      usage: subscription?.usage ?? null,
      subscription,
      plans,
      // fail-open: before data arrives, everything is visible
      featureOn: (key: string) => (features ? features.includes(key) : true),
      reload,
    }
  }, [ready, subscription, plans, reload])

  return <SubscriptionContext.Provider value={value}>{children}</SubscriptionContext.Provider>
}

export function useSubscription(): SubscriptionState {
  const ctx = useContext(SubscriptionContext)
  if (!ctx) {
    // Safe default when rendered outside the provider (auth screens…)
    return {
      ready: false, status: null, statusLabel: null, daysLeft: null,
      planSlug: null, features: null, limits: null, usage: null,
      subscription: null, plans: [],
      featureOn: () => true,
      reload: async () => {},
    }
  }
  return ctx
}
