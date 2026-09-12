"use client";

// Task 90 — subscription operations: the super admin monitors every
// company's subscription and applies lifecycle actions (extend, cancel,
// suspend, reactivate) and registers manual payments — which perform the
// exact subscription transitions the future Paymob webhook will drive.

import React, { useCallback, useEffect, useState } from "react";
import { CalendarClock, Ban, PauseCircle, PlayCircle, Wallet, UserPlus } from "lucide-react";
import { toast } from "sonner";
import {
  Card, CardContent, Button, Input, Badge,
} from "@/components/ui";
import { Table, TableHeader, TableBody, TableRow, TableHead } from "@/components/ui/table";
import { Modal } from "@/components/ui/modal";
import { plansApi, subscriptionsApi, type PlanRow, type SubscriptionRow } from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtDate } from "@/i18n/format";

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
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("all");
  const [search, setSearch] = useState("");

  const [assignOpen, setAssignOpen] = useState(false);
  const [assign, setAssign] = useState({ company_id: "", plan_id: "", interval: "monthly", trial_days: "0", period_end: "" });
  const [extendRow, setExtendRow] = useState<SubscriptionRow | null>(null);
  const [extendDate, setExtendDate] = useState("");
  const [payRow, setPayRow] = useState<SubscriptionRow | null>(null);
  const [pay, setPay] = useState({ plan_id: "", interval: "monthly", amount: "", note: "" });
  const [busy, setBusy] = useState(false);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const [subs, planList] = await Promise.all([
        subscriptionsApi.list({
          status: statusFilter === "all" ? undefined : statusFilter,
          search: search || undefined,
        }),
        plansApi.list(),
      ]);
      setRows(subs.data);
      setPlans(planList);
    } catch {
      toast.error(t("load_failed"));
    } finally {
      setLoading(false);
    }
  }, [statusFilter, search, t]);

  useEffect(() => { void reload(); }, [reload]);

  const runAction = async (row: SubscriptionRow, action: "cancel" | "suspend" | "reactivate") => {
    if (action === "cancel" && !window.confirm(t("confirm_cancel"))) return;
    if (action === "suspend" && !window.confirm(t("confirm_suspend"))) return;
    setBusy(true);
    try {
      await subscriptionsApi.action(row.id, { action });
      toast.success(t("saved"));
      await reload();
    } catch {
      toast.error(t("failed"));
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
    } catch {
      toast.error(t("failed"));
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
    } catch {
      toast.error(t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const doManualPayment = async () => {
    if (!payRow || !pay.plan_id) return;
    setBusy(true);
    try {
      await subscriptionsApi.manualPayment({
        company_id: payRow.company.id,
        plan_id: pay.plan_id,
        billing_interval: pay.interval as "monthly" | "yearly",
        amount_piastres: pay.amount ? Math.round(Number(pay.amount) * 100) : undefined,
        note: pay.note || undefined,
      });
      toast.success(t("saved"));
      setPayRow(null);
      await reload();
    } catch {
      toast.error(t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const periodLabel = (row: SubscriptionRow) => {
    if (row.status === "trial" && row.trial_ends_at) return fmtDate(row.trial_ends_at, { dateStyle: "medium" });
    if (row.current_period_end) return fmtDate(row.current_period_end, { dateStyle: "medium" });
    return t("no_period");
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">{t("title")}</h1>
          <p className="text-muted-foreground mt-1">{t("subtitle")}</p>
        </div>
        <Button onClick={() => { setAssign({ company_id: "", plan_id: "", interval: "monthly", trial_days: "0", period_end: "" }); setAssignOpen(true); }}>
          <UserPlus className="h-4 w-4 ms-2" />
          {t("assign")}
        </Button>
      </div>

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
                    </td>
                    <td className="px-4 py-3 text-sm">{row.plan.name_ar || row.plan.name}</td>
                    <td className="px-4 py-3 text-sm">
                      <Badge variant={statusVariant[row.status]}>{t(`status_${row.status}`)}</Badge>
                    </td>
                    <td className="px-4 py-3 text-sm">{periodLabel(row)}</td>
                    <td className="px-4 py-3 text-sm text-muted-foreground">{t(`source_${row.source}`)}</td>
                    <td className="px-4 py-3 text-sm">
                      <div className="flex items-center justify-end gap-1">
                        <Button variant="ghost" size="icon" title={t("extend")}
                          onClick={() => { setExtendRow(row); setExtendDate(""); }}>
                          <CalendarClock className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" title={t("manual_payment")}
                          onClick={() => { setPayRow(row); setPay({ plan_id: row.plan.id, interval: "monthly", amount: "", note: "" }); }}>
                          <Wallet className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" title={t("suspend")}
                          onClick={() => void runAction(row, "suspend")}>
                          <PauseCircle className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" title={t("reactivate")}
                          onClick={() => void runAction(row, "reactivate")}>
                          <PlayCircle className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" className="text-destructive" title={t("cancel_sub")}
                          onClick={() => void runAction(row, "cancel")}>
                          <Ban className="h-4 w-4" />
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

      {/* Assign plan */}
      <Modal isOpen={assignOpen} onClose={() => setAssignOpen(false)}>
        <div className="w-[440px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{t("assign_title")}</h2>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("assign_company")}</span>
            <Input dir="ltr" value={assign.company_id} onChange={(e) => setAssign({ ...assign, company_id: e.target.value })} />
          </label>
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

      {/* Extend */}
      <Modal isOpen={!!extendRow} onClose={() => setExtendRow(null)}>
        <div className="w-[380px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{t("extend_title")}</h2>
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("new_period_end")}</span>
            <Input type="date" value={extendDate} onChange={(e) => setExtendDate(e.target.value)} />
          </label>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setExtendRow(null)}>{t("cancel_sub")}</Button>
            <Button disabled={busy || !extendDate} onClick={() => void doExtend()}>{busy ? "…" : t("saved")}</Button>
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
