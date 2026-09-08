export interface Employee {
  id: string
  pharmacy_id: string
  branch_id: string
  first_name: string
  last_name: string
  email: string
  phone?: string
  role: string
  is_active: boolean
  created_at: string
  updated_at: string
}
