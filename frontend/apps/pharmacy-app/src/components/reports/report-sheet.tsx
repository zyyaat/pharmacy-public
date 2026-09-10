'use client'

// قالب التقرير الموحد — نفس هوية الموقع على الشاشة وعند الطباعة.
// الهيدر يحمل شعار العلامة واسم الصيدلية والفرع وعنوان التقرير والفترة،
// والفوتر يحمل توقيت الإنشاء. الأقسام تُمرَّر كأبناء.

import * as React from 'react'
import { cn } from '@/lib/utils'
import { useT } from '@/i18n/provider'
import { formatArabicDateTime, formatPeriodRange } from '@/lib/reports'

export interface ReportSheetProps {
  /** عنوان التقرير مثل: تقرير المبيعات */
  title: string
  /** وصف قصير تحت العنوان */
  subtitle?: string
  /** أيقونة العنوان */
  icon?: React.ReactNode
  /** فترة التقرير YYYY-MM-DD */
  period?: { from: string; to: string } | null
  /** بيانات الصيدلية من /pharmacy/context */
  pharmacy?: {
    name: string
    city?: string
    branchName?: string
    userName?: string
  } | null
  /** وقت الإنشاء — ثابت لحظة تحميل التقرير حتى لا يتغير عند الطباعة */
  generatedAt?: string
  className?: string
  children: React.ReactNode
}

export function ReportSheet({
  title,
  subtitle,
  icon,
  period,
  pharmacy,
  generatedAt,
  className,
  children,
}: ReportSheetProps) {
  const t = useT('reports')
  return (
    <section
      className={cn(
        'print-sheet overflow-hidden rounded-xl border border-border bg-card shadow-sm',
        className,
      )}
    >
      {/* ترويسة الهوية */}
      <header className="flex flex-wrap items-start justify-between gap-x-6 gap-y-4 border-b border-border bg-muted/30 p-5 sm:p-6">
        <div className="flex items-center gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/brand/pharmacy-os-icon.svg"
            alt=""
            aria-hidden
            className="h-12 w-12 shrink-0"
          />
          <div className="leading-tight">
            <p className="text-base font-bold tracking-tight">Pharmacy OS</p>
            <p className="mt-0.5 text-sm font-medium text-foreground/80">
              {pharmacy?.name || t('default_pharmacy_name')}
              {pharmacy?.city ? ` — ${pharmacy.city}` : ''}
            </p>
            {pharmacy?.branchName && (
              <p className="mt-0.5 text-xs text-muted-foreground">{t('branch_label', { name: pharmacy.branchName })}</p>
            )}
          </div>
        </div>

        <div className="sm:text-end">
          <div className="flex items-center gap-2 sm:justify-end">
            {icon}
            <h2 className="text-lg font-bold sm:text-xl">{title}</h2>
          </div>
          {subtitle && <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>}
          {period && (
            <p className="mt-1 text-sm font-medium tabular-nums text-foreground/80">
              {formatPeriodRange(period.from, period.to)}
            </p>
          )}
        </div>
      </header>

      {/* محتوى التقرير */}
      <div className="space-y-6 p-5 sm:p-6">{children}</div>

      {/* تذييل الهوية */}
      <footer className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border bg-muted/30 px-5 py-3 text-[11px] text-muted-foreground sm:px-6">
        <span className="font-semibold">{t('brand_tagline')}</span>
        {generatedAt && (
          <span className="tabular-nums">
            {pharmacy?.userName
              ? t('generated_note_by', { user: pharmacy.userName, datetime: formatArabicDateTime(generatedAt) })
              : t('generated_note', { datetime: formatArabicDateTime(generatedAt) })}
          </span>
        )}
      </footer>
    </section>
  )
}
