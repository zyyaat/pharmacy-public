# Pharmacy OS Backend API

[![Go Version](https://img.shields.io/badge/Go-1.21-blue.svg)](https://golang.org)
[![Gin Framework](https://img.shields.io/badge/Gin-v1.9.1-green.svg)](https://gin-gonic.com)
[![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL-blue.svg)](https://postgresql.org)

## 📋 Overview

Pharmacy OS Backend is a RESTful API built with Go (Gin framework) for managing pharmacy operations including inventory, employees, branches, and more.

## 🚀 Quick Start

### Prerequisites

- Go 1.21+
- PostgreSQL (Supabase can be used as the PostgreSQL provider)
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/zyyaat/pharmacy-os-backend.git
cd pharmacy-os-backend

# Copy environment file
cp .env.example .env
# Edit .env with your configuration

# Install dependencies
go mod download

# Run the server
go run ./cmd/server
```

### Using Docker

```bash
# Build the image
docker build -t pharmacy-os-backend .

# Run the container
docker run -p 8080:8080 --env-file .env pharmacy-os-backend
```

## ⚙️ Configuration

See [`.env.example`](.env.example) for all available environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `8080` |
| `APP_ENV` | Environment (development/staging/production) | `development` |
| `DATABASE_URL` | PostgreSQL connection string | - |
| `AUTH_COOKIE_SECURE` | Set to `true` in production | `false` |
| `AUTH_COOKIE_DOMAIN` | Optional cookie domain | - |
| `BREVO_API_KEY` | Brevo API key for verification code and password reset email | - |
| `MAIL_FROM_EMAIL` | Verified Brevo sender email | - |
| `MAIL_FROM_NAME` | Sender name | `Pharmacy OS` |
| `PUBLIC_APP_URL` | Public frontend URL used in email links | - |
| `RIVER_DSN` | River Queue DSN | Same as DATABASE_URL |
| `CORS_ORIGINS` | Allowed CORS origins | `localhost:3000,3001` |
| `BOOTSTRAP_SUPER_ADMIN_EMAIL` | The only allowed initial platform administrator email | Required in production |
| `BOOTSTRAP_SUPER_ADMIN_PASSWORD` | One-time secret used only when initializing a new database | Required for a new database |
| `BOOTSTRAP_SUPER_ADMIN_FIRST_NAME` | Initial platform administrator first name | `Mohamed` |
| `BOOTSTRAP_SUPER_ADMIN_LAST_NAME` | Initial platform administrator last name | `Admin` |
| `BOOTSTRAP_SUPER_ADMIN_COMPANY` | Initial platform company name | `Pharmacy OS` |

In production, the backend verifies the singleton Super Admin bootstrap on every
startup. A new database is initialized only when the bootstrap password secret
is present. After successful initialization, the password secret may be removed;
the persisted bootstrap state keeps later restarts idempotent. If a new
database is provisioned later, add the secret again deliberately for that
one-time initialization.

## 📁 Project Structure

```
pharmacy-os-backend/
├── cmd/
│   └── server/
│       └── main.go          # Entry point
├── internal/
│   ├── config/              # Configuration management
│   ├── handlers/            # HTTP handlers
│   ├── middleware/           # Auth, CORS, logging
│   ├── models/              # Data structures
│   ├── repository/          # Database operations
│   ├── services/            # Business logic
│   └── jobs/                # Background jobs
├── migrations/              # SQL database migrations
├── tests/                   # Integration tests
├── Dockerfile               # Docker configuration
├── Procfile                 # Process file for deployment
├── go.mod                   # Go modules
└── go.sum                   # Dependencies checksum
```

## 🔌 API Endpoints

### Health Check
```
GET /api/v1/health
GET /health
```

Response:
```json
{
  "status": "healthy",
  "service": "pharmacy-os-api"
}
```

### Pharmacies
```
GET    /api/v1/pharmacies     # List pharmacies
GET    /api/v1/pharmacies/:id # Get pharmacy
POST   /api/v1/pharmacies     # Create pharmacy
PUT    /api/v1/pharmacies/:id # Update pharmacy
```

### Dashboard
```
GET /api/v1/dashboard/stats    # Dashboard statistics
GET /api/v1/dashboard/activity # Recent activity
```

## 🗄️ Database Migrations

SQL migration files are located in the [`migrations/`](migrations/) directory:

1. `00000000000001_foundation.sql` - Core tables
2. `00000000000002_products_inventory.sql` - Products & inventory
3. `00000000000003_permissions_auth.sql` - Permissions & auth
4. `00000000000004_audit_logs.sql` - Audit logging
5. `00000000000005_holding_company.sql` - Multi-tenant support
6. `00000000000006_go_auth.sql` - Go-owned sessions and email tokens
7. `00000000000007_inventory_idempotency.sql` - Retry-safe inventory mutations
8. `00000000000008_auth_realms.sql` - Separate platform and pharmacy sessions
9. `00000000000009_publish_compatible_views.sql` - Stable published views
10. `00000000000010_platform_super_admin_singleton.sql` - One-time admin bootstrap state
11. `00000000000011_packaging_and_sales.sql` - Pharmacy packaging rules and POS sales ledger

Apply the SQL migrations using your PostgreSQL provider in this order. The
inventory adjustment endpoint also requires the idempotency column and unique
index created by `00000000000007_inventory_idempotency.sql`.

## 🔐 Authentication

Authentication is fully owned by the Go API. It uses bcrypt password hashes,
opaque short-lived access cookies, rotating refresh cookies, database-backed
session revocation, and CSRF protection. Supabase is only used as PostgreSQL.

Auth endpoints:
```
POST /api/v1/auth/platform/login
POST /api/v1/auth/platform/refresh
POST /api/v1/auth/platform/logout
GET  /api/v1/auth/platform/me
POST /api/v1/auth/platform/logout-all
POST /api/v1/auth/platform/change-password

POST /api/v1/auth/pharmacy/login
POST /api/v1/auth/pharmacy/refresh
POST /api/v1/auth/pharmacy/logout
GET  /api/v1/auth/pharmacy/me
POST /api/v1/auth/pharmacy/logout-all
POST /api/v1/auth/pharmacy/change-password

Platform and pharmacy sessions use separate cookies and database realms.
Platform sessions are limited to `super_admin` accounts; pharmacy sessions
accept employees and company managers with an assigned pharmacy, but never
`company_viewer` or `super_admin` accounts.
POST /api/v1/auth/forgot-password
POST /api/v1/auth/reset-password
POST /api/v1/auth/verify-email   # body: {"email":"user@example.com","code":"123456"}
POST /api/v1/auth/resend-verification
```

**Headers:**
```
Authorization: Bearer <your-jwt-token>
```

## 🚢 Deployment

### DockHosting / Coolify
1. Connect this repository
2. Set environment variables
3. Deploy (auto-detects Go project)

### Railway
1. Import from GitHub
2. Add environment variables
3. Deploy

### VPS (Hetzner, DigitalOcean, etc.)
```bash
# Clone and build
git clone https://github.com/zyyaat/pharmacy-os-backend.git
cd pharmacy-os-backend
cp .env.example .env
# Edit .env
docker compose up -d
```

## 🧪 Testing

```bash
# Run integration tests
go test ./tests/integration/...

# Run all tests
go test ./...
```

## 📦 Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [gin-gonic/gin](https://github.com/gin-gonic/gin) | v1.9.1 | HTTP framework |
| [golang-jwt/jwt](https://github.com/golang-jwt/jwt) | v5.2.0 | JWT authentication |
| [jackc/pgx](https://github.com/jackc/pgx) | v5.4.3 | PostgreSQL driver |

## 📄 License

Private - All rights reserved

## 👥 Support

For issues and questions, contact the development team.
