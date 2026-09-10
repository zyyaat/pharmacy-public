'use client'

import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import ReceiptTemplate, { type ReceiptData, type ReceiptPharmacy } from './receipt-template'
import type { ReceiptSettings } from '@/lib/api'

export interface ReceiptPrintJob {
  data: ReceiptData
  pharmacy: ReceiptPharmacy
  cashierName?: string
  /** معرّف فريد للوظيفة يمنع الطباعة المزدوجة في إعادة تركيب React */
  jobId: string
}

/**
 * مدير طباعة الإيصال: يركّب الإيصال في بوابة خارج هيكل التطبيق، ويضبط مقاس
 * الورقة بالمليمتر من الإعدادات، ثم يستدعي نافذة الطباعة. كل شيء يحدث في
 * متصفح الصيدلية — صفر حمل على الخادم.
 */
export default function ReceiptPrinter({
  job,
  settings,
  onDone,
}: {
  job: ReceiptPrintJob | null
  settings: ReceiptSettings
  onDone?: () => void
}) {
  const [mounted, setMounted] = useState(false)
  const printedJob = useRef<string | null>(null)
  const doneRef = useRef(onDone)
  doneRef.current = onDone

  useEffect(() => setMounted(true), [])

  useEffect(() => {
    if (!job || !mounted) return
    if (printedJob.current === job.jobId) return
    printedJob.current = job.jobId

    document.body.classList.add('printing-receipt')
    // انتظار طلاء الإطار قبل فتح نافذة الطباعة حتى تكون المعاينة كاملة
    const timer = setTimeout(() => {
      try {
        window.print()
      } finally {
        document.body.classList.remove('printing-receipt')
        doneRef.current?.()
      }
    }, 80)

    return () => {
      clearTimeout(timer)
      document.body.classList.remove('printing-receipt')
    }
  }, [job, mounted])

  if (!job || !mounted) return null

  // صفحة حرارية: العرض من الإعدادات والطول حر، بهامش ضئيل يتركه السائق
  const pageRule = `@media print { @page { size: ${settings.paper_width_mm}mm auto; margin: 2mm; } }`

  return createPortal(
    <div id="receipt-print-host">
      <style>{pageRule}</style>
      <ReceiptTemplate data={job.data} pharmacy={job.pharmacy} cashierName={job.cashierName} settings={settings} />
      {settings.copies === 2 && (
        <>
          <div className="flex items-center gap-2 px-[3mm] py-[2mm] text-[10px] text-neutral-600">
            <span className="h-px flex-1 border-t border-dashed border-neutral-500" />
            <span>قص هنا</span>
            <span className="h-px flex-1 border-t border-dashed border-neutral-500" />
          </div>
          <ReceiptTemplate
            data={job.data}
            pharmacy={job.pharmacy}
            cashierName={job.cashierName}
            settings={settings}
            showCopyLabel
            copyLabel="نسخة الصيدلية"
          />
        </>
      )}
    </div>,
    document.body,
  )
}
