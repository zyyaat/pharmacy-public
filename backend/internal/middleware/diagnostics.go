// Package middleware provides HTTP middleware for the API.
//
// diagnostics.go wires a per-request correlation ID into every request so
// that frontend error panels and backend log lines can be matched 1:1 while
// diagnosing deployment problems (CORS, cookies, database, ...).
package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

const (
	// ContextRequestID is the gin.Context key holding the request ID.
	ContextRequestID = "request_id"
	// ContextDebug marks whether debug details may be exposed in responses.
	ContextDebug = "app_debug"
	// RequestIDHeader is the canonical header name used on both sides.
	RequestIDHeader = "X-Request-ID"
)

// RequestID returns a middleware that guarantees every request carries a
// unique correlation ID. Clients may supply their own via X-Request-ID;
// otherwise one is generated. The ID is echoed back on the response and is
// embedded in every structured error response (see auth.writeError).
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.GetHeader(RequestIDHeader)
		if id == "" {
			id = newRequestID()
		}
		c.Set(ContextRequestID, id)
		c.Writer.Header().Set(RequestIDHeader, id)
		c.Next()
	}
}

// InjectDebug publishes the APP_DEBUG flag on the request context so that
// handlers (including the auth package) can decide whether to attach internal
// error details to responses without importing the config package.
func InjectDebug(debug bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Set(ContextDebug, debug)
		c.Next()
	}
}

// RequestIDFromContext extracts the correlation ID of the current request.
func RequestIDFromContext(c *gin.Context) string {
	if v, ok := c.Get(ContextRequestID); ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

// DebugFromContext reports whether internal error details may be exposed.
func DebugFromContext(c *gin.Context) bool {
	if v, ok := c.Get(ContextDebug); ok {
		if b, ok := v.(bool); ok {
			return b
		}
	}
	return false
}

// newRequestID builds a short, collision-resistant, log-friendly ID:
// req-<unixmilli>-<6 random bytes in hex>.
func newRequestID() string {
	buf := make([]byte, 6)
	if _, err := rand.Read(buf); err != nil {
		// crypto/rand failure is practically impossible on Linux; fall back
		// to a timestamp-only ID instead of crashing the request path.
		return fmt.Sprintf("req-%d", time.Now().UnixNano())
	}
	return fmt.Sprintf("req-%d-%s", time.Now().UnixMilli(), hex.EncodeToString(buf))
}
