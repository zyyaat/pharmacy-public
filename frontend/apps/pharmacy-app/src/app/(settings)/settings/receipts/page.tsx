'use client'

import { useMemo, useState } from 'react'
import { Check, Copy, Loader2, Printer, RotateCcw, Save, ShieldCheck } from 'lucide-react'
import { Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui'
import { usePharmacyContext } from '@/hooks/usePharmacyContext'
import { useReceiptSettings } from '@/hooks/useReceiptSettings'
import ReceiptPrinter, { type ReceiptPrintJob } from '@/components/pos/receipt-printer'
import ReceiptTemplate, { composePharmacyDisplayName } from '@/components/pos/receipt-template'
import type { ReceiptSettings } from '@/lib/api'

/** بادئات جاهزة تظهر قبل اسم الصيدلية في رأس الفاتورة — '' = بدون بادئة */
const NAME_PREFIX_PRESETS: Array<{ value: string; label: string }> = [
  { value: '', label: 'بدون بادئة' },
  { value: 'صيدلية', label: 'صيدلية' },
  { value: 'صيدلية د.', label: 'صيدلية د.' },
  { value: 'صيدلية دكتور', label: 'صيدلية دكتور' },
  { value: 'صيدليات', label: 'صيدليات' },
]

/** بيانات فاتورة تجريبية ثابتة للمعاينة والطباعة الاختبارية */
const SAMPLE_RECEIPT = {
  sale: {
    invoice_number: 1024,
    created_at: '2026-09-09T14:30:00Z',
    total_amount_piastres: 14550,
  },
  items: [
    { product_name: 'بانادول اكسترا', strength: '500mg', sale_unit: 'box' as const, units_per_box: 24, quantity_base: 48, unit_price_piastres: 3600, amount_piastres: 7200 },
    { product_name: 'كاربيمازول 200mg', strength: '', sale_unit: 'strip' as const, units_per_box: 10, quantity_base: 3, unit_price_piastres: 750, amount_piastres: 2250 },
    { product_name: 'كونجستال أقراص', strength: '500mg', sale_unit: 'box' as const, units_per_box: 20, quantity_base: 40, unit_price_piastres: 2550, amount_piastres: 5100 },
  ],
}

export default function SettingsPage() {
  const { settings, loading, save } = useReceiptSettings()
  const { context } = usePharmacyContext()
  const [draft, setDraft] = useState<ReceiptSettings | null>(null)
  const [saving, setSaving] = useState(false)
  const [savedFlash, setSavedFlash] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [printJob, setPrintJob] = useState<ReceiptPrintJob | null>(null)
  const [copied, setCopied] = useState(false)

  // المسودة تبدأ من الإعدادات المحمّلة من الخادم
  const current = draft ?? settings
  const dirty = draft !== null && JSON.stringify(draft) !== JSON.stringify(settings)

  const pharmacy = useMemo(
    () => ({
      name: context?.pharmacy.name ?? 'صيدلية النور',
      city: context?.pharmacy.city ?? 'القاهرة',
      address: context?.pharmacy.address ?? '15 شارع الجمهورية',
      phone: context?.pharmacy.phone ?? '01000000000',
    }),
    [context],
  )
  const cashierName = context?.user.display_name || [context?.user.first_name, context?.user.last_name].filter(Boolean).join(' ') || 'أمين الصيدلية'

  function update(patch: Partial<ReceiptSettings>) {
    setDraft({ ...(current as ReceiptSettings), ...patch })
    setSaveError(null)
  }

  async function handleSave() {
    if (!draft || saving) return
    setSaving(true)
    setSaveError(null)
    try {
      await save(draft)
      setDraft(null)
      setSavedFlash(true)
      setTimeout(() => setSavedFlash(false), 2500)
    } catch (cause) {
      setSaveError(cause instanceof Error ? cause.message : 'تعذر حفظ الإعدادات')
    } finally {
      setSaving(false)
    }
  }

  function testPrint() {
    // الطباعة التجريبية تستخدم المسودة الحالية حتى تختبر قبل الحفظ
    setPrintJob({
      data: SAMPLE_RECEIPT,
      pharmacy,
      cashierName,
      jobId: `test-${Date.now()}`,
    })
  }

  async function copyKioskCommand() {
    try {
      await navigator.clipboard.writeText('"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" --kiosk-printing')
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      /* الحقل نصي عادي يمكن نسخه يدوياً */
    }
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold">الفواتير والطباعة</h1>
        <p className="mt-2 text-sm text-muted-foreground">تحكم كامل في شكل الفاتورة وسلوك الطباعة — الإعدادات تُحفظ على مستوى الصيدلية وتعمل على كل الأجهزة.</p>
      </div>

      {loading ? (
        <Card><CardContent className="flex items-center justify-center gap-2 py-14 text-sm text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> جاري تحميل الإعدادات…
        </CardContent></Card>
      ) : (
        <div className="grid gap-6 lg:grid-cols-[1fr_380px]">
          {/* ------------------------------- النموذج ------------------------------- */}
          <div className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>اسم الصيدلية على الفاتورة</CardTitle>
                <CardDescription>لو الصيدلية مسجّلة باسمك الشخصي، اختار بادئة تظهر قبل الاسم في رأس الفاتورة — أو اكتبها بنفسك.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex flex-wrap gap-2">
                  {NAME_PREFIX_PRESETS.map((preset) => (
                    <button
                      key={preset.label}
                      type="button"
                      aria-pressed={current.name_prefix === preset.value}
                      onClick={() => update({ name_prefix: preset.value })}
                      className={`rounded-full border px-4 py-2 text-sm font-semibold transition-all ${
                        current.name_prefix === preset.value
                          ? 'border-primary bg-primary/5 text-primary ring-4 ring-primary/10'
                          : 'border-border text-muted-foreground hover:border-primary/40 hover:text-foreground'
                      }`}
                    >
                      {preset.label}
                    </button>
                  ))}
                </div>
                <TextField
                  value={current.name_prefix}
                  maxLength={40}
                  onChange={(value) => update({ name_prefix: value })}
                  placeholder="أو اكتب بادئة خاصة — مثال: صيدليات النور"
                />
                <p className="rounded-lg bg-muted/50 px-3 py-2.5 text-sm">
                  يظهر على الفاتورة: <span className="font-extrabold">{composePharmacyDisplayName(current.name_prefix, pharmacy.name) || pharmacy.name || 'صيدلية'}</span>
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>مقاس الورقة</CardTitle>
                <CardDescription>اختر عرض الورق حسب طابعتك الحرارية — القالب يُعاد تنسيقه تلقائياً.</CardDescription>
              </CardHeader>
              <CardContent className="grid gap-3 sm:grid-cols-2">
                {([58, 80] as const).map((width) => (
                  <button
                    key={width}
                    type="button"
                    aria-pressed={current.paper_width_mm === width}
                    onClick={() => update({ paper_width_mm: width })}
                    className={`rounded-xl border p-4 text-right transition-all ${
                      current.paper_width_mm === width ? 'border-primary bg-primary/5 ring-4 ring-primary/10' : 'border-border hover:border-primary/40'
                    }`}
                  >
                    <p className="font-bold">{width} ملم</p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      {width === 80 ? 'المعيار الأشهر — أعمدة مريحة واسم الدواء بسطر واحد' : 'الأصغر والأرخص — الأصناف تتكدد في سطرين'}
                    </p>
                  </button>
                ))}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>وضع الطباعة</CardTitle>
                <CardDescription>متى تُفتح نافذة الطباعة بعد إتمام البيع؟</CardDescription>
              </CardHeader>
              <CardContent className="grid gap-3 sm:grid-cols-2">
                {([
                  { value: 'auto', title: 'تلقائي', desc: 'بعد الحفظ تفتح نافذة الطباعة فوراً — الكاشير يضغط موافقة فقط' },
                  { value: 'manual', title: 'يدوي', desc: 'تظهر رسالة نجاح فيها زر «طباعة الفاتورة» — يطبع عند الحاجة' },
                ] as const).map((mode) => (
                  <button
                    key={mode.value}
                    type="button"
                    aria-pressed={current.print_mode === mode.value}
                    onClick={() => update({ print_mode: mode.value })}
                    className={`rounded-xl border p-4 text-right transition-all ${
                      current.print_mode === mode.value ? 'border-primary bg-primary/5 ring-4 ring-primary/10' : 'border-border hover:border-primary/40'
                    }`}
                  >
                    <p className="font-bold">{mode.title}</p>
                    <p className="mt-1 text-xs text-muted-foreground">{mode.desc}</p>
                  </button>
                ))}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>محتوى الإيصال</CardTitle>
                <CardDescription>ظهر ويخفى حسب حاجتك — والمعاينة الجانبية تتحدث لحظياً.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <ToggleRow
                  label="نسختان (عميل + صيدلية)"
                  desc="تنطبع وراء بعض على نفس الورقة بخط قص"
                  checked={current.copies === 2}
                  onChange={(checked) => update({ copies: checked ? 2 : 1 })}
                />
                <ToggleRow label="رقم التليفون" checked={current.show_phone} onChange={(checked) => update({ show_phone: checked })} />
                <ToggleRow label="العنوان" checked={current.show_address} onChange={(checked) => update({ show_address: checked })} />
                <ToggleRow label="اسم الكاشير" checked={current.show_cashier} onChange={(checked) => update({ show_cashier: checked })} />
                <ToggleRow
                  label="رسالة شكر"
                  checked={current.show_thank_you}
                  onChange={(checked) => update({ show_thank_you: checked })}
                  child={current.show_thank_you && (
                    <TextField
                      value={current.thank_you_text}
                      maxLength={120}
                      onChange={(value) => update({ thank_you_text: value })}
                      placeholder="شكراً لثقتكم"
                    />
                  )}
                />
                <ToggleRow
                  label="سياسة الاسترجاع"
                  checked={current.show_return_policy}
                  onChange={(checked) => update({ show_return_policy: checked })}
                  child={current.show_return_policy && (
                    <TextField
                      value={current.return_policy_text}
                      maxLength={160}
                      onChange={(value) => update({ return_policy_text: value })}
                      placeholder="الاسترجاع خلال 14 يوماً بالإيصال الأصلي"
                    />
                  )}
                />
              </CardContent>
            </Card>

            <Card className="border-primary/30 bg-primary/[0.03]">
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><ShieldCheck className="h-5 w-5 text-primary" />ضمان طباعة سليمة</CardTitle>
                <CardDescription>ثلاث خطوات مرة واحدة على جهاز الكاشير، وبعدها كل إيصال يخرج مضبوطاً.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3 text-sm">
                <ol className="list-inside list-decimal space-y-2 text-muted-foreground">
                  <li>اضبط الطابعة الحرارية كـ<b className="text-foreground">طابعة افتراضية</b> في إعدادات ويندوز.</li>
                  <li>في تفضيلات تعريف الطابعة أنشئ <b className="text-foreground">مقاس ورق مخصص</b> بعرض {current.paper_width_mm}mm وطول حر (Continuous).</li>
                  <li>اضغط <b className="text-foreground">«طباعة اختبار»</b> أعلاه وتأكد من المحاذاة والقطع.</li>
                </ol>
                <div className="rounded-lg border border-border bg-card p-3">
                  <p className="text-xs font-semibold text-foreground">للطباعة الصامتة تماماً (بلا أي تأكيد) — اختياري:</p>
                  <div className="mt-2 flex items-center gap-2">
                    <code dir="ltr" className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap rounded bg-muted px-2 py-1.5 text-[11px]">
                      "C:\Program Files\Google\Chrome\Application\chrome.exe" --kiosk-printing
                    </code>
                    <Button type="button" variant="ghost" size="icon" className="h-8 w-8 shrink-0" onClick={copyKioskCommand} aria-label="نسخ الأمر">
                      {copied ? <Check className="h-4 w-4 text-primary" /> : <Copy className="h-4 w-4" />}
                    </Button>
                  </div>
                  <p className="mt-1.5 text-[11px] text-muted-foreground">شغّل كروم بهذا الاختصار على جهاز الكاشير فقط — نافذة الطباعة ستمر صامتة على الطابعة الافتراضية.</p>
                </div>
              </CardContent>
            </Card>
          </div>

          {/* ------------------------- المعاينة الحية + الأزرار ------------------------- */}
          <div className="space-y-4 lg:sticky lg:top-6 lg:self-start">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><Printer className="h-5 w-5 text-primary" />معاينة حية</CardTitle>
                <CardDescription>بنفس عرض الورقة الحقيقي ({current.paper_width_mm} ملم)</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="flex justify-center rounded-xl bg-muted/60 p-4">
                  <div
                    className="max-w-full overflow-hidden rounded-md border border-neutral-300 bg-white shadow-md"
                    style={{ width: `${current.paper_width_mm}mm` }}
                  >
                    <ReceiptTemplate data={SAMPLE_RECEIPT} pharmacy={pharmacy} cashierName={cashierName} settings={current} />
                  </div>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="flex flex-col gap-2.5 pt-6">
                <Button onClick={handleSave} loading={saving} disabled={!dirty}>
                  <Save className="h-4 w-4" /> حفظ الإعدادات
                </Button>
                <Button variant="outline" onClick={testPrint}>
                  <Printer className="h-4 w-4" /> طباعة اختبار
                </Button>
                {dirty && (
                  <Button variant="ghost" onClick={() => setDraft(null)}>
                    <RotateCcw className="h-4 w-4" /> تراجع عن التعديلات
                  </Button>
                )}
                {savedFlash && <p className="rounded-lg border border-primary/30 bg-primary/10 p-2.5 text-center text-sm text-primary">تم حفظ الإعدادات وتطبيقها على كل الأجهزة</p>}
                {saveError && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-2.5 text-center text-sm text-destructive">{saveError}</p>}
                {!dirty && !savedFlash && <p className="text-center text-xs text-muted-foreground">أي تعديل في النموذج يحدّث المعاينة فوراً قبل الحفظ</p>}
              </CardContent>
            </Card>
          </div>
        </div>
      )}

      {/* مدير طباعة الإيصال — البوابة نفسها مخفية على الشاشة وتظهر في الطباعة فقط */}
      <ReceiptPrinter job={printJob} settings={current} onDone={() => setPrintJob(null)} />
    </div>
  )
}

function ToggleRow({
  label,
  desc,
  checked,
  onChange,
  child,
}: {
  label: string
  desc?: string
  checked: boolean
  onChange: (checked: boolean) => void
  child?: React.ReactNode
}) {
  return (
    <div className="rounded-xl border border-border p-3.5">
      <label className="flex cursor-pointer items-start justify-between gap-3">
        <span>
          <span className="block text-sm font-semibold">{label}</span>
          {desc && <span className="mt-0.5 block text-xs text-muted-foreground">{desc}</span>}
        </span>
        <input
          type="checkbox"
          checked={checked}
          onChange={(event) => onChange(event.target.checked)}
          className="mt-0.5 h-5 w-5 shrink-0 accent-[hsl(var(--primary))]"
        />
      </label>
      {child && <div className="mt-3">{child}</div>}
    </div>
  )
}

function TextField({
  value,
  maxLength,
  onChange,
  placeholder,
}: {
  value: string
  maxLength: number
  onChange: (value: string) => void
  placeholder: string
}) {
  return (
    <div>
      <input
        type="text"
        value={value}
        maxLength={maxLength}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
        className="h-10 w-full rounded-lg border border-input bg-background px-3 text-sm outline-none transition-colors placeholder:text-muted-foreground focus:border-primary focus:ring-4 focus:ring-primary/10"
      />
      <p className="mt-1 text-left text-[11px] text-muted-foreground" dir="ltr">{[...value].length}/{maxLength}</p>
    </div>
  )
}
