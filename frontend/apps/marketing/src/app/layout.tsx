import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Pharmacy OS — إدارة صيدليتك بذكاء',
  description: 'منصة تشغيل حديثة لإدارة الصيدليات والفروع والموظفين والمخزون.',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="ar" dir="rtl">
      <body>{children}</body>
    </html>
  )
}
