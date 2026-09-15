// Support WebSocket hub (Phase T1) — the real-time accelerator.
//
// Architecture rule: the DATABASE is the source of truth. Every chat write
// goes through REST inside a transaction; the hub only PUSHES what already
// committed (message.new / typing / conversation.updated / ticket.updated).
// A dropped socket never loses a message — the client falls back to
// polling; the next REST response always contains the full history.
//
// One process serves one Docker container (web: ./server), so an in-process
// hub is complete today. If the deployment ever scales horizontally, the
// same fan-out calls become a Redis pub/sub publish — the client contract
// (REST truth + WS acceleration) does not change.
//
// Client → server frames are ONLY tiny control envelopes (ping / typing).
// Chat content NEVER rides the socket: authentication, validation,
// transactions and audit stay on the REST path exactly like every other
// mutation in this codebase.
package handlers

import (
        "context"
        "encoding/json"
        "log"
        "net/http"
        "strings"
        "sync"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/gorilla/websocket"
        "github.com/jackc/pgx/v5/pgxpool"

        "github.com/pharmacy-os/backend/internal/auth"
)

const (
        supportWriteWait    = 10 * time.Second
        supportPongWait     = 60 * time.Second
        supportPingPeriod   = (supportPongWait * 9) / 10
        supportMaxWSMessage = 8192 // control envelopes only
        supportSendBuffer   = 64
        supportTypingDebounce = 1200 * time.Millisecond
)

// supportEnvelope is the wire shape for hub pushes AND client control
// frames (clients send only type=ping|typing with a conversation id).
type supportEnvelope struct {
        Type           string          `json:"type"`
        ConversationID string          `json:"conversation_id,omitempty"`
        CompanyID      string          `json:"company_id,omitempty"`
        Actor          string          `json:"actor,omitempty"`
        Ticket         json.RawMessage `json:"ticket,omitempty"`
        Message        json.RawMessage `json:"message,omitempty"`
        SentAt         string          `json:"sent_at,omitempty"`
}

// supportClient is one live connection.
type supportClient struct {
        hub         *supportHub
        conn        *websocket.Conn
        send        chan []byte
        realm       string // models.SupportSenderPlatform | SupportSenderPharmacy
        userID      string
        companyID   string // pharmacy realm only — the tenant boundary
        displayName string

        lastTypingAt time.Time // debounce guard, guarded by hub.mu
        closedOnce   sync.Once
}

// supportHub fans pushes out to authenticated live sockets.
type supportHub struct {
        pool    *pgxpool.Pool
        mu      sync.RWMutex
        clients map[*supportClient]struct{}
        // conversationOwner caches conversation_id → company_id for the typing
        // ownership check. Conversation → company never changes, so entries live
        // for the process lifetime; misses fall through to the database once.
        conversationOwner sync.Map
}

func newSupportHub(pool *pgxpool.Pool) *supportHub {
        return &supportHub{pool: pool, clients: make(map[*supportClient]struct{})}
}

func (hub *supportHub) add(c *supportClient) {
        hub.mu.Lock()
        hub.clients[c] = struct{}{}
        hub.mu.Unlock()
}

func (hub *supportHub) remove(c *supportClient) {
        hub.mu.Lock()
        if _, ok := hub.clients[c]; ok {
                delete(hub.clients, c)
        }
        hub.mu.Unlock()
        c.closedOnce.Do(func() {
                close(c.send)
                _ = c.conn.Close()
        })
}

// broadcast delivers to the clients matching the predicate. Slow consumers
// are dropped (buffered chan full) — REST polling covers them; one dead
// socket must never stall the hub.
func (hub *supportHub) broadcast(predicate func(*supportClient) bool, payload []byte) {
        hub.mu.RLock()
        defer hub.mu.RUnlock()
        for client := range hub.clients {
                if !predicate(client) {
                        continue
                }
                select {
                case client.send <- payload:
                default:
                }
        }
}

func (hub *supportHub) toPlatform(payload []byte) {
        hub.broadcast(func(c *supportClient) bool { return c.realm == "platform" }, payload)
}

func (hub *supportHub) toCompany(companyID string, payload []byte) {
        hub.broadcast(func(c *supportClient) bool {
                return c.realm == "pharmacy" && c.companyID == companyID
        }, payload)
}

