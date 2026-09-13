// Package subscription implements the SaaS plan enforcement layer
// (migration 26 / Task 90).
//
// The plan is the COMPANY ceiling: it bounds what the whole company may do,
// on top of the existing per-user RBAC:
//
//      Allow = plan_permissions ∋ key  AND  user_permissions ∋ key
//
// Design invariants:
//   - Plans are data, never code: nothing here ever compares a plan slug.
//   - Status is evaluated LAZILY (trial_ends_at / current_period_end vs
//     NOW() at read time) so correctness never depends on a scheduler;
//     the stored status is flipped durably on first access after a
//     deadline passes.
//   - Effective plans are cached in memory for a short TTL and invalidated
//     explicitly whenever a subscription or plan changes.
//   - A plan without an explicit limit value never blocks a counter
//     (limit 0 / missing key = not configured = unlimited).
package subscription

import (
        "context"
        "errors"
        "fmt"
        "sync"
        "time"

        "github.com/jackc/pgx/v5/pgxpool"
        "github.com/pharmacy-os/backend/internal/models"
)

const (
        defaultTTL       = 2 * time.Minute
        maxCacheEntries  = 10000
        tenantTTL        = 30 * time.Minute
        maxTenantEntries = 10000
)

// ErrNoSubscription means the company has no subscription row at all.
// Post-backfill this should never happen; enforcement treats it as deny.
var ErrNoSubscription = errors.New("company has no subscription")

type cacheEntry struct {
        eff       *models.EffectivePlan
        expiresAt time.Time
}

type tenantEntry struct {
        companyID string
        expiresAt time.Time
}

// Service loads and caches effective plans and usage counters.
type Service struct {
        db  *pgxpool.Pool
        ttl time.Duration

        mu    sync.RWMutex
        cache map[string]*cacheEntry

        tenantMu  sync.RWMutex
        tenantMap map[string]*tenantEntry
}

// NewService builds a subscription service over the shared pool.
func NewService(db *pgxpool.Pool) *Service {
        return &Service{
                db:        db,
                ttl:       defaultTTL,
                cache:     make(map[string]*cacheEntry),
                tenantMap: make(map[string]*tenantEntry),
        }
}

// ---------------------------------------------------------------------------
// Default singleton — the middleware packages need access without an
// import cycle back into handlers. handlers.New wires it once at startup.
// ---------------------------------------------------------------------------

var (
        defaultMu sync.RWMutex
        defaultSv *Service
)

// SetDefault wires the process-wide subscription service (called once).
func SetDefault(s *Service) {
        defaultMu.Lock()
        defer defaultMu.Unlock()
        defaultSv = s
}

// Default returns the process-wide service (nil when not wired — e.g. in
// unit tests that never touch the plans tables; callers must fail open).
func Default() *Service {
        defaultMu.RLock()
        defer defaultMu.RUnlock()
        return defaultSv
}

// ---------------------------------------------------------------------------
// Effective plan
// ---------------------------------------------------------------------------

// GetEffective returns the lazily-evaluated effective plan for a company,
// served from cache when fresh. Never returns a nil plan with a nil error.
func (s *Service) GetEffective(ctx context.Context, companyID string) (*models.EffectivePlan, error) {
        if companyID == "" {
                return nil, ErrNoSubscription
        }
        if eff, ok := s.fromCache(companyID); ok {
                // Deadlines must be enforced EXACTLY, not within cache TTL: the
                // deadline timestamps live inside the cached struct, so a cheap
                // in-memory comparison detects expiry on every hit with zero DB
                // cost. Deadline passed → bypass the cache and re-evaluate (the
                // load path flips the stored row durably).
                if !deadlinePassed(eff) {
                        return eff, nil
                }
        }
        eff, err := s.load(ctx, companyID)
        if err != nil {
                return nil, err
        }
        s.store(companyID, eff)
        return eff, nil
}

// deadlinePassed reports whether a cached entry's own trial/period
// deadline has passed since it was cached.
func deadlinePassed(eff *models.EffectivePlan) bool {
        now := time.Now()
        switch eff.Status {
        case models.SubStatusTrial:
                return eff.TrialEndsAt != nil && now.After(*eff.TrialEndsAt)
        case models.SubStatusActive:
                return eff.PeriodEnd != nil && now.After(*eff.PeriodEnd)
        default:
                return false
        }
}

