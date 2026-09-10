"use client";

import React, { useEffect, useMemo, useState } from "react";
import {
  Search,
  Plus,
  Eye,
  Edit,
  Trash2,
  ChevronLeft,
  ChevronRight,
  Building2,
  Users,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { Button } from "@/components/ui";
import { Input } from "@/components/ui";
import { Badge } from "@/components/ui";
import { Select } from "@/components/ui";
import { companyStatusLabel, companyPlanLabel, type CompanyStatus, type CompanyPlan } from "@/lib/utils";
import { companiesApi } from "@/lib/api";
import { useT } from "@/i18n/provider";
import { fmtDate } from "@/i18n/format";

type CompanyRow = {
  id: string;
  name: string;
  nameEn?: string;
  status: CompanyStatus;
  plan: CompanyPlan;
  maxUsers: number;
  currentUsersCount: number;
  createdAt: string;
  email: string;
  phone?: string;
};

const statusVariants: Record<CompanyStatus, "default" | "secondary" | "destructive" | "success" | "warning" | "outline"> = {
  active: "success",
  suspended: "destructive",
  trial: "warning",
  cancelled: "secondary",
};

const planBadgeVariants: Record<CompanyPlan, "default" | "secondary" | "outline"> = {
  free: "secondary",
  starter: "outline",
  professional: "default",
  enterprise: "default",
  custom: "secondary",
};

export default function CompaniesPage() {
  const t = useT("companies");
  const [companies, setCompanies] = useState<CompanyRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [selectedCompanies, setSelectedCompanies] = useState<string[]>([]);
  const [summary, setSummary] = useState({ total: 0, active: 0, trial: 0, suspended: 0 });

  useEffect(() => {
    let cancelled = false;
    companiesApi.list({
      page: 1,
      limit: 100,
      search: searchQuery || undefined,
      status: statusFilter === "all" ? undefined : statusFilter,
    })
      .then((response) => {
        if (cancelled) return;
        setCompanies(response.data.map((company) => ({
          id: company.id,
          name: company.name,
          nameEn: company.nameEn,
          status: company.status,
          plan: company.plan,
          maxUsers: company.maxUsers,
          currentUsersCount: company.currentUsersCount,
          createdAt: company.createdAt,
          email: company.email || "",
          phone: company.phone,
        })));
        setSummary(response.summary);
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : t("load_failed"));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => { cancelled = true; };
  }, [searchQuery, statusFilter, t]);

  const filteredCompanies = useMemo(() => companies.filter((company) => {
    const matchesSearch =
      company.name.includes(searchQuery) ||
      company.nameEn?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      company.email.includes(searchQuery);

    const matchesStatus = statusFilter === "all" || company.status === statusFilter;

    return matchesSearch && matchesStatus;
  }), [companies, searchQuery, statusFilter]);

  const toggleSelectAll = () => {
    if (selectedCompanies.length === filteredCompanies.length) {
      setSelectedCompanies([]);
    } else {
      setSelectedCompanies(filteredCompanies.map((c) => c.id));
    }
  };

  const toggleSelect = (id: string) => {
    setSelectedCompanies((prev) =>
      prev.includes(id) ? prev.filter((i) => i !== id) : [...prev, id]
    );
  };

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">{t("title")}</h1>
          <p className="text-muted-foreground mt-1">
            {t("subtitle")}
          </p>
        </div>
        <Button variant="gradient">
          <Plus className="h-4 w-4 me-2" />
          {t("add_company")}
        </Button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-primary/10 text-primary">
              <Building2 className="h-5 w-5" />
            </div>
            <div>
               <p className="text-2xl font-bold">{summary.total}</p>
              <p className="text-sm text-muted-foreground">{t("stat_total")}</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-emerald-500/10 text-emerald-600 dark:text-emerald-400">
              <Building2 className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                 {summary.active}
              </p>
              <p className="text-sm text-muted-foreground">{t("stat_active")}</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-amber-500/10 text-amber-600 dark:text-amber-400">
              <Building2 className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                 {summary.trial}
              </p>
              <p className="text-sm text-muted-foreground">{t("stat_trial")}</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-red-500/10 text-red-600 dark:text-red-400">
              <Building2 className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                 {summary.suspended}
              </p>
              <p className="text-sm text-muted-foreground">{t("stat_suspended")}</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filters */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-col sm:flex-row gap-4">
            <div className="flex-1 relative">
              <Search className="absolute start-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <input
                type="search"
                placeholder={t("search_placeholder")}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full h-10 ps-10 pe-4 rounded-lg border border-input bg-background text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring transition-all"
                dir="ltr"
              />
            </div>
            <div className="w-[160px]">
              <Select
                value={statusFilter}
                onValueChange={(value) => setStatusFilter(value)}
                aria-label={t("filter_status_aria")}
                options={[
                  { value: "all", label: t("filter_all") },
                  { value: "active", label: t("status.active") },
                  { value: "trial", label: t("status.trial") },
                  { value: "suspended", label: t("status.suspended") },
                  { value: "cancelled", label: t("status.cancelled") },
                ]}
              />
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Companies Table */}
      <Card>
        <CardContent className="p-0">
          {loading && <div className="p-12 text-center text-muted-foreground">{t("loading")}</div>}
          {error && !loading && <div className="p-12 text-center text-destructive">{error}</div>}
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border bg-muted/30">
                  <th className="p-4 text-start">
                    <input
                      type="checkbox"
                      checked={selectedCompanies.length === filteredCompanies.length && filteredCompanies.length > 0}
                      onChange={toggleSelectAll}
                      className="rounded border-border"
                    />
                  </th>
                  <th className="p-4 text-start text-sm font-medium text-muted-foreground">{t("th_company")}</th>
                  <th className="p-4 text-start text-sm font-medium text-muted-foreground hidden md:table-cell">{t("th_status")}</th>
                  <th className="p-4 text-start text-sm font-medium text-muted-foreground hidden lg:table-cell">{t("th_plan")}</th>
                  <th className="p-4 text-start text-sm font-medium text-muted-foreground hidden lg:table-cell">{t("th_users")}</th>
                  <th className="p-4 text-start text-sm font-medium text-muted-foreground hidden xl:table-cell">{t("th_registered")}</th>
                  <th className="p-4 text-start text-sm font-medium text-muted-foreground">{t("th_actions")}</th>
                </tr>
              </thead>
              <tbody>
                {filteredCompanies.map((company) => (
                  <tr
                    key={company.id}
                    className={`border-b border-border hover:bg-accent/30 transition-colors ${
                      selectedCompanies.includes(company.id) ? "bg-primary/5" : ""
                    }`}
                  >
                    <td className="p-4">
                      <input
                        type="checkbox"
                        checked={selectedCompanies.includes(company.id)}
                        onChange={() => toggleSelect(company.id)}
                        className="rounded border-border"
                      />
                    </td>
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center text-primary font-bold shrink-0">
                          {company.name.charAt(0)}
                        </div>
                        <div>
                          <p className="font-medium">{company.name}</p>
                          {company.nameEn && (
                            <p className="text-xs text-muted-foreground">{company.nameEn}</p>
                          )}
                          <p className="text-xs text-muted-foreground mt-0.5">{company.email}</p>
                        </div>
                      </div>
                    </td>
                    <td className="p-4 hidden md:table-cell">
                      <Badge variant={statusVariants[company.status]}>
                        {companyStatusLabel(company.status)}
                      </Badge>
                    </td>
                    <td className="p-4 hidden lg:table-cell">
                      <Badge variant={planBadgeVariants[company.plan]}>
                        {companyPlanLabel(company.plan)}
                      </Badge>
                    </td>
                    <td className="p-4 hidden lg:table-cell">
                      <div className="flex items-center gap-2">
                        <Users className="h-4 w-4 text-muted-foreground" />
                        <span>{company.currentUsersCount}/{company.maxUsers}</span>
                        <div className="w-16 h-1.5 bg-muted rounded-full overflow-hidden">
                          <div
                            className="h-full bg-primary rounded-full"
                            style={{
                              width: `${(company.currentUsersCount / company.maxUsers) * 100}%`,
                            }}
                          />
                        </div>
                      </div>
                    </td>
                    <td className="p-4 hidden xl:table-cell text-sm text-muted-foreground">
                      {fmtDate(company.createdAt)}
                    </td>
                    <td className="p-4">
                      <div className="flex items-center gap-1">
                        <Button variant="ghost" size="icon" title={t("action_view")}>
                          <Eye className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" title={t("action_edit")}>
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" title={t("action_delete")} className="text-destructive hover:text-destructive">
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Empty State */}
          {!loading && !error && filteredCompanies.length === 0 && (
            <div className="text-center py-12">
              <Building2 className="h-12 w-12 mx-auto text-muted-foreground mb-4" />
              <h3 className="text-lg font-medium mb-2">{t("empty_title")}</h3>
              <p className="text-muted-foreground mb-4">
                {t("empty_desc")}
              </p>
              <Button variant="outline" onClick={() => { setSearchQuery(""); setStatusFilter("all"); }}>
                {t("clear_filters")}
              </Button>
            </div>
          )}

          {/* Pagination */}
           {!loading && !error && filteredCompanies.length > 0 && (
            <div className="flex items-center justify-between p-4 border-t border-border">
             <p className="text-sm text-muted-foreground">
             {t("pagination", { shown: filteredCompanies.length, total: summary.total })}
              </p>
              <div className="flex items-center gap-2">
                <Button variant="outline" size="icon" disabled>
                  <ChevronRight className="h-4 w-4 rtl-flip" />
                </Button>
                <span className="px-3 py-1 rounded-md bg-primary text-primary-foreground text-sm">
                  1
                </span>
                <Button variant="outline" size="icon" disabled>
                  <ChevronLeft className="h-4 w-4 rtl-flip" />
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

// RTL arrows fix - using CSS transform for proper RTL support
// ChevronLeft/ChevronRight are imported from lucide-react and will be flipped via CSS
