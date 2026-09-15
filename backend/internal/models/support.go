// Support system models (live chat + tickets, Phase T1 — migration 33).
//
// Three separate answers, like the settlement design before it:
//
//   CONVERSATION — the live chat channel (open | closed) with per-side
//                  unread counters. Never plan-gated.
//   TICKET       — the work item (full lifecycle) that may be linked to a
//                  conversation; changes surface as system chat messages.
//   MESSAGE      — append-only chat text (<= SupportMaxMessageLength) with
//                  an optional attachment; system rows record lifecycle.
package models

import "time"

// Support conversation (the chat channel) statuses.
const (
	SupportConversationOpen   = "open"
	SupportConversationClosed = "closed"
)

// Support message sender realms.
const (
	SupportSenderPlatform = "platform"
	SupportSenderPharmacy = "pharmacy"
)

// Support ticket lifecycle statuses.
const (
	SupportTicketOpen            = "open"
	SupportTicketInProgress      = "in_progress"
	SupportTicketWaitingCustomer = "waiting_customer"
	SupportTicketResolved        = "resolved"
	SupportTicketClosed          = "closed"
)

// Support ticket priorities.
const (
	SupportPriorityLow    = "low"
	SupportPriorityNormal = "normal"
	SupportPriorityHigh   = "high"
	SupportPriorityUrgent = "urgent"
)

// Support ticket categories.
const (
	SupportCategoryBilling         = "billing"
	SupportCategoryTechnical       = "technical"
	SupportCategoryInventory       = "inventory"
	SupportCategoryAccount         = "account"
	SupportCategoryFeatureRequest  = "feature_request"
	SupportCategoryOther           = "other"
)

// System message kinds (support_messages.system_kind — the chat-visible
// audit trail of ticket/conversation lifecycle events).
const (
	SupportSystemTicketCreated   = "ticket.created"
	SupportSystemTicketUpdated   = "ticket.updated"
	SupportSystemTicketResolved  = "ticket.resolved"
	SupportSystemTicketReopened  = "ticket.reopened"
	SupportSystemConversationClosed = "conversation.closed"
)

// Support limits — enforced in the handlers AND in migration 33 CHECKs.
const (
	SupportMaxMessageLength    = 4000          // characters (body CHECK)
	SupportMaxAttachmentBytes  = 2 << 20       // 2 MiB (size_bytes CHECK)
	SupportEmailThrottleWindow = 15 * time.Minute // one quiet-hours mail per side per window
)

// SupportAttachmentMIMEs is the upload allow-list: the file types support
// actually needs (screenshots + PDF invoices/reports). Anything else is
// rejected at upload time.
var SupportAttachmentMIMEs = map[string]string{
	"image/png":  ".png",
	"image/jpeg": ".jpg",
	"image/webp": ".webp",
	"image/gif":  ".gif",
	"application/pdf": ".pdf",
}

// SupportConversation is one company's chat channel with the platform.
type SupportConversation struct {
	ID                        string     `json:"id"`
	CompanyID                 string     `json:"company_id"`
	Subject                   string     `json:"subject"`
	Status                    string     `json:"status"`
	ClosedBy                  *string    `json:"closed_by,omitempty"`
	LastMessageAt             *time.Time `json:"last_message_at,omitempty"`
	LastMessagePreview        string     `json:"last_message_preview"`
	PlatformUnreadCount       int        `json:"platform_unread_count"`
	CompanyUnreadCount        int        `json:"company_unread_count"`
	PlatformLastReadMessageID *string    `json:"platform_last_read_message_id,omitempty"`
	CompanyLastReadMessageID  *string    `json:"company_last_read_message_id,omitempty"`
	CreatedAt                 *time.Time `json:"created_at,omitempty"`
	UpdatedAt                 *time.Time `json:"updated_at,omitempty"`
	// Joined for the platform inbox (and absent for pharmacy listings).
	CompanyName *string `json:"company_name,omitempty"`
	CompanyEmail *string `json:"company_email,omitempty"`
}

// SupportMessage is one append-only chat row.
type SupportMessage struct {
	ID             string     `json:"id"`
	ConversationID string     `json:"conversation_id"`
	SenderRealm    string     `json:"sender_realm"`
	SenderID       *string    `json:"sender_id,omitempty"`
	SenderName     string     `json:"sender_name"`
	Body           string     `json:"body"`
	AttachmentID   *string    `json:"attachment_id,omitempty"`
	IsSystem       bool       `json:"is_system"`
	SystemKind     *string    `json:"system_kind,omitempty"`
	CreatedAt      *time.Time `json:"created_at,omitempty"`
}

// SupportTicket is the support work item.
type SupportTicket struct {
	ID              string     `json:"id"`
	CompanyID       string     `json:"company_id"`
	ConversationID  *string    `json:"conversation_id,omitempty"`
	Number          string     `json:"number"`
	Subject         string     `json:"subject"`
	Status          string     `json:"status"`
	Priority        string     `json:"priority"`
	Category        string     `json:"category"`
	AssignedTo      *string    `json:"assigned_to,omitempty"`
	ResolutionNote  *string    `json:"resolution_note,omitempty"`
	ResolvedAt      *time.Time `json:"resolved_at,omitempty"`
	ClosedAt        *time.Time `json:"closed_at,omitempty"`
	CreatedAt       *time.Time `json:"created_at,omitempty"`
	UpdatedAt       *time.Time `json:"updated_at,omitempty"`
	// Joined for the platform ticket table.
	CompanyName *string `json:"company_name,omitempty"`
}

// SupportAttachmentMeta is the upload response / message join shape — never
// the raw bytes.
type SupportAttachmentMeta struct {
	ID          string     `json:"id"`
	FileName    string     `json:"file_name"`
	MimeType    string     `json:"mime_type"`
	SizeBytes   int64      `json:"size_bytes"`
	CreatedAt   *time.Time `json:"created_at,omitempty"`
}