// toBoth pushes one committed event to the company side and the platform
// side at once (message.new, conversation.updated, ticket.updated).
func (hub *supportHub) toBoth(companyID string, payload []byte) {
        hub.broadcast(func(c *supportClient) bool {
                if c.realm == "platform" {
                        return true
                }
                return c.realm == "pharmacy" && c.companyID == companyID
        }, payload)
}

// PlatformSupportOnline reports whether any platform socket is live — used
// by the send handlers to decide whether the quiet-hours email is needed.
func (hub *supportHub) PlatformSupportOnline() bool {
        hub.mu.RLock()
        defer hub.mu.RUnlock()
        for client := range hub.clients {
                if client.realm == "platform" {
                        return true
                }
        }
        return false
}

// CompanySupportOnline reports whether any socket of this company is live.
func (hub *supportHub) CompanySupportOnline(companyID string) bool {
        hub.mu.RLock()
        defer hub.mu.RUnlock()
        for client := range hub.clients {
                if client.realm == "pharmacy" && client.companyID == companyID {
                        return true
                }
        }
        return false
}

func marshalSupportEnvelope(e supportEnvelope) []byte {
        if e.SentAt == "" {
                e.SentAt = time.Now().UTC().Format(time.RFC3339Nano)
        }
        blob, err := json.Marshal(e)
        if err != nil {
                return nil
        }
        return blob
}

// ---------------------------------------------------------------------------
// Upgrade endpoints
// ---------------------------------------------------------------------------

// supportOriginAllowed mirrors the CORS middleware semantics (exact origin,
// *.subdomain wildcard, "*") plus the same-origin case (the request's Host
// equals the Origin's host — a page served from the API domain itself), for
// the WebSocket handshake. The auth cookie still proves the session; this
// only blocks cross-site socket hijacking from unknown pages. Native /
// mobile / curl clients carry no Origin and always pass.
func supportOriginAllowed(origin, requestHost string, allowedOrigins []string) bool {
        if origin == "" {
                return true
        }
        originHost := originHostOnly(origin)
        if requestHost != "" && originHost == originHostOnly(requestHost) {
                return true // same-origin handshake
        }
        for _, candidate := range allowedOrigins {
                candidate = strings.TrimSpace(candidate)
                if candidate == "" {
                        continue
                }
                if candidate == "*" || candidate == origin {
                        return true
                }
                if strings.HasPrefix(candidate, "*.") {
                        suffix := strings.TrimPrefix(candidate, "*.")
                        if originHost != "" && strings.HasSuffix(originHost, "."+suffix) {
                                return true
                        }
                }
        }
        return false
}

func originHostOnly(origin string) string {
        origin = strings.TrimPrefix(strings.TrimPrefix(origin, "https://"), "http://")
        if i := strings.IndexAny(origin, "/?#"); i >= 0 {
                origin = origin[:i]
        }
        if i := strings.LastIndex(origin, ":"); i >= 0 && !strings.Contains(origin, "]") {
                origin = origin[:i]
        }
        return strings.ToLower(origin)
}

func (h *Handler) newSupportUpgrader() websocket.Upgrader {
        origins := h.config.GetCorsOrigins()
        return websocket.Upgrader{
                ReadBufferSize:  1024,
                WriteBufferSize: 1024,
                CheckOrigin: func(r *http.Request) bool {
                        return supportOriginAllowed(r.Header.Get("Origin"), r.Host, origins)
                },
        }
}

// SupportPharmacyWS is the company-side socket (cookie or Bearer token —
// both are already verified by the auth middleware before the upgrade).
func (h *Handler) SupportPharmacyWS(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        companyID := h.companyIDForGate(c, principal)
        if companyID == "" {
                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "company_required"})
                return
        }
        h.serveSupportWS(c, principal, "pharmacy", companyID)
}

// SupportPlatformWS is the platform-side socket (super admin realm).
func (h *Handler) SupportPlatformWS(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        h.serveSupportWS(c, principal, "platform", "")
}

func (h *Handler) serveSupportWS(c *gin.Context, principal *auth.Principal, realm, companyID string) {
        conn, err := h.supportUpgrader.Upgrade(c.Writer, c.Request, nil)
        if err != nil {
                // Upgrade already answered with the HTTP error; nothing to write.
                log.Printf("[support-ws] upgrade failed realm=%s: %v", realm, err)
                return
        }
        client := &supportClient{
                hub:         h.supportHub,
                conn:        conn,
                send:        make(chan []byte, supportSendBuffer),
                realm:       realm,
                userID:      principal.ID,
                companyID:   companyID,
                displayName: principal.DisplayName,
        }
        h.supportHub.add(client)
        go client.writePump()
        go client.readPump()
}

