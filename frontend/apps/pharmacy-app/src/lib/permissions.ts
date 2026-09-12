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

/**
 * الصلاحية المطلوبة لكل صفحة (Task 43 — حماية المسارات من الدخول المباشر).
 * نفس مفاتيح القائمة الجانبية كي لا يظهر ما لا يمكن فتحه، ولا يُمنع ما ظاهر.
 */
export const PAGE_PERMISSIONS: Record<string, string[]> = {
  '/': ['dashboard.view'],
  '/pos': ['pos.access'],
  '/sales': ['sales.view'],
  '/customers': ['customers.view'],
  '/employees': ['employees.view'],
  '/attendance': ['attendance.view'],
  '/branches': ['branches.view'],
  '/inventory': ['inventory.view'],
  '/inventory/movements': ['inventory.movements.view'],
  '/inventory/new': ['inventory.manage_products'],
  '/reports': ['reports.sales', 'reports.inventory', 'reports.movements', 'reports.financial', 'reports.employees'],
  '/reports/sales': ['reports.sales'],
  '/reports/inventory': ['reports.inventory'],
  '/reports/movements': ['reports.movements'],
}

/** الصلاحيات المطلوبة لأقسام الإعدادات — القسم الفارغ للمالك الكامل فقط */
export const SETTINGS_SECTION_PERMISSIONS: Record<string, string[]> = {
  '/settings/import': ['inventory.import'],
  '/settings/receipts': ['settings.receipts'],
  '/settings/labels': ['settings.labels'],
  '/settings/database': [],
}

/** أول صفحة رئيسية مسموحة — للتحويل الصامت بعد الدخول المباشر لصفحة ممنوعة */
export const LANDING_PRIORITY: string[] = [
  '/pos',
  '/inventory',
  '/sales',
  '/customers',
  '/inventory/movements',
  '/reports',
  '/employees',
  '/attendance',
  '/branches',
]

export function firstAllowedPage(
  allowedAny: (keys: string[]) => boolean,
): string | null {
  for (const href of LANDING_PRIORITY) {
    const required = PAGE_PERMISSIONS[href]
    if (required && allowedAny(required)) return href
  }
  return null
}
