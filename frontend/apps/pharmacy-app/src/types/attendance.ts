export interface AttendanceRecord {
  id: string
  employee_id: string
  clock_in: string
  clock_out?: string
  notes?: string
}
