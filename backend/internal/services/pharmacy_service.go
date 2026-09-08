package services

import (
	"context"
	
	"github.com/pharmacy-os/backend/internal/models"
	"github.com/pharmacy-os/backend/internal/repository"
)

// PharmacyService handles pharmacy business logic
type PharmacyService struct {
	repo *repository.PharmacyRepository
}

// NewPharmacyService creates a new PharmacyService
func NewPharmacyService(repo *repository.PharmacyRepository) *PharmacyService {
	return &PharmacyService{repo: repo}
}

// List returns paginated pharmacies
// TODO: Implement with pagination and filtering
func (s *PharmacyService) List(ctx context.Context, page, limit int) ([]models.Pharmacy, error) {
	return s.repo.List(ctx, page, limit)
}

// GetByID returns a single pharmacy by ID
// TODO: Implement with cache support
func (s *PharmacyService) GetByID(ctx context.Context, id string) (*models.Pharmacy, error) {
	return s.repo.GetByID(ctx, id)
}

// Create creates a new pharmacy tenant
// TODO: Implement with initial setup (default branch, admin user)
func (s *PharmacyService) Create(ctx context.Context, pharmacy *models.Pharmacy) error {
	return s.repo.Create(ctx, pharmacy)
}

// Update updates an existing pharmacy
// TODO: Implement with validation
func (s *PharmacyService) Update(ctx context.Context, pharmacy *models.Pharmacy) error {
	return s.repo.Update(ctx, pharmacy)
}
