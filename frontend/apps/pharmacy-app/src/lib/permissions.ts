// نظام الصلاحيات المرن (Task 42) — أنواع ومساعدات مشتركة بين القائمة الجانبية
// وصفحات التطبيق.

import type { PermissionModule, PermissionTemplate } from '@/lib/api'

export type { PermissionModule, PermissionTemplate }

/**
 * خريطة مسارات القائمة الجانبية → مفتاح الصلاحية المطلوب لرؤية القسم.
 * الترتيب مهم: المسارات الأكثر تحديدًا أولًا (/inventory/movements قبل /inventory).
 */
export const SIDEBAR_PERMISSION_ROUTES: Array<{ href: string; anyOf: string[] }> = [
  { href: '/inventory/movements', anyOf: ['inventory.movements.view', 'inventory.view'] },
  { href: '/inventory', anyOf: ['inventory.view'] },
  { href: '/pos', anyOf: ['pos.access'] },
  { href: '/sales', anyOf: ['sales.view'] },
  { href: '/customers', anyOf: ['customers.view'] },
  { href: '/employees', anyOf: ['employees.view'] },
  { href: '/attendance', anyOf: ['attendance.view'] },
  { href: '/branches', anyOf: ['branches.view'] },
  { href: '/reports', anyOf: ['reports.sales', 'reports.inventory', 'reports.movements', 'reports.financial', 'reports.employees'] },
  { href: '/', anyOf: ['dashboard.view'] },
]

/** هل يملك المفتاح أي صلاحية من المجموعة المطلوبة؟ */
export function hasAnyPermission(granted: string[] | undefined, anyOf: string[], fullAccess: boolean): boolean {
  if (fullAccess) return true
  if (!granted || granted.length === 0) return false
  return anyOf.some((key) => granted.includes(key))
}
