"use client";

import React, { useState } from "react";
import Link from "next/link";
import {
  Eye,
  EyeOff,
  Lock,
  Mail,
  AlertCircle,
  Building2,
  User,
  CheckCircle2,
  ArrowLeft,
} from "lucide-react";
import { Button } from "@/components/ui";
import { Input } from "@/components/ui";
import { ApiError, authApi } from "@/lib/api";

const PASSWORD_HINT =
  "10 أحرف على الأقل وتشمل: حرف كبير (A-Z) + حرف صغير (a-z) + رقم (0-9) + رمز خاص (!@#...)";

export default function RegisterPage() {
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [genericError, setGenericError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [formData, setFormData] = useState({
    companyName: "",
    companyEmail: "",
    firstName: "",
    lastName: "",
    email: "",
    password: "",
  });

  const setField = (key: keyof typeof formData, value: string) =>
    setFormData((prev) => ({ ...prev, [key]: value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setGenericError(null);
    setSuccessMessage(null);

    if (
      !formData.companyName ||
      !formData.companyEmail ||
      !formData.firstName ||
      !formData.lastName ||
      !formData.email ||
      !formData.password
    ) {
      setGenericError("يرجى تعبئة جميع الحقول");
      return;
    }

    setIsLoading(true);
    try {
      const response = await authApi.register({
        companyName: formData.companyName,
        companyEmail: formData.companyEmail,
        firstName: formData.firstName,
        lastName: formData.lastName,
        email: formData.email,
        password: formData.password,
      });
      setSuccessMessage(
        response?.message ||
          "تم إنشاء الحساب بنجاح. يمكنك تسجيل الدخول الآن.",
      );
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err);
      } else {
        setGenericError(err instanceof Error ? err.message : "فشل إنشاء الحساب");
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background relative overflow-hidden py-10">
      {/* Background Decorations */}
      <div className="absolute inset-0 overflow-hidden">
        <div className="absolute -top-40 -right-40 w-80 h-80 bg-primary/10 rounded-full blur-3xl animate-float" />
        <div
          className="absolute -bottom-40 -left-40 w-80 h-80 bg-primary/5 rounded-full blur-3xl animate-float"
          style={{ animationDelay: "1s" }}
        />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-gradient-to-r from-primary/5 to-transparent rounded-full blur-3xl" />
      </div>

      {/* Register Card */}
      <div className="relative w-full max-w-lg mx-4 animate-scale-in">
        {/* Logo & Header */}
        <div className="text-center mb-8">
          <Link
            href="/"
            className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-primary text-primary-foreground mb-4 shadow-lg shadow-primary/25"
          >
            <Building2 className="h-8 w-8" />
          </Link>
          <h1 className="text-3xl font-bold mb-2">
            <span className="gradient-text">Pharmacy OS</span>
          </h1>
          <p className="text-muted-foreground">
            أنشئ حساب شركتك وابدأ إدارة صيدلياتك
          </p>
        </div>

        {/* Form Card */}
        <div className="bg-card border border-border rounded-2xl shadow-xl p-8">
          {/* Success Message */}
          {successMessage && (
            <div className="mb-6 p-4 rounded-lg bg-emerald-500/10 border border-emerald-500/30 animate-fade-in">
              <div className="flex items-start gap-3">
                <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-500 mt-0.5" />
                <div className="space-y-3 w-full">
                  <p className="text-sm font-medium text-emerald-600 dark:text-emerald-400">
                    {successMessage}
                  </p>
                  <Button variant="gradient" size="lg" className="w-full" asChild>
                    <Link href="/login" className="flex items-center justify-center gap-2">
                      تسجيل الدخول الآن
                      <ArrowLeft className="h-4 w-4" />
                    </Link>
                  </Button>
                </div>
              </div>
            </div>
          )}

          {!successMessage && (
            <form onSubmit={handleSubmit} className="space-y-5">
              {/* Detailed Error */}
              {error && (
                <div
                  className="p-4 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive animate-fade-in"
                  role="alert"
                >
                  <div className="flex items-start gap-3">
                    <AlertCircle className="h-5 w-5 shrink-0 mt-0.5" />
                    <div className="w-full space-y-2">
                      <p className="text-sm font-semibold">{error.message}</p>
                      <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-[11px] text-muted-foreground">
                        <span>
                          النوع: <b className="font-mono">{error.kind}</b>
                        </span>
                        <span>
                          الحالة: <b className="font-mono">{error.status ?? "—"}</b>
                        </span>
                        <span className="col-span-2">
                          الكود: <b className="font-mono">{error.code ?? "—"}</b>
                        </span>
                        {error.requestId && (
                          <span className="col-span-2">
                            request_id: <b className="font-mono">{error.requestId}</b>
                          </span>
                        )}
                      </div>
                      <details className="rounded-md bg-background/60 p-2">
                        <summary className="cursor-pointer text-xs font-medium">
                          التفاصيل التقنية الكاملة
                        </summary>
                        <pre
                          className="mt-2 max-h-40 overflow-auto whitespace-pre-wrap break-all text-[11px] leading-5 text-muted-foreground"
                          dir="ltr"
                        >
                          {JSON.stringify(error.toJSON(), null, 2)}
                        </pre>
                      </details>
                    </div>
                  </div>
                </div>
              )}

              {!error && genericError && (
                <div className="flex items-center gap-3 p-4 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive animate-fade-in">
                  <AlertCircle className="h-5 w-5 shrink-0" />
                  <p className="text-sm">{genericError}</p>
                </div>
              )}

              {/* Company Name */}
              <Input
                type="text"
                placeholder="اسم الشركة / الصيدلية"
                label="اسم الشركة"
                icon={<Building2 className="h-4 w-4" />}
                value={formData.companyName}
                onChange={(e) => setField("companyName", e.target.value)}
              />

              {/* Company Email */}
              <Input
                type="email"
                placeholder="البريد الرسمي للشركة"
                label="بريد الشركة"
                icon={<Mail className="h-4 w-4" />}
                value={formData.companyEmail}
                onChange={(e) => setField("companyEmail", e.target.value)}
                dir="ltr"
                className="text-left"
              />

              {/* Owner Names */}
              <div className="grid grid-cols-2 gap-4">
                <Input
                  type="text"
                  placeholder="الاسم الأول"
                  label="الاسم الأول"
                  icon={<User className="h-4 w-4" />}
                  value={formData.firstName}
                  onChange={(e) => setField("firstName", e.target.value)}
                />
                <Input
                  type="text"
                  placeholder="اسم العائلة"
                  label="اسم العائلة"
                  value={formData.lastName}
                  onChange={(e) => setField("lastName", e.target.value)}
                />
              </div>

              {/* Login Email */}
              <Input
                type="email"
                placeholder="البريد المستخدم لتسجيل الدخول"
                label="بريد المالك (للدخول)"
                icon={<Mail className="h-4 w-4" />}
                value={formData.email}
                onChange={(e) => setField("email", e.target.value)}
                dir="ltr"
                className="text-left"
              />

              {/* Password */}
              <div className="space-y-2">
                <label className="text-sm font-medium text-foreground/80">
                  كلمة المرور
                </label>
                <div className="relative">
                  <Lock className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <input
                    type={showPassword ? "text" : "password"}
                    placeholder="أدخل كلمة مرور قوية"
                    value={formData.password}
                    onChange={(e) => setField("password", e.target.value)}
                    dir="ltr"
                    className="flex h-10 w-full rounded-lg border border-input bg-background pl-12 pr-10 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 transition-all duration-200"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors"
                  >
                    {showPassword ? (
                      <EyeOff className="h-4 w-4" />
                    ) : (
                      <Eye className="h-4 w-4" />
                    )}
                  </button>
                </div>
                <p className="text-xs text-muted-foreground leading-5">
                  {PASSWORD_HINT}
                </p>
              </div>

              {/* Submit */}
              <Button
                type="submit"
                variant="gradient"
                size="lg"
                className="w-full"
                loading={isLoading}
              >
                {isLoading ? "جاري إنشاء الحساب..." : "إنشاء حساب الشركة"}
              </Button>
            </form>
          )}

          {/* Divider + Login Link */}
          <div className="relative my-6">
            <div className="absolute inset-0 flex items-center">
              <span className="w-full border-t border-border" />
            </div>
            <div className="relative flex justify-center text-xs uppercase">
              <span className="bg-card px-2 text-muted-foreground">لديك حساب؟</span>
            </div>
          </div>

          <Button variant="outline" size="lg" className="w-full" asChild>
            <Link href="/login">العودة لتسجيل الدخول</Link>
          </Button>
        </div>

        <p className="mt-6 text-center text-xs text-muted-foreground">
          سيكون حسابك حساب مالك الشركة — لدخول الموظفين استخدم بوابة الصيدلية
        </p>
      </div>
    </div>
  );
}
