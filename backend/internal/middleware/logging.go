// Package middleware provides HTTP middleware for the API
package middleware

import (
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

// statusCategory maps an HTTP status to a compact log label so that failed
// requests stand out when scanning DockHosting logs.
func statusCategory(status int) string {
	switch {
	case status >= 500:
		return "SERVER_ERROR"
	case status >= 400:
		return "CLIENT_ERROR"
	case status >= 300:
		return "REDIRECT"
	default:
		return "OK"
	}
}

// Logger returns a middleware that logs every HTTP request with the fields
// needed to diagnose production problems:
//
//	[HTTP] method=POST path=/api/v1/auth/login status=401 category=CLIENT_ERROR
//	       latency=42ms ip=1.2.3.4 request_id=req-1715-abc origin=https://...
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()
		log.Printf("[HTTP] method=%s path=%s status=%d category=%s latency=%s ip=%s request_id=%s origin=%s referer=%s",
			c.Request.Method,
			c.Request.URL.Path,
			status,
			statusCategory(status),
			latency,
			c.ClientIP(),
			RequestIDFromContext(c),
			orDash(c.GetHeader("Origin")),
			orDash(c.GetHeader("Referer")),
		)
	}
}

// orDash replaces empty header values with "-" to keep log lines aligned.
func orDash(value string) string {
	if value == "" {
		return "-"
	}
	return value
}
