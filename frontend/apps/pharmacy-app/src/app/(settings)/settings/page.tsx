'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { LoadingSpinner } from '@/components/ui'
import { useAccess } from '@/components/permissions/gate'
import { SETTINGS_SECTION_PERMISSIONS } from '@/lib/permissions'

/**
 * مدخل الإعدادات — يحوّل صامتًا لأول قسم يملكه المستخدم صلاحيته
 * (بدل تحويل ثابت لقسم قد يكون ممنوعًا عنه)، وإن لم يملك أي قسم يعيده للرئيسية.
 */
export default function SettingsIndexPage() {
  const router = useRouter()
  const { ready, allowedAny, fullAccess } = useAccess()

  function sectionAllowed(href: string): boolean {
    const required = SETTINGS_SECTION_PERMISSIONS[href]
    if (!required || required.length === 0) return fullAccess
    return allowedAny(required)
  }

  useEffect(() => {
    if (!ready) return
    // السلوك القديم: الفواتير والطباعة هي المدخل الافتراضي لمن يملكها،
    // وإلا فأول قسم مسموح — وإن لا شيء حوّل للرئيسية.
    const order = ['/settings/receipts', '/settings/import', '/settings/database']
    const first = order.find((href) => sectionAllowed(href))
    router.replace(first ?? '/')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, router])

  return (
    <div className="flex items-center justify-center py-24">
      <LoadingSpinner />
    </div>
  )
}
