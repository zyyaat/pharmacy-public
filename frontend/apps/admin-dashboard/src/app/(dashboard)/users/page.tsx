"use client";

import { useEffect, useState } from "react";
import { Search, ShieldCheck, Users as UsersIcon } from "lucide-react";
import { Badge, Card, CardContent, CardHeader, CardTitle, Select } from "@/components/ui";
import { roleLabel } from "@/lib/utils";
import { usersApi } from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtDate } from "@/i18n/format";
import type { PlatformUser } from "@/types";

const roleVariants: Record<string, "default" | "secondary" | "outline" | "destructive" | "success" | "warning"> = {
  super_admin: "destructive",
  company_admin: "default",
  company_manager: "secondary",
  company_viewer: "outline",
  employee: "secondary",
};

export default function UsersPage() {
  const t = useT("users");
  const [users, setUsers] = useState<PlatformUser[]>([]);
  const [search, setSearch] = useState("");
  const [role, setRole] = useState("all");
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    usersApi.listPlatform({ page: 1, limit: 100, search: search || undefined, role: role === "all" ? undefined : role })
      .then((response) => {
        if (cancelled) return;
        setUsers(response.data);
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
  }, [search, role, t]);

  const activeCount = users.filter((user) => user.isActive).length;
  const adminCount = users.filter((user) => user.role === "super_admin").length;

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-bold">{t("title")}</h1>
        <p className="mt-1 text-muted-foreground">{t("subtitle")}</p>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <Metric icon={<UsersIcon className="h-5 w-5 text-primary" />} value={total} label={t("metric_total")} />
        <Metric icon={<ShieldCheck className="h-5 w-5 text-emerald-600" />} value={activeCount} label={t("metric_active")} />
        <Metric icon={<ShieldCheck className="h-5 w-5 text-amber-600" />} value={adminCount} label={t("metric_admins")} />
      </div>

      <Card>
        <CardHeader><CardTitle>{t("guide_title")}</CardTitle></CardHeader>
        <CardContent>
          <div className="mb-5 flex flex-col gap-3 sm:flex-row">
            <div className="relative flex-1">
              <Search className="absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder={t("search_placeholder")} className="h-10 w-full rounded-lg border border-input bg-background ps-10 pe-4 text-sm focus:outline-none focus:ring-2 focus:ring-ring" />
            </div>
            <div className="w-[190px]">
              <Select
                value={role}
                onValueChange={(value) => setRole(value)}
                aria-label={t("filter_role_aria")}
                options={[
                  { value: "all", label: t("role_all") },
                  { value: "super_admin", label: t("roles.super_admin") },
                  { value: "company_admin", label: t("roles.company_admin") },
                  { value: "company_manager", label: t("roles.company_manager") },
                  { value: "company_viewer", label: t("roles.company_viewer") },
                  { value: "employee", label: t("account_pharmacy_employee") },
                ]}
              />
            </div>
          </div>
          {loading && <p className="py-8 text-center text-muted-foreground">{t("loading")}</p>}
          {error && !loading && <p className="py-8 text-center text-destructive">{error}</p>}
          {!loading && !error && users.length === 0 && <p className="py-8 text-center text-muted-foreground">{t("no_matches")}</p>}
          <div className="space-y-3">
            {users.map((user) => (
              <div key={`${user.accountType}-${user.id}`} className={`flex flex-col gap-4 rounded-xl border border-border p-4 transition hover:shadow-sm sm:flex-row sm:items-center ${!user.isActive ? "opacity-60" : ""}`}>
                <div className="flex min-w-0 flex-1 items-center gap-3">
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary/10 font-semibold text-primary">{user.displayName.charAt(0)}</div>
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2"><p className="font-medium">{user.displayName}</p>{!user.isActive && <Badge variant="destructive">{t("badge_disabled")}</Badge>}</div>
                    <p className="truncate text-sm text-muted-foreground" dir="ltr">{user.email}</p>
                    <p className="mt-1 text-xs text-muted-foreground">{user.companyName} · {user.accountType === "company_user" ? t("account_company_user") : t("account_pharmacy_employee")}</p>
                  </div>
                </div>
                <div className="flex items-center gap-4 sm:justify-end">
                  <div className="text-center"><Badge variant={roleVariants[user.role] || "outline"}>{roleLabel(user.role)}</Badge><p className="mt-1 text-xs text-muted-foreground">{t("permissions_count", { count: user.permissionsCount })}</p></div>
                  <p className="hidden text-xs text-muted-foreground lg:block">{user.lastLoginAt ? t("last_login", { date: fmtDate(user.lastLoginAt) }) : t("never_logged_in")}</p>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

function Metric({ icon, value, label }: { icon: React.ReactNode; value: number; label: string }) {
  return <Card><CardContent className="flex items-center gap-4 p-5"><div className="rounded-xl bg-primary/10 p-3">{icon}</div><div><p className="text-2xl font-bold">{value}</p><p className="text-sm text-muted-foreground">{label}</p></div></CardContent></Card>;
}
