"use client";

import { useEffect, useState } from "react";
import { Building2, Mail, Phone, Search, Store } from "lucide-react";
import { Badge, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { accountsApi } from "@/lib/api";
import { useT } from "@/i18n/provider";
import type { Account } from "@/types";

export default function AccountsPage() {
  const t = useT("accounts");
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [search, setSearch] = useState("");
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    accountsApi.listPlatform({ page: 1, limit: 100, search: search || undefined })
      .then((response) => {
        if (cancelled) return;
        setAccounts(response.data);
        setTotal(response.total);
        setError(null);
      })
      .catch((reason) => {
        if (!cancelled) setError(reason instanceof Error ? reason.message : t("load_failed"));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => { cancelled = true; };
  }, [search, t]);

  const statusLabels: Record<string, string> = {
    active: t("status_active"),
    suspended: t("status_suspended"),
    inactive: t("status_inactive"),
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-bold">{t("title")}</h1>
        <p className="mt-1 text-muted-foreground">{t("subtitle")}</p>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <Card><CardContent className="flex items-center gap-4 p-5"><CreditCardIcon /><div><p className="text-2xl font-bold">{total}</p><p className="text-sm text-muted-foreground">{t("stat_total")}</p></div></CardContent></Card>
        <Card><CardContent className="flex items-center gap-4 p-5"><Store className="h-5 w-5 text-emerald-600" /><div><p className="text-2xl font-bold">{accounts.reduce((sum, account) => sum + account.pharmacyCount, 0)}</p><p className="text-sm text-muted-foreground">{t("stat_pharmacies")}</p></div></CardContent></Card>
        <Card><CardContent className="flex items-center gap-4 p-5"><Building2 className="h-5 w-5 text-blue-600" /><div><p className="text-2xl font-bold">{accounts.reduce((sum, account) => sum + account.branchesCount, 0)}</p><p className="text-sm text-muted-foreground">{t("stat_branches")}</p></div></CardContent></Card>
      </div>

      <Card>
        <CardHeader><CardTitle>{t("list_title")}</CardTitle></CardHeader>
        <CardContent>
          <div className="relative mb-5">
            <Search className="absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder={t("search_placeholder")} className="h-10 w-full rounded-lg border border-input bg-background ps-10 pe-4 text-sm focus:outline-none focus:ring-2 focus:ring-ring" />
          </div>
          {loading && <p className="py-8 text-center text-muted-foreground">{t("loading")}</p>}
          {error && !loading && <p className="py-8 text-center text-destructive">{error}</p>}
          {!loading && !error && accounts.length === 0 && <p className="py-8 text-center text-muted-foreground">{t("no_accounts")}</p>}
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            {accounts.map((account) => (
              <div key={account.id} className="rounded-xl border border-border p-5 transition hover:shadow-md">
                <div className="mb-4 flex items-start justify-between gap-3">
                  <div><h3 className="font-semibold">{account.name}</h3><p className="text-sm text-muted-foreground">{account.companyName}</p></div>
                  <Badge variant={account.status === "active" ? "success" : account.status === "suspended" ? "destructive" : "secondary"}>{statusLabels[account.status] || account.status}</Badge>
                </div>
                <div className="space-y-2 text-sm text-muted-foreground">
                  <p className="flex items-center gap-2"><Store className="h-4 w-4" />{t("pharmacies_branches", { pharmacies: account.pharmacyCount, branches: account.branchesCount })}</p>
                  {account.email && <p className="flex items-center gap-2" dir="ltr"><Mail className="h-4 w-4 shrink-0" />{account.email}</p>}
                  {account.phone && <p className="flex items-center gap-2" dir="ltr"><Phone className="h-4 w-4 shrink-0" />{account.phone}</p>}
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

function CreditCardIcon() {
  return <div className="rounded-xl bg-primary/10 p-3 text-primary"><Building2 className="h-5 w-5" /></div>;
}
