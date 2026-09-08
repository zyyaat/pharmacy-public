// User & Auth Types
export interface CompanyUser {
  id: string;
  email: string;
  displayName: string;
  role: "super_admin" | "company_admin" | "company_manager" | "viewer";
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
  name: string;
  type: "pharmacy" | "chain" | "hospital";
  isActive: boolean;
  branchesCount: number;
  createdAt: string;
}

// Dashboard Stats
export interface DashboardStats {
  totalCompanies: number;
  activeCompanies: number;
  totalUsers: number;
  activeUsers: number;
  totalAccounts: number;
  recentActivity: ActivityItem[];
}

export interface ActivityItem {
  id: string;
  type: "user_created" | "company_created" | "login" | "permission_changed";
  description: string;
  userName: string;
  timestamp: string;
}
