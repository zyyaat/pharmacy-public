package services

import (
	"context"
	
	"github.com/pharmacy-os/backend/internal/models"
	"github.com/pharmacy-os/backend/internal/repository"
)

// BranchService handles branch business logic
type BranchService struct {
	repo *repository.BranchRepository
}

// NewBranchService creates a new BranchService
func NewBranchService(repo *repository.BranchRepository) *BranchService {
	return &BranchService{repo: repo}
}

// List returns branches for a pharmacy
// TODO: Implement with RLS filtering
func (s *BranchService) List(ctx context.Context, pharmacyID string) ([]models.Branch, error) {
	return s.repo.ListByPharmacy(ctx, pharmacyID)
}

// Create creates a new branch
// TODO: Implement with address validation
func (s *BranchService) Create(ctx context.Context, branch *models.Branch) error {
	return s.repo.Create(ctx, branch)
}

// GetByID returns a single branch
// TODO: Implement
func (s *BranchService) GetByID(ctx context.Context, id string) (*models.Branch, error) {
	return s.repo.GetByID(ctx, id)
}

// Update updates a branch
// TODO: Implement
func (s *BranchService) Update(ctx context.Context, branch *models.Branch) error {
	return s.repo.Update(ctx, branch)
}
