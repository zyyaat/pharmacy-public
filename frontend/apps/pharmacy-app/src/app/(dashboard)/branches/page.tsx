'use client'

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { Pencil, Plus, Store } from 'lucide-react'
import { Button, Card, CardContent, CardHeader, CardTitle } from '@/components/ui'
import { pharmacyApi, type PharmacyBranch } from '@/lib/api'
import { RequirePermission } from '@/components/permissions/gate'
import { useT } from '@/i18n/provider'

/**
 * تبويب الفروع — المكان الوحيد لإدارة مواقع الصيدلية (Task 50):
 * قائمة الفروع مع الفرع الرئيسي أولًا + إضافة فرع + تعديل كل فرع بنموذج
 * يعرض بياناته الحالية. تعديل الفرع الرئيسي يحدّث معلومات الصيدلية نفسها.
 */
export default function BranchesPage() {
  const t = useT('employees')
  const [items, setItems] = useState<PharmacyBranch[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const response = await pharmacyApi.getBranches()
      setItems(response.data)
    } catch (err) {
      setError(err instanceof Error ? err.message : t('branchesLoadErrorFallback'))
    } finally {
      setLoading(false)
    }
  }, [t])

  useEffect(() => {
    void load()
  }, [load])

  return (
    <RequirePermission anyOf={['branches.view']}>
      <div className="mx-auto max-w-[1500px] space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold">{t('branchesTitle')}</h1>
            <p className="mt-2 text-sm text-muted-foreground">{t('branchesSubtitle')}</p>
          </div>
          <Link href="/branches/new">
            <Button>
              <Plus className="h-4 w-4" aria-hidden="true" />
              {t('branchesAddBtn')}
            </Button>
          </Link>
        </div>
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Store className="h-5 w-5 text-primary" />
              {t('branchesListTitle')}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loading && <p className="py-10 text-center text-muted-foreground">{t('loading')}</p>}
            {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
            {!loading && !error && items.length === 0 && (
              <p className="py-10 text-center text-muted-foreground">{t('branchesEmpty')}</p>
            )}
            {!loading && !error && items.length > 0 && (
              <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                {items.map((item) => (
                  <div
                    key={item.id}
                    className={`rounded-xl border p-4 ${
                      item.is_main ? 'border-primary/30 bg-primary/5' : 'border-border'
                    } ${item.is_active ? '' : 'opacity-70'}`}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="flex flex-wrap items-center gap-2">
                          <h2 className="font-semibold">{item.name}</h2>
                          {item.is_main && (
                            <span className="rounded-full bg-primary px-2 py-0.5 text-xs font-bold text-primary-foreground">
                              {t('branchMainBadge')}
                            </span>
                          )}
                        </div>
                        {/* Task 52: العنوان والمدينة كلاهما بيانات حقيقية — لا نُخفي أحدهما كما كان يفعل city || address */}
                        <p className="mt-1 text-sm text-muted-foreground">
                          {[item.address, item.city].filter(Boolean).join('، ') || t('noAddress')}
                        </p>
                      </div>
                      <span className={`rounded-full px-2 py-1 text-xs ${item.is_active ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'}`}>
                        {item.is_active ? t('branchActive') : t('branchStopped')}
                      </span>
                    </div>
                    <div className="mt-4 space-y-1 text-xs text-muted-foreground">
                      <p>{t('branchCodeLabel')} {item.code || '—'}</p>
                      <p>{t('branchManagerLabel')} {item.manager_name || t('unspecified')}</p>
                      <p>{t('branchPhoneLabel')} {item.phone || '—'}</p>
                      <p>{t('branchEmailCardLabel')} {item.email || '—'}</p>
                    </div>
                    <div className="mt-4 border-t border-border pt-3">
                      <Link href={`/branches/${item.id}`}>
                        <Button variant="outline" size="sm" className="gap-1.5">
                          <Pencil className="h-3.5 w-3.5" aria-hidden="true" />
                          {t('branchEditBtn')}
                        </Button>
                      </Link>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </RequirePermission>
  )
}
