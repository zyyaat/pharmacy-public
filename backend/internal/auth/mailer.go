package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

type mailer struct {
	apiKey    string
	fromEmail string
	fromName  string
	appURL    string
	client    *http.Client
}

func newMailer(cfg Config) *mailer {
	return &mailer{
		apiKey: cfg.BrevoAPIKey, fromEmail: cfg.MailFromEmail,
		fromName: cfg.MailFromName, appURL: strings.TrimRight(cfg.PublicAppURL, "/"),
		client: &http.Client{},
	}
}

func (m *mailer) configured() bool {
	return m.apiKey != "" && m.fromEmail != "" && m.appURL != ""
}

func (m *mailer) send(ctx context.Context, recipient, subject, html string) error {
	if !m.configured() {
		return fmt.Errorf("transactional email is not configured")
	}
	body, err := json.Marshal(map[string]interface{}{
		"sender":  map[string]string{"email": m.fromEmail, "name": m.fromName},
		"to":      []map[string]string{{"email": recipient}},
		"subject": subject, "htmlContent": html,
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.brevo.com/v3/smtp/email", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("accept", "application/json")
	req.Header.Set("content-type", "application/json")
	req.Header.Set("api-key", m.apiKey)
	response, err := m.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("brevo returned status %d", response.StatusCode)
	}
	return nil
}

func (m *mailer) verificationEmail(ctx context.Context, email, token string) error {
	link := fmt.Sprintf("%s/verify-email?token=%s", m.appURL, token)
	return m.send(ctx, email, "Verify your Pharmacy OS email", fmt.Sprintf(
		`<p>Welcome to Pharmacy OS.</p><p>Verify your email by clicking <a href="%s">this link</a>.</p><p>This link expires in 24 hours.</p>`,
		link,
	))
}

func (m *mailer) resetEmail(ctx context.Context, email, token string) error {
	link := fmt.Sprintf("%s/reset-password?token=%s", m.appURL, token)
	return m.send(ctx, email, "Reset your Pharmacy OS password", fmt.Sprintf(
		`<p>We received a request to reset your Pharmacy OS password.</p><p>Reset it by clicking <a href="%s">this link</a>.</p><p>This link expires in one hour.</p>`,
		link,
	))
}
