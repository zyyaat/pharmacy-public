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

/** تسميات حقول الربط بالعربية */
const FIELDS: Array<{ key: string; label: string; required?: boolean; hint?: string }> = [
  { key: 'name', label: 'اسم الصنف', required: true },
  { key: 'barcode', label: 'الباركود' },
  { key: 'selling_price', label: 'سعر البيع (جنيه)' },
  { key: 'cost_price', label: 'سعر الشراء (جنيه)' },
  { key: 'partial_price', label: 'سعر الشريط (جنيه)', hint: 'لمنتجات البيع بالشريط — يُشتق تلقائيًا إن تُرك فارغًا' },
  { key: 'units_per_box', label: 'عدد الشرائط بالعلبة', hint: '2 أو أكثر يعني منتج يُباع بالشريط' },
  { key: 'quantity', label: 'الكمية' },
  { key: 'min_stock_level', label: 'حد الطلب (بالعلبة الكاملة)' },
  { key: 'expiry_date', label: 'الصلاحية' },
  { key: 'batch_number', label: 'رقم التشغيلة' },
  { key: 'generic_name', label: 'الاسم العلمي' },
  { key: 'strength', label: 'التركيز' },
  { key: 'dosage_form', label: 'الشكل الصيدلي' },
]

const numberFmt = new Intl.NumberFormat('ar-EG-u-nu-latn')

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

  const headerOptions = useMemo(() => {
    if (!preview) return []
    return [
      { value: '-1', label: '— غير مرتبط —' },
      ...preview.headers.map((h, idx) => ({ value: String(idx), label: h || `العمود ${idx + 1}` })),
    ]
  }, [preview])

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
      setError(cause instanceof Error ? cause.message : 'تعذر تحليل الملف')
    } finally {
      setBusy(false)
    }
  }, [])

  /** إعادة تقدير الصلاحية على الربط المعدل */
  const reestimate = useCallback(async (nextMapping: ProductImportMapping) => {
    if (!file) return
    setBusy(true)
    setError(null)
    try {
      const response = await productImportApi.preview(file, nextMapping)
      setPreview(response.data)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر إعادة التقدير')
    } finally {
      setBusy(false)
    }
  }, [file])

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
      setError('يجب ربط عمود اسم الصنف قبل التنفيذ')
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
      setError(cause instanceof Error ? cause.message : 'فشل تنفيذ الترحيل')
    } finally {
      setBusy(false)
    }
  }, [file, mapping, duplicateStrategy, quantityUnit, importStock])

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
  const linkedFields = FIELDS.filter((f) => (mapping[f.key] ?? -1) >= 0)

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold">ترحيل المنتجات</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          استيراد أصناف البرنامج القديم من ملف جداول (Excel بصيغة xlsx أو CSV) — معاينة وربط أعمدة وتقرير مفصل قبل وبعد الترحيل.
        </p>
      </div>

      {/* مؤشر الخطوات */}
      <ol className="flex items-center gap-2 text-sm" aria-label="خطوات الترحيل">
        {[
          { n: 1, label: 'رفع الملف' },
          { n: 2, label: 'المعاينة والربط' },
          { n: 3, label: 'التقرير' },
        ].map((s, idx) => (
          <li key={s.n} className="flex items-center gap-2">
            {idx > 0 && <span className="text-muted-foreground" aria-hidden="true">←</span>}
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
              ارفع ملف المنتجات القديمة
            </CardTitle>
            <CardDescription>
              يُقبل Excel بصيغة xlsx أو ملف CSV — حتى {numberFmt.format(5000)} صفًا وحجم 10 ميجابايت. الصف الفارغ يُهمل تلقائيًا.
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
              <span className="text-sm font-semibold">{busy ? 'جارٍ تحليل الملف…' : 'اسحب الملف هنا أو اضغط للاختيار'}</span>
              <span className="text-xs text-muted-foreground">أول صف في الملف يجب أن يكون صف العناوين</span>
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
                  لا تملك الملف بالصيغة الصحيحة؟ نزّل نموذجنا الجاهز واملأه ببياناتك.
                </span>
              </div>
              <Button
                variant="outline"
                size="sm"
                data-testid="import-template-btn"
                onClick={() => {
                  void productImportApi
                    .template()
                    .then((blob) => downloadBlob(blob, 'نموذج-ترحيل-المنتجات.csv'))
                    .catch((cause) => setError(cause instanceof Error ? cause.message : 'تعذر تحميل النموذج'))
                }}
              >
                <Download className="h-4 w-4" aria-hidden="true" />
                تنزيل النموذج
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
                ربط الأعمدة
                <Badge variant="secondary">{preview.file_type.toUpperCase()}</Badge>
                <Badge variant="outline">{numberFmt.format(preview.total_rows)} صفًا</Badge>
              </CardTitle>
              <CardDescription>
                اقترح النظام الربط تلقائيًا — عدّل ما تشاء وسيُعاد تقدير الصلاحية فورًا.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-5">
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {FIELDS.map((f) => (
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
                      aria-label={`ربط حقل ${f.label}`}
                    />
                    {f.hint && <span className="block text-[11px] text-muted-foreground">{f.hint}</span>}
                  </label>
                ))}
              </div>

              <div className="flex flex-wrap gap-3 text-sm">
                <span className="flex items-center gap-1.5 rounded-full bg-primary/10 px-3 py-1 font-bold text-primary">
                  <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
                  صالح: {numberFmt.format(preview.valid_estimate)}
                </span>
                <span className="flex items-center gap-1.5 rounded-full bg-destructive/10 px-3 py-1 font-bold text-destructive">
                  <XCircle className="h-4 w-4" aria-hidden="true" />
                  به مشكلة: {numberFmt.format(preview.invalid_estimate)}
                </span>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>خيارات الترحيل</CardTitle>
            </CardHeader>
            <CardContent className="grid gap-5 md:grid-cols-2">
              <fieldset className="space-y-2">
                <legend className="text-sm font-bold">الصنف المكرر (نفس الباركود أو الاسم)</legend>
                {[
                  { v: 'skip', label: 'تجاهله والاحتفاظ ببياناته الحالية' },
                  { v: 'update', label: 'تحديث أسعاره وحد طلبه من الملف' },
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
                <p className="text-xs text-muted-foreground">التحديث لا يلمس المخزون القائم ولا نوع التغليف.</p>
              </fieldset>

              <fieldset className="space-y-2">
                <legend className="text-sm font-bold">الكمية في الملف تُحتسب</legend>
                {[
                  { v: 'box', label: 'بالعلبة (تُحوَّل داخليًا إلى شرائط)' },
                  { v: 'strip', label: 'بالشريط / الوحدة الأساسية' },
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
                  ترحيل الكميات كرصيد افتتاحي
                </label>
              </fieldset>
            </CardContent>
          </Card>

          {sampleRows.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="text-base">عينة من الصفوف (أول {numberFmt.format(sampleRows.length)})</CardTitle>
                <CardDescription>الأعمدة المرتبطة فقط تظهر هنا.</CardDescription>
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
                        <TableCell className="text-muted-foreground">{numberFmt.format(ri + 1)}</TableCell>
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
              <ArrowRight className="h-4 w-4" aria-hidden="true" />
              ملف آخر
            </Button>
            <Button onClick={() => void handleExecute()} disabled={busy || (mapping['name'] ?? -1) < 0} data-testid="import-execute-btn">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <ArrowLeft className="h-4 w-4" aria-hidden="true" />}
              بدء الترحيل ({numberFmt.format(preview.valid_estimate)} صنفًا)
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
                انتهى الترحيل
              </CardTitle>
              <CardDescription>
                الصفوف الصالحة رُحِّلت كلها في معاملة واحدة — أي فشل غير متوقع يعني عدم تغيير شيء.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4" data-testid="import-report">
                {[
                  { label: 'أُنشئ', value: report.created, tone: 'text-primary' },
                  { label: 'حُدِّث', value: report.updated, tone: 'text-blue-600' },
                  { label: 'تُخِطي', value: report.skipped, tone: 'text-muted-foreground' },
                  { label: 'رُفض', value: report.failed, tone: 'text-destructive' },
                ].map((s) => (
                  <div key={s.label} className="rounded-xl border bg-muted/20 p-4 text-center">
                    <dt className="text-xs text-muted-foreground">{s.label}</dt>
                    <dd className={`mt-1 text-2xl font-bold ${s.tone}`}>{numberFmt.format(s.value)}</dd>
                  </div>
                ))}
              </dl>
              {report.stock_lines > 0 && (
                <p className="mt-4 text-sm text-muted-foreground">
                  <SkipForward className="mr-1 inline h-4 w-4" aria-hidden="true" />
                  أُضيف {numberFmt.format(report.stock_lines)} رصيدًا افتتاحيًا بتشغيلة «IMPORT».
                </p>
              )}
            </CardContent>
          </Card>

          {report.errors.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                  <AlertTriangle className="h-4 w-4 text-destructive" aria-hidden="true" />
                  الصفوف المرفوضة ({numberFmt.format(report.errors.length)})
                </CardTitle>
                <CardDescription>صحّح هذه الصفوف في ملفك وأعد ترحيلها في جلسة جديدة.</CardDescription>
              </CardHeader>
              <CardContent className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>الصف</TableHead>
                      <TableHead>الصنف</TableHead>
                      <TableHead>السبب</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {report.errors.map((e, i) => (
                      <TableRow key={i}>
                        <TableCell>{numberFmt.format(e.row)}</TableCell>
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
              ترحيل ملف آخر
            </Button>
            <Button onClick={() => window.location.assign('/inventory')}>فتح صفحة المخزون</Button>
          </div>
        </>
      )}
    </div>
  )
}
