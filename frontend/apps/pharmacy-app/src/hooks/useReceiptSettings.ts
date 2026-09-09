'use client'

import { useCallback, useEffect, useState } from 'react'
import { pharmacyApi, type ReceiptSettings } from '@/lib/api'

/** الافتراضي في الواجهة — مطابق لافتراضيات الخادم حتى يصل الرد الأول */
export const DEFAULT_RECEIPT_SETTINGS: ReceiptSettings = {
  paper_width_mm: 80,
  print_mode: 'auto',
  copies: 1,
  show_phone: true,
  show_address: true,
  show_cashier: true,
  show_thank_you: true,
  thank_you_text: 'شكراً لثقتكم — صحتك أمانة عندنا',
  show_return_policy: true,
  return_policy_text: 'الاسترجاع خلال 14 يوماً بالإيصال الأصلي',
}

// كاش على مستوى الوحدة: نقطة البيع وصفحة الإعدادات يتشاركان نفس الجلب،
// والحفظ يبطشه حتى التبويب الآخر يقرأ القيمة الجديدة.
let cache: ReceiptSettings | null = null
let inflight: Promise<ReceiptSettings> | null = null

export function invalidateReceiptSettingsCache() {
  cache = null
  inflight = null
}

export async function loadReceiptSettings(): Promise<ReceiptSettings> {
  if (cache) return cache
  if (!inflight) {
    inflight = pharmacyApi
      .getPharmacySettings()
      .then((response) => {
        cache = { ...DEFAULT_RECEIPT_SETTINGS, ...response.data.receipt }
        return cache
      })
      .catch(() => DEFAULT_RECEIPT_SETTINGS)
      .finally(() => {
        inflight = null
      })
  }
  return inflight
}

export function useReceiptSettings() {
  const [settings, setSettings] = useState<ReceiptSettings>(DEFAULT_RECEIPT_SETTINGS)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let alive = true
    loadReceiptSettings().then((value) => {
      if (alive) {
        setSettings(value)
        setLoading(false)
      }
    })
    return () => {
      alive = false
    }
  }, [])

  const save = useCallback(async (next: ReceiptSettings) => {
    const response = await pharmacyApi.updatePharmacySettings(next)
    cache = { ...DEFAULT_RECEIPT_SETTINGS, ...response.data.receipt }
    setSettings(cache)
    return cache
  }, [])

  return { settings, loading, save }
}
