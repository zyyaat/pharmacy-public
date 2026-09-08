"use client";

import { useEffect, useState } from "react";
import { Search, ShieldCheck, Users as UsersIcon } from "lucide-react";
import { Badge, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { ROLE_LABELS, type Role } from "@/lib/utils";
import { usersApi } from "@/lib/api";
import type { PlatformUser } from "@/types";

const roleVariants: Record<string, "default" | "secondary" | "outline" | "destructive" | "success" | "warning"> = {
  super_admin: "destructive",
  company_admin: "default",
  company_manager: "secondary",
  company_viewer: "outline",
  employee: "secondary",
};

export default function UsersPage() {
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
        if (!cancelled) setError(reason instanceof Error ? reason.message : "تعذر تحميل المستخدمين");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => { cancelled = true; };
  }, [search, role]);

  const activeCount = users.filter((user) => user.isActive).length;
  const adminCount = users.filter((user) => user.role === "super_admin").length;

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-bold">مستخدمو المنصة</h1>
        <p className="mt-1 text-muted-foreground">كل مستخدمي الشركات وموظفي الصيدليات مع مصدر الحساب والدور الفعلي</p>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <Metric icon={<UsersIcon className="h-5 w-5 text-primary" />} value={total} label="إجمالي المستخدمين" />
        <Metric icon={<ShieldCheck className="h-5 w-5 text-emerald-600" />} value={activeCount} label="نشطون في النتائج" />
        <Metric icon={<ShieldCheck className="h-5 w-5 text-amber-600" />} value={adminCount} label="مديرو النظام في النتائج" />
      </div>

      <Card>
        <CardHeader><CardTitle>دليل المستخدمين</CardTitle></CardHeader>
        <CardContent>
          <div className="mb-5 flex flex-col gap-3 sm:flex-row">
            <div className="relative flex-1">
              <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="ابحث بالاسم أو البريد أو الشركة..." className="h-10 w-full rounded-lg border border-input bg-background pl-4 pr-10 text-sm focus:outline-none focus:ring-2 focus:ring-ring" dir="rtl" />
            </div>
            <select value={role} onChange={(event) => setRole(event.target.value)} className="h-10 rounded-lg border border-input bg-background px-4 text-sm">
              <option value="all">كل الأدوار</option>
              <option value="super_admin">مدير النظام</option>
              <option value="company_admin">مدير الشركة</option>
              <option value="company_manager">مدير العمليات</option>
              <option value="company_viewer">مشاهد الشركة</option>
              <option value="employee">موظف صيدلية</option>
            </select>
          </div>
          {loading && <p className="py-8 text-center text-muted-foreground">جاري تحميل المستخدمين...</p>}
          {error && !loading && <p className="py-8 text-center text-destructive">{error}</p>}
          {!loading && !error && users.length === 0 && <p className="py-8 text-center text-muted-foreground">لا يوجد مستخدمون مطابقون</p>}
          <div className="space-y-3">
            {users.map((user) => (
              <div key={`${user.accountType}-${user.id}`} className={`flex flex-col gap-4 rounded-xl border border-border p-4 transition hover:shadow-sm sm:flex-row sm:items-center ${!user.isActive ? "opacity-60" : ""}`}>
                <div className="flex min-w-0 flex-1 items-center gap-3">
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary/10 font-semibold text-primary">{user.displayName.charAt(0)}</div>
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2"><p className="font-medium">{user.displayName}</p>{!user.isActive && <Badge variant="destructive">معطل</Badge>}</div>
                    <p className="truncate text-sm text-muted-foreground" dir="ltr">{user.email}</p>
                    <p className="mt-1 text-xs text-muted-foreground">{user.companyName} · {user.accountType === "company_user" ? "حساب شركة" : "موظف صيدلية"}</p>
                  </div>
                </div>
                <div className="flex items-center gap-4 sm:justify-end">
                  <div className="text-center"><Badge variant={roleVariants[user.role] || "outline"}>{ROLE_LABELS[user.role as Role] || user.role}</Badge><p className="mt-1 text-xs text-muted-foreground">{user.permissionsCount} صلاحية فعلية</p></div>
                  <p className="hidden text-xs text-muted-foreground lg:block">{user.lastLoginAt ? `آخر دخول: ${new Date(user.lastLoginAt).toLocaleDateString("ar-EG")}` : "لم يسجل الدخول بعد"}</p>
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