# Pharmacy OS deployment contract

The frontend and API are independently deployable. The API owns authentication
and PostgreSQL access; Supabase is the PostgreSQL provider, not the frontend
API and not the authentication provider.

## 1. Deploy the backend first

The backend must be reachable over HTTPS and respond to:

```text
GET https://<backend-host>/api/v1/health
```

### Render

The repository includes `render.yaml`. Create a Render Blueprint from the
repository and provide these values in Render's environment settings:

```text
APP_ENV=production
DATABASE_URL=<Supabase connection string>
RIVER_DSN=<same Supabase connection string, unless a separate queue database is used>
CORS_ORIGINS=https://<pharmacy-vercel-domain>,https://<admin-vercel-domain>,https://<marketing-vercel-domain>
PUBLIC_APP_URL=https://<pharmacy-vercel-domain>
MAIL_FROM_EMAIL=<verified Brevo sender>
MAIL_FROM_NAME=Pharmacy OS
BREVO_API_KEY=<secret stored in Render, never in source control>
AUTH_COOKIE_SECURE=true
```

Use the Supabase connection pooler URL when the host cannot use a direct
PostgreSQL connection. The backend disables prepared statements so Supabase's
transaction pooler works correctly.

## 2. Configure each Vercel app

The recommended Vercel setup is a same-origin proxy. It keeps browser requests
on the Vercel origin and forwards them server-side to Render:

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
local machine. Do not use a private Render hostname unless the Vercel runtime
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