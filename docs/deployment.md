# Pharmacy OS deployment contract

The frontend and API are independently deployable. The API owns authentication
and PostgreSQL access; Supabase is the PostgreSQL provider, not the frontend
API and not the authentication provider.

## 1. Deploy the backend on DockHosting (Docker)

The backend ships a production `backend/Dockerfile` (multi-stage build, Alpine
runtime image, honors the `PORT` environment variable). DockHosting builds it
directly from this repository — no platform blueprint file is needed.

The backend must be reachable over HTTPS and respond to:

```text
GET https://<backend-host>/api/v1/health
```

Environment variables to set on the DockHosting service:

```text
APP_ENV=production
DATABASE_URL=<Supabase connection string>
RIVER_DSN=<same Supabase connection string, unless a separate queue database is used>
CORS_ORIGINS=https://<pharmacy-vercel-domain>,https://<admin-vercel-domain>,https://<marketing-vercel-domain>
PUBLIC_APP_URL=https://<pharmacy-vercel-domain>
MAIL_FROM_EMAIL=<verified Brevo sender>
MAIL_FROM_NAME=Pharmacy OS
BREVO_API_KEY=<secret stored in the hosting panel, never in source control>
AUTH_COOKIE_SECURE=true
```

Notes:

- The server resolves its port as `PORT` (DockHosting/standard) first, then
  `BACKEND_PORT`, then `8080` — see `backend/internal/config/config.go`.
- Go dependencies are vendored (`backend/vendor/`), so the image build never
  downloads modules from the network and cannot fail on registry hiccups.
- `backend/docker-compose.yml` mirrors the same container for VPS use
  (`docker compose up -d`), including a wget healthcheck against
  `/api/v1/health`.

### Verifying the deployed build

`GET /api/v1/health` reports `status` and `api_level`. The `api_level`
constant (see `backend/internal/handlers/handler.go`) is bumped with every
behavioral backend change. If the endpoint does not report the level you
expect, the running container is stale: rebuild and redeploy the service on
DockHosting and re-check before debugging anything else. This check requires
no credentials and settles "did my push actually ship?" in seconds.

Use the Supabase connection pooler URL when the host cannot use a direct
PostgreSQL connection. The backend disables prepared statements so Supabase's
transaction pooler works correctly.

## 2. Configure each Vercel app

The recommended Vercel setup is a same-origin proxy. It keeps browser requests
on the Vercel origin and forwards them server-side to the DockHosting backend:

```text
NEXT_PUBLIC_API_URL=/api/v1
BACKEND_INTERNAL_URL=https://<backend-host>
```

`BACKEND_INTERNAL_URL` is used by Next.js rewrites and must not have `/api/v1`
at the end. It is not a browser-exposed variable. Set it in the Vercel
Production environment and redeploy after changing it.

For a direct browser-to-API setup instead, use:

```text
NEXT_PUBLIC_API_URL=https://<backend-host>/api/v1
```

In direct mode, the backend `CORS_ORIGINS` must include every exact Vercel
origin. The proxy mode is preferred because it avoids cross-site cookie and
browser CORS problems.

The Vercel project root directories are:

```text
frontend/apps/pharmacy-app
frontend/apps/admin-dashboard
frontend/apps/marketing
```

Do not set `BACKEND_INTERNAL_URL` to `localhost` or `127.0.0.1` in Vercel.
Those addresses point to the Vercel runtime, not the Replit workspace or your
local machine. Do not use a private backend hostname unless the Vercel runtime
can resolve and reach it.

## 3. Authentication and CORS rules

The browser sends HTTP-only cookies with `credentials: include`. Therefore:

- `CORS_ORIGINS` must contain the exact HTTPS frontend origins.
- Do not use a wildcard origin.
- Do not add paths or trailing slashes to an origin.
- Keep `AUTH_COOKIE_DOMAIN` empty when frontend and API are on different hosts.
- Production cookies use `Secure` and `SameSite=None`.

Example:

```text
CORS_ORIGINS=https://pharmacy-os.vercel.app,https://pharmacy-admin.vercel.app
```

