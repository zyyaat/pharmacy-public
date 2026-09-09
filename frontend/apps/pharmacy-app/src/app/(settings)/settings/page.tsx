import { redirect } from 'next/navigation'

/** مدخل الإعدادات — يوجّه لقسم الفواتير والطباعة افتراضياً */
export default function SettingsIndexPage() {
  redirect('/settings/receipts')
}
