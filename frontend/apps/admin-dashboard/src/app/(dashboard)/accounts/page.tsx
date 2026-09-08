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
  Building2,
  CreditCard,
  MapPin,
  Phone,
  Mail,
  ChevronLeft,
  ChevronRight,
  Store,
  Hospital,
  Building,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { Button } from "@/components/ui";
import { Input } from "@/components/ui";
import { Badge } from "@/components/ui";

// Types
type AccountType = "pharmacy" | "chain" | "hospital";
type AccountStatus = "active" | "inactive" | "suspended";

interface Account {
  id: string;
  name: string;
  type: AccountType;
  status: AccountStatus;
  companyName: string;
  branchesCount: number;
  city: string;
  phone?: string;
  email: string;
  createdAt: string;
}

// Mock Data
const mockAccounts: Account[] = [
  {
    id: "1",
    name: "صيدلية الأمل الرئيسية",
    type: "pharmacy",
    status: "active",
    companyName: "صيدليات الأمل",
    branchesCount: 1,
    city: "الرياض",
    phone: "+966 50 123 4567",
    email: "main@hope-pharma.com",
    createdAt: "2024-01-15",
  },
  {
    id: "2",
    name: "مستشفى النور التخصصي",
    type: "hospital",
    status: "active",
    companyName: "مجموعة النور الطبية",
    branchesCount: 5,
    city: "جدة",
    email: "hospital@alnoor-med.com",
    createdAt: "2024-01-12",
  },
  {
    id: "3",
    name: "سلسلة صيدليات الوفاء",
    type: "chain",
    status: "active",
    companyName: "صيدلية الوفاء",
    branchesCount: 8,
    city: "الدمام",
    phone: "+966 55 987 6543",
    email: "info@alwafa-chain.com",
    createdAt: "2024-01-10",
  },
  {
    id: "4",
    name: "صيدلية الرحمة",
    type: "pharmacy",
    status: "suspended",
    companyName: "شركة الرحمة",
    branchesCount: 1,
    city: "مكة المكرمة",
    email: "rahma@pharma.com",
    createdAt: "2024-01-08",
  },
  {
    id: "5",
    name: "صيدليات الشفاء - فرع العليا",
    type: "pharmacy",
    status: "active",
    companyName: "صيدليات الشفاء",
    branchesCount: 1,
    city: "الرياض",
    phone: "+966 50 111 2233",
    email: "aliya@shifa-pharma.com",
    createdAt: "2024-01-05",
  },
];

const typeLabels: Record<AccountType, string> = {
  pharmacy: "صيدلية",
  chain: "سلسلة صيدليات",
  hospital: "مستشفى",
};

const typeIcons: Record<AccountType, React.ReactNode> = {
  pharmacy: <Store className="h-4 w-4" />,
  chain: <Building className="h-4 w-4" />,
  hospital: <Hospital className="h-4 w-4" />,
};

const statusVariants: Record<AccountStatus, "default" | "secondary" | "destructive" | "success" | "warning" | "outline"> = {
  active: "success",
  inactive: "secondary",
  suspended: "destructive",
};

