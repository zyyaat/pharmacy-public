'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { Barcode, CheckCircle2, Printer, Save, Sparkles, Trash2 } from 'lucide-react'
import { ApiError, pharmacyApi, type LabelSettingsData, type LabelSettingsUpdate, type LabelSize, type LabelTemplate, type PharmacyProduct } from '@/lib/api'
import { LabelSheet } from '@/components/labels/label-sheet'
import LabelPrintManager, { type LabelPrintJob } from '@/components/labels/label-print-manager'
import { Button, Card, CardContent, CardDescription, CardHeader, CardTitle, Input, Select } from '@/components/ui'
import { useT } from '@/i18n/provider'
import { formatPiastres } from '@/lib/money'

/**
 * لوحة «الباركود والملصقات» — Final Decisions 6/7/8 من التقرير المعتمد:
 *  (أ) قوالب الملصقات: قوالب النظام من السجل المركزي + قوالب مخصصة محفوظة
 *      في pharmacies.settings JSONB (namespace labels) بمعاينة حية بمقاس
 *      المليمتر الحقيقي وطباعة اختبار — لا تسمح كسر مناطق الهدوء لأن
 *      الباركود يُرسم بمكوّن ثابت الحد الأدنى.
 *  (ب) طباعة الدفعات: فلترة المنتجات بلا باركود → توليد جماعي خادمي مؤكد
 *      → شبكة طباعة بالقالب الافتراضي.
 */

type Draft = {
  id?: string
  name: string
  size_id: string
  fields: string[]
  font_scale: number
  show_pharmacy: boolean
}

function templateToDraft(template: LabelTemplate): Draft {
  return {
    id: template.system ? undefined : template.id,
    name: template.system ? '' : template.name,
    size_id: template.size_id,
    fields: [...template.fields],
    font_scale: template.font_scale,
    show_pharmacy: template.show_pharmacy,
  }
}

