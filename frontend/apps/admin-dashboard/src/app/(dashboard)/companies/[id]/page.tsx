"use client";

// Task 15 — the full per-account management page. Everything about ONE
// company lives here in tabs: overview (profile + usage meters), the
// subscription (assign/change + lifecycle actions moved OUT of the table
// rows — inline row controls were error-prone), per-company entitlement
// overrides (the plan baseline + per-account merge, the professional
// SaaS pattern), the account's OWN logs (hard company_id filter) and its
// payments. The subscriptions table now links here instead of hosting
// half a dozen icon buttons per row.

import React, { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import {
  ArrowRight, Ban, CalendarClock, History, Hourglass, LayoutDashboard,
  PauseCircle, PlayCircle, ScrollText, SlidersHorizontal,
  UserPlus, Wallet, X,
} from "lucide-react";
import { toast } from "sonner";
import {
  Card, CardContent, Button, Input, Badge,
} from "@/components/ui";
import { Modal } from "@/components/ui/modal";
import {
  accountApi, plansApi, subscriptionsApi, paymentsApi, featuresApi, ApiError,
  type CompanyProfile, type EntitlementRow, type EntitlementPayload,
  type CompanyLogRow, type PlanRow, type SubscriptionRow, type PaymentRow,
  type FeatureRow,
} from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtDate, fmtNumber } from "@/i18n/format";

type Tab = "overview" | "subscription" | "overrides" | "logs" | "payments";

const statusVariant: Record<SubscriptionRow["status"], "success" | "warning" | "destructive" | "secondary" | "default"> = {
  trial: "warning",
  active: "success",
  expired: "destructive",
  cancelled: "secondary",
  suspended: "destructive",
  pending: "default",
};

const LIMIT_KEYS = ["branches", "users", "employees", "products"] as const;

