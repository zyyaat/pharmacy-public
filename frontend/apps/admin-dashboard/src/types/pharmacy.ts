export interface Pharmacy {
  id: string
  name: string
  email: string
  phone?: string
  plan_type: 'free' | 'pro' | 'enterprise'
  is_active: boolean
  created_at: string
  employee_count?: number
  branch_count?: number
}
