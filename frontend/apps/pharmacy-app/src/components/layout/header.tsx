'use client'

import { useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { Bell, Globe, Menu, Moon, Search, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'
import { pharmacyApi, type CustomerDebtItem, type LowStockItem } from '@/lib/api'
import { formatPiastres } from '@/lib/money'
import { availabilityAr, boxWordAr, extraStrengthLabel } from '@/lib/product'
import { Button } from '@/components/ui'
import { useAccess } from '@/components/permissions/gate'
import { useT } from '@/i18n/provider'

/**
 * جرس الإشعارات الحقيقي: أصناف المخزون المنخفض — حد الطلب يُحسب بالعلبة
 * الكاملة فقط (الشرائط المفردة لا تُحتسب)، والرسالة صريحة: باقي كام علب،
 * وحد الطلب كام. تُجلب عند التحميل وتُحدّث كل دقيقة حتى يتخذ الصيدلي إجراء الشراء.
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

/** ديون العملاء (البيع الآجل): من عليهم رصيد مستحق — تُجلب مع الجرس كل دقيقة للتحصيل */
function useCustomerDebts() {
  const [items, setItems] = useState<CustomerDebtItem[]>([])
  useEffect(() => {
    let cancelled = false
    async function load() {
      try {
        const response = await pharmacyApi.listCustomerDebts()
        if (!cancelled) setItems(response.data.customers)
      } catch {
        // الإشعارات ميزة غير حرجة — أي فشل يترك القسم صامتاً
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
  const t = useT('nav')
  // أقسام الإشعارات وروابطها تختفي كليًا عمن لا يملك صلاحية الصفحة المقصودة
  const { ready, allowed } = useAccess()
  const canSeeInventoryAlerts = ready && allowed('inventory.view')
  const canSeeCustomerDebts = ready && allowed('customers.view')
  const lowStock = useLowStock()
  const debts = useCustomerDebts()
  const alertCount = (canSeeInventoryAlerts ? lowStock.length : 0) + (canSeeCustomerDebts ? debts.length : 0)
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
          <Search className="absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            type="search"
            placeholder={t('search_placeholder')}
            className="h-10 w-full rounded-lg border border-input bg-background pe-4 ps-10 text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>
      </div>

      <div className="flex items-center gap-2">
        <Button variant="ghost" size="icon" title={t('change_language')}>
          <Globe className="h-5 w-5" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          title={theme === 'dark' ? t('light_mode') : t('dark_mode')}
        >
          <Sun className="h-5 w-5 rotate-0 scale-100 transition-all dark:-rotate-90 dark:scale-0" />
          <Moon className="absolute h-5 w-5 rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100" />
        </Button>
        <div ref={panelRef} className="relative">
          <Button
            variant="ghost"
            size="icon"
            className="relative"
            title={t('notifications')}
            aria-label={alertCount ? t('notifications_with_count', { count: alertCount }) : t('notifications')}
            onClick={() => setPanelOpen((open) => !open)}
          >
            <Bell className="h-5 w-5" />
            {alertCount > 0 && (
              <span className="absolute -start-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-destructive px-1 text-[10px] font-bold text-destructive-foreground">
                {alertCount}
              </span>
            )}
          </Button>
          {panelOpen && (
            <div className="absolute end-0 top-full z-50 mt-2 w-80 overflow-hidden rounded-xl border border-border bg-card shadow-lg animate-in fade-in-0 zoom-in-95">
              <div className="flex items-center justify-between border-b border-border px-4 py-3">
                <p className="text-sm font-bold">{t('notifications')}</p>
                <span className="text-xs text-muted-foreground">{alertCount ? t('alerts_count', { count: alertCount }) : t('no_alerts')}</span>
              </div>
              <div className="max-h-96 overflow-y-auto">
                {alertCount === 0 ? (
                  <p className="px-4 py-8 text-center text-sm text-muted-foreground">
                    {t('all_clear')}
                  </p>
                ) : (
                  <>
                    {canSeeCustomerDebts && debts.length > 0 && (
                      <div>
                        <p className="border-b border-border/60 bg-muted/40 px-4 py-1.5 text-[11px] font-bold text-muted-foreground">{t('customer_debts')}</p>
                        {debts.map((debt) => (
                          <Link
                            key={debt.id}
                            href="/customers"
                            className="flex items-center justify-between gap-3 border-b border-border/60 px-4 py-2.5 text-sm last:border-0 hover:bg-accent"
                            onClick={() => setPanelOpen(false)}
                          >
                            <span className="min-w-0">
                              <span className="block truncate font-semibold">{debt.name}</span>
                              <span className="text-xs text-muted-foreground">{t('debt_owed', { amount: formatPiastres(debt.balance_piastres) })}</span>
                            </span>
                            <span className="shrink-0 rounded-full bg-amber-500/10 px-2 py-0.5 text-[11px] font-bold text-amber-600">{t('debtor_badge')}</span>
                          </Link>
                        ))}
                      </div>
                    )}
                    {canSeeInventoryAlerts && lowStock.length > 0 && (
                      <div>
                        <p className="border-b border-border/60 bg-muted/40 px-4 py-1.5 text-[11px] font-bold text-muted-foreground">{t('low_stock')}</p>
                        {lowStock.map((item) => (
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
                          {item.full_boxes === 0 && item.strips === 0
                            ? t('out_of_stock_line', { min: boxWordAr(item.min_stock_level) })
                            : t('low_stock_line', { min: boxWordAr(item.min_stock_level), available: availabilityAr(item.full_boxes, item.strips) })}
                        </span>
                      </span>
                      <span className="shrink-0 rounded-full bg-destructive/10 px-2 py-0.5 text-[11px] font-bold text-destructive">
                        {item.full_boxes === 0 && item.strips === 0 ? t('out_badge') : t('low_badge')}
                      </span>
                    </Link>
                      ))}
                      </div>
                    )}
                  </>
                )}
              </div>
              {canSeeCustomerDebts && debts.length > 0 && (
                <Link href="/customers" className="block border-t border-border px-4 py-2.5 text-center text-xs font-bold text-primary hover:bg-accent" onClick={() => setPanelOpen(false)}>
                  {t('open_customers')}
                </Link>
              )}
              {canSeeInventoryAlerts && (
                <Link href="/inventory" className="block border-t border-border px-4 py-2.5 text-center text-xs font-bold text-primary hover:bg-accent" onClick={() => setPanelOpen(false)}>
                  {t('open_inventory')}
                </Link>
              )}
            </div>
          )}
        </div>
      </div>
    </header>
  )
}
