/** @type {import('next').NextConfig} */
const apiBaseUrl = process.env.NEXT_PUBLIC_API_URL || '/api/v1'
const backendOrigin = process.env.BACKEND_INTERNAL_URL || 'http://127.0.0.1:8080'
const useDevelopmentProxy = apiBaseUrl.startsWith('/')

// Task 55 — production compass: proxy mode without an explicit target silently
// rewrites every /api/v1 request to http://127.0.0.1:8080, which resolves to a
// private address inside Vercel and breaks the whole app with
// DNS_HOSTNAME_RESOLVED_PRIVATE. Make that visible at build time.
if (useDevelopmentProxy && !process.env.BACKEND_INTERNAL_URL) {
  console.warn('[pharmacy-app] proxy mode active but BACKEND_INTERNAL_URL is NOT set — rewrites target http://127.0.0.1:8080 (local/Replit only). On Vercel set BACKEND_INTERNAL_URL to the public backend origin (https://..., no /api/v1 suffix) and redeploy, or every /api/v1 request fails.')
}

const nextConfig = {
  env: {
    // Task 58 — بصمة بناء الواجهة (VERCEL_GIT_COMMIT_SHA) تظهر في كونسول المتصفح
    // لكشف النسخ القديمة المخبأة فورًا أثناء تشخيص التسجيل الذكي.
    NEXT_PUBLIC_BUILD_ID: process.env.VERCEL_GIT_COMMIT_SHA || '',
  },
  allowedDevOrigins: ['127.0.0.1', 'localhost', process.env.REPLIT_DEV_DOMAIN].filter(Boolean),
  async rewrites() {
    if (!useDevelopmentProxy) return []
    return [
      {
        source: '/api/v1/:path*',
        destination: `${backendOrigin}/api/v1/:path*`,
      },
      {
        source: '/health',
        destination: `${backendOrigin}/health`,
      },
    ]
  },
}

module.exports = nextConfig
