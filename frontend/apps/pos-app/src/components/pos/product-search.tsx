'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { Loader2, PackageSearch, ScanLine } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type POSProduct,
  type POSProductSuggestion,
} from '@/lib/api'
import { formatPiastres } from '@/lib/money'
import { extraStrengthLabel } from '@/lib/product'
import { useT } from '@/i18n/provider'
import type { Translator } from '@/i18n/translator'

const SEARCH_DEBOUNCE_MS = 180
const MIN_QUERY_RUNES = 2
const SEARCH_LIMIT = 8
/** أكواد الماسح الرقمية الطويلة (EAN-13/UPC) — لا بحث أثناء الكتابة، Enter فقط */
const SCANNER_CODE_MIN_DIGITS = 6
/** ثقة الإضافة التلقائية عند خطأ الماسح: أعلى نتيجة باركود تقريبية */
const FUZZY_AUTO_ADD_SCORE = 0.72

const matchLabelKeys: Record<string, string> = {
  barcode_exact: 'matchBarcodeExact',
  barcode_prefix: 'matchBarcodePrefix',
  barcode_fuzzy: 'matchBarcodeFuzzy',
  name_prefix: 'matchNamePrefix',
  name_substring: 'matchNameSubstring',
  name_fuzzy: 'matchNameFuzzy',
  generic_fuzzy: 'matchGenericFuzzy',
}

function isScannerCode(value: string) {
  return /^[0-9]{6,}$/.test(value.trim())
}

function stockLabel(stock: number, t: Translator) {
  return stock <= 0 ? t('outOfStock') : t('inStock', { count: stock })
}

/** يبرز الجزء المطابق في الاسم للبادئة/الاحتواء فقط (الضبابي ليس نصاً حرفياً) */
function HighlightName({ name, query }: { name: string; query: string }) {
  const q = query.trim()
  if (!q) return <>{name}</>
  const index = name.indexOf(q)
  if (index < 0) return <>{name}</>
  return (
    <>
      {name.slice(0, index)}
      <mark className="rounded bg-primary/15 px-0.5 text-primary">{name.slice(index, index + q.length)}</mark>
      {name.slice(index + q.length)}
    </>
  )
}

export type AddSource = 'dropdown' | 'barcode' | 'barcode_fuzzy'

interface ProductSearchProps {
  onAddProduct: (product: POSProduct, source: AddSource) => void
  onMessage?: (message: string | null) => void
  onError?: (message: string | null) => void
  disabled?: boolean
  autoFocus?: boolean
}

