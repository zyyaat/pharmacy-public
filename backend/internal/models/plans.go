// Package models - SaaS Plans & Subscriptions (migration 26).
//
// The plans system is fully dynamic: plans live in the database and the
// super admin manages them from the admin dashboard. The Go structs below
// are row shapes only — business logic must never branch on a plan's name
// or slug, only on its permission/feature/limit sets.
package models

import "time"

// Subscription lifecycle states (subscriptions.status CHECK).
const (
        SubStatusTrial     = "trial"
        SubStatusActive    = "active"
        SubStatusExpired   = "expired"
        SubStatusCancelled = "cancelled"
        SubStatusSuspended = "suspended"
        SubStatusPending   = "pending"
)

// GraceDays is the post-expiry grace window (global best practice: 7-14
// days before lockout — cutting access the second a period ends churns
// customers who simply had a busy week). During grace an expired
// subscription keeps working and every surface shows an urgent renewal
// banner; after it, the standard expired lockout applies. Cancelled and
// suspended rows get NO grace — those are deliberate admin actions.
const SubGraceDays = 7

// Billing intervals.
const (
        BillingIntervalNone    = "none"
        BillingIntervalMonthly = "monthly"
        BillingIntervalYearly  = "yearly"
)

// Subscription sources.
const (
        SubSourceRegistration = "registration"
        SubSourcePayment      = "payment"
        SubSourceManual       = "manual"
        SubSourceMigration    = "migration"
)

// Payment statuses (payments.status CHECK).
const (
        PaymentStatusPending   = "pending"
        PaymentStatusSucceeded = "succeeded"
        PaymentStatusFailed    = "failed"
        PaymentStatusRefunded  = "refunded"
        PaymentStatusVoided    = "voided"
        PaymentStatusCancelled = "cancelled"
)

// How a payment's success became known to us (payments.confirmation_source).
// webhook = provider event with a verified signature; sync = we pulled the
// session from the provider API (lost-webhook recovery); manual = the super
// admin's own out-of-band entry.
const (
        PaymentConfirmedByWebhook = "webhook"
        PaymentConfirmedBySync    = "sync"
        PaymentConfirmedByManual  = "manual"
)

// Settlement statuses (payment_settlements.status CHECK, migration 32).
// pending = the provider captured the money (confirmation) but the bank
// payout is not matched yet; settled/partially_settled = the operator
// matched an XPay payout batch; unknown/disputed = conflict or chargeback
// — always paired with payments.needs_review. Manual payments have no
// settlement row: there is no provider to settle with.
const (
        SettlementStatusPending          = "pending"
        SettlementStatusSettled          = "settled"
        SettlementStatusPartiallySettled = "partially_settled"
        SettlementStatusFailed           = "failed"
        SettlementStatusDisputed         = "disputed"
        SettlementStatusUnknown          = "unknown"
)

// payment_transactions event kinds added by migration 32 (the original
// intent/webhook/refund/void stay unchanged).
const (
        TxnTypeSync         = "sync"
        TxnTypeSettlement   = "settlement"
        TxnTypeReview       = "review"
        TxnTypeStatusChange = "status_change"
)

// StalePendingHours marks when an unconfirmed online payment becomes a
// reconciliation candidate: after this long a session is either abandoned
// or its webhook was lost — the resync action asks the provider directly.
const StalePendingHours = 24

// Known plan limit keys. The limits table itself is dynamic (any key), but
// the backend enforces these counters at the matching creation endpoints.
const (
        LimitKeyBranches  = "branches"
        LimitKeyUsers     = "users" // company_users (dashboard logins)
        LimitKeyEmployees = "employees"
        LimitKeyProducts  = "products"
)

// Feature is one row of the presentation catalog.
type Feature struct {
        Key         string `json:"key"`
        Name        string `json:"name"`
        NameAr      string `json:"name_ar,omitempty"`
        Description string `json:"description,omitempty"`
        SortOrder   int    `json:"sort_order"`
        IsActive    bool   `json:"is_active"`
}

