'use client'

import { cn } from '@/lib/utils'

export interface KpiItem {
  label: string
  value: string
  hint?: string
  tone?: 'default' | 'success' | 'destructive' | 'warning'
}

const toneClasses: Record<NonNullable<KpiItem['tone']>, string> = {
  default: 'text-foreground',
  success: 'text-emerald-600 dark:text-emerald-400',
  destructive: 'text-destructive',
  warning: 'text-amber-600 dark:text-amber-400',
}

/** صف بطاقات المؤشرات الرئيسية — 3 إلى 5 بطاقات بحسب المحتوى. */
export function KpiCards({ items, columns = 4 }: { items: KpiItem[]; columns?: 3 | 4 | 5 }) {
  const gridCols =
    columns === 5
      ? 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-5'
      : columns === 3
        ? 'grid-cols-2 sm:grid-cols-3'
        : 'grid-cols-2 lg:grid-cols-4'
  return (
    <div className={cn('print-avoid-break grid gap-3', gridCols)}>
      {items.map((item) => (
        <div
          key={item.label}
          className="print-avoid-break rounded-xl border border-border bg-card p-4"
        >
          <p className="text-xs font-medium text-muted-foreground">{item.label}</p>
          <p
            className={cn(
              'mt-1 text-xl font-bold tabular-nums sm:text-2xl',
              toneClasses[item.tone ?? 'default'],
            )}
          >
            {item.value}
          </p>
          {item.hint && <p className="mt-1 text-xs text-muted-foreground">{item.hint}</p>}
        </div>
      ))}
    </div>
  )
}
