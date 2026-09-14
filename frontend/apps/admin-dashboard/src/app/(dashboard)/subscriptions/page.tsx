"use client";

// Task 90 — subscription operations, aligned with global billing best
// practices: an operator overview (active/trials/expiring/MRR KPIs),
// lifecycle actions (extend — trial-aware, cancel-at-period-end, suspend,
// reactivate), and idempotent manual payments. Assigning uses a company
// SEARCH picker instead of pasting raw UUIDs.

import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  CalendarClock, Ban, PauseCircle, PlayCircle, Wallet, UserPlus,
  Hourglass, Search, CheckCircle2, Users, TrendingUp, AlertTriangle,
} from "lucide-react";
import { toast } from "sonner";
import {
  Card, CardContent, Button, Input, Badge,
} from "@/components/ui";
import { Table, TableHeader, TableBody, TableRow, TableHead } from "@/components/ui/table";
import { Modal } from "@/components/ui/modal";
import {
  plansApi, subscriptionsApi, companiesApi, ApiError,
  type PlanRow, type SubscriptionRow, type BillingOverview,
} from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtDate, fmtNumber } from "@/i18n/format";

const statusVariant: Record<SubscriptionRow["status"], "success" | "warning" | "destructive" | "secondary" | "default"> = {
  trial: "warning",
  active: "success",
  expired: "destructive",
  cancelled: "secondary",
  suspended: "destructive",
  pending: "default",
};

