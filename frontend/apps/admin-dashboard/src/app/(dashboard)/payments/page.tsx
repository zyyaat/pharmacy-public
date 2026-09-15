"use client";

// Payments ledger + settlement & reconciliation worklist (Phase S1).
// Three money questions, three answers on one surface:
//   CONFIRMED (confirmation badge) — SETTLED (operator-verified payout batch)
//   — REVIEW (machine refused to decide). Every manual state change carries a
//   note, an actor and an audit row; resync asks XPay directly via the
//   server-only secret. The ledger stays one table: filter, inspect, act.

import React, { useCallback, useEffect, useState } from "react";
import { Undo2, RefreshCw, ChevronDown, ChevronUp, ShieldAlert, Eye, Landmark, Scale } from "lucide-react";
import { toast } from "sonner";
import {
  Card, CardContent, Button, Input, Badge,
} from "@/components/ui";
import { Table, TableHeader, TableBody, TableRow, TableHead } from "@/components/ui/table";
import { Modal } from "@/components/ui/modal";
import {
  paymentsApi, type PaymentRow, type PaymentDetail, type ReconciliationData,
  type PaymentSettlementStatus,
} from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtDate, fmtNumber, fmtDateTime } from "@/i18n/format";

const statusVariant: Record<PaymentRow["status"], "success" | "warning" | "destructive" | "secondary" | "default"> = {
  pending: "warning",
  succeeded: "success",
  failed: "destructive",
  refunded: "secondary",
  voided: "secondary",
  cancelled: "secondary",
};

const settlementVariant: Record<string, "success" | "warning" | "destructive" | "secondary" | "default"> = {
  settled: "success",
  partially_settled: "warning",
  pending: "warning",
  failed: "destructive",
  disputed: "destructive",
  unknown: "destructive",
  manual: "secondary",
  missing: "secondary",
};

const SETTLEMENT_TARGETS: PaymentSettlementStatus[] = [
  "settled", "partially_settled", "failed", "disputed", "pending",
];

