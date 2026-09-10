'use client'

import { RequirePermission } from '@/components/permissions/gate'

export default function MedicationDetailPage() {
  return (
    <RequirePermission anyOf={['inventory.view']}>
      <div className="p-6">
        <h1 className="text-2xl font-bold">Medication Details</h1>
      </div>
    </RequirePermission>
  )
}
