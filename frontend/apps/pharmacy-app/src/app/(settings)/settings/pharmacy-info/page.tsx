'use client'

import { useEffect, useState } from 'react'
import { Building2, Loader2, Save } from 'lucide-react'
import {
  Button,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Input,
} from '@/components/ui'
import { pharmacyApi, type PharmacyProfile } from '@/lib/api'
import { usePharmacyContext } from '@/hooks/usePharmacyContext'
import { useT } from '@/i18n/provider'

/**
 * قسم «معلومات الصيدلية» في الإعدادات — تعديل بيانات الصيدلية الحقيقية
 * (اسم الصيدلية + اسم الفرع الرئيسي + التواصل والعنوان).
 *
 * هذه بيانات مدخلة في قاعدة البيانات (وليست نصوص واجهة)، لذلك لا تتأثر
 * بتغيير لغة التطبيق — وهي التي تظهر في الشريط الجانبي ورأس الفاتورة.
 * الحفظ يتطلب صلاحية settings.general، وبعده يُعاد جلب سياق الصيدلية
 * مباشرة حتى يتحدّث الشريط الجانبي فورًا دون إعادة تحميل.
 */
const EMPTY_PROFILE: PharmacyProfile = {
  name: '',
  phone: '',
  email: '',
  address: '',
  city: '',
  branch_name: '',
}

export default function PharmacyInfoSettingsPage() {
  const t = useT('settings')
  const { refetch } = usePharmacyContext()
  const [profile, setProfile] = useState<PharmacyProfile | null>(null)
  const [draft, setDraft] = useState<PharmacyProfile | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [savedFlash, setSavedFlash] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    async function load() {
      try {
        const res = await pharmacyApi.getProfile()
        if (cancelled) return
        setProfile(res.data)
        setDraft(res.data)
      } catch {
        if (!cancelled) setDraft({ ...EMPTY_PROFILE })
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void load()
    return () => {
      cancelled = true
    }
  }, [])

  const current = draft ?? EMPTY_PROFILE
  const dirty = profile !== null && JSON.stringify(draft) !== JSON.stringify(profile)

  function update(patch: Partial<PharmacyProfile>) {
    setDraft({ ...current, ...patch })
    setSaveError(null)
  }

  async function handleSave() {
    if (saving || !draft) return
    if (!draft.name.trim() || !draft.branch_name.trim()) {
      setSaveError(t('profileSaveError'))
      return
    }
    setSaving(true)
    setSaveError(null)
    try {
      const res = await pharmacyApi.updateProfile(draft)
      setProfile(res.data)
      setDraft(res.data)
      setSavedFlash(true)
      setTimeout(() => setSavedFlash(false), 2500)
      // الشريط الجانبي والفواتير يقرأون من سياق الصيدلية — نعيد جلبه فورًا
      void refetch()
    } catch (cause) {
      setSaveError(cause instanceof Error ? cause.message : t('profileSaveError'))
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" aria-hidden="true" />
        <span className="ms-3 text-sm text-muted-foreground">{t('loadingProfile')}</span>
      </div>
    )
  }

  const fields: Array<{
    key: keyof PharmacyProfile
    label: string
    hint?: string
    placeholder: string
    type?: string
    required?: boolean
  }> = [
    {
      key: 'name',
      label: t('fieldName'),
      hint: t('fieldNameHint'),
      placeholder: t('fieldNamePlaceholder'),
      required: true,
    },
    {
      key: 'branch_name',
      label: t('fieldBranchName'),
      hint: t('fieldBranchNameHint'),
      placeholder: t('fieldBranchNamePlaceholder'),
      required: true,
    },
    { key: 'phone', label: t('fieldPhone'), placeholder: t('fieldPhonePlaceholder'), type: 'tel' },
    { key: 'email', label: t('fieldEmail'), placeholder: t('fieldEmailPlaceholder'), type: 'email' },
    { key: 'address', label: t('fieldAddress'), placeholder: t('fieldAddressPlaceholder') },
    { key: 'city', label: t('fieldCity'), placeholder: t('fieldCityPlaceholder') },
  ]

  return (
    <div className="max-w-2xl">
      <header className="mb-6">
        <div className="flex items-center gap-2.5">
          <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/10 text-primary">
            <Building2 className="h-5 w-5" aria-hidden="true" />
          </span>
          <div>
            <h1 className="text-xl font-black">{t('pharmacyInfoTitle')}</h1>
            <p className="mt-0.5 text-sm text-muted-foreground">{t('pharmacyInfoSubtitle')}</p>
          </div>
        </div>
      </header>

      <Card>
        <CardHeader>
          <CardTitle>{t('pharmacyInfoTitle')}</CardTitle>
          <CardDescription>{t('dataNote')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-5">
          {fields.map((field) => (
            <div key={field.key}>
              <label htmlFor={`profile-${field.key}`} className="mb-1.5 block text-sm font-bold">
                {field.label}
                {field.required && <span className="text-destructive"> *</span>}
              </label>
              <Input
                id={`profile-${field.key}`}
                type={field.type ?? 'text'}
                value={current[field.key]}
                placeholder={field.placeholder}
                required={field.required}
                onChange={(event) => update({ [field.key]: event.target.value })}
              />
              {field.hint && <p className="mt-1 text-xs text-muted-foreground">{field.hint}</p>}
            </div>
          ))}

          {saveError && (
            <p role="alert" className="rounded-lg bg-destructive/10 px-3 py-2 text-sm font-semibold text-destructive">
              {saveError}
            </p>
          )}
          {savedFlash && !saveError && (
            <p role="status" className="rounded-lg bg-primary/10 px-3 py-2 text-sm font-semibold text-primary">
              {t('profileSaved')}
            </p>
          )}

          <div className="flex items-center gap-3 border-t border-border pt-4">
            <Button onClick={handleSave} disabled={saving || !dirty}>
              {saving ? (
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
              ) : (
                <Save className="h-4 w-4" aria-hidden="true" />
              )}
              {saving ? t('loadingProfile') : t('saveSettings')}
            </Button>
            {dirty && !saving && (
              <Button variant="ghost" onClick={() => setDraft(profile ? { ...profile } : null)} disabled={saving}>
                {t('profileCancel')}
              </Button>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
