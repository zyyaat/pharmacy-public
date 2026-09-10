'use client'

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { useParams, useRouter } from 'next/navigation'
import { ArrowRight, Loader2 } from 'lucide-react'
import { Button, Card, CardContent, CardHeader, CardTitle } from '@/components/ui'
import { pharmacyApi, type BranchWriteInput, type PharmacyBranch } from '@/lib/api'
import { RequirePermission } from '@/components/permissions/gate'
import BranchFormFields from '@/components/branches/branch-form-fields'
import { useT } from '@/i18n/provider'
import { usePharmacyContext } from '@/hooks/usePharmacyContext'

/**
 * تعديل فرع قائم (Task 50) — النموذج يبدأ ممتلئًا ببيانات الفرع الحالية
 * (المعلومات القديمة ظاهرة أثناء التعديل). تعديل الفرع الرئيسي يحدّث
 * معلومات الصيدلية نفسها، فنعيد جلب السياق كي يتحدث الشريط الجانبي فورًا.
 *
 * Task 51 — درس شكوى «الاسم دائمًا الفرع الرئيسي»: حقل اسم الصيدلية يجب أن
 * يُتعبّى من قيمة قاعدة البيانات الحقيقية. المصدر الأساسي: pharmacy_name
 * الذي يُعيده GET /pharmacy/branches حيًا من pharmacies؛ والاحتياط: سياق
 * الصيدلية المحمّل؛ واسم الفرع آخر الملجآت فقط.
 */
function toDraft(branch: PharmacyBranch, contextPharmacyName?: string): BranchWriteInput {
  return {
    name: branch.name,
    code: branch.code ?? '',
    phone: branch.phone ?? '',
    email: branch.email ?? '',
    address: branch.address ?? '',
    city: branch.city ?? '',
    pharmacy_name: branch.is_main
      ? branch.pharmacy_name ?? contextPharmacyName ?? branch.name
      : undefined,
  }
}

export default function EditBranchPage() {
  const t = useT('employees')
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const branchId = params?.id
  const { context, refetch } = usePharmacyContext()
  const [branch, setBranch] = useState<PharmacyBranch | null>(null)
  const [draft, setDraft] = useState<BranchWriteInput | null>(null)
  const [loading, setLoading] = useState(true)
  const [notFound, setNotFound] = useState(false)
  const [saving, setSaving] = useState(false)
  const [savedFlash, setSavedFlash] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)

  const load = useCallback(async () => {
    if (!branchId) return
    setLoading(true)
    setNotFound(false)
    try {
      const response = await pharmacyApi.getBranches()
      const found = response.data.find((item) => item.id === branchId) ?? null
      if (!found) {
        setNotFound(true)
        return
      }
      setBranch(found)
      setDraft(toDraft(found, context?.pharmacy.name))
    } catch (err) {
      setSaveError(err instanceof Error ? err.message : t('branchesLoadErrorFallback'))
    } finally {
      setLoading(false)
    }
  }, [branchId, t, context])

  useEffect(() => {
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [branchId])

  function update(patch: Partial<BranchWriteInput>) {
    setDraft((current) => (current ? { ...current, ...patch } : current))
    setSaveError(null)
  }

  async function handleSave() {
    if (saving || !draft || !branchId) return
    if (!draft.name.trim() || (branch?.is_main && !draft.pharmacy_name?.trim())) {
      setSaveError(t('branchSaveError'))
      return
    }
    setSaving(true)
    setSaveError(null)
    try {
      await pharmacyApi.updateBranch(branchId, draft)
      setSavedFlash(true)
      if (branch?.is_main) {
        // الفرع الرئيسي = معلومات الصيدلية — الشريط الجانبي والفواتير يتحدثان فورًا
        void refetch()
      }
      setTimeout(() => router.push('/branches'), 700)
    } catch (cause) {
      setSaveError(cause instanceof Error ? cause.message : t('branchSaveError'))
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" aria-hidden="true" />
      </div>
    )
  }

  return (
    <RequirePermission anyOf={['branches.update']}>
      <div className="mx-auto max-w-2xl space-y-6">
        <div>
          <Link href="/branches" className="inline-flex items-center gap-1.5 text-sm font-bold text-primary hover:underline">
            <ArrowRight className="h-4 w-4 rtl-flip" aria-hidden="true" />
            {t('branchesTitle')}
          </Link>
          <h1 className="mt-2 text-2xl font-bold">{t('branchesEditTitle')}{branch ? ` — ${branch.name}` : ''}</h1>
        </div>
        {notFound && (
          <Card>
            <CardContent className="py-10 text-center text-muted-foreground">{t('branchesEmpty')}</CardContent>
          </Card>
        )}
        {!notFound && branch && draft && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                {branch.name}
                {branch.is_main && (
                  <span className="rounded-full bg-primary px-2 py-0.5 text-xs font-bold text-primary-foreground">
                    {t('branchMainBadge')}
                  </span>
                )}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-5">
              <BranchFormFields draft={draft} onChange={update} isMain={branch.is_main} />

              {saveError && (
                <p role="alert" className="rounded-lg bg-destructive/10 px-3 py-2 text-sm font-semibold text-destructive">
                  {saveError}
                </p>
              )}
              {savedFlash && !saveError && (
                <p role="status" className="rounded-lg bg-primary/10 px-3 py-2 text-sm font-semibold text-primary">
                  {t('branchSaved')}
                </p>
              )}

              <div className="flex items-center gap-3 border-t border-border pt-4">
                <Button onClick={handleSave} disabled={saving}>
                  {saving && <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />}
                  {t('branchSave')}
                </Button>
                <Link href="/branches">
                  <Button variant="ghost" disabled={saving}>
                    {t('branchCancel')}
                  </Button>
                </Link>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </RequirePermission>
  )
}
