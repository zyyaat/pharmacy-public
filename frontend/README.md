# Pharmacy OS - Frontend Monorepo

![Next.js](https://img.shields.io/badge/Next.js-16-black?logo=next.js)
![React](https://img.shields.io/badge/React-19-blue?logo=react)
![TypeScript](https://img.shields.io/badge/TypeScript-5.6-blue?logo=typescript)
![Tailwind CSS](https://img.shields.io/badge/Tailwind_CSS-v4-06B6D4?logo=tailwindcss)
![Supabase](https://img.shields.io/badge/Supabase-2.39-3ECF8E?logo=supabase)

Complete pharmacy management system frontend with 3 applications:

1. **Pharmacy App** - Main pharmacy management dashboard
2. **Admin Dashboard** - Admin/Super-admin control panel  
3. **Marketing** - Public landing page & marketing site

---

## Applications

### 1. 🏥 Pharmacy App (`apps/pharmacy-app`)

Main application for pharmacy staff and managers.

**Features:**
- Dashboard with key metrics & analytics
- Inventory Management (medications, stock, batches)
- Employee Management (staff, roles)
- Attendance Tracking (clock in/out)
- Branch Management (multi-location)
- Reports & Analytics
- Settings

**Run:**
```bash
cd apps/pharmacy-app
npm install
npm run dev
```

---

### 2. 👑 Admin Dashboard (`apps/admin-dashboard`)

Super-admin panel for managing multiple pharmacies.

**Features:**
- Company/Account Management
- Pharmacy Overview & Monitoring
- User Management
- Permissions & Access Control
- Analytics & Reports
- System Settings

**Run:**
```bash
cd apps/admin-dashboard
npm install
npm run dev
```

---

### 3. 📢 Marketing Site (`apps/marketing`)

Public-facing website for Pharmacy OS.

**Pages:**
- Landing Page (Home)
- Pricing Plans
- Privacy Policy
- Terms of Use

**Run:**
```bash
cd apps/marketing
npm install
npm run dev
```

---

## Tech Stack

| Technology | Version | Purpose |
|------------|---------|---------|
| Next.js | 16.x | React Framework (App Router) |
| React | 19.x | UI Library |
| TypeScript | 5.6.x | Type Safety |
| Tailwind CSS | 4.x | Utility-first Styling |
| Supabase JS | 2.39.x | Authentication & Database |

## Getting Started

### Prerequisites

- Node.js 18+ 
- npm or yarn
- Supabase project (for auth & database)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/zyyaat/pharmacy-os-frontend.git
cd pharmacy-os-frontend
```

2. Install dependencies for all apps:
```bash
# Install for each app
cd apps/pharmacy-app && npm install
cd ../admin-dashboard && npm install
cd ../marketing && npm install
```

3. Copy environment variables:
```bash
cp .env.example .env.local
```

4. Update `.env.local` with your Supabase credentials:
```env
NEXT_PUBLIC_SUPABASE_URL=your-supabase-url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
```

5. Run any app:
```bash
cd apps/pharmacy-app
npm run dev
```

## Project Structure

```
pharmacy-os-frontend/
├── apps/
│   ├── pharmacy-app/          # Main pharmacy app
│   │   ├── src/
│   │   │   ├── app/          # Pages (App Router)
│   │   │   │   ├── (auth)/   # Login page
│   │   │   │   └── (dashboard)/ # Dashboard pages
│   │   │   ├── components/   # React components
│   │   │   ├── hooks/        # Custom hooks
│   │   │   ├── lib/          # Utilities
│   │   │   └── types/        # TypeScript types
│   │   └── package.json
│   │
│   ├── admin-dashboard/       # Admin panel
│   │   ├── src/
│   │   │   ├── app/
│   │   │   │   ├── (auth)/   # Admin login
│   │   │   │   └── (dashboard)/ # Admin pages
│   │   │   ├── components/
│   │   │   ├── hooks/
│   │   │   ├── lib/
│   │   │   └── types/
│   │   └── package.json
│   │
│   └── marketing/              # Public site
│       ├── src/
│       │   └── app/
│       │       ├── page.tsx           # Landing page
│       │       ├── pricing/page.tsx   # Pricing
│       │       ├── privacy-policy/    # Legal
│       │       └── terms-of-use/      # Legal
│       └── package.json
│
├── .env.example
├── .gitignore
└── README.md
```

## Available Scripts

Each app supports these scripts:

| Command | Description |
|---------|-------------|
| `npm run dev` | Start development server on port 3000 |
| `npm run build` | Build for production |
| `npm run start` | Start production server |
| `npm run lint` | Run ESLint |

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `NEXT_PUBLIC_SUPABASE_URL` | Only needed if a frontend feature directly uses Supabase | ❌ No |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Only needed if a frontend feature directly uses Supabase | ❌ No |
| `NEXT_PUBLIC_API_URL` | `/api/v1` for the Vercel same-origin proxy, or the public API URL in direct mode | ✅ Yes for deployed apps |
| `BACKEND_INTERNAL_URL` | Public backend origin used by the Next.js server-side proxy, without `/api/v1` | ✅ Yes when using proxy mode |

## Deployment

### Vercel (Recommended)

1. Push code to GitHub
2. Import each `apps/*` folder as separate project on Vercel
3. Add environment variables
4. Deploy!

**Root Directory for each project:**
- Pharmacy App: `./apps/pharmacy-app`
- Admin Dashboard: `./apps/admin-dashboard`
- Marketing: `./apps/marketing`

### Replit

1. Fork this repository to Replit
2. Configure which app to run in config
3. Set environment variables in Secrets
4. Click "Run"

### Docker

Each app can be containerized:

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
EXPOSE 3000
CMD ["node", "server.js"]
```

## Related Repositories

- [Backend (Go + Gin)](https://github.com/zyyaat/pharmacy-os-backend) - Go REST API backend

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is private. All rights reserved.
