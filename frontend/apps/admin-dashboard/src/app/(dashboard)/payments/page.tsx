"use client";

// Payments ledger — every manual or Paymob payment browsable with filters
// and a one-click refund (Stripe-style: refund once, audit everything,
// optionally shorten the linked subscription by the billing interval).

import React, { useCallback, useEffect, useState } from "react";
import { Undo2 } from "lucide-react";
import { toast } from "sonner";
import {
  Card, CardContent, Button, Input, Badge,
} from "@/components/ui";
import { Table, TableHeader, TableBody, TableRow, TableHead } from "@/components/ui/table";
import { Modal } from "@/components/ui/modal";
import { paymentsApi, type PaymentRow } from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtDate, fmtNumber } from "@/i18n/format";

const statusVariant: Record<PaymentRow["status"], "success" | "warning" | "destructive" | "secondary" | "default"> = {
  pending: "warning",
  succeeded: "success",
  failed: "destructive",
  refunded: "secondary",
  voided: "secondary",
  cancelled: "secondary",
};

export default function PaymentsPage() {
  const t = useT("payments");
  const [rows, setRows] = useState<PaymentRow[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("all");
  const [providerFilter, setProviderFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);

  const [refundRow, setRefundRow] = useState<PaymentRow | null>(null);
  const [refundNote, setRefundNote] = useState("");
  const [refundShorten, setRefundShorten] = useState(false);
  const [busy, setBusy] = useState(false);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const res = await paymentsApi.list({
        status: statusFilter === "all" ? undefined : statusFilter,
        provider: providerFilter === "all" ? undefined : providerFilter,
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
  }, [statusFilter, providerFilter, search, page, t]);

  useEffect(() => { void reload(); }, [reload]);

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
    } catch {
      toast.error(t("failed"));
    } finally {
      setBusy(false);
    }
  };

  const egp = (piastres: number, currency: string) => `${fmtNumber(piastres / 100)} ${currency}`;

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-bold">{t("title")}</h1>
        <p className="text-muted-foreground mt-1">{t("subtitle")}</p>
      </div>

      <div className="flex flex-col sm:flex-row gap-3">
        <Input className="sm:max-w-xs" placeholder={t("search_placeholder")} value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} />
        <select
          className="sm:max-w-[180px] rounded-md border border-border bg-background px-3 py-2 text-sm"
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
        >
          <option value="all">{t("filter_status_all")}</option>
          {(["pending", "succeeded", "failed", "refunded"] as const).map((s) => (
            <option key={s} value={s}>{t(`status_${s}`)}</option>
          ))}
        </select>
        <select
          className="sm:max-w-[180px] rounded-md border border-border bg-background px-3 py-2 text-sm"
          value={providerFilter}
          onChange={(e) => { setProviderFilter(e.target.value); setPage(1); }}
        >
          <option value="all">{t("filter_provider_all")}</option>
          <option value="paymob">{t("provider_paymob")}</option>
          <option value="manual">{t("provider_manual")}</option>
        </select>
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
                  <TableHead>{t("col_company")}</TableHead>
                  <TableHead>{t("col_plan")}</TableHead>
                  <TableHead>{t("col_amount")}</TableHead>
                  <TableHead>{t("col_provider")}</TableHead>
                  <TableHead>{t("col_status")}</TableHead>
                  <TableHead>{t("col_date")}</TableHead>
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
                    <td className="px-4 py-3 text-sm">
                      {row.plan.name_ar || row.plan.name}
                      <div className="text-xs text-muted-foreground">{t(`interval_${row.billing_interval}`)}</div>
                    </td>
                    <td className="px-4 py-3 text-sm font-semibold">{egp(row.amount_piastres, row.currency)}</td>
                    <td className="px-4 py-3 text-sm">{t(`provider_${row.provider}`)}</td>
                    <td className="px-4 py-3 text-sm">
                      <Badge variant={statusVariant[row.status]}>{t(`status_${row.status}`)}</Badge>
                    </td>
                    <td className="px-4 py-3 text-sm">{fmtDate(row.created_at, { dateStyle: "medium" })}</td>
                    <td className="px-4 py-3 text-sm">
                      <div className="flex items-center justify-end gap-1">
                        {row.status === "succeeded" && (
                          <Button variant="ghost" size="icon" className="text-destructive" title={t("refund")}
                            onClick={() => { setRefundRow(row); setRefundNote(""); setRefundShorten(false); }}>
                            <Undo2 className="h-4 w-4" />
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
    </div>
  );
}
