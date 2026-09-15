"use client";

// Support desk (Phase T2) — the platform side of the live chat + tickets.
// Two surfaces on one page: the CONVERSATION inbox (live chat with per-company
// channels, typing indicators, attachments, presence) and the TICKET work
// table (guarded lifecycle with an audited note). REST is the source of
// truth: the WebSocket only accelerates delivery, and while it is down the
// page polls the same endpoints — a dropped socket loses nothing.

import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  LifeBuoy, MessageSquare, Ticket as TicketIcon, Send, Paperclip, X, Circle,
  RefreshCw, Loader2, Eye, Lock,
} from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, Button, Badge } from "@/components/ui";
import { Table, TableHeader, TableBody, TableRow, TableHead } from "@/components/ui/table";
import { Modal } from "@/components/ui/modal";
import {
  supportApi, SupportSocket, type SocketStatus,
  type SupportConversation, type SupportConversationDetail, type SupportMessage,
  type SupportOverview, type SupportTicket, type SupportTicketStatus,
} from "@/lib/support";
import { useT } from "@/i18n/provider";
import { fmtDateTime } from "@/i18n/format";

type InboxFilter = "all" | "unread" | "unanswered" | "closed";
type Tab = "chats" | "tickets";

const priorityVariant: Record<string, "success" | "warning" | "destructive" | "secondary" | "default"> = {
  urgent: "destructive",
  high: "warning",
  normal: "secondary",
  low: "secondary",
};

const statusVariant: Record<SupportTicketStatus, "success" | "warning" | "destructive" | "secondary" | "default"> = {
  open: "warning",
  in_progress: "default",
  waiting_customer: "secondary",
  resolved: "success",
  closed: "secondary",
};

const ATTACH_MIMES = ["image/png", "image/jpeg", "image/webp", "image/gif", "application/pdf"];