// Plan is a dynamic plan definition. Prices are integer piastres
// (migration 14 convention).
type Plan struct {
        ID                   string     `json:"id"`
        Slug                 string     `json:"slug"`
        Name                 string     `json:"name"`
        NameAr               string     `json:"name_ar,omitempty"`
        Description          string     `json:"description,omitempty"`
        MonthlyPricePiastres int64      `json:"monthly_price_piastres"`
        YearlyPricePiastres  int64      `json:"yearly_price_piastres"`
        Currency             string     `json:"currency"`
        IsActive             bool       `json:"is_active"`
        IsPublic             bool       `json:"is_public"`
        SortOrder            int        `json:"sort_order"`
        CreatedAt            time.Time  `json:"created_at"`
        UpdatedAt            time.Time  `json:"updated_at"`
        DeletedAt            *time.Time `json:"deleted_at,omitempty"`
}

// PlanDetail is a plan plus its feature/permission/limit sets (admin view).
type PlanDetail struct {
        Plan
        Features    []string        `json:"features"`
        Permissions []string        `json:"permissions"`
        Limits      map[string]int  `json:"limits"`
        Subscribers int             `json:"subscribers"`
}

// PublicPlan is the customer-facing shape for the upgrade page: what the
// plan includes, never its raw permission keys.
type PublicPlan struct {
        ID                   string        `json:"id"`
        Slug                 string        `json:"slug"`
        Name                 string        `json:"name"`
        NameAr               string        `json:"name_ar,omitempty"`
        Description          string        `json:"description,omitempty"`
        MonthlyPricePiastres int64         `json:"monthly_price_piastres"`
        YearlyPricePiastres  int64         `json:"yearly_price_piastres"`
        Currency             string        `json:"currency"`
        SortOrder            int           `json:"sort_order"`
        Features             []string      `json:"features"`
        Limits               map[string]int `json:"limits"`
}

// Subscription is one billing-lifecycle row per company.
type Subscription struct {
        ID                 string     `json:"id"`
        CompanyID          string     `json:"company_id"`
        PlanID             string     `json:"plan_id"`
        Status             string     `json:"status"`
        BillingInterval    string     `json:"billing_interval"`
        CurrentPeriodStart *time.Time `json:"current_period_start,omitempty"`
        CurrentPeriodEnd   *time.Time `json:"current_period_end,omitempty"`
        TrialEndsAt        *time.Time `json:"trial_ends_at,omitempty"`
        CancelAtPeriodEnd  bool       `json:"cancel_at_period_end"`
        Source             string     `json:"source"`
        CreatedAt          time.Time  `json:"created_at"`
        UpdatedAt          time.Time  `json:"updated_at"`
}

// EffectivePlan is the materialized per-company authorization view the
// middleware consumes: the live subscription, its plan, and the flat
// permission/feature/limit sets. Cached in memory for a short TTL.
type EffectivePlan struct {
        SubscriptionID string         `json:"subscription_id"`
        CompanyID      string         `json:"company_id"`
        Status         string         `json:"status"` // lazily evaluated
        PlanID         string         `json:"plan_id"`
        PlanSlug       string         `json:"plan_slug"`
        PlanName       string         `json:"plan_name"`
        PlanNameAr     string         `json:"plan_name_ar,omitempty"`
        Currency       string         `json:"currency"`
        MonthlyPrice   int64          `json:"monthly_price_piastres"`
        YearlyPrice    int64          `json:"yearly_price_piastres"`
        BillingInterval string        `json:"billing_interval"`
        PeriodStart    *time.Time     `json:"current_period_start,omitempty"`
        PeriodEnd      *time.Time     `json:"current_period_end,omitempty"`
        TrialEndsAt    *time.Time     `json:"trial_ends_at,omitempty"`
        CancelAtPeriodEnd bool        `json:"cancel_at_period_end"`
        // Grace (report-only, never stored): an expired row whose deadline
        // is still inside SubGraceDays keeps full access with renewal
        // warnings. InGrace is true only for expired-by-deadline rows.
        InGrace         bool            `json:"in_grace,omitempty"`
        GraceEndsAt     *time.Time      `json:"grace_ends_at,omitempty"`
        Permissions    map[string]bool `json:"-"`
        Features       map[string]bool `json:"-"`
        Limits         map[string]int  `json:"-"`
}

