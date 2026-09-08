// Package middleware provides HTTP middleware for the API
package middleware

import (
        "log"
        "net/http"
        "strings"

        "github.com/gin-gonic/gin"
)

// CORS returns a middleware that handles CORS with diagnostics.
//
// Allowed origins are configured via CORS_ORIGINS (comma separated). In
// addition to exact matches, entries support a single leading wildcard for
// subdomains, e.g. "*.vercel.app" — required because every Vercel preview
// deployment gets its own randomly generated subdomain.
//
// Rejected origins are logged with the reason and the current allow-list so
// misconfiguration shows up directly in the DockHosting logs:
//
//      [CORS] origin not allowed: https://foo.vercel.app (allowed: [...])
func CORS(allowedOrigins ...string) gin.HandlerFunc {
        return func(c *gin.Context) {
                origin := c.GetHeader("Origin")
                allowed := originAllowed(origin, allowedOrigins)

                // No Origin header means the call is same-origin or a server/curl
                // client: CORS is irrelevant, always allow through.
                if origin == "" {
                        allowed = true
                }

                if allowed {
                        c.Header("Access-Control-Allow-Origin", origin)
                        c.Header("Access-Control-Allow-Credentials", "true")
                        c.Header("Vary", "Origin")
                } else {
                        log.Printf("[CORS] origin not allowed: %s (allowed: %s) - configure CORS_ORIGINS on the backend",
                                origin, strings.Join(allowedOrigins, ", "))
                }

                c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
                c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization, X-CSRF-Token, X-Request-ID")
                c.Header("Access-Control-Max-Age", "86400")

                if c.Request.Method == "OPTIONS" {
                        c.AbortWithStatus(http.StatusNoContent)
                        return
                }

                c.Next()
        }
}

// originAllowed matches an origin against the allow-list. An entry may be:
//   - an exact origin:        https://pharmacy-app.vercel.app
//   - a subdomain wildcard:   *.vercel.app  (matches any subdomain at any
//     depth, e.g. pharmacy-app.vercel.app and project-git-fix.vercel.app,
//     but NOT vercel.app itself and NOT evil-vercel-app.com)
//   - "*"                     allow everything (prefer explicit origins in
//     production)
func originAllowed(origin string, allowedOrigins []string) bool {
        if origin == "" {
                return false
        }
        host := normalizeHost(origin)
        if host == "" {
                return false
        }
        for _, candidate := range allowedOrigins {
                candidate = strings.TrimSpace(candidate)
                if candidate == "" {
                        continue
                }
                if candidate == "*" {
                        return true
                }
                if candidate == origin || normalizeHost(candidate) == host {
                        return true
                }
                if strings.HasPrefix(candidate, "*.") {
                        wildcard := strings.TrimPrefix(candidate, "*.") // e.g. "vercel.app"
                        wildcardHost := normalizeHost(wildcard)
                        if wildcardHost == "" {
                                continue
                        }
                        if strings.HasSuffix(host, "."+wildcardHost) && host != wildcardHost {
                                return true
                        }
                }
        }
        return false
}

// normalizeHost reduces an origin (or bare domain) to its bare host so that
// wildcard comparisons are not confused by scheme or port.
func normalizeHost(value string) string {
        value = strings.TrimSpace(value)
        value = strings.TrimPrefix(value, "https://")
        value = strings.TrimPrefix(value, "http://")
        if i := strings.IndexAny(value, "/?#"); i >= 0 {
                value = value[:i]
        }
        if i := strings.LastIndex(value, ":"); i >= 0 && !strings.Contains(value, "]") {
                value = value[:i] // strip :port (careful not to break IPv6 literals)
        }
        return strings.ToLower(value)
}
