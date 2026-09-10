// Task 48 — محمّل القواميس: قاعدة عربية دائمًا + طبقة لغة الواجهة فوقها.
// أي مفتاح ناقص في لغة غير مكتملة يرجع تلقائيًا للعربية (لا نصوص مفاتيح للمستخدم).
// الملف مولّد بـ scripts/task48_scaffold.py — أضف مساحات جديدة هناك وليس يدويًا.
import { DEFAULT_LOCALE, type Locale } from '../config'
import arCommon from './ar/common.json'
import arNav from './ar/nav.json'
import arAuth from './ar/auth.json'
import arErrors from './ar/errors.json'
import arDashboard from './ar/dashboard.json'
import arUsers from './ar/users.json'
import arCompanies from './ar/companies.json'
import arAccounts from './ar/accounts.json'
import arPermissions from './ar/permissions.json'
import arSettings from './ar/settings.json'
import enCommon from './en/common.json'
import enNav from './en/nav.json'
import enAuth from './en/auth.json'
import enErrors from './en/errors.json'
import enDashboard from './en/dashboard.json'
import enUsers from './en/users.json'
import enCompanies from './en/companies.json'
import enAccounts from './en/accounts.json'
import enPermissions from './en/permissions.json'
import enSettings from './en/settings.json'
import frCommon from './fr/common.json'
import frNav from './fr/nav.json'
import frAuth from './fr/auth.json'
import frErrors from './fr/errors.json'
import frDashboard from './fr/dashboard.json'
import frUsers from './fr/users.json'
import frCompanies from './fr/companies.json'
import frAccounts from './fr/accounts.json'
import frPermissions from './fr/permissions.json'
import frSettings from './fr/settings.json'
import esCommon from './es/common.json'
import esNav from './es/nav.json'
import esAuth from './es/auth.json'
import esErrors from './es/errors.json'
import esDashboard from './es/dashboard.json'
import esUsers from './es/users.json'
import esCompanies from './es/companies.json'
import esAccounts from './es/accounts.json'
import esPermissions from './es/permissions.json'
import esSettings from './es/settings.json'
import trCommon from './tr/common.json'
import trNav from './tr/nav.json'
import trAuth from './tr/auth.json'
import trErrors from './tr/errors.json'
import trDashboard from './tr/dashboard.json'
import trUsers from './tr/users.json'
import trCompanies from './tr/companies.json'
import trAccounts from './tr/accounts.json'
import trPermissions from './tr/permissions.json'
import trSettings from './tr/settings.json'
import zhCommon from './zh/common.json'
import zhNav from './zh/nav.json'
import zhAuth from './zh/auth.json'
import zhErrors from './zh/errors.json'
import zhDashboard from './zh/dashboard.json'
import zhUsers from './zh/users.json'
import zhCompanies from './zh/companies.json'
import zhAccounts from './zh/accounts.json'
import zhPermissions from './zh/permissions.json'
import zhSettings from './zh/settings.json'
import hiCommon from './hi/common.json'
import hiNav from './hi/nav.json'
import hiAuth from './hi/auth.json'
import hiErrors from './hi/errors.json'
import hiDashboard from './hi/dashboard.json'
import hiUsers from './hi/users.json'
import hiCompanies from './hi/companies.json'
import hiAccounts from './hi/accounts.json'
import hiPermissions from './hi/permissions.json'
import hiSettings from './hi/settings.json'
import urCommon from './ur/common.json'
import urNav from './ur/nav.json'
import urAuth from './ur/auth.json'
import urErrors from './ur/errors.json'
import urDashboard from './ur/dashboard.json'
import urUsers from './ur/users.json'
import urCompanies from './ur/companies.json'
import urAccounts from './ur/accounts.json'
import urPermissions from './ur/permissions.json'
import urSettings from './ur/settings.json'

export type Messages = Record<string, unknown>

const catalogs: Record<Locale, Record<string, Record<string, unknown>>> = {
  ar: {
    common: arCommon,
    nav: arNav,
    auth: arAuth,
    errors: arErrors,
    dashboard: arDashboard,
    users: arUsers,
    companies: arCompanies,
    accounts: arAccounts,
    permissions: arPermissions,
    settings: arSettings,
  },
  en: {
    common: enCommon,
    nav: enNav,
    auth: enAuth,
    errors: enErrors,
    dashboard: enDashboard,
    users: enUsers,
    companies: enCompanies,
    accounts: enAccounts,
    permissions: enPermissions,
    settings: enSettings,
  },
  fr: {
    common: frCommon,
    nav: frNav,
    auth: frAuth,
    errors: frErrors,
    dashboard: frDashboard,
    users: frUsers,
    companies: frCompanies,
    accounts: frAccounts,
    permissions: frPermissions,
    settings: frSettings,
  },
  es: {
    common: esCommon,
    nav: esNav,
    auth: esAuth,
    errors: esErrors,
    dashboard: esDashboard,
    users: esUsers,
    companies: esCompanies,
    accounts: esAccounts,
    permissions: esPermissions,
    settings: esSettings,
  },
  tr: {
    common: trCommon,
    nav: trNav,
    auth: trAuth,
    errors: trErrors,
    dashboard: trDashboard,
    users: trUsers,
    companies: trCompanies,
    accounts: trAccounts,
    permissions: trPermissions,
    settings: trSettings,
  },
  zh: {
    common: zhCommon,
    nav: zhNav,
    auth: zhAuth,
    errors: zhErrors,
    dashboard: zhDashboard,
    users: zhUsers,
    companies: zhCompanies,
    accounts: zhAccounts,
    permissions: zhPermissions,
    settings: zhSettings,
  },
  hi: {
    common: hiCommon,
    nav: hiNav,
    auth: hiAuth,
    errors: hiErrors,
    dashboard: hiDashboard,
    users: hiUsers,
    companies: hiCompanies,
    accounts: hiAccounts,
    permissions: hiPermissions,
    settings: hiSettings,
  },
  ur: {
    common: urCommon,
    nav: urNav,
    auth: urAuth,
    errors: urErrors,
    dashboard: urDashboard,
    users: urUsers,
    companies: urCompanies,
    accounts: urAccounts,
    permissions: urPermissions,
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
