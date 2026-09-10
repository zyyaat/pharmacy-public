'use client'

// محرر الصلاحيات المرن (Task 42): بطاقات قوالب جاهزة + مفاتيح تشغيل/إيقاف
// مجمّعة حسب الأقسام، مع مفتاح رئيسي لكل قسم يجمع صلاحياته دفعة واحدة.

import { useEffect, useMemo, useState } from 'react'
import { ChevronDown, Shield, ShieldCheck } from 'lucide-react'
import { pharmacyApi, type PermissionModule, type PermissionTemplate } from '@/lib/api'
import { useT } from '@/i18n/provider'
import { cn } from '@/lib/utils'

interface PermissionsEditorProps {
  /** المفاتيح المختارة حاليًا (مصدر الحقيقة خارج المكوّن). */
  selected: string[]
  onChange: (keys: string[]) => void
}

/** أقسام بترتيب ثابت منطقي للصيدلية. */
const MODULE_ORDER = [
  'dashboard', 'pos', 'sales', 'inventory', 'customers',
  'employees', 'attendance', 'branches', 'reports', 'settings', 'pharmacy',
]

/** صلاحيات حساسة تُبرز بلون تحذيري داخل قسمها. */
const SENSITIVE_KEYS = new Set([
  'employees.delete', 'employees.manage_permissions', 'inventory.import',
  'inventory.writeoff', 'customers.delete', 'settings.general', 'pharmacy.admin',
])

