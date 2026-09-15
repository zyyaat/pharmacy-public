// Support live chat + tickets client (Phase T2) — the COMPANY side.
//
// Same contract as the platform client: REST is the source of truth, the
// WebSocket hub only accelerates committed events, and a dropped socket
// falls back to polling — nothing is ever lost. Wire shapes are the gin
// responses verbatim (no {data} envelope), locked by the e2e suite.

const API_BASE_URL = (process.env.NEXT_PUBLIC_API_URL || '/api/v1').replace(/\/+$/, '')
const CSRF_COOKIE_NAME = 'pharmacy_csrf'

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
  resolution_note?: string | null
  resolved_at?: string | null
  closed_at?: string | null
  created_at?: string | null
  updated_at?: string | null
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
  open_tickets: number
  urgent_tickets: number
  platform_online: boolean
}

export type SupportConversationDetail = {
  conversation: SupportConversation
  ticket: SupportTicket | null
  platform_online: boolean
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
    return supportFetch<SupportOverview>('/pharmacy/support/overview')
  },

  async conversations(): Promise<SupportConversation[]> {
    const data = await supportFetch<{ conversations: SupportConversation[] }>('/pharmacy/support/conversations')
    return data.conversations
  },

  async conversation(id: string): Promise<SupportConversationDetail> {
    return supportFetch<SupportConversationDetail>(`/pharmacy/support/conversations/${id}`)
  },

  async messages(id: string, beforeTs?: string, beforeId?: string, limit = 50): Promise<{ messages: SupportMessage[]; has_more: boolean }> {
    const query = new URLSearchParams({ limit: String(limit) })
    if (beforeTs) query.set('before_ts', beforeTs)
    if (beforeId) query.set('before_id', beforeId)
    return supportFetch(`/pharmacy/support/conversations/${id}/messages?${query.toString()}`)
  },

  async createConversation(subject: string, body: string, attachmentId?: string): Promise<{ conversation: SupportConversation; message: SupportMessage }> {
    return supportFetch('/pharmacy/support/conversations', {
      method: 'POST',
      body: JSON.stringify({ subject: subject || undefined, body, attachment_id: attachmentId || undefined }),
    })
  },

  async sendMessage(id: string, body: string, attachmentId?: string): Promise<SupportMessage> {
    const data = await supportFetch<{ message: SupportMessage }>(
      `/pharmacy/support/conversations/${id}/messages`,
      { method: 'POST', body: JSON.stringify({ body, attachment_id: attachmentId || undefined }) }
    )
    return data.message
  },

  async markRead(id: string): Promise<void> {
    await supportFetch(`/pharmacy/support/conversations/${id}/read`, { method: 'POST', body: JSON.stringify({}) })
  },

  async closeConversation(id: string): Promise<SupportConversation> {
    const data = await supportFetch<{ conversation: SupportConversation }>(
      `/pharmacy/support/conversations/${id}/close`,
      { method: 'POST', body: JSON.stringify({}) }
    )
    return data.conversation
  },

  async uploadAttachment(payload: { file_name: string; mime_type: string; content: string }): Promise<SupportAttachmentMeta> {
    const data = await supportFetch<{ attachment: SupportAttachmentMeta }>(
      '/pharmacy/support/attachments',
      { method: 'POST', body: JSON.stringify(payload) }
    )
    return data.attachment
  },

  async downloadAttachment(id: string): Promise<Blob> {
    const response = await fetch(`${API_BASE_URL}/pharmacy/support/attachments/${id}`, {
      credentials: 'include',
    })
    if (!response.ok) throw new Error('attachment_download_failed')
    return response.blob()
  },

  async tickets(): Promise<SupportTicket[]> {
    const data = await supportFetch<{ tickets: SupportTicket[] }>('/pharmacy/support/tickets')
    return data.tickets
  },

  async createTicket(payload: { subject: string; category: string; priority?: string; body?: string; conversation_id?: string }): Promise<SupportTicket> {
    const data = await supportFetch<{ ticket: SupportTicket }>('/pharmacy/support/tickets', {
      method: 'POST',
      body: JSON.stringify(payload),
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

/** Live event pipe — identical policy to the platform client. */
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
        /* ignore malformed frames — REST remains the truth */
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
