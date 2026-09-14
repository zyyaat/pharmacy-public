'use client'

// تفاصيل مكتبة المنتجات — منتجات المكتبة + معالج الاستيراد الذكي
// (معاينة البوابات الثلاث ← قرارات الصيدلي ← تنفيذ ← نتيجة) + تبويب
// «التحديثات» بشاشة الفروقات وزر سحب التحديثات.

import Link from 'next/link'
import { useParams, useSearchParams } from 'next/navigation'
import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  AlertTriangle, ArrowDownUp, ArrowLeft, CheckCircle2, Copy, Download,
  Link2, RefreshCw, Search, ShieldCheck, SkipForward,
} from 'lucide-react'
import {
  librariesApi,
  type ImportCandidate,
  type ImportPreview,
  type LibraryDiff,
  type LibraryProductRow,
  type PharmacyLibrary,
} from '@/lib/libraries'
import { formatPiastres } from '@/lib/money'
import { fmtNumber } from '@/i18n/format'
import { useT } from '@/i18n/provider'
import { Badge, Button, Card, CardContent, Modal } from '@/components/ui'
import { RequirePermission, useAccess } from '@/components/permissions/gate'

type Decision = { action: 'create' | 'link' | 'skip'; pharmacy_product_id?: string }
type WizardStep = 'preview' | 'result'

const actionBadge: Record<string, { variant: 'default' | 'success' | 'warning' | 'secondary' | 'destructive'; key: string; icon: typeof Copy }> = {
  create_new: { variant: 'default', key: 'action_create', icon: Download },
  link_existing: { variant: 'success', key: 'action_link', icon: Link2 },
  already_have: { variant: 'secondary', key: 'action_have', icon: CheckCircle2 },
  plan_limited: { variant: 'destructive', key: 'action_plan', icon: AlertTriangle },
}

interface ExecuteResultShape {
  library_version: number
  applied: number
  products_created: number
  products_linked: number
  prices_updated: number
  skipped: Array<{ global_product_id: string; reason: string; product_name?: string }>
  plan: { products_used: number; products_limit: number }
}

