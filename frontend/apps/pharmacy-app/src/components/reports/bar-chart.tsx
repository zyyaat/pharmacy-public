'use client'

// رسم بياني عمودي خفيف بلا مكتبات خارجية — أعمدة CSS تُطبع بدقة
// مع هوية الموقع (print-color-adjust: exact مضبوط في globals.css).

import { useMemo } from 'react'
import { cn } from '@/lib/utils'
import { useT } from '@/i18n/provider'
import { fmtNumber } from '@/i18n/format'

export interface BarChartPoint {
  /** تسمية قصيرة تحت العمود (رقم اليوم مثلاً) */
  label: string
  value: number
  /** نص Tooltip كامل */
  title?: string
  /** تمييز العمود بقيمة صفرية أو سالبة */
  muted?: boolean
}

export function BarChart({
  points,
  height = 180,
  summary,
}: {
  points: BarChartPoint[]
  height?: number
  /** سطر ملخص أعلى الرسم (القيمة القصوى مثلاً) */
  summary?: string
}) {
  const t = useT('reports')
  const maxValue = useMemo(
    () => points.reduce((max, point) => Math.max(max, point.value), 0),
    [points],
  )
  // كل كم يوم نُظهر تسمية حتى لا تزدحم المحور (الهدف ≈ 8 تسميات)
  const labelStep = Math.max(1, Math.ceil(points.length / 8))

  if (points.length === 0) {
    return (
      <p className="py-10 text-center text-sm text-muted-foreground">
        {t('no_chart_data')}
      </p>
    )
  }

  return (
    <div>
      <div className="mb-2 flex items-center justify-between text-xs text-muted-foreground">
        <span className="tabular-nums">{t('chart_max', { value: fmtNumber(maxValue) })}</span>
        {summary && <span>{summary}</span>}
      </div>
      <div
        className="report-chart flex items-end gap-[3px] sm:gap-1.5"
        style={{ height }}
        role="img"
        aria-label={summary || t('aria_bar_chart')}
      >
        {points.map((point, index) => {
          const ratio = maxValue > 0 ? point.value / maxValue : 0
          const isZero = point.value <= 0
          return (
            <div
              key={`${point.label}-${index}`}
              className="flex h-full flex-1 flex-col justify-end"
              title={point.title ?? `${point.label}: ${fmtNumber(point.value)}`}
            >
              <div
                className={cn(
                  'mx-auto w-full max-w-[40px] rounded-t-sm transition-colors',
                  isZero
                    ? 'bg-muted min-h-[2px]'
                    : 'bg-primary/80 hover:bg-primary min-h-[3px]',
                )}
                style={{ height: isZero ? undefined : `${Math.max(3, ratio * 100)}%` }}
              />
            </div>
          )
        })}
      </div>
      <div className="mt-1.5 flex gap-[3px] sm:gap-1.5">
        {points.map((point, index) => (
          <span
            key={`label-${point.label}-${index}`}
            className="flex-1 truncate text-center text-[10px] tabular-nums text-muted-foreground"
          >
            {index % labelStep === 0 || index === points.length - 1 ? point.label : ''}
          </span>
        ))}
      </div>
    </div>
  )
}