export default function CompanyAccountPage() {
  const t = useT("subscriptions");
  const router = useRouter();
  // Dynamic route /companies/[id] — useParams avoids the Suspense boundary
  // that useSearchParams requires at build time (house pattern).
  const routeParams = useParams<{ id: string }>();
  const companyId = routeParams?.id ?? null;
  const [tab, setTab] = useState<Tab>("overview");

  const [profile, setProfile] = useState<CompanyProfile | null>(null);
  const [plans, setPlans] = useState<PlanRow[]>([]);
  const [features, setFeatures] = useState<FeatureRow[]>([]);
  const [entitlements, setEntitlements] = useState<EntitlementRow[]>([]);
  const [logs, setLogs] = useState<CompanyLogRow[]>([]);
  const [logsTotal, setLogsTotal] = useState(0);
  const [logsPage, setLogsPage] = useState(1);
  const [payments, setPayments] = useState<PaymentRow[]>([]);
  const [history, setHistory] = useState<SubscriptionRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  // Read the optional ?tab= on mount.
  useEffect(() => {
    const tb = new URLSearchParams(window.location.search).get("tab");
    if (tb && ["overview", "subscription", "overrides", "logs", "payments"].includes(tb)) {
      setTab(tb as Tab);
    }
  }, []);

  const reload = useCallback(async () => {
    if (!companyId) { setLoading(false); return; }
    setLoading(true);
    try {
      const prof = await accountApi.profile(companyId);
      setProfile(prof);
      if (tab === "overrides") {
        const [planList, featList, ents] = await Promise.all([
          plansApi.list(), featuresApi.list(), accountApi.entitlements(companyId),
        ]);
        setPlans(planList);
        setFeatures(featList);
        setEntitlements(ents);
      } else if (tab === "logs") {
        const res = await accountApi.logs(companyId, logsPage);
        setLogs(res.data);
        setLogsTotal(res.pagination.total);
      } else if (tab === "payments") {
        const res = await paymentsApi.list({ company_id: companyId });
        setPayments(res.data);
      } else if (tab === "subscription") {
        const [planList, hist] = await Promise.all([
          plansApi.list(),
          subscriptionsApi.list({ history: true, company_id: companyId, pageSize: 50 }),
        ]);
        setPlans(planList);
        setHistory(hist.data);
      }
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("load_failed"));
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [companyId, tab, logsPage, t]);

  useEffect(() => { void reload(); }, [reload]);

  const sub = profile?.subscription ?? null;
  const egp = (piastres: number) => `${fmtNumber(piastres / 100)} EGP`;

  const switchTab = (next: Tab) => {
    setTab(next);
    const url = new URL(window.location.href);
    url.searchParams.set("tab", next);
    window.history.replaceState({}, "", url.toString());
  };

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
        <div className="flex items-start gap-3">
          <Button variant="ghost" size="icon" onClick={() => router.push("/subscriptions")}
            title={t("back_to_list")}>
            <ArrowRight className="h-5 w-5 rtl:rotate-180" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">{profile?.name_ar || profile?.name || t("acc_loading")}</h1>
            <p className="text-muted-foreground text-sm" dir="ltr">{profile?.email}</p>
            <div className="flex flex-wrap items-center gap-2 mt-2">
              {sub && <Badge variant={statusVariant[sub.status]}>{t(`status_${sub.status}`)}</Badge>}
              {sub && <Badge variant="outline">{sub.plan.name_ar || sub.plan.name}</Badge>}
              {profile && profile.active_overrides > 0 && (
                <Badge variant="warning">
                  {t("ov_badge").replace("{n}", String(profile.active_overrides))}
                </Badge>
              )}
              {sub?.cancel_at_period_end && <Badge variant="secondary">{t("cap_pending")}</Badge>}
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex flex-wrap gap-1 border-b border-border">
        {([
          ["overview", <LayoutDashboard key="o" className="h-4 w-4" />, t("acc_tab_overview")],
          ["subscription", <UserPlus key="s" className="h-4 w-4" />, t("acc_tab_subscription")],
          ["overrides", <SlidersHorizontal key="v" className="h-4 w-4" />, t("acc_tab_overrides")],
          ["logs", <ScrollText key="l" className="h-4 w-4" />, t("acc_tab_logs")],
          ["payments", <Wallet key="p" className="h-4 w-4" />, t("acc_tab_payments")],
        ] as const).map(([key, icon, label]) => (
          <button
            key={key}
            onClick={() => switchTab(key)}
            className={`flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors ${
              tab === key
                ? "border-emerald-600 text-emerald-700 dark:text-emerald-400"
                : "border-transparent text-muted-foreground hover:text-foreground"
            }`}
          >
            {icon}
            {label}
          </button>
        ))}
      </div>

      {!companyId ? (
        <Card><CardContent className="py-10 text-center text-muted-foreground">{t("acc_no_company")}</CardContent></Card>
      ) : loading ? (
        <Card><CardContent className="py-10 text-center text-muted-foreground">…</CardContent></Card>
      ) : !profile ? (
        <Card><CardContent className="py-10 text-center text-muted-foreground">{t("acc_no_company")}</CardContent></Card>
      ) : (
        <>
          {tab === "overview" && (
            <OverviewTab profile={profile} sub={sub} t={t} fmtDate={fmtDate} />
          )}
          {tab === "subscription" && (
            <SubscriptionTab
              profile={profile} sub={sub} plans={plans} history={history}
              reload={reload} busy={busy} setBusy={setBusy} t={t} />
          )}
          {tab === "overrides" && (
            <OverridesTab
              companyId={companyId} entitlements={entitlements}
              features={features} reload={reload} busy={busy} setBusy={setBusy} t={t} />
          )}
          {tab === "logs" && (
            <LogsTab
              logs={logs} total={logsTotal} page={logsPage}
              setPage={setLogsPage} t={t} fmtDate={fmtDate} />
          )}
          {tab === "payments" && (
            <PaymentsTab payments={payments} egp={egp} t={t} fmtDate={fmtDate} />
          )}
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

function OverviewTab({ profile, sub, t, fmtDate }: {
  profile: CompanyProfile;
  sub: SubscriptionRow | null;
  t: (k: string) => string;
  fmtDate: (d: string, o?: Intl.DateTimeFormatOptions) => string;
}) {
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <Card><CardContent className="p-4">
          <div className="text-xs text-muted-foreground">{t("acc_card_plan")}</div>
          <div className="text-lg font-bold mt-1">{sub ? (sub.plan.name_ar || sub.plan.name) : t("acc_no_sub")}</div>
          {sub && (
            <div className="text-sm text-muted-foreground mt-1">
              {sub.status === "trial" && sub.trial_ends_at
                ? `${t("col_period_end")}: ${fmtDate(sub.trial_ends_at, { dateStyle: "medium" })}`
                : sub.current_period_end
                  ? `${t("col_period_end")}: ${fmtDate(sub.current_period_end, { dateStyle: "medium" })}`
                  : t("no_period")}
            </div>
          )}
        </CardContent></Card>
        <Card><CardContent className="p-4">
          <div className="text-xs text-muted-foreground">{t("acc_card_source")}</div>
          <div className="text-lg font-bold mt-1">{sub ? t(`source_${sub.source}`) : "—"}</div>
          <div className="text-sm text-muted-foreground mt-1">{fmtDate(profile.created_at, { dateStyle: "medium" })}</div>
        </CardContent></Card>
        <Card><CardContent className="p-4">
          <div className="text-xs text-muted-foreground">{t("acc_card_overrides")}</div>
          <div className="text-lg font-bold mt-1">{profile.active_overrides}</div>
          <div className="text-sm text-muted-foreground mt-1">{t("acc_card_phone")}: {profile.phone || "—"}</div>
        </CardContent></Card>
      </div>

      <Card>
        <CardContent className="p-4">
          <div className="text-sm font-semibold mb-3">{t("acc_usage_title")}</div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            {LIMIT_KEYS.map((key) => {
              const used = profile.usage[key] ?? 0;
              return (
                <div key={key} className="rounded-md border border-border px-3 py-2">
                  <div className="text-xs text-muted-foreground">{t(`limit_${key}`)}</div>
                  <div className="text-xl font-bold">{fmtNumber(used)}</div>
                </div>
              );
            })}
          </div>
          {sub?.billing_interval && sub.billing_interval !== "none" && (
            <div className="mt-3">
              <Badge variant="outline">{t(`interval_${sub.billing_interval}`)}</Badge>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Subscription — lifecycle actions moved from the table rows
// ---------------------------------------------------------------------------

function SubscriptionTab({ profile, sub, plans, history, reload, busy, setBusy, t }: {
  profile: CompanyProfile;
  sub: SubscriptionRow | null;
  plans: PlanRow[];
  history: SubscriptionRow[];
  reload: () => Promise<void>;
  busy: boolean;
  setBusy: (b: boolean) => void;
  t: (k: string) => string;
}) {
  // assign / change plan
  const [assignOpen, setAssignOpen] = useState(false);
  const [assign, setAssign] = useState({ plan_id: "", interval: "monthly", trial_days: "0", period_end: "" });
  // extend
  const [extendOpen, setExtendOpen] = useState(false);
  const [extendDate, setExtendDate] = useState("");
  // reactivate
  const [reactOpen, setReactOpen] = useState(false);
  const [reactMode, setReactMode] = useState<"days" | "date">("days");
  const [reactDays, setReactDays] = useState(30);
  const [reactDate, setReactDate] = useState("");
  // manual payment
  const [payOpen, setPayOpen] = useState(false);
  const [pay, setPay] = useState({ plan_id: "", interval: "monthly", amount: "", note: "" });
  const [payIdempotencyKey, setPayIdempotencyKey] = useState("");

  const companyId = profile.id;

  const run = async (fn: () => Promise<unknown>, okMsg?: string) => {
    setBusy(true);
    try {
      await fn();
      toast.success(okMsg || t("saved"));
      await reload();
      return true;
    } catch (e) {
      // رسالة الخادم الحقيقية أولًا (invalid_state/period_end_required…) —
      // «فشل» العمياء تركت المسؤول بلا سبب (درس بلاغ إعادة التفعيل)
      toast.error(e instanceof ApiError && e.message ? e.message : t("failed"));
      return false;
    } finally {
      setBusy(false);
    }
  };

  const doAssign = async () => {
    if (!assign.plan_id) { toast.error(t("failed")); return; }
    const ok = await run(() => subscriptionsApi.assign({
      company_id: companyId,
      plan_id: assign.plan_id,
      billing_interval: assign.interval as "none" | "monthly" | "yearly",
      trial_days: Number(assign.trial_days || "0"),
      current_period_end: assign.period_end || undefined,
    }));
    if (ok) setAssignOpen(false);
  };

  const reactEndIso = () => {
    if (reactMode === "date" && reactDate) {
      const d = new Date(`${reactDate}T23:59:59`);
      if (!Number.isNaN(d.getTime())) return d.toISOString();
    }
    return new Date(Date.now() + reactDays * 86400000).toISOString();
  };

  const doManualPayment = async () => {
    if (!pay.plan_id) { toast.error(t("failed")); return; }
    const ok = await run(() => subscriptionsApi.manualPayment({
      company_id: companyId,
      plan_id: pay.plan_id,
      billing_interval: pay.interval as "monthly" | "yearly",
      amount_piastres: pay.amount ? Math.round(Number(pay.amount) * 100) : undefined,
      note: pay.note || undefined,
      idempotency_key: payIdempotencyKey || undefined,
    }));
    if (ok) setPayOpen(false);
  };

  return (
    <div className="space-y-4">
      {/* Actions — all the controls that used to be icon buttons in the
          table rows, now in a proper form area with confirmations. */}
      <div className="flex flex-wrap gap-2">
        <Button onClick={() => {
          setAssign({
            plan_id: sub?.plan.id || "",
            interval: sub?.billing_interval === "yearly" ? "yearly" : sub?.billing_interval === "none" ? "none" : "monthly",
            trial_days: "0", period_end: "",
          });
          setAssignOpen(true);
        }}>
          <UserPlus className="h-4 w-4 ms-2" />
          {sub && (sub.status === "active" || sub.status === "trial") ? t("acc_change_plan") : t("assign")}
        </Button>
        {sub && (sub.status === "active" || sub.status === "trial") && (
          <Button variant="outline" onClick={() => { setExtendDate(""); setExtendOpen(true); }}>
            <CalendarClock className="h-4 w-4 ms-2" />
            {sub.status === "trial" ? t("extend_trial_title") : t("extend")}
          </Button>
        )}
        {sub && (sub.status === "active" || sub.status === "trial") && (
          <Button variant="outline" disabled={busy}
            onClick={() => void run(() => subscriptionsApi.action(sub.id, {
              action: "set_cancel_at_period_end",
              cancel_at_period_end: !sub.cancel_at_period_end,
            }))}>
            <Hourglass className="h-4 w-4 ms-2" />
            {sub.cancel_at_period_end ? t("cap_unset") : t("cap_set")}
          </Button>
        )}
        <Button variant="outline" onClick={() => {
          setPay({ plan_id: sub?.plan.id || "", interval: "monthly", amount: "", note: "" });
          setPayIdempotencyKey(crypto.randomUUID());
          setPayOpen(true);
        }}>
          <Wallet className="h-4 w-4 ms-2" />
          {t("manual_payment")}
        </Button>
        {sub && (sub.status === "active" || sub.status === "trial") && (
          <Button variant="outline" className="text-amber-700 border-amber-300 hover:bg-amber-50 dark:hover:bg-amber-950"
            disabled={busy}
            onClick={() => { if (window.confirm(t("confirm_suspend"))) void run(() => subscriptionsApi.action(sub.id, { action: "suspend" })); }}>
            <PauseCircle className="h-4 w-4 ms-2" />
            {t("suspend")}
          </Button>
        )}
        {sub && (sub.status === "expired" || sub.status === "cancelled" || sub.status === "suspended") && (
          <Button variant="outline"
            onClick={() => { setReactMode("days"); setReactDays(30); setReactDate(""); setReactOpen(true); }}>
            <PlayCircle className="h-4 w-4 ms-2" />
            {t("reactivate")}
          </Button>
        )}
        {sub && sub.status !== "cancelled" && (
          <Button variant="outline" className="text-destructive border-destructive/40 hover:bg-destructive/10"
            disabled={busy}
            onClick={() => { if (window.confirm(t("confirm_cancel"))) void run(() => subscriptionsApi.action(sub.id, { action: "cancel" })); }}>
            <Ban className="h-4 w-4 ms-2" />
            {t("cancel_sub")}
          </Button>
        )}
      </div>

      {/* Version ledger — this account only */}
      <Card>
        <CardContent className="p-0">
          <div className="flex items-center gap-2 px-4 py-3 text-sm font-semibold border-b border-border">
            <History className="h-4 w-4 text-emerald-600" />
            {t("acc_versions_title")}
            <Badge variant="outline">{history.length}</Badge>
          </div>
          {history.length === 0 ? (
            <div className="py-8 text-center text-muted-foreground text-sm">{t("acc_no_sub")}</div>
          ) : (
            <div className="divide-y divide-border">
              {history.map((row) => {
                const live = row.status === "pending" || row.status === "trial" || row.status === "active";
                return (
                  <div key={row.id} className={`flex flex-wrap items-center justify-between gap-2 px-4 py-2.5 text-sm ${live ? "bg-emerald-500/5" : ""}`}>
                    <div className="font-medium">{row.plan.name_ar || row.plan.name}</div>
                    <Badge variant={statusVariant[row.status]}>{t(`status_${row.status}`)}</Badge>
                    <div className="text-muted-foreground">
                      {row.current_period_end ? fmtDateSafeDay(row.current_period_end) : "—"}
                    </div>
                    <div className="text-muted-foreground">{t(`source_${row.source}`)}</div>
                    <div className="text-xs text-muted-foreground">{fmtDateSafeDay(row.created_at)}</div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Assign / change plan modal */}
      <Modal isOpen={assignOpen} onClose={() => setAssignOpen(false)}>
        <div className="w-[420px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{t("assign_title")}</h2>
          <div className="rounded-md border border-border bg-muted/30 px-3 py-2 text-sm">
            <div className="font-medium">{profile.name_ar || profile.name}</div>
            <div className="text-xs text-muted-foreground" dir="ltr">{profile.email}</div>
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
            <Button disabled={busy || !assign.plan_id} onClick={() => void doAssign()}>{busy ? "…" : t("saved")}</Button>
          </div>
        </div>
      </Modal>

      {/* Extend modal */}
      <Modal isOpen={extendOpen} onClose={() => setExtendOpen(false)}>
        <div className="w-[380px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{sub?.status === "trial" ? t("extend_trial_title") : t("extend_title")}</h2>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{sub?.status === "trial" ? t("new_trial_end") : t("new_period_end")}</span>
            <Input type="date" value={extendDate} onChange={(e) => setExtendDate(e.target.value)} />
          </label>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setExtendOpen(false)}>{t("cancel_sub")}</Button>
            <Button disabled={busy || !extendDate} onClick={() => {
              if (!sub || !extendDate) return;
              void run(() => subscriptionsApi.action(sub.id, {
                action: "extend",
                current_period_end: new Date(extendDate).toISOString(),
              })).then((ok) => { if (ok) setExtendOpen(false); });
            }}>{busy ? "…" : t("saved")}</Button>
          </div>
        </div>
      </Modal>

      {/* Reactivate modal */}
      <Modal isOpen={reactOpen} onClose={() => setReactOpen(false)}>
        <div className="w-[420px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{t("reactivate_title")}</h2>
          <p className="text-sm text-muted-foreground">{t("reactivate_hint")}</p>
          <div className="grid grid-cols-4 gap-2">
            {[7, 14, 30, 90].map((d) => (
              <Button key={d} size="sm"
                variant={reactMode === "days" && reactDays === d ? "default" : "outline"}
                onClick={() => { setReactMode("days"); setReactDays(d); }}>
                {t(`reactivate_p${d}`)}
              </Button>
            ))}
          </div>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("reactivate_custom")}</span>
            <Input type="date" value={reactDate}
              onChange={(e) => { setReactDate(e.target.value); if (e.target.value) setReactMode("date"); }} />
          </label>
          <div className="rounded-md border border-emerald-500/40 bg-emerald-500/10 px-3 py-2 text-sm">
            {t("reactivate_until")}{" "}
            <span className="font-semibold">{fmtDateSafeDay(reactEndIso())}</span>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setReactOpen(false)}>{t("cancel_sub")}</Button>
            <Button disabled={busy} onClick={() => {
              if (!sub) return;
              void run(() => subscriptionsApi.action(sub.id, {
                action: "reactivate",
                current_period_end: reactEndIso(),
              })).then((ok) => { if (ok) setReactOpen(false); });
            }}>{busy ? "…" : t("reactivate_confirm")}</Button>
          </div>
        </div>
      </Modal>

      {/* Manual payment modal */}
      <Modal isOpen={payOpen} onClose={() => setPayOpen(false)}>
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
            <Button variant="outline" onClick={() => setPayOpen(false)}>{t("cancel_sub")}</Button>
            <Button disabled={busy || !pay.plan_id} onClick={() => void doManualPayment()}>{busy ? "…" : t("saved")}</Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}

// Locale-safe short date without pulling the hook through every modal.
function fmtDateSafeDay(iso: string) {
  try {
    return new Date(iso).toLocaleDateString(undefined, { dateStyle: "medium" });
  } catch {
    return iso.slice(0, 10);
  }
}

// ---------------------------------------------------------------------------
// Overrides — the «التحكم الكامل» layer
// ---------------------------------------------------------------------------

function OverridesTab({ companyId, entitlements, features, reload, busy, setBusy, t }: {
  companyId: string;
  entitlements: EntitlementRow[];
  features: FeatureRow[];
  reload: () => Promise<void>;
  busy: boolean;
  setBusy: (b: boolean) => void;
  t: (k: string) => string;
}) {
  const [addOpen, setAddOpen] = useState(false);
  const [form, setForm] = useState<{
    kind: EntitlementPayload["kind"]; featureKey: string; permKey: string;
    enabled: boolean; limitKey: string; limitValue: string; unlimited: boolean;
    reason: string; expires: string;
  }>({
    kind: "feature", featureKey: "", permKey: "", enabled: true,
    limitKey: "branches", limitValue: "5", unlimited: false, reason: "", expires: "",
  });

  const permissionSuggestions = useMemo(() => {
    const f = features.find((x) => x.key === form.featureKey);
    return f ? f.suggested_permissions : [];
  }, [features, form.featureKey]);

  const doAdd = async () => {
    const payload: EntitlementPayload = { kind: form.kind, key: "", reason: form.reason || undefined };
    if (form.expires) payload.expires_at = new Date(`${form.expires}T23:59:59`).toISOString();
    if (form.kind === "feature") {
      payload.key = form.featureKey;
      payload.enabled = form.enabled;
    } else if (form.kind === "permission") {
      payload.key = form.permKey.trim();
      payload.enabled = form.enabled;
    } else {
      payload.key = form.limitKey;
      payload.value = form.unlimited ? -1 : Number(form.limitValue || "0");
      if (!payload.value || payload.value < -1) { toast.error(t("ov_invalid_value")); return; }
    }
    if (!payload.key) { toast.error(t("failed")); return; }
    setBusy(true);
    try {
      await accountApi.upsertEntitlement(companyId, payload);
      toast.success(t("saved"));
      setAddOpen(false);
      await reload();
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const doDelete = async (row: EntitlementRow) => {
    if (!window.confirm(t("ov_confirm_delete"))) return;
    setBusy(true);
    try {
      await accountApi.deleteEntitlement(companyId, row.id);
      toast.success(t("saved"));
      await reload();
    } catch (e) {
      toast.error(e instanceof ApiError && e.message ? e.message : t("failed"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="rounded-md border border-emerald-500/40 bg-emerald-500/5 px-4 py-3 text-sm">
        {t("ov_explainer")}
      </div>

      <div className="flex justify-between items-center">
        <div className="text-sm font-semibold">{t("ov_list_title")}</div>
        <Button onClick={() => setAddOpen(true)}>
          <SlidersHorizontal className="h-4 w-4 ms-2" />
          {t("ov_add")}
        </Button>
      </div>

      <Card>
        <CardContent className="p-0">
          {entitlements.length === 0 ? (
            <div className="py-10 text-center text-muted-foreground text-sm">{t("ov_empty")}</div>
          ) : (
            <div className="divide-y divide-border">
              {entitlements.map((row) => {
                const bundled = row.bundle_key !== "";
                return (
                  <div key={row.id} className={`flex flex-wrap items-center justify-between gap-2 px-4 py-3 text-sm ${row.expired ? "opacity-50" : ""}`}>
                    <div className="flex items-center gap-2">
                      <Badge variant={row.kind === "feature" ? "default" : row.kind === "permission" ? "secondary" : "outline"}>
                        {t(`ov_kind_${row.kind}`)}
                      </Badge>
                      <span className="font-mono font-medium" dir="ltr">{row.key}</span>
                      {row.kind !== "limit" && (
                        <Badge variant={row.enabled ? "success" : "destructive"}>
                          {row.enabled ? t("ov_granted") : t("ov_denied")}
                        </Badge>
                      )}
                      {row.kind === "limit" && (
                        <Badge variant="warning">
                          {row.value === -1 ? t("ov_unlimited") : `${fmtNumber(row.value ?? 0)}`}
                        </Badge>
                      )}
                      {bundled && <Badge variant="outline">{t("ov_bundled")}</Badge>}
                      {row.expired && <Badge variant="secondary">{t("ov_expired")}</Badge>}
                    </div>
                    <div className="flex items-center gap-3">
                      <div className="text-xs text-muted-foreground max-w-[220px] truncate" title={row.reason}>
                        {row.reason || "—"}
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {row.expires_at ? `${t("ov_until")} ${fmtDateSafeDay(row.expires_at)}` : t("ov_permanent")}
                      </div>
                      {!bundled && (
                        <Button variant="ghost" size="icon" className="text-destructive" disabled={busy}
                          title={t("ov_delete")} onClick={() => void doDelete(row)}>
                          <X className="h-4 w-4" />
                        </Button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      <Modal isOpen={addOpen} onClose={() => setAddOpen(false)}>
        <div className="w-[440px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{t("ov_add_title")}</h2>
          <p className="text-sm text-muted-foreground">{t("ov_add_hint")}</p>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("ov_kind")}</span>
            <select className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
              value={form.kind}
              onChange={(e) => setForm({ ...form, kind: e.target.value as EntitlementPayload["kind"] })}>
              <option value="feature">{t("ov_kind_feature")}</option>
              <option value="permission">{t("ov_kind_permission")}</option>
              <option value="limit">{t("ov_kind_limit")}</option>
            </select>
          </label>

          {form.kind === "feature" && (
            <>
              <label className="block text-sm space-y-1">
                <span className="text-muted-foreground">{t("ov_feature")}</span>
                <select className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                  value={form.featureKey} onChange={(e) => setForm({ ...form, featureKey: e.target.value })}>
                  <option value="">—</option>
                  {features.map((f) => (
                    <option key={f.key} value={f.key}>{f.name_ar || f.name} ({f.key})</option>
                  ))}
                </select>
              </label>
              <div className="grid grid-cols-2 gap-2">
                <Button size="sm" variant={form.enabled ? "default" : "outline"}
                  onClick={() => setForm({ ...form, enabled: true })}>{t("ov_grant")}</Button>
                <Button size="sm" variant={!form.enabled ? "destructive" : "outline"}
                  onClick={() => setForm({ ...form, enabled: false })}>{t("ov_deny")}</Button>
              </div>
            </>
          )}

          {form.kind === "permission" && (
            <>
              <label className="block text-sm space-y-1">
                <span className="text-muted-foreground">{t("ov_permission")}</span>
                <Input dir="ltr" className="font-mono" placeholder="sales.create" value={form.permKey}
                  onChange={(e) => setForm({ ...form, permKey: e.target.value })} />
              </label>
              <div className="grid grid-cols-2 gap-2">
                <Button size="sm" variant={form.enabled ? "default" : "outline"}
                  onClick={() => setForm({ ...form, enabled: true })}>{t("ov_grant")}</Button>
                <Button size="sm" variant={!form.enabled ? "destructive" : "outline"}
                  onClick={() => setForm({ ...form, enabled: false })}>{t("ov_deny")}</Button>
              </div>
            </>
          )}

          {form.kind === "limit" && (
            <>
              <label className="block text-sm space-y-1">
                <span className="text-muted-foreground">{t("ov_limit_key")}</span>
                <select className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                  value={form.limitKey} onChange={(e) => setForm({ ...form, limitKey: e.target.value })}>
                  {LIMIT_KEYS.map((k) => (
                    <option key={k} value={k}>{t(`limit_${k}`)}</option>
                  ))}
                </select>
              </label>
              <div className="flex items-center gap-3">
                <Input type="number" min="1" dir="ltr" className="w-32" value={form.limitValue}
                  disabled={form.unlimited}
                  onChange={(e) => setForm({ ...form, limitValue: e.target.value })} />
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={form.unlimited}
                    onChange={(e) => setForm({ ...form, unlimited: e.target.checked })} />
                  {t("ov_unlimited")}
                </label>
              </div>
            </>
          )}

          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("ov_reason")}</span>
            <Input value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
          </label>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("ov_expires")}</span>
            <Input type="date" value={form.expires} onChange={(e) => setForm({ ...form, expires: e.target.value })} />
          </label>

          {form.kind === "feature" && permissionSuggestions.length > 0 && (
            <div className="rounded-md border border-border bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
              {t("ov_bundle_hint").replace("{n}", String(permissionSuggestions.length))}
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setAddOpen(false)}>{t("cancel_sub")}</Button>
            <Button disabled={busy} onClick={() => void doAdd()}>{busy ? "…" : t("saved")}</Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Logs — this account only
// ---------------------------------------------------------------------------

function LogsTab({ logs, total, page, setPage, t, fmtDate }: {
  logs: CompanyLogRow[];
  total: number;
  page: number;
  setPage: (p: number) => void;
  t: (k: string) => string;
  fmtDate: (d: string, o?: Intl.DateTimeFormatOptions) => string;
}) {
  const totalPages = Math.max(1, Math.ceil(total / 50));
  return (
    <Card>
      <CardContent className="p-0">
        <div className="flex items-center gap-2 px-4 py-3 text-sm font-semibold border-b border-border">
          <ScrollText className="h-4 w-4 text-emerald-600" />
          {t("log_title")}
          <Badge variant="outline">{total}</Badge>
        </div>
        {logs.length === 0 ? (
          <div className="py-10 text-center text-muted-foreground text-sm">{t("log_empty")}</div>
        ) : (
          <div className="divide-y divide-border">
            {logs.map((row) => (
              <div key={row.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5 text-sm">
                <div className="flex items-center gap-2 min-w-0">
                  <Badge variant="outline" dir="ltr">{row.action}</Badge>
                  <span className="truncate">{row.summary}</span>
                </div>
                <div className="flex items-center gap-3 text-xs text-muted-foreground">
                  <span>{row.actor}</span>
                  <span>{fmtDate(row.created_at, { dateStyle: "medium", timeStyle: "short" })}</span>
                </div>
              </div>
            ))}
          </div>
        )}
        {totalPages > 1 && (
          <div className="flex items-center justify-between px-4 py-3 border-t border-border text-sm">
            <Button variant="outline" size="sm" disabled={page <= 1}
              onClick={() => setPage(page - 1)}>{t("log_prev")}</Button>
            <span className="text-muted-foreground">{page} / {totalPages}</span>
            <Button variant="outline" size="sm" disabled={page >= totalPages}
              onClick={() => setPage(page + 1)}>{t("log_next")}</Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Payments — this company only
// ---------------------------------------------------------------------------

function PaymentsTab({ payments, egp, t, fmtDate }: {
  payments: PaymentRow[];
  egp: (p: number) => string;
  t: (k: string) => string;
  fmtDate: (d: string, o?: Intl.DateTimeFormatOptions) => string;
}) {
  return (
    <Card>
      <CardContent className="p-0">
        {payments.length === 0 ? (
          <div className="py-10 text-center text-muted-foreground text-sm">{t("acc_no_payments")}</div>
        ) : (
          <div className="divide-y divide-border">
            {payments.map((p) => (
              <div key={p.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 text-sm">
                <div className="font-medium">{p.plan?.name_ar || p.plan?.name || "—"}</div>
                <div className="font-semibold" dir="ltr">{egp(p.amount_piastres)}</div>
                <Badge variant={p.status === "succeeded" ? "success" : p.status === "pending" ? "warning" : "destructive"}>
                  {p.status}
                </Badge>
                <Badge variant="outline">{t(`source_${p.provider === "manual" ? "manual" : "online"}`)}</Badge>
                <div className="text-xs text-muted-foreground">{fmtDate(p.created_at, { dateStyle: "medium" })}</div>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
