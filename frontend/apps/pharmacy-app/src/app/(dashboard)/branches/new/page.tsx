'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { ArrowRight, Loader2 } from 'lucide-react'
import { Button, Card, CardContent, CardHeader, CardTitle } from '@/components/ui'
import { pharmacyApi, type BranchWriteInput } from '@/lib/api'
import { RequirePermission } from '@/components/permissions/gate'
import BranchFormFields from '@/components/branches/branch-form-fields'
import { useT } from '@/i18n/provider'

/**
 * إضافة فرع جديد كليًا (Task 50) — POST /pharmacy/branches بصلاحية
 * branches.create، وبعد الحفظ يعود لقائمة الفروع مباشرة.
 */
const EMPTY: BranchWriteInput = { name: '', code: '', phone: '', email: '', address: '', city: '' }

export default function NewBranchPage() {
  const t = useT('employees')
  const router = useRouter()
  const [draft, setDraft] = useState<BranchWriteInput>({ ...EMPTY })
  const [saving, setSaving] = useState(false)
  const [savedFlash, setSavedFlash] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)

  function update(patch: Partial<BranchWriteInput>) {
    setDraft((current) => ({ ...current, ...patch }))
    setSaveError(null)
  }

  async function handleSave() {
    if (saving) return
    if (!draft.name.trim()) {
      setSaveError(t('branchSaveError'))
      return
    }
    setSaving(true)
    setSaveError(null)
    try {
      await pharmacyApi.createBranch(draft)
      setSavedFlash(true)
      // عودة لقائمة الفروع بعد وميض نجاح قصير
      setTimeout(() => router.push('/branches'), 700)
    } catch (cause) {
      setSaveError(cause instanceof Error ? cause.message : t('branchSaveError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <RequirePermission anyOf={['branches.create']}>
      <div className="mx-auto max-w-2xl space-y-6">
        <div>
          <Link href="/branches" className="inline-flex items-center gap-1.5 text-sm font-bold text-primary hover:underline">
            <ArrowRight className="h-4 w-4 rtl-flip" aria-hidden="true" />
            {t('branchesTitle')}
          </Link>
          <h1 className="mt-2 text-2xl font-bold">{t('branchesNewTitle')}</h1>
        </div>
        <Card>
          <CardHeader>
            <CardTitle>{t('branchesAddBtn')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-5">
            <BranchFormFields draft={draft} onChange={update} />

            {saveError && (
              <p role="alert" className="rounded-lg bg-destructive/10 px-3 py-2 text-sm font-semibold text-destructive">
                {saveError}
              </p>
            )}
            {savedFlash && !saveError && (
              <p role="status" className="rounded-lg bg-primary/10 px-3 py-2 text-sm font-semibold text-primary">
                {t('branchCreated')}
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
      </div>
    </RequirePermission>
  )
}
