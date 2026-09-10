'use client'

import Link from 'next/link'
import { useCallback, useEffect, useState } from 'react'
import { ChevronLeft, ReceiptText, RotateCcw, Search } from 'lucide-react'
import { ApiError, pharmacyApi, type POSSaleSummary } from '@/lib/api'
import { formatPiastres } from '@/lib/money'
import { formatSaleDate, formatSaleTime, saleStatusLabel, saleStatusVariant } from '@/lib/sales'
import { Badge, Button, Card, CardContent, Input, LoadingSpinner } from '@/components/ui'
import { RequirePermission } from '@/components/permissions/gate'
import { useT } from '@/i18n/provider'

const PAGE_SIZE = 20

export default function SalesHistoryPage() {
  const t = useT('sales')
  const [sales, setSales] = useState<POSSaleSummary[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [searchInput, setSearchInput] = useState('')
  const [search, setSearch] = useState('')

  const load = useCallback(async (offset: number, searchTerm: string, append: boolean) => {
    if (append) setLoadingMore(true)
    else setLoading(true)
    setError(null)
    try {
      const response = await pharmacyApi.listPOSSales(PAGE_SIZE, offset, searchTerm)
      setTotal(response.data.total)
      setSales((current) => (append ? [...current, ...response.data.sales] : response.data.sales))
    } catch (err) {
      const message = err instanceof ApiError ? err.message : t('loadError')
      setError(message)
    } finally {
      setLoading(false)
      setLoadingMore(false)
    }
  }, [t])

  useEffect(() => {
    load(0, '', false)
  }, [load])

  function submitSearch(event: React.FormEvent) {
    event.preventDefault()
    const value = searchInput.trim()
    setSearch(value)
    load(0, value, false)
  }

  const hasMore = sales.length < total

  return (
    <RequirePermission anyOf={['sales.view']}>
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">{t('title')}</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {t('subtitle')}
          </p>
        </div>
        <form onSubmit={submitSearch} className="flex w-full max-w-sm items-center gap-2">
          <div className="relative flex-1">
            <Search className="absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={searchInput}
              onChange={(event) => setSearchInput(event.target.value)}
              placeholder={t('searchPlaceholder')}
              className="ps-9"
              aria-label={t('searchLabel')}
            />
          </div>
          <Button type="submit" variant="secondary" size="sm">{t('searchButton')}</Button>
        </form>
      </div>

      {error && (
        <Card>
          <CardContent className="p-4 text-sm text-destructive">{error}</CardContent>
        </Card>
      )}

      {loading ? (
        <div className="flex items-center justify-center py-16">
          <LoadingSpinner />
        </div>
      ) : sales.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
            <ReceiptText className="h-10 w-10 text-muted-foreground" />
            <p className="font-medium">{t('emptyTitle')}</p>
            <p className="text-sm text-muted-foreground">
              {search ? t('emptySearchHint') : t('emptyFirstHint')}
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {sales.map((sale) => (
            <div key={sale.id} className="space-y-2">
              <Link href={`/sales/${sale.id}`} className="block">
                <Card className="transition-colors hover:border-primary/40">
                  <CardContent className="flex flex-wrap items-center gap-x-6 gap-y-2 p-4">
                    <div className="min-w-[130px]">
                      <p className="font-mono text-sm font-bold" dir="ltr">INV-{String(sale.invoice_number).padStart(6, '0')}</p>
                      <p className="mt-0.5 text-xs text-muted-foreground">
                        {formatSaleDate(sale.created_at)} · {formatSaleTime(sale.created_at)}
                      </p>
                    </div>
                    <div className="text-sm text-muted-foreground">
                      {sale.products_count > 0 ? t('productsAndUnits', { products: sale.products_count, units: sale.total_quantity_base }) : t('noProducts')}
                    </div>
                    <Badge variant={saleStatusVariant(sale.status)}>{saleStatusLabel(sale.status)}</Badge>
                    {sale.payment_type === 'credit' && (
                      <Badge variant="warning">{sale.customer_name ? t('creditBadgeWithCustomer', { customer: sale.customer_name }) : t('creditBadge')}</Badge>
                    )}
                    {sale.discount_amount_piastres > 0 && (
                      <span className="text-xs font-semibold text-destructive">{t('discount', { amount: formatPiastres(sale.discount_amount_piastres) })}</span>
                    )}
                    <div className="ms-auto text-end">
                      <p className="font-bold">{formatPiastres(sale.total_amount_piastres)}</p>
                      {sale.returned_amount_piastres > 0 && (
                        <p className="text-xs font-medium text-destructive">
                          {t('returnedAmount', { amount: formatPiastres(sale.returned_amount_piastres) })}
                        </p>
                      )}
                    </div>
                    <ChevronLeft className="rtl-flip h-5 w-5 shrink-0 text-muted-foreground" />
                  </CardContent>
                </Card>
              </Link>

              {sale.returns.map((ret) => (
                <div key={ret.id} className="ms-4 rounded-lg border border-destructive/30 bg-destructive/5 p-3 sm:ms-8">
                  <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
                    <RotateCcw className="h-4 w-4 text-destructive" />
                    <span className="font-semibold text-destructive">{t('returnInvoice')}</span>
                    <span className="font-mono text-xs text-muted-foreground" dir="ltr">
                      RET-{String(ret.return_number).padStart(6, '0')}
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {formatSaleDate(ret.created_at)} · {formatSaleTime(ret.created_at)}
                    </span>
                    <span className="ms-auto font-bold text-destructive">
                      -{formatPiastres(ret.total_amount_piastres)}
                    </span>
                  </div>
                  {ret.reason && (
                    <p className="mt-1 text-xs text-muted-foreground">{t('reason', { reason: ret.reason })}</p>
                  )}
                </div>
              ))}
            </div>
          ))}

          {hasMore && (
            <div className="flex justify-center pt-2">
              <Button
                variant="secondary"
                onClick={() => load(sales.length, search, true)}
                disabled={loadingMore}
              >
                {loadingMore ? <LoadingSpinner /> : t('loadMore')}
              </Button>
            </div>
          )}
        </div>
      )}
    </div>
    </RequirePermission>
  )
}
