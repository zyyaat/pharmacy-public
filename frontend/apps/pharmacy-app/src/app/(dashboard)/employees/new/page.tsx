'use client'

// المسار القديم /employees/new أصبح نافذة داخل صفحة الموظفين نفسها —
// نعيد التوجيه لتفادي صفحة معلقة بلا وظيفة.
import { useEffect } from 'react'
import { useRouter } from 'next/navigation'

export default function NewEmployeePage() {
  const router = useRouter()
  useEffect(() => {
    router.replace('/employees')
  }, [router])
  return null
}
