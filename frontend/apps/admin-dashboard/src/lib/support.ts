// Support live chat + tickets client (Phase T2) — the platform side.
//
// Contract mirrors the backend (migration 33): REST is the source of truth,
// the WebSocket hub only ACCELERATES delivery of committed events, and a
// dropped socket never loses data — the page falls back to polling the same
// REST endpoints while the socket is down.
//
// Wire shapes are the gin responses verbatim (no {data} envelope on the
// support surface) — locked by the 108-check e2e suite.

const API_BASE_URL = (process.env.NEXT_PUBLIC_API_URL || '/api/v1').replace(/\/+$/, '')
const CSRF_COOKIE_NAME = 'platform_csrf'

export type SupportConversationStatus = 'open' | 'closed'
export type SupportSenderRealm = 'platform' | 'pharmacy'
export type SupportTicketStatus = 'open' | 'in_progress' | 'waiting_customer' | 'resolved' | 'closed'
export type SupportTicketPriority = 'low' | 'normal' | 'high' | 'urgent'
export type SupportTicketCategory = 'billing' | 'technical' | 'inventory' | 'account' | 'feature_request' | 'other'

export type SupportConversation = {
  id: string
  company_id: string
  subject: string
  status: SupportConversationStatus
  closed_by?: string | null
  last_message_at?: string | null
  last_message_preview: string
  platform_unread_count: number
  company_unread_count: number
  created_at?: string | null
  updated_at?: string | null
  company_name?: string | null
  company_email?: string | null
}

export type SupportMessage = {
  id: string
  conversation_id: string
  sender_realm: SupportSenderRealm
  sender_id?: string | null
  sender_name: string
  body: string
  attachment_id?: string | null
  is_system: boolean
  system_kind?: string | null
  created_at?: string | null
}

export type SupportTicket = {
  id: string
  company_id: string
  conversation_id?: string | null
  number: string
  subject: string
  status: SupportTicketStatus
  priority: SupportTicketPriority
  category: SupportTicketCategory
  assigned_to?: string | null
  resolution_note?: string | null
  resolved_at?: string | null
  closed_at?: string | null
  created_at?: string | null
  updated_at?: string | null
  company_name?: string | null
}

export type SupportAttachmentMeta = {
  id: string
  file_name: string
  mime_type: string
  size_bytes: number
}

export type SupportOverview = {
  unread_conversations: number
  open_conversations: number
  unanswered_conversations: number
  open_tickets: number
  urgent_tickets: number
  platform_online: boolean
}

export type SupportConversationDetail = {
  conversation: SupportConversation
  ticket: SupportTicket | null
  platform_online: boolean
  company_online?: boolean
}

function csrfHeader(): Record<string, string> {
  if (typeof document === 'undefined') return {}
  const csrf = document.cookie.match(new RegExp(`(?:^|; )${CSRF_COOKIE_NAME}=([^;]+)`))?.[1]
  return csrf ? { 'X-CSRF-Token': decodeURIComponent(csrf) } : {}
}

