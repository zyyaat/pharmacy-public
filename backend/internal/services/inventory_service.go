package services

import (
        "context"
        
        "github.com/pharmacy-os/backend/internal/models"
        "github.com/pharmacy-os/backend/internal/repository"
)

// InventoryService handles medication/inventory business logic
type InventoryService struct {
        repo *repository.MedicationRepository
}

// NewInventoryService creates a new InventoryService
func NewInventoryService(repo *repository.MedicationRepository) *InventoryService {
        return &InventoryService{repo: repo}
}

// List returns medications in inventory
// TODO: Implement with search, filter, sort
func (s *InventoryService) List(ctx context.Context, pharmacyID string) ([]models.GlobalProduct, error) {
        return s.repo.ListByPharmacy(ctx, pharmacyID)
}

// Create adds a new medication to inventory
// TODO: Implement with SKU generation, duplicate check
func (s *InventoryService) Create(ctx context.Context, med *models.GlobalProduct) error {
        return s.repo.Create(ctx, med)
}

// GetByID returns a single medication
// TODO: Implement
func (s *InventoryService) GetByID(ctx context.Context, id string) (*models.GlobalProduct, error) {
        return s.repo.GetByID(ctx, id)
}

// Update updates medication details
// TODO: Implement with stock validation
func (s *InventoryService) Update(ctx context.Context, med *models.GlobalProduct) error {
        return s.repo.Update(ctx, med)
}

// AdjustStock adjusts medication quantity
// TODO: Implement with audit logging, low-stock check job trigger
func (s *InventoryService) AdjustStock(ctx context.Context, id string, quantity int, reason string) error {
        return s.repo.AdjustStock(ctx, id, quantity, reason)
}

// GetLowStockItems returns items below minimum stock level
// TODO: Implement for dashboard alerts
func (s *InventoryService) GetLowStockItems(ctx context.Context, pharmacyID string) ([]models.GlobalProduct, error) {
        return s.repo.GetLowStock(ctx, pharmacyID)
}
