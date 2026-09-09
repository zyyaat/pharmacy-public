'use client'

import { useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { Bell, Globe, Menu, Moon, Search, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'
import { pharmacyApi, type LowStockItem } from '@/lib/api'
import { extraStrengthLabel } from '@/lib/product'
import { Button } from '@/components/ui'

/**
 * جرس الإشعارات الحقيقي: أصناف المخزون المنخفض (الكمية بلغت حد إعادة الطلب
 * أو أقل) — تُجلب عند التحميل وتُحدّث كل دقيقة حتى يتخذ الصيدلي إجراء الشراء.
 */
function useLowStock() {
  const [items, setItems] = useState<LowStockItem[]>([])
  useEffect(() => {
    let cancelled = false
    async function load() {
      try {
        const response = await pharmacyApi.listLowStockItems()
        if (!cancelled) setItems(response.data.items)
      } catch {
        // الإشعارات ميزة غير حرجة — أي فشل يترك الجرس صامتاً
      }
    }
    void load()
    const timer = setInterval(load, 60_000)
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [])
  return items
}

export default function Header({ onMenuClick }: { onMenuClick?: () => void }) {
  const { theme, setTheme } = useTheme()
  const lowStock = useLowStock()
  const [panelOpen, setPanelOpen] = useState(false)
  const panelRef = useRef<HTMLDivElement>(null)

  // إغلاق لوحة الإشعارات عند الضغط خارجها
  useEffect(() => {
    if (!panelOpen) return
    function handlePointerDown(event: PointerEvent) {
      if (!panelRef.current?.contains(event.target as Node)) setPanelOpen(false)
    }
    document.addEventListener('pointerdown', handlePointerDown)
    return () => document.removeEventListener('pointerdown', handlePointerDown)
  }, [panelOpen])

  return (
    <header className="print-hidden sticky top-0 z-30 flex h-16 items-center gap-4 border-b border-border bg-background/80 px-4 backdrop-blur-md lg:px-6">
      <Button variant="ghost" size="icon" className="lg:hidden" onClick={onMenuClick}>
        <Menu className="h-5 w-5" />
      </Button>

      <div className="max-w-md flex-1">
        <div className="relative">
          <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            type="search"
            placeholder="بحث عن دواء، موظف..."
            className="h-10 w-full rounded-lg border border-input bg-background pl-4 pr-10 text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>
      </div>

      <div className="flex items-center gap-2">
        <Button variant="ghost" size="icon" title="تغيير اللغة">
          <Globe className="h-5 w-5" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          title={theme === 'dark' ? 'الوضع النهاري' : 'الوضع الليلي'}
        >
          <Sun className="h-5 w-5 rotate-0 scale-100 transition-all dark:-rotate-90 dark:scale-0" />
          <Moon className="absolute h-5 w-5 rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100" />
        </Button>
        <div ref={panelRef} className="relative">
          <Button
            variant="ghost"
            size="icon"
            className="relative"
            title="إشعارات المخزون المنخفض"
            aria-label={`إشعارات المخزون المنخفض${lowStock.length ? ` (${lowStock.length} أصناف)` : ''}`}
            onClick={() => setPanelOpen((open) => !open)}
          >
            <Bell className="h-5 w-5" />
            {lowStock.length > 0 && (
              <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-destructive px-1 text-[10px] font-bold text-destructive-foreground">
                {lowStock.length}
              </span>
            )}
          </Button>
          {panelOpen && (
            <div className="absolute end-0 top-full z-50 mt-2 w-80 overflow-hidden rounded-xl border border-border bg-card shadow-lg animate-in fade-in-0 zoom-in-95">
              <div className="flex items-center justify-between border-b border-border px-4 py-3">
                <p className="text-sm font-bold">المخزون المنخفض</p>
                <span className="text-xs text-muted-foreground">{lowStock.length ? `${lowStock.length} صنف يحتاج تزويد` : 'لا تنبيهات'}</span>
              </div>
              <div className="max-h-72 overflow-y-auto">
                {lowStock.length === 0 ? (
                  <p className="px-4 py-8 text-center text-sm text-muted-foreground">
                    كل الأصناف فوق حد إعادة الطلب — لا يوجد ما يستدعي الإجراء.
                  </p>
                ) : (
                  lowStock.map((item) => (
                    <Link
                      key={item.pharmacy_product_id}
                      href="/inventory"
                      className="flex items-center justify-between gap-3 border-b border-border/60 px-4 py-2.5 text-sm last:border-0 hover:bg-accent"
                      onClick={() => setPanelOpen(false)}
                    >
                      <span className="min-w-0">
                        <span className="block truncate font-semibold">
                          {item.product_name}
                          {extraStrengthLabel(item.product_name, item.strength) && (
                            <span className="ms-1 text-xs font-normal text-muted-foreground">{extraStrengthLabel(item.product_name, item.strength)}</span>
                          )}
                        </span>
                        <span className="text-xs text-muted-foreground">
                          المتاح {item.quantity_base} · حد الطلب {item.min_stock_level}
                        </span>
                      </span>
                      <span className="shrink-0 rounded-full bg-destructive/10 px-2 py-0.5 text-[11px] font-bold text-destructive">
                        {item.quantity_base === 0 ? 'نفد' : 'منخفض'}
                      </span>
                    </Link>
                  ))
                )}
              </div>
              <Link href="/inventory" className="block border-t border-border px-4 py-2.5 text-center text-xs font-bold text-primary hover:bg-accent" onClick={() => setPanelOpen(false)}>
                فتح صفحة المخزون لاتخاذ الإجراء
              </Link>
            </div>
          )}
        </div>
      </div>
    </header>
  )
}
