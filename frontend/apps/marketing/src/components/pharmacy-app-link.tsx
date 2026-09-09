'use client'

import type { ReactNode } from 'react'
import { getConfiguredPharmacyAppUrl, getPharmacyAppUrl } from '@/lib/app-links'

const configuredPharmacyAppUrl = getConfiguredPharmacyAppUrl()

export default function PharmacyAppLink({ children, className }: { children: ReactNode; className?: string }) {
  function handleClick(event: React.MouseEvent<HTMLAnchorElement>) {
    if (!configuredPharmacyAppUrl) {
      event.preventDefault()
      // /start بوابة ذكية داخل التطبيق: مسجل دخوله → اللوحة، زائر → التسجيل
      window.location.assign(`${getPharmacyAppUrl()}/start`)
    }
  }

  return (
    <a
      className={className}
      href={configuredPharmacyAppUrl ? `${configuredPharmacyAppUrl}/start` : '/register'}
      onClick={handleClick}
    >
      {children}
    </a>
  )
}