// HasPermission reports whether the plan grants the permission key.
func (e *EffectivePlan) HasPermission(key string) bool {
        if e == nil || e.Permissions == nil {
                return false
        }
        return e.Permissions[key]
}

// HasFeature reports whether the plan enables a feature key.
func (e *EffectivePlan) HasFeature(key string) bool {
        if e == nil || e.Features == nil {
                return false
        }
        return e.Features[key]
}

// Limit returns the configured ceiling for a limit key (-1 = unlimited,
// 0 when the key is absent — treated as unlimited so a plan without an
// explicit limit never blocks a counter).
func (e *EffectivePlan) Limit(key string) int {
        if e == nil || e.Limits == nil {
                return 0
        }
        return e.Limits[key]
}

// Payment is one payment attempt (Paymob intention or manual registration).
type Payment struct {
        ID                string     `json:"id"`
        Number            string     `json:"number,omitempty"`
        CompanyID         string     `json:"company_id"`
        SubscriptionID    string     `json:"subscription_id,omitempty"`
        PlanID            string     `json:"plan_id"`
        BillingInterval   string     `json:"billing_interval"`
        AmountPiastres    int64      `json:"amount_piastres"`
        Currency          string     `json:"currency"`
        Provider          string     `json:"provider"`
        ProviderReference string     `json:"provider_reference,omitempty"`
        Status            string     `json:"status"`
        ConfirmedAt       *time.Time `json:"confirmed_at,omitempty"`
        ConfirmationSource string    `json:"confirmation_source,omitempty"`
        FailureCode       string     `json:"failure_code,omitempty"`
        FailureMessage    string     `json:"failure_message,omitempty"`
        RefundedAmount    int64      `json:"refunded_amount_piastres"`
        NeedsReview       bool       `json:"needs_review"`
        ReviewReason      string     `json:"review_reason,omitempty"`
        Metadata          map[string]interface{} `json:"metadata,omitempty"`
        CreatedAt         time.Time  `json:"created_at"`
        UpdatedAt         time.Time  `json:"updated_at"`
}

// PaymentSettlement is the operator-verified financial state of one online
// payment with the provider (migration 32). One row per payment; history
// lives in payment_transactions.
type PaymentSettlement struct {
        ID                         string     `json:"id"`
        PaymentID                  string     `json:"payment_id"`
        Provider                   string     `json:"provider"`
        Status                     string     `json:"status"`
        SettledAmountPiastres      *int64     `json:"settled_amount_piastres,omitempty"`
        FeesPiastres               *int64     `json:"fees_piastres,omitempty"`
        Currency                   string     `json:"currency"`
        ProviderSettlementReference string    `json:"provider_settlement_reference,omitempty"`
        SettledAt                  *time.Time `json:"settled_at,omitempty"`
        LastSyncedAt               *time.Time `json:"last_synced_at,omitempty"`
        CreatedAt                  time.Time  `json:"created_at"`
        UpdatedAt                  time.Time  `json:"updated_at"`
}

// PaymentTransaction is one raw provider event on a payment (audit ledger).
type PaymentTransaction struct {
        ID                      string                 `json:"id"`
        PaymentID               string                 `json:"payment_id"`
        TxnType                 string                 `json:"txn_type"`
        ProviderTransactionID   string                 `json:"provider_transaction_id,omitempty"`
        AmountPiastres          int64                  `json:"amount_piastres,omitempty"`
        HMACVerified            bool                   `json:"hmac_verified"`
        Payload                 map[string]interface{} `json:"payload,omitempty"`
        CreatedAt               time.Time              `json:"created_at"`
}
