package services

import (
	"context"
	
	"github.com/pharmacy-os/backend/internal/models"
	"github.com/pharmacy-os/backend/internal/repository"
)

// EmployeeService handles employee business logic
type EmployeeService struct {
	repo *repository.EmployeeRepository
}

// NewEmployeeService creates a new EmployeeService
func NewEmployeeService(repo *repository.EmployeeRepository) *EmployeeService {
	return &EmployeeService{repo: repo}
}

// List returns employees for a pharmacy
// TODO: Implement with role/branch filters
func (s *EmployeeService) List(ctx context.Context, pharmacyID string) ([]models.Employee, error) {
	return s.repo.ListByPharmacy(ctx, pharmacyID)
}

// Create creates a new employee
// TODO: Implement with email uniqueness check, password hashing
func (s *EmployeeService) Create(ctx context.Context, employee *models.Employee) error {
	return s.repo.Create(ctx, employee)
}

// GetByID returns a single employee
// TODO: Implement
func (s *EmployeeService) GetByID(ctx context.Context, id string) (*models.Employee, error) {
	return s.repo.GetByID(ctx, id)
}

// Update updates an employee
// TODO: Implement with role change validation
func (s *EmployeeService) Update(ctx context.Context, employee *models.Employee) error {
	return s.repo.Update(ctx, employee)
}

// Deactivate soft-deletes an employee
// TODO: Implement with cascade checks
func (s *EmployeeService) Deactivate(ctx context.Context, id string) error {
	return s.repo.Deactivate(ctx, id)
}