export default function LabelsPanel() {
  const t = useT('settings')
  const [data, setData] = useState<LabelSettingsData | null>(null)
  const [selectedId, setSelectedId] = useState<string>('')
  const [draft, setDraft] = useState<Draft | null>(null)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [printJob, setPrintJob] = useState<LabelPrintJob | null>(null)

  const load = useCallback(async () => {
    try {
      const response = await pharmacyApi.getLabelSettings()
      setData(response.data)
      setSelectedId((current) => current || response.data.default_template_id)
      setError(null)
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : t('labels_load_failed'))
    }
  }, [t])

  useEffect(() => {
    void load()
  }, [load])

  const templates = data?.templates ?? []
  const selected = templates.find((tpl) => tpl.id === selectedId) ?? templates[0] ?? null

  useEffect(() => {
    setDraft(selected ? templateToDraft(selected) : null)
  }, [selected?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const sizeById = useMemo(() => {
    const map = new Map<string, LabelSize>()
    data?.sizes.forEach((size) => map.set(size.id, size))
    return map
  }, [data?.sizes])

  const draftSize = draft ? sizeById.get(draft.size_id) ?? data?.sizes[0] : undefined

  const sampleProduct = {
    name: t('label_sample_name'),
    generic_name: t('label_sample_generic'),
    strength: '500mg',
    barcode: '2000000000015',
    selling_price_piastres: 6500,
    partial_selling_price_piastres: 1500,
    units_per_box: 5,
    packaging_type: 'BOX_STRIP',
  }

  function toggleField(field: string) {
    if (!draft) return
    const has = draft.fields.includes(field)
    let fields = has ? draft.fields.filter((f) => f !== field) : [...draft.fields, field]
    if (fields.length > 4) return
    if (!fields.includes('barcode')) return // الباركود إلزامي في كل قالب
    fields = fields
    setDraft({ ...draft, fields })
  }

  function moveField(field: string, direction: -1 | 1) {
    if (!draft) return
    const index = draft.fields.indexOf(field)
    const target = index + direction
    if (index < 0 || target < 0 || target >= draft.fields.length) return
    const fields = [...draft.fields]
    ;[fields[index], fields[target]] = [fields[target], fields[index]]
    setDraft({ ...draft, fields })
  }

  async function persist(payload: { default_template_id: string; templates: LabelSettingsUpdate['templates'] }, successMessage: string) {
    setSaving(true)
    setError(null)
    setMessage(null)
    try {
      await pharmacyApi.updateLabelSettings(payload)
      await load()
      setMessage(successMessage)
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : t('labels_save_failed'))
    } finally {
      setSaving(false)
    }
  }

  function saveAsNew() {
    if (!data || !draft) return
    const name = draft.name.trim()
    if (!name) {
      setError(t('labels_name_required'))
      return
    }
    persist(
      {
        default_template_id: data.default_template_id,
        templates: [
          ...data.templates.filter((tpl) => !tpl.system),
          { name, size_id: draft.size_id, fields: draft.fields, font_scale: draft.font_scale, show_pharmacy: draft.show_pharmacy },
        ],
      },
      t('labels_saved_new'),
    )
  }

  function saveEdits() {
    if (!data || !draft?.id) return
    persist(
      {
        default_template_id: data.default_template_id,
        templates: data.templates.filter((tpl) => !tpl.system).map((tpl) =>
          tpl.id === draft.id
            ? { ...tpl, name: draft.name.trim() || tpl.name, size_id: draft.size_id, fields: draft.fields, font_scale: draft.font_scale, show_pharmacy: draft.show_pharmacy }
            : tpl,
        ),
      },
      t('labels_saved_changes'),
    )
  }

  function removeCustom() {
    if (!data || !draft?.id) return
    const rest = data.templates.filter((tpl) => !tpl.system && tpl.id !== draft.id)
    const nextDefault = data.default_template_id === draft.id ? data.templates[0]?.id ?? '' : data.default_template_id
    persist({ default_template_id: nextDefault, templates: rest }, t('labels_deleted'))
  }

  function makeDefault() {
    if (!data || !selected) return
    if (selected.system) {
      // قالب نظام كافتراضي: حفظ فوري للمعرّف فقط
      persist({ default_template_id: selected.id, templates: data.templates.filter((tpl) => !tpl.system) }, t('labels_default_set'))
      return
    }
    persist({ default_template_id: selected.id, templates: data.templates.filter((tpl) => !tpl.system) }, t('labels_default_set'))
  }

  function printTest() {
    if (!draft || !draftSize || !data) return
    const template: LabelTemplate = {
      id: 'preview',
      name: draft.name || t('labels_test_template_name'),
      system: false,
      size_id: draft.size_id,
      fields: draft.fields,
      font_scale: draft.font_scale,
      show_pharmacy: draft.show_pharmacy,
    }
    setPrintJob({
      jobId: `test-${Date.now()}`,
      template,
      size: draftSize,
      products: [sampleProduct],
    })
  }

  return (
    <div className="space-y-6">
      <header className="space-y-1">
        <h1 className="flex items-center gap-2 text-xl font-bold lg:text-2xl"><Barcode className="h-6 w-6 text-primary" />{t('labels_title')}</h1>
        <p className="text-sm text-muted-foreground">{t('labels_subtitle')}</p>
      </header>

      {error && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
      {message && <p className="rounded-lg border border-primary/30 bg-primary/10 p-3 text-sm text-primary">{message}</p>}

      <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
        {/* تحرير القالب */}
        <Card>
          <CardHeader>
            <CardTitle>{t('labels_editor_title')}</CardTitle>
            <CardDescription>{selected?.name}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-5">
            {draft && (
              <>
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <label className="text-sm font-medium text-foreground/80">{t('labels_template_name')}</label>
                    <Input
                      value={draft.name}
                      onChange={(event) => setDraft({ ...draft, name: event.currentTarget.value })}
                      placeholder={selected?.system ? t('labels_system_name_hint') : t('labels_template_name_placeholder')}
                      disabled={!!selected?.system}
                    />
                  </div>
                  <div className="space-y-2">
                    <label className="text-sm font-medium text-foreground/80">{t('labels_template_size')}</label>
                    <Select
                      value={draft.size_id}
                      onValueChange={(value) => setDraft({ ...draft, size_id: value })}
                      options={(data?.sizes ?? []).map((size) => ({ value: size.id, label: size.name }))}
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <label className="text-sm font-medium text-foreground/80">{t('labels_template_fields')}</label>
                  <div className="grid gap-2 sm:grid-cols-2">
                    {(data?.fields ?? []).filter((f) => f !== 'barcode').map((field) => {
                      const active = draft.fields.includes(field)
                      return (
                        <button
                          key={field}
                          type="button"
                          onClick={() => toggleField(field)}
                          className={`rounded-lg border px-3 py-2 text-start text-sm transition ${
                            active ? 'border-primary bg-primary/5 font-semibold text-primary' : 'border-border text-muted-foreground hover:bg-accent'
                          }`}
                        >
                          {t(`labels_field_${field}`)}
                        </button>
                      )
                    })}
                  </div>
                  <p className="text-xs text-muted-foreground">{t('labels_fields_order')}</p>
                  <ul className="space-y-1">
                    {draft.fields.map((field, index) => (
                      <li key={field} className="flex items-center gap-2 rounded-lg bg-muted/50 px-3 py-1.5 text-sm">
                        <span className="flex-1">{t(`labels_field_${field}`)}</span>
                        <button type="button" onClick={() => moveField(field, -1)} disabled={index === 0} className="px-1 text-muted-foreground disabled:opacity-30">↑</button>
                        <button type="button" onClick={() => moveField(field, 1)} disabled={index === draft.fields.length - 1} className="px-1 text-muted-foreground disabled:opacity-30">↓</button>
                      </li>
                    ))}
                  </ul>
                </div>

                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <label className="text-sm font-medium text-foreground/80">{t('labels_font_scale', { scale: draft.font_scale })}</label>
                    <input
                      type="range"
                      min={70}
                      max={200}
                      step={5}
                      value={draft.font_scale}
                      onChange={(event) => setDraft({ ...draft, font_scale: Number(event.currentTarget.value) })}
                      className="w-full"
                    />
                  </div>
                  <label className="flex cursor-pointer items-center gap-2 self-end text-sm">
                    <input
                      type="checkbox"
                      checked={draft.show_pharmacy}
                      onChange={(event) => setDraft({ ...draft, show_pharmacy: event.currentTarget.checked })}
                      className="h-4 w-4"
                    />
                    {t('labels_show_pharmacy')}
                  </label>
                </div>

                <div className="flex flex-wrap gap-2">
                  <Button type="button" variant="outline" onClick={printTest}><Printer className="h-4 w-4" />{t('labels_test_print')}</Button>
                  {selected?.system ? (
                    <Button type="button" loading={saving} onClick={saveAsNew}><Save className="h-4 w-4" />{t('labels_save_as_new')}</Button>
                  ) : (
                    <>
                      <Button type="button" loading={saving} onClick={saveEdits}><Save className="h-4 w-4" />{t('labels_save_changes')}</Button>
                      <Button type="button" variant="outline" loading={saving} onClick={saveAsNew}><Sparkles className="h-4 w-4" />{t('labels_save_as_new')}</Button>
                      <Button type="button" variant="outline" onClick={removeCustom}><Trash2 className="h-4 w-4" />{t('labels_delete')}</Button>
                    </>
                  )}
                  {data && data.default_template_id !== selected?.id && (
                    <Button type="button" variant="outline" loading={saving} onClick={makeDefault}><CheckCircle2 className="h-4 w-4" />{t('labels_set_default')}</Button>
                  )}
                </div>
              </>
            )}
          </CardContent>
        </Card>

        {/* قائمة القوالب + المعاينة الحية */}
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>{t('labels_templates_title')}</CardTitle>
              <CardDescription>{t('labels_templates_desc')}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-1.5">
              {templates.map((template) => (
                <button
                  key={template.id}
                  type="button"
                  onClick={() => setSelectedId(template.id)}
                  className={`flex w-full items-center justify-between gap-2 rounded-lg border px-3 py-2 text-start text-sm transition ${
                    template.id === selected?.id ? 'border-primary bg-primary/5 font-semibold text-primary' : 'border-border text-muted-foreground hover:bg-accent'
                  }`}
                >
                  <span className="min-w-0 truncate">{template.name}</span>
                  <span className="flex shrink-0 items-center gap-1.5">
                    {data?.default_template_id === template.id && (
                      <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] font-bold text-primary">{t('labels_default_badge')}</span>
                    )}
                    <span className="rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">{template.size_id}</span>
                    {template.system && <span className="rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">{t('labels_system_badge')}</span>}
                  </span>
                </button>
              ))}
            </CardContent>
          </Card>

          {draft && draftSize && (
            <Card>
              <CardHeader>
                <CardTitle>{t('labels_preview_title')}</CardTitle>
                <CardDescription>{t('labels_preview_desc')}</CardDescription>
              </CardHeader>
              <CardContent className="flex justify-center overflow-x-auto rounded-lg bg-neutral-200 p-4">
                <div className="shadow-md">
                  <LabelSheet
                    template={{
                      id: 'preview',
                      name: draft.name || 'preview',
                      system: false,
                      size_id: draft.size_id,
                      fields: draft.fields,
                      font_scale: draft.font_scale,
                      show_pharmacy: draft.show_pharmacy,
                    }}
                    size={draftSize}
                    product={sampleProduct}
                    pharmacyName={t('labels_sample_pharmacy')}
                  />
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </div>

      <BatchPrintSection onPrint={(job) => setPrintJob(job)} reloadSignal={message} />

      <LabelPrintManager job={printJob} />
    </div>
  )
}

/** منطقة طباعة الدفعات — التوليد الجماعي الخادمي ثم شبكة الطباعة */
function BatchPrintSection({ onPrint, reloadSignal }: { onPrint: (job: LabelPrintJob) => void; reloadSignal: string | null }) {
  const t = useT('settings')
  const [products, setProducts] = useState<PharmacyProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [missingOnly, setMissingOnly] = useState(true)
  const [search, setSearch] = useState('')
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [generating, setGenerating] = useState(false)
  const [printing, setPrinting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const response = await pharmacyApi.listProducts(search, missingOnly)
      setProducts(response.data)
      setError(null)
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : t('labels_products_load_failed'))
    } finally {
      setLoading(false)
    }
  }, [missingOnly, search, t])

  useEffect(() => {
    const timer = setTimeout(() => void load(), search ? 250 : 0)
    return () => clearTimeout(timer)
  }, [load, search, reloadSignal])

  function toggle(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function bulkGenerate() {
    if (selectedIds.size === 0 || generating) return
    const confirmed = window.confirm(t('labels_bulk_confirm', { count: selectedIds.size }))
    if (!confirmed) return
    setGenerating(true)
    setError(null)
    setNotice(null)
    try {
      const response = await pharmacyApi.bulkGenerateBarcodes([...selectedIds])
      setNotice(t('labels_bulk_done', { generated: response.data.generated, requested: response.data.requested }))
      setSelectedIds(new Set())
      await load()
    } catch (cause) {
      setError(cause instanceof ApiError ? cause.message : t('labels_bulk_failed'))
    } finally {
      setGenerating(false)
    }
  }

  async function printSelected() {
    if (selectedIds.size === 0 || printing) return
    const chosen = products.filter((product) => selectedIds.has(product.id) && product.barcode)
    if (chosen.length === 0) {
      setError(t('labels_no_barcode_selected'))
      return
    }
    setPrinting(true)
    setError(null)
    try {
      const [labels, context] = await Promise.all([
        pharmacyApi.getLabelSettings(),
        pharmacyApi.getContext().catch(() => null),
      ])
      const data = labels.data
      const template = data.templates.find((tpl) => tpl.id === data.default_template_id) ?? data.templates[0]
      const size = data.sizes.find((s) => s.id === template?.size_id) ?? data.sizes[0]
      if (!template || !size) {
        setError(t('labels_load_failed'))
        return
      }
      onPrint({
        jobId: `batch-${Date.now()}`,
        template,
        size,
        pharmacyName: context?.pharmacy?.name ?? '',
        products: chosen.map((product) => ({
          name: product.name,
          generic_name: product.generic_name,
          strength: product.strength,
          barcode: product.barcode,
          selling_price_piastres: product.selling_price_piastres,
          partial_selling_price_piastres: product.partial_selling_price_piastres,
          units_per_box: product.units_per_box,
          packaging_type: product.packaging_type,
        })),
      })
    } finally {
      setPrinting(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('labels_batch_title')}</CardTitle>
        <CardDescription>{t('labels_batch_desc')}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap items-center gap-3">
          <label className="flex cursor-pointer items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={missingOnly}
              onChange={(event) => {
                setMissingOnly(event.currentTarget.checked)
                setSelectedIds(new Set())
              }}
              className="h-4 w-4"
            />
            {t('labels_missing_only')}
          </label>
          <div className="min-w-[200px] flex-1">
            <Input
              value={search}
              onChange={(event) => setSearch(event.currentTarget.value)}
              placeholder={t('labels_search_placeholder')}
            />
          </div>
        </div>

        <div className="max-h-80 overflow-y-auto rounded-lg border border-border">
          {loading ? (
            <p className="p-6 text-center text-sm text-muted-foreground">{t('labels_loading_products')}</p>
          ) : products.length === 0 ? (
            <p className="p-6 text-center text-sm text-muted-foreground">{t('labels_no_products')}</p>
          ) : (
            <ul className="divide-y divide-border">
              {products.map((product) => (
                <li key={product.id}>
                  <label className="flex cursor-pointer items-center gap-3 px-4 py-2.5 text-sm hover:bg-accent/50">
                    <input
                      type="checkbox"
                      checked={selectedIds.has(product.id)}
                      onChange={() => toggle(product.id)}
                      className="h-4 w-4"
                    />
                    <span className="min-w-0 flex-1 truncate font-medium">{product.name}</span>
                    {product.barcode ? (
                      <span className="shrink-0 font-mono text-xs text-muted-foreground" dir="ltr">{product.barcode}</span>
                    ) : (
                      <span className="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold text-amber-700">{t('labels_no_barcode_badge')}</span>
                    )}
                    <span className="w-20 shrink-0 text-end text-xs text-muted-foreground">{formatPiastres(product.selling_price_piastres)}</span>
                  </label>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <span className="text-sm text-muted-foreground">{t('labels_selected_count', { count: selectedIds.size })}</span>
          <Button type="button" variant="outline" loading={generating} disabled={selectedIds.size === 0} onClick={bulkGenerate}>
            <Barcode className="h-4 w-4" />
            {t('labels_bulk_generate')}
          </Button>
          <Button type="button" variant="outline" loading={printing} disabled={selectedIds.size === 0} onClick={printSelected}>
            <Printer className="h-4 w-4" />
            {t('labels_print_selected')}
          </Button>
        </div>

        {error && <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
        {notice && <p className="rounded-lg border border-primary/30 bg-primary/10 p-3 text-sm text-primary">{notice}</p>}
      </CardContent>
    </Card>
  )
}
