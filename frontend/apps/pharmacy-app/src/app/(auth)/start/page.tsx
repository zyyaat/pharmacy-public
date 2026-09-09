"use client"

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/hooks/useAuth'
import BrandSplash from '@/components/brand-splash'

/**
 * /start — بوابة الدخول الذكية (نقطة وصول روابط التسويق "ابدأ الآن")
 * - عندك جلسة صالحة؟ → لوحة التحكم مباشرة
 * - زائر جديد؟ → صفحة إنشاء الحساب
 */
export default function StartPage() {
  const router = useRouter()
  const { user, loading } = useAuth()

  useEffect(() => {
    if (loading) return
    router.replace(user ? '/' : '/register')
  }, [loading, user, router])

  return <BrandSplash />
}
