export interface Medication {
  id: string
  pharmacy_id: string
  name: string
  generic_name?: string
  sku: string
  quantity: number
  min_stock_level: number
  price: number
  expiry_date?: string
  created_at: string
  updated_at: string
}
