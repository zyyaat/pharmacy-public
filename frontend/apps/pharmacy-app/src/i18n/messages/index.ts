// Task 48 — محمّل القواميس: قاعدة عربية دائمًا + طبقة لغة الواجهة فوقها.
// أي مفتاح ناقص في لغة غير مكتملة يرجع تلقائيًا للعربية (لا نصوص مفاتيح للمستخدم).
// الملف مولّد بـ scripts/task48_scaffold.py — أضف مساحات جديدة هناك وليس يدويًا.
import { DEFAULT_LOCALE, type Locale } from '../config'
import arCommon from './ar/common.json'
import arNav from './ar/nav.json'
import arAuth from './ar/auth.json'
import arErrors from './ar/errors.json'
import arDashboard from './ar/dashboard.json'
import arPos from './ar/pos.json'
import arSales from './ar/sales.json'
import arInventory from './ar/inventory.json'
import arMovements from './ar/movements.json'
import arCustomers from './ar/customers.json'
import arEmployees from './ar/employees.json'
import arReports from './ar/reports.json'
import arSettings from './ar/settings.json'
import enCommon from './en/common.json'
import enNav from './en/nav.json'
import enAuth from './en/auth.json'
import enErrors from './en/errors.json'
import enDashboard from './en/dashboard.json'
import enPos from './en/pos.json'
import enSales from './en/sales.json'
import enInventory from './en/inventory.json'
import enMovements from './en/movements.json'
import enCustomers from './en/customers.json'
import enEmployees from './en/employees.json'
import enReports from './en/reports.json'
import enSettings from './en/settings.json'
import frCommon from './fr/common.json'
import frNav from './fr/nav.json'
import frAuth from './fr/auth.json'
import frErrors from './fr/errors.json'
import frDashboard from './fr/dashboard.json'
import frPos from './fr/pos.json'
import frSales from './fr/sales.json'
import frInventory from './fr/inventory.json'
import frMovements from './fr/movements.json'
import frCustomers from './fr/customers.json'
import frEmployees from './fr/employees.json'
import frReports from './fr/reports.json'
import frSettings from './fr/settings.json'
import esCommon from './es/common.json'
import esNav from './es/nav.json'
import esAuth from './es/auth.json'
import esErrors from './es/errors.json'
import esDashboard from './es/dashboard.json'
import esPos from './es/pos.json'
import esSales from './es/sales.json'
import esInventory from './es/inventory.json'
import esMovements from './es/movements.json'
import esCustomers from './es/customers.json'
import esEmployees from './es/employees.json'
import esReports from './es/reports.json'
import esSettings from './es/settings.json'
import trCommon from './tr/common.json'
import trNav from './tr/nav.json'
import trAuth from './tr/auth.json'
import trErrors from './tr/errors.json'
import trDashboard from './tr/dashboard.json'
import trPos from './tr/pos.json'
import trSales from './tr/sales.json'
import trInventory from './tr/inventory.json'
import trMovements from './tr/movements.json'
import trCustomers from './tr/customers.json'
import trEmployees from './tr/employees.json'
import trReports from './tr/reports.json'
import trSettings from './tr/settings.json'
import zhCommon from './zh/common.json'
import zhNav from './zh/nav.json'
import zhAuth from './zh/auth.json'
import zhErrors from './zh/errors.json'
import zhDashboard from './zh/dashboard.json'
import zhPos from './zh/pos.json'
import zhSales from './zh/sales.json'
import zhInventory from './zh/inventory.json'
import zhMovements from './zh/movements.json'
import zhCustomers from './zh/customers.json'
import zhEmployees from './zh/employees.json'
import zhReports from './zh/reports.json'
import zhSettings from './zh/settings.json'
import hiCommon from './hi/common.json'
import hiNav from './hi/nav.json'
import hiAuth from './hi/auth.json'
import hiErrors from './hi/errors.json'
import hiDashboard from './hi/dashboard.json'
import hiPos from './hi/pos.json'
import hiSales from './hi/sales.json'
import hiInventory from './hi/inventory.json'
import hiMovements from './hi/movements.json'
import hiCustomers from './hi/customers.json'
import hiEmployees from './hi/employees.json'
import hiReports from './hi/reports.json'
import hiSettings from './hi/settings.json'
import urCommon from './ur/common.json'
import urNav from './ur/nav.json'
import urAuth from './ur/auth.json'
import urErrors from './ur/errors.json'
import urDashboard from './ur/dashboard.json'
import urPos from './ur/pos.json'
import urSales from './ur/sales.json'
import urInventory from './ur/inventory.json'
import urMovements from './ur/movements.json'
import urCustomers from './ur/customers.json'
import urEmployees from './ur/employees.json'
import urReports from './ur/reports.json'
import urSettings from './ur/settings.json'

