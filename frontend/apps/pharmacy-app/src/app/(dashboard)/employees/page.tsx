'use client'

// الموظفون + نظام الصلاحيات المرن (Task 42):
// - قائمة الموظفين مع ملخص صلاحيات كل موظف
// - إضافة موظف جديد (بيانات + قالب جاهز + تخصيص الصلاحيات بالمفاتيح)
// - تعديل صلاحيات موظف قائم في أي وقت
// - تفعيل/إيقاف حساب الموظف
// إدارة الصلاحيات متاحة لمن يملك employees.manage_permissions،
// وإضافة الموظفين لمن يملك employees.create — والباقي عرض فقط.

import { useCallback, useEffect, useState } from 'react'
import { Power, Shield, ShieldCheck, UserRoundPlus, Users } from 'lucide-react'
import {
  ApiError,
  pharmacyApi,
  type EmployeePermissions,
  type PharmacyBranch,
  type PharmacyEmployee,
} from '@/lib/api'
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Input } from '@/components/ui'
import { PermissionsEditor, usePermissionCatalog } from '@/components/employees/permissions-editor'
import { RequirePermission } from '@/components/permissions/gate'
import { usePermissions } from '@/hooks/usePermissions'
import { useT } from '@/i18n/provider'

function fieldLabel(value: string, labels: Record<string, string>) {
  return labels[value] || value
}

