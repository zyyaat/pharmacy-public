"use client";

import React, { useEffect, useState } from "react";
import {
  User,
  Bell,
  Shield,
  Palette,
  Globe,
  Languages,
  Database,
  Key,
  Save,
  RefreshCw,
  CheckCircle,
  AlertCircle,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui";
import { LanguageSetting } from "@/components/settings/language-setting";
import { Button } from "@/components/ui";
import { Input } from "@/components/ui";
import { Badge } from "@/components/ui";
import { Select } from "@/components/ui";
import { platformSettingsApi } from "@/lib/api";
import { useT } from "@/i18n/provider";

type SettingsTab = "profile" | "notifications" | "security" | "appearance" | "system" | "language";

export default function SettingsPage() {
  const t = useT("settings");
  const [activeTab, setActiveTab] = useState<SettingsTab>("profile");
  const [saved, setSaved] = useState(false);
  const [saving, setSaving] = useState(false);
  const [trialDays, setTrialDays] = useState(30);
  const [trialSettingsLoading, setTrialSettingsLoading] = useState(false);
  const [trialSettingsError, setTrialSettingsError] = useState("");

  useEffect(() => {
    if (activeTab !== "system") return;
    setTrialSettingsLoading(true);
    platformSettingsApi.getTrialSettings()
      .then((settings) => {
        setTrialDays(settings.default_trial_days || 30);
        setTrialSettingsError("");
      })
      .catch(() => setTrialSettingsError(t("trial_load_failed")))
      .finally(() => setTrialSettingsLoading(false));
  }, [activeTab, t]);

  const handleSave = async () => {
    setSaving(true);
    try {
      if (activeTab === "system") {
        const settings = await platformSettingsApi.updateTrialSettings(trialDays);
        setTrialDays(settings.default_trial_days);
      } else {
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch {
      setTrialSettingsError(t("trial_save_failed"));
    } finally {
      setSaving(false);
    }
  };

  const tabs: { id: SettingsTab; label: string; icon: React.ReactNode }[] = [
    { id: "profile", label: t("tab_profile"), icon: <User className="h-4 w-4" /> },
    { id: "language", label: t("tab_language"), icon: <Languages className="h-4 w-4" /> },
    { id: "notifications", label: t("tab_notifications"), icon: <Bell className="h-4 w-4" /> },
    { id: "security", label: t("tab_security"), icon: <Shield className="h-4 w-4" /> },
    { id: "appearance", label: t("tab_appearance"), icon: <Palette className="h-4 w-4" /> },
    { id: "system", label: t("tab_system"), icon: <Database className="h-4 w-4" /> },
  ];

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
        <div className="flex gap-2">
          {saved && (
            <Badge variant="success" className="animate-fade-in">
              <CheckCircle className="h-3 w-3 me-1" />
              {t("saved")}
            </Badge>
          )}
          <Button variant="outline" onClick={handleSave} disabled={saving}>
            {saving ? (
              <>
                <RefreshCw className="h-4 w-4 me-2 animate-spin" />
                {t("saving")}
              </>
            ) : (
              <>
                <Save className="h-4 w-4 me-2" />
                {t("save_changes")}
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
                  className={`w-full flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium transition-all text-start ${
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
                <CardTitle>{t("profile_title")}</CardTitle>
                <CardDescription>{t("profile_desc")}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                {/* Avatar Section */}
                <div className="flex items-center gap-6">
                  <div className="w-24 h-24 rounded-2xl bg-primary/10 flex items-center justify-center text-primary text-3xl font-bold">
                    {t("profile_avatar_letter")}
                  </div>
                  <div className="space-y-2">
                    <Button variant="outline" size="sm">
                      {t("change_photo")}
                    </Button>
                    <p className="text-xs text-muted-foreground">
                      {t("photo_hint")}
                    </p>
                  </div>
                </div>

                {/* Form */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <Input label={t("full_name")} defaultValue={t("default_name")} />
                  <Input label={t("email")} type="email" defaultValue="admin@pharmacy.os" dir="ltr" className="text-left" />
                  <Input label={t("phone")} type="tel" defaultValue="+966 50 000 0000" dir="ltr" className="text-left" />
                  <Input label={t("job_title")} defaultValue={t("default_name")} />
                </div>

                <div>
                  <label className="text-sm font-medium mb-2 block">{t("bio")}</label>
                  <textarea
                    rows={4}
                    className="w-full px-4 py-3 rounded-lg border border-input bg-background text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring resize-none transition-all"
                    defaultValue={t("default_bio")}
                  />
                </div>
              </CardContent>
            </Card>
          )}

          {/* Language Tab (Task 48) — متاح دائمًا بلا صلاحيات */}
          {activeTab === "language" && <LanguageSetting />}

          {/* Notifications Tab */}
          {activeTab === "notifications" && (
            <Card>
              <CardHeader>
                <CardTitle>{t("notifications_title")}</CardTitle>
                <CardDescription>{t("notifications_desc")}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                {[
                  {
                    title: t("notif_email_title"),
                    description: t("notif_email_desc"),
                    options: [t("notif_email_opt_companies"), t("notif_email_opt_users"), t("notif_email_opt_reports")],
                  },
                  {
                    title: t("notif_browser_title"),
                    description: t("notif_browser_desc"),
                    options: [t("notif_browser_opt_logins"), t("notif_browser_opt_updates"), t("notif_browser_opt_alerts")],
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
                            className="w-11 h-6 bg-primary rounded-full appearance-none cursor-pointer relative before:content-[''] before:absolute before:top-0.5 before:start-0.5 before:w-5 before:h-5 before:bg-white before:rounded-full before:transition-transform rtl:checked:before:translate-x-5 ltr:checked:before:-translate-x-5"
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
                  <CardTitle>{t("password_title")}</CardTitle>
                  <CardDescription>{t("password_desc")}</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <Input label={t("current_password")} type="password" />
                  <Input label={t("new_password")} type="password" />
                  <Input label={t("confirm_password")} type="password" />
                  <Button variant="gradient">{t("update_password")}</Button>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>{t("two_fa_title")}</CardTitle>
                  <CardDescription>{t("two_fa_desc")}</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="flex items-center justify-between p-4 rounded-lg border border-border">
                    <div className="flex items-center gap-3">
                      <Key className="h-5 w-5 text-muted-foreground" />
                      <div>
                        <p className="font-medium">{t("two_fa_label")}</p>
                        <p className="text-sm text-muted-foreground">
                          {t("two_fa_disabled")}
                        </p>
                      </div>
                    </div>
                    <Button variant="outline">{t("two_fa_enable")}</Button>
                  </div>
                </CardContent>
              </Card>

              <Card className="border-destructive/20">
                <CardHeader>
                  <CardTitle className="text-destructive">{t("danger_title")}</CardTitle>
                  <CardDescription>{t("danger_desc")}</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="flex items-center justify-between p-4 rounded-lg border border-destructive/20 bg-destructive/5">
                    <div className="flex items-center gap-3">
                      <AlertCircle className="h-5 w-5 text-destructive" />
                      <div>
                        <p className="font-medium">{t("delete_account")}</p>
                        <p className="text-sm text-muted-foreground">
                          {t("delete_account_desc")}
                        </p>
                      </div>
                    </div>
                    <Button variant="destructive">{t("delete_account")}</Button>
                  </div>
                </CardContent>
              </Card>
            </div>
          )}

          {/* Appearance Tab */}
          {activeTab === "appearance" && (
            <Card>
              <CardHeader>
                <CardTitle>{t("appearance_title")}</CardTitle>
                <CardDescription>{t("appearance_desc")}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div>
                  <h3 className="font-medium mb-3">{t("mode")}</h3>
                  <div className="grid grid-cols-3 gap-4">
                    {[
                      { id: "light", name: t("theme_light"), desc: t("theme_light_desc") },
                      { id: "dark", name: t("theme_dark"), desc: t("theme_dark_desc") },
                      { id: "system", name: t("theme_system"), desc: t("theme_system_desc") },
                    ].map((theme) => (
                      <button
                        key={theme.id}
                        className="p-4 rounded-xl border border-border hover:border-primary/50 transition-all text-start group"
                      >
                        <div className={`w-full aspect-video rounded-lg mb-3 ${theme.id === "dark" ? "bg-gray-900" : theme.id === "system" ? "bg-gradient-to-b from-white to-gray-900" : "bg-gray-100"}`} />
                        <p className="font-medium text-sm">{theme.name}</p>
                        <p className="text-xs text-muted-foreground">{theme.desc}</p>
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <h3 className="font-medium mb-3">{t("appearance_language")}</h3>
                  <div className="w-full max-w-xs">
                    <Select
                      defaultValue="ar"
                      aria-label={t("language_aria")}
                      options={[
                        { value: "ar", label: "العربية" },
                        { value: "en", label: "English" },
                      ]}
                    />
                  </div>
                </div>
              </CardContent>
            </Card>
          )}

          {/* System Tab */}
          {activeTab === "system" && (
            <div className="space-y-6">
              <Card>
                <CardHeader>
                  <CardTitle>{t("trial_title")}</CardTitle>
                  <CardDescription>
                    {t("trial_desc")}
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="max-w-sm">
                    <Input
                      label={t("trial_days_label")}
                      type="number"
                      min={1}
                      max={3650}
                      value={trialDays}
                      onChange={(event) => setTrialDays(Number(event.target.value))}
                      disabled={trialSettingsLoading}
                      dir="ltr"
                      className="text-left"
                    />
                  </div>
                  {trialSettingsError && (
                    <p className="text-sm text-destructive">{trialSettingsError}</p>
                  )}
                  <p className="text-xs text-muted-foreground">
                    {t("trial_note")}
                  </p>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>{t("system_info_title")}</CardTitle>
                  <CardDescription>{t("system_info_desc")}</CardDescription>
                </CardHeader>
                <CardContent>
                  <dl className="space-y-4">
                    {[
                      { label: t("info_version"), value: "v2.1.0" },
                      { label: t("info_last_update"), value: "2024-01-15" },
                      { label: t("info_server_status"), value: t("info_server_active"), badge: "success" as const },
                      { label: t("info_database"), value: "PostgreSQL 16", badge: "success" as const },
                      { label: t("info_storage"), value: "2.4 GB / 10 GB" },
                    ].map((item, idx) => (
                      <div key={idx} className="flex items-center justify-between py-2 border-b border-border last:border-0">
                        <dt className="text-sm text-muted-foreground">{item.label}</dt>
                        <dd className="flex items-center gap-2 text-sm font-medium">
                          {item.value}
                          {item.badge && <Badge variant={item.badge}>{t("badge_connected")}</Badge>}
                        </dd>
                      </div>
                    ))}
                  </dl>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>{t("maintenance_title")}</CardTitle>
                  <CardDescription>{t("maintenance_desc")}</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="flex items-center justify-between p-4 rounded-lg border border-border">
                    <div>
                      <p className="font-medium">{t("clear_cache")}</p>
                      <p className="text-sm text-muted-foreground">
                        {t("clear_cache_desc")}
                      </p>
                    </div>
                    <Button variant="outline">{t("clear_now")}</Button>
                  </div>
                  <div className="flex items-center justify-between p-4 rounded-lg border border-border">
                    <div>
                      <p className="font-medium">{t("export_data")}</p>
                      <p className="text-sm text-muted-foreground">
                        {t("export_data_desc")}
                      </p>
                    </div>
                    <Button variant="outline">{t("export_now")}</Button>
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
