'use client'

// مكتبات المنتجات — صفحة الصيدلية (المرحلة 2).
// بطاقات المكتبات المرئية حسب بلد الصيدلية مع حالة المزامنة وشارة
// «تحديث متاح»، وأزرار الاستيراد وسحب التحديثات.

import Link from 'next/link'
import { useCallback, useEffect, useState } from 'react'
import { ArrowDownUp, BookOpenCheck, CheckCircle2, Download, Library, RefreshCw } from 'lucide-react'
import { librariesApi, type PharmacyLibrary } from '@/lib/libraries'
import { fmtNumber } from '@/i18n/format'
import { useT } from '@/i18n/provider'
import { Badge, Button, Card, CardContent, Modal } from '@/components/ui'
import { RequirePermission, useAccess } from '@/components/permissions/gate'

const statusStyles: Record<string, { variant: 'success' | 'warning' | 'secondary'; icon: typeof CheckCircle2 }> = {
  up_to_date: { variant: 'success', icon: CheckCircle2 },
  update_available: { variant: 'warning', icon: RefreshCw },
  not_imported: { variant: 'secondary', icon: BookOpenCheck },
}

interface SyncResultShape {
  prices_updated: number
  products_added: number
  products_linked: number
  removed: Array<{ name: string }>
  skipped: Array<{ reason: string; product_name?: string }>
  nothing_to_do: boolean
}

function SyncResultModal({ result, onClose, libraryName }: { result: SyncResultShape | null; onClose: () => void; libraryName: string }) {
  const t = useT('libraries')
  if (!result) return null
  return (
    <Modal isOpen onClose={onClose}>
      <div className="space-y-4">
        <h3 className="text-lg font-bold">{t('sync_result_title', { name: libraryName })}</h3>
        {result.nothing_to_do ? (
          <p className="text-sm text-muted-foreground">{t('sync_nothing')}</p>
        ) : (
          <ul className="space-y-2 text-sm">
            <li className="flex justify-between rounded-lg bg-muted p-2.5"><span>{t('sync_prices_updated')}</span><span className="font-bold">{fmtNumber(result.prices_updated)}</span></li>
            <li className="flex justify-between rounded-lg bg-muted p-2.5"><span>{t('sync_products_added')}</span><span className="font-bold">{fmtNumber(result.products_added)}</span></li>
            <li className="flex justify-between rounded-lg bg-muted p-2.5"><span>{t('sync_products_linked')}</span><span className="font-bold">{fmtNumber(result.products_linked)}</span></li>
            {result.removed.length > 0 && (
              <li className="rounded-lg bg-warning/10 p-2.5 text-xs">
                <p className="font-semibold text-foreground">{t('sync_removed_count', { count: result.removed.length })}</p>
                <p className="mt-1 text-muted-foreground">{t('sync_removed_note')}</p>
              </li>
            )}
            {result.skipped.length > 0 && (
              <li className="rounded-lg bg-destructive/10 p-2.5 text-xs text-destructive">
                {t('sync_skipped_count', { count: result.skipped.length })}
              </li>
            )}
          </ul>
        )}
        <Button className="w-full" onClick={onClose}>{t('close')}</Button>
      </div>
    </Modal>
  )
}

