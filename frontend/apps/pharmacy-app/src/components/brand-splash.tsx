'use client';

import { useEffect, useRef, useState } from 'react';
import './brand-splash.css';

export type BrandSplashVariant = 'wiggle' | 'pulse';

export interface BrandSplashProps {
  /** false = يشغّل أنيميشن الخروج الناعم ثم يختفي */
  show?: boolean;
  /** مسار شعار التطبيق (png / svg) — الافتراضي أيقونة Pharmacy OS */
  logoSrc?: string;
  /** اسم التطبيق اللي يظهر تحت الأيقونة */
  title?: string;
  /** سطر فرعي صغير تحت الاسم (اختياري) */
  subtitle?: string;
  /** wiggle = اهتزاز عصري | pulse = نبض هادئ */
  variant?: BrandSplashVariant;
  /** true = يملأ العنصر الأب بدل ملء الشاشة (للبريفيو أو داخل صفحات) */
  inline?: boolean;
}

const EXIT_MS = 560;

/** مارك Pharmacy OS مدمج — يُستخدم تلقائياً عند عدم تمرير logoSrc */
function PharmacyOSMark() {
  return (
    <svg viewBox="0 0 128 128" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
      <g transform="rotate(-5 64 64)">
        <rect width="128" height="128" rx="30" fill="#00d084" />
        <rect x="42" y="43" width="14" height="45" rx="7" fill="#06100d" />
        <rect x="61" y="32" width="14" height="67" rx="7" fill="#06100d" />
        <rect x="80" y="43" width="14" height="45" rx="7" fill="#06100d" />
      </g>
    </svg>
  );
}

/**
 * BrandSplash — شاشة افتتاحية بهوية Pharmacy OS تُعرض أثناء التحقق من الجلسة
 * أو تحميل الصفحة، بدل الرسائل التقنية مثل «جاري التحقق من الجلسة».
 *
 * الاستخدام (سطر واحد):
 *   {checking && <BrandSplash />}
 *   أو الأفضل مع خروج ناعم تلقائي:
 *   <BrandSplash show={checking} />
 */
export function BrandSplash({
  show = true,
  logoSrc,
  title = 'Pharmacy OS',
  subtitle,
  variant = 'wiggle',
  inline = false,
}: BrandSplashProps) {
  const [render, setRender] = useState(show);
  const [exiting, setExiting] = useState(false);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);

  useEffect(() => {
    if (show) {
      timers.current.forEach(clearTimeout);
      timers.current = [];
      setRender(true);
      setExiting(false);
      return;
    }
    // show → false: تشغيل أنيميشن الخروج ثم الإزالة من الـ DOM
    setExiting(true);
    const t = setTimeout(() => {
      setRender(false);
      setExiting(false);
    }, EXIT_MS);
    timers.current.push(t);
    return () => clearTimeout(t);
  }, [show]);

  if (!render) return null;

  const classes = [
    'bs-root',
    inline ? 'bs-inline' : '',
    exiting ? 'bs-exiting' : '',
    variant === 'pulse' ? 'bs-variant-pulse' : '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <div className={classes} role="status" aria-live="polite" aria-label="جارٍ التحميل">
      <span className="bs-orb bs-orb-1" />
      <span className="bs-orb bs-orb-2" />
      <span className="bs-orb bs-orb-3" />

      <div className="bs-stage">
        <span className="bs-glow" />
        <span className="bs-ring" />
        <span className="bs-ring bs-ring-2" />
        <div className="bs-icon">
          {logoSrc ? (
            <img src={logoSrc} alt={title || 'شعار التطبيق'} />
          ) : (
            <PharmacyOSMark />
          )}
        </div>
      </div>

      {title ? <h1 className="bs-title">{title}</h1> : null}
      {subtitle ? <p className="bs-subtitle">{subtitle}</p> : null}

      <div className="bs-dots" aria-hidden="true">
        <span className="bs-dot" />
        <span className="bs-dot" />
        <span className="bs-dot" />
      </div>
    </div>
  );
}

export default BrandSplash;
