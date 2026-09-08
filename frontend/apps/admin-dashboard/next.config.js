/** @type {import('next').NextConfig} */
const apiBaseUrl = process.env.NEXT_PUBLIC_API_URL || '/api/v1'
const backendOrigin = process.env.BACKEND_INTERNAL_URL || 'http://127.0.0.1:8080'
const useDevelopmentProxy = apiBaseUrl.startsWith('/')

const nextConfig = {
  reactStrictMode: true,
  allowedDevOrigins: ['127.0.0.1', 'localhost', process.env.REPLIT_DEV_DOMAIN].filter(Boolean),
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "**",
      },
    ],
  },
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
};

module.exports = nextConfig;
