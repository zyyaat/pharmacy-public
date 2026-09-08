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
| `BREVO_API_KEY` | Brevo API key for verification and password reset email | - |
| `MAIL_FROM_EMAIL` | Verified Brevo sender email | - |
| `MAIL_FROM_NAME` | Sender name | `Pharmacy OS` |
| `PUBLIC_APP_URL` | Public frontend URL used in email links | - |
| `RIVER_DSN` | River Queue DSN | Same as DATABASE_URL |
| `CORS_ORIGINS` | Allowed CORS origins | `localhost:3000,3001` |

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

Apply the SQL migrations using your PostgreSQL provider. The
`00000000000006_go_auth.sql` migration creates the Go-owned session and
email-token tables.

## 🔐 Authentication

Authentication is fully owned by the Go API. It uses bcrypt password hashes,
opaque short-lived access cookies, rotating refresh cookies, database-backed
session revocation, and CSRF protection. Supabase is only used as PostgreSQL.

Auth endpoints:
```
POST /api/v1/auth/login
POST /api/v1/auth/refresh
POST /api/v1/auth/logout
GET  /api/v1/auth/me
POST /api/v1/auth/logout-all
POST /api/v1/auth/change-password
POST /api/v1/auth/forgot-password
POST /api/v1/auth/reset-password
POST /api/v1/auth/verify-email
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

### Railway / Render
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
