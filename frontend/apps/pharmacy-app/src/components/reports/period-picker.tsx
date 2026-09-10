'use client'

// منتقي الفترة: قوائم جاهزة عبر قائمة الموقع المخصصة + فترة مخصصة بتاريخين.

import { Button, Input, Select } from '@/components/ui'
import { useT } from '@/i18n/provider'
import {
  periodPresetOptions,
  type PeriodPreset,
} from '@/lib/reports'

export interface PeriodPickerProps {
  preset: PeriodPreset
  onPresetChange: (preset: PeriodPreset) => void
  from: string
  to: string
  onFromChange: (value: string) => void
  onToChange: (value: string) => void
  /** يُستدعى عند اختيار فترة جاهزة أو الضغط على تطبيق في المخصصة */
  onApply: () => void
  loading?: boolean
  className?: string
}

export function PeriodPicker({
  preset,
  onPresetChange,
  from,
  to,
  onFromChange,
  onToChange,
  onApply,
  loading,
  className,
}: PeriodPickerProps) {
  const t = useT('reports')
  return (
    <div className={className}>
      <div className="flex flex-wrap items-center gap-2">
        <div className="w-[170px]">
          <Select
            value={preset}
            onValueChange={(value) => onPresetChange(value as PeriodPreset)}
            options={periodPresetOptions()}
            aria-label={t('aria_period')}
          />
        </div>
        {preset === 'custom' && (
          <>
            <Input
              type="date"
              value={from}
              max={to || undefined}
              onChange={(event) => onFromChange(event.target.value)}
              className="w-[150px]"
              aria-label={t('from_date')}
            />
            <span className="text-sm text-muted-foreground">{t('to_word')}</span>
            <Input
              type="date"
              value={to}
              min={from || undefined}
              onChange={(event) => onToChange(event.target.value)}
              className="w-[150px]"
              aria-label={t('to_date')}
            />
            <Button type="button" variant="secondary" onClick={onApply} disabled={loading}>
              {t('apply')}
            </Button>
          </>
        )}
      </div>
    </div>
  )
}