export default function EmployeesPage() {
  const t = useT('employees')
  const { can } = usePermissions()
  const canManage = can('employees.manage_permissions')
  const canCreate = can('employees.create')

  const [items, setItems] = useState<PharmacyEmployee[]>([])
  const [branches, setBranches] = useState<PharmacyBranch[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  // نافذة إضافة موظف
  const [showAdd, setShowAdd] = useState(false)
  const [form, setForm] = useState({ first_name: '', last_name: '', email: '', password: '', phone: '', job_title: '', branch_id: '' })
  const [newPerms, setNewPerms] = useState<string[]>([])
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)

  // نافذة تعديل الصلاحيات
  const [editing, setEditing] = useState<PharmacyEmployee | null>(null)
  const [editingPerms, setEditingPerms] = useState<string[]>([])
  const [editingOriginal, setEditingOriginal] = useState<string[]>([])
  const [loadingPerms, setLoadingPerms] = useState(false)
  const [savingPerms, setSavingPerms] = useState(false)

  // بذرة القوالب لتعبئة الصلاحيات الأولية عند الإضافة
  const { templates } = usePermissionCatalog()

  const roleLabels: Record<string, string> = {
    pharmacy_admin: t('rolePharmacyAdmin'),
    pharmacist: t('rolePharmacist'),
    cashier: t('roleCashier'),
    inventory_manager: t('roleInventoryManager'),
    hr_manager: t('roleHrManager'),
    accountant: t('roleAccountant'),
  }

  const load = useCallback(() => {
    setLoading(true)
    Promise.all([pharmacyApi.getEmployees(), pharmacyApi.getBranches()])
      .then(([employees, branchList]) => {
        setItems(employees.data)
        setBranches(branchList.data)
        setError(null)
      })
      .catch((err) => setError(err instanceof Error ? err.message : t('loadErrorFallback')))
      .finally(() => setLoading(false))
  }, [t])

  useEffect(() => {
    load()
  }, [load])

  function resetAddForm() {
    setForm({ first_name: '', last_name: '', email: '', password: '', phone: '', job_title: '', branch_id: '' })
    setNewPerms([])
    setFormError(null)
  }

  async function handleCreate() {
    setFormError(null)
    if (!form.first_name.trim() || !form.last_name.trim() || !form.email.trim()) {
      setFormError(t('errNameEmailRequired'))
      return
    }
    if (form.password.length < 8) {
      setFormError(t('errPasswordTooShort'))
      return
    }
    setSaving(true)
    try {
      await pharmacyApi.createEmployee({
        first_name: form.first_name.trim(),
        last_name: form.last_name.trim(),
        email: form.email.trim(),
        password: form.password,
        phone: form.phone.trim() || undefined,
        job_title: form.job_title.trim() || undefined,
        branch_id: form.branch_id || undefined,
        permissions: newPerms,
      })
      setShowAdd(false)
      resetAddForm()
      setNotice(t('employeeCreatedNotice'))
      load()
    } catch (err) {
      const message = err instanceof ApiError ? err.message : t('employeeCreateErrorFallback')
      setFormError(message)
    } finally {
      setSaving(false)
    }
  }

  async function openPermissions(employee: PharmacyEmployee) {
    setEditing(employee)
    setLoadingPerms(true)
    try {
      const response = await pharmacyApi.getEmployeePermissions(employee.id)
      const data: EmployeePermissions = response.data
      setEditingPerms(data.permissions)
      setEditingOriginal(data.permissions)
    } catch {
      setEditingPerms([])
      setEditingOriginal([])
    } finally {
      setLoadingPerms(false)
    }
  }

  async function savePermissions() {
    if (!editing) return
    setSavingPerms(true)
    try {
      await pharmacyApi.updateEmployeePermissions(editing.id, editingPerms)
      setEditing(null)
      setNotice(t('permsUpdatedNotice'))
      load()
    } catch (err) {
      const message = err instanceof ApiError ? err.message : t('permsSaveErrorFallback')
      setNotice(message)
    } finally {
      setSavingPerms(false)
    }
  }

  async function toggleStatus(employee: PharmacyEmployee) {
    const next = employee.status === 'active' ? 'inactive' : 'active'
    try {
      await pharmacyApi.setEmployeeStatus(employee.id, next)
      setNotice(next === 'inactive' ? t('deactivatedNotice') : t('activatedNotice'))
      load()
    } catch (err) {
      const message = err instanceof ApiError ? err.message : t('statusChangeErrorFallback')
      setNotice(message)
    }
  }

  const dirty = editingPerms.length !== editingOriginal.length ||
    editingPerms.some((k) => !editingOriginal.includes(k))

  return (
    <RequirePermission anyOf={['employees.view']}>
    <div className="mx-auto max-w-[1500px] space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">{t('title')}</h1>
          <p className="mt-2 text-sm text-muted-foreground">{t('subtitle')}</p>
        </div>
        {canCreate && (
          <Button onClick={() => { setShowAdd(true); resetAddForm() }} className="gap-2">
            <UserRoundPlus className="h-4 w-4" />
            {t('addNew')}
          </Button>
        )}
      </div>

      {notice && (
        <div className="rounded-lg border border-primary/30 bg-primary/5 px-4 py-2.5 text-sm text-primary">
          {notice}
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Users className="h-5 w-5 text-primary" />
            {t('listTitle')}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading && <p className="py-10 text-center text-muted-foreground">{t('loading')}</p>}
          {error && !loading && <p className="py-10 text-center text-destructive">{error}</p>}
          {!loading && !error && items.length === 0 && <p className="py-10 text-center text-muted-foreground">{t('empty')}</p>}
          {!loading && !error && items.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[820px] text-end text-sm">
                <thead className="border-b text-xs text-muted-foreground">
                  <tr>
                    <th className="p-3">{t('thName')}</th>
                    <th className="p-3">{t('thEmail')}</th>
                    <th className="p-3">{t('thJob')}</th>
                    <th className="p-3">{t('thBranch')}</th>
                    <th className="p-3">{t('permissions')}</th>
                    <th className="p-3">{t('thStatus')}</th>
                    {(canManage || can('employees.update')) && <th className="p-3">{t('thActions')}</th>}
                  </tr>
                </thead>
                <tbody>
                  {items.map((item) => (
                    <tr key={item.id} className="border-b last:border-0">
                      <td className="p-3 font-semibold">{item.display_name || `${item.first_name} ${item.last_name}`}</td>
                      <td className="p-3" dir="ltr">{item.email}</td>
                      <td className="p-3">{item.job_title || fieldLabel(item.role || 'pharmacist', roleLabels)}</td>
                      <td className="p-3">{item.branch_name || '—'}</td>
                      <td className="p-3">
                        {canManage ? (
                          <button
                            type="button"
                            onClick={() => openPermissions(item)}
                            className="inline-flex items-center gap-1.5 rounded-md border border-border px-2 py-1 text-xs transition-colors hover:border-primary hover:text-primary"
                          >
                            <Shield className="h-3.5 w-3.5" />
                            {t('viewEdit')}
                          </button>
                        ) : (
                          <span className="text-xs text-muted-foreground">—</span>
                        )}
                      </td>
                      <td className="p-3">
                        {item.status === 'active'
                          ? <Badge variant="success">{t('statusActive')}</Badge>
                          : <Badge variant="destructive">{t('statusInactive')}</Badge>}
                      </td>
                      {(canManage || can('employees.update')) && (
                        <td className="p-3">
                          <div className="flex items-center gap-1.5">
                            {canManage && (
                              <Button variant="ghost" size="sm" className="gap-1.5" onClick={() => openPermissions(item)}>
                                <ShieldCheck className="h-4 w-4" />
                                {t('permissions')}
                              </Button>
                            )}
                            {can('employees.update') && (
                              <Button
                                variant="ghost"
                                size="sm"
                                className="gap-1.5"
                                title={item.status === 'active' ? t('deactivateTitle') : t('activateTitle')}
                                onClick={() => toggleStatus(item)}
                              >
                                <Power className={item.status === 'active' ? 'h-4 w-4 text-destructive' : 'h-4 w-4 text-emerald-600'} />
                                {item.status === 'active' ? t('deactivate') : t('activate')}
                              </Button>
                            )}
                          </div>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* نافذة إضافة موظف */}
      {showAdd && (
        <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 py-10">
          <div className="w-full max-w-3xl rounded-xl bg-background p-6 shadow-xl">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="flex items-center gap-2 text-lg font-bold">
                <UserRoundPlus className="h-5 w-5 text-primary" />
                {t('addNew')}
              </h2>
              <Button variant="ghost" size="sm" onClick={() => setShowAdd(false)}>{t('cancel')}</Button>
            </div>

            <div className="mb-5 grid gap-3 sm:grid-cols-2">
              <div>
                <label className="mb-1 block text-sm font-medium">{t('firstNameLabel')}</label>
                <Input value={form.first_name} onChange={(e) => setForm({ ...form, first_name: e.target.value })} placeholder={t('firstNamePlaceholder')} />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium">{t('lastNameLabel')}</label>
                <Input value={form.last_name} onChange={(e) => setForm({ ...form, last_name: e.target.value })} placeholder={t('lastNamePlaceholder')} />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium">{t('emailLabel')} <span className="text-xs text-muted-foreground">{t('emailHint')}</span></label>
                <Input dir="ltr" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="staff@pharmacy.com" />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium">{t('passwordLabel')} <span className="text-xs text-muted-foreground">{t('passwordHint')}</span></label>
                <Input dir="ltr" type="text" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} placeholder="••••••••" />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium">{t('phoneLabel')}</label>
                <Input dir="ltr" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} placeholder="01xxxxxxxxx" />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium">{t('jobTitleLabel')}</label>
                <Input value={form.job_title} onChange={(e) => setForm({ ...form, job_title: e.target.value })} placeholder={t('jobTitlePlaceholder')} />
              </div>
              <div className="sm:col-span-2">
                <label className="mb-1 block text-sm font-medium">{t('branchLabel')}</label>
                <select
                  className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                  value={form.branch_id}
                  onChange={(e) => setForm({ ...form, branch_id: e.target.value })}
                >
                  <option value="">{t('noBranchOption')}</option>
                  {branches.map((b) => (
                    <option key={b.id} value={b.id}>{b.name}</option>
                  ))}
                </select>
              </div>
            </div>

            <div className="mb-4 rounded-lg border border-border p-4">
              <PermissionsEditor selected={newPerms} onChange={setNewPerms} />
            </div>

            {formError && <p className="mb-3 text-sm text-destructive">{formError}</p>}

            <div className="flex items-center justify-end gap-2">
              <Button variant="outline" onClick={() => setShowAdd(false)}>{t('cancel')}</Button>
              <Button onClick={handleCreate} disabled={saving}>
                {saving ? t('saving') : t('saveEmployee')}
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* نافذة تعديل الصلاحيات */}
      {editing && (
        <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 py-10">
          <div className="w-full max-w-3xl rounded-xl bg-background p-6 shadow-xl">
            <div className="mb-4 flex items-center justify-between">
              <div>
                <h2 className="flex items-center gap-2 text-lg font-bold">
                  <Shield className="h-5 w-5 text-primary" />
                  {t('permsModalTitle', { name: editing.display_name || `${editing.first_name} ${editing.last_name}` })}
                </h2>
                <p className="mt-1 text-xs text-muted-foreground" dir="ltr">{editing.email}</p>
              </div>
              <Button variant="ghost" size="sm" onClick={() => setEditing(null)}>{t('close')}</Button>
            </div>

            {editingOriginal.length === 0 && !loadingPerms && (
              <div className="mb-4 rounded-lg border border-amber-500/40 bg-amber-500/10 px-4 py-2.5 text-sm text-amber-700 dark:text-amber-400">
                {t('legacyPermsNote')}
              </div>
            )}

            {loadingPerms ? (
              <p className="py-10 text-center text-muted-foreground">{t('loadingPerms')}</p>
            ) : (
              <div className="max-h-[60vh] overflow-y-auto rounded-lg border border-border p-4">
                <PermissionsEditor selected={editingPerms} onChange={setEditingPerms} />
              </div>
            )}

            <div className="mt-4 flex items-center justify-end gap-2">
              <Button variant="outline" onClick={() => setEditing(null)}>{t('cancel')}</Button>
              <Button onClick={savePermissions} disabled={savingPerms || !dirty}>
                {savingPerms ? t('saving') : t('savePerms')}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
    </RequirePermission>
  )
}