// Invalidate drops the cached plan for one company (call after any write).
func (s *Service) Invalidate(companyID string) {
        s.mu.Lock()
        defer s.mu.Unlock()
        delete(s.cache, companyID)
}

// InvalidateAll drops the whole cache (call after editing a plan: every
// subscriber's effective sets may change).
func (s *Service) InvalidateAll() {
        s.mu.Lock()
        defer s.mu.Unlock()
        s.cache = make(map[string]*cacheEntry)
}

func (s *Service) fromCache(companyID string) (*models.EffectivePlan, bool) {
        s.mu.RLock()
        defer s.mu.RUnlock()
        entry, ok := s.cache[companyID]
        if !ok || time.Now().After(entry.expiresAt) {
                return nil, false
        }
        return entry.eff, true
}

func (s *Service) store(companyID string, eff *models.EffectivePlan) {
        s.mu.Lock()
        defer s.mu.Unlock()
        if len(s.cache) >= maxCacheEntries {
                s.cache = make(map[string]*cacheEntry) // crude reset; entries rehydrate lazily
        }
        s.cache[companyID] = &cacheEntry{eff: eff, expiresAt: time.Now().Add(s.ttl)}
}

// applyGrace evaluates the post-expiry grace window on an expired row
// (global best practice: never hard-lock the moment a period ends — busy
// owners renew within days; immediate lockout converts a payment hiccup
// into churned customer). Expired-by-deadline rows inside
// models.SubGraceDays keep FULL access (sets loaded, gate passes) while
// every surface shows an urgent renewal state. Cancelled/suspended rows
// are deliberate admin actions and get no grace.
func applyGrace(eff *models.EffectivePlan) {
        if eff.Status != models.SubStatusExpired {
                return
        }
        deadline := eff.PeriodEnd
        if deadline == nil {
                deadline = eff.TrialEndsAt
        }
        if deadline == nil {
                return
        }
        graceEnd := deadline.Add(models.SubGraceDays * 24 * time.Hour)
        if time.Now().Before(graceEnd) {
                eff.InGrace = true
                eff.GraceEndsAt = &graceEnd
        }
}

// load runs the lazy status evaluation then materializes the plan sets.
func (s *Service) load(ctx context.Context, companyID string) (*models.EffectivePlan, error) {
        eff, err := s.loadLive(ctx, companyID)
        if errors.Is(err, ErrNoSubscription) {
                // No live row: fall back to the most recent terminal row so the
                // API can answer "expired/cancelled/suspended" precisely instead
                // of a generic deny.
                eff, err = s.loadTerminal(ctx, companyID)
                if err != nil {
                        return nil, err
                }
                // Grace: a recently expired row keeps working (with sets) and
                // only the UI urgency changes; truly terminal rows grant nothing.
                applyGrace(eff)
                if !eff.InGrace {
                        return eff, nil
                }
                if err := s.loadSets(ctx, eff); err != nil {
                        return nil, err
                }
                return eff, nil
        }
        if err != nil {
                return nil, err
        }

        // Lazy expiry — flip the stored row durably so admin listings agree
        // with enforcement without needing a scheduler.
        now := time.Now()
        computed := eff.Status
        if eff.Status == models.SubStatusTrial && eff.TrialEndsAt != nil && now.After(*eff.TrialEndsAt) {
                computed = models.SubStatusExpired
        } else if eff.Status == models.SubStatusActive && eff.PeriodEnd != nil && now.After(*eff.PeriodEnd) {
                computed = models.SubStatusExpired
        }
        if computed != eff.Status {
                if _, err := s.db.Exec(ctx, `
                        UPDATE subscriptions SET status = 'expired'
                        WHERE id = $1 AND status IN ('trial','active')
                `, eff.SubscriptionID); err != nil {
                        return nil, fmt.Errorf("lazy-expire subscription: %w", err)
                }
                eff.Status = computed
        }

        applyGrace(eff)
        if err := s.loadSets(ctx, eff); err != nil {
                return nil, err
        }
        return eff, nil
}

const subscriptionColumns = `
        s.id::text, s.company_id::text, s.status, s.plan_id::text, s.billing_interval,
        s.current_period_start, s.current_period_end, s.trial_ends_at, s.cancel_at_period_end,
        p.slug, p.name, COALESCE(p.name_ar, ''), p.currency,
        p.monthly_price_piastres, p.yearly_price_piastres`

