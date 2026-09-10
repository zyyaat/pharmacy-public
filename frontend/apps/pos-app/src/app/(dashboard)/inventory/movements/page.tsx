'use client'

import { useCallback, useEffect, useState } from 'react'
import { ArrowDownLeft, ArrowUpRight, ClipboardList, RotateCcw, Search } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type StockMovementFilters,
  type StockMovementRow,
  type StockMovementType,
} from '@/lib/api'
import {
  formatMovementDate,
  formatMovementQuantity,
  formatMovementTime,
  movementTypeLabel,
  movementTypeVariant,
} from '@/lib/movements'
import { fmtNumber } from '@/i18n/format'
import { useT } from '@/i18n/provider'
import {
  Badge,
  Button,
  Card,
  CardContent,
  Input,
  LoadingSpinner,
  Select,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import { RequirePermission } from '@/components/permissions/gate'

const PAGE_SIZE = 50

const movementTypeKeys: Array<{ value: StockMovementType | 'all'; key: string }> = [
  { value: 'all', key: 'filter_all_types' },
  { value: 'sale', key: 'type_sale' },
  { value: 'return_from_customer', key: 'type_return_from_customer' },
  { value: 'purchase', key: 'type_purchase' },
  { value: 'return_to_supplier', key: 'type_return_to_supplier' },
  { value: 'adjustment', key: 'type_adjustment' },
  { value: 'transfer_in', key: 'type_transfer_in' },
  { value: 'transfer_out', key: 'type_transfer_out' },
  { value: 'expiry_writeoff', key: 'type_expiry_writeoff' },
  { value: 'damage_writeoff', key: 'type_damage_writeoff' },
  { value: 'theft_loss', key: 'type_theft_loss' },
  { value: 'production_input', key: 'type_production_input' },
  { value: 'production_output', key: 'type_production_output' },
]

const directionKeys = [
  { value: 'all', key: 'direction_all' },
  { value: 'in', key: 'direction_in' },
  { value: 'out', key: 'direction_out' },
] as const

export default function InventoryMovementsPage() {
  const t = useT('movements')
  const movementTypeOptions = movementTypeKeys.map((option) => ({ value: option.value, label: t(option.key) }))
  const directionOptions = directionKeys.map((option) => ({ value: option.value, label: t(option.key) }))
  const [movements, setMovements] = useState<StockMovementRow[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // الفلاتر المطبقة (اللي بتتبعت للسيرفر)
  const [filters, setFilters] = useState<StockMovementFilters>({})
  // قيم النموذج قبل التطبيق
  const [searchInput, setSearchInput] = useState('')
  const [typeInput, setTypeInput] = useState<StockMovementType | 'all'>('all')
  const [directionInput, setDirectionInput] = useState<'all' | 'in' | 'out'>('all')
  const [fromInput, setFromInput] = useState('')
  const [toInput, setToInput] = useState('')

  const load = useCallback(async (offset: number, applied: StockMovementFilters, append: boolean) => {
    if (append) setLoadingMore(true)
    else setLoading(true)
    setError(null)
    try {
      const response = await pharmacyApi.listStockMovements(applied, PAGE_SIZE, offset)
      setTotal(response.data.total)
      setMovements((current) =>
        append ? [...current, ...response.data.movements] : response.data.movements,
      )
    } catch (err) {
      const message = err instanceof ApiError ? err.message : t('error_load')
      setError(message)
    } finally {
      setLoading(false)
      setLoadingMore(false)
    }
  }, [t])

  useEffect(() => {
    load(0, {}, false)
  }, [load])

  function submitFilters(event: React.FormEvent) {
    event.preventDefault()
    const applied: StockMovementFilters = {
      search: searchInput.trim(),
      type: typeInput === 'all' ? '' : typeInput,
      direction: directionInput === 'all' ? '' : directionInput,
      from: fromInput || undefined,
      to: toInput || undefined,
    }
    setFilters(applied)
    load(0, applied, false)
  }

  function resetFilters() {
    setSearchInput('')
    setTypeInput('all')
    setDirectionInput('all')
    setFromInput('')
    setToInput('')
    setFilters({})
    load(0, {}, false)
  }

  const hasFilters =
    Boolean(filters.search) || Boolean(filters.type) || Boolean(filters.direction) ||
    Boolean(filters.from) || Boolean(filters.to)
  const hasMore = movements.length < total

  return (
    <RequirePermission anyOf={['inventory.movements.view']}>
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">{t('title')}</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {t('subtitle')}
          </p>
        </div>
        {total > 0 && (
          <p className="text-sm text-muted-foreground">
            {t('count_shown', { shown: fmtNumber(movements.length), total: fmtNumber(total) })}
          </p>
        )}
      </div>

      {/* الفلاتر */}
      <form onSubmit={submitFilters} className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative min-w-[220px] flex-1">
            <Search className="absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={searchInput}
              onChange={(event) => setSearchInput(event.target.value)}
              placeholder={t('search_placeholder')}
              className="pe-9"
              aria-label={t('search_aria')}
            />
          </div>
          <div className="w-[200px]">
            <Select
              value={typeInput}
              onValueChange={(value) => setTypeInput(value as StockMovementType | 'all')}
              options={movementTypeOptions}
              aria-label={t('type_aria')}
            />
          </div>
          <div className="w-[170px]">
            <Select
              value={directionInput}
              onValueChange={(value) => setDirectionInput(value as 'all' | 'in' | 'out')}
              options={directionOptions}
              aria-label={t('direction_aria')}
            />
          </div>
          <Button type="submit" variant="secondary" size="sm">{t('apply')}</Button>
          {hasFilters && (
            <Button type="button" variant="ghost" size="sm" onClick={resetFilters}>
              <RotateCcw className="h-4 w-4" /> {t('clear_filters')}
            </Button>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-muted-foreground">{t('from_label')}</span>
          <Input
            type="date"
            value={fromInput}
            onChange={(event) => setFromInput(event.target.value)}
            className="w-[150px]"
            aria-label={t('from_aria')}
          />
          <span className="text-muted-foreground">{t('to_label')}</span>
          <Input
            type="date"
            value={toInput}
            onChange={(event) => setToInput(event.target.value)}
            className="w-[150px]"
            aria-label={t('to_aria')}
          />
        </div>
      </form>

      {error && (
        <Card>
          <CardContent className="p-4 text-sm text-destructive">{error}</CardContent>
        </Card>
      )}

      {loading ? (
        <div className="flex items-center justify-center py-16">
          <LoadingSpinner />
        </div>
      ) : movements.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
            <ClipboardList className="h-10 w-10 text-muted-foreground" />
            <p className="font-medium">{t('empty_title')}</p>
            <p className="text-sm text-muted-foreground">
              {hasFilters ? t('empty_filtered') : t('empty_default')}
            </p>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-[110px]">{t('th_date')}</TableHead>
                    <TableHead>{t('th_product')}</TableHead>
                    <TableHead>{t('th_batch')}</TableHead>
                    <TableHead>{t('th_type')}</TableHead>
                    <TableHead className="w-[120px]">{t('th_quantity')}</TableHead>
                    <TableHead className="w-[100px]">{t('th_balance_after')}</TableHead>
                    <TableHead>{t('th_by')}</TableHead>
                    <TableHead>{t('th_branch')}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {movements.map((movement) => {
                    const incoming = movement.quantity >= 0
                    return (
                      <TableRow key={movement.id}>
                        <TableCell className="whitespace-nowrap">
                          <span className="flex flex-col leading-tight">
                            <span className="text-xs text-foreground/80">{formatMovementDate(movement.created_at)}</span>
                            <span className="text-[11px] tabular-nums text-muted-foreground">{formatMovementTime(movement.created_at)}</span>
                          </span>
                        </TableCell>
                        <TableCell className="max-w-[280px]">
                          <p className="truncate font-medium" title={movement.product_name}>{movement.product_name}</p>
                          {movement.generic_name && (
                            <p className="truncate text-xs text-muted-foreground" title={movement.generic_name}>{movement.generic_name}</p>
                          )}
                          {(movement.reason || movement.notes) && (
                            <p className="mt-0.5 truncate text-xs text-muted-foreground" title={movement.reason || movement.notes || ''}>
                              {movement.reason || movement.notes}
                            </p>
                          )}
                        </TableCell>
                        <TableCell className="font-mono text-xs">
                          {movement.batch_number ? (
                            <span dir="ltr" className="inline-block text-start">{movement.batch_number}</span>
                          ) : '—'}
                        </TableCell>
                        <TableCell>
                          <Badge variant={movementTypeVariant(movement.movement_type)}>
                            {movementTypeLabel(movement.movement_type)}
                          </Badge>
                        </TableCell>
                        <TableCell className="whitespace-nowrap">
                          <span
                            className={`inline-flex items-center gap-1 font-bold tabular-nums ${
                              incoming ? 'text-emerald-600' : 'text-destructive'
                            }`}
                          >
                            {incoming ? (
                              <ArrowDownLeft className="h-4 w-4" />
                            ) : (
                              <ArrowUpRight className="h-4 w-4" />
                            )}
                            {incoming ? '+' : '−'}
                            {formatMovementQuantity(movement.quantity, movement.unit)}
                          </span>
                        </TableCell>
                        <TableCell className="whitespace-nowrap text-xs tabular-nums">
                          {movement.quantity_after != null
                            ? formatMovementQuantity(movement.quantity_after, movement.unit)
                            : '—'}
                        </TableCell>
                        <TableCell className="text-xs">{movement.actor_name || '—'}</TableCell>
                        <TableCell className="text-xs">{movement.branch_name || '—'}</TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      )}

      {hasMore && (
        <div className="flex justify-center">
          <Button
            variant="secondary"
            onClick={() => load(movements.length, filters, true)}
            disabled={loadingMore}
          >
            {loadingMore ? <LoadingSpinner /> : t('load_more')}
          </Button>
        </div>
      )}
    </div>
    </RequirePermission>
  )
}