export default function PaymentsPage() {
  const t = useT("payments");
  const [rows, setRows] = useState<PaymentRow[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("all");
  const [providerFilter, setProviderFilter] = useState("all");
  const [settlementFilter, setSettlementFilter] = useState("all");
  const [reviewOnly, setReviewOnly] = useState(false);
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);

  const [refundRow, setRefundRow] = useState<PaymentRow | null>(null);
  const [refundNote, setRefundNote] = useState("");
  const [refundShorten, setRefundShorten] = useState(false);
  const [busy, setBusy] = useState(false);

  // Reconciliation worklist
  const [recon, setRecon] = useState<ReconciliationData | null>(null);
  const [reconOpen, setReconOpen] = useState<Record<string, boolean>>({});

  // Payment detail drawer/modal
  const [detail, setDetail] = useState<PaymentDetail | null>(null);
  const [detailBusy, setDetailBusy] = useState(false);
  const [settleStatus, setSettleStatus] = useState<PaymentSettlementStatus>("settled");
  const [settleRef, setSettleRef] = useState("");
  const [settleFees, setSettleFees] = useState("");
  const [settleNote, setSettleNote] = useState("");

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const res = await paymentsApi.list({
        status: statusFilter === "all" ? undefined : statusFilter,
        provider: providerFilter === "all" ? undefined : providerFilter,
        settlement: settlementFilter === "all" ? undefined : settlementFilter,
        needs_review: reviewOnly || undefined,
        search: search || undefined,
        page,
        pageSize: 50,
      });
      setRows(res.data);
      setTotal(res.pagination?.total ?? res.data.length);
    } catch {
      toast.error(t("load_failed"));
    } finally {
      setLoading(false);
    }
  }, [statusFilter, providerFilter, settlementFilter, reviewOnly, search, page, t]);

  const reloadRecon = useCallback(async () => {
    try {
      setRecon(await paymentsApi.reconciliation());
    } catch {
      /* the ledger itself still renders — the worklist is a bonus panel */
    }
  }, []);

  useEffect(() => { void reload(); }, [reload]);
  useEffect(() => { void reloadRecon(); }, [reloadRecon]);

  const doRefund = async () => {
    if (!refundRow) return;
    setBusy(true);
    try {
      const res = await paymentsApi.refund(refundRow.id, {
        note: refundNote || undefined,
        shorten_subscription: refundShorten,
      });
      toast.success(res.shortened ? t("refunded_shortened") : t("refunded"));
      setRefundRow(null);
      setRefundNote("");
      setRefundShorten(false);
      await reload();
      await reloadRecon();
    } catch {
      toast.error(t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const openDetail = async (row: PaymentRow) => {
    try {
      const d = await paymentsApi.detail(row.id);
      setDetail(d);
      setSettleStatus("settled");
      setSettleRef(d.settlement?.reference ?? "");
      setSettleFees("");
      setSettleNote("");
    } catch {
      toast.error(t("load_failed"));
    }
  };

  const doSettle = async () => {
    if (!detail) return;
    setDetailBusy(true);
    try {
      await paymentsApi.settle(detail.id, {
        status: settleStatus,
        provider_settlement_reference: settleRef || undefined,
        fees_piastres: settleFees ? Math.round(parseFloat(settleFees) * 100) : undefined,
        note: settleNote,
      });
      toast.success(t("settlement_saved"));
      setDetail(null);
      await reload();
      await reloadRecon();
    } catch (e) {
      const msg = (e as { message?: string })?.message || t("failed");
      toast.error(msg);
    } finally {
      setDetailBusy(false);
    }
  };

  const doResync = async (id: string) => {
    setDetailBusy(true);
    try {
      const res = await paymentsApi.resync(id);
      const key = `resync_${res.result}`;
      toast.success(t(key));
      setDetail(null);
      await reload();
      await reloadRecon();
    } catch (e) {
      const msg = (e as { message?: string })?.message || t("failed");
      toast.error(msg);
    } finally {
      setDetailBusy(false);
    }
  };

  const egp = (piastres: number, currency: string) => `${fmtNumber(piastres / 100)} ${currency}`;

  const bucketRows = (key: string, data: PaymentRow[]) => (
    <div className="rounded-md border border-border overflow-x-auto">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t("col_company")}</TableHead>
            <TableHead>{t("col_amount")}</TableHead>
            <TableHead>{t("col_provider")}</TableHead>
            <TableHead>{t("col_status")}</TableHead>
            <TableHead>{t("col_settlement")}</TableHead>
            <TableHead className="text-end">{t("col_actions")}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {data.map((row) => (
            <TableRow key={`${key}-${row.id}`}>
              <td className="px-3 py-2 text-sm">
                <div className="font-medium">{row.company.name}</div>
                {row.number && <div className="text-xs text-muted-foreground" dir="ltr">{row.number}</div>}
              </td>
              <td className="px-3 py-2 text-sm font-semibold">{egp(row.amount_piastres, row.currency)}</td>
              <td className="px-3 py-2 text-sm">{t(`provider_${row.provider}`)}</td>
              <td className="px-3 py-2 text-sm">
                <Badge variant={statusVariant[row.status]}>{t(`status_${row.status}`)}</Badge>
              </td>
              <td className="px-3 py-2 text-sm">
                <Badge variant={settlementVariant[row.settlement_status ?? "missing"] ?? "secondary"}>
                  {t(`settlement_${row.settlement_status ?? "missing"}`)}
                </Badge>
              </td>
              <td className="px-3 py-2 text-sm">
                <div className="flex items-center justify-end gap-1">
                  {row.provider === "xpay" && row.provider_reference && (
                    <Button variant="ghost" size="icon" title={t("resync")}
                      onClick={() => void doResync(row.id)}>
                      <RefreshCw className="h-4 w-4" />
                    </Button>
                  )}
                  <Button variant="ghost" size="icon" title={t("details")}
                    onClick={() => void openDetail(row)}>
                    <Eye className="h-4 w-4" />
                  </Button>
                </div>
              </td>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );

  const buckets: Array<{ key: string; icon: React.ReactNode; data: PaymentRow[] }> = recon ? [
    { key: "needs_review", icon: <ShieldAlert className="h-4 w-4 text-destructive" />, data: recon.needs_review },
    { key: "settlement_conflicts", icon: <Scale className="h-4 w-4 text-destructive" />, data: recon.settlement_conflicts },
    { key: "confirmed_unsettled", icon: <Landmark className="h-4 w-4 text-amber-600" />, data: recon.confirmed_unsettled },
    { key: "stale_pending", icon: <RefreshCw className="h-4 w-4 text-muted-foreground" />, data: recon.stale_pending },
    { key: "refunded", icon: <Undo2 className="h-4 w-4 text-muted-foreground" />, data: recon.refunded },
  ] : [];

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-bold">{t("title")}</h1>
        <p className="text-muted-foreground mt-1">{t("subtitle")}</p>
      </div>

      {/* Reconciliation worklist — the operator's matching queue */}
      {recon && (
        <Card>
          <CardContent className="p-4 space-y-3">
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <h2 className="font-semibold">{t("recon_title")}</h2>
              <div className="flex gap-4 text-xs text-muted-foreground flex-wrap">
                <span>{t("recon_summary_unsettled")}: <b className="text-foreground">{egp(recon.summary.confirmed_unsettled_piastres, "EGP")}</b></span>
                <span>{t("recon_summary_window")}: {fmtNumber(recon.summary.stale_pending_after_hours)} {t("recon_summary_hours")}</span>
              </div>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
              {[
                { k: "needs_review", n: recon.summary.needs_review_count, c: "text-destructive" },
                { k: "settlement_conflicts", n: recon.summary.settlement_conflicts_count, c: "text-destructive" },
                { k: "confirmed_unsettled", n: recon.summary.confirmed_unsettled_count, c: "text-amber-600" },
                { k: "stale_pending", n: recon.summary.stale_pending_count, c: "text-muted-foreground" },
                { k: "refunded", n: recon.summary.refunded_count, c: "text-muted-foreground" },
              ].map(({ k, n, c }) => (
                <button key={k} type="button"
                  className="rounded-md border border-border px-3 py-2 text-start hover:bg-muted/40 transition"
                  onClick={() => setReconOpen((o) => ({ ...o, [k]: !o[k] }))}>
                  <div className={`text-xl font-bold ${c}`}>{fmtNumber(n)}</div>
                  <div className="text-xs text-muted-foreground flex items-center gap-1">
                    {buckets.find((b) => b.key === k)?.icon}
                    {t(`recon_bucket_${k}`)}
                  </div>
                </button>
              ))}
            </div>
            {buckets.map(({ key, data }) => data.length > 0 && (
              <div key={key} className="space-y-2">
                <button type="button"
                  className="flex items-center gap-1 text-sm font-medium text-muted-foreground hover:text-foreground"
                  onClick={() => setReconOpen((o) => ({ ...o, [key]: !o[key] }))}>
                  {reconOpen[key] ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                  {t(`recon_bucket_${key}`)} ({fmtNumber(data.length)})
                </button>
                {reconOpen[key] && bucketRows(key, data)}
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <div className="flex flex-col sm:flex-row gap-3">
        <Input className="sm:max-w-xs" placeholder={t("search_placeholder")} value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} />
        <select
          className="sm:max-w-[170px] rounded-md border border-border bg-background px-3 py-2 text-sm"
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
        >
          <option value="all">{t("filter_status_all")}</option>
          {(["pending", "succeeded", "failed", "refunded"] as const).map((s) => (
            <option key={s} value={s}>{t(`status_${s}`)}</option>
          ))}
        </select>
        <select
          className="sm:max-w-[170px] rounded-md border border-border bg-background px-3 py-2 text-sm"
          value={providerFilter}
          onChange={(e) => { setProviderFilter(e.target.value); setPage(1); }}
        >
          <option value="all">{t("filter_provider_all")}</option>
          <option value="paymob">{t("provider_paymob")}</option>
          <option value="xpay">{t("provider_xpay")}</option>
          <option value="manual">{t("provider_manual")}</option>
        </select>
        <select
          className="sm:max-w-[190px] rounded-md border border-border bg-background px-3 py-2 text-sm"
          value={settlementFilter}
          onChange={(e) => { setSettlementFilter(e.target.value); setPage(1); }}
        >
          <option value="all">{t("filter_settlement_all")}</option>
          <option value="unsettled">{t("filter_settlement_unsettled")}</option>
          {(["settled", "partially_settled", "pending", "failed", "disputed", "unknown"] as const).map((s) => (
            <option key={s} value={s}>{t(`settlement_${s}`)}</option>
          ))}
        </select>
        <label className="flex items-center gap-2 text-sm cursor-pointer self-center">
          <input type="checkbox" checked={reviewOnly}
            onChange={(e) => { setReviewOnly(e.target.checked); setPage(1); }}
            className="h-4 w-4 accent-emerald-600" />
          <span>{t("filter_needs_review")}</span>
        </label>
        <span className="text-sm text-muted-foreground self-center ms-auto">{fmtNumber(total)}</span>
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {loading ? (
            <div className="py-10 text-center text-muted-foreground">…</div>
          ) : rows.length === 0 ? (
            <div className="py-10 text-center text-muted-foreground">{t("no_payments")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("col_number")}</TableHead>
                  <TableHead>{t("col_company")}</TableHead>
                  <TableHead>{t("col_plan")}</TableHead>
                  <TableHead>{t("col_amount")}</TableHead>
                  <TableHead>{t("col_provider")}</TableHead>
                  <TableHead>{t("col_status")}</TableHead>
                  <TableHead>{t("col_settlement")}</TableHead>
                  <TableHead>{t("col_date")}</TableHead>
                  <TableHead className="text-end">{t("col_actions")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((row) => (
                  <TableRow key={row.id} className={row.needs_review ? "bg-destructive/5" : undefined}>
                    <td className="px-4 py-3 text-sm" dir="ltr">{row.number || "—"}</td>
                    <td className="px-4 py-3 text-sm">
                      <div className="font-medium">{row.company.name}</div>
                      <div className="text-xs text-muted-foreground" dir="ltr">{row.company.email}</div>
                    </td>
                    <td className="px-4 py-3 text-sm">
                      {row.plan.name_ar || row.plan.name}
                      <div className="text-xs text-muted-foreground">{t(`interval_${row.billing_interval}`)}</div>
                    </td>
                    <td className="px-4 py-3 text-sm font-semibold">{egp(row.amount_piastres, row.currency)}</td>
                    <td className="px-4 py-3 text-sm">{t(`provider_${row.provider}`)}</td>
                    <td className="px-4 py-3 text-sm">
                      <div className="flex flex-col gap-1 items-start">
                        <Badge variant={statusVariant[row.status]}>{t(`status_${row.status}`)}</Badge>
                        {row.needs_review && (
                          <Badge variant="destructive" className="gap-1">
                            <ShieldAlert className="h-3 w-3" /> {t("needs_review")}
                          </Badge>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-sm">
                      <Badge variant={settlementVariant[row.settlement_status ?? "missing"] ?? "secondary"}>
                        {t(`settlement_${row.settlement_status ?? "missing"}`)}
                      </Badge>
                    </td>
                    <td className="px-4 py-3 text-sm">{fmtDate(row.created_at, { dateStyle: "medium" })}</td>
                    <td className="px-4 py-3 text-sm">
                      <div className="flex items-center justify-end gap-1">
                        {row.provider === "xpay" && row.provider_reference && (
                          <Button variant="ghost" size="icon" title={t("resync")}
                            onClick={() => void doResync(row.id)}>
                            <RefreshCw className="h-4 w-4" />
                          </Button>
                        )}
                        {row.provider !== "manual" && row.status === "succeeded" && (
                          <Button variant="ghost" size="icon" title={t("settle")}
                            onClick={() => void openDetail(row)}>
                            <Landmark className="h-4 w-4" />
                          </Button>
                        )}
                        {row.status === "succeeded" && (
                          <Button variant="ghost" size="icon" className="text-destructive" title={t("refund")}
                            onClick={() => { setRefundRow(row); setRefundNote(""); setRefundShorten(false); }}>
                            <Undo2 className="h-4 w-4" />
                          </Button>
                        )}
                        <Button variant="ghost" size="icon" title={t("details")}
                          onClick={() => void openDetail(row)}>
                          <Eye className="h-4 w-4" />
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

      {total > 50 && (
        <div className="flex items-center justify-end gap-2">
          <Button variant="outline" disabled={page <= 1} onClick={() => setPage(page - 1)}>‹</Button>
          <span className="text-sm text-muted-foreground">{fmtNumber(page)}</span>
          <Button variant="outline" disabled={page * 50 >= total} onClick={() => setPage(page + 1)}>›</Button>
        </div>
      )}

      {/* Refund */}
      <Modal isOpen={!!refundRow} onClose={() => setRefundRow(null)}>
        <div className="w-[420px] max-w-[92vw] space-y-4 text-start">
          <h2 className="text-lg font-bold">{t("refund_title")}</h2>
          {refundRow && (
            <div className="rounded-md border border-border px-3 py-2 text-sm space-y-0.5">
              <div className="font-medium">{refundRow.company.name}</div>
              <div>{egp(refundRow.amount_piastres, refundRow.currency)} — {refundRow.plan.name_ar || refundRow.plan.name}</div>
            </div>
          )}
          <label className="block text-sm space-y-1">
            <span className="text-muted-foreground">{t("refund_note")}</span>
            <Input value={refundNote} onChange={(e) => setRefundNote(e.target.value)} />
          </label>
          <label className="flex items-center gap-2 text-sm cursor-pointer">
            <input
              type="checkbox"
              checked={refundShorten}
              onChange={(e) => setRefundShorten(e.target.checked)}
              className="h-4 w-4 accent-emerald-600"
            />
            <span>{t("refund_shorten")}</span>
          </label>
          <p className="text-xs text-muted-foreground">{t("refund_warning")}</p>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setRefundRow(null)}>{t("cancel")}</Button>
            <Button variant="destructive" disabled={busy} onClick={() => void doRefund()}>{busy ? "…" : t("refund_confirm")}</Button>
          </div>
        </div>
      </Modal>

      {/* Payment detail + settlement + timeline */}
      <Modal isOpen={!!detail} onClose={() => setDetail(null)}>
        {detail && (
          <div className="w-[640px] max-w-[94vw] max-h-[86vh] overflow-y-auto space-y-4 text-start">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-lg font-bold" dir="ltr">{detail.number || detail.id}</h2>
                <p className="text-sm text-muted-foreground">{detail.company.name} — {detail.plan.name_ar || detail.plan.name}</p>
              </div>
              <div className="flex gap-1">
                <Badge variant={statusVariant[detail.status]}>{t(`status_${detail.status}`)}</Badge>
                {detail.needs_review && <Badge variant="destructive">{t("needs_review")}</Badge>}
              </div>
            </div>

            <div className="rounded-md border border-border p-3 text-sm grid grid-cols-2 gap-2">
              <div>{t("col_amount")}: <b>{egp(detail.amount_piastres, detail.currency)}</b></div>
              <div>{t("col_provider")}: <b>{t(`provider_${detail.provider}`)}</b></div>
              <div>{t("detail_confirmed")}: <b>{detail.confirmed_at ? `${fmtDateTime(detail.confirmed_at)} (${t(`source_${detail.confirmation_source || "manual"}`)})` : "—"}</b></div>
              <div>{t("detail_created")}: <b>{fmtDateTime(detail.created_at)}</b></div>
              {detail.failure_message && (
                <div className="col-span-2 text-destructive">{t("detail_failure")}: {detail.failure_message}</div>
              )}
              {detail.review_reason && (
                <div className="col-span-2 text-destructive">{t("detail_review_reason")}: {detail.review_reason}</div>
              )}
              <div className="col-span-2" dir="ltr">
                <span className="text-muted-foreground">{t("detail_session")}: </span>
                <code className="text-xs">{detail.provider_reference || "—"}</code>
              </div>
            </div>

            {detail.provider !== "manual" && detail.status === "succeeded" && (
              <div className="rounded-md border border-border p-3 space-y-3">
                <h3 className="font-semibold text-sm">{t("settlement_title")}</h3>
                <div className="text-sm flex gap-2 items-center">
                  <Badge variant={settlementVariant[detail.settlement?.status ?? "missing"] ?? "secondary"}>
                    {t(`settlement_${detail.settlement?.status ?? "missing"}`)}
                  </Badge>
                  {detail.settlement?.reference && (
                    <span className="text-xs text-muted-foreground" dir="ltr">{detail.settlement.reference}</span>
                  )}
                  {detail.settlement?.settled_at && (
                    <span className="text-xs text-muted-foreground">{fmtDateTime(detail.settlement.settled_at)}</span>
                  )}
                </div>
                <p className="text-xs text-muted-foreground">{t("settlement_hint")}</p>
                <div className="grid grid-cols-2 gap-2">
                  <label className="block text-sm space-y-1">
                    <span className="text-muted-foreground">{t("settlement_status")}</span>
                    <select className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                      value={settleStatus}
                      onChange={(e) => setSettleStatus(e.target.value as PaymentSettlementStatus)}>
                      {SETTLEMENT_TARGETS.map((s) => (
                        <option key={s} value={s}>{t(`settlement_${s}`)}</option>
                      ))}
                    </select>
                  </label>
                  <label className="block text-sm space-y-1">
                    <span className="text-muted-foreground">{t("settlement_reference")}</span>
                    <Input dir="ltr" value={settleRef} onChange={(e) => setSettleRef(e.target.value)} />
                  </label>
                  <label className="block text-sm space-y-1">
                    <span className="text-muted-foreground">{t("settlement_fees")}</span>
                    <Input dir="ltr" inputMode="decimal" value={settleFees} onChange={(e) => setSettleFees(e.target.value)} />
                  </label>
                  <label className="block text-sm space-y-1">
                    <span className="text-muted-foreground">{t("settlement_note")}</span>
                    <Input value={settleNote} onChange={(e) => setSettleNote(e.target.value)} />
                  </label>
                </div>
                <div className="flex justify-end gap-2">
                  {detail.provider === "xpay" && detail.provider_reference && (
                    <Button variant="outline" disabled={detailBusy} onClick={() => void doResync(detail.id)}>
                      <RefreshCw className="h-4 w-4 me-1" /> {t("resync")}
                    </Button>
                  )}
                  <Button disabled={detailBusy || !settleNote.trim()} onClick={() => void doSettle()}>
                    {detailBusy ? "…" : t("settlement_save")}
                  </Button>
                </div>
              </div>
            )}

            {detail.provider === "xpay" && detail.provider_reference && detail.status !== "succeeded" && (
              <div className="flex justify-end">
                <Button variant="outline" disabled={detailBusy} onClick={() => void doResync(detail.id)}>
                  <RefreshCw className="h-4 w-4 me-1" /> {t("resync")}
                </Button>
              </div>
            )}

            <div className="space-y-2">
              <h3 className="font-semibold text-sm">{t("timeline_title")}</h3>
              <div className="space-y-1.5">
                {detail.timeline.map((e, i) => (
                  <div key={i} className="rounded-md border border-border px-3 py-2 text-sm flex items-center gap-2 flex-wrap">
                    <Badge variant={e.hmac_verified ? "success" : "secondary"}>
                      {t(`txn_${e.txn_type}`)}
                    </Badge>
                    <span className="text-xs text-muted-foreground">{fmtDateTime(e.created_at)}</span>
                    {e.amount_piastres > 0 && (
                      <span className="text-xs">{egp(e.amount_piastres, detail.currency)}</span>
                    )}
                    {e.provider_transaction_id && (
                      <code className="text-xs text-muted-foreground" dir="ltr">{e.provider_transaction_id}</code>
                    )}
                    {(e.payload as { note?: string })?.note && (
                      <span className="text-xs text-muted-foreground">— {(e.payload as { note?: string }).note}</span>
                    )}
                  </div>
                ))}
                {detail.timeline.length === 0 && (
                  <div className="text-sm text-muted-foreground">{t("timeline_empty")}</div>
                )}
              </div>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}
