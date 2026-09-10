'use client'

import { Input } from '@/components/ui'
import { useT } from '@/i18n/provider'
import type { BranchWriteInput } from '@/lib/api'

/**
 * حقول نموذج الفرع المشتركة بين الإضافة والتعديل (Task 50).
 * تعديل الفرع الرئيسي يضيف حقل «اسم الصيدلية» لأن تعديله يحدّث
 * معلومات الصيدلية نفسها (الشريط الجانبي + رأس الفاتورة).
 */
export default function BranchFormFields({
  draft,
  onChange,
  isMain,
}: {
  draft: BranchWriteInput
  onChange: (patch: Partial<BranchWriteInput>) => void
  isMain?: boolean
}) {
  const t = useT('employees')

  const fields: Array<{ key: keyof BranchWriteInput; label: string; type?: string; required?: boolean }> = [
    { key: 'name', label: t('branchNameLabel'), required: true },
    { key: 'code', label: t('branchCodeLabel') },
    { key: 'phone', label: t('branchPhoneLabel'), type: 'tel' },
    { key: 'email', label: t('branchEmailLabel'), type: 'email' },
    { key: 'address', label: t('branchAddressLabel') },
    { key: 'city', label: t('branchCityLabel') },
  ]

  return (
    <div className="space-y-5">
      {isMain && (
        <div className="rounded-xl border border-primary/20 bg-primary/5 p-3 text-xs leading-relaxed text-muted-foreground">
          {t('branchMainSyncNote')}
        </div>
      )}
      {isMain && (
        <div>
          <label htmlFor="branch-pharmacy_name" className="mb-1.5 block text-sm font-bold">
            {t('pharmacyNameLabel')} <span className="text-destructive">*</span>
          </label>
          <Input
            id="branch-pharmacy_name"
            value={draft.pharmacy_name ?? ''}
            onChange={(event) => onChange({ pharmacy_name: event.target.value })}
            required
          />
        </div>
      )}
      {fields.map((field) => (
        <div key={field.key}>
          <label htmlFor={`branch-${field.key}`} className="mb-1.5 block text-sm font-bold">
            {field.label.replace(/:$/, '')}
            {field.required && <span className="text-destructive"> *</span>}
          </label>
          <Input
            id={`branch-${field.key}`}
            type={field.type ?? 'text'}
            value={draft[field.key] ?? ''}
            onChange={(event) => onChange({ [field.key]: event.target.value })}
            required={field.required}
          />
        </div>
      ))}
    </div>
  )
}
