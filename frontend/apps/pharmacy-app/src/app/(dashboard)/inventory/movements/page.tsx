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

const PAGE_SIZE = 50

const movementTypeOptions: Array<{ value: StockMovementType | 'all'; label: string }> = [
  { value: 'all', label: 'كل الحركات' },
  { value: 'sale', label: 'بيع' },
  { value: 'return_from_customer', label: 'استرجاع من عميل' },
  { value: 'purchase', label: 'شراء' },
  { value: 'return_to_supplier', label: 'مرتجع للمورد' },
  { value: 'adjustment', label: 'تسوية مخزون' },
  { value: 'transfer_in', label: 'تحويل وارد' },
  { value: 'transfer_out', label: 'تحويل صادر' },
  { value: 'expiry_writeoff', label: 'إعدام منتهي الصلاحية' },
  { value: 'damage_writeoff', label: 'إعدام تالف' },
  { value: 'theft_loss', label: 'فقد/سرقة' },
  { value: 'production_input', label: 'استهلاك تصنيع' },
  { value: 'production_output', label: 'إنتاج' },
]

const directionOptions = [
  { value: 'all', label: 'داخل وخارج' },
  { value: 'in', label: 'داخل فقط (+)' },
  { value: 'out', label: 'خارج فقط (−)' },
]

export default function InventoryMovementsPage() {
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
      const message = err instanceof ApiError ? err.message : 'تعذر تحميل سجل حركات المخزون'
      setError(message)
    } finally {
      setLoading(false)
      setLoadingMore(false)
    }
  }, [])

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
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">سجل حركات المخزون</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            كل حركة دخول وخروج: بيع، استرجاع، شراء، تسويات وإعدام — بالتسلسل الزمني
          </p>
        </div>
        {total > 0 && (
          <p className="text-sm text-muted-foreground">
            {movements.length.toLocaleString('ar-EG')} من {total.toLocaleString('ar-EG')} حركة
          </p>
        )}
      </div>

      {/* الفلاتر */}
      <form onSubmit={submitFilters} className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative min-w-[220px] flex-1">
            <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={searchInput}
              onChange={(event) => setSearchInput(event.target.value)}
              placeholder="ابحث باسم الدواء أو رقم التشغيلة"
              className="pr-9"
              aria-label="بحث في سجل المخزون"
            />
          </div>
          <div className="w-[200px]">
            <Select
              value={typeInput}
              onValueChange={(value) => setTypeInput(value as StockMovementType | 'all')}
              options={movementTypeOptions}
              aria-label="نوع الحركة"
            />
          </div>
          <div className="w-[170px]">
            <Select
              value={directionInput}
              onValueChange={(value) => setDirectionInput(value as 'all' | 'in' | 'out')}
              options={directionOptions}
              aria-label="اتجاه الحركة"
            />
          </div>
          <Button type="submit" variant="secondary" size="sm">تطبيق</Button>
          {hasFilters && (
            <Button type="button" variant="ghost" size="sm" onClick={resetFilters}>
              <RotateCcw className="h-4 w-4" /> مسح الفلاتر
            </Button>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-muted-foreground">من تاريخ</span>
          <Input
            type="date"
            value={fromInput}
            onChange={(event) => setFromInput(event.target.value)}
            className="w-[150px]"
            aria-label="من تاريخ"
          />
          <span className="text-muted-foreground">إلى</span>
          <Input
            type="date"
            value={toInput}
            onChange={(event) => setToInput(event.target.value)}
            className="w-[150px]"
            aria-label="إلى تاريخ"
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
            <p className="font-medium">لا توجد حركات مخزون</p>
            <p className="text-sm text-muted-foreground">
              {hasFilters ? 'جرب تغيير الفلاتر أو مسحها' : 'أي حركة بيع أو استرجاع أو تعديل مخزون ستظهر هنا تلقائياً'}
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
                    <TableHead className="w-[110px]">التاريخ</TableHead>
                    <TableHead>الدواء</TableHead>
                    <TableHead>التشغيلة</TableHead>
                    <TableHead>النوع</TableHead>
                    <TableHead className="w-[120px]">الكمية</TableHead>
                    <TableHead className="w-[100px]">الرصيد بعدها</TableHead>
                    <TableHead>بواسطة</TableHead>
                    <TableHead>الفرع</TableHead>
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
            {loadingMore ? <LoadingSpinner /> : 'تحميل المزيد'}
          </Button>
        </div>
      )}
    </div>
  )
}
