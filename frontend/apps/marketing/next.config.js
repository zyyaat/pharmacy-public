/** @type {import('next').NextConfig} */
const backendOrigin = process.env.BACKEND_INTERNAL_URL || 'http://127.0.0.1:8080'

const nextConfig = {
  allowedDevOrigins: ['127.0.0.1', 'localhost', process.env.REPLIT_DEV_DOMAIN].filter(Boolean),
  async rewrites() {
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
