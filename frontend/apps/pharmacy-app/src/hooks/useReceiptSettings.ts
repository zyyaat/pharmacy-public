'use client'

import { useCallback, useEffect, useState } from 'react'
import { pharmacyApi, type ReceiptSettings } from '@/lib/api'
import { runtimeTranslator } from '@/i18n/runtime'

/** الافتراضي في الواجهة — مطابق لافتراضيات الخادم حتى يصل الرد الأول.
 *  نصوص الإيصال الافتراضية تُقرأ من كتالوج pos وقت النداء (تبع لغة الواجهة الحالية). */
export function defaultReceiptSettings(): ReceiptSettings {
  const t = runtimeTranslator('pos')
  return {
    paper_width_mm: 80,
    print_mode: 'auto',
    copies: 1,
    name_prefix: '',
    show_phone: true,
    show_address: true,
    show_cashier: true,
    show_thank_you: true,
    thank_you_text: t('defaultThankYou'),
    show_return_policy: true,
    return_policy_text: t('defaultReturnPolicy'),
  }
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
        cache = { ...defaultReceiptSettings(), ...response.data.receipt }
        return cache
      })
      .catch(() => defaultReceiptSettings())
      .finally(() => {
        inflight = null
      })
  }
  return inflight
}

export function useReceiptSettings() {
  const [settings, setSettings] = useState<ReceiptSettings>(defaultReceiptSettings)
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
    cache = { ...defaultReceiptSettings(), ...response.data.receipt }
    setSettings(cache)
    return cache
  }, [])

  return { settings, loading, save }
}
