"use client";

import React, { useState } from "react";
import {
  Settings,
  User,
  Bell,
  Shield,
  Palette,
  Globe,
  Database,
  Key,
  Save,
  RefreshCw,
  CheckCircle,
  AlertCircle,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui";
import { Button } from "@/components/ui";
import { Input } from "@/components/ui";
import { Badge } from "@/components/ui";

type SettingsTab = "profile" | "notifications" | "security" | "appearance" | "system";

export default function SettingsPage() {
  const [activeTab, setActiveTab] = useState<SettingsTab>("profile");
  const [saved, setSaved] = useState(false);
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    setSaving(true);
    await new Promise((resolve) => setTimeout(resolve, 1000));
    setSaving(false);
    setSaved(true);
    setTimeout(() => setSaved(false), 3000);
  };

  const tabs: { id: SettingsTab; label: string; icon: React.ReactNode }[] = [
    { id: "profile", label: "الملف الشخصي", icon: <User className="h-4 w-4" /> },
    { id: "notifications", label: "الإشعارات", icon: <Bell className="h-4 w-4" /> },
    { id: "security", label: "الأمان", icon: <Shield className="h-4 w-4" /> },
    { id: "appearance", label: "المظهر", icon: <Palette className="h-4 w-4" /> },
    { id: "system", label: "النظام", icon: <Database className="h-4 w-4" /> },
  ];

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">الإعدادات</h1>
          <p className="text-muted-foreground mt-1">
            إدارة إعدادات النظام والحساب
          </p>
        </div>
        <div className="flex gap-2">
          {saved && (
            <Badge variant="success" className="animate-fade-in">
              <CheckCircle className="h-3 w-3 ml-1" />
              تم الحفظ
            </Badge>
          )}
          <Button variant="outline" onClick={handleSave} disabled={saving}>
            {saving ? (
              <>
                <RefreshCw className="h-4 w-4 ml-2 animate-spin" />
                جاري الحفظ...
              </>
            ) : (
              <>
                <Save className="h-4 w-4 ml-2" />
                حفظ التغييرات
              </>
            )}
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
        {/* Sidebar Tabs */}
        <Card className="lg:col-span-1 h-fit">
          <CardContent className="p-2">
            <nav className="space-y-1">
              {tabs.map((tab) => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`w-full flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium transition-all text-right ${
                    activeTab === tab.id
                      ? "bg-primary/10 text-primary"
                      : "text-muted-foreground hover:bg-accent hover:text-foreground"
                  }`}
                >
                  {tab.icon}
                  {tab.label}
                </button>
              ))}
            </nav>
          </CardContent>
        </Card>

        {/* Content */}
        <div className="lg:col-span-3 space-y-6">
          {/* Profile Tab */}
          {activeTab === "profile" && (
            <Card>
              <CardHeader>
                <CardTitle>الملف الشخصي</CardTitle>
                <CardDescription>معلومات حسابك الشخصية</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                {/* Avatar Section */}
                <div className="flex items-center gap-6">
                  <div className="w-24 h-24 rounded-2xl bg-primary/10 flex items-center justify-center text-primary text-3xl font-bold">
                    م
                  </div>
                  <div className="space-y-2">
                    <Button variant="outline" size="sm">
                      تغيير الصورة الشخصية
                    </Button>
                    <p className="text-xs text-muted-foreground">
                      JPG, PNG أو GIF. الحد الأقصى 5MB.
                    </p>
                  </div>
                </div>

                {/* Form */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <Input label="الاسم الكامل" defaultValue="مدير النظام" />
                  <Input label="البريد الإلكتروني" type="email" defaultValue="admin@pharmacy.os" dir="ltr" className="text-left" />
                  <Input label="رقم الهاتف" type="tel" defaultValue="+966 50 000 0000" dir="ltr" className="text-left" />
                  <Input label="المسمى الوظيفي" defaultValue="مدير النظام" />
                </div>

                <div>
                  <label className="text-sm font-medium mb-2 block">نبذة شخصية</label>
                  <textarea
                    rows={4}
                    className="w-full px-4 py-3 rounded-lg border border-input bg-background text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring resize-none transition-all"
                    defaultValue="مدير نظام Pharmacy OS..."
                  />
                </div>
              </CardContent>
            </Card>
          )}

          {/* Notifications Tab */}
          {activeTab === "notifications" && (
            <Card>
              <CardHeader>
                <CardTitle>إعدادات الإشعارات</CardTitle>
                <CardDescription>تحكم في كيفية استلامك للإشعارات</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                {[
                  {
                    title: "إشعارات البريد الإلكتروني",
                    description: "استلم إشعارات عبر البريد عند حدوث أحداث مهمة",
                    options: ["شركات جديدة", "مستخدمين جدد", "تقارير أمنية"],
                  },
                  {
                    title: "إشعارات المتصفح",
                    description: "إشعارات فورية في المتصفح عند حدوث نشاط",
                    options: ["تسجيلات دخول جديدة", "تحديثات النظام", "تنبيهات الأمان"],
                  },
                ].map((section, idx) => (
                  <div key={idx} className="space-y-4 pb-6 border-b border-border last:border-0">
                    <div>
                      <h3 className="font-medium">{section.title}</h3>
                      <p className="text-sm text-muted-foreground mt-1">{section.description}</p>
                    </div>
                    <div className="space-y-3">
                      {section.options.map((option) => (
                        <label key={option} className="flex items-center justify-between p-3 rounded-lg hover:bg-accent/50 cursor-pointer transition-colors">
                          <span className="text-sm">{option}</span>
                          <input
                            type="switch"
                            defaultChecked
                            className="w-11 h-6 bg-primary rounded-full appearance-none cursor-pointer relative before:content-[''] before:absolute before:top-0.5 before:right-0.5 before:w-5 before:h-5 before:bg-white before:rounded-full before:transition-transform checked:before:translate-x-5"
                          />
                        </label>
                      ))}
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}

          {/* Security Tab */}
          {activeTab === "security" && (
            <div className="space-y-6">
              <Card>
                <CardHeader>
                  <CardTitle>تغيير كلمة المرور</CardTitle>
                  <CardDescription>حدّث كلمة المرور الخاصة بحسابك</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <Input label="كلمة المرور الحالية" type="password" />
                  <Input label="كلمة المرور الجديدة" type="password" />
                  <Input label="تأكيد كلمة المرور الجديدة" type="password" />
                  <Button variant="gradient">تحديث كلمة المرور</Button>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>المصادقة الثنائية</CardTitle>
                  <CardDescription>أضف طبقة أمان إضافية لحسابك</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="flex items-center justify-between p-4 rounded-lg border border-border">
                    <div className="flex items-center gap-3">
                      <Key className="h-5 w-5 text-muted-foreground" />
                      <div>
                        <p className="font-medium">مصادقة ثنائية (2FA)</p>
                        <p className="text-sm text-muted-foreground">
                          غير مفعّل حالياً
                        </p>
                      </div>
                    </div>
                    <Button variant="outline">تفعيل</Button>
                  </div>
                </CardContent>
              </Card>

              <Card className="border-destructive/20">
                <CardHeader>
                  <CardTitle className="text-destructive">منطقة خطرة</CardTitle>
                  <CardDescription>إجراءات لا يمكن التراجع عنها</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="flex items-center justify-between p-4 rounded-lg border border-destructive/20 bg-destructive/5">
                    <div className="flex items-center gap-3">
                      <AlertCircle className="h-5 w-5 text-destructive" />
                      <div>
                        <p className="font-medium">حذف الحساب</p>
                        <p className="text-sm text-muted-foreground">
                          حذف نهائي لجميع بياناتك
                        </p>
                      </div>
                    </div>
                    <Button variant="destructive">حذف الحساب</Button>
                  </div>
                </CardContent>
              </Card>
            </div>
          )}

          {/* Appearance Tab */}
          {activeTab === "appearance" && (
            <Card>
              <CardHeader>
                <CardTitle>المظهر</CardTitle>
                <CardDescription>خصص واجهة المستخدم حسب تفضيلاتك</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div>
                  <h3 className="font-medium mb-3">الوضع</h3>
                  <div className="grid grid-cols-3 gap-4">
                    {[
                      { id: "light", name: "فاتح", desc: "خلفية فاتحة" },
                      { id: "dark", name: "داكن", desc: "خلفية داكنة" },
                      { id: "system", name: "تلقائي", desc: "تبع إعدادات الجهاز" },
                    ].map((theme) => (
                      <button
                        key={theme.id}
                        className="p-4 rounded-xl border border-border hover:border-primary/50 transition-all text-right group"
                      >
                        <div className={`w-full aspect-video rounded-lg mb-3 ${theme.id === "dark" ? "bg-gray-900" : theme.id === "system" ? "bg-gradient-to-b from-white to-gray-900" : "bg-gray-100"}`} />
                        <p className="font-medium text-sm">{theme.name}</p>
                        <p className="text-xs text-muted-foreground">{theme.desc}</p>
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <h3 className="font-medium mb-3">اللغة</h3>
                  <select className="w-full max-w-xs h-10 px-4 rounded-lg border border-input bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring">
                    <option value="ar">العربية</option>
                    <option value="en">English</option>
                  </select>
                </div>
              </CardContent>
            </Card>
          )}

          {/* System Tab */}
          {activeTab === "system" && (
            <div className="space-y-6">
              <Card>
                <CardHeader>
                  <CardTitle>معلومات النظام</CardTitle>
                  <CardDescription>معلومات حول النظام والإصدار</CardDescription>
                </CardHeader>
                <CardContent>
                  <dl className="space-y-4">
                    {[
                      { label: "إصدار النظام", value: "v2.1.0" },
                      { label: "آخر تحديث", value: "2024-01-15" },
                      { label: "حالة الخادم", value: "نشط", badge: "success" as const },
                      { label: "قاعدة البيانات", value: "PostgreSQL 16", badge: "success" as const },
                      { label: "التخزين المستخدم", value: "2.4 GB / 10 GB" },
                    ].map((item, idx) => (
                      <div key={idx} className="flex items-center justify-between py-2 border-b border-border last:border-0">
                        <dt className="text-sm text-muted-foreground">{item.label}</dt>
                        <dd className="flex items-center gap-2 text-sm font-medium">
                          {item.value}
                          {item.badge && <Badge variant={item.badge}>متصل</Badge>}
                        </dd>
                      </div>
                    ))}
                  </dl>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>الصيانة</CardTitle>
                  <CardDescription>أدوات صيانة النظام</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="flex items-center justify-between p-4 rounded-lg border border-border">
                    <div>
                      <p className="font-medium">مسح ذاكرة التخزين المؤقت</p>
                      <p className="text-sm text-muted-foreground">
                        مسح البيانات المؤقتة لتسريع النظام
                      </p>
                    </div>
                    <Button variant="outline">مسح الآن</Button>
                  </div>
                  <div className="flex items-center justify-between p-4 rounded-lg border border-border">
                    <div>
                      <p className="font-medium">تصدير البيانات</p>
                      <p className="text-sm text-muted-foreground">
                        تصدير جميع بيانات النظام كنسخة احتياطية
                      </p>
                    </div>
                    <Button variant="outline">تصدير</Button>
                  </div>
                </CardContent>
              </Card>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