// ---------------------------------------------------------------------------
// Client pumps (the standard gorilla/websocket pattern)
// ---------------------------------------------------------------------------

func (c *supportClient) readPump() {
        defer func() { c.hub.remove(c) }()
        c.conn.SetReadLimit(supportMaxWSMessage)
        _ = c.conn.SetReadDeadline(time.Now().Add(supportPongWait))
        c.conn.SetPongHandler(func(string) error {
                return c.conn.SetReadDeadline(time.Now().Add(supportPongWait))
        })
        for {
                _, raw, err := c.conn.ReadMessage()
                if err != nil {
                        return
                }
                var frame supportEnvelope
                if err := json.Unmarshal(raw, &frame); err != nil {
                        continue // garbage frames are ignored, never fatal
                }
                switch frame.Type {
                case "ping":
                        if pong := marshalSupportEnvelope(supportEnvelope{Type: "pong"}); pong != nil {
                                select {
                                case c.send <- pong:
                                default:
                                }
                        }
                case "typing":
                        c.handleTyping(frame.ConversationID)
                default:
                        // Unknown client frame types are ignored — the REST API is the
                        // only way to produce content.
                }
        }
}

// handleTyping validates that the typing client may speak in this
// conversation, debounces floods, and relays the indicator to the OTHER
// side only (nobody benefits from seeing their own typing).
func (c *supportClient) handleTyping(conversationID string) {
        conversationID = strings.TrimSpace(conversationID)
        if conversationID == "" {
                return
        }
        companyID, ok := c.hub.conversationOwnerOf(c, conversationID)
        if !ok {
                return // unknown or foreign conversation — stay silent
        }
        c.hub.mu.Lock()
        if time.Since(c.lastTypingAt) < supportTypingDebounce {
                c.hub.mu.Unlock()
                return
        }
        c.lastTypingAt = time.Now()
        c.hub.mu.Unlock()

        actor := c.realm
        payload := marshalSupportEnvelope(supportEnvelope{
                Type:           "typing",
                ConversationID: conversationID,
                CompanyID:      companyID,
                Actor:          actor,
        })
        if payload == nil {
                return
        }
        if actor == "platform" {
                c.hub.toCompany(companyID, payload)
        } else {
                c.hub.toPlatform(payload)
        }
}

// conversationOwnerOf resolves (and caches) the conversation → company
// mapping. Platform clients may type anywhere the conversation exists;
// pharmacy clients only inside their own company's conversations.
func (hub *supportHub) conversationOwnerOf(c *supportClient, conversationID string) (string, bool) {
        if cached, ok := hub.conversationOwner.Load(conversationID); ok {
                companyID := cached.(string)
                if c.realm == "platform" {
                        return companyID, true
                }
                if c.companyID == companyID {
                        return companyID, true
                }
                return "", false
        }
        // Miss: one indexed lookup, then cache forever (company binding is
        // immutable for the conversation's life). A nil pool (unit-test wiring)
        // simply never validates unknown conversations — typing stays silent.
        if hub.pool == nil {
                return "", false
        }
        qctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
        defer cancel()
        var companyID string
        err := hub.pool.QueryRow(
                qctx,
                `SELECT company_id::text FROM support_conversations WHERE id = $1::uuid`,
                conversationID,
        ).Scan(&companyID)
        if err != nil || companyID == "" {
                return "", false
        }
        hub.conversationOwner.Store(conversationID, companyID)
        if c.realm == "platform" || c.companyID == companyID {
                return companyID, true
        }
        return "", false
}

func (c *supportClient) writePump() {
        ticker := time.NewTicker(supportPingPeriod)
        defer func() {
                ticker.Stop()
                _ = c.conn.Close()
        }()
        for {
                select {
                case payload, ok := <-c.send:
                        _ = c.conn.SetWriteDeadline(time.Now().Add(supportWriteWait))
                        if !ok {
                                // Hub closed the channel (remove) — acknowledge politely.
                                _ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
                                return
                        }
                        if err := c.conn.WriteMessage(websocket.TextMessage, payload); err != nil {
                                return
                        }
                case <-ticker.C:
                        _ = c.conn.SetWriteDeadline(time.Now().Add(supportWriteWait))
                        if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
                                return
                        }
                }
        }
}