export function usePermissionCatalog() {
  const [modules, setModules] = useState<PermissionModule[]>([])
  const [templates, setTemplates] = useState<PermissionTemplate[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    Promise.all([pharmacyApi.getPermissionCatalog(), pharmacyApi.getPermissionTemplates()])
      .then(([catalog, tpl]) => {
        if (cancelled) return
        const ordered = [...catalog.data].sort(
          (a, b) => MODULE_ORDER.indexOf(a.module) - MODULE_ORDER.indexOf(b.module),
        )
        setModules(ordered)
        setTemplates(tpl.data)
      })
      .catch(() => {
        if (!cancelled) {
          setModules([])
          setTemplates([])
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [])

  return { modules, templates, loading }
}

function Toggle({
  checked,
  onChange,
  disabled,
  label,
}: {
  checked: boolean
  onChange: (next: boolean) => void
  disabled?: boolean
  label: string
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cn(
        'relative inline-block h-6 w-11 shrink-0 rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50',
        checked ? 'bg-primary' : 'bg-muted-foreground/30',
      )}
    >
      {/* تموضع فيزيائي ثابت (RTL-safe): مطفأ = يمين المسار، شغّال = يساره */}
      <span
        className="absolute rounded-full bg-white shadow transition-transform"
        style={{
          height: 16,
          width: 16,
          top: 4,
          insetInlineStart: 4,
          transform: checked ? 'translateX(-20px)' : 'translateX(0)',
        }}
      />
    </button>
  )
}

export function PermissionsEditor({ selected, onChange }: PermissionsEditorProps) {
  const t = useT('employees')
  const { modules, templates, loading } = usePermissionCatalog()
  const [appliedTemplateId, setAppliedTemplateId] = useState<string | null>(null)
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({})

  const selectedSet = useMemo(() => new Set(selected), [selected])

  function applyTemplate(tpl: PermissionTemplate) {
    setAppliedTemplateId(tpl.id)
    onChange([...tpl.permissions])
  }

  function toggleKey(key: string, next: boolean) {
    setAppliedTemplateId(null)
    if (next) {
      onChange([...selected, key])
    } else {
      onChange(selected.filter((k) => k !== key))
    }
  }

  function toggleModule(mod: PermissionModule, next: boolean) {
    setAppliedTemplateId(null)
    const keys = mod.permissions.map((p) => p.key)
    if (next) {
      const merged = new Set([...selected, ...keys])
      onChange([...merged])
    } else {
      onChange(selected.filter((k) => !keys.includes(k)))
    }
  }

  if (loading) {
    return <p className="py-6 text-center text-sm text-muted-foreground">{t('loadingPerms')}</p>
  }

  return (
    <div className="space-y-5">
      {/* القوالب الجاهزة */}
      <div>
        <p className="mb-2 flex items-center gap-2 text-sm font-semibold">
          <ShieldCheck className="h-4 w-4 text-primary" />
          {t('templatesTitle')}
          <span className="text-xs font-normal text-muted-foreground">{t('templatesHint')}</span>
        </p>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {templates.map((tpl) => {
            const active = appliedTemplateId === tpl.id
            const matchCount = tpl.permissions.filter((k) => selectedSet.has(k)).length
            const exact = matchCount === tpl.permissions.length && matchCount === selected.length
            return (
              <button
                key={tpl.id}
                type="button"
                onClick={() => applyTemplate(tpl)}
                className={cn(
                  'rounded-lg border p-2.5 text-end transition-all',
                  active || (exact && tpl.permissions.length > 0)
                    ? 'border-primary bg-primary/5 ring-1 ring-primary'
                    : 'border-border hover:border-primary/40 hover:bg-accent/50',
                )}
              >
                <p className="text-sm font-semibold">{tpl.display_name_ar || tpl.display_name}</p>
                <p className="mt-0.5 line-clamp-1 text-xs text-muted-foreground">{tpl.description_ar}</p>
                <p className="mt-1 text-[11px] text-primary">{t('permsCount', { count: tpl.permissions.length })}</p>
              </button>
            )
          })}
        </div>
      </div>

      {/* الأقسام والمفاتيح */}
      <div className="space-y-2">
        <p className="flex items-center gap-2 text-sm font-semibold">
          <Shield className="h-4 w-4 text-primary" />
          {t('detailsTitle', { count: selected.length })}
        </p>
        {modules.length === 0 && (
          <p className="py-4 text-center text-sm text-muted-foreground">{t('noPermissionsDefined')}</p>
        )}
        {modules.map((mod) => {
          const keys = mod.permissions.map((p) => p.key)
          const enabledCount = keys.filter((k) => selectedSet.has(k)).length
          const allOn = enabledCount === keys.length && keys.length > 0
          const isCollapsed = collapsed[mod.module]
          return (
            <div key={mod.module} className="rounded-lg border border-border bg-card">
              <div className="flex items-center gap-2 p-3">
                <button
                  type="button"
                  className="flex flex-1 items-center gap-2 text-end"
                  onClick={() => setCollapsed((prev) => ({ ...prev, [mod.module]: !prev[mod.module] }))}
                >
                  <ChevronDown className={cn('h-4 w-4 text-muted-foreground transition-transform', isCollapsed && '-rotate-90')} />
                  <span className="text-sm font-semibold">{mod.label}</span>
                  <span className={cn('rounded-full px-2 py-0.5 text-xs', allOn ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground')}>
                    {enabledCount}/{keys.length}
                  </span>
                </button>
                <Toggle
                  checked={allOn}
                  onChange={(next) => toggleModule(mod, next)}
                  label={t('toggleModuleAria', { module: mod.label })}
                />
              </div>
              {!isCollapsed && (
                <div className="grid gap-1 border-t border-border p-3 sm:grid-cols-2">
                  {mod.permissions.map((p) => {
                    const sensitive = SENSITIVE_KEYS.has(p.key)
                    return (
                      <div
                        key={p.key}
                        className={cn(
                          'flex items-center justify-between gap-2 rounded-md px-2 py-1.5',
                          selectedSet.has(p.key) ? 'bg-primary/5' : '',
                        )}
                      >
                        <span className={cn('text-sm', sensitive && 'font-medium')}>
                          {p.name_ar || p.key}
                          {sensitive && <span className="ms-1 text-xs text-amber-600">●</span>}
                        </span>
                        <Toggle
                          checked={selectedSet.has(p.key)}
                          onChange={(next) => toggleKey(p.key, next)}
                          label={p.name_ar || p.key}
                        />
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
