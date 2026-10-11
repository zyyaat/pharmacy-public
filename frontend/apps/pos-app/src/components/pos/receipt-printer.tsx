'use client'

import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import ReceiptTemplate, { type ReceiptData, type ReceiptPharmacy } from './receipt-template'
import type { ReceiptSettings } from '@/lib/api'
import { useT } from '@/i18n/provider'

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
  const t = useT('pos')
  const printedJob = useRef<string | null>(null)
  const doneRef = useRef(onDone)
  doneRef.current = onDone

  useEffect(() => setMounted(true), [])

  useEffect(() => {
    if (!job || !mounted) return
    if (printedJob.current === job.jobId) return
    printedJob.current = job.jobId

    document.body.classList.add('printing-receipt')

    let finished = false
    let safety: ReturnType<typeof setTimeout> | undefined
    const finish = () => {
      if (finished) return
      finished = true
      window.removeEventListener('afterprint', finish)
      if (safety !== undefined) clearTimeout(safety)
      document.body.classList.remove('printing-receipt')
      // تصفير الحارس عند الاكتمال: إعادة طباعة نفس الفاتورة تعمل لاحقًا،
      // والحماية من التكرار تشمل المهمة الحية فقط لا وسمًا دائمًا لكل saleId
      printedJob.current = null
      doneRef.current?.()
    }
    // بعض المتصفحات تعيد window.print() قبل إغلاق حوار الطباعة (استدعاء غير
    // متزامن) — والتفريغ الفوري بعد return كان يزيل الإيصال من الـ DOM
    // وصنف العزل من body أثناء فتح الحوار، فيُطبع هيكل الصفحة نفسه بدل
    // الفاتورة. حدث afterprint هو إشارة إغلاق الحوار الموثوقة عبر كل
    // المتصفحات، ومؤقت الأمان يحرر الموارد إن لم يُطلق أبدًا.
    safety = setTimeout(finish, 120000)

    // انتظار طلاء الإطار قبل فتح نافذة الطباعة حتى تكون المعاينة كاملة
    const timer = setTimeout(() => {
      window.addEventListener('afterprint', finish)
      window.print()
    }, 80)

    return () => {
      clearTimeout(timer)
      window.removeEventListener('afterprint', finish)
      if (!finished) {
        if (safety !== undefined) clearTimeout(safety)
        document.body.classList.remove('printing-receipt')
      }
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
            <span>{t('cutHere')}</span>
            <span className="h-px flex-1 border-t border-dashed border-neutral-500" />
          </div>
          <ReceiptTemplate
            data={job.data}
            pharmacy={job.pharmacy}
            cashierName={job.cashierName}
            settings={settings}
            showCopyLabel
            copyLabel={t('copyPharmacy')}
          />
        </>
      )}
    </div>,
    document.body,
  )
}
