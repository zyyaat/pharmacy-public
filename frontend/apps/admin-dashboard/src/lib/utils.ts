import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";
import { runtimeTranslator } from "@/i18n/runtime";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// Permissions System - matches backend
export const PERMISSIONS = {
  // Company Permissions
  COMPANIES_VIEW: "companies.view",
  COMPANIES_CREATE: "companies.create",
  COMPANIES_EDIT: "companies.edit",
  COMPANIES_DELETE: "companies.delete",
  
  // Company Users Permissions
  COMPANY_USERS_VIEW: "company_users.view",
  COMPANY_USERS_CREATE: "company_users.create",
  COMPANY_USERS_EDIT: "company_users.edit",
  COMPANY_USERS_DELETE: "company_users.delete",
  COMPANY_USERS_MANAGE_PERMISSIONS: "company_users.manage_permissions",
  
  // Accounts Permissions
  ACCOUNTS_VIEW: "accounts.view",
  ACCOUNTS_CREATE: "accounts.create",
  ACCOUNTS_EDIT: "accounts.edit",
  ACCOUNTS_DELETE: "accounts.delete",
  
  // Platform Permissions
  PLATFORM_SETTINGS: "platform.settings",
  PLATFORM_MANAGEMENT: "platform.management",
  PLATFORM_ANALYTICS: "platform.analytics",
} as const;

export type Permission = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];

export const ROLES = {
  SUPER_ADMIN: "super_admin",
  COMPANY_ADMIN: "company_admin",
  COMPANY_MANAGER: "company_manager",
  VIEWER: "company_viewer",
} as const;

export type Role = (typeof ROLES)[keyof typeof ROLES];

const KNOWN_ROLES: readonly string[] = Object.values(ROLES);

/** Task 48 — تسميات الأدوار من كتالوج users (مع الرجوع للقيمة الخام لغير المعروفة). */
export function roleLabel(role: string): string {
  return KNOWN_ROLES.includes(role) ? runtimeTranslator("users")(`roles.${role}`) : role;
}

const KNOWN_PERMISSIONS: readonly string[] = Object.values(PERMISSIONS);

/** Task 48 — تسميات الصلاحيات من كتالوج permissions. */
export function permissionLabel(permission: string): string {
  return KNOWN_PERMISSIONS.includes(permission)
    ? runtimeTranslator("permissions")(`labels.${permission.replace(/\./g, "_")}`)
    : permission;
}

// Company Status
export const COMPANY_STATUS = {
  ACTIVE: "active",
  SUSPENDED: "suspended",
  TRIAL: "trial",
  CANCELLED: "cancelled",
} as const;

export type CompanyStatus = (typeof COMPANY_STATUS)[keyof typeof COMPANY_STATUS];

const KNOWN_COMPANY_STATUSES: readonly string[] = Object.values(COMPANY_STATUS);

/** Task 48 — تسميات حالة الشركة من كتالوج companies. */
export function companyStatusLabel(status: string): string {
  return KNOWN_COMPANY_STATUSES.includes(status)
    ? runtimeTranslator("companies")(`status.${status}`)
    : status;
}

// Company Plans
export const COMPANY_PLANS = {
  FREE: "free",
  STARTER: "starter",
  PROFESSIONAL: "professional",
  ENTERPRISE: "enterprise",
  CUSTOM: "custom",
} as const;

export type CompanyPlan = (typeof COMPANY_PLANS)[keyof typeof COMPANY_PLANS];

const KNOWN_COMPANY_PLANS: readonly string[] = Object.values(COMPANY_PLANS);

/** Task 48 — تسميات خطط الشركة من كتالوج companies. */
export function companyPlanLabel(plan: string): string {
  return KNOWN_COMPANY_PLANS.includes(plan)
    ? runtimeTranslator("companies")(`plans.${plan}`)
    : plan;
}
