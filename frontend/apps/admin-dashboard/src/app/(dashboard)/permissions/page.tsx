"use client";

import { useEffect, useMemo, useState } from "react";
import { Lock, Search, Shield, ShieldCheck, Users } from "lucide-react";
import { Badge, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { permissionsApi } from "@/lib/api";
import type { PlatformPermission, PlatformRole } from "@/types";

export default function PermissionsPage() {
  const [permissions, setPermissions] = useState<PlatformPermission[]>([]);
  const [roles, setRoles] = useState<PlatformRole[]>([]);
  const [selectedRole, setSelectedRole] = useState("");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    permissionsApi.list()
      .then((response) => {
        setPermissions(response.permissions);
        setRoles(response.roles);
        setSelectedRole(response.roles[0]?.id || "");
        setError(null);
      })
      .catch((reason) => setError(reason instanceof Error ? reason.message : "تعذر تحميل الصلاحيات"))
      .finally(() => setLoading(false));
  }, []);

  const role = roles.find((item) => item.id === selectedRole) || roles[0];
  const filteredPermissions = useMemo(() => {
    const query = search.toLowerCase();
    return permissions.filter((permission) =>
      !query || permission.key.toLowerCase().includes(query) || permission.name.toLowerCase().includes(query) || permission.module.toLowerCase().includes(query)
    );
  }, [permissions, search]);

  const groupedPermissions = filteredPermissions.reduce<Record<string, PlatformPermission[]>>((groups, permission) => {
    (groups[permission.module] ||= []).push(permission);
    return groups;
  }, {});

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-bold">الأدوار والصلاحيات</h1>
        <p className="mt-1 text-muted-foreground">بيانات الأدوار والصلاحيات الفعلية من قاعدة بيانات المنصة</p>
      </div>
      {loading && <Card><CardContent className="p-8 text-center text-muted-foreground">جاري تحميل الصلاحيات...</CardContent></Card>}
      {error && !loading && <Card><CardContent className="p-8 text-center text-destructive">{error}</CardContent></Card>}
      {!loading && !error && (
        <>
          <div className="grid gap-4 sm:grid-cols-3">
            <Metric icon={<Shield className="h-5 w-5 text-primary" />} value={permissions.length} label="صلاحية مسجلة" />
            <Metric icon={<ShieldCheck className="h-5 w-5 text-emerald-600" />} value={roles.length} label="دور نظامي" />
            <Metric icon={<Users className="h-5 w-5 text-amber-600" />} value={roles.reduce((sum, item) => sum + item.userCount, 0)} label="مستخدمون مرتبطون بأدوار" />
          </div>
          <div className="grid gap-6 lg:grid-cols-3">
            <Card>
              <CardHeader><CardTitle>الأدوار</CardTitle></CardHeader>
              <CardContent className="space-y-2">
                {roles.map((item) => (
                  <button key={item.id} onClick={() => setSelectedRole(item.id)} className={`w-full rounded-lg border p-4 text-right transition ${role?.id === item.id ? "border-primary bg-primary/5" : "border-border hover:bg-accent/30"}`}>
                    <div className="flex items-center justify-between gap-2"><span className="font-medium">{item.name}</span><Badge variant={item.isSystem ? "secondary" : "outline"}>{item.userCount} مستخدم</Badge></div>
                    <p className="mt-2 text-xs text-muted-foreground">{item.description}</p>
                  </button>
                ))}
              </CardContent>
            </Card>
            <Card className="lg:col-span-2">
              <CardHeader>
                <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <div><CardTitle>{role?.name || "الصلاحيات"}</CardTitle><p className="mt-1 text-sm text-muted-foreground">{role?.permissionKeys.length || 0} صلاحية لهذا الدور</p></div>
                  <div className="relative sm:w-72"><Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="ابحث في الصلاحيات..." className="h-10 w-full rounded-lg border border-input bg-background pl-4 pr-10 text-sm" /></div>
                </div>
              </CardHeader>
              <CardContent className="max-h-[600px] space-y-5 overflow-y-auto">
                {Object.entries(groupedPermissions).map(([module, items]) => (
                  <section key={module}>
                    <h3 className="mb-2 text-sm font-semibold uppercase text-primary">{module}</h3>
                    <div className="grid gap-2 md:grid-cols-2">
                      {items.map((permission) => {
                        const granted = role?.permissionKeys.includes(permission.key) || false;
                        return <div key={permission.key} className={`rounded-lg border p-3 ${granted ? "border-emerald-500/30 bg-emerald-500/5" : "border-border"}`}><div className="flex items-center justify-between gap-2"><div><p className="text-sm font-medium">{permission.name}</p><p className="text-xs text-muted-foreground" dir="ltr">{permission.key}</p></div>{granted ? <ShieldCheck className="h-4 w-4 text-emerald-600" /> : <Lock className="h-4 w-4 text-muted-foreground" />}</div><p className="mt-2 text-xs text-muted-foreground">{permission.description}</p></div>;
                      })}
                    </div>
                  </section>
                ))}
                {filteredPermissions.length === 0 && <p className="py-8 text-center text-muted-foreground">لا توجد صلاحيات مطابقة</p>}
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </div>
  );
}

function Metric({ icon, value, label }: { icon: React.ReactNode; value: number; label: string }) {
  return <Card><CardContent className="flex items-center gap-4 p-5"><div className="rounded-xl bg-primary/10 p-3">{icon}</div><div><p className="text-2xl font-bold">{value}</p><p className="text-sm text-muted-foreground">{label}</p></div></CardContent></Card>;
}