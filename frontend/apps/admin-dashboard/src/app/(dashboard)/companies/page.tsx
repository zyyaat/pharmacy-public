"use client";

import React, { useEffect, useMemo, useState } from "react";
import {
  Search,
  Plus,
  Filter,
  MoreHorizontal,
  Eye,
  Edit,
  Trash2,
  ChevronLeft,
  ChevronRight,
  Building2,
  Users,
  Mail,
  Phone,
  Calendar,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { Button } from "@/components/ui";
import { Input } from "@/components/ui";
import { Badge } from "@/components/ui";
import { COMPANY_STATUS_LABELS, COMPANY_PLAN_LABELS, type CompanyStatus, type CompanyPlan } from "@/lib/utils";
import { companiesApi } from "@/lib/api";

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
  const [companies, setCompanies] = useState<CompanyRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [selectedCompanies, setSelectedCompanies] = useState<string[]>([]);

  useEffect(() => {
    let cancelled = false;
    companiesApi.list({ page: 1, limit: 100 })
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
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "تعذر تحميل الشركات");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => { cancelled = true; };
  }, []);

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
          <h1 className="text-2xl font-bold">إدارة الشركات</h1>
          <p className="text-muted-foreground mt-1">
            إدارة جميع الشركات المسجلة في المنصة
          </p>
        </div>
        <Button variant="gradient">
          <Plus className="h-4 w-4 ml-2" />
          إضافة شركة جديدة
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
               <p className="text-2xl font-bold">{companies.length}</p>
              <p className="text-sm text-muted-foreground">إجمالي الشركات</p>
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
                 {companies.filter((c) => c.status === "active").length}
              </p>
              <p className="text-sm text-muted-foreground">شركات نشطة</p>
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
                 {companies.filter((c) => c.status === "trial").length}
              </p>
              <p className="text-sm text-muted-foreground">في الفترة التجريبية</p>
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
                 {companies.filter((c) => c.status === "suspended").length}
              </p>
              <p className="text-sm text-muted-foreground">شركات موقوفة</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filters */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-col sm:flex-row gap-4">
            <div className="flex-1 relative">
              <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <input
                type="search"
                placeholder="بحث بالاسم أو البريد الإلكتروني..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full h-10 pl-4 pr-10 rounded-lg border border-input bg-background text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring transition-all"
                dir="ltr"
              />
            </div>
            <div className="flex gap-2">
              <select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="h-10 px-4 rounded-lg border border-input bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              >
                <option value="all">كل الحالات</option>
                <option value="active">نشط</option>
                <option value="trial">تجريبي</option>
                <option value="suspended">موقوف</option>
                <option value="cancelled">ملغي</option>
              </select>
              <Button variant="outline" size="icon">
                <Filter className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Companies Table */}
      <Card>
        <CardContent className="p-0">
          {loading && <div className="p-12 text-center text-muted-foreground">جاري تحميل الشركات...</div>}
          {error && !loading && <div className="p-12 text-center text-destructive">{error}</div>}
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border bg-muted/30">
                  <th className="p-4 text-right">
                    <input
                      type="checkbox"
                      checked={selectedCompanies.length === filteredCompanies.length && filteredCompanies.length > 0}
                      onChange={toggleSelectAll}
                      className="rounded border-border"
                    />
                  </th>
                  <th className="p-4 text-right text-sm font-medium text-muted-foreground">الشركة</th>
                  <th className="p-4 text-right text-sm font-medium text-muted-foreground hidden md:table-cell">الحالة</th>
                  <th className="p-4 text-right text-sm font-medium text-muted-foreground hidden lg:table-cell">الخطة</th>
                  <th className="p-4 text-right text-sm font-medium text-muted-foreground hidden lg:table-cell">المستخدمين</th>
                  <th className="p-4 text-right text-sm font-medium text-muted-foreground hidden xl:table-cell">تاريخ التسجيل</th>
                  <th className="p-4 text-right text-sm font-medium text-muted-foreground">إجراءات</th>
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
                        {COMPANY_STATUS_LABELS[company.status]}
                      </Badge>
                    </td>
                    <td className="p-4 hidden lg:table-cell">
                      <Badge variant={planBadgeVariants[company.plan]}>
                        {COMPANY_PLAN_LABELS[company.plan]}
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
                      {new Date(company.createdAt).toLocaleDateString("ar-EG")}
                    </td>
                    <td className="p-4">
                      <div className="flex items-center gap-1">
                        <Button variant="ghost" size="icon" title="عرض">
                          <Eye className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" title="تعديل">
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" title="حذف" className="text-destructive hover:text-destructive">
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
              <h3 className="text-lg font-medium mb-2">لا توجد شركات</h3>
              <p className="text-muted-foreground mb-4">
                لم يتم العثور على شركات تطابق معايير البحث
              </p>
              <Button variant="outline" onClick={() => { setSearchQuery(""); setStatusFilter("all"); }}>
                مسح الفلاتر
              </Button>
            </div>
          )}

          {/* Pagination */}
           {!loading && !error && filteredCompanies.length > 0 && (
            <div className="flex items-center justify-between p-4 border-t border-border">
              <p className="text-sm text-muted-foreground">
                 عرض {filteredCompanies.length} من {companies.length} شركة
              </p>
              <div className="flex items-center gap-2">
                <Button variant="outline" size="icon" disabled>
                  <ChevronRight className="h-4 w-4" />
                </Button>
                <span className="px-3 py-1 rounded-md bg-primary text-primary-foreground text-sm">
                  1
                </span>
                <Button variant="outline" size="icon" disabled>
                  <ChevronLeft className="h-4 w-4" />
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
