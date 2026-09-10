import { type ClassValue, clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'
import { fmtDate } from '@/i18n/format'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDate(date: Date): string {
  return fmtDate(date)
}
