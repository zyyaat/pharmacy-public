"use client";

// رمز تحقق عصري: 6 مربعات منفصلة جنب بعض بدل الخانة الواحدة الواسعة.
// السلوك: تقدم تلقائي للخانة التالية، مسح للخلف يعود للخانة السابقة،
// أسهم يمين/يسار للتنقل، ولصق الرمز كاملًا (أو تعبئة لوحة المفاتيح
// التلقائية one-time-code) يوزع الأرقام من البداية.
// القيمة الخارجية تبقى نص الرمز كما كان (value/onChange) فلا يتغير
// منطق الصفحات المستدعية إطلاقًا.
import { ClipboardEvent, KeyboardEvent, useEffect, useRef, useState } from "react";

type OtpInputProps = {
  value: string;
  onChange: (value: string) => void;
  length?: number;
  disabled?: boolean;
  hasError?: boolean;
};

export default function OtpInput({
  value,
  onChange,
  length = 6,
  disabled = false,
  hasError = false,
}: OtpInputProps) {
  const inputsRef = useRef<Array<HTMLInputElement | null>>([]);
  const [digits, setDigits] = useState<string[]>(() => Array.from({ length }, () => ""));
  const digitsRef = useRef(digits);
  digitsRef.current = digits;

  // مزامنة التغييرات الخارجية فقط: تصفير كامل ("") أو رمز كامل مكتمل —
  // حتى لا ينهار ترتيب الخانات عند وجود فراغات أثناء الكتابة الجزئية.
  useEffect(() => {
    const joined = digitsRef.current.join("");
    if (value === joined) return;
    if (value === "" || new RegExp(`^\\d{${length}}$`).test(value)) {
      setDigits(Array.from({ length }, (_, index) => value[index] ?? ""));
    }
  }, [value, length]);

  function focusAt(index: number) {
    const clamped = Math.max(0, Math.min(length - 1, index));
    const element = inputsRef.current[clamped];
    if (!element) return;
    element.focus();
    element.select();
  }

  function applyDigits(next: string[], focusIndex?: number) {
    setDigits(next);
    onChange(next.join(""));
    if (focusIndex !== undefined) focusAt(focusIndex);
  }

  function handleChange(index: number, raw: string) {
    const input = raw.replace(/\D/g, "");
    const current = digitsRef.current.slice();
    const previous = current[index] ?? "";
    if (!input) {
      current[index] = "";
      applyDigits(current);
      return;
    }
    if (input.length > previous.length + 1) {
      // لصق أو تعبئة تلقائية لرمز كامل: وزّع الأرقام من الخانة الأولى
      const next = Array.from({ length }, (_, index) => input[index] ?? "");
      applyDigits(next, Math.min(input.length, length - 1));
      return;
    }
    // محرف واحد (أو كتابة فوق رقم موجود): خذ آخر محرف وتقدم للخانة التالية
    current[index] = input[input.length - 1] ?? "";
    applyDigits(current, index < length - 1 ? index + 1 : undefined);
  }

  function handleKeyDown(index: number, event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Backspace") {
      event.preventDefault();
      const current = digitsRef.current.slice();
      if (current[index]) {
        current[index] = "";
        applyDigits(current);
      } else if (index > 0) {
        current[index - 1] = "";
        applyDigits(current, index - 1);
      }
      return;
    }
    if (event.key === "ArrowLeft") {
      event.preventDefault();
      focusAt(index - 1);
    }
    if (event.key === "ArrowRight") {
      event.preventDefault();
      focusAt(index + 1);
    }
  }

  function handlePaste(event: ClipboardEvent<HTMLInputElement>) {
    event.preventDefault();
    const text = event.clipboardData.getData("text").replace(/\D/g, "");
    if (!text) return;
    applyDigits(
      Array.from({ length }, (_, index) => text[index] ?? ""),
      Math.min(text.length, length - 1),
    );
  }

  return (
    <div className="flex justify-center gap-2 sm:gap-3" dir="ltr" role="group">
      {digits.map((digit, index) => (
        <input
          key={index}
          ref={(element) => {
            inputsRef.current[index] = element;
          }}
          className={`h-14 w-11 rounded-xl border bg-background text-center text-2xl font-bold outline-none transition focus:ring-4 disabled:cursor-not-allowed disabled:opacity-60 sm:w-12 ${
            hasError
              ? "border-destructive text-destructive focus:border-destructive focus:ring-destructive/10"
              : digit
                ? "border-primary/50 bg-primary/5 focus:border-primary focus:ring-primary/10"
                : "border-input focus:border-primary focus:ring-primary/10"
          }`}
          type="text"
          dir="ltr"
          inputMode="numeric"
          autoComplete={index === 0 ? "one-time-code" : "off"}
          pattern="[0-9]*"
          disabled={disabled}
          value={digit}
          aria-label={`Digit ${index + 1}`}
          onChange={(event) => handleChange(index, event.target.value)}
          onKeyDown={(event) => handleKeyDown(index, event)}
          onPaste={handlePaste}
          onFocus={(event) => event.target.select()}
        />
      ))}
    </div>
  );
}
