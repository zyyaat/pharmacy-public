"use client";

import React from "react";
import Link from "next/link";
import {
  Building2,
  Users,
  CreditCard,
  TrendingUp,
  ArrowUpRight,
  ArrowDownRight,
  Activity,
  Clock,
  CheckCircle,
  XCircle,
  Plus,
  MoreHorizontal,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { Button } from "@/components/ui";
import { Badge } from "@/components/ui";

// Mock Data
const stats = [
  {
    title: "إجمالي الشركات",
    value: "24",
    change: "+12%",
    trend: "up",
    icon: <Building2 className="h-5 w-5" />,
    description: "منذ الشهر الماضي",
  },
  {
    title: "المستخدمين النشطين",
    value: "1,429",
    change: "+8.2%",
    trend: "up",
    icon: <Users className="h-5 w-5" />,
    description: "منذ الأسبوع الماضي",
  },
  {
    title: "الحسابات",
    value: "156",
    change: "+23",
    trend: "up",
    icon: <CreditCard className="h-5 w-5" />,
    description: "صيدليات وفروع جديدة",
  },
  {
    title: "معدل النمو",
    value: "94.2%",
    change: "-2.4%",
    trend: "down",
    icon: <TrendingUp className="h-5 w-5" />,
    description: "مقارنة بالشهر السابق",
  },
];

const recentCompanies = [
  {
    id: "1",
    name: "صيدليات الأمل",
    status: "active" as const,
    plan: "professional" as const,
    users: 12,
    createdAt: "2024-01-15",
  },
  {
    id: "2",
    name: "مجموعة النور الطبية",
    status: "active" as const,
    plan: "enterprise" as const,
    users: 45,
    createdAt: "2024-01-12",
  },
  {
    id: "3",
    name: "صيدلية الوفاء",
    status: "trial" as const,
    plan: "starter" as const,
    users: 3,
    createdAt: "2024-01-10",
  },
  {
    id: "4",
    name: "شركة الرحمة",
    status: "suspended" as const,
    plan: "professional" as const,
    users: 8,
    createdAt: "2024-01-08",
  },
];

const recentActivities = [
  {
    id: "1",
    type: "user_created" as const,
    description: "تم إنشاء مستخدم جديد: أحمد محمد",
    user: "مدير النظام",
    time: "منذ 5 دقائق",
    icon: <Users className="h-4 w-4" />,
    color: "text-emerald-500 bg-emerald-500/10",
  },
  {
    id: "2",
    type: "company_created" as const,
    description: "تم تسجيل شركة جديدة: صيدليات الشفاء",
    user: "مدير النظام",
    time: "منذ ساعة",
    icon: <Building2 className="h-4 w-4" />,
    color: "text-blue-500 bg-blue-500/10",
  },
  {
    id: "3",
    type: "permission_changed" as const,
    description: "تحديث صلاحيات مستخدم: سارة علي",
    user: "مدير الشركة",
    time: "منذ ساعتين",
    icon: <CheckCircle className="h-4 w-4" />,
    color: "text-amber-500 bg-amber-500/10",
  },
  {
    id: "4",
    type: "login" as const,
    description: "تسجيل دخول من جهاز جديد",
    user: "محمد خالد",
    time: "منذ 3 ساعات",
    icon: <Activity className="h-4 w-4" />,
    color: "text-primary bg-primary/10",
  },
];

const statusLabels: Record<string, { label: string; variant: "default" | "secondary" | "destructive" | "success" | "warning" | "outline" }> = {
  active: { label: "نشط", variant: "success" },
  trial: { label: "تجريبي", variant: "warning" },
  suspended: { label: "موقوف", variant: "destructive" },
  cancelled: { label: "ملغي", variant: "secondary" },
};

const planLabels: Record<string, string> = {
  free: "مجاني",
  starter: "أساسي",
  professional: "احترافي",
  enterprise: "مؤسسي",
  custom: "مخصص",
};

export default function DashboardPage() {
  return (
    <div className="space-y-6 animate-fade-in">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">لوحة التحكم</h1>
          <p className="text-muted-foreground mt-1">
            نظرة عامة على نظام إدارة الصيدلية
          </p>
        </div>
        <Button variant="gradient">
          <Plus className="h-4 w-4 ml-2" />
          إضافة شركة جديدة
        </Button>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map((stat, index) => (
          <Card key={index} className="relative overflow-hidden">
            <CardContent className="p-6">
              <div className="flex items-start justify-between">
                <div className="space-y-2">
                  <p className="text-sm text-muted-foreground">{stat.title}</p>
                  <p className="text-3xl font-bold">{stat.value}</p>
                  <div className="flex items-center gap-1 text-sm">
                    {stat.trend === "up" ? (
                      <ArrowUpRight className="h-4 w-4 text-emerald-500" />
                    ) : (
                      <ArrowDownRight className="h-4 w-4 text-red-500" />
                    )}
                    <span
                      className={
                        stat.trend === "up"
                          ? "text-emerald-500"
                          : "text-red-500"
                      }
                    >
                      {stat.change}
                    </span>
                    <span className="text-muted-foreground">
                      {stat.description}
                    </span>
                  </div>
                </div>
                <div className="p-3 rounded-xl bg-primary/10 text-primary">
                  {stat.icon}
                </div>
              </div>
              {/* Decorative gradient */}
              <div className="absolute -bottom-4 -left-4 w-24 h-24 bg-primary/5 rounded-full blur-2xl" />
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Content Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Recent Companies */}
        <Card className="lg:col-span-2">
          <CardHeader className="flex flex-row items-center justify-between pb-4">
            <CardTitle className="text-lg">أحدث الشركات</CardTitle>
            <Link href="/companies">
              <Button variant="ghost" size="sm">
                عرض الكل
                <ArrowUpRight className="h-4 w-4 mr-1 rotate-180" />
              </Button>
            </Link>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {recentCompanies.map((company) => (
                <div
                  key={company.id}
                  className="flex items-center justify-between p-4 rounded-lg bg-background hover:bg-accent/50 transition-colors group"
                >
                  <div className="flex items-center gap-4">
                    <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center text-primary font-bold">
                      {company.name.charAt(0)}
                    </div>
                    <div>
                      <p className="font-medium">{company.name}</p>
                      <p className="text-sm text-muted-foreground">
                        {company.users} مستخدم • {planLabels[company.plan]}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <Badge variant={statusLabels[company.status].variant}>
                      {statusLabels[company.status].label}
                    </Badge>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="opacity-0 group-hover:opacity-100 transition-opacity"
                    >
                      <MoreHorizontal className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Recent Activity */}
        <Card>
          <CardHeader className="pb-4">
            <CardTitle className="text-lg">النشاط الأخير</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {recentActivities.map((activity) => (
                <div key={activity.id} className="flex gap-3">
                  <div
                    className={`p-2 rounded-lg shrink-0 ${activity.color}`}
                  >
                    {activity.icon}
                  </div>
                  <div className="flex-1 min-w-0 space-y-1">
                    <p className="text-sm leading-relaxed">
                      {activity.description}
                    </p>
                    <div className="flex items-center gap-2 text-xs text-muted-foreground">
                      <span>{activity.user}</span>
                      <span>•</span>
                      <span>{activity.time}</span>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {/* View All Link */}
            <Button variant="outline" className="w-full mt-4">
              عرض كل النشاطات
            </Button>
          </CardContent>
        </Card>
      </div>

      {/* Quick Actions */}
      <Card>
        <CardHeader className="pb-4">
          <CardTitle className="text-lg">إجراءات سريعة</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <Link
              href="/companies/new"
              className="flex flex-col items-center gap-2 p-4 rounded-xl border border-border hover:bg-accent/50 hover:border-primary/20 transition-all group"
            >
              <div className="p-3 rounded-xl bg-primary/10 text-primary group-hover:bg-primary group-hover:text-primary-foreground transition-colors">
                <Building2 className="h-6 w-6" />
              </div>
              <span className="text-sm font-medium">إضافة شركة</span>
            </Link>
            <Link
              href="/users/new"
              className="flex flex-col items-center gap-2 p-4 rounded-xl border border-border hover:bg-accent/50 hover:border-primary/20 transition-all group"
            >
              <div className="p-3 rounded-xl bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 group-hover:bg-emerald-500 group-hover:text-white transition-colors">
                <Users className="h-6 w-6" />
              </div>
              <span className="text-sm font-medium">إضافة مستخدم</span>
            </Link>
            <Link
              href="/permissions"
              className="flex flex-col items-center gap-2 p-4 rounded-xl border border-border hover:bg-accent/50 hover:border-primary/20 transition-all group"
            >
              <div className="p-3 rounded-xl bg-amber-500/10 text-amber-600 dark:text-amber-400 group-hover:bg-amber-500 group-hover:text-white transition-colors">
                <CheckCircle className="h-6 w-6" />
              </div>
              <span className="text-sm font-medium">الصلاحيات</span>
            </Link>
            <Link
              href="/settings"
              className="flex flex-col items-center gap-2 p-4 rounded-xl border border-border hover:bg-accent/50 hover:border-primary/20 transition-all group"
            >
              <div className="p-3 rounded-xl bg-blue-500/10 text-blue-600 dark:text-blue-400 group-hover:bg-blue-500 group-hover:text-white transition-colors">
                <Clock className="h-6 w-6" />
              </div>
              <span className="text-sm font-medium">التقارير</span>
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

// RTL arrow fix - using CSS transform for proper RTL support
// ArrowUpRight is imported from lucide-react and will be flipped via CSS
