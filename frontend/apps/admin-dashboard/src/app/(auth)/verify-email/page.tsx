"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ApiError, authApi } from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";
import { getSafeRedirectPath } from "@/lib/navigation";

export default function VerifyEmailPage() {
  const router = useRouter();
  const { user, loading: authLoading } = useAuth();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [message, setMessage] = useState("أدخل رمز التحقق المكوّن من 6 أرقام");
  const [error, setError] = useState("");
  const [sending, setSending] = useState(false);
  const [verifying, setVerifying] = useState(false);

  useEffect(() => {
    if (!authLoading && user) {
      router.replace(getSafeRedirectPath(new URLSearchParams(window.location.search).get("next")));
    }
  }, [authLoading, router, user]);

  useEffect(() => {
    if (authLoading || user) return;
    const pendingEmail = new URLSearchParams(window.location.search).get("email")?.trim() || "";
    setEmail(pendingEmail);
    if (!pendingEmail) return;

    let cancelled = false;
    setSending(true);
    void authApi.resendVerification(pendingEmail)
      .then((response) => {
        if (cancelled) return;
        setError("");
        setMessage(
          response.sent === false
            ? "يوجد رمز تحقق صالح بالفعل. استخدم آخر رمز أُرسل إلى بريدك الإلكتروني."
            : "تم إرسال رمز تحقق جديد إلى بريدك الإلكتروني.",
        );
      })
      .catch((resendError) => {
        if (cancelled) return;
        setError(
          resendError instanceof ApiError
            ? resendError.message
            : "تعذر إرسال رمز التحقق الآن",
        );
      })
      .finally(() => {
        if (!cancelled) setSending(false);
      });
    return () => {
      cancelled = true;
    };
  }, [authLoading, user]);

  async function verifyEmail(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!email || !/^\d{6}$/.test(code)) {
      setError("أدخل البريد الإلكتروني ورمز التحقق المكوّن من 6 أرقام");
      return;
    }
    setVerifying(true);
    setError("");
    try {
      await authApi.verifyEmail(email, code);
      setMessage("تم تأكيد البريد بنجاح. يمكنك تسجيل الدخول الآن.");
      setCode("");
    } catch (verificationError) {
      setError(
        verificationError instanceof ApiError
          ? verificationError.message
          : "تعذر تأكيد البريد الإلكتروني",
      );
    } finally {
      setVerifying(false);
    }
  }

  async function resendVerification() {
    if (!email || sending) return;
    setSending(true);
    setError("");
    try {
      const response = await authApi.resendVerification(email);
      setMessage(
        response.sent === false
          ? "يوجد رمز تحقق صالح بالفعل. استخدم آخر رمز أُرسل إلى بريدك الإلكتروني."
          : "تم إرسال رمز تحقق جديد. تحقق من صندوق الوارد والرسائل غير المرغوب فيها.",
      );
    } catch (resendError) {
      setError(
        resendError instanceof ApiError
          ? resendError.message
          : "تعذر إرسال رمز التحقق الآن",
      );
    } finally {
      setSending(false);
    }
  }

  if (authLoading || user) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background text-muted-foreground">
        جاري التحقق من الجلسة...
      </div>
    );
  }

  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4 py-8" dir="rtl">
      <section className="relative w-full max-w-lg rounded-3xl border border-border bg-card p-8 text-center shadow-2xl sm:p-12">
        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 text-2xl font-black text-primary">
          ✓
        </div>
        <p className="mt-6 text-sm font-medium text-primary">Pharmacy OS</p>
        <h1 className="mt-3 text-2xl font-bold leading-relaxed">تأكيد البريد الإلكتروني</h1>
        <p className={`mt-3 text-sm leading-7 ${error ? "text-destructive" : "text-muted-foreground"}`}>
          {error || message}
        </p>

        <form className="mt-8 space-y-4 text-right" onSubmit={verifyEmail}>
          <label className="block">
            <span className="mb-2 block text-sm font-medium">البريد الإلكتروني</span>
            <input
              className="h-12 w-full rounded-xl border border-input bg-background px-4 text-left text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10"
              dir="ltr"
              type="email"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </label>
          <label className="block">
            <span className="mb-2 block text-sm font-medium">رمز التحقق</span>
            <input
              className="h-14 w-full rounded-xl border border-input bg-background px-4 text-center text-2xl font-bold tracking-[0.6em] outline-none focus:border-primary focus:ring-4 focus:ring-primary/10"
              dir="ltr"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              pattern="[0-9]{6}"
              required
              value={code}
              onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
              placeholder="000000"
            />
          </label>
          <button
            className="h-12 w-full rounded-xl bg-primary text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60"
            type="submit"
            disabled={verifying}
          >
            {verifying ? "جاري التأكيد..." : "تأكيد البريد"}
          </button>
        </form>

        <button
          className="mt-4 text-sm font-medium text-primary hover:underline disabled:cursor-not-allowed disabled:opacity-50"
          type="button"
          onClick={resendVerification}
          disabled={!email || sending}
        >
          {sending ? "جاري إرسال الرمز..." : "إعادة إرسال رمز التحقق"}
        </button>

        <Link className="mt-8 inline-flex h-11 items-center rounded-xl border border-border px-6 text-sm font-semibold transition hover:bg-muted" href="/login">
          العودة إلى تسجيل الدخول
        </Link>
      </section>
    </main>
  );
}