// User & Auth Types
export interface CompanyUser {
  id: string;
  email: string;
  account_type?: "company_user" | "employee";
  displayName: string;
  role: "super_admin" | "company_admin" | "company_manager" | "company_viewer";
  companyId?: string;
  avatarUrl?: string;
  isActive: boolean;
  lastLoginAt?: string;
  createdAt: string;
}

export interface LoginCredentials {
  email: string;
  password: string;
}

export interface AuthResponse {
  user: CompanyUser;
  token: string;
  expiresIn: number;
}

// Company Types
export interface Company {
  id: string;
  name: string;
  nameEn?: string;
  email: string;
  phone?: string;
  status: "active" | "suspended" | "trial" | "cancelled";
  plan: "free" | "starter" | "professional" | "enterprise" | "custom";
  logoUrl?: string;
  maxUsers: number;
  currentUsersCount: number;
  subscriptionEndsAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface CreateCompanyRequest {
  name: string;
  nameEn?: string;
  plan: Company["plan"];
  maxUsers?: number;
}

// Permission Types
export interface UserPermission {
  permission: string;
  granted: boolean;
  grantedAt?: string;
  grantedBy?: string;
}

// Account Types (Pharmacy)
export interface Account {
  id: string;
  companyId: string;
  companyName?: string;
  name: string;
  status: string;
  plan?: string;
  pharmacyCount: number;
  branchesCount: number;
  email?: string;
  phone?: string;
  createdAt: string;
}

// Dashboard Stats
export interface DashboardStats {
  totalCompanies: number;
  activeCompanies: number;
  suspendedCompanies: number;
  totalUsers: number;
  activeUsers: number;
  totalAccounts: number;
  totalPharmacies: number;
  recentActivity: ActivityItem[];
}

export interface ActivityItem {
  id: string;
  type: string;
  description: string;
  userName: string;
  timestamp: string;
}

export interface PlatformUser {
  id: string;
  accountType: "company_user" | "employee";
  email: string;
  displayName: string;
  companyName: string;
  role: string;
  isActive: boolean;
  lastLoginAt?: string;
  createdAt?: string;
  permissionsCount: number;
}

export interface PlatformPermission {
  key: string;
  name: string;
  description: string;
  module: string;
  category: string;
  isSystem: boolean;
  sortOrder: number;
}

export interface PlatformRole {
  id: string;
  name: string;
  description: string;
  isSystem: boolean;
  userCount: number;
  permissionKeys: string[];
}
