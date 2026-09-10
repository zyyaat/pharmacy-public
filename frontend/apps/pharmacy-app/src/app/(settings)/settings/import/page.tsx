'use client'

import { useCallback, useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  CheckCircle2,
  Download,
  FileSpreadsheet,
  Info,
  Loader2,
  RotateCcw,
  SkipForward,
  Upload,
  XCircle,
} from 'lucide-react'
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Select, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { productImportApi, type ProductImportMapping, type ProductImportPreview, type ProductImportReport } from '@/lib/api'
import { fmtNumber } from '@/i18n/format'
import { useT } from '@/i18n/provider'

/**
 * ترحيل المنتجات — استيراد أصناف البرامج القديمة من ملف جداول (Excel/CSV).
 *
 * معالج ثلاثي الخطوات وفق ممارسات أدوات الاستيراد الاحترافية:
 *   1) رفع الملف (+ نموذج جاهز للتنزيل)؛
 *   2) معاينة: ربط الأعمدة المقترح تلقائيًا قابل للتعديل + عينة صفوف + خيارات
 *      (سياسة التكرار / وحدة الكمية / ترحيل الرصيد)؛
 *   3) تنفيذ ذري للصفوف الصالحة مع تقرير مفصل بأسباب رفض كل صف.
 */

type Step = 1 | 2 | 3

type ImportField = { key: string; label: string; required?: boolean; hint?: string }

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