export type Messages = Record<string, unknown>

const catalogs: Record<Locale, Record<string, Record<string, unknown>>> = {
  ar: {
    common: arCommon,
    nav: arNav,
    auth: arAuth,
    errors: arErrors,
    dashboard: arDashboard,
    pos: arPos,
    sales: arSales,
    inventory: arInventory,
    movements: arMovements,
    customers: arCustomers,
    employees: arEmployees,
    reports: arReports,
    settings: arSettings,
  },
  en: {
    common: enCommon,
    nav: enNav,
    auth: enAuth,
    errors: enErrors,
    dashboard: enDashboard,
    pos: enPos,
    sales: enSales,
    inventory: enInventory,
    movements: enMovements,
    customers: enCustomers,
    employees: enEmployees,
    reports: enReports,
    settings: enSettings,
  },
  fr: {
    common: frCommon,
    nav: frNav,
    auth: frAuth,
    errors: frErrors,
    dashboard: frDashboard,
    pos: frPos,
    sales: frSales,
    inventory: frInventory,
    movements: frMovements,
    customers: frCustomers,
    employees: frEmployees,
    reports: frReports,
    settings: frSettings,
  },
  es: {
    common: esCommon,
    nav: esNav,
    auth: esAuth,
    errors: esErrors,
    dashboard: esDashboard,
    pos: esPos,
    sales: esSales,
    inventory: esInventory,
    movements: esMovements,
    customers: esCustomers,
    employees: esEmployees,
    reports: esReports,
    settings: esSettings,
  },
  tr: {
    common: trCommon,
    nav: trNav,
    auth: trAuth,
    errors: trErrors,
    dashboard: trDashboard,
    pos: trPos,
    sales: trSales,
    inventory: trInventory,
    movements: trMovements,
    customers: trCustomers,
    employees: trEmployees,
    reports: trReports,
    settings: trSettings,
  },
  zh: {
    common: zhCommon,
    nav: zhNav,
    auth: zhAuth,
    errors: zhErrors,
    dashboard: zhDashboard,
    pos: zhPos,
    sales: zhSales,
    inventory: zhInventory,
    movements: zhMovements,
    customers: zhCustomers,
    employees: zhEmployees,
    reports: zhReports,
    settings: zhSettings,
  },
  hi: {
    common: hiCommon,
    nav: hiNav,
    auth: hiAuth,
    errors: hiErrors,
    dashboard: hiDashboard,
    pos: hiPos,
    sales: hiSales,
    inventory: hiInventory,
    movements: hiMovements,
    customers: hiCustomers,
    employees: hiEmployees,
    reports: hiReports,
    settings: hiSettings,
  },
  ur: {
    common: urCommon,
    nav: urNav,
    auth: urAuth,
    errors: urErrors,
    dashboard: urDashboard,
    pos: urPos,
    sales: urSales,
    inventory: urInventory,
    movements: urMovements,
    customers: urCustomers,
    employees: urEmployees,
    reports: urReports,
    settings: urSettings,
  },
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function deepMerge(base: Record<string, unknown>, overlay: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...base }
  for (const [key, value] of Object.entries(overlay)) {
    const baseValue = out[key]
    if (isPlainObject(baseValue) && isPlainObject(value)) {
      out[key] = deepMerge(baseValue, value)
    } else {
      out[key] = value
    }
  }
  return out
}

const cache = new Map<Locale, Messages>()

export function messagesFor(locale: Locale): Messages {
  const hit = cache.get(locale)
  if (hit) return hit
  const result: Messages =
    locale === DEFAULT_LOCALE
      ? catalogs[locale]
      : deepMerge(catalogs[DEFAULT_LOCALE], catalogs[locale])
  cache.set(locale, result)
  return result
}
