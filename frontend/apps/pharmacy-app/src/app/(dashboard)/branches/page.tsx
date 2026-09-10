'use client'

import { useEffect, useState } from 'react'
import { Store } from 'lucide-react'
import { pharmacyApi, type PharmacyBranch } from '@/lib/api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui'
import { RequirePermission } from '@/components/permissions/gate'
import { useT } from '@/i18n/provider'

export default function BranchesPage() {
  const t = useT('employees')
  const [items, setItems] = useState<PharmacyBranch[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    pharmacyApi.getBranches()
      .then((response) => setItems(response.data))
      .catch((err) => setError(err instanceof Error ? err.message : t('branchesLoadErrorFallback')))
      .finally(() => setLoading(false))
  }, [t])

  return (
    <RequirePermission anyOf={['branches.view']}>
    <div className="mx-auto max-w-[1500px] space-y-6">
      <div><h1 className="text-2xl font-bold">{t('branchesTitle')}</h1><p className="mt-2 text-sm text-muted-foreground">{t('branchesSubtitle')}</p></div>
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><Store className="h-5 w-5 text-primary" />{t('branchesListTitle')}</CardTitle></CardHeader>
        <CardContent>
          {loading && <p className="py-10 text-center text-muted-foreground">{t('loading')}</p>}
          {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
          {!loading && !error && items.length === 0 && <p className="py-10 text-center text-muted-foreground">{t('branchesEmpty')}</p>}
          {!loading && !error && items.length > 0 && <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{items.map((item) => <div key={item.id} className="rounded-xl border border-border p-4"><div className="flex items-start justify-between gap-3"><div><h2 className="font-semibold">{item.name}</h2><p className="mt-1 text-sm text-muted-foreground">{item.city || item.address || t('noAddress')}</p></div><span className="rounded-full bg-primary/10 px-2 py-1 text-xs text-primary">{item.is_active ? t('branchActive') : t('branchStopped')}</span></div><div className="mt-4 space-y-1 text-xs text-muted-foreground"><p>{t('branchCodeLabel')} {item.code || '—'}</p><p>{t('branchManagerLabel')} {item.manager_name || t('unspecified')}</p><p>{t('branchPhoneLabel')} {item.phone || '—'}</p></div></div>)}</div>}
        </CardContent>
      </Card>
    </div>
    </RequirePermission>
  )
}