async function supportFetch<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${endpoint}`, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...csrfHeader(), ...(options.headers as Record<string, string>) },
    credentials: 'include',
  })
  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'request_failed' }))
    throw new Error((error as { error?: string }).error || 'request_failed')
  }
  return response.json() as Promise<T>
}

export const supportApi = {
  async overview(): Promise<SupportOverview> {
    return supportFetch<SupportOverview>('/platform-admin/support/overview')
  },

  async conversations(filter: string, companyId?: string): Promise<SupportConversation[]> {
    const query = new URLSearchParams({ filter })
    if (companyId) query.set('company_id', companyId)
    const data = await supportFetch<{ conversations: SupportConversation[] }>(
      `/platform-admin/support/conversations?${query.toString()}`
    )
    return data.conversations
  },

  async conversation(id: string): Promise<SupportConversationDetail> {
    return supportFetch<SupportConversationDetail>(`/platform-admin/support/conversations/${id}`)
  },

  async messages(id: string, beforeTs?: string, beforeId?: string, limit = 50): Promise<{ messages: SupportMessage[]; has_more: boolean }> {
    const query = new URLSearchParams({ limit: String(limit) })
    if (beforeTs) query.set('before_ts', beforeTs)
    if (beforeId) query.set('before_id', beforeId)
    return supportFetch(`/platform-admin/support/conversations/${id}/messages?${query.toString()}`)
  },

  async sendMessage(id: string, body: string, attachmentId?: string): Promise<SupportMessage> {
    const data = await supportFetch<{ message: SupportMessage }>(
      `/platform-admin/support/conversations/${id}/messages`,
      { method: 'POST', body: JSON.stringify({ body, attachment_id: attachmentId || undefined }) }
    )
    return data.message
  },

  async markRead(id: string): Promise<void> {
    await supportFetch(`/platform-admin/support/conversations/${id}/read`, { method: 'POST', body: JSON.stringify({}) })
  },

  async closeConversation(id: string): Promise<SupportConversation> {
    const data = await supportFetch<{ conversation: SupportConversation }>(
      `/platform-admin/support/conversations/${id}/close`,
      { method: 'POST', body: JSON.stringify({}) }
    )
    return data.conversation
  },

  async uploadAttachment(payload: { file_name: string; mime_type: string; content: string; company_id: string }): Promise<SupportAttachmentMeta> {
    const data = await supportFetch<{ attachment: SupportAttachmentMeta }>(
      '/platform-admin/support/attachments',
      { method: 'POST', body: JSON.stringify(payload) }
    )
    return data.attachment
  },

  async downloadAttachment(id: string): Promise<Blob> {
    const response = await fetch(`${API_BASE_URL}/platform-admin/support/attachments/${id}`, {
      credentials: 'include',
    })
    if (!response.ok) throw new Error('attachment_download_failed')
    return response.blob()
  },

  async tickets(filters: { status?: string; priority?: string; category?: string; company_id?: string } = {}): Promise<SupportTicket[]> {
    const query = new URLSearchParams()
    for (const [key, value] of Object.entries(filters)) if (value) query.set(key, value)
    const data = await supportFetch<{ tickets: SupportTicket[] }>(`/platform-admin/support/tickets?${query.toString()}`)
    return data.tickets
  },

  async updateTicket(id: string, patch: { status?: string; priority?: string; category?: string; resolution_note?: string }): Promise<SupportTicket> {
    const data = await supportFetch<{ ticket: SupportTicket }>(`/platform-admin/support/tickets/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(patch),
    })
    return data.ticket
  },
}

// ---------------------------------------------------------------------------
// WebSocket — the accelerator with graceful degradation
// ---------------------------------------------------------------------------

export type SupportSocketEvent = {
  type: string
  conversation_id?: string
  company_id?: string
  actor?: string
  message?: SupportMessage
  ticket?: SupportTicket
}

function wsURL(path: string): string {
  if (API_BASE_URL.startsWith('http')) {
    return API_BASE_URL.replace(/^http/, 'ws') + path
  }
  if (typeof window === 'undefined') return ''
  const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
  return `${proto}://${window.location.host}${API_BASE_URL}${path}`
}

export type SocketStatus = 'connecting' | 'open' | 'closed'

/** Live event pipe. Auto-reconnects with a capped backoff; every disconnect
 *  simply flips the page into polling mode — nothing is ever lost. */
export class SupportSocket {
  private ws: WebSocket | null = null
  private backoff = 1000
  private disposed = false
  private retryTimer: ReturnType<typeof setTimeout> | null = null

  onEvent: (event: SupportSocketEvent) => void = () => {}
  onStatus: (status: SocketStatus) => void = () => {}

  constructor(private readonly path: string) {}

  connect() {
    if (this.disposed || (this.ws && this.ws.readyState <= WebSocket.OPEN)) return
    const url = wsURL(this.path)
    if (!url) return
    this.onStatus('connecting')
    try {
      this.ws = new WebSocket(url)
    } catch {
      this.scheduleRetry()
      return
    }
    this.ws.onopen = () => {
      this.backoff = 1000
      this.onStatus('open')
    }
    this.ws.onmessage = (raw) => {
      try {
        const event = JSON.parse(raw.data as string) as SupportSocketEvent
        if (event.type !== 'pong') this.onEvent(event)
      } catch {
        // ignore malformed frames — REST remains the truth
      }
    }
    this.ws.onclose = () => {
      this.onStatus('closed')
      this.scheduleRetry()
    }
    this.ws.onerror = () => {
      try {
        this.ws?.close()
      } catch {
        /* already closing */
      }
    }
  }

  private scheduleRetry() {
    if (this.disposed || this.retryTimer) return
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null
      this.connect()
    }, this.backoff)
    this.backoff = Math.min(this.backoff * 2, 10000)
  }

  /** Typing indicator — fire and forget (best effort by design). */
  sendTyping(conversationId: string) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ type: 'typing', conversation_id: conversationId }))
    }
  }

  disconnect() {
    this.disposed = true
    if (this.retryTimer) clearTimeout(this.retryTimer)
    try {
      this.ws?.close()
    } catch {
      /* already closed */
    }
    this.ws = null
  }
}
