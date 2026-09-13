"use client";

// Task 90 — SaaS plans management: the super admin creates and edits plans
// (name, pricing, features, permissions, limits) with ZERO code changes.
// Toggling a feature auto-selects its suggested permissions; the permission
// sets remain fully editable. Deactivating a plan never touches existing
// subscribers — it only hides it from new subscriptions.

import React, { useCallback, useEffect, useMemo, useState } from "react";
import { Plus, Pencil, Trash2, Power } from "lucide-react";
import { toast } from "sonner";
import {
  Card, CardContent, Button, Input, Badge,
} from "@/components/ui";
import { Table, TableHeader, TableBody, TableRow, TableHead } from "@/components/ui/table";
import { Modal } from "@/components/ui/modal";
import { featuresApi, plansApi, type FeatureRow, type PlanRow, type PlanDetail } from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtNumber } from "@/i18n/format";

const LIMIT_SUGGESTIONS = ["branches", "users", "employees", "products"];

type EditorState = {
  id?: string;
  slug: string;
  name: string;
  name_ar: string;
  description: string;
  monthly: string;
  yearly: string;
  isActive: boolean;
  isPublic: boolean;
  sortOrder: string;
  features: string[];
  permissions: string[];
  limits: Array<{ key: string; value: string }>;
};

const emptyEditor = (): EditorState => ({
  slug: "", name: "", name_ar: "", description: "",
  monthly: "0", yearly: "0",
  isActive: true, isPublic: true, sortOrder: "0",
  features: [], permissions: [], limits: [],
});