// pgxRow is the minimal interface shared by pgx.Row and pgxpool.Row.
type pgxRow interface{ Scan(dest ...any) error }

func scanEffective(row pgxRow) (*models.EffectivePlan, error) {
        eff := &models.EffectivePlan{}
        err := row.Scan(&eff.SubscriptionID, &eff.CompanyID, &eff.Status, &eff.PlanID,
                &eff.BillingInterval, &eff.PeriodStart, &eff.PeriodEnd, &eff.TrialEndsAt,
                &eff.CancelAtPeriodEnd, &eff.PlanSlug, &eff.PlanName, &eff.PlanNameAr,
                &eff.Currency, &eff.MonthlyPrice, &eff.YearlyPrice)
        if err != nil {
                return nil, err
        }
        return eff, nil
}

func (s *Service) loadLive(ctx context.Context, companyID string) (*models.EffectivePlan, error) {
        row := s.db.QueryRow(ctx, `
                SELECT `+subscriptionColumns+`
                FROM subscriptions s
                JOIN plans p ON p.id = s.plan_id
                WHERE s.company_id = $1 AND s.status IN ('trial','active','pending')
                ORDER BY s.created_at DESC
                LIMIT 1
        `, companyID)
        eff, err := scanEffective(row)
        if err != nil {
                return nil, ErrNoSubscription
        }
        return eff, nil
}

func (s *Service) loadTerminal(ctx context.Context, companyID string) (*models.EffectivePlan, error) {
        row := s.db.QueryRow(ctx, `
                SELECT `+subscriptionColumns+`
                FROM subscriptions s
                JOIN plans p ON p.id = s.plan_id
                WHERE s.company_id = $1
                ORDER BY s.created_at DESC
                LIMIT 1
        `, companyID)
        eff, err := scanEffective(row)
        if err != nil {
                return nil, ErrNoSubscription
        }
        return eff, nil
}

func (s *Service) loadSets(ctx context.Context, eff *models.EffectivePlan) error {
        permRows, err := s.db.Query(ctx, `
                SELECT p2.key
                FROM plan_permissions pp
                JOIN permissions p2 ON p2.id = pp.permission_id
                WHERE pp.plan_id = $1
        `, eff.PlanID)
        if err != nil {
                return fmt.Errorf("load plan permissions: %w", err)
        }
        permissions := make(map[string]bool)
        for permRows.Next() {
                var key string
                if err := permRows.Scan(&key); err != nil {
                        permRows.Close()
                        return err
                }
                permissions[key] = true
        }
        permRows.Close()
        if err := permRows.Err(); err != nil {
                return err
        }

        featureRows, err := s.db.Query(ctx, `
                SELECT feature_key FROM plan_features WHERE plan_id = $1
        `, eff.PlanID)
        if err != nil {
                return fmt.Errorf("load plan features: %w", err)
        }
        features := make(map[string]bool)
        for featureRows.Next() {
                var key string
                if err := featureRows.Scan(&key); err != nil {
                        featureRows.Close()
                        return err
                }
                features[key] = true
        }
        featureRows.Close()
        if err := featureRows.Err(); err != nil {
                return err
        }

        limitRows, err := s.db.Query(ctx, `
                SELECT limit_key, value FROM plan_limits WHERE plan_id = $1
        `, eff.PlanID)
        if err != nil {
                return fmt.Errorf("load plan limits: %w", err)
        }
        limits := make(map[string]int)
        for limitRows.Next() {
                var key string
                var value int
                if err := limitRows.Scan(&key, &value); err != nil {
                        limitRows.Close()
                        return err
                }
                limits[key] = value
        }
        limitRows.Close()
        if err := limitRows.Err(); err != nil {
                return err
        }

        eff.Permissions = permissions
        eff.Features = features
        eff.Limits = limits
        return nil
}

// ---------------------------------------------------------------------------
// Tenant resolution + usage counters
// ---------------------------------------------------------------------------

