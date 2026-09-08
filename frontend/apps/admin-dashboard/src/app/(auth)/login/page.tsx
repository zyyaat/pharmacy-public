"use client";

import React, { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { 
  Eye, 
  EyeOff, 
  Lock, 
  Mail, 
  ArrowLeft,
  AlertCircle,
} from "lucide-react";
import { Button } from "@/components/ui";
import { Input } from "@/components/ui";
import { useAuth } from "@/hooks/useAuth";
import { ApiError } from "@/lib/api";
import { getSafeRedirectPath } from "@/lib/navigation";

export default function LoginPage() {
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();
  const { login, user, loading: authLoading } = useAuth();
  const [redirectPath, setRedirectPath] = useState<string | null>(null);
  const [formData, setFormData] = useState({
    email: "",
    password: "",
    rememberMe: false,
  });

  useEffect(() => {
    setRedirectPath(
      getSafeRedirectPath(new URLSearchParams(window.location.search).get("next")),
    );
  }, []);

  useEffect(() => {
    if (!authLoading && user && redirectPath) {
      router.replace(redirectPath);
    }
  }, [authLoading, redirectPath, router, user]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    
    // Validation
    if (!formData.email || !formData.password) {
      setError("يرجى إدخال البريد الإلكتروني وكلمة المرور");
      return;
    }

    setIsLoading(true);
    
    try {
      await login({ email: formData.email, password: formData.password });
      router.replace(redirectPath || "/");
    } catch (err) {
      if (err instanceof ApiError && err.code === "EMAIL_NOT_VERIFIED") {
        router.replace(`/verify-email?email=${encodeURIComponent(formData.email.trim())}`);
        return;
      }
      setError(err instanceof Error ? err.message : "فشل تسجيل الدخول");
    } finally {
      setIsLoading(false);
    }
  };

  if (authLoading || (user && redirectPath)) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background text-muted-foreground">
        جاري التحقق من الجلسة...
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background relative overflow-hidden">
      {/* Background Decorations */}
      <div className="absolute inset-0 overflow-hidden">
        <div className="absolute -top-40 -right-40 w-80 h-80 bg-primary/10 rounded-full blur-3xl animate-float" />
        <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-primary/5 rounded-full blur-3xl animate-float" style={{ animationDelay: "1s" }} />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-gradient-to-r from-primary/5 to-transparent rounded-full blur-3xl" />
      </div>

      {/* Login Card */}
      <div className="relative w-full max-w-md mx-4 animate-scale-in">
        {/* Logo & Header */}
        <div className="text-center mb-8">
          <Link href="/" className="mb-4 inline-flex items-center justify-center" aria-label="Pharmacy OS - الرئيسية">
            <img
              src="/brand/pharmacy-os-logo-light.svg"
              alt="Pharmacy OS"
              className="h-16 w-auto dark:hidden"
              width="260"
              height="64"
            />
            <img
              src="/brand/pharmacy-os-logo-dark.svg"
              alt="Pharmacy OS"
              className="hidden h-16 w-auto dark:block"
              width="260"
              height="64"
            />
          </Link>
          <p className="text-muted-foreground">
            مرحباً بعودتك! سجّل دخولك للوحة التحكم
          </p>
        </div>

        {/* Login Form */}
        <div className="bg-card border border-border rounded-2xl shadow-xl p-8">
          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Error Message */}
            {error && (
              <div className="flex items-center gap-3 p-4 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive animate-fade-in">
                <AlertCircle className="h-5 w-5 shrink-0" />
                <p className="text-sm">{error}</p>
              </div>
            )}

            {/* Email Field */}
            <Input
              type="email"
              placeholder="البريد الإلكتروني"
              label="البريد الإلكتروني"
              icon={<Mail className="h-4 w-4" />}
              value={formData.email}
              onChange={(e) => setFormData({ ...formData, email: e.target.value })}
              dir="ltr"
              className="text-left"
            />

            {/* Password Field */}
            <div className="space-y-2">
              <label className="text-sm font-medium text-foreground/80">
                كلمة المرور
              </label>
              <div className="relative">
                <Lock className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <input
                  type={showPassword ? "text" : "password"}
                  placeholder="أدخل كلمة المرور"
                  value={formData.password}
                  onChange={(e) => setFormData({ ...formData, password: e.target.value })}
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
            </div>

            {/* Remember Me & Forgot Password */}
            <div className="flex items-center justify-between">
              <label className="flex items-center gap-2 cursor-pointer group">
                <input
                  type="checkbox"
                  checked={formData.rememberMe}
                  onChange={(e) => setFormData({ ...formData, rememberMe: e.target.checked })}
                  className="w-4 h-4 rounded border-border text-primary focus:ring-primary transition-colors"
                />
                <span className="text-sm text-muted-foreground group-hover:text-foreground transition-colors">
                  تذكرني
                </span>
              </label>
              <Link
                href="/forgot-password"
                className="text-sm text-primary hover:text-primary/80 transition-colors"
              >
                نسيت كلمة المرور؟
              </Link>
            </div>

            {/* Submit Button */}
            <Button
              type="submit"
              variant="gradient"
              size="lg"
              className="w-full"
              loading={isLoading}
            >
              {isLoading ? "جاري تسجيل الدخول..." : "تسجيل الدخول"}
            </Button>

            {/* Divider */}
            <div className="relative my-6">
              <div className="absolute inset-0 flex items-center">
                <span className="w-full border-t border-border" />
              </div>
              <div className="relative flex justify-center text-xs uppercase">
                <span className="bg-card px-2 text-muted-foreground">
                  أو
                </span>
              </div>
            </div>

            {/* SSO / OAuth Options (Future) */}
            <div className="grid grid-cols-2 gap-3">
              <Button variant="outline" type="button" disabled>
                <svg className="h-4 w-4 ml-2" viewBox="0 0 24 24">
                  <path fill="currentColor" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"/>
                  <path fill="currentColor" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                  <path fill="currentColor" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22z"/>
                  <path fill="currentColor" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                </svg>
                Google
              </Button>
              <Button variant="outline" type="button" disabled>
                <svg className="h-4 w-4 ml-2" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
                </svg>
                GitHub
              </Button>
            </div>
          </form>
        </div>

        {/* Footer Links */}
        <div className="mt-6 text-center">
          <p className="text-sm text-muted-foreground">
            ليس لديك حساب؟{" "}
            <Link
              href="/register"
              className="text-primary hover:text-primary/80 font-medium transition-colors"
            >
              تواصل مع المدير
            </Link>
          </p>
        </div>

        {/* Back to Home */}
        <div className="mt-4 text-center">
          <Link
            href="/"
            className="inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            <ArrowLeft className="h-4 w-4" />
            العودة للرئيسية
          </Link>
        </div>
      </div>
    </div>
  );
}
