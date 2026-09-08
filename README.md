# Pharmacy OS

Pharmacy OS is a pharmacy-management system split into a backend and three independently deployable frontend applications:

## Frontend

The `frontend/` directory contains the complete Next.js 16 / React 19 frontend monorepo:

- `frontend/apps/pharmacy-app/` — the main pharmacy dashboard with inventory, employees, attendance, branches, reports, and settings.
- `frontend/apps/admin-dashboard/` — the admin/super-admin panel for companies, pharmacies, users, permissions, and analytics.
- `frontend/apps/marketing/` — the public landing page, pricing, privacy policy, and terms pages.

Each app remains independently deployable on Vercel using its own directory as the Vercel Root Directory. The imported frontend repository was refreshed from the latest upstream commit without installing dependencies or changing its app settings. See `frontend/README.md` for the deployment details.

## Backend

The `backend/` directory contains the Go 1.25 Gin REST API. It provides the backend services for pharmacies, inventory, employees, branches, attendance, dashboard data, permissions, and multi-tenant company support.

Backend documentation, migrations, tests, and dependency files are in `backend/README.md`.

To run the backend locally:

```bash
cd backend
go mod download
go run ./cmd/server
```

The API listens on port `8080`.