The API should be tested from the browser origin, not only by opening the API
URL directly:

```bash
curl -i -X OPTIONS https://<backend-host>/api/v1/auth/login \
  -H 'Origin: https://<pharmacy-vercel-domain>' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type'
```

The response must include:

```text
Access-Control-Allow-Origin: https://<pharmacy-vercel-domain>
Access-Control-Allow-Credentials: true
```

## 4. Replit development

Keep `NEXT_PUBLIC_API_URL=/api/v1` in the Replit workflow. Next.js proxies that
relative path to `BACKEND_INTERNAL_URL`, which defaults to
`http://127.0.0.1:8080`.

For a frontend deployed on another host, use the public API URL instead; the
local proxy is never used by the browser in production.

## 5. Transactional email deliverability (OTP to Outlook/Hotmail)

### "Sending succeeded" means Brevo accepted it — not that it was delivered

When the backend returns success for a verification code or password reset
email, that success reflects one thing: the Brevo API accepted the message
(HTTP 2xx and returned a `messageId`, now captured in the backend logs).
Delivery to the recipient's mail provider happens afterwards, asynchronously,
inside Brevo. Gmail is forgiving; **Microsoft-hosted recipients
(outlook.com, outlook.sa, hotmail.com, live.com) routinely and silently drop
messages sent from Brevo's shared IP pools** — the message never reaches the
inbox and often never even the junk folder. This is a provider-side
reputation issue, not a bug in the application.

### Diagnose a missing message

1. Log in to Brevo → **Transactional → Logs / Events** and search the
   recipient address. Event meanings:
   - `delivered` — the provider accepted it; check junk/quarantine next.
   - `blocked`, `softBounce`, `hardBounce`, `deferred`, `spam` — the
     provider (or Brevo pre-send filters) refused or postponed it. The
     `reason` field carries the provider's SMTP response (a Microsoft
     `550 5.7.1 ...` block-list reply is typical).
   - no events — nothing was sent to that address within Brevo's retention
     window, or the address was mistyped.
2. Or query it without leaving the app — the backend exposes a
   platform-admin-only endpoint that proxies Brevo's event log:

   ```bash
   # 1) platform admin login (persist cookies)
   curl -s -c /tmp/plat.jar -X POST https://<backend-host>/api/v1/auth/platform/login \
     -H 'Content-Type: application/json' \
     -d '{"email":"<super-admin-email>","password":"<super-admin-password>"}'

   # 2) read the delivery truth for the affected address
   curl -s -b /tmp/plat.jar \
     'https://<backend-host>/api/v1/auth/platform/email-delivery-status?email=user@outlook.sa'
   ```

   The response lists the latest events with dates and reasons, a per-status
   summary, and an Arabic `hint` explaining the verdict
   (`delivered` / `rejected_or_deferred` / `no_delivery_evidence` / `no_events`).

### Fix deliverability for Microsoft recipients (runbook)

1. **Authenticate the sending domain in Brevo** (Senders, Domains & Dedicated
   IPs → Domains): add the DKIM/SPF (Brevo code) DNS records it generates,
   verify them, and ideally publish DMARC (`p=none` to start) on the domain.
   Unauthenticated domains are the single most common cause of silent
   Microsoft drops.
2. **Send from a custom-domain sender.** `MAIL_FROM_EMAIL` on a free mailbox
   (gmail.com/outlook.com) is treated as spoofing by Microsoft. Use e.g.
   `no-reply@<your-domain>`, verified in Brevo (Senders).
3. **If the domain is authenticated and messages still bounce**: the shared
   IP reputation with Microsoft is the bottleneck. Open a Brevo support
   ticket including the `messageId`s of affected messages and ask them to
   review their Microsoft/SNDS standing; the durable fix is a dedicated IP.
4. **Recipient-side hardening** (limited effect but free): ask the recipient
   to add the sender to Outlook's safe-senders list and check
   `https://outlook.live.com/mail/0/junkemail` via web — the web client
   sometimes shows messages the phone app hides.