export default function PlansPage() {
  const t = useT("plans");
  const [plans, setPlans] = useState<PlanRow[]>([]);
  const [features, setFeatures] = useState<FeatureRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [editorOpen, setEditorOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editor, setEditor] = useState<EditorState>(emptyEditor());

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const [planList, featureList] = await Promise.all([plansApi.list(), featuresApi.list()]);
      setPlans(planList);
      setFeatures(featureList);
    } catch {
      toast.error(t("load_failed"));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => { void reload(); }, [reload]);

  const featureByKey = useMemo(
    () => Object.fromEntries(features.map((f) => [f.key, f])),
    [features]
  );

  const egp = (piastres: number) => fmtNumber(piastres / 100) + " EGP";

  const openCreate = () => {
    setEditor(emptyEditor());
    setEditorOpen(true);
  };

  const openEdit = async (id: string) => {
    try {
      const detail: PlanDetail = await plansApi.get(id);
      setEditor({
        id: detail.id,
        slug: detail.slug,
        name: detail.name,
        name_ar: detail.name_ar || "",
        description: detail.description || "",
        monthly: String(detail.monthly_price_piastres / 100),
        yearly: String(detail.yearly_price_piastres / 100),
        isActive: detail.is_active,
        isPublic: detail.is_public,
        sortOrder: String(detail.sort_order),
        features: detail.features,
        permissions: detail.permissions,
        limits: Object.entries(detail.limits).map(([key, value]) => ({ key, value: String(value) })),
      });
      setEditorOpen(true);
    } catch {
      toast.error(t("load_failed"));
    }
  };

  const toggleFeature = (key: string) => {
    setEditor((prev) => {
      const on = prev.features.includes(key);
      const features = on ? prev.features.filter((f) => f !== key) : [...prev.features, key];
      let permissions = prev.permissions;
      const suggested = featureByKey[key]?.suggested_permissions ?? [];
      if (!on) {
        // auto-select suggested permissions of the newly enabled feature
        permissions = Array.from(new Set([...permissions, ...suggested]));
      }
      return { ...prev, features, permissions };
    });
  };

  // group permissions shown in the editor by their module prefix
  const permissionGroups = useMemo(() => {
    const groups = new Map<string, Set<string>>();
    for (const f of features) {
      for (const key of f.suggested_permissions) {
        const mod = key.split(".")[0];
        if (!groups.has(mod)) groups.set(mod, new Set());
        groups.get(mod)!.add(key);
      }
    }
    return Array.from(groups.entries())
      .map(([mod, keys]) => ({ module: mod, keys: Array.from(keys).sort() }))
      .sort((a, b) => a.module.localeCompare(b.module));
  }, [features]);

  const toggleModulePermissions = (modulePrefix: string, select: boolean) => {
    setEditor((prev) => {
      if (select) {
        const add = permissionGroups
          .filter((g) => g.module === modulePrefix)
          .flatMap((g) => g.keys)
          .filter((k) => !prev.permissions.includes(k));
        return { ...prev, permissions: [...prev.permissions, ...add] };
      }
      return { ...prev, permissions: prev.permissions.filter((k) => !k.startsWith(modulePrefix + ".")) };
    });
  };

  const save = async () => {
    // Stripe-model guard: a plan shown on the public pricing page must carry
    // a price — a zero-priced public plan renders as "0 EGP" and dead-ends
    // at checkout (the server refuses zero-amount intentions too).
    const monthlyPiastres = Math.round(Number(editor.monthly || "0") * 100);
    const yearlyPiastres = Math.round(Number(editor.yearly || "0") * 100);
    if (editor.isPublic && editor.isActive && monthlyPiastres <= 0 && yearlyPiastres <= 0) {
      toast.error(t("price_required"));
      return;
    }
    setSaving(true);
    try {
      const payload = {
        slug: editor.slug,
        name: editor.name,
        name_ar: editor.name_ar,
        description: editor.description,
        monthly_price_piastres: monthlyPiastres,
        yearly_price_piastres: yearlyPiastres,
        is_active: editor.isActive,
        is_public: editor.isPublic,
        sort_order: Number(editor.sortOrder || "0"),
        features: editor.features,
        permissions: editor.permissions,
        limits: Object.fromEntries(
          editor.limits
            .filter((l) => l.key.trim() !== "")
            .map((l) => [l.key.trim(), Number(l.value)])
        ),
      };
      if (editor.id) {
        await plansApi.update(editor.id, payload);
      } else {
        await plansApi.create(payload);
      }
      toast.success(t("saved"));
      setEditorOpen(false);
      await reload();
    } catch (err) {
      const message = err instanceof Error ? err.message : "";
      if (message.includes("slug")) toast.error(t("slug_taken"));
      else toast.error(t("failed"));
    } finally {
      setSaving(false);
    }
  };

  const toggleStatus = async (plan: PlanRow) => {
    try {
      await plansApi.setStatus(plan.id, !plan.is_active);
      await reload();
    } catch {
      toast.error(t("failed"));
    }
  };

  const remove = async (plan: PlanRow) => {
    if (!window.confirm(t("delete_confirm"))) return;
    try {
      await plansApi.remove(plan.id);
      await reload();
    } catch (err) {
      const message = err instanceof Error ? err.message : "";
      if (message.includes("subscribers")) toast.error(t("plan_has_subscribers"));
      else toast.error(t("failed"));
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">{t("title")}</h1>
          <p className="text-muted-foreground mt-1">{t("subtitle")}</p>
        </div>
        <Button onClick={openCreate}>
          <Plus className="h-4 w-4 ms-2" />
          {t("new_plan")}
        </Button>
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {loading ? (
            <div className="py-10 text-center text-muted-foreground">…</div>
          ) : plans.length === 0 ? (
            <div className="py-10 text-center text-muted-foreground">{t("no_plans")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("col_plan")}</TableHead>
                  <TableHead>{t("col_price_monthly")}</TableHead>
                  <TableHead>{t("col_price_yearly")}</TableHead>
                  <TableHead>{t("col_status")}</TableHead>
                  <TableHead>{t("col_subscribers")}</TableHead>
                  <TableHead className="text-end">{t("col_actions")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {plans.map((plan) => (
                  <TableRow key={plan.id}>
                    <td className="px-4 py-3 text-sm">
                      <div className="font-medium">{plan.name_ar || plan.name}</div>
                      <div className="text-xs text-muted-foreground" dir="ltr">{plan.slug}</div>
                    </td>
                    <td className="px-4 py-3 text-sm">
                      {plan.monthly_price_piastres > 0 ? egp(plan.monthly_price_piastres)
                        : <span className="text-muted-foreground">{t("unpriced")}</span>}
                    </td>
                    <td className="px-4 py-3 text-sm">
                      {plan.yearly_price_piastres > 0 ? egp(plan.yearly_price_piastres)
                        : <span className="text-muted-foreground">{t("unpriced")}</span>}
                    </td>
                    <td className="px-4 py-3 text-sm">
                      <Badge variant={plan.is_active ? "success" : "secondary"}>
                        {plan.is_active ? t("active") : t("inactive")}
                      </Badge>
                    </td>
                    <td className="px-4 py-3 text-sm">{plan.subscribers}</td>
                    <td className="px-4 py-3 text-sm">
                      <div className="flex items-center justify-end gap-1">
                        <Button variant="ghost" size="icon" title={t("edit_plan")} onClick={() => void openEdit(plan.id)}>
                          <Pencil className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" title={plan.is_active ? t("deactivate") : t("activate")} onClick={() => void toggleStatus(plan)}>
                          <Power className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" className="text-destructive" title={t("delete")} onClick={() => void remove(plan)}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </td>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Plan editor */}
      <Modal isOpen={editorOpen} onClose={() => setEditorOpen(false)}>
        <div className="max-h-[85vh] w-[720px] max-w-[92vw] overflow-y-auto space-y-4 text-start">
          <h2 className="text-lg font-bold">{editor.id ? t("edit_plan") : t("create_plan")}</h2>

          <div className="grid grid-cols-2 gap-3">
            <Field label={t("form_name")}>
              <Input value={editor.name} onChange={(e) => setEditor({ ...editor, name: e.target.value })} />
            </Field>
            <Field label={t("form_name_ar")}>
              <Input value={editor.name_ar} onChange={(e) => setEditor({ ...editor, name_ar: e.target.value })} />
            </Field>
            {!editor.id && (
              <Field label={t("form_slug")}>
                <Input dir="ltr" value={editor.slug} onChange={(e) => setEditor({ ...editor, slug: e.target.value })} />
              </Field>
            )}
            <Field label={t("form_sort")}>
              <Input type="number" value={editor.sortOrder} onChange={(e) => setEditor({ ...editor, sortOrder: e.target.value })} />
            </Field>
            <Field label={t("form_price_monthly")}>
              <Input type="number" min="0" value={editor.monthly} onChange={(e) => setEditor({ ...editor, monthly: e.target.value })} />
            </Field>
            <Field label={t("form_price_yearly")}>
              <Input type="number" min="0" value={editor.yearly} onChange={(e) => setEditor({ ...editor, yearly: e.target.value })} />
            </Field>
          </div>
          <p className="text-xs text-muted-foreground">{t("price_hint")}</p>
          <Field label={t("form_description")}>
            <Input value={editor.description} onChange={(e) => setEditor({ ...editor, description: e.target.value })} />
          </Field>
          <div className="flex items-center gap-6 text-sm">
            <label className="flex items-center gap-2">
              <input type="checkbox" checked={editor.isActive} onChange={(e) => setEditor({ ...editor, isActive: e.target.checked })} />
              {t("form_is_active")}
            </label>
            <label className="flex items-center gap-2">
              <input type="checkbox" checked={editor.isPublic} onChange={(e) => setEditor({ ...editor, isPublic: e.target.checked })} />
              {t("form_is_public")}
            </label>
          </div>

          {/* Features */}
          <div>
            <h3 className="font-semibold mb-2">{t("form_features")}</h3>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
              {features.map((f) => (
                <label key={f.key} className="flex items-center gap-2 rounded-lg border border-border px-3 py-2 text-sm cursor-pointer hover:bg-accent">
                  <input
                    type="checkbox"
                    checked={editor.features.includes(f.key)}
                    onChange={() => toggleFeature(f.key)}
                  />
                  <span>{f.name_ar || f.name}</span>
                </label>
              ))}
            </div>
            <p className="text-xs text-muted-foreground mt-2">{t("suggested_hint")}</p>
          </div>

          {/* Permissions grouped by module */}
          <div>
            <h3 className="font-semibold mb-2">{t("form_permissions")}</h3>
            <div className="space-y-3 max-h-64 overflow-y-auto rounded-lg border border-border p-3">
              {permissionGroups.map((group) => (
                <div key={group.module}>
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-xs font-semibold text-muted-foreground" dir="ltr">{group.module}</span>
                    <button type="button" className="text-xs text-primary hover:underline" onClick={() => toggleModulePermissions(group.module, true)}>
                      {t("select_all_module")}
                    </button>
                    <button type="button" className="text-xs text-muted-foreground hover:underline" onClick={() => toggleModulePermissions(group.module, false)}>
                      {t("clear_module")}
                    </button>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-1">
                    {group.keys.map((key) => (
                      <label key={key} className="flex items-center gap-2 text-sm cursor-pointer">
                        <input
                          type="checkbox"
                          checked={editor.permissions.includes(key)}
                          onChange={() => setEditor((prev) => ({
                            ...prev,
                            permissions: prev.permissions.includes(key)
                              ? prev.permissions.filter((k) => k !== key)
                              : [...prev.permissions, key],
                          }))}
                        />
                        <span dir="ltr" className="text-xs">{key}</span>
                      </label>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Limits */}
          <div>
            <h3 className="font-semibold mb-2">{t("form_limits")}</h3>
            <div className="space-y-2">
              {editor.limits.map((limit, index) => (
                <div key={index} className="flex items-center gap-2">
                  <select
                    className="rounded-md border border-border bg-background px-2 py-2 text-sm"
                    value={LIMIT_SUGGESTIONS.includes(limit.key) ? limit.key : "custom"}
                    onChange={(e) => {
                      const value = e.target.value;
                      setEditor((prev) => ({
                        ...prev,
                        limits: prev.limits.map((l, i) =>
                          i === index ? { ...l, key: value === "custom" ? l.key : value } : l
                        ),
                      }));
                    }}
                  >
                    {LIMIT_SUGGESTIONS.map((key) => (
                      <option key={key} value={key}>{t(`limit_${key}`)}</option>
                    ))}
                    <option value="custom">…</option>
                  </select>
                  {!LIMIT_SUGGESTIONS.includes(limit.key) && (
                    <Input dir="ltr" className="w-40" value={limit.key}
                      onChange={(e) => setEditor((prev) => ({
                        ...prev,
                        limits: prev.limits.map((l, i) => (i === index ? { ...l, key: e.target.value } : l)),
                      }))} />
                  )}
                  <Input type="number" className="w-28" value={limit.value}
                    onChange={(e) => setEditor((prev) => ({
                      ...prev,
                      limits: prev.limits.map((l, i) => (i === index ? { ...l, value: e.target.value } : l)),
                    }))} />
                  <Button variant="ghost" size="icon" className="text-destructive"
                    onClick={() => setEditor((prev) => ({ ...prev, limits: prev.limits.filter((_, i) => i !== index) }))}>
                    ×
                  </Button>
                </div>
              ))}
              <Button variant="outline" size="sm"
                onClick={() => setEditor((prev) => ({ ...prev, limits: [...prev.limits, { key: "branches", value: "1" }] }))}>
                <Plus className="h-4 w-4 ms-2" /> {t("add_limit")}
              </Button>
            </div>
          </div>

          <div className="flex justify-end gap-2 pt-2 border-t border-border">
            <Button variant="outline" onClick={() => setEditorOpen(false)}>{t("cancel")}</Button>
            <Button disabled={saving} onClick={() => void save()}>{saving ? "…" : t("save")}</Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block text-sm space-y-1">
      <span className="text-muted-foreground">{label}</span>
      {children}
    </label>
  );
}
