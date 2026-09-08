// Package models - Permission types for role-based access control
//
// MANDATORY FILE: This file is reserved for future Permission system implementation.
// Do not delete - will be used in Task N (Permissions System).

package models

import "time"

// Permission represents a single permission key
// TODO: Implement permission constants and validation
type Permission struct {
        Key         string `json:"key"`
        Description string `json:description"`
        Category    string `json:"category"`
}

// EmployeePermission links employees to their permissions
// TODO: Implement employee-permission mapping
type EmployeePermission struct {
        ID          string `json:"id"`
        EmployeeID  string `json:"employee_id"`
        PermissionKey string `json:"permission_key"`
        GrantedBy   string `json:"granted_by"`
        GrantedAt   time.Time `json:"granted_at"`
}

// Permission categories
const (
        PermCategoryInventory = "inventory"
        PermCategoryEmployees = "employees"
        PermCategoryAttendance = "attendance"
        PermCategoryReports   = "reports"
        PermCategorySettings  = "settings"
        PermCategoryBranches  = "branches"
)
