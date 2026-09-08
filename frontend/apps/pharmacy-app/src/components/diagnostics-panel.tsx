'use client'

// ============================================================================
// ConnectionDiagnostics — a self-service diagnostics panel for the login page.
//
// Shows a checklist of what is broken (config / server / DB / CORS / auth
// route / cookies) with Arabic explanations. Auto-runs when a connectivity
// error occurs, and can always be launched manually.
// ============================================================================

import { useCallback, useEffect, useRef, useState } from 'react'
import { runConnectionDiagnostics, installDiagnosticsHelper, type DiagnosticCheck, type DiagnosticReport } from '@/lib/diagnostics'

const STATUS_STYLES: Record<DiagnosticCheck['status'], { dot: string; text: string; label: string }> = {
  pass: { dot: 'bg-emerald-500', text: 'text-emerald-600 dark:text-emerald-400', label: 'سليم' },
  fail: { dot: 'bg-red-500', text: 'text-red-600 dark:text-red-400', label: 'فشل' },
  warn: { dot: 'bg-amber-500', text: 'text-amber-600 dark:text-amber-400', label: 'تنبيه' },
}

export function ConnectionDiagnostics({ autoRunKey = 0 }: { autoRunKey?: number }) {
  const [report, setReport] = useState<DiagnosticReport | null>(null)
  const [running, setRunning] = useState(false)
  const [open, setOpen] = useState(false)
  const lastAutoKey = useRef(0)

  const run = useCallback(async () => {
    setRunning(true)
    setOpen(true)
    try {
      const result = await runConnectionDiagnostics()
      setReport(result)
    } finally {
      setRunning(false)
    }
  }, [])

  // Console helper for deeper debugging: window.__diagnose()
  useEffect(() => {
    installDiagnosticsHelper()
  }, [])

  // Auto-run when the parent signals a connectivity failure.
  useEffect(() => {
    if (autoRunKey > 0 && autoRunKey !== lastAutoKey.current) {
      lastAutoKey.current = autoRunKey
      void run()
    }
  }, [autoRunKey, run])

  return (
    <div className="rounded-2xl border border-border bg-background/60">
      <button
        type="button"
        onClick={() => (report ? setOpen((value) => !value) : void run())}
        className="flex w-full items-center justify-between gap-3 px-4 py-3 text-right"
      >
        <span className="flex items-center gap-2 text-sm font-medium">
          <span aria-hidden className="text-base">🩺</span>
          أداة تشخيص الاتصال بالسيرفر
          {report && (
            <span className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${report.ok ? 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400' : 'bg-red-500/15 text-red-600 dark:text-red-400'}`}>
              {report.ok ? 'كل الفحوصات سليمة' : 'يوجد خلل'}
            </span>
          )}
        </span>
        <span className="text-xs text-muted-foreground">{running ? 'جاري الفحص...' : report ? (open ? 'إخفاء' : 'عرض') : 'تشغيل'}</span>
      </button>

      {open && (
        <div className="space-y-3 border-t border-border px-4 py-4">
          {running && <p className="text-sm text-muted-foreground">يتم الآن فحص: الإعدادات ← السيرفر وقاعدة البيانات ← مسار الدخول ← الكوكيز...</p>}

          {report?.checks.map((check) => {
            const style = STATUS_STYLES[check.status]
            return (
              <div key={check.id} className="rounded-xl border border-border bg-card p-3">
                <div className="flex items-center gap-2">
                  <span aria-hidden className={`h-2.5 w-2.5 shrink-0 rounded-full ${style.dot}`} />
                  <p className="text-sm font-semibold">{check.label}</p>
                  <span className={`text-xs font-medium ${style.text}`}>({style.label})</span>
                </div>
                <p className="mt-2 whitespace-pre-wrap text-xs leading-6 text-muted-foreground" dir="auto">
                  {check.detail}
                </p>
              </div>
            )
          })}

          {report && (
            <div className="flex items-center justify-between gap-3 pt-1">
              <p className="text-[11px] text-muted-foreground">آخر فحص: {new Date(report.finishedAt).toLocaleTimeString('ar-EG')}</p>
              <button type="button" onClick={() => void run()} disabled={running} className="rounded-lg border border-border px-3 py-1.5 text-xs font-medium transition-colors hover:bg-accent disabled:opacity-50">
                إعادة الفحص
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