export default function SubscriptionsPage() {
  const t = useT("subscriptions");
  const [rows, setRows] = useState<SubscriptionRow[]>([]);
  const [plans, setPlans] = useState<PlanRow[]>([]);
  const [overview, setOverview] = useState<BillingOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("all");
  const [showHistory, setShowHistory] = useState(false);
  const [search, setSearch] = useState("");

  const [assignOpen, setAssignOpen] = useState(false);
  const [assign, setAssign] = useState({ company_id: "", company_name: "", plan_id: "", interval: "monthly", trial_days: "0", period_end: "" });
  const [companyQuery, setCompanyQuery] = useState("");
  const [companyResults, setCompanyResults] = useState<Array<{ id: string; name: string; email: string }>>([]);
  const companySearchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const [extendRow, setExtendRow] = useState<SubscriptionRow | null>(null);
  const [extendDate, setExtendDate] = useState("");
  const [payRow, setPayRow] = useState<SubscriptionRow | null>(null);
  const [pay, setPay] = useState({ plan_id: "", interval: "monthly", amount: "", note: "" });
  const [payIdempotencyKey, setPayIdempotencyKey] = useState("");
  const [busy, setBusy] = useState(false);

  // إعادة التفعيل بفترة يختارها المسؤول — حتى بعد الانتهاء أو الإلغاء
  const [reactRow, setReactRow] = useState<SubscriptionRow | null>(null);
  const [reactMode, setReactMode] = useState<"days" | "date">("days");
  const [reactDays, setReactDays] = useState(30);
  const [reactDate, setReactDate] = useState("");

  const reactEndIso = (): string => {
    if (reactMode === "date" && reactDate) {
      const d = new Date(`${reactDate}T23:59:59`);
      if (!Number.isNaN(d.getTime())) return d.toISOString();
    }
    return new Date(Date.now() + reactDays * 86400000).toISOString();
  };

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const [subs, planList, ov] = await Promise.all([
        subscriptionsApi.list({
          status: statusFilter === "all" ? undefined : statusFilter,
          search: search || undefined,
          history: showHistory || undefined,
        }),
        plansApi.list(),
        subscriptionsApi.overview().catch(() => null),
      ]);
      setRows(subs.data);
      setPlans(planList);
      setOverview(ov);
    } catch {
      toast.error(t("load_failed"));
    } finally {
      setLoading(false);
    }
  }, [statusFilter, search, showHistory, t]);

  useEffect(() => { void reload(); }, [reload]);

  // Company search for the assign picker — debounced, server-side.
  useEffect(() => {
    if (!assignOpen) return;
    if (companySearchTimer.current) clearTimeout(companySearchTimer.current);
    if (!companyQuery.trim()) { setCompanyResults([]); return; }
    companySearchTimer.current = setTimeout(async () => {
      try {
        const res = await companiesApi.list({ search: companyQuery.trim(), limit: 8 });
        setCompanyResults(res.data.map((c) => ({ id: c.id, name: c.name, email: c.email })));
      } catch { setCompanyResults([]); }
    }, 250);
  }, [companyQuery, assignOpen]);

  const runAction = async (row: SubscriptionRow, action: "cancel" | "suspend") => {
    if (action === "cancel" && !window.confirm(t("confirm_cancel"))) return;
    if (action === "suspend" && !window.confirm(t("confirm_suspend"))) return;
    setBusy(true);
    try {
      await subscriptionsApi.action(row.id, { action });
      toast.success(t("saved"));
      await reload();
    } catch (e) {
      // رسالة الخادم الحقيقية أولًا (invalid_state/period_end_required…) —
      // «فشل» العمياء تركت المسؤول بلا سبب (درس بلاغ إعادة التفعيل)
      toast.error(e instanceof ApiError && e.message ? e.message : t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const toggleCancelAtPeriodEnd = async (row: SubscriptionRow) => {
    setBusy(true);
    try {
      await subscriptionsApi.action(row.id, {
        action: "set_cancel_at_period_end",
        cancel_at_period_end: !row.cancel_at_period_end,
      });
      toast.success(t("saved"));
      await reload();
    } catch (e) {
      // رسالة الخادم الحقيقية أولًا (invalid_state/period_end_required…) —
      // «فشل» العمياء تركت المسؤول بلا سبب (درس بلاغ إعادة التفعيل)
      toast.error(e instanceof ApiError && e.message ? e.message : t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const doAssign = async () => {
    if (!assign.company_id.trim() || !assign.plan_id) {
      toast.error(t("failed"));
      return;
    }
    setBusy(true);
    try {
      await subscriptionsApi.assign({
        company_id: assign.company_id.trim(),
        plan_id: assign.plan_id,
        billing_interval: assign.interval as "none" | "monthly" | "yearly",
        trial_days: Number(assign.trial_days || "0"),
        current_period_end: assign.period_end || undefined,
      });
      toast.success(t("saved"));
      setAssignOpen(false);
      await reload();
    } catch (e) {
      // رسالة الخادم الحقيقية أولًا (invalid_state/period_end_required…) —
      // «فشل» العمياء تركت المسؤول بلا سبب (درس بلاغ إعادة التفعيل)
      toast.error(e instanceof ApiError && e.message ? e.message : t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const doReactivate = async () => {
    if (!reactRow) return;
    setBusy(true);
    try {
      await subscriptionsApi.action(reactRow.id, {
        action: "reactivate",
        current_period_end: reactEndIso(),
      });
      toast.success(t("saved"));
      setReactRow(null);
      await reload();
    } catch (e) {
      // رسالة الخادم الحقيقية أولًا (invalid_state/period_end_required…) —
      // «فشل» العمياء تركت المسؤول بلا سبب (درس بلاغ إعادة التفعيل)
      toast.error(e instanceof ApiError && e.message ? e.message : t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const doExtend = async () => {
    if (!extendRow || !extendDate) return;
    setBusy(true);
    try {
      await subscriptionsApi.action(extendRow.id, {
        action: "extend",
        current_period_end: new Date(extendDate).toISOString(),
      });
      toast.success(t("saved"));
      setExtendRow(null);
      await reload();
    } catch (e) {
      // رسالة الخادم الحقيقية أولًا (invalid_state/period_end_required…) —
      // «فشل» العمياء تركت المسؤول بلا سبب (درس بلاغ إعادة التفعيل)
      toast.error(e instanceof ApiError && e.message ? e.message : t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const doManualPayment = async () => {
    if (!payRow || !pay.plan_id) return;
    setBusy(true);
    try {
      const res = await subscriptionsApi.manualPayment({
        company_id: payRow.company.id,
        plan_id: pay.plan_id,
        billing_interval: pay.interval as "monthly" | "yearly",
        amount_piastres: pay.amount ? Math.round(Number(pay.amount) * 100) : undefined,
        note: pay.note || undefined,
        idempotency_key: payIdempotencyKey || undefined,
      });
      toast.success(res?.duplicate ? t("duplicate_payment") : t("saved"));
      setPayRow(null);
      await reload();
    } catch (e) {
      // رسالة الخادم الحقيقية أولًا (invalid_state/period_end_required…) —
      // «فشل» العمياء تركت المسؤول بلا سبب (درس بلاغ إعادة التفعيل)
      toast.error(e instanceof ApiError && e.message ? e.message : t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const periodLabel = (row: SubscriptionRow) => {
    if (row.status === "trial" && row.trial_ends_at) return fmtDate(row.trial_ends_at, { dateStyle: "medium" });
    if (row.current_period_end) return fmtDate(row.current_period_end, { dateStyle: "medium" });
    return t("no_period");
  };

  const egp = (piastres: number) => `${fmtNumber(piastres / 100)} EGP`;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">{t("title")}</h1>
          <p className="text-muted-foreground mt-1">{t("subtitle")}</p>
        </div>
        <Button onClick={() => { setAssign({ company_id: "", company_name: "", plan_id: "", interval: "monthly", trial_days: "0", period_end: "" }); setCompanyQuery(""); setCompanyResults([]); setAssignOpen(true); }}>
          <UserPlus className="h-4 w-4 ms-2" />
          {t("assign")}
        </Button>
      </div>

      {/* Operator KPIs — active/trials/cancelling/MRR + expiring watch list */}
      {overview && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
          <Card><CardContent className="p-4 flex items-center gap-3">
            <CheckCircle2 className="h-8 w-8 text-emerald-600" />
            <div><div className="text-2xl font-bold">{overview.active_count}</div><div className="text-xs text-muted-foreground">{t("kpi_active")}</div></div>
          </CardContent></Card>
          <Card><CardContent className="p-4 flex items-center gap-3">
            <Hourglass className="h-8 w-8 text-amber-600" />
            <div><div className="text-2xl font-bold">{overview.trial_count}</div><div className="text-xs text-muted-foreground">{t("kpi_trials")}</div></div>
          </CardContent></Card>
          <Card><CardContent className="p-4 flex items-center gap-3">
            <AlertTriangle className="h-8 w-8 text-amber-600" />
            <div><div className="text-2xl font-bold">{overview.expiring_within_7_days.length}</div><div className="text-xs text-muted-foreground">{t("kpi_expiring_7d")}</div></div>
          </CardContent></Card>
          <Card><CardContent className="p-4 flex items-center gap-3">
            <TrendingUp className="h-8 w-8 text-emerald-600" />
            <div><div className="text-2xl font-bold">{egp(overview.mrr_piastres)}</div><div className="text-xs text-muted-foreground">{t("kpi_mrr")}</div></div>
          </CardContent></Card>
        </div>
      )}
      {overview && overview.expiring_within_7_days.length > 0 && (
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-2 text-sm font-semibold mb-2">
              <Users className="h-4 w-4 text-amber-600" />
              {t("expiring_soon")}
            </div>
            <div className="space-y-1.5">
              {overview.expiring_within_7_days.map((e) => (
                <div key={e.id} className="flex flex-wrap items-center justify-between gap-2 text-sm rounded-md border border-border px-3 py-1.5">
                  <span className="font-medium">{e.company_name}</span>
                  <span className="text-muted-foreground">{e.plan_name_ar || e.plan_name}</span>
                  <span className="text-xs text-muted-foreground">
                    {e.ends_at ? fmtDate(e.ends_at, { dateStyle: "medium" }) : ""}
                  </span>
                  {e.cancel_at_period_end && <Badge variant="secondary">{t("cap_pending")}</Badge>}
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      <div className="flex flex-col sm:flex-row gap-3">
        <Input className="sm:max-w-xs" placeholder={t("search_placeholder")} value={search} onChange={(e) => setSearch(e.target.value)} />
        <select
          className="sm:max-w-[200px] rounded-md border border-border bg-background px-3 py-2 text-sm"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
        >
          <option value="all">{t("filter_status_all")}</option>
          {(["trial", "active", "expired", "cancelled", "suspended", "pending"] as const).map((s) => (
            <option key={s} value={s}>{t(`status_${s}`)}</option>
          ))}
        </select>
        <Button
          variant={showHistory ? "default" : "outline"}
          size="sm"
          className="sm:self-stretch"
          onClick={() => setShowHistory((v) => !v)}
        >
          {showHistory ? t("view_current_only") : t("view_full_history")}
        </Button>
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {loading ? (
            <div className="py-10 text-center text-muted-foreground">…</div>
          ) : rows.length === 0 ? (
            <div className="py-10 text-center text-muted-foreground">{t("no_subscriptions")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("col_company")}</TableHead>
                  <TableHead>{t("col_plan")}</TableHead>
                  <TableHead>{t("col_status")}</TableHead>
                  <TableHead>{t("col_period_end")}</TableHead>
                  <TableHead>{t("col_source")}</TableHead>
                  <TableHead className="text-end">{t("col_actions")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((row) => (
                  <TableRow key={row.id}>
                    <td className="px-4 py-3 text-sm">
                      <div className="font-medium">{row.company.name}</div>
                      <div className="text-xs text-muted-foreground" dir="ltr">{row.company.email}</div>
                      {(row.versions ?? 1) > 1 && (
                        <div className="mt-0.5">
                          <Badge variant="outline">{t("history_badge").replace("{n}", String(row.versions))}</Badge>
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-sm">{row.plan.name_ar || row.plan.name}</td>
                    <td className="px-4 py-3 text-sm">
                      <Badge variant={statusVariant[row.status]}>{t(`status_${row.status}`)}</Badge>
                    </td>
                    <td className="px-4 py-3 text-sm">
                      {periodLabel(row)}
                      {row.cancel_at_period_end && (
                        <div className="mt-0.5"><Badge variant="secondary">{t("cap_pending")}</Badge></div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-sm text-muted-foreground">{t(`source_${row.source}`)}</td>
                    <td className="px-4 py-3 text-sm">
                      <div className="flex items-center justify-end gap-1">
                        {(row.status === "active" || row.status === "trial") && (
                          <Button variant="ghost" size="icon" title={row.status === "trial" ? t("extend_trial_title") : t("extend")}
                            onClick={() => { setExtendRow(row); setExtendDate(""); }}>
                            <CalendarClock className="h-4 w-4" />
                          </Button>
                        )}
                        {(row.status === "active" || row.status === "trial") && (
                          <Button variant="ghost" size="icon" title={row.cancel_at_period_end ? t("cap_unset") : t("cap_set")}
                            onClick={() => void toggleCancelAtPeriodEnd(row)}>
                            <Hourglass className="h-4 w-4" />
                          </Button>
                        )}
                        <Button variant="ghost" size="icon" title={t("manual_payment")}
                          onClick={() => {
                            setPayRow(row);
                            setPay({ plan_id: row.plan.id, interval: "monthly", amount: "", note: "" });
                            setPayIdempotencyKey(crypto.randomUUID());
                          }}>
                          <Wallet className="h-4 w-4" />
                        </Button>
                        {(row.status === "active" || row.status === "trial") && (
                          <Button variant="ghost" size="icon" title={t("suspend")}
                            onClick={() => void runAction(row, "suspend")}>
                            <PauseCircle className="h-4 w-4" />
                          </Button>
                        )}
                        {(row.status === "expired" || row.status === "cancelled" || row.status === "suspended") && (
                          <Button variant="ghost" size="icon" title={t("reactivate")}
                            onClick={() => {
                              setReactRow(row);
                              setReactMode("days");
                              setReactDays(30);
                              setReactDate("");
                            }}>
                            <PlayCircle className="h-4 w-4" />
                          </Button>
                        )}
                        {row.status !== "cancelled" && (
                          <Button variant="ghost" size="icon" className="text-destructive" title={t("cancel_sub")}
                            onClick={() => void runAction(row, "cancel")}>
                            <Ban className="h-4 w-4" />
                          </Button>
                        )}
                      </div>
                    </td>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Assign plan — company SEARCH picker, never raw UUID paste */}
      <Modal isOpen={assignOpen} onClose={() => setAssignOpen(false)}>
        <div className="w-[440px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{t("assign_title")}</h2>
          <div className="space-y-1">
            <span className="text-sm text-muted-foreground">{t("assign_company")}</span>
            {assign.company_id ? (
              <div className="flex items-center justify-between rounded-md border border-emerald-500/50 bg-emerald-500/10 px-3 py-2 text-sm">
                <div>
                  <div className="font-medium">{assign.company_name}</div>
                  <div className="text-xs text-muted-foreground" dir="ltr">{assign.company_id}</div>
                </div>
                <Button variant="ghost" size="icon" onClick={() => setAssign({ ...assign, company_id: "", company_name: "" })}>
                  <Ban className="h-4 w-4" />
                </Button>
              </div>
            ) : (
              <div className="relative">
                <Search className="absolute top-2.5 start-3 h-4 w-4 text-muted-foreground" />
                <Input className="ps-9" placeholder={t("assign_company_search")} value={companyQuery} onChange={(e) => setCompanyQuery(e.target.value)} />
                {companyResults.length > 0 && (
                  <div className="absolute z-10 mt-1 w-full rounded-md border border-border bg-background shadow-lg max-h-56 overflow-y-auto">
                    {companyResults.map((c) => (
                      <button
                        key={c.id}
                        className="w-full text-start px-3 py-2 text-sm hover:bg-accent"
                        onClick={() => { setAssign({ ...assign, company_id: c.id, company_name: c.name }); setCompanyResults([]); setCompanyQuery(""); }}
                      >
                        <div className="font-medium">{c.name}</div>
                        <div className="text-xs text-muted-foreground" dir="ltr">{c.email}</div>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("assign_plan")}</span>
            <select className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm" value={assign.plan_id}
              onChange={(e) => setAssign({ ...assign, plan_id: e.target.value })}>
              <option value="">—</option>
              {plans.filter((p) => p.is_active).map((p) => (
                <option key={p.id} value={p.id}>{p.name_ar || p.name}</option>
              ))}
            </select>
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block text-sm space-y-1">
              <span className="text-muted-foreground">{t("assign_interval")}</span>
              <select className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm" value={assign.interval}
                onChange={(e) => setAssign({ ...assign, interval: e.target.value })}>
                <option value="none">{t("interval_none")}</option>
                <option value="monthly">{t("interval_monthly")}</option>
                <option value="yearly">{t("interval_yearly")}</option>
              </select>
            </label>
            <label className="block text-sm space-y-1">
              <span className="text-muted-foreground">{t("assign_trial_days")}</span>
              <Input type="number" min="0" value={assign.trial_days} onChange={(e) => setAssign({ ...assign, trial_days: e.target.value })} />
            </label>
          </div>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("assign_period_end")}</span>
            <Input type="date" value={assign.period_end} onChange={(e) => setAssign({ ...assign, period_end: e.target.value })} />
          </label>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setAssignOpen(false)}>{t("cancel_sub")}</Button>
            <Button disabled={busy} onClick={() => void doAssign()}>{busy ? "…" : t("saved")}</Button>
          </div>
        </div>
      </Modal>

      {/* Extend — trial-aware title/label */}
      <Modal isOpen={!!extendRow} onClose={() => setExtendRow(null)}>
        <div className="w-[380px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{extendRow?.status === "trial" ? t("extend_trial_title") : t("extend_title")}</h2>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{extendRow?.status === "trial" ? t("new_trial_end") : t("new_period_end")}</span>
            <Input type="date" value={extendDate} onChange={(e) => setExtendDate(e.target.value)} />
          </label>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setExtendRow(null)}>{t("cancel_sub")}</Button>
            <Button disabled={busy || !extendDate} onClick={() => void doExtend()}>{busy ? "…" : t("saved")}</Button>
          </div>
        </div>
      </Modal>

      {/* Reactivate — فترة يختارها المسؤول (أيام سريعة أو تاريخ مخصص) */}
      <Modal isOpen={!!reactRow} onClose={() => setReactRow(null)}>
        <div className="w-[420px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{t("reactivate_title")}</h2>
          <p className="text-sm text-muted-foreground">{t("reactivate_hint")}</p>
          <div className="grid grid-cols-4 gap-2">
            {[7, 14, 30, 90].map((d) => (
              <Button
                key={d}
                size="sm"
                variant={reactMode === "days" && reactDays === d ? "default" : "outline"}
                onClick={() => { setReactMode("days"); setReactDays(d); }}
              >
                {t(`reactivate_p${d}`)}
              </Button>
            ))}
          </div>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("reactivate_custom")}</span>
            <Input
              type="date"
              value={reactDate}
              onChange={(e) => {
                setReactDate(e.target.value);
                if (e.target.value) setReactMode("date");
              }}
            />
          </label>
          <div className="rounded-md border border-emerald-500/40 bg-emerald-500/10 px-3 py-2 text-sm">
            {t("reactivate_until")}{" "}
            <span className="font-semibold">{fmtDate(reactEndIso(), { dateStyle: "medium" })}</span>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setReactRow(null)}>{t("cancel_sub")}</Button>
            <Button disabled={busy} onClick={() => void doReactivate()}>{busy ? "…" : t("reactivate_confirm")}</Button>
          </div>
        </div>
      </Modal>

      {/* Manual payment */}
      <Modal isOpen={!!payRow} onClose={() => setPayRow(null)}>
        <div className="w-[440px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{t("manual_payment_title")}</h2>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("assign_plan")}</span>
            <select className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm" value={pay.plan_id}
              onChange={(e) => setPay({ ...pay, plan_id: e.target.value })}>
              {plans.filter((p) => p.is_active).map((p) => (
                <option key={p.id} value={p.id}>{p.name_ar || p.name}</option>
              ))}
            </select>
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block text-sm space-y-1">
              <span className="text-muted-foreground">{t("assign_interval")}</span>
              <select className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm" value={pay.interval}
                onChange={(e) => setPay({ ...pay, interval: e.target.value })}>
                <option value="monthly">{t("interval_monthly")}</option>
                <option value="yearly">{t("interval_yearly")}</option>
              </select>
            </label>
            <label className="block text-sm space-y-1">
              <span className="text-muted-foreground">{t("amount_egp")}</span>
              <Input type="number" min="0" value={pay.amount} onChange={(e) => setPay({ ...pay, amount: e.target.value })} />
            </label>
          </div>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("note")}</span>
            <Input value={pay.note} onChange={(e) => setPay({ ...pay, note: e.target.value })} />
          </label>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setPayRow(null)}>{t("cancel_sub")}</Button>
            <Button disabled={busy} onClick={() => void doManualPayment()}>{busy ? "…" : t("saved")}</Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