The backend `messageId` acceptance log line
(`[mailer] brevo accepted send: message_id=... to=...`) correlates an
application-level send with Brevo's log — use it when reporting to Brevo
support.

## 6. Paymob payment environment variables (Phase G — embedded checkout)

The Plans & Subscriptions system (migration 26) ships with BOTH billing
paths: super-admin manual payments AND the Paymob embedded online checkout.
The card form renders INSIDE the pharmacy app's subscription modal
(Unified Checkout iframe) — the customer never navigates to a Paymob page
and back, and card data never touches our servers (PCI on Paymob's iframe).

The credentials are read exclusively from environment variables on the
DockHosting **backend** service. None of these values belong in Vercel, in
`NEXT_PUBLIC_*` variables, or in source control. The frontend never holds a
Paymob secret — the public key and the iframe URL are returned by the
backend's checkout endpoint, built server-side.

With the variables unset, the checkout endpoint answers
`paymob_not_configured` and billing falls back to manual payments — setting
them is the ONLY step needed to switch online payments on (then rebuild the
service).

| Variable | Required | Purpose |
| --- | --- | --- |
| `PAYMOB_API_KEY` | Yes | Secret API key used server-side to authenticate intention requests (`Authorization: Token …`). Never exposed to any client. |
| `PAYMOB_PUBLIC_KEY` | Yes | Public key (`pk_test_...` / `pk_live_...`) embedded in the Unified Checkout iframe URL, built server-side. |
| `PAYMOB_CARD_INTEGRATION_ID` | Yes | Numeric integration ID of the **Online Card** channel. |
| `PAYMOB_WALLET_INTEGRATION_ID` | Optional | Numeric integration ID of the **Mobile Wallets** channel (Vodafone Cash etc.). |
| `PAYMOB_HMAC_SECRET` | Yes | HMAC-SHA512 secret used to verify Paymob webhooks. Webhook activation is the ONLY trusted path that activates or extends a paid subscription. |
| `PAYMOB_WEBHOOK_TOKEN` | Recommended | Long random string appended to the webhook URL (`?token=…`) as a second provider-independent check. |
| `PAYMOB_BASE_URL` | Optional | API base override; defaults to `https://accept.paymob.com`. For staging/testing only. |

Where to get each value (Paymob dashboard → Developers section):

| Value | Dashboard location |
| --- | --- |
| API Key | Developers → Account Information → API Key |
| Public Key | Developers → Account Information → Public Key (`pk_...`) |
| Integration IDs | Developers → Payment Integrations → numeric ID beside each channel (Online Card, Mobile Wallets) |
| HMAC secret | Developers → Webhooks → the HMAC secret shown when registering a webhook response URL |

Webhook URL to register in the Paymob dashboard (HTTPS only, exact path —
the route is LIVE now):

```text
https://<backend-host>/api/v1/payments/webhook/paymob?token=<PAYMOB_WEBHOOK_TOKEN>
```

Embedded payment flow (why these variables are enough):

1. `POST /pharmacy/subscription/checkout` (owner session + CSRF) creates a
   `pending` payment row, then the intention server-side (`PAYMOB_API_KEY`,
   snapshot pricing from the plan row — later plan edits never change an
   open invoice) and returns `client_secret` + the iframe URL.
2. The subscription page (web) or an in-app WebView (mobile) renders the
   Unified Checkout iframe from that URL. Card entry happens inside
   Paymob's frame; the customer stays in the app.
3. While the modal is open the app polls
   `GET /pharmacy/subscription/payments/:id` — display only.
4. Paymob calls the webhook; the backend verifies HMAC-SHA512 over the
   documented field order (`PAYMOB_HMAC_SECRET`) plus the URL token,
   cross-checks the amount against the stored snapshot, records the raw
   payload in `payment_transactions` with `hmac_verified=true`, and only
   then activates or extends the subscription via the SAME transition the
   manual-payment path uses. Replays are idempotent; a tampered amount
   fails the payment instead of activating it.