export default function LibrariesPage() {
  const t = useT('libraries')
  const { allowed } = useAccess()
  const canImport = allowed('inventory.import')
  const [libs, setLibs] = useState<PharmacyLibrary[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [syncingId, setSyncingId] = useState<string | null>(null)
  const [syncResult, setSyncResult] = useState<SyncResultShape | null>(null)
  const [syncLibName, setSyncLibName] = useState('')
  const [actionError, setActionError] = useState<string | null>(null)

  const load = useCallback(() => {
    setLoading(true)
    setError(null)
    librariesApi
      .list()
      .then((r) => setLibs(r.data))
      .catch((err) => setError(err instanceof Error ? err.message : t('error_load')))
      .finally(() => setLoading(false))
  }, [t])

  useEffect(() => {
    load()
  }, [load])

  const pullUpdates = async (lib: PharmacyLibrary) => {
    setSyncingId(lib.id)
    setActionError(null)
    try {
      const r = await librariesApi.sync(lib.id)
      setSyncLibName(lib.name)
      setSyncResult(r.data)
      load()
    } catch (err) {
      setActionError(err instanceof Error ? err.message : t('error_sync'))
    } finally {
      setSyncingId(null)
    }
  }

  return (
    <RequirePermission anyOf={['inventory.view']}>
      <div className="mx-auto max-w-[1500px] space-y-6">
        <div>
          <h1 className="text-2xl font-bold">{t('title')}</h1>
          <p className="mt-2 text-sm text-muted-foreground">{t('subtitle')}</p>
        </div>

        {loading && (
          <div className="space-y-3">
            {Array.from({ length: 3 }, (_, i) => (
              <div key={i} className="h-28 animate-pulse rounded-xl bg-muted/60" />
            ))}
          </div>
        )}
        {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
        {actionError && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{actionError}</p>}
        {!loading && !error && libs.length === 0 && (
          <Card>
            <CardContent className="py-14 text-center">
              <Library className="mx-auto h-10 w-10 text-muted-foreground/50" />
              <p className="mt-3 text-sm text-muted-foreground">{t('empty')}</p>
            </CardContent>
          </Card>
        )}

        {!loading && !error && libs.length > 0 && (
          <div className="grid gap-4 lg:grid-cols-2">
            {libs.map((lib) => {
              const style = statusStyles[lib.sync_status] ?? statusStyles.not_imported
              const StatusIcon = style.icon
              return (
                <Card key={lib.id} className="flex flex-col">
                  <CardContent className="flex flex-1 flex-col gap-4 p-5">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <h3 className="truncate text-base font-bold">{lib.name}</h3>
                        {lib.description && <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">{lib.description}</p>}
                      </div>
                      <Badge variant={style.variant}>
                        <StatusIcon className="h-3 w-3" />
                        {t(`status_${lib.sync_status}`)}
                      </Badge>
                    </div>

                    <div className="grid grid-cols-3 gap-2 text-center">
                      <div className="rounded-lg bg-muted p-2">
                        <p className="text-xs text-muted-foreground">{t('products')}</p>
                        <p className="mt-0.5 text-sm font-bold">{fmtNumber(lib.product_count)}</p>
                      </div>
                      <div className="rounded-lg bg-muted p-2">
                        <p className="text-xs text-muted-foreground">{t('library_version')}</p>
                        <p className="mt-0.5 text-sm font-bold">v{fmtNumber(lib.version)}</p>
                      </div>
                      <div className="rounded-lg bg-muted p-2">
                        <p className="text-xs text-muted-foreground">{t('my_version')}</p>
                        <p className="mt-0.5 text-sm font-bold">{lib.last_synced_version > 0 ? `v${fmtNumber(lib.last_synced_version)}` : '—'}</p>
                      </div>
                    </div>

                    {lib.sync_status === 'update_available' && (
                      <p className="rounded-lg bg-warning/10 p-2.5 text-xs font-semibold text-foreground">
                        {t('update_available_hint', { changes: fmtNumber(lib.pending_changes), version: fmtNumber(lib.version) })}
                      </p>
                    )}
                    {lib.sync_status === 'not_imported' && (
                      <p className="text-xs text-muted-foreground">{t('not_imported_hint')}</p>
                    )}

                    <div className="mt-auto flex flex-wrap gap-2">
                      <Button asChild variant="outline" size="sm">
                        <Link href={`/libraries/${lib.id}`}><BookOpenCheck className="h-4 w-4" />{t('browse')}</Link>
                      </Button>
                      {canImport && (
                        <>
                          <Button asChild size="sm">
                            <Link href={`/libraries/${lib.id}?import=1`}><Download className="h-4 w-4" />{lib.sync_status === 'not_imported' ? t('import') : t('import_more')}</Link>
                          </Button>
                          {lib.sync_status === 'update_available' && (
                            <Button size="sm" loading={syncingId === lib.id} onClick={() => pullUpdates(lib)}>
                              <ArrowDownUp className="h-4 w-4" />{t('pull_updates')}
                            </Button>
                          )}
                        </>
                      )}
                    </div>
                  </CardContent>
                </Card>
              )
            })}
          </div>
        )}

        <SyncResultModal result={syncResult} libraryName={syncLibName} onClose={() => setSyncResult(null)} />
      </div>
    </RequirePermission>
  )
}
