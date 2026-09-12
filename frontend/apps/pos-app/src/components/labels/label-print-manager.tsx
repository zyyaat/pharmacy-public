'use client'

import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { LabelSheet, type LabelSizeView, type LabelTemplateView, type LabelProductView } from './label-sheet'

export interface LabelPrintJob {
  /** معرّف فريد يمنع الطباعة المزدوجة في إعادة تركيب React */
  jobId: string
  template: LabelTemplateView
  size: LabelSizeView
  products: LabelProductView[]
  pharmacyName?: string
}

/**
 * مدير طباعة الملصقات — نفس معمارية طباعة الإيصال حرفيًا (Final Decision 8):
 * بوابة خارج هيكل التطبيق + @page بمقاس الملصق بالمليمتر + نافذة طباعة
 * المتصفح. كل شيء في جهاز الصيدلية، صفر حمل على الخادم، وأي طابعة ملصقات
 * مثبتة بالنظام (حرارية 203dpi أو غيرها) تعمل من نفس الزر.
 *
 * الملصقات تُصفّ في شبكة بأقصى عدد يلائم عرض الورقة الواحدة؛ الطابعات
 * الحرارية ذات الورقة المستمرة تأخذ كل ملصق كسطر مستقل بهامش قطع.
 */
export default function LabelPrintManager({ job, onDone }: { job: LabelPrintJob | null; onDone?: () => void }) {
  const [mounted, setMounted] = useState(false)
  const printedJob = useRef<string | null>(null)
  const doneRef = useRef(onDone)
  doneRef.current = onDone

  useEffect(() => setMounted(true), [])

  useEffect(() => {
    if (!job || !mounted) return
    if (printedJob.current === job.jobId) return
    printedJob.current = job.jobId

    document.body.classList.add('printing-labels')
    const timer = setTimeout(() => {
      try {
        window.print()
      } finally {
        document.body.classList.remove('printing-labels')
        doneRef.current?.()
      }
    }, 80)

    return () => {
      clearTimeout(timer)
      document.body.classList.remove('printing-labels')
    }
  }, [job, mounted])

  if (!job || !mounted) return null

  const pageRule = `@media print { @page { size: ${job.size.width_mm}mm ${job.size.height_mm}mm; margin: 0; }
    body * { visibility: hidden; }
    #label-print-host, #label-print-host * { visibility: visible; }
    #label-print-host { position: absolute; inset: 0; }
  }`

  return createPortal(
    <div id="label-print-host">
      <style>{pageRule}</style>
      {job.products.map((product, index) => (
        <div key={`${job.jobId}-${index}`} style={{ breakAfter: 'page', pageBreakAfter: job.products.length - 1 === index ? 'auto' : 'always' }}>
          <LabelSheet
            template={job.template}
            size={job.size}
            product={product}
            pharmacyName={job.pharmacyName}
          />
        </div>
      ))}
    </div>,
    document.body,
  )
}
