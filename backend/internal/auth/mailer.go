package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net/http"
	"strings"
	"time"
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
		client: &http.Client{Timeout: 15 * time.Second},
	}
}

func (m *mailer) configured() bool {
	return m.apiKey != "" && m.fromEmail != ""
}

func (m *mailer) send(ctx context.Context, recipient, subject, html, text string) error {
	if !m.configured() {
		return fmt.Errorf("transactional email is not configured")
	}
	body, err := json.Marshal(map[string]interface{}{
		"sender":      map[string]string{"email": m.fromEmail, "name": m.fromName},
		"to":          []map[string]string{{"email": recipient}},
		"subject":     subject,
		"htmlContent": html,
		"textContent": text,
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
		details, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
		detail := strings.TrimSpace(string(details))
		if detail == "" {
			return fmt.Errorf("brevo returned status %d", response.StatusCode)
		}
		return fmt.Errorf("brevo returned status %d: %s", response.StatusCode, detail)
	}
	return nil
}

func (m *mailer) verificationEmail(ctx context.Context, email, code string) error {
	logoURL := html.EscapeString(m.assetURL("brand/pharmacy-os-icon.png"))
	logo := `<span style="display:inline-block;width:46px;height:46px;border-radius:14px;background:#00d084;color:#06100d;font-size:20px;line-height:46px;text-align:center;font-weight:800;">P</span>`
	if logoURL != "" {
		logo = fmt.Sprintf(`<img src="%s" alt="Pharmacy OS" width="46" height="46" style="display:block;width:46px;height:46px;border:0;border-radius:14px;" />`, logoURL)
	}
	emailHTML := fmt.Sprintf(`<!doctype html>
<html lang="ar" dir="rtl">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>تأكيد البريد الإلكتروني — Pharmacy OS</title></head>
<body style="margin:0;padding:0;background:#050a09;color:#f4fff8;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%%" cellspacing="0" cellpadding="0" border="0" style="width:100%%;background:#050a09;">
    <tr><td align="center" style="padding:32px 14px 44px;">
      <table role="presentation" width="100%%" cellspacing="0" cellpadding="0" border="0" style="max-width:620px;">
        <tr><td style="padding:0 8px 22px;">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="right" dir="ltr">
            <tr>
              <td valign="middle">%s</td>
              <td style="padding-left:12px;color:#f4fff8;font-size:17px;font-weight:800;letter-spacing:-.4px;">Pharmacy <span style="color:#00d084;">OS</span></td>
            </tr>
          </table>
        </td></tr>
        <tr><td style="background:#0a1511;border:1px solid #2b493a;border-radius:24px;padding:42px 34px 38px;text-align:right;">
          <table role="presentation" width="100%%" cellspacing="0" cellpadding="0" border="0" dir="rtl">
            <tr><td style="color:#00d084;font-size:12px;font-weight:800;letter-spacing:1.6px;text-transform:uppercase;padding-bottom:18px;">PHARMACY OPERATING SYSTEM</td></tr>
            <tr><td style="color:#ffffff;font-size:30px;line-height:1.45;font-weight:800;padding-bottom:14px;">أهلًا بك في<br><span style="color:#00d084;">Pharmacy OS</span></td></tr>
            <tr><td style="color:#d7e8dc;font-size:16px;line-height:1.9;padding-bottom:28px;">باقي خطوة واحدة لتفعيل حسابك والبدء في إدارة صيدليتك بوضوح أكبر.</td></tr>
            <tr><td align="center" style="background:#10251b;border:1px solid #347b59;border-radius:18px;padding:25px 18px 23px;">
              <div style="color:#d7e8dc;font-size:14px;line-height:1.6;">رمز التحقق الخاص بك</div>
              <div dir="ltr" style="color:#00d084;font-size:44px;line-height:1.25;font-weight:800;letter-spacing:12px;padding:10px 0 8px 12px;">%s</div>
              <div style="color:#b5cbbd;font-size:12px;line-height:1.6;">6 أرقام&nbsp; • &nbsp;صالح لمدة 24 ساعة</div>
            </td></tr>
            <tr><td style="color:#d7e8dc;font-size:14px;line-height:1.9;padding-top:26px;">أدخل الرمز في شاشة تأكيد البريد الإلكتروني داخل التطبيق. إذا لم تطلب إنشاء هذا الحساب، يمكنك تجاهل هذه الرسالة.</td></tr>
          </table>
        </td></tr>
        <tr><td align="center" style="color:#a9bdb0;font-size:12px;line-height:1.8;padding:24px 18px 0;">بُني للصيدليات التي تريد أن تنمو<br><span style="color:#00d084;font-weight:700;">Pharmacy OS</span> &nbsp;•&nbsp; © 2026</td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`, logo, html.EscapeString(code))
	text := fmt.Sprintf("أهلًا بك في Pharmacy OS.\n\nرمز تأكيد البريد الإلكتروني: %s\n\nأدخل الرمز في شاشة التحقق داخل التطبيق. الرمز صالح لمدة 24 ساعة.\n\nإذا لم تطلب إنشاء هذا الحساب، يمكنك تجاهل هذه الرسالة.", code)
	return m.send(ctx, email, "تأكيد بريدك الإلكتروني — Pharmacy OS", emailHTML, text)
}

func (m *mailer) assetURL(path string) string {
	if m.appURL == "" {
		return ""
	}
	return strings.TrimRight(m.appURL, "/") + "/" + strings.TrimLeft(path, "/")
}

func (m *mailer) resetEmail(ctx context.Context, email, token string) error {
	if m.appURL == "" {
		return fmt.Errorf("public app URL is not configured")
	}
	link := fmt.Sprintf("%s/reset-password?token=%s", m.appURL, token)
	html := fmt.Sprintf(
		`<p>We received a request to reset your Pharmacy OS password.</p><p>Reset it by clicking <a href="%s">this link</a>.</p><p>This link expires in one hour.</p>`,
		link,
	)
	text := fmt.Sprintf("Reset your Pharmacy OS password using this link: %s\n\nThis link expires in one hour.", link)
	return m.send(ctx, email, "Reset your Pharmacy OS password", html, text)
}
