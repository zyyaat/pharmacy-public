'use client'

import { useCallback, useEffect, useState } from 'react'
import { pharmacyApi, type PharmacyContext } from '@/lib/api'

/**
 * يجلب بيانات ترويسة التقرير (اسم الصيدلية/الفرع/المستخدم) مرة واحدة،
 * ويثبّت توقيت الإنشاء لحظة التحميل حتى لا يتغير عند الطباعة.
 */
export function useReportContext() {
  const [context, setContext] = useState<PharmacyContext | null>(null)
  const [generatedAt, setGeneratedAt] = useState(() => new Date().toISOString())

  // هوية ثابتة للدالة حتى لا تعيد الcallbacks المعتمدة عليها التغيّر كل render
  const refreshTimestamp = useCallback(() => setGeneratedAt(new Date().toISOString()), [])

  useEffect(() => {
    let active = true
    pharmacyApi
      .getContext()
      .then((value) => {
        if (active) setContext(value)
      })
      .catch(() => {
        // الترويسة تعمل حتى لو فشل جلب السياق — الاسم الافتراضي يظهر
      })
    return () => {
      active = false
    }
  }, [])

  return { context, generatedAt, refreshTimestamp }
}