// ---------------------------------------------------------------------------
// معالج الاستيراد — الخطوة 1: قرارات لكل مرشح، الخطوة 2: نتيجة التنفيذ.
// ---------------------------------------------------------------------------
function ImportWizard({ library, preview, onClose, onDone }: {
  library: PharmacyLibrary
  preview: ImportPreview
  onClose: () => void
  onDone: (result: ExecuteResultShape) => void
}) {
  const t = useT('libraries')
  const [decisions, setDecisions] = useState<Record<string, Decision>>(() => {
    const initial: Record<string, Decision> = {}
    for (const cand of preview.candidates) {
      if (cand.plan_limited || cand.suggested_action === 'plan_limited') {
        initial[cand.global_product_id] = { action: 'skip' }
      } else if (cand.suggested_action === 'link_existing') {
        const match = cand.matches?.[0]
        initial[cand.global_product_id] = match
          ? { action: 'link', pharmacy_product_id: match.pharmacy_product_id }
          : { action: 'create' }
      } else if (cand.suggested_action === 'already_have') {
        initial[cand.global_product_id] = { action: 'create' } // refresh price
      } else {
        initial[cand.global_product_id] = { action: 'create' }
      }
    }
    return initial
  })
  const [executing, setExecuting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const selected = preview.candidates.filter((c) => decisions[c.global_product_id]?.action !== 'skip')
  const willCreate = selected.filter(
    (c) => decisions[c.global_product_id]?.action === 'create' && !c.already_have,
  ).length

  const setDecision = (gpId: string, d: Decision) =>
    setDecisions((prev) => ({ ...prev, [gpId]: d }))

  const execute = async () => {
    setExecuting(true)
    setError(null)
    try {
      const items = selected.map((c) => ({
        global_product_id: c.global_product_id,
        action: decisions[c.global_product_id].action as 'create' | 'link',
        pharmacy_product_id: decisions[c.global_product_id].pharmacy_product_id,
      }))
      const r = await librariesApi.importExecute(library.id, items)
      onDone(r.data)
    } catch (err) {
      setError(err instanceof Error ? err.message : t('error_execute'))
    } finally {
      setExecuting(false)
    }
  }

  return (
    <Modal isOpen onClose={onClose}>
      <div className="space-y-4">
        <div>
          <h3 className="text-lg font-bold">{t('wizard_title', { name: library.name })}</h3>
          <p className="mt-1 text-xs text-muted-foreground">{t('wizard_subtitle')}</p>
        </div>

        <div className="grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
          <div className="rounded-lg bg-muted p-2 text-center"><p className="font-bold">{fmtNumber(preview.summary.create_new ?? 0)}</p><p className="text-muted-foreground">{t('summary_new')}</p></div>
          <div className="rounded-lg bg-muted p-2 text-center"><p className="font-bold">{fmtNumber(preview.summary.link_existing ?? 0)}</p><p className="text-muted-foreground">{t('summary_suspects')}</p></div>
          <div className="rounded-lg bg-muted p-2 text-center"><p className="font-bold">{fmtNumber(preview.summary.already_have ?? 0)}</p><p className="text-muted-foreground">{t('summary_have')}</p></div>
          <div className="rounded-lg bg-destructive/10 p-2 text-center"><p className="font-bold text-destructive">{fmtNumber(preview.summary.plan_limited ?? 0)}</p><p className="text-muted-foreground">{t('summary_plan')}</p></div>
        </div>

        <div className="max-h-[45vh] space-y-2 overflow-y-auto pe-1">
          {preview.candidates.map((cand: ImportCandidate) => {
            const d = decisions[cand.global_product_id] ?? { action: 'skip' as const }
            const badge = actionBadge[cand.suggested_action] ?? actionBadge.create_new
            const BadgeIcon = badge.icon
            return (
              <div key={cand.global_product_id} className="rounded-lg border border-border p-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="flex items-center gap-1.5 truncate text-sm font-semibold">
                      {cand.name}
                      {badge.variant === 'success' && <BadgeIcon className="h-3.5 w-3.5 text-emerald-500" />}
                    </p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      {cand.barcode ? t('with_barcode', { barcode: cand.barcode }) : t('no_barcode')}
                      {' · '}
                      {t('official_price', { price: formatPiastres(cand.official_price_piastres) })}
                    </p>
                    {cand.already_have && cand.my_price_piastres != null && (
                      <p className="mt-0.5 text-xs text-muted-foreground">{t('my_price', { price: formatPiastres(cand.my_price_piastres) })}</p>
                    )}
                  </div>
                  <Badge variant={badge.variant}>{t(badge.key)}</Badge>
                </div>

                {cand.matches && cand.matches.length > 0 && (
                  <div className="mt-2 rounded-lg bg-muted/60 p-2 text-xs">
                    <p className="font-semibold">{t('possible_matches')}</p>
                    <ul className="mt-1 space-y-1">
                      {cand.matches.slice(0, 3).map((m) => (
                        <li key={m.pharmacy_product_id} className="flex items-center justify-between gap-2">
                          <span className="truncate">{m.name}{m.barcode ? ` · ${m.barcode}` : ''}</span>
                          <button
                            type="button"
                            className={`rounded-md px-2 py-0.5 text-xs font-semibold ${d.action === 'link' && d.pharmacy_product_id === m.pharmacy_product_id ? 'bg-primary text-primary-foreground' : 'bg-background text-primary hover:bg-accent'}`}
                            onClick={() => setDecision(cand.global_product_id, { action: 'link', pharmacy_product_id: m.pharmacy_product_id })}
                          >
                            {t('link_this')}
                          </button>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}

                <div className="mt-2 flex gap-1.5">
                  {!cand.already_have && (
                    <button
                      type="button"
                      disabled={cand.plan_limited}
                      className={`rounded-md px-2.5 py-1 text-xs font-semibold disabled:opacity-40 ${d.action === 'create' ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-accent'}`}
                      onClick={() => setDecision(cand.global_product_id, { action: 'create' })}
                    >
                      {t('decide_create')}
                    </button>
                  )}
                  <button
                    type="button"
                    className={`rounded-md px-2.5 py-1 text-xs font-semibold ${d.action === 'skip' ? 'bg-destructive text-destructive-foreground' : 'bg-muted text-muted-foreground hover:bg-accent'}`}
                    onClick={() => setDecision(cand.global_product_id, { action: 'skip' })}
                  >
                    {t('decide_skip')}
                  </button>
                  {cand.plan_limited && (
                    <span className="ms-auto self-center text-xs font-semibold text-destructive">{t('plan_limited_note')}</span>
                  )}
                </div>
              </div>
            )
          })}
        </div>

        <p className="rounded-lg bg-primary/5 p-2.5 text-xs text-muted-foreground">{t('wizard_redlines')}</p>
        {error && <p className="text-sm text-destructive">{error}</p>}

        <div className="flex gap-2">
          <Button className="flex-1" loading={executing} onClick={execute} disabled={selected.length === 0}>
            {t('wizard_execute', { count: fmtNumber(selected.length), create: fmtNumber(willCreate) })}
          </Button>
          <Button variant="outline" onClick={onClose}>{t('cancel')}</Button>
        </div>
      </div>
    </Modal>
  )
}

function ResultModal({ result, onClose }: { result: ExecuteResultShape | null; onClose: () => void }) {
  const t = useT('libraries')
  if (!result) return null
  return (
    <Modal isOpen onClose={onClose}>
      <div className="space-y-4 text-center">
        <CheckCircle2 className="mx-auto h-12 w-12 text-emerald-500" />
        <h3 className="text-lg font-bold">{t('result_title')}</h3>
        <div className="grid grid-cols-3 gap-2 text-sm">
          <div className="rounded-lg bg-muted p-3"><p className="text-lg font-bold">{fmtNumber(result.prices_updated)}</p><p className="text-xs text-muted-foreground">{t('result_prices')}</p></div>
          <div className="rounded-lg bg-muted p-3"><p className="text-lg font-bold">{fmtNumber(result.products_created)}</p><p className="text-xs text-muted-foreground">{t('result_created')}</p></div>
          <div className="rounded-lg bg-muted p-3"><p className="text-lg font-bold">{fmtNumber(result.products_linked)}</p><p className="text-xs text-muted-foreground">{t('result_linked')}</p></div>
        </div>
        {result.skipped.length > 0 && (
          <div className="rounded-lg bg-warning/10 p-3 text-xs">
            <p className="flex items-center justify-center gap-1.5 font-semibold"><SkipForward className="h-3.5 w-3.5" />{t('result_skipped', { count: result.skipped.length })}</p>
            <ul className="mt-1 space-y-0.5 text-muted-foreground">
              {result.skipped.slice(0, 5).map((s) => (
                <li key={s.global_product_id}>{s.product_name || s.global_product_id} — {t(`skip_${s.reason}`, { defaultValue: s.reason })}</li>
              ))}
            </ul>
          </div>
        )}
        <p className="text-xs text-muted-foreground">{t('result_version', { version: fmtNumber(result.library_version) })}</p>
        <Button className="w-full" onClick={onClose}>{t('close')}</Button>
      </div>
    </Modal>
  )
}

// ---------------------------------------------------------------------------
// الصفحة
// ---------------------------------------------------------------------------
export default function LibraryDetailPage() {
  const t = useT('libraries')
  const params = useParams<{ id: string }>()
  const searchParams = useSearchParams()
  const libraryId = params.id
  const { allowed } = useAccess()
  const canImport = allowed('inventory.import')

  const [library, setLibrary] = useState<PharmacyLibrary | null>(null)
  const [products, setProducts] = useState<LibraryProductRow[]>([])
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [tab, setTab] = useState<'products' | 'updates'>('products')
  const [preview, setPreview] = useState<ImportPreview | null>(null)
  const [previewLoading, setPreviewLoading] = useState(false)
  const [pageError, setPageError] = useState<string | null>(null)
  const [result, setResult] = useState<ExecuteResultShape | null>(null)
  const [diff, setDiff] = useState<LibraryDiff | null>(null)
  const [diffLoading, setDiffLoading] = useState(false)
  const [syncing, setSyncing] = useState(false)

  const loadLibrary = useCallback(() => {
    librariesApi
      .get(libraryId)
      .then((r) => setLibrary(r.data))
      .catch((err) => setError(err instanceof Error ? err.message : t('error_load')))
  }, [libraryId, t])

  const loadProducts = useCallback(() => {
    setLoading(true)
    librariesApi
      .products(libraryId, search)
      .then((r) => {
        setProducts(r.data)
        setTotal(r.pagination.total)
      })
      .catch((err) => setError(err instanceof Error ? err.message : t('error_load')))
      .finally(() => setLoading(false))
  }, [libraryId, search, t])

  const loadDiff = useCallback(() => {
    setDiffLoading(true)
    librariesApi
      .diff(libraryId)
      .then((r) => setDiff(r.data))
      .catch(() => setDiff(null))
      .finally(() => setDiffLoading(false))
  }, [libraryId])

  useEffect(() => {
    loadLibrary()
  }, [loadLibrary])
  useEffect(() => {
    loadProducts()
  }, [loadProducts])
  useEffect(() => {
    if (tab === 'updates') loadDiff()
  }, [tab, loadDiff])

  const startPreview = async (mode: 'all' | 'selected', ids?: string[]) => {
    setPreviewLoading(true)
    setPageError(null)
    try {
      const r = await librariesApi.importPreview(libraryId, mode, ids)
      setPreview(r.data)
    } catch (err) {
      setPageError(err instanceof Error ? err.message : t('error_preview'))
    } finally {
      setPreviewLoading(false)
    }
  }

  // ?import=1 يفتح المعالج تلقائيًا (زر «استيراد» من قائمة المكتبات)
  useEffect(() => {
    if (searchParams.get('import') === '1' && library && canImport && !preview && !previewLoading) {
      startPreview('all')
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [library, canImport, searchParams])

  const pullUpdates = async () => {
    setSyncing(true)
    setPageError(null)
    try {
      await librariesApi.sync(libraryId)
      loadLibrary()
      loadDiff()
      loadProducts()
    } catch (err) {
      setPageError(err instanceof Error ? err.message : t('error_sync'))
    } finally {
      setSyncing(false)
    }
  }

  const statusBadge = useMemo(() => {
    if (!library) return null
    if (library.sync_status === 'up_to_date') return { variant: 'success' as const, key: 'status_up_to_date' }
    if (library.sync_status === 'update_available') return { variant: 'warning' as const, key: 'status_update_available' }
    return { variant: 'secondary' as const, key: 'status_not_imported' }
  }, [library])

  if (error) {
    return (
      <RequirePermission anyOf={['inventory.view']}>
        <div className="py-10 text-center text-destructive">{error}</div>
      </RequirePermission>
    )
  }

  return (
    <RequirePermission anyOf={['inventory.view']}>
      <div className="mx-auto max-w-[1500px] space-y-6">
        <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
          <div className="min-w-0">
            <Link href="/libraries" className="flex w-fit items-center gap-1 text-sm text-muted-foreground hover:text-primary">
              <ArrowLeft className="h-4 w-4 rtl-flip" />{t('back')}
            </Link>
            <h1 className="mt-1 flex flex-wrap items-center gap-2 text-2xl font-bold">
              {library?.name ?? '…'}
              {statusBadge && <Badge variant={statusBadge.variant}>{t(statusBadge.key)}</Badge>}
            </h1>
            {library && (
              <p className="mt-1 text-sm text-muted-foreground">
                {t('versions_line', {
                  mine: library.last_synced_version > 0 ? fmtNumber(library.last_synced_version) : '—',
                  latest: fmtNumber(library.version),
                  count: fmtNumber(library.product_count),
                })}
              </p>
            )}
          </div>
          {canImport && library && (
            <div className="flex flex-wrap gap-2">
              {library.sync_status === 'update_available' && (
                <Button variant="outline" loading={syncing} onClick={pullUpdates}>
                  <ArrowDownUp className="h-4 w-4" />{t('pull_updates')}
                </Button>
              )}
              <Button loading={previewLoading} onClick={() => startPreview('all')}>
                <Download className="h-4 w-4" />{t('import')}
              </Button>
            </div>
          )}
        </div>

        {pageError && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{pageError}</p>}

        <div className="flex gap-2 border-b border-border">
          <button
            type="button"
            onClick={() => setTab('products')}
            className={`-mb-px border-b-2 px-4 py-2.5 text-sm font-semibold ${tab === 'products' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}
          >
            {t('tab_products')}
          </button>
          {library && library.last_synced_version > 0 && (
            <button
              type="button"
              onClick={() => setTab('updates')}
              className={`-mb-px flex items-center gap-1.5 border-b-2 px-4 py-2.5 text-sm font-semibold ${tab === 'updates' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}
            >
              {t('tab_updates')}
              {library.pending_changes > 0 && (
                <span className="rounded-full bg-warning/15 px-2 py-0.5 text-xs font-bold text-foreground">{fmtNumber(library.pending_changes)}</span>
              )}
            </button>
          )}
        </div>

        {tab === 'products' && (
          <Card>
            <CardContent className="p-0">
              <div className="relative border-b border-border p-4">
                <Search className="absolute start-7 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <input
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder={t('search_placeholder')}
                  className="h-10 w-full rounded-lg border border-input bg-background ps-10 pe-3 text-sm outline-none focus:ring-2 focus:ring-ring sm:max-w-sm"
                />
              </div>
              {loading ? (
                <div className="space-y-2 p-4">{Array.from({ length: 5 }, (_, i) => <div key={i} className="h-12 animate-pulse rounded-lg bg-muted/60" />)}</div>
              ) : products.length === 0 ? (
                <p className="py-10 text-center text-sm text-muted-foreground">{t('no_products')}</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[760px] text-end text-sm">
                    <thead className="border-b text-xs text-muted-foreground">
                      <tr>
                        <th className="p-3 text-start">{t('th_product')}</th>
                        <th className="p-3">{t('th_barcode')}</th>
                        <th className="p-3">{t('th_official_price')}</th>
                        <th className="p-3">{t('th_my_price')}</th>
                        <th className="p-3">{t('th_status')}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {products.map((p) => (
                        <tr key={p.global_product_id} className="border-b last:border-0">
                          <td className="p-3 text-start">
                            <span className="flex items-center gap-1.5 font-semibold">
                              {p.name}
                              {p.is_verified && <ShieldCheck className="h-3.5 w-3.5 text-emerald-500" aria-label={t('verified')} />}
                            </span>
                            <span className="mt-0.5 block text-xs text-muted-foreground">{p.generic_name || p.brand_name}{p.strength ? ` · ${p.strength}` : ''}</span>
                          </td>
                          <td className="p-3">{p.barcode || '—'}</td>
                          <td className="p-3 font-bold">{formatPiastres(p.official_price_piastres)}</td>
                          <td className="p-3">{p.my_price_piastres != null ? formatPiastres(p.my_price_piastres) : '—'}</td>
                          <td className="p-3">
                            {p.already_have ? (
                              <Badge variant="secondary">{t('have_it')}</Badge>
                            ) : (
                              <Badge variant="outline">{t('new_for_me')}</Badge>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {total > products.length && (
                    <p className="border-t border-border p-3 text-center text-xs text-muted-foreground">
                      {t('showing_of', { shown: fmtNumber(products.length), total: fmtNumber(total) })}
                    </p>
                  )}
                </div>
              )}
            </CardContent>
          </Card>
        )}

        {tab === 'updates' && (
          <Card>
            <CardContent className="p-4">
              {diffLoading ? (
                <div className="space-y-2">{Array.from({ length: 4 }, (_, i) => <div key={i} className="h-10 animate-pulse rounded-lg bg-muted/60" />)}</div>
              ) : !diff || diff.changes.length === 0 ? (
                <p className="py-10 text-center text-sm text-muted-foreground">
                  {diff && diff.library.last_synced_version > 0 ? t('diff_empty') : t('diff_never_synced')}
                </p>
              ) : (
                <>
                  <div className="mb-4 flex flex-wrap items-center gap-2 text-xs">
                    {(['price_changed', 'added', 'removed', 'metadata_changed'] as const).map((k) =>
                      diff.counts[k] ? (
                        <Badge key={k} variant={k === 'removed' ? 'destructive' : k === 'price_changed' ? 'warning' : 'secondary'}>
                          {t(`change_${k}`)}: {fmtNumber(diff.counts[k])}
                        </Badge>
                      ) : null,
                    )}
                    {canImport && library?.sync_status === 'update_available' && (
                      <Button size="sm" className="ms-auto" loading={syncing} onClick={pullUpdates}>
                        <ArrowDownUp className="h-3.5 w-3.5" />{t('pull_updates')}
                      </Button>
                    )}
                  </div>
                  <ul className="space-y-2">
                    {diff.changes.map((ch) => (
                      <li key={`${ch.global_product_id}-${ch.change_type}`} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-border p-3">
                        <div className="min-w-0">
                          <p className="truncate text-sm font-semibold">{ch.product_name}</p>
                          <p className="text-xs text-muted-foreground">{t(`change_${ch.change_type}`)} · v{fmtNumber(ch.version)}</p>
                        </div>
                        <div className="text-sm">
                          {ch.change_type === 'price_changed' && ch.old_price_piastres != null && ch.new_price_piastres != null && (
                            <span className="font-semibold">
                              {formatPiastres(ch.old_price_piastres)} <RefreshCw className="inline h-3 w-3 text-muted-foreground" /> {formatPiastres(ch.new_price_piastres)}
                            </span>
                          )}
                          {ch.change_type === 'added' && ch.new_price_piastres != null && (
                            <Badge variant="secondary">{formatPiastres(ch.new_price_piastres)}</Badge>
                          )}
                          {ch.change_type === 'removed' && <Badge variant="destructive">{t('change_removed')}</Badge>}
                          {ch.change_type === 'metadata_changed' && <Badge variant="outline">{t('change_metadata_changed')}</Badge>}
                        </div>
                      </li>
                    ))}
                  </ul>
                  <p className="mt-3 rounded-lg bg-muted p-2.5 text-xs text-muted-foreground">{t('removed_note')}</p>
                </>
              )}
            </CardContent>
          </Card>
        )}

        {preview && library && (
          <ImportWizard
            library={library}
            preview={preview}
            onClose={() => setPreview(null)}
            onDone={(r) => {
              setPreview(null)
              setResult(r)
              loadLibrary()
              loadProducts()
              loadDiff()
            }}
          />
        )}
        <ResultModal result={result} onClose={() => setResult(null)} />
      </div>
    </RequirePermission>
  )
}
