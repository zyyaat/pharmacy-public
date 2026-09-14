"use client";

// Per-company subscription history — the operator clicks «السجل» on any
// company row (or its versions badge) and lands on THIS page, where the
// company's full version ledger lives alone. The old global history
// toggle mixed every company's rows into one list and became unreadable
// the moment more than one company had versions — the dedicated page
// keeps the effective list clean and the history one company per view.

import React, { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { History, ArrowRight, ArrowLeft } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, Button, Badge } from "@/components/ui";
import { Table, TableHeader, TableBody, TableRow, TableHead } from "@/components/ui/table";
import {
  subscriptionsApi,
  type SubscriptionRow,
} from "@/lib/api";
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

const isLive = (status: SubscriptionRow["status"]) =>
  status === "pending" || status === "trial" || status === "active";

export default function CompanySubscriptionHistoryPage() {
  const t = useT("subscriptions");
  const router = useRouter();
  const [companyId, setCompanyId] = useState<string | null>(null);
  const [rows, setRows] = useState<SubscriptionRow[]>([]);
  const [loading, setLoading] = useState(true);

  // Read the ?company= param on mount — window.location avoids the
  // Suspense boundary that useSearchParams requires at build time.
  useEffect(() => {
    const id = new URLSearchParams(window.location.search).get("company");
    setCompanyId(id && id.trim() ? id.trim() : null);
  }, []);

  const reload = useCallback(async () => {
    if (!companyId) { setLoading(false); return; }
    setLoading(true);
    try {
      const res = await subscriptionsApi.list({
        history: true,
        company_id: companyId,
        pageSize: 200,
      });
      setRows(res.data);
    } catch {
      toast.error(t("load_failed"));
    } finally {
      setLoading(false);
    }
  }, [companyId, t]);

  useEffect(() => { void reload(); }, [reload]);

  const periodLabel = (row: SubscriptionRow) => {
    if (row.status === "trial" && row.trial_ends_at) return fmtDate(row.trial_ends_at, { dateStyle: "medium" });
    if (row.current_period_end) return fmtDate(row.current_period_end, { dateStyle: "medium" });
    return t("no_period");
  };

  const company = rows[0]?.company;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <History className="h-6 w-6" />
            {t("history_page_title")}
          </h1>
          <p className="text-muted-foreground mt-1">
            {company
              ? `${company.name} · ${company.email}`
              : t("history_page_subtitle")}
          </p>
        </div>
        <Button variant="outline" onClick={() => router.push("/subscriptions")}>
          {typeof document !== "undefined" && document.documentElement.dir === "rtl"
            ? <ArrowRight className="h-4 w-4 me-2" />
            : <ArrowLeft className="h-4 w-4 me-2" />}
          {t("history_back")}
        </Button>
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {loading ? (
            <div className="py-10 text-center text-muted-foreground">…</div>
          ) : !companyId ? (
            <div className="py-10 text-center text-muted-foreground">{t("history_no_company")}</div>
          ) : rows.length === 0 ? (
            <div className="py-10 text-center text-muted-foreground">{t("no_subscriptions")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("col_plan")}</TableHead>
                  <TableHead>{t("col_status")}</TableHead>
                  <TableHead>{t("col_period_end")}</TableHead>
                  <TableHead>{t("col_source")}</TableHead>
                  <TableHead>{t("col_created")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((row) => (
                  <TableRow key={row.id} className={isLive(row.status) ? "bg-emerald-500/5" : undefined}>
                    <td className="px-4 py-3 text-sm font-medium">{row.plan.name_ar || row.plan.name}</td>
                    <td className="px-4 py-3 text-sm">
                      <div className="flex items-center gap-2">
                        <Badge variant={statusVariant[row.status]}>{t(`status_${row.status}`)}</Badge>
                        {isLive(row.status) && <Badge variant="outline">{t("history_governing")}</Badge>}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-sm">{periodLabel(row)}</td>
                    <td className="px-4 py-3 text-sm text-muted-foreground">{t(`source_${row.source}`)}</td>
                    <td className="px-4 py-3 text-sm text-muted-foreground">
                      {fmtDate(row.created_at, { dateStyle: "medium" })}
                    </td>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
