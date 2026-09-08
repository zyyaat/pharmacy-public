// Package jobs - Notification Sender Job
//
// This job handles sending notifications to users via multiple channels:
// - In-app notifications (stored in DB, read via Supabase Realtime)
// - Email notifications (via external service like SendGrid/SES)
// - Push notifications (via FCM/APNs - future enhancement)
//
// Trigger: Inserted by other jobs (expiry_check, low_stock_check, etc.)
// Action: Deliver notification to user's preferred channels
// Output: Notification delivery status logged in audit_logs

package jobs

import (
	"context"
	"time"
)

// NotificationSenderWorker handles sending notifications
// TODO: Implement with River JobArgs interface
type NotificationSenderWorker struct {
	UserID      string `json:"user_id"`
	PharmacyID  string `json:"pharmacy_id"`
	Type        string `json:"type"` // email, push, in_app
	Title       string `json:"title"`
	Body        string `json:"body"`
	Data        string `json:"data"` // JSON payload for additional data
	Priority    string `json:"priority"` // low, normal, high, urgent
}

// NotificationChannel represents a delivery channel
type NotificationChannel string

const (
	ChannelInApp  NotificationChannel = "in_app"
	ChannelEmail  NotificationChannel = "email"
	ChannelPush   NotificationChannel = "push"
)

// NotificationStatus represents delivery status
type NotificationStatus string

const (
	StatusPending   NotificationStatus = "pending"
	StatusSent      NotificationStatus = "sent"
	StatusDelivered NotificationStatus = "delivered"
	StatusFailed    NotificationStatus = "failed"
)

// NotificationRecord represents a stored notification
type NotificationRecord struct {
	ID          string              `json:"id"`
	UserID      string              `json:"user_id"`
	PharmacyID  string              `json:"pharmacy_id"`
	Type        NotificationChannel `json:"type"`
	Title       string              `json:"title"`
	Body        string              `json:"body"`
	Data        string              `json:"data"`
	Status      NotificationStatus  `json:"status"`
	ReadAt      *time.Time          `json:"read_at,omitempty"`
	CreatedAt   time.Time           `json:"created_at"`
	SentAt      *time.Time          `json:"sent_at,omitempty"`
}

// SendResult holds the result of a send operation
type SendResult struct {
	NotificationID string            `json:"notification_id"`
	Channel        NotificationChannel `json:"channel"`
	Status         NotificationStatus  `json:"status"`
	ErrorMessage   string             `json:"error_message,omitempty"`
}

// Run executes the notification sending job
// TODO: Implement actual logic:
// 1. Determine target channels based on user preferences
// 2. For in_app: Insert into notifications table (triggers Realtime)
// 3. For email: Queue with email service (SendGrid/SES)
// 4. For push: Send to FCM/APNs (future)
// 5. Update notification status
// 6. Log delivery attempt in audit_logs
func (w *NotificationSenderWorker) Run(ctx context.Context) (*SendResult, error) {
	// Placeholder implementation
	_ = ctx
	
	return &SendResult{
		NotificationID: "",
		Channel:        ChannelInApp,
		Status:         StatusPending,
	}, nil
}
