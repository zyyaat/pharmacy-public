"use client";

import React, { useState } from "react";
import {
  Shield,
  ShieldCheck,
  Search,
  Plus,
  Users,
  Building2,
  Settings,
  Eye,
  Edit,
  Trash2,
  ChevronDown,
  Lock,
  Unlock,
  Copy,
  Check,
  RefreshCw,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui";
import { Button } from "@/components/ui";
import { Input } from "@/components/ui";
import { Badge } from "@/components/ui";
import { PERMISSIONS, PERMISSION_LABELS, type Permission } from "@/lib/utils";

// Group permissions by category
const permissionGroups = [
  {
    id: "companies",
    name: "صلاحيات الشركات",
    icon: <Building2 className="h-5 w-5" />,
    permissions: [
      PERMISSIONS.COMPANIES_VIEW,
      PERMISSIONS.COMPANIES_CREATE,
      PERMISSIONS.COMPANIES_EDIT,
      PERMISSIONS.COMPANIES_DELETE,
    ],
  },
  {
    id: "users",
    name: "صلاحيات المستخدمين",
    icon: <Users className="h-5 w-5" />,
    permissions: [
      PERMISSIONS.COMPANY_USERS_VIEW,
      PERMISSIONS.COMPANY_USERS_CREATE,
      PERMISSIONS.COMPANY_USERS_EDIT,
      PERMISSIONS.COMPANY_USERS_DELETE,
      PERMISSIONS.COMPANY_USERS_MANAGE_PERMISSIONS,
    ],
  },
  {
    id: "accounts",
    name: "صلاحيات الحسابات",
    icon: <Settings className="h-5 w-5" />,
    permissions: [
      PERMISSIONS.ACCOUNTS_VIEW,
      PERMISSIONS.ACCOUNTS_CREATE,
      PERMISSIONS.ACCOUNTS_EDIT,
      PERMISSIONS.ACCOUNTS_DELETE,
    ],
  },
  {
    id: "platform",
    name: "صلاحيات المنصة",
    icon: <Shield className="h-5 w-5" />,
    permissions: [
      PERMISSIONS.PLATFORM_SETTINGS,
      PERMISSIONS.PLATFORM_MANAGEMENT,
      PERMISSIONS.PLATFORM_ANALYTICS,
    ],
  },
];

// Mock roles with their default permissions
const mockRoles = [
  {
    id: "super_admin",
    name: "مدير النظام",
    description: "صلاحيات كاملة على جميع أنظمة المنصة",
    userCount: 3,
    permissions: Object.values(PERMISSIONS) as Permission[],
    isSystem: true,
  },
  {
    id: "company_admin",
    name: "مدير الشركة",
    description: "إدارة كاملة لشركته والمستخدمين التابعين لها",
    userCount: 12,
    permissions: [
      PERMISSIONS.COMPANIES_VIEW,
      PERMISSIONS.COMPANIES_EDIT,
      PERMISSIONS.COMPANY_USERS_VIEW,
      PERMISSIONS.COMPANY_USERS_CREATE,
      PERMISSIONS.COMPANY_USERS_EDIT,
      PERMISSIONS.COMPANY_USERS_MANAGE_PERMISSIONS,
      PERMISSIONS.ACCOUNTS_VIEW,
      PERMISSIONS.ACCOUNTS_CREATE,
      PERMISSIONS.ACCOUNTS_EDIT,
    ],
    isSystem: true,
  },
  {
    id: "company_manager",
    name: "مدير العمليات",
    description: "إدارة يومية للعمليات دون صلاحيات الحذف",
    userCount: 28,
    permissions: [
      PERMISSIONS.COMPANIES_VIEW,
      PERMISSIONS.COMPANY_USERS_VIEW,
      PERMISSIONS.ACCOUNTS_VIEW,
      PERMISSIONS.ACCOUNTS_CREATE,
      PERMISSIONS.ACCOUNTS_EDIT,
    ],
    isSystem: true,
  },
  {
    id: "viewer",
    name: "مشاهد",
    description: "عرض فقط بدون صلاحيات تعديل",
    userCount: 45,
    permissions: [
      PERMISSIONS.COMPANIES_VIEW,
      PERMISSIONS.COMPANY_USERS_VIEW,
      PERMISSIONS.ACCOUNTS_VIEW,
      PERMISSIONS.PLATFORM_ANALYTICS,
    ],
    isSystem: true,
  },
];

export default function PermissionsPage() {
  const [activeTab, setActiveTab] = useState<"roles" | "matrix">("roles");
  const [selectedRole, setSelectedRole] = useState(mockRoles[0].id);
  const [searchPermission, setSearchPermission] = useState("");
  const [copiedRole, setCopiedRole] = useState<string | null>(null);

  const currentRole = mockRoles.find((r) => r.id === selectedRole) || mockRoles[0];

  const handleCopyRole = (roleId: string) => {
    setCopiedRole(roleId);
    setTimeout(() => setCopiedRole(null), 2000);
  };

  const filteredGroups = permissionGroups.map((group) => ({
    ...group,
    permissions: group.permissions.filter(
      (p) =>
        PERMISSION_LABELS[p].toLowerCase().includes(searchPermission.toLowerCase()) ||
        p.toLowerCase().includes(searchPermission.toLowerCase())
    ),
  })).filter((group) => group.permissions.length > 0);

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">إدارة الصلاحيات</h1>
          <p className="text-muted-foreground mt-1">
            تحكم في صلاحيات الوصول والأدوار في النظام
          </p>
        </div>
        <Button variant="gradient">
          <Plus className="h-4 w-4 ml-2" />
          إنشاء دور مخصص
        </Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-primary/10 text-primary">
              <Shield className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">{Object.keys(PERMISSIONS).length}</p>
              <p className="text-sm text-muted-foreground">إجمالي الصلاحيات</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-emerald-500/10 text-emerald-600 dark:text-emerald-400">
              <ShieldCheck className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">{mockRoles.length}</p>
              <p className="text-sm text-muted-foreground">أدوار النظام</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-amber-500/10 text-amber-600 dark:text-amber-400">
              <Users className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                {mockRoles.reduce((acc, r) => acc + r.userCount, 0)}
              </p>
              <p className="text-sm text-muted-foreground">مستخدم مع دور</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-blue-500/10 text-blue-600 dark:text-blue-400">
              <Unlock className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">كاملة</p>
              <p className="text-sm text-muted-foreground">حالة الأمان</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 border-b border-border pb-4">
        <Button
          variant={activeTab === "roles" ? "default" : "ghost"}
          onClick={() => setActiveTab("roles")}
        >
          <Shield className="h-4 w-4 ml-2" />
          الأدوار والصلاحيات
        </Button>
        <Button
          variant={activeTab === "matrix" ? "default" : "ghost"}
          onClick={() => setActiveTab("matrix")}
        >
          <Settings className="h-4 w-4 ml-2" />
          مصفوفة الصلاحيات
        </Button>
      </div>

      {activeTab === "roles" ? (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Roles List */}
          <Card className="lg:col-span-1">
            <CardHeader className="pb-4">
              <CardTitle className="text-lg">الأدوار</CardTitle>
              <CardDescription>اختر دوراً لعرض صلاحياته</CardDescription>
            </CardHeader>
            <CardContent className="p-0">
              <div className="space-y-1 max-h-[500px] overflow-y-auto">
                {mockRoles.map((role) => (
                  <button
                    key={role.id}
                    onClick={() => setSelectedRole(role.id)}
                    className={`w-full text-right p-4 transition-all hover:bg-accent/50 ${
                      selectedRole === role.id ? "bg-primary/10 border-r-2 border-primary" : ""
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="font-medium">{role.name}</p>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          {role.userCount} مستخدم
                        </p>
                      </div>
                      {role.isSystem && (
                        <Badge variant="secondary" className="text-xs">
                          نظامي
                        </Badge>
                      )}
                    </div>
                  </button>
                ))}
              </div>
            </CardContent>
          </Card>

          {/* Role Permissions */}
          <Card className="lg:col-span-2">
            <CardHeader className="pb-4">
              <div className="flex items-start justify-between">
                <div>
                  <CardTitle className="text-lg flex items-center gap-2">
                    {currentRole.name}
                    {currentRole.isSystem && (
                      <Badge variant="secondary" className="text-xs">دور نظامي</Badge>
                    )}
                  </CardTitle>
                  <CardDescription className="mt-1">
                    {currentRole.description}
                  </CardDescription>
                </div>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => handleCopyRole(currentRole.id)}>
                    {copiedRole === currentRole.id ? (
                      <>
                        <Check className="h-4 w-4 ml-1" />
                        تم النسخ
                      </>
                    ) : (
                      <>
                        <Copy className="h-4 w-4 ml-1" />
                        نسخ الدور
                      </>
                    )}
                  </Button>
                  {!currentRole.isSystem && (
                    <Button variant="ghost" size="icon" className="text-destructive">
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  )}
                </div>
              </div>
            </CardHeader>
            <CardContent>
              {/* Search */}
              <div className="relative mb-4">
                <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <input
                  type="search"
                  placeholder="بحث في الصلاحيات..."
                  value={searchPermission}
                  onChange={(e) => setSearchPermission(e.target.value)}
                  className="w-full h-10 pl-4 pr-10 rounded-lg border border-input bg-background text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring transition-all"
                />
              </div>

              {/* Permission Groups */}
              <div className="space-y-6 max-h-[400px] overflow-y-auto pr-2">
                {filteredGroups.map((group) => (
                  <div key={group.id}>
                    <div className="flex items-center gap-2 mb-3 text-primary font-medium">
                      {group.icon}
                      <span>{group.name}</span>
                      <Badge variant="secondary" className="mr-auto">
                        {group.permissions.filter(p => currentRole.permissions.includes(p)).length}/{group.permissions.length}
                      </Badge>
                    </div>
                    <div className="grid gap-2 pl-7">
                      {group.permissions.map((permission) => {
                        const hasPermission = currentRole.permissions.includes(permission);
                        return (
                          <label
                            key={permission}
                            className={`flex items-center justify-between p-3 rounded-lg border cursor-pointer transition-all ${
                              hasPermission
                                ? "border-primary/30 bg-primary/5"
                                : "border-border hover:bg-accent/30"
                            } ${currentRole.isSystem ? "opacity-70" : ""}`}
                          >
                            <div className="flex items-center gap-3">
                              <input
                                type="checkbox"
                                checked={hasPermission}
                                disabled={currentRole.isSystem}
                                className="rounded border-border text-primary focus:ring-primary"
                              />
                              <span className="text-sm">{PERMISSION_LABELS[permission]}</span>
                            </div>
                            <span className={`text-xs px-2 py-0.5 rounded ${
                              hasPermission ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400" : "bg-muted text-muted-foreground"
                            }`}>
                              {hasPermission ? "مفعّل" : "معطّل"}
                            </span>
                          </label>
                        );
                      })}
                    </div>
                  </div>
                ))}
              </div>

              {/* Actions */}
              {!currentRole.isSystem && (
                <div className="flex justify-end gap-3 mt-6 pt-4 border-t border-border">
                  <Button variant="outline">إعادة تعيين</Button>
                  <Button variant="gradient">حفظ التغييرات</Button>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      ) : (
        /* Permission Matrix View */
        <Card>
          <CardHeader className="pb-4">
            <CardTitle className="text-lg">مصفوفة الصلاحيات</CardTitle>
            <CardDescription>
              عرض جميع الصلاحيات مقسمة حسب الأدوار
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[800px]">
                <thead>
                  <tr className="border-b border-border">
                    <th className="p-3 text-right font-medium">الصلاحية / الدور</th>
                    {mockRoles.map((role) => (
                      <th key={role.id} className="p-3 text-center font-medium min-w-[120px]">
                        <Badge variant={selectedRole === role.id ? "default" : "outline"} 
                          className="cursor-pointer"
                          onClick={() => setSelectedRole(role.id)}>
                          {role.name}
                        </Badge>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {permissionGroups.flatMap((group) =>
                    group.permissions.map((permission, idx) => (
                      <tr key={permission} className="border-b border-border hover:bg-accent/20">
                        <td className="p-3">
                          {idx === 0 && (
                            <div className="flex items-center gap-2 mb-2 text-primary font-medium">
                              {group.icon}
                              <span className="text-xs">{group.name}</span>
                            </div>
                          )}
                          <span className={`text-sm ${idx > 0 ? "pr-8" : ""}`}>
                            {PERMISSION_LABELS[permission]}
                          </span>
                        </td>
                        {mockRoles.map((role) => (
                          <td key={`${role.id}-${permission}`} className="p-3 text-center">
                            {role.permissions.includes(permission) ? (
                              <ShieldCheck className="h-5 w-5 mx-auto text-emerald-500" />
                            ) : (
                              <Lock className="h-5 w-5 mx-auto text-muted-foreground" />
                            )}
                          </td>
                        ))}
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