export default function ProductSearch({ onAddProduct, onMessage, onError, disabled, autoFocus }: ProductSearchProps) {
  const t = useT('pos')
  const [query, setQuery] = useState('')
  const [suggestions, setSuggestions] = useState<POSProductSuggestion[]>([])
  const [open, setOpen] = useState(false)
  const [activeIndex, setActiveIndex] = useState(-1)
  const [searching, setSearching] = useState(false)
  const [resolving, setResolving] = useState(false)

  const inputRef = useRef<HTMLInputElement>(null)
  const listRef = useRef<HTMLUListElement>(null)
  const debounceTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const abortRef = useRef<AbortController | null>(null)
  const requestSeq = useRef(0)

  /** بحث القائمة المنسدلة — مؤجّل، ملغي القديم، ومحمي بتسلسل الطلبات */
  const runSearch = useCallback((rawQuery: string) => {
    const seq = ++requestSeq.current
    abortRef.current?.abort()
    const controller = new AbortController()
    abortRef.current = controller
    setSearching(true)
    pharmacyApi
      .searchPOSProducts(rawQuery, SEARCH_LIMIT, controller.signal)
      .then((response) => {
        if (seq !== requestSeq.current) return
        setSuggestions(response.data)
        setOpen(true)
        setActiveIndex(-1)
      })
      .catch(() => {
        if (seq !== requestSeq.current) return
        setSuggestions([])
      })
      .finally(() => {
        if (seq === requestSeq.current) setSearching(false)
      })
  }, [])

  const scheduleSearch = useCallback(
    (value: string) => {
      if (debounceTimer.current) clearTimeout(debounceTimer.current)
      if ([...value.trim()].length < MIN_QUERY_RUNES || isScannerCode(value)) {
        abortRef.current?.abort()
        requestSeq.current++
        setSearching(false)
        setSuggestions([])
        setOpen(false)
        return
      }
      debounceTimer.current = setTimeout(() => runSearch(value.trim()), SEARCH_DEBOUNCE_MS)
    },
    [runSearch],
  )

  useEffect(() => () => {
    if (debounceTimer.current) clearTimeout(debounceTimer.current)
    abortRef.current?.abort()
  }, [])

  /* القائمة مرتبطة بالنص المكتوب لا بالتركيز: تبقى ظاهرة ما دام النص قائماً،
     وتُغلق فقط عند الاختيار أو مسح النص أو Escape المقصود — الضغط خارجها لا يغلقها
     حتى يستطيع الصيدلي التعامل مع الفاتورة والعودة لنفس النتائج. */

  function pick(product: POSProduct, source: AddSource) {
    onMessage?.(null)
    onError?.(null)
    setQuery('')
    setSuggestions([])
    setOpen(false)
    setActiveIndex(-1)
    onAddProduct(product, source)
    inputRef.current?.focus()
  }

  function notifyError(message: string) {
    onError?.(message)
    inputRef.current?.focus()
  }

  /** مسار الماسح: باركود تام فوراً، وإن فشل ⇒ تصحيح ذكي تلقائي */
  async function resolveScannerCode(code: string) {
    setResolving(true)
    onMessage?.(null)
    onError?.(null)
    try {
      const exact = await pharmacyApi.lookupPOSProduct(code)
      pick(exact.data, 'barcode')
      return
    } catch (cause) {
      if (!(cause instanceof ApiError) || cause.status !== 404) {
        setResolving(false)
        notifyError(cause instanceof ApiError ? cause.message : t('productNotFound'))
        return
      }
    }
    try {
      const response = await pharmacyApi.searchPOSProducts(code, SEARCH_LIMIT)
      const results = response.data
      const top = results[0]
      const topIsBarcodeHit = top && (top.match_type === 'barcode_prefix' || top.match_type === 'barcode_fuzzy')
      if (topIsBarcodeHit && (results.length === 1 || top.score >= FUZZY_AUTO_ADD_SCORE)) {
        pick(top, 'barcode_fuzzy')
        onMessage?.(t('scannerCorrected', { name: top.name }))
        return
      }
      if (results.length > 0) {
        setSuggestions(results)
        setOpen(true)
        setActiveIndex(0)
        onMessage?.(t('barcodeNotExact'))
        return
      }
      notifyError(t('barcodeNoProduct'))
    } catch {
      notifyError(t('barcodeSearchFailed'))
    } finally {
      setResolving(false)
    }
  }

  async function handleKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === 'Escape') {
      // إغلاق مقصود: نلغي المؤجّل والطلب الجاري حتى لا تفتح القائمة من تلقاء نفسها
      if (debounceTimer.current) clearTimeout(debounceTimer.current)
      abortRef.current?.abort()
      requestSeq.current++
      setSearching(false)
      setOpen(false)
      return
    }
    // إعادة الفتح بالأسهم بعد الإغلاق المقصود (النتائج ما زالت مرتبطة بالنص)
    if (!open && suggestions.length > 0 && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
      event.preventDefault()
      setOpen(true)
      setActiveIndex(event.key === 'ArrowUp' ? suggestions.length - 1 : 0)
      return
    }
    if (open && suggestions.length > 0) {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault()
        setActiveIndex((current) => {
          const next = event.key === 'ArrowDown' ? current + 1 : current - 1
          const bounded = Math.max(0, Math.min(suggestions.length - 1, next))
          listRef.current?.children[bounded]?.scrollIntoView({ block: 'nearest' })
          return bounded
        })
        return
      }
      if (event.key === 'Enter') {
        event.preventDefault()
        const chosen = suggestions[activeIndex >= 0 ? activeIndex : 0]
        if (chosen) pick(chosen, 'dropdown')
        return
      }
    }
    if (event.key === 'Enter' && !open && query.trim()) {
      event.preventDefault()
      if (isScannerCode(query)) {
        await resolveScannerCode(query.trim())
        return
      }
      // اسم مكتمل + Enter ⇒ أضف أعلى نتيجة مباشرة (سرعة الكاشير)
      if (suggestions.length > 0) {
        pick(suggestions[0], 'dropdown')
        return
      }
      runSearch(query.trim())
    }
  }

  const showList = open && suggestions.length > 0
  const busy = resolving || (searching && !showList)

  return (
    <div className="relative">
      <div className="flex gap-3">
        <div className="relative flex-1">
          <ScanLine className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
          <input
            ref={inputRef}
            type="text"
            role="combobox"
            aria-expanded={showList}
            aria-controls="pos-search-listbox"
            aria-autocomplete="list"
            aria-label={t('searchAria')}
            autoComplete="off"
            enterKeyHint="search"
            className="h-12 w-full rounded-xl border border-input bg-background ps-9 pe-4 text-sm outline-none transition-all placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10 disabled:cursor-not-allowed disabled:opacity-60"
            placeholder={t('searchPlaceholder')}
            value={query}
            disabled={disabled}
            autoFocus={autoFocus}
            onChange={(event) => {
              const value = event.target.value
              setQuery(value)
              scheduleSearch(value)
            }}
            onKeyDown={handleKeyDown}
          />
          {busy && <Loader2 className="absolute end-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-primary" aria-hidden="true" />}
        </div>
      </div>

      {showList && (
        <ul
          id="pos-search-listbox"
          ref={listRef}
          role="listbox"
          aria-label={t('resultsAria')}
          className="absolute inset-x-0 top-full z-40 mt-2 max-h-80 overflow-y-auto rounded-xl border border-border bg-card p-1.5 shadow-2xl"
        >
          {suggestions.map((item, index) => {
            const strengthLabel = extraStrengthLabel(item.name, item.strength)
            return (
            <li
              key={item.id}
              role="option"
              aria-selected={index === activeIndex}
              id={`pos-search-option-${index}`}
              onMouseEnter={() => setActiveIndex(index)}
              onMouseDown={(event) => {
                // mousedown قبل blur الحقل لضمان الالتقاط
                event.preventDefault()
                pick(item, 'dropdown')
              }}
              className={`flex cursor-pointer items-center justify-between gap-3 rounded-lg px-3 py-2.5 transition-colors ${
                index === activeIndex ? 'bg-primary/10' : 'hover:bg-muted'
              }`}
            >
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold">
                  <HighlightName name={item.name} query={query} />
                  {strengthLabel && <span className="font-normal text-muted-foreground"> {strengthLabel}</span>}
                </p>
                <p className="mt-0.5 truncate text-xs text-muted-foreground">
                  {[item.generic_name, item.barcode].filter(Boolean).join(' · ')}
                </p>
              </div>
              <div className="flex shrink-0 flex-col items-start gap-0.5">
                <span className="text-sm font-bold text-primary">{formatPiastres(item.selling_price_piastres)}</span>
                <span className={`text-[11px] ${item.stock <= 0 ? 'font-semibold text-destructive' : 'text-muted-foreground'}`}>
                  {stockLabel(item.stock, t)}
                </span>
              </div>
              <span
                className={`shrink-0 rounded-full border px-2 py-0.5 text-[10px] leading-4 ${
                  item.match_type.startsWith('barcode')
                    ? 'border-primary/40 bg-primary/10 text-primary'
                    : 'border-border bg-muted text-muted-foreground'
                }`}
              >
                {matchLabelKeys[item.match_type] ? t(matchLabelKeys[item.match_type]) : item.match_type}
              </span>
            </li>
            )
          })}
        </ul>
      )}

      {open && !searching && suggestions.length === 0 && [...query.trim()].length >= MIN_QUERY_RUNES && !isScannerCode(query) && (
        <div className="absolute inset-x-0 top-full z-40 mt-2 flex items-center gap-2 rounded-xl border border-border bg-card px-4 py-3 text-sm text-muted-foreground shadow-2xl">
          <PackageSearch className="h-4 w-4 shrink-0" aria-hidden="true" />
          {t('noResults')}
        </div>
      )}
    </div>
  )
}