export default function AccountsPage() {
  const [searchQuery, setSearchQuery] = useState("");
  const [typeFilter, setTypeFilter] = useState<string>("all");
  const [statusFilter, setStatusFilter] = useState<string>("all");

  const filteredAccounts = mockAccounts.filter((account) => {
    const matchesSearch =
      account.name.includes(searchQuery) ||
      account.companyName.includes(searchQuery) ||
      account.city.includes(searchQuery);
    
    const matchesType = typeFilter === "all" || account.type === typeFilter;
    const matchesStatus = statusFilter === "all" || account.status === statusFilter;
    
    return matchesSearch && matchesType && matchesStatus;
  });

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">إدارة الحسابات</h1>
          <p className="text-muted-foreground mt-1">
            إدارة جميع الحسابات والصيدليات والفروع في المنصة
          </p>
        </div>
        <Button variant="gradient">
          <Plus className="h-4 w-4 ml-2" />
          إضافة حساب جديد
        </Button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-primary/10 text-primary">
              <CreditCard className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">{mockAccounts.length}</p>
              <p className="text-sm text-muted-foreground">إجمالي الحسابات</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-emerald-500/10 text-emerald-600 dark:text-emerald-400">
              <Store className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                {mockAccounts.filter((a) => a.type === "pharmacy").length}
              </p>
              <p className="text-sm text-muted-foreground">صيدليات فردية</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-blue-500/10 text-blue-600 dark:text-blue-400">
              <Building className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                {mockAccounts.filter((a) => a.type === "chain").length}
              </p>
              <p className="text-sm text-muted-foreground">سلاسل صيدليات</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-4">
            <div className="p-3 rounded-xl bg-purple-500/10 text-purple-600 dark:text-purple-400">
              <Hospital className="h-5 w-5" />
            </div>
            <div>
              <p className="text-2xl font-bold">
                {mockAccounts.filter((a) => a.type === "hospital").length}
              </p>
              <p className="text-sm text-muted-foreground">مستشفيات</p>
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
                placeholder="بحث بالاسم أو الشركة أو المدينة..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full h-10 pl-4 pr-10 rounded-lg border border-input bg-background text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring transition-all"
              />
            </div>
            <div className="flex gap-2 flex-wrap">
              <select
                value={typeFilter}
                onChange={(e) => setTypeFilter(e.target.value)}
                className="h-10 px-4 rounded-lg border border-input bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              >
                <option value="all">كل الأنواع</option>
                <option value="pharmacy">صيدلية</option>
                <option value="chain">سلسلة صيدليات</option>
                <option value="hospital">مستشفى</option>
              </select>
              <select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="h-10 px-4 rounded-lg border border-input bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              >
                <option value="all">كل الحالات</option>
                <option value="active">نشط</option>
                <option value="inactive">غير نشط</option>
                <option value="suspended">موقوف</option>
              </select>
              <Button variant="outline" size="icon">
                <Filter className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Accounts Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        {filteredAccounts.map((account) => (
          <Card key={account.id} className={`transition-all hover:shadow-lg ${account.status === "suspended" ? "opacity-60" : ""}`}>
            <CardContent className="p-6">
              {/* Header */}
              <div className="flex items-start justify-between mb-4">
                <div className="flex items-center gap-3">
                  <div className="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center text-primary">
                    {typeIcons[account.type]}
                  </div>
                  <div>
                    <h3 className="font-semibold line-clamp-1">{account.name}</h3>
                    <p className="text-sm text-muted-foreground">{account.companyName}</p>
                  </div>
                </div>
                <Badge variant={statusVariants[account.status]}>
                  {account.status === "active" ? "نشط" : account.status === "suspended" ? "موقوف" : "غير نشط"}
                </Badge>
              </div>

              {/* Details */}
              <div className="space-y-2 mb-4">
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Building2 className="h-4 w-4 shrink-0" />
                  <span>{typeLabels[account.type]}</span>
                  <span className="mr-auto">
                    {account.branchesCount} {account.branchesCount === 1 ? "فرع" : "فروع"}
                  </span>
                </div>
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <MapPin className="h-4 w-4 shrink-0" />
                  <span>{account.city}</span>
                </div>
                {account.phone && (
                  <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Phone className="h-4 w-4 shrink-0" />
                    <span dir="ltr">{account.phone}</span>
                  </div>
                )}
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Mail className="h-4 w-4 shrink-0" />
                  <span dir="ltr" className="truncate">{account.email}</span>
                </div>
              </div>

              {/* Actions */}
              <div className="flex items-center gap-2 pt-4 border-t border-border">
                <Button variant="ghost" size="sm" className="flex-1">
                  <Eye className="h-4 w-4 ml-1" />
                  عرض
                </Button>
                <Button variant="ghost" size="sm" className="flex-1">
                  <Edit className="h-4 w-4 ml-1" />
                  تعديل
                </Button>
                <Button variant="ghost" size="icon" className="text-destructive hover:text-destructive shrink-0">
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Empty State */}
      {filteredAccounts.length === 0 && (
        <Card>
          <CardContent className="text-center py-12">
            <CreditCard className="h-12 w-12 mx-auto text-muted-foreground mb-4" />
            <h3 className="text-lg font-medium mb-2">لا توجد حسابات</h3>
            <p className="text-muted-foreground mb-4">
              لم يتم العثور على حسابات تطابق معايير البحث
            </p>
            <Button variant="outline" onClick={() => {
              setSearchQuery("");
              setTypeFilter("all");
              setStatusFilter("all");
            }}>
              مسح الفلاتر
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Pagination */}
      {filteredAccounts.length > 0 && (
        <div className="flex items-center justify-between">
          <p className="text-sm text-muted-foreground">
            عرض {filteredAccounts.length} من {mockAccounts.length} حساب
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
    </div>
  );
}

// RTL arrows fix - using CSS transform for proper RTL support
// ChevronLeft/ChevronRight are imported from lucide-react and will be flipped via CSS