export default function ProductImportPage() {
  const t = useT('settings')
  const [step, setStep] = useState<Step>(1)
  const [file, setFile] = useState<File | null>(null)
  const [preview, setPreview] = useState<ProductImportPreview | null>(null)
  const [mapping, setMapping] = useState<ProductImportMapping>({})
  const [duplicateStrategy, setDuplicateStrategy] = useState<'skip' | 'update'>('skip')
  const [quantityUnit, setQuantityUnit] = useState<'box' | 'strip'>('box')
  const [importStock, setImportStock] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [report, setReport] = useState<ProductImportReport | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  /** تسميات حقول الربط (مُعرّبة من القاموس) */
  const fields: ImportField[] = [
    { key: 'name', label: t('fieldName'), required: true },
    { key: 'barcode', label: t('fieldBarcode') },
    { key: 'selling_price', label: t('fieldSellingPrice') },
    { key: 'cost_price', label: t('fieldCostPrice') },
    { key: 'partial_price', label: t('fieldPartialPrice'), hint: t('fieldPartialPriceHint') },
    { key: 'units_per_box', label: t('fieldUnitsPerBox'), hint: t('fieldUnitsPerBoxHint') },
    { key: 'quantity', label: t('fieldQuantity') },
    { key: 'min_stock_level', label: t('fieldMinStock') },
    { key: 'expiry_date', label: t('fieldExpiry') },
    { key: 'batch_number', label: t('fieldBatch') },
    { key: 'generic_name', label: t('fieldGenericName') },
    { key: 'strength', label: t('fieldStrength') },
    { key: 'dosage_form', label: t('fieldDosageForm') },
  ]

  const headerOptions = useMemo(() => {
    if (!preview) return []
    return [
      { value: '-1', label: t('unlinkedOption') },
      ...preview.headers.map((h, idx) => ({ value: String(idx), label: h || t('columnN', { n: idx + 1 }) })),
    ]
  }, [preview, t])

  const handleFilePicked = useCallback(async (picked: File) => {
    setError(null)
    setBusy(true)
    setReport(null)
    try {
      const response = await productImportApi.preview(picked)
      setFile(picked)
      setPreview(response.data)
      setMapping({ ...response.data.mapping })
      setStep(2)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : t('parseErrorFallback'))
    } finally {
      setBusy(false)
    }
  }, [t])

  /** إعادة تقدير الصلاحية على الربط المعدل */
  const reestimate = useCallback(async (nextMapping: ProductImportMapping) => {
    if (!file) return
    setBusy(true)
    setError(null)
    try {
      const response = await productImportApi.preview(file, nextMapping)
      setPreview(response.data)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : t('reestimateErrorFallback'))
    } finally {
      setBusy(false)
    }
  }, [file, t])

  const setField = useCallback((field: string, value: string) => {
    const idx = Number(value)
    setMapping((prev) => {
      const next = { ...prev, [field]: Number.isFinite(idx) ? idx : -1 }
      void reestimate(next)
      return next
    })
  }, [reestimate])

  const handleExecute = useCallback(async () => {
    if (!file) return
    if (mapping['name'] === undefined || mapping['name'] < 0) {
      setError(t('nameColumnRequired'))
      return
    }
    setBusy(true)
    setError(null)
    try {
      const response = await productImportApi.execute(file, mapping, {
        duplicate_strategy: duplicateStrategy,
        quantity_unit: quantityUnit,
        import_stock: importStock,
      })
      setReport(response.data)
      setStep(3)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : t('executeErrorFallback'))
    } finally {
      setBusy(false)
    }
  }, [file, mapping, duplicateStrategy, quantityUnit, importStock, t])

  const reset = useCallback(() => {
    setStep(1)
    setFile(null)
    setPreview(null)
    setMapping({})
    setReport(null)
    setError(null)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }, [])

  const sampleRows = preview?.rows.slice(0, 8) ?? []
  const linkedFields = fields.filter((f) => (mapping[f.key] ?? -1) >= 0)

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold">{t('importTitle')}</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          {t('importSubtitle')}
        </p>
      </div>

      {/* مؤشر الخطوات */}
      <ol className="flex items-center gap-2 text-sm" aria-label={t('stepsAria')}>
        {[
          { n: 1, label: t('stepUpload') },
          { n: 2, label: t('stepPreview') },
          { n: 3, label: t('stepReport') },
        ].map((s, idx) => (
          <li key={s.n} className="flex items-center gap-2">
            {idx > 0 && <span className="text-muted-foreground rtl-flip" aria-hidden="true">←</span>}
            <span
              aria-current={step === s.n ? 'step' : undefined}
              className={`flex items-center gap-1.5 rounded-full px-3 py-1 ${
                step === s.n ? 'bg-primary text-primary-foreground font-bold' : step > s.n ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'
              }`}
            >
              <span className="font-bold">{s.n}</span>
              {s.label}
            </span>
          </li>
        ))}
      </ol>

      {error && (
        <div role="alert" className="flex items-start gap-2 rounded-xl border border-destructive/30 bg-destructive/10 p-4 text-sm text-destructive">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
          <span>{error}</span>
        </div>
      )}

      {/* ============ الخطوة 1: رفع الملف ============ */}
      {step === 1 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Upload className="h-5 w-5" aria-hidden="true" />
              {t('uploadTitle')}
            </CardTitle>
            <CardDescription>
              {t('uploadDesc', { rows: fmtNumber(5000) })}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <label
              className="flex cursor-pointer flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed border-border bg-muted/30 p-10 text-center transition-colors hover:border-primary/50 hover:bg-primary/5"
              onDragOver={(e) => e.preventDefault()}
              onDrop={(e) => {
                e.preventDefault()
                const dropped = e.dataTransfer.files?.[0]
                if (dropped) void handleFilePicked(dropped)
              }}
            >
              {busy ? (
                <Loader2 className="h-8 w-8 animate-spin text-primary" aria-hidden="true" />
              ) : (
                <FileSpreadsheet className="h-8 w-8 text-primary" aria-hidden="true" />
              )}
              <span className="text-sm font-semibold">{busy ? t('parsingFile') : t('dropHere')}</span>
              <span className="text-xs text-muted-foreground">{t('firstRowHint')}</span>
              <input
                ref={fileInputRef}
                type="file"
                accept=".xlsx,.csv,.txt"
                className="sr-only"
                data-testid="import-file-input"
                onChange={(e) => {
                  const picked = e.target.files?.[0]
                  if (picked) void handleFilePicked(picked)
                }}
              />
            </label>

            <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-muted/20 p-4">
              <div className="flex items-start gap-2 text-sm">
                <Info className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden="true" />
                <span>
                  {t('templateHint')}
                </span>
              </div>
              <Button
                variant="outline"
                size="sm"
                data-testid="import-template-btn"
                onClick={() => {
                  void productImportApi
                    .template()
                    .then((blob) => downloadBlob(blob, t('templateFileName')))
                    .catch((cause) => setError(cause instanceof Error ? cause.message : t('templateErrorFallback')))
                }}
              >
                <Download className="h-4 w-4" aria-hidden="true" />
                {t('downloadTemplate')}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ============ الخطوة 2: المعاينة والربط ============ */}
      {step === 2 && preview && (
        <>
          <Card>
            <CardHeader>
              <CardTitle className="flex flex-wrap items-center gap-2">
                <FileSpreadsheet className="h-5 w-5" aria-hidden="true" />
                {t('mappingTitle')}
                <Badge variant="secondary">{preview.file_type.toUpperCase()}</Badge>
                <Badge variant="outline">{t('rowsBadge', { rows: fmtNumber(preview.total_rows) })}</Badge>
              </CardTitle>
              <CardDescription>
                {t('mappingDesc')}
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-5">
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {fields.map((f) => (
                  <label key={f.key} className="block space-y-1">
                    <span className="block text-xs font-bold text-foreground">
                      {f.label}
                      {f.required && <span className="text-destructive"> *</span>}
                    </span>
                    <Select
                      options={headerOptions}
                      value={String(mapping[f.key] ?? -1)}
                      onValueChange={(v) => setField(f.key, v)}
                      size="sm"
                      aria-label={t('mapFieldAria', { field: f.label })}
                    />
                    {f.hint && <span className="block text-[11px] text-muted-foreground">{f.hint}</span>}
                  </label>
                ))}
              </div>

              <div className="flex flex-wrap gap-3 text-sm">
                <span className="flex items-center gap-1.5 rounded-full bg-primary/10 px-3 py-1 font-bold text-primary">
                  <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
                  {t('validBadge', { rows: fmtNumber(preview.valid_estimate) })}
                </span>
                <span className="flex items-center gap-1.5 rounded-full bg-destructive/10 px-3 py-1 font-bold text-destructive">
                  <XCircle className="h-4 w-4" aria-hidden="true" />
                  {t('invalidBadge', { rows: fmtNumber(preview.invalid_estimate) })}
                </span>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>{t('optionsTitle')}</CardTitle>
            </CardHeader>
            <CardContent className="grid gap-5 md:grid-cols-2">
              <fieldset className="space-y-2">
                <legend className="text-sm font-bold">{t('duplicateLegend')}</legend>
                {[
                  { v: 'skip', label: t('duplicateSkip') },
                  { v: 'update', label: t('duplicateUpdate') },
                ].map((o) => (
                  <label key={o.v} className="flex items-center gap-2 text-sm">
                    <input
                      type="radio"
                      name="duplicate_strategy"
                      value={o.v}
                      checked={duplicateStrategy === o.v}
                      onChange={() => setDuplicateStrategy(o.v as 'skip' | 'update')}
                      className="h-4 w-4 accent-[var(--primary)]"
                    />
                    {o.label}
                  </label>
                ))}
                <p className="text-xs text-muted-foreground">{t('duplicateNote')}</p>
              </fieldset>

              <fieldset className="space-y-2">
                <legend className="text-sm font-bold">{t('quantityLegend')}</legend>
                {[
                  { v: 'box', label: t('quantityBox') },
                  { v: 'strip', label: t('quantityStrip') },
                ].map((o) => (
                  <label key={o.v} className="flex items-center gap-2 text-sm">
                    <input
                      type="radio"
                      name="quantity_unit"
                      value={o.v}
                      checked={quantityUnit === o.v}
                      onChange={() => setQuantityUnit(o.v as 'box' | 'strip')}
                      className="h-4 w-4 accent-[var(--primary)]"
                    />
                    {o.label}
                  </label>
                ))}
                <label className="flex items-center gap-2 text-sm font-semibold">
                  <input
                    type="checkbox"
                    checked={importStock}
                    onChange={(e) => setImportStock(e.target.checked)}
                    className="h-4 w-4 accent-[var(--primary)]"
                  />
                  {t('importStockLabel')}
                </label>
              </fieldset>
            </CardContent>
          </Card>

          {sampleRows.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="text-base">{t('sampleTitle', { rows: fmtNumber(sampleRows.length) })}</CardTitle>
                <CardDescription>{t('sampleDesc')}</CardDescription>
              </CardHeader>
              <CardContent className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>#</TableHead>
                      {linkedFields.map((f) => (
                        <TableHead key={f.key}>{f.label}</TableHead>
                      ))}
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {sampleRows.map((row, ri) => (
                      <TableRow key={ri}>
                        <TableCell className="text-muted-foreground">{fmtNumber(ri + 1)}</TableCell>
                        {linkedFields.map((f) => (
                          <TableCell key={f.key}>{row[mapping[f.key]] || '—'}</TableCell>
                        ))}
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}

          <div className="flex flex-wrap items-center justify-between gap-3">
            <Button variant="ghost" onClick={reset}>
              <ArrowRight className="h-4 w-4 rtl-flip" aria-hidden="true" />
              {t('anotherFile')}
            </Button>
            <Button onClick={() => void handleExecute()} disabled={busy || (mapping['name'] ?? -1) < 0} data-testid="import-execute-btn">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <ArrowLeft className="h-4 w-4 rtl-flip" aria-hidden="true" />}
              {t('executeBtn', { rows: fmtNumber(preview.valid_estimate) })}
            </Button>
          </div>
        </>
      )}

      {/* ============ الخطوة 3: التقرير ============ */}
      {step === 3 && report && (
        <>
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <CheckCircle2 className="h-5 w-5 text-primary" aria-hidden="true" />
                {t('doneTitle')}
              </CardTitle>
              <CardDescription>
                {t('doneDesc')}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4" data-testid="import-report">
                {[
                  { label: t('reportCreated'), value: report.created, tone: 'text-primary' },
                  { label: t('reportUpdated'), value: report.updated, tone: 'text-blue-600' },
                  { label: t('reportSkipped'), value: report.skipped, tone: 'text-muted-foreground' },
                  { label: t('reportFailed'), value: report.failed, tone: 'text-destructive' },
                ].map((s) => (
                  <div key={s.label} className="rounded-xl border bg-muted/20 p-4 text-center">
                    <dt className="text-xs text-muted-foreground">{s.label}</dt>
                    <dd className={`mt-1 text-2xl font-bold ${s.tone}`}>{fmtNumber(s.value)}</dd>
                  </div>
                ))}
              </dl>
              {report.stock_lines > 0 && (
                <p className="mt-4 text-sm text-muted-foreground">
                  <SkipForward className="ms-1 inline h-4 w-4" aria-hidden="true" />
                  {t('stockLinesNote', { rows: fmtNumber(report.stock_lines) })}
                </p>
              )}
            </CardContent>
          </Card>

          {report.errors.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                  <AlertTriangle className="h-4 w-4 text-destructive" aria-hidden="true" />
                  {t('rejectedTitle', { count: fmtNumber(report.errors.length) })}
                </CardTitle>
                <CardDescription>{t('rejectedDesc')}</CardDescription>
              </CardHeader>
              <CardContent className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('thRow')}</TableHead>
                      <TableHead>{t('thProduct')}</TableHead>
                      <TableHead>{t('thReason')}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {report.errors.map((e, i) => (
                      <TableRow key={i}>
                        <TableCell>{fmtNumber(e.row)}</TableCell>
                        <TableCell>{e.name || '—'}</TableCell>
                        <TableCell className="text-destructive">{e.reason}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}

          <div className="flex flex-wrap justify-between gap-3">
            <Button variant="outline" onClick={reset}>
              <RotateCcw className="h-4 w-4" aria-hidden="true" />
              {t('importAnotherFile')}
            </Button>
            <Button onClick={() => window.location.assign('/inventory')}>{t('openInventory')}</Button>
          </div>
        </>
      )}
    </div>
  )
}