// CompanyIDForPharmacy resolves the owning company of a pharmacy-scoped
// principal (employees carry pharmacy_id only). Cached: the mapping is
// assigned at registration and does not change in practice.
func (s *Service) CompanyIDForPharmacy(ctx context.Context, pharmacyID string) (string, error) {
        if pharmacyID == "" {
                return "", fmt.Errorf("empty pharmacy id")
        }
        s.tenantMu.RLock()
        if entry, ok := s.tenantMap[pharmacyID]; ok && time.Now().Before(entry.expiresAt) {
                s.tenantMu.RUnlock()
                return entry.companyID, nil
        }
        s.tenantMu.RUnlock()

        var companyID string
        err := s.db.QueryRow(ctx, `
                SELECT a.company_id::text
                FROM pharmacies ph
                JOIN accounts a ON a.id = ph.account_id
                WHERE ph.id = $1
        `, pharmacyID).Scan(&companyID)
        if err != nil {
                return "", fmt.Errorf("resolve pharmacy company: %w", err)
        }

        s.tenantMu.Lock()
        if len(s.tenantMap) >= maxTenantEntries {
                s.tenantMap = make(map[string]*tenantEntry)
        }
        s.tenantMap[pharmacyID] = &tenantEntry{companyID: companyID, expiresAt: time.Now().Add(tenantTTL)}
        s.tenantMu.Unlock()
        return companyID, nil
}

// UsageCount returns the current usage for a limit key across the whole
// company (all pharmacies of all its accounts).
func (s *Service) UsageCount(ctx context.Context, companyID, limitKey string) (int, error) {
        var query string
        switch limitKey {
        case models.LimitKeyBranches:
                query = `
                        SELECT COUNT(*)::int
                        FROM branches b
                        JOIN pharmacies ph ON ph.id = b.pharmacy_id
                        JOIN accounts a ON a.id = ph.account_id
                        WHERE a.company_id = $1 AND b.is_active`
        case models.LimitKeyEmployees:
                query = `
                        SELECT COUNT(*)::int
                        FROM employees e
                        JOIN pharmacies ph ON ph.id = e.pharmacy_id
                        JOIN accounts a ON a.id = ph.account_id
                        WHERE a.company_id = $1 AND e.is_active`
        case models.LimitKeyUsers:
                query = `
                        SELECT COUNT(*)::int FROM company_users
                        WHERE company_id = $1 AND deleted_at IS NULL`
        case models.LimitKeyProducts:
                query = `
                        SELECT COUNT(*)::int
                        FROM pharmacy_products pp
                        JOIN pharmacies ph ON ph.id = pp.pharmacy_id
                        JOIN accounts a ON a.id = ph.account_id
                        WHERE a.company_id = $1 AND pp.is_active`
        default:
                return 0, fmt.Errorf("unknown limit key: %s", limitKey)
        }
        var used int
        if err := s.db.QueryRow(ctx, query, companyID).Scan(&used); err != nil {
                return 0, fmt.Errorf("count usage for %s: %w", limitKey, err)
        }
        return used, nil
}

// LimitAllowed decides against the plan: absent key or 0 = not configured
// (allowed), -1 = unlimited, otherwise used must stay below the ceiling.
func LimitAllowed(limit, used int) bool {
        if limit == -1 {
                return true
        }
        if limit == 0 {
                return true // not configured on this plan — do not block
        }
        return used < limit
}

// CheckLimit returns (used, limit, allowed, err) for a company and key.
func (s *Service) CheckLimit(ctx context.Context, companyID, limitKey string) (int, int, bool, error) {
        eff, err := s.GetEffective(ctx, companyID)
        if err != nil {
                return 0, 0, false, err
        }
        used, err := s.UsageCount(ctx, companyID, limitKey)
        if err != nil {
                return 0, 0, false, err
        }
        limit := eff.Limit(limitKey)
        return used, limit, LimitAllowed(limit, used), nil
}

// UsageAll returns usage for every known limit key at once (subscription
// page meters).
func (s *Service) UsageAll(ctx context.Context, companyID string) (map[string]int, error) {
        usage := make(map[string]int, 4)
        for _, key := range []string{
                models.LimitKeyBranches, models.LimitKeyUsers,
                models.LimitKeyEmployees, models.LimitKeyProducts,
        } {
                used, err := s.UsageCount(ctx, companyID, key)
                if err != nil {
                        return nil, err
                }
                usage[key] = used
        }
        return usage, nil
}