export default function SupportPage() {
  const t = useT("support");
  const [tab, setTab] = useState<Tab>("chats");
  const [overview, setOverview] = useState<SupportOverview | null>(null);

  // Inbox state
  const [filter, setFilter] = useState<InboxFilter>("all");
  const [conversations, setConversations] = useState<SupportConversation[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [detail, setDetail] = useState<SupportConversationDetail | null>(null);
  const [messages, setMessages] = useState<SupportMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [typingAt, setTypingAt] = useState(0);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const typingSentAt = useRef(0);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Tickets state
  const [tickets, setTickets] = useState<SupportTicket[]>([]);
  const [ticketDetail, setTicketDetail] = useState<SupportTicket | null>(null);
  const [resolutionNote, setResolutionNote] = useState("");
  const [ticketFilters, setTicketFilters] = useState<{ status: string; priority: string; category: string }>({
    status: "active", priority: "", category: "",
  });

  const [socketStatus, setSocketStatus] = useState<SocketStatus>("closed");

  const socketRef = useRef<SupportSocket | null>(null);
  const activeIdRef = useRef<string | null>(null);
  activeIdRef.current = activeId;

  // --- data loaders --------------------------------------------------------
  const loadOverview = useCallback(async () => {
    try {
      setOverview(await supportApi.overview());
    } catch {
      /* transient */
    }
  }, []);

  const loadConversations = useCallback(async () => {
    try {
      setConversations(await supportApi.conversations(filter));
    } catch {
      /* transient */
    }
  }, [filter]);

  const loadConversation = useCallback(async (id: string) => {
    try {
      const d = await supportApi.conversation(id);
      const page = await supportApi.messages(id);
      setDetail(d);
      setMessages(page.messages);
      // Viewing the chat means reading it — clear the operator's counter.
      if (d.conversation.platform_unread_count > 0) {
        await supportApi.markRead(id).catch(() => undefined);
        setDetail((prev) =>
          prev && prev.conversation.id === id
            ? { ...prev, conversation: { ...prev.conversation, platform_unread_count: 0 } }
            : prev
        );
        loadOverview();
      }
    } catch {
      toast.error(t("load_failed"));
    }
  }, [t, loadOverview]);

  const loadTickets = useCallback(async () => {
    try {
      setTickets(await supportApi.tickets(ticketFilters));
    } catch {
      /* transient */
    }
  }, [ticketFilters]);

  // --- socket: the live accelerator ---------------------------------------
  useEffect(() => {
    const socket = new SupportSocket("/platform-admin/support/ws");
    socketRef.current = socket;
    socket.onStatus = (status) => setSocketStatus(status);
    socket.onEvent = (event) => {
      const openId = activeIdRef.current;
      if (event.type === "message.new" && event.message) {
        const msg = event.message;
        if (msg.conversation_id === openId) {
          // Dedupe by id (the sender's own writes are echoed to all devices).
          setMessages((prev) => (prev.some((m) => m.id === msg.id) ? prev : [...prev, msg]));
          if (msg.sender_realm === "pharmacy") {
            supportApi.markRead(msg.conversation_id).catch(() => undefined);
          }
          setTypingAt(0);
        }
        loadConversations();
        loadOverview();
      } else if (event.type === "typing" && event.conversation_id === openId && event.actor === "pharmacy") {
        setTypingAt(Date.now());
      } else if (event.type === "conversation.updated" && event.conversation_id === openId) {
        loadConversation(event.conversation_id);
        loadConversations();
      } else if (event.type === "ticket.updated" && event.ticket) {
        const fresh = event.ticket;
        setTickets((prev) => {
          const next = prev.filter((x) => x.id !== fresh.id);
          next.unshift(fresh);
          return next;
        });
        setTicketDetail((prev) => (prev && prev.id === fresh.id ? fresh : prev));
        loadOverview();
      }
    };
    socket.connect();
    return () => socket.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Typing indicator auto-hide
  useEffect(() => {
    if (!typingAt) return;
    const timer = setTimeout(() => setTypingAt(0), 2500);
    return () => clearTimeout(timer);
  }, [typingAt]);

  // Polling fallback: the same REST truth at a slower cadence while the
  // socket is down; a light list/overview refresh even when it is up.
  useEffect(() => {
    const heavy = setInterval(() => {
      if (socketStatus !== "open") {
        loadConversations();
        loadOverview();
        if (activeIdRef.current) loadConversation(activeIdRef.current);
      }
    }, 6000);
    const light = setInterval(() => {
      if (socketStatus === "open") {
        loadConversations();
        loadOverview();
      }
    }, 20000);
    return () => {
      clearInterval(heavy);
      clearInterval(light);
    };
  }, [socketStatus, loadConversations, loadOverview, loadConversation]);

  useEffect(() => {
    loadOverview();
    loadTickets();
  }, [loadOverview, loadTickets]);

  useEffect(() => {
    loadConversations();
  }, [loadConversations]);

  // Auto-scroll chat
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, typingAt]);

  const openConversation = useCallback(
    (id: string) => {
      setActiveId(id);
      setDetail(null);
      setMessages([]);
      loadConversation(id);
    },
    [loadConversation]
  );

  // --- actions --------------------------------------------------------------
  const send = useCallback(async () => {
    const body = draft.trim();
    if (!body || !activeId || sending) return;
    setSending(true);
    try {
      const msg = await supportApi.sendMessage(activeId, body);
      setMessages((prev) => (prev.some((m) => m.id === msg.id) ? prev : [...prev, msg]));
      setDraft("");
      loadConversations();
    } catch (e) {
      const code = (e as Error).message;
      toast.error(code === "conversation_closed" ? t("closed_banner") : t("send_failed"));
    } finally {
      setSending(false);
    }
  }, [draft, activeId, sending, t, loadConversations]);

  const onPickFile = useCallback(async (file: File | null) => {
    if (!file || !activeId || !detail) return;
    if (!ATTACH_MIMES.includes(file.type)) {
      toast.error(t("bad_mime"));
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      toast.error(t("file_too_large"));
      return;
    }
    setUploading(true);
    try {
      const base64 = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result).split(",")[1] || "");
        reader.onerror = () => reject(new Error("read_failed"));
        reader.readAsDataURL(file);
      });
      const att = await supportApi.uploadAttachment({
        file_name: file.name,
        mime_type: file.type,
        content: base64,
        company_id: detail.conversation.company_id,
      });
      const msg = await supportApi.sendMessage(activeId, "", att.id);
      setMessages((prev) => (prev.some((m) => m.id === msg.id) ? prev : [...prev, msg]));
      loadConversations();
    } catch {
      toast.error(t("upload_failed"));
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }, [activeId, detail, t, loadConversations]);

  const closeConversation = useCallback(async () => {
    if (!activeId) return;
    try {
      const conv = await supportApi.closeConversation(activeId);
      setDetail((prev) => (prev ? { ...prev, conversation: conv } : prev));
      loadConversations();
      toast.success(t("closed_toast"));
    } catch {
      toast.error(t("send_failed"));
    }
  }, [activeId, t, loadConversations]);

  const ticketAction = useCallback(async (ticket: SupportTicket, patch: { status?: string; priority?: string; resolution_note?: string }) => {
    try {
      const fresh = await supportApi.updateTicket(ticket.id, patch);
      setTicketDetail(fresh);
      setTickets((prev) => prev.map((x) => (x.id === fresh.id ? fresh : x)));
      toast.success(t("ticket_updated_toast"));
      loadOverview();
    } catch (e) {
      const code = (e as Error).message;
      if (code === "invalid_transition") toast.error(t("invalid_transition"));
      else toast.error(t("send_failed"));
    }
  }, [t, loadOverview]);

  const sendTyping = useCallback(() => {
    const socket = socketRef.current;
    if (!socket || !activeId) return;
    const now = Date.now();
    if (now - typingSentAt.current < 1200) return;
    typingSentAt.current = now;
    socket.sendTyping(activeId);
  }, [activeId]);

  const active = detail?.conversation ?? null;
  const activeTicket = detail?.ticket ?? null;
  const presenceColor = overview?.platform_online ? "text-emerald-500" : "text-zinc-400";

  return (
    <div className="flex flex-col gap-4">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold">
            <LifeBuoy className="h-6 w-6 text-teal-600" />
            {t("title")}
          </h1>
          <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
        </div>
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Circle className={`h-3 w-3 fill-current ${presenceColor}`} />
          {overview?.platform_online ? t("presence_online") : t("presence_offline")}
          <Badge variant={socketStatus === "open" ? "success" : "secondary"}>
            {socketStatus === "open" ? t("live") : t("polling")}
          </Badge>
        </div>
      </div>

      {/* Overview cards */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <OverviewCard label={t("unread")} value={overview?.unread_conversations ?? 0} tone="text-teal-600" />
        <OverviewCard label={t("unanswered")} value={overview?.unanswered_conversations ?? 0} tone="text-amber-600" />
        <OverviewCard label={t("open_tickets")} value={overview?.open_tickets ?? 0} tone="text-blue-600" />
        <OverviewCard label={t("urgent_tickets")} value={overview?.urgent_tickets ?? 0} tone="text-red-600" />
      </div>

      {/* Tabs */}
      <div className="flex gap-2">
        <Button variant={tab === "chats" ? "default" : "outline"} size="sm" onClick={() => setTab("chats")}>
          <MessageSquare className="h-4 w-4" />
          {t("tab_chats")}
        </Button>
        <Button variant={tab === "tickets" ? "default" : "outline"} size="sm" onClick={() => setTab("tickets")}>
          <TicketIcon className="h-4 w-4" />
          {t("tab_tickets")}
        </Button>
      </div>

      {tab === "chats" ? (
        <div className="grid gap-4 lg:grid-cols-3">
          {/* Inbox list */}
          <Card className="lg:col-span-1">
            <CardContent className="p-3">
              <div className="mb-2 flex flex-wrap gap-1.5">
                {(["all", "unread", "unanswered", "closed"] as InboxFilter[]).map((f) => (
                  <Button key={f} size="sm" variant={filter === f ? "default" : "outline"} className="h-7 px-2 text-xs" onClick={() => setFilter(f)}>
                    {t(`filter_${f}`)}
                  </Button>
                ))}
              </div>
              <div className="max-h-[540px] space-y-1 overflow-y-auto">
                {conversations.length === 0 && <p className="py-10 text-center text-sm text-muted-foreground">{t("no_conversations")}</p>}
                {conversations.map((conv) => (
                  <button
                    key={conv.id}
                    onClick={() => openConversation(conv.id)}
                    className={`w-full rounded-lg border p-2.5 text-start transition-colors hover:bg-muted/60 ${
                      conv.id === activeId ? "border-teal-500 bg-muted/40" : "border-transparent"
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="truncate text-sm font-semibold">{conv.company_name || conv.company_id}</span>
                      {conv.platform_unread_count > 0 && (
                        <Badge variant="destructive" className="h-5 min-w-5 justify-center px-1.5">
                          {conv.platform_unread_count}
                        </Badge>
                      )}
                    </div>
                    <p className="truncate text-xs text-muted-foreground">{conv.subject}</p>
                    <div className="flex items-center justify-between gap-2">
                      <p className="truncate text-xs text-muted-foreground">{conv.last_message_preview}</p>
                      <span className="shrink-0 text-[10px] text-muted-foreground">
                        {conv.last_message_at ? fmtDateTime(conv.last_message_at) : ""}
                      </span>
                    </div>
                  </button>
                ))}
              </div>
            </CardContent>
          </Card>

          {/* Chat pane */}
          <Card className="lg:col-span-2">
            <CardContent className="flex h-[600px] flex-col p-0">
              {!active ? (
                <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">{t("pick_conversation")}</div>
              ) : (
                <>
                  <div className="flex items-center justify-between gap-2 border-b p-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold">{active.subject}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {active.company_name} {activeTicket ? `· ${activeTicket.number}` : ""}
                      </p>
                    </div>
                    <div className="flex items-center gap-1.5">
                      {active.status === "closed" ? (
                        <Badge variant="secondary"><Lock className="h-3 w-3" />{t("status_closed_conv")}</Badge>
                      ) : (
                        <Button size="sm" variant="outline" onClick={closeConversation}>{t("close_conv")}</Button>
                      )}
                    </div>
                  </div>

                  <div className="flex-1 space-y-2 overflow-y-auto p-3">
                    {messages.map((m) =>
                      m.is_system ? (
                        <div key={m.id} className="py-1 text-center text-xs text-muted-foreground">
                          <span className="rounded-full bg-muted px-2 py-0.5">{m.body}</span>
                        </div>
                      ) : (
                        <div key={m.id} className={`flex ${m.sender_realm === "platform" ? "justify-end" : "justify-start"}`}>
                          <div
                            className={`max-w-[78%] rounded-2xl px-3 py-2 text-sm ${
                              m.sender_realm === "platform"
                                ? "rounded-br-sm bg-teal-600 text-white"
                                : "rounded-bl-sm border bg-muted/40"
                            }`}
                          >
                            <p className="mb-1 text-[10px] opacity-70">{m.sender_name}</p>
                            {m.body && <p className="whitespace-pre-wrap break-words">{m.body}</p>}
                            {m.attachment_id && <AttachmentView id={m.attachment_id} />}
                            <p className={`mt-1 text-[10px] ${m.sender_realm === "platform" ? "text-white/60" : "text-muted-foreground"}`}>
                              {m.created_at ? fmtDateTime(m.created_at) : ""}
                            </p>
                          </div>
                        </div>
                      )
                    )}
                    {typingAt > 0 && <div className="text-xs text-muted-foreground">{t("typing")}</div>}
                    <div ref={bottomRef} />
                  </div>

                  <div className="flex items-end gap-2 border-t p-3">
                    <input
                      ref={fileRef}
                      type="file"
                      accept={ATTACH_MIMES.join(",")}
                      className="hidden"
                      onChange={(e) => onPickFile(e.target.files?.[0] ?? null)}
                    />
                    <Button size="icon" variant="ghost" disabled={active.status === "closed" || uploading} onClick={() => fileRef.current?.click()} aria-label={t("attach")}>
                      {uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Paperclip className="h-4 w-4" />}
                    </Button>
                    <textarea
                      value={draft}
                      onChange={(e) => {
                        setDraft(e.target.value);
                        sendTyping();
                      }}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" && !e.shiftKey) {
                          e.preventDefault();
                          send();
                        }
                      }}
                      placeholder={active.status === "closed" ? t("closed_banner") : t("placeholder")}
                      disabled={active.status === "closed"}
                      rows={1}
                      className="max-h-28 min-h-10 flex-1 resize-y rounded-lg border border-input bg-background px-3 py-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-50"
                    />
                    <Button size="icon" onClick={send} disabled={active.status === "closed" || sending || !draft.trim()} aria-label={t("send")}>
                      <Send className="h-4 w-4 rtl:rotate-180" />
                    </Button>
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        </div>
      ) : (
        /* Tickets table */
        <Card>
          <CardContent className="p-4">
            <div className="mb-3 flex flex-wrap gap-2">
              <select className="h-8 rounded-md border bg-background px-2 text-sm" value={ticketFilters.status} onChange={(e) => setTicketFilters((f) => ({ ...f, status: e.target.value }))}>
                {["active", "all", "open", "in_progress", "waiting_customer", "resolved", "closed"].map((s) => (
                  <option key={s} value={s}>{t(`tfilter_${s}`)}</option>
                ))}
              </select>
              <select className="h-8 rounded-md border bg-background px-2 text-sm" value={ticketFilters.priority} onChange={(e) => setTicketFilters((f) => ({ ...f, priority: e.target.value }))}>
                <option value="">{t("filter_priority_all")}</option>
                {["urgent", "high", "normal", "low"].map((p) => (
                  <option key={p} value={p}>{t(`priority_${p}`)}</option>
                ))}
              </select>
              <select className="h-8 rounded-md border bg-background px-2 text-sm" value={ticketFilters.category} onChange={(e) => setTicketFilters((f) => ({ ...f, category: e.target.value }))}>
                <option value="">{t("filter_category_all")}</option>
                {["billing", "technical", "inventory", "account", "feature_request", "other"].map((c) => (
                  <option key={c} value={c}>{t(`category_${c}`)}</option>
                ))}
              </select>
              <Button size="sm" variant="outline" onClick={loadTickets}><RefreshCw className="h-3.5 w-3.5" /></Button>
            </div>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("col_number")}</TableHead>
                  <TableHead>{t("col_subject")}</TableHead>
                  <TableHead>{t("col_company")}</TableHead>
                  <TableHead>{t("col_category")}</TableHead>
                  <TableHead>{t("col_priority")}</TableHead>
                  <TableHead>{t("col_status")}</TableHead>
                  <TableHead>{t("col_actions")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {tickets.length === 0 && (
                  <TableRow>
                    <td colSpan={7} className="py-10 text-center text-sm text-muted-foreground">{t("no_tickets")}</td>
                  </TableRow>
                )}
                {tickets.map((ticket) => (
                  <TableRow key={ticket.id}>
                    <td className="font-mono text-xs">{ticket.number}</td>
                    <td className="max-w-56 truncate">{ticket.subject}</td>
                    <td className="max-w-40 truncate text-muted-foreground">{ticket.company_name || ticket.company_id}</td>
                    <td><Badge variant="outline">{t(`category_${ticket.category}`)}</Badge></td>
                    <td><Badge variant={priorityVariant[ticket.priority]}>{t(`priority_${ticket.priority}`)}</Badge></td>
                    <td><Badge variant={statusVariant[ticket.status]}>{t(`tstatus_${ticket.status}`)}</Badge></td>
                    <td>
                      <Button size="sm" variant="ghost" onClick={() => { setTicketDetail(ticket); setResolutionNote(ticket.resolution_note || ""); }}>
                        <Eye className="h-4 w-4" />
                      </Button>
                    </td>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Ticket detail / lifecycle modal */}
      <Modal isOpen={!!ticketDetail} onClose={() => setTicketDetail(null)}>
        {ticketDetail && (
          <div className="w-[460px] max-w-[92vw] space-y-4 text-start">
            <div className="flex items-start justify-between gap-2">
              <h2 className="text-lg font-bold">{ticketDetail.number}</h2>
              <Button size="icon" variant="ghost" onClick={() => setTicketDetail(null)} aria-label="close">
                <X className="h-4 w-4" />
              </Button>
            </div>
            <p className="text-sm font-medium">{ticketDetail.subject}</p>
            <div className="grid grid-cols-2 gap-1.5 text-sm">
              <p className="text-muted-foreground">{t("col_company")}</p>
              <p className="truncate">{ticketDetail.company_name || ticketDetail.company_id}</p>
              <p className="text-muted-foreground">{t("col_category")}</p>
              <p>{t(`category_${ticketDetail.category}`)}</p>
              <p className="text-muted-foreground">{t("col_priority")}</p>
              <p>{t(`priority_${ticketDetail.priority}`)}</p>
              <p className="text-muted-foreground">{t("col_status")}</p>
              <p><Badge variant={statusVariant[ticketDetail.status]}>{t(`tstatus_${ticketDetail.status}`)}</Badge></p>
              <p className="text-muted-foreground">{t("col_created")}</p>
              <p>{ticketDetail.created_at ? fmtDateTime(ticketDetail.created_at) : "—"}</p>
            </div>
            <div>
              <label className="mb-1 block text-sm font-medium">{t("resolution_note")}</label>
              <textarea
                value={resolutionNote}
                onChange={(e) => setResolutionNote(e.target.value)}
                rows={3}
                placeholder={t("resolution_note_ph")}
                className="w-full resize-y rounded-lg border border-input bg-background px-3 py-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              />
            </div>
            <div className="flex flex-wrap gap-2">
              {ticketDetail.status === "open" && (
                <Button size="sm" onClick={() => ticketAction(ticketDetail, { status: "in_progress" })}>{t("action_start")}</Button>
              )}
              {ticketDetail.status === "in_progress" && (
                <Button size="sm" variant="outline" onClick={() => ticketAction(ticketDetail, { status: "waiting_customer" })}>{t("action_wait")}</Button>
              )}
              {(ticketDetail.status === "open" || ticketDetail.status === "in_progress") && (
                <Button size="sm" variant="gradient" onClick={() => ticketAction(ticketDetail, { status: "resolved", resolution_note: resolutionNote || undefined })}>{t("action_resolve")}</Button>
              )}
              {ticketDetail.status !== "closed" && (
                <Button size="sm" variant="destructive" onClick={() => ticketAction(ticketDetail, { status: "closed" })}>{t("action_close")}</Button>
              )}
              {(ticketDetail.status === "closed" || ticketDetail.status === "resolved") && (
                <Button size="sm" variant="outline" onClick={() => ticketAction(ticketDetail, { status: "in_progress" })}>{t("action_reopen")}</Button>
              )}
              <Button size="sm" variant="secondary" onClick={() => ticketAction(ticketDetail, { resolution_note: resolutionNote })}>{t("action_save_note")}</Button>
            </div>
            {ticketDetail.resolution_note && (
              <p className="rounded-lg bg-muted/50 p-2 text-sm whitespace-pre-wrap">{ticketDetail.resolution_note}</p>
            )}
          </div>
        )}
      </Modal>
    </div>
  );
}

function OverviewCard({ label, value, tone }: { label: string; value: number; tone: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs text-muted-foreground">{label}</p>
        <p className={`text-2xl font-bold ${tone}`}>{value}</p>
      </CardContent>
    </Card>
  );
}

function AttachmentView({ id }: { id: string }) {
  const t = useT("support");
  const [src, setSrc] = useState<string | null>(null);
  const [mime, setMime] = useState<string>("");
  useEffect(() => {
    let alive = true;
    let url: string | null = null;
    supportApi.downloadAttachment(id).then((blob) => {
      if (!alive) return;
      url = URL.createObjectURL(blob);
      setMime(blob.type);
      setSrc(url);
    }).catch(() => undefined);
    return () => {
      alive = false;
      if (url) URL.revokeObjectURL(url);
    };
  }, [id]);
  if (!src) return <p className="text-xs opacity-60">{t("attachment")}</p>;
  if (mime.startsWith("image/")) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={src} alt={t("attachment")} className="mt-1 max-h-48 rounded-lg" />;
  }
  return (
    <a href={src} download className="mt-1 block text-xs underline">
      {t("attachment")}
    </a>
  );
}
