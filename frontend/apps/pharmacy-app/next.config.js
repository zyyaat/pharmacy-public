/** @type {import('next').NextConfig} */
const backendUrl = (process.env.BACKEND_URL || 'http://127.0.0.1:8080').replace(/\/$/, '')

const nextConfig = {
  allowedDevOrigins: ['127.0.0.1', 'localhost'],
  rewrites: async () => [
    { source: '/api/v1/:path*', destination: `${backendUrl}/api/v1/:path*` },
    { source: '/health', destination: `${backendUrl}/health` },
  ],
}

module.exports = nextConfig
