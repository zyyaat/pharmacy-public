"use client";

import React, { useState } from "react";
import {
  Search,
  Plus,
  Filter,
  MoreHorizontal,
  Eye,
  Edit,
  Trash2,
  Shield,
  ShieldCheck,
  UserPlus,
  Mail,
  Lock,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { Button } from "@/components/ui";
import { Badge } from "@/components/ui";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui";
import { ROLE_LABELS, type Role } from "@/lib/utils";

// Mock Data
const mockUsers = [
  {
    id: "1",
    name: "أحمد محمد",
    email: "ahmed@pharmacy.os",
    role: "super_admin" as Role,
    company: "Pharmacy OS",
    isActive: true,
    lastLogin: "2024-01-15T10:30:00Z",
    createdAt: "2023-06-01",
    permissionsCount: 45,
  },
  {
    id: "2",
    name: "سارة علي",
    email: "sara@hope-pharma.com",
    role: "company_admin" as Role,
    company: "صيدليات الأمل",
    isActive: true,
    lastLogin: "2024-01-15T09:15:00Z",
    createdAt: "2023-08-15",
    permissionsCount: 28,
  },
  {
    id: "3",
    name: "محمد خالد",
    email: "mohammed@alnoor-med.com",
    role: "company_manager" as Role,
    company: "مجموعة النور الطبية",
    isActive: true,
    lastLogin: "2024-01-14T14:20:00Z",
    createdAt: "2023-09-20",
    permissionsCount: 18,
  },
  {
    id: "4",
    name: "فاطمة حسن",
    email: "fatima@shifa-pharma.com",
    role: "viewer" as Role,
    company: "صيدليات الشفاء",
    isActive: true,
    lastLogin: "2024-01-13T11:00:00Z",
    createdAt: "2023-10-05",
    permissionsCount: 8,
  },
  {
    id: "5",
    name: "عمر عبدالله",
    email: "omar@rahma-co.com",
    role: "company_admin" as Role,
    company: "شركة الرحمة",
    isActive: false,
    lastLogin: "2024-01-10T16:45:00Z",
    createdAt: "2023-11-12",
    permissionsCount: 28,
  },
];

const roleBadgeVariants: Record<Role, "default" | "secondary" | "outline" | "destructive" | "success" | "warning"> = {
  super_admin: "destructive",
  company_admin: "default",
  company_manager: "secondary",
  viewer: "outline",
};

export default function UsersPage() {
  const [searchQuery, setSearchQuery] = useState("");
  const [roleFilter, setRoleFilter] = useState<string>("all");
  const [showPermissionsModal, setShowPermissionsModal] = useState<string | null>(null);

  const filteredUsers = mockUsers.filter((user) => {
    const matchesSearch =
      user.name.includes(searchQuery) ||
      user.email.toLowerCase().includes(searchQuery.toLowerCase()) ||
      user.company.includes(searchQuery);
    
    const matchesRole = roleFilter === "all" || user.role === roleFilter;
    
    return matchesSearch && matchesRole;
  });

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">إدارة المستخدمين</h1>
          <p className="text-muted-foreground mt-1">
            إدارة جميع المستخدمين والصلاحيات في المنصة
          </p>
        </div>
        <Button variant="gradient">
          <UserPlus className="h-4 w-4 ml-2" />
          إضافة مستخدم جديد
        </Button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-primary/10 text-primary">
              <ShieldCheck className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">{mockUsers.length}</p>
              <p className="text-sm text-muted-foreground">إجمالي المستخدمين</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-emerald-500/10 text-emerald-600 dark:text-emerald-400">
              <ShieldCheck className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                {mockUsers.filter((u) => u.isActive).length}
              </p>
              <p className="text-sm text-muted-foreground">مستخدمين نشطين</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-amber-500/10 text-amber-600 dark:text-amber-400">
              <Shield className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                {mockUsers.filter((u) => u.role === "super_admin").length}
              </p>
              <p className="text-sm text-muted-foreground">مدراء نظام</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-red-500/10 text-red-600 dark:text-red-400">
              <Lock className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                {mockUsers.filter((u) => !u.isActive).length}
              </p>
              <p className="text-sm text-muted-foreground">مستخدمين معطلين</p>
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
                value={roleFilter}
                onChange={(e) => setRoleFilter(e.target.value)}
                className="h-10 px-4 rounded-lg border border-input bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              >
                <option value="all">كل الأدوار</option>
                <option value="super_admin">مدير النظام</option>
                <option value="company_admin">مدير الشركة</option>
                <option value="company_manager">مدير العمليات</option>
                <option value="viewer">مشاهد</option>
              </select>
              <Button variant="outline" size="icon">
                <Filter className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Users Grid/Table */}
      <div className="grid gap-4">
        {filteredUsers.map((user) => (
          <Card key={user.id} className={`transition-all hover:shadow-md ${!user.isActive ? "opacity-60" : ""}`}>
            <CardContent className="p-6">
              <div className="flex flex-col sm:flex-row sm:items-center gap-4">
                {/* User Info */}
                <div className="flex items-center gap-4 flex-1 min-w-0">
                  <Avatar className="h-12 w-12 shrink-0">
                    <AvatarImage src={`/avatars/${user.id}.png`} alt={user.name} />
                    <AvatarFallback className="bg-primary/10 text-primary text-lg">
                      {user.name.charAt(0)}
                    </AvatarFallback>
                  </Avatar>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <h3 className="font-semibold">{user.name}</h3>
                      {!user.isActive && (
                        <Badge variant="destructive">معطل</Badge>
                      )}
                    </div>
                    <p className="text-sm text-muted-foreground">{user.email}</p>
                    <div className="flex items-center gap-3 mt-1 text-xs text-muted-foreground">
                      <span>{user.company}</span>
                      <span>•</span>
                      <span>آخر تسجيل: {new Date(user.lastLogin).toLocaleDateString("ar-EG")}</span>
                    </div>
                  </div>
                </div>

                {/* Role & Permissions */}
                <div className="flex items-center gap-4 sm:gap-6">
                  <div className="text-center sm:text-right">
                    <Badge variant={roleBadgeVariants[user.role]} className="mb-1">
                      {ROLE_LABELS[user.role]}
                    </Badge>
                    <p className="text-xs text-muted-foreground mt-1">
                      {user.permissionsCount} صلاحية
                    </p>
                  </div>

                  {/* Actions */}
                  <div className="flex items-center gap-1">
                    <Button
                      variant="ghost"
                      size="icon"
                      title="عرض التفاصيل"
                    >
                      <Eye className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      title="تعديل"
                    >
                      <Edit className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      title="إدارة الصلاحيات"
                      onClick={() => setShowPermissionsModal(user.id)}
                    >
                      <Shield className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      title="حذف"
                      className="text-destructive hover:text-destructive"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}

        {/* Empty State */}
        {filteredUsers.length === 0 && (
          <Card>
            <CardContent className="text-center py-12">
              <ShieldCheck className="h-12 w-12 mx-auto text-muted-foreground mb-4" />
              <h3 className="text-lg font-medium mb-2">لا يوجد مستخدمون</h3>
              <p className="text-muted-foreground mb-4">
                لم يتم العثور على مستخدمين تطابق معايير البحث
              </p>
              <Button variant="outline" onClick={() => { setSearchQuery(""); setRoleFilter("all"); }}>
                مسح الفلاتر
              </Button>
            </CardContent>
          </Card>
        )}
      </div>

      {/* Permissions Modal (Simplified) */}
      {showPermissionsModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
          <Card className="w-full max-w-lg max-h-[80vh] overflow-hidden animate-scale-in">
            <CardHeader className="border-b border-border">
              <CardTitle>إدارة صلاحيات المستخدم</CardTitle>
            </CardHeader>
            <CardContent className="p-6 overflow-y-auto">
              <div className="space-y-4">
                <div>
                  <h4 className="font-medium mb-3">صلاحيات الشركات</h4>
                  <div className="space-y-2">
                    {["companies.view", "companies.create", "companies.edit", "companies.delete"].map((perm) => (
                      <label key={perm} className="flex items-center gap-3 p-3 rounded-lg hover:bg-accent/50 cursor-pointer transition-colors">
                        <input type="checkbox" defaultChecked={perm.includes("view")} className="rounded" />
                        <span className="text-sm">{perm.replace(".", ". ")}</span>
                      </label>
                    ))}
                  </div>
                </div>
                <div>
                  <h4 className="font-medium mb-3">صلاحيات المستخدمين</h4>
                  <div className="space-y-2">
                    {["company_users.view", "company_users.create", "company_users.edit"].map((perm) => (
                      <label key={perm} className="flex items-center gap-3 p-3 rounded-lg hover:bg-accent/50 cursor-pointer transition-colors">
                        <input type="checkbox" defaultChecked={perm.includes("view")} className="rounded" />
                        <span className="text-sm">{perm.replace(".", ". ")}</span>
                      </label>
                    ))}
                  </div>
                </div>
              </div>
            </CardContent>
            <div className="flex justify-end gap-3 p-6 pt-0">
              <Button variant="outline" onClick={() => setShowPermissionsModal(null)}>
                إلغاء
              </Button>
              <Button variant="gradient" onClick={() => setShowPermissionsModal(null)}>
                حفظ التغييرات
              </Button>
            </div>
          </Card>
        </div>
      )}
    </div>
  );
}

// RTL arrows fix - using CSS transform for proper RTL support
// ChevronLeft/ChevronRight are imported from lucide-react and will be flipped via CSS
