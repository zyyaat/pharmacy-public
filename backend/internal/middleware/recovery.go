// Package middleware provides HTTP middleware for the API
package middleware

import (
        "fmt"
        "log"
        "net/http"
        "runtime/debug"

        "github.com/gin-gonic/gin"
)

// Recovery returns a middleware that recovers from panics without exposing
// internals. It logs the full panic value and stack trace to the server log
// and returns a structured JSON error carrying the request ID.
func Recovery() gin.HandlerFunc {
        return recoveryWith(false)
}

// RecoveryDebug behaves like Recovery but additionally embeds the panic
// message in the JSON response when APP_DEBUG=true is configured. Use it so
// deployment-time panics surface their real cause in the frontend error
// panel instead of a blank 500.
func RecoveryDebug(debug bool) gin.HandlerFunc {
        return recoveryWith(debug)
}

func recoveryWith(debug bool) gin.HandlerFunc {
        return func(c *gin.Context) {
                defer func() {
                        if recovered := recover(); recovered != nil {
                                requestID := RequestIDFromContext(c)
                                log.Printf("[PANIC] request_id=%s method=%s path=%s panic=%v\n%s",
                                        requestID,
                                        c.Request.Method,
                                        c.Request.URL.Path,
                                        recovered,
                                        debug.Stack(),
                                )
                                body := gin.H{
                                        "error":      "internal_error",
                                        "code":       "INTERNAL_ERROR",
                                        "message":    "Unexpected server error",
                                        "request_id": requestID,
                                }
                                if debug {
                                        body["debug"] = gin.H{"panic": toErrorString(recovered)}
                                }
                                c.AbortWithStatusJSON(http.StatusInternalServerError, body)
                        }
                }()
                c.Next()
        }
}

// toErrorString renders an arbitrary panic value (error, string, ...) safely.
func toErrorString(value interface{}) string {
        switch v := value.(type) {
        case error:
                return v.Error()
        case string:
                return v
        default:
                return fmt.Sprintf("%v", v)
        }
}
