'use client'

import type { ReactNode } from 'react'
import { getConfiguredPharmacyAppUrl, getPharmacyAppUrl } from '@/lib/app-links'

const configuredPharmacyAppUrl = getConfiguredPharmacyAppUrl()

export default function PharmacyAppLink({ children, className }: { children: ReactNode; className?: string }) {
  function handleClick(event: React.MouseEvent<HTMLAnchorElement>) {
    if (!configuredPharmacyAppUrl) {
      event.preventDefault()
      window.location.assign(`${getPharmacyAppUrl()}/register`)
    }
  }

  return (
    <a
      className={className}
      href={configuredPharmacyAppUrl ? `${configuredPharmacyAppUrl}/register` : '/register'}
      onClick={handleClick}
    >
      {children}
    </a>
  )
}