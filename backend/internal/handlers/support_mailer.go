// Support email notifications (Phase T1) — the quiet-hours bell.
//
// Rule: a chat message NEVER waits on an email. The REST send path only
// stamps the throttle and hands the actual Brevo call to a goroutine — a
// dead mail provider can add zero latency and zero failure to chat.
//
// Conditions for sending, all checked in order:
//  1. the receiving side has NO live WebSocket (they're not looking at the
//     chat right now — presence is the hub's knowledge);
//  2. the throttle window for this conversation+side has passed (one mail
//     per quiet window — a conversation storm must not become a mail storm);
//  3. the recipient address exists (platform: PLATFORM_SUPPORT_EMAIL or the
//     mail-from fallback; company: the account email from `companies`).
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/pharmacy-os/backend/internal/models"
)

const supportBrevoEndpoint = "https://api.brevo.com/v3/smtp/email"

// supportNotifyMaybe is called after COMMIT from every human-message path.
// senderRealm says WHO wrote; the OTHER side is notified.
func (h *Handler) supportNotifyMaybe(ctx context.Context, companyID, senderRealm, conversationID, senderName, body string) {
	if h.supportHub == nil || h.db == nil || companyID == "" {
		return
	}
	var (
		companyName, companyEmail string
		err                       error
	)
	err = h.db.QueryRow(ctx,
		`SELECT name, email FROM companies WHERE id = $1::uuid`, companyID,
	).Scan(&companyName, &companyEmail)
	if err != nil || companyEmail == "" {
		return // no address → nothing to notify, and not an error worth noise
	}

	// The throttle stamp rides the caller's post-commit connection as its
	// own tiny transaction — optimistic: even if the mail send later fails,
	// the window still holds (no mail storms while a provider is down).
	throttleColumn := "last_notified_platform_at"
	if senderRealm == models.SupportSenderPlatform {
		throttleColumn = "last_notified_company_at"
	}
	tag, err := h.db.Exec(ctx, `
        UPDATE support_conversations SET `+throttleColumn+` = NOW()
        WHERE id = $1::uuid
          AND (`+throttleColumn+` IS NULL OR `+throttleColumn+` < NOW() - ($2::bigint * INTERVAL '1 second'))
    `, conversationID, int64(models.SupportEmailThrottleWindow/time.Second))
	if err != nil {
		log.Printf("[support-mail] throttle stamp failed conv=%s: %v", conversationID, err)
		return
	}
	if tag.RowsAffected() == 0 {
		return // inside the quiet window — already notified recently
	}

	if senderRealm == models.SupportSenderPharmacy {
		if h.supportHub.PlatformSupportOnline() {
			return // the desk is literally looking at the inbox
		}
		to := strings.TrimSpace(os.Getenv("PLATFORM_SUPPORT_EMAIL"))
		if to == "" {
			to = h.config.MailFromEmail // sane fallback: the operator mailbox
		}
		if to == "" || h.config.BrevoAPIKey == "" {
			return
		}
		subject := "New support message — " + companyName
		go sendSupportEmail(h.config.BrevoAPIKey, h.config.MailFromEmail, h.config.MailFromName, to, subject,
			supportMailHTML(senderName, companyName, body, true),
			supportMailText(senderName, companyName, body, true))
		return
	}

	// Platform → company.
	if h.supportHub.CompanySupportOnline(companyID) {
		return
	}
	if h.config.BrevoAPIKey == "" {
		return
	}
	subject := "رد جديد من فريق الدعم — Pharmacy OS"
	go sendSupportEmail(h.config.BrevoAPIKey, h.config.MailFromEmail, h.config.MailFromName, companyEmail, subject,
		supportMailHTML(senderName, companyName, body, false),
		supportMailText(senderName, companyName, body, false))
}

func supportMailText(from, company, body string, toPlatform bool) string {
	if toPlatform {
		return from + " (" + company + ") أرسل رسالة دعم جديدة:\n\n" + body
	}
	return "رد من فريق الدعم (" + from + "):\n\n" + body
}

func supportMailHTML(from, company, body string, toPlatform bool) string {
	title := "رد جديد من فريق الدعم"
	who := from
	if toPlatform {
		title = "رسالة دعم جديدة"
		who = from + " — " + company
	}
	var b strings.Builder
	b.WriteString(`<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;background:#f6f7f9;padding:24px">`)
	b.WriteString(`<div style="max-width:520px;margin:auto;background:#fff;border-radius:12px;padding:24px">`)
	b.WriteString(`<h2 style="margin:0 0 12px;color:#0f766e;font-size:18px">Pharmacy OS — ` + title + `</h2>`)
	b.WriteString(`<p style="margin:0 0 8px;color:#475569;font-size:14px">` + who + `</p>`)
	b.WriteString(`<p style="margin:0;color:#0f172a;font-size:15px;line-height:1.6;white-space:pre-wrap">` + body + `</p>`)
	b.WriteString(`<p style="margin:16px 0 0;color:#94a3b8;font-size:12px">افتح لوحة الدعم في التطبيق لمتابعة المحادثة.</p>`)
	b.WriteString(`</div></body></html>`)
	return b.String()
}

// sendSupportEmail is the minimal Brevo transactional call (same endpoint
// and contract as internal/auth mailer — kept local so the support feature
// never couples to the auth package's internals).
func sendSupportEmail(apiKey, fromEmail, fromName, to, subject, html, text string) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	payload, err := json.Marshal(map[string]any{
		"sender":      map[string]string{"email": fromEmail, "name": fromName},
		"to":          []map[string]string{{"email": to}},
		"subject":     subject,
		"htmlContent": html,
		"textContent": text,
	})
	if err != nil {
		return
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, supportBrevoEndpoint, bytes.NewReader(payload))
	if err != nil {
		return
	}
	req.Header.Set("accept", "application/json")
	req.Header.Set("content-type", "application/json")
	req.Header.Set("api-key", apiKey)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("[support-mail] send failed: %v", err)
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("[support-mail] brevo returned %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
		return
	}
	log.Printf("[support-mail] sent: to=%s subject=%q", to, subject)
}
