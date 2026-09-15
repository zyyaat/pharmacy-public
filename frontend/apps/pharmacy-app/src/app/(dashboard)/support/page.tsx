"use client";

// Support (Phase T2) — the COMPANY side: chat with the platform team, open
// tickets, follow their lifecycle. Deliberately never gated: an expired or
// suspended company must still be able to ask for help, which is why this
// page sits outside the permission/plan gates entirely (the backend refuses
// nothing here either).

import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  LifeBuoy, MessageSquare, Ticket as TicketIcon, Send, Paperclip, X, Circle,
  Plus, Lock, Loader2,
} from "lucide-react";
import { Card, CardContent, Button, Input, Badge } from "@/components/ui";
import { Modal } from "@/components/ui/modal";
import { Table, TableHeader, TableBody, TableRow, TableHead } from "@/components/ui/table";
import {
  supportApi, SupportSocket, type SocketStatus,
  type SupportConversation, type SupportConversationDetail, type SupportMessage,
  type SupportOverview, type SupportTicket, type SupportTicketStatus,
} from "@/lib/support";
import { useT } from "@/i18n/provider";
import { fmtDateTime } from "@/i18n/format";

const statusVariant: Record<SupportTicketStatus, "success" | "warning" | "destructive" | "secondary" | "default"> = {
  open: "warning",
  in_progress: "default",
  waiting_customer: "secondary",
  resolved: "success",
  closed: "secondary",
};

const ATTACH_MIMES = ["image/png", "image/jpeg", "image/webp", "image/gif", "application/pdf"];

type Notice = { kind: "ok" | "err"; text: string } | null;

export default function SupportPage() {
  const t = useT("support");
  const [tab, setTab] = useState<"chats" | "tickets">("chats");
  const [overview, setOverview] = useState<SupportOverview | null>(null);
  const [notice, setNotice] = useState<Notice>(null);

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

  const [newConvOpen, setNewConvOpen] = useState(false);
  const [newConvSubject, setNewConvSubject] = useState("");
  const [newConvBody, setNewConvBody] = useState("");
  const [newConvBusy, setNewConvBusy] = useState(false);

  const [tickets, setTickets] = useState<SupportTicket[]>([]);
  const [ticketDetail, setTicketDetail] = useState<SupportTicket | null>(null);
  const [newTicketOpen, setNewTicketOpen] = useState(false);
  const [newTicket, setNewTicket] = useState({ subject: "", category: "technical", priority: "normal", body: "" });
  const [newTicketBusy, setNewTicketBusy] = useState(false);

  const [socketStatus, setSocketStatus] = useState<SocketStatus>("closed");
  const socketRef = useRef<SupportSocket | null>(null);
  const activeIdRef = useRef<string | null>(null);
  activeIdRef.current = activeId;

  const showNotice = useCallback((kind: "ok" | "err", text: string) => {
    setNotice({ kind, text });
    setTimeout(() => setNotice(null), 3500);
  }, []);

  const loadOverview = useCallback(async () => {
    try {
      setOverview(await supportApi.overview());
    } catch {
      /* transient */
    }
  }, []);

  const loadConversations = useCallback(async () => {
    try {
      setConversations(await supportApi.conversations());
    } catch {
      /* transient */
    }
  }, []);

  const loadConversation = useCallback(async (id: string) => {
    try {
      const d = await supportApi.conversation(id);
      const page = await supportApi.messages(id);
      setDetail(d);
      setMessages(page.messages);
      if (d.conversation.company_unread_count > 0) {
        await supportApi.markRead(id).catch(() => undefined);
        setDetail((prev) =>
          prev && prev.conversation.id === id
            ? { ...prev, conversation: { ...prev.conversation, company_unread_count: 0 } }
            : prev
        );
        loadOverview();
      }
    } catch {
      showNotice("err", t("load_failed"));
    }
  }, [t, showNotice, loadOverview]);

  const loadTickets = useCallback(async () => {
    try {
      setTickets(await supportApi.tickets());
    } catch {
      /* transient */
    }
  }, []);

  useEffect(() => {
    const socket = new SupportSocket("/pharmacy/support/ws");
    socketRef.current = socket;
    socket.onStatus = (status) => setSocketStatus(status);
    socket.onEvent = (event) => {
      const openId = activeIdRef.current;
      if (event.type === "message.new" && event.message) {
        const msg = event.message;
        if (msg.conversation_id === openId) {
          setMessages((prev) => (prev.some((m) => m.id === msg.id) ? prev : [...prev, msg]));
          if (msg.sender_realm === "platform") {
            supportApi.markRead(msg.conversation_id).catch(() => undefined);
          }
          setTypingAt(0);
        }
        loadConversations();
        loadOverview();
      } else if (event.type === "typing" && event.conversation_id === openId && event.actor === "platform") {
        setTypingAt(Date.now());
      } else if (event.type === "conversation.updated" && event.conversation_id === openId) {
        loadConversation(event.conversation_id);
        loadConversations();
      } else if (event.type === "ticket.updated" && event.ticket) {
        const fresh = event.ticket;
        setTickets((prev) => {
          const exists = prev.some((x) => x.id === fresh.id);
          return exists ? prev.map((x) => (x.id === fresh.id ? fresh : x)) : [fresh, ...prev];
        });
        setTicketDetail((prev) => (prev && prev.id === fresh.id ? fresh : prev));
        loadOverview();
      }
    };
    socket.connect();
    return () => socket.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!typingAt) return;
    const timer = setTimeout(() => setTypingAt(0), 2500);
    return () => clearTimeout(timer);
  }, [typingAt]);

  useEffect(() => {
    const heavy = setInterval(() => {
      if (socketStatus !== "open") {
        loadConversations();
        loadOverview();
        loadTickets();
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
  }, [socketStatus, loadConversations, loadOverview, loadTickets, loadConversation]);

  useEffect(() => {
    loadOverview();
    loadConversations();
    loadTickets();
  }, [loadOverview, loadConversations, loadTickets]);

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
      showNotice("err", code === "conversation_closed" ? t("closed_banner") : t("send_failed"));
    } finally {
      setSending(false);
    }
  }, [draft, activeId, sending, t, showNotice, loadConversations]);

  const onPickFile = useCallback(async (file: File | null) => {
    if (!file || !activeId) return;
    if (!ATTACH_MIMES.includes(file.type)) {
      showNotice("err", t("bad_mime"));
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      showNotice("err", t("file_too_large"));
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
      const att = await supportApi.uploadAttachment({ file_name: file.name, mime_type: file.type, content: base64 });
      const msg = await supportApi.sendMessage(activeId, "", att.id);
      setMessages((prev) => (prev.some((m) => m.id === msg.id) ? prev : [...prev, msg]));
      loadConversations();
    } catch {
      showNotice("err", t("upload_failed"));
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }, [activeId, t, showNotice, loadConversations]);

  const createConversation = useCallback(async () => {
    const body = newConvBody.trim();
    if (!body || newConvBusy) return;
    setNewConvBusy(true);
    try {
      const created = await supportApi.createConversation(newConvSubject.trim(), body);
      setNewConvOpen(false);
      setNewConvSubject("");
      setNewConvBody("");
      await loadConversations();
      openConversation(created.conversation.id);
    } catch (e) {
      const code = (e as Error).message;
      showNotice("err", code === "message_required" ? t("new_conv_message") : t("send_failed"));
    } finally {
      setNewConvBusy(false);
    }
  }, [newConvBody, newConvSubject, newConvBusy, t, showNotice, loadConversations, openConversation]);

  const closeConversation = useCallback(async () => {
    if (!activeId) return;
    try {
      const conv = await supportApi.closeConversation(activeId);
      setDetail((prev) => (prev ? { ...prev, conversation: conv } : prev));
      loadConversations();
      showNotice("ok", t("closed_toast"));
    } catch {
      showNotice("err", t("send_failed"));
    }
  }, [activeId, t, showNotice, loadConversations]);

  const createTicket = useCallback(async () => {
    if (!newTicket.subject.trim() || newTicketBusy) return;
    setNewTicketBusy(true);
    try {
      const ticket = await supportApi.createTicket({
        subject: newTicket.subject.trim(),
        category: newTicket.category,
        priority: newTicket.priority,
        body: newTicket.body.trim() || undefined,
      });
      setNewTicketOpen(false);
      setNewTicket({ subject: "", category: "technical", priority: "normal", body: "" });
      await loadTickets();
      loadOverview();
      showNotice("ok", `${t("ticket_created_toast")} · ${ticket.number}`);
    } catch {
      showNotice("err", t("send_failed"));
    } finally {
      setNewTicketBusy(false);
    }
  }, [newTicket, newTicketBusy, t, showNotice, loadTickets, loadOverview]);

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

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
        <MiniCard label={t("unread")} value={overview?.unread_conversations ?? 0} tone="text-teal-600" />
        <MiniCard label={t("open_tickets")} value={overview?.open_tickets ?? 0} tone="text-blue-600" />
        <MiniCard label={t("urgent_tickets")} value={overview?.urgent_tickets ?? 0} tone="text-red-600" />
      </div>

      {notice && (
        <div
          className={`rounded-lg border px-3 py-2 text-sm ${
            notice.kind === "ok"
              ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-400"
              : "border-destructive/30 bg-destructive/10 text-destructive"
          }`}
        >
          {notice.text}
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        <Button variant={tab === "chats" ? "default" : "outline"} size="sm" onClick={() => setTab("chats")}>
          <MessageSquare className="h-4 w-4" />
          {t("tab_chats")}
        </Button>
        <Button variant={tab === "tickets" ? "default" : "outline"} size="sm" onClick={() => setTab("tickets")}>
          <TicketIcon className="h-4 w-4" />
          {t("my_tickets")}
        </Button>
        {tab === "chats" ? (
          <Button size="sm" variant="gradient" onClick={() => setNewConvOpen(true)}>
            <Plus className="h-4 w-4" />
            {t("new_conv_btn")}
          </Button>
        ) : (
          <Button size="sm" variant="gradient" onClick={() => setNewTicketOpen(true)}>
            <Plus className="h-4 w-4" />
            {t("new_ticket_btn")}
          </Button>
        )}
      </div>

      {tab === "chats" ? (
        <div className="grid gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-1">
            <CardContent className="p-3">
              <div className="max-h-[540px] space-y-1 overflow-y-auto">
                {conversations.length === 0 && (
                  <p className="py-10 text-center text-sm text-muted-foreground">{t("no_conversations")}</p>
                )}
                {conversations.map((conv) => (
                  <button
                    key={conv.id}
                    onClick={() => openConversation(conv.id)}
                    className={`w-full rounded-lg border p-2.5 text-start transition-colors hover:bg-muted/60 ${
                      conv.id === activeId ? "border-teal-500 bg-muted/40" : "border-transparent"
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="truncate text-sm font-semibold">{conv.subject || t("tab_chats")}</span>
                      {conv.company_unread_count > 0 && (
                        <Badge variant="destructive" className="h-5 min-w-5 justify-center px-1.5">
                          {conv.company_unread_count}
                        </Badge>
                      )}
                    </div>
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

          <Card className="lg:col-span-2">
            <CardContent className="flex h-[600px] flex-col p-0">
              {!active ? (
                <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">{t("pick_conversation")}</div>
              ) : (
                <>
                  <div className="flex items-center justify-between gap-2 border-b p-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold">{active.subject}</p>
                      {activeTicket && <p className="truncate text-xs text-muted-foreground">{activeTicket.number}</p>}
                    </div>
                    {active.status === "closed" ? (
                      <Badge variant="secondary"><Lock className="h-3 w-3" />{t("status_closed_conv")}</Badge>
                    ) : (
                      <Button size="sm" variant="outline" onClick={closeConversation}>{t("close_conv")}</Button>
                    )}
                  </div>

                  <div className="flex-1 space-y-2 overflow-y-auto p-3">
                    {messages.map((m) =>
                      m.is_system ? (
                        <div key={m.id} className="py-1 text-center text-xs text-muted-foreground">
                          <span className="rounded-full bg-muted px-2 py-0.5">{m.body}</span>
                        </div>
                      ) : (
                        <div key={m.id} className={`flex ${m.sender_realm === "pharmacy" ? "justify-end" : "justify-start"}`}>
                          <div
                            className={`max-w-[78%] rounded-2xl px-3 py-2 text-sm ${
                              m.sender_realm === "pharmacy"
                                ? "rounded-br-sm bg-teal-600 text-white"
                                : "rounded-bl-sm border bg-muted/40"
                            }`}
                          >
                            <p className="mb-1 text-[10px] opacity-70">
                              {m.sender_realm === "platform" ? t("title") : m.sender_name}
                            </p>
                            {m.body && <p className="whitespace-pre-wrap break-words">{m.body}</p>}
                            {m.attachment_id && <AttachmentView id={m.attachment_id} />}
                            <p className={`mt-1 text-[10px] ${m.sender_realm === "pharmacy" ? "text-white/60" : "text-muted-foreground"}`}>
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
        <Card>
          <CardContent className="p-4">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("col_number")}</TableHead>
                  <TableHead>{t("col_subject")}</TableHead>
                  <TableHead>{t("col_category")}</TableHead>
                  <TableHead>{t("col_priority")}</TableHead>
                  <TableHead>{t("col_status")}</TableHead>
                  <TableHead>{t("col_created")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {tickets.length === 0 && (
                  <TableRow>
                    <td colSpan={6} className="py-10 text-center text-sm text-muted-foreground">{t("no_tickets")}</td>
                  </TableRow>
                )}
                {tickets.map((ticket) => (
                  <TableRow key={ticket.id} className="cursor-pointer" onClick={() => setTicketDetail(ticket)}>
                    <td className="font-mono text-xs">{ticket.number}</td>
                    <td className="max-w-56 truncate">{ticket.subject}</td>
                    <td><Badge variant="outline">{t(`category_${ticket.category}`)}</Badge></td>
                    <td><Badge variant={ticket.priority === "urgent" ? "destructive" : ticket.priority === "high" ? "warning" : "secondary"}>{t(`priority_${ticket.priority}`)}</Badge></td>
                    <td><Badge variant={statusVariant[ticket.status]}>{t(`tstatus_${ticket.status}`)}</Badge></td>
                    <td className="text-muted-foreground">{ticket.created_at ? fmtDateTime(ticket.created_at) : "—"}</td>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      <Modal isOpen={newConvOpen} onClose={() => setNewConvOpen(false)}>
        <div className="w-[420px] max-w-[92vw] space-y-3 text-start">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-bold">{t("new_conv_title")}</h2>
            <Button size="icon" variant="ghost" onClick={() => setNewConvOpen(false)} aria-label={t("cancel")}>
              <X className="h-4 w-4" />
            </Button>
          </div>
          <Input value={newConvSubject} onChange={(e) => setNewConvSubject(e.target.value)} placeholder={t("new_conv_subject")} maxLength={200} />
          <textarea
            value={newConvBody}
            onChange={(e) => setNewConvBody(e.target.value)}
            rows={4}
            maxLength={4000}
            placeholder={t("new_conv_message_ph")}
            className="w-full resize-y rounded-lg border border-input bg-background px-3 py-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          />
          <div className="flex justify-end gap-2">
            <Button variant="outline" size="sm" onClick={() => setNewConvOpen(false)}>{t("cancel")}</Button>
            <Button size="sm" onClick={createConversation} disabled={newConvBusy || !newConvBody.trim()}>
              {newConvBusy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4 rtl:rotate-180" />}
              {t("new_conv_submit")}
            </Button>
          </div>
        </div>
      </Modal>

      <Modal isOpen={!!ticketDetail} onClose={() => setTicketDetail(null)}>
        {ticketDetail && (
          <div className="w-[420px] max-w-[92vw] space-y-3 text-start">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-bold">{ticketDetail.number}</h2>
              <Button size="icon" variant="ghost" onClick={() => setTicketDetail(null)} aria-label={t("cancel")}>
                <X className="h-4 w-4" />
              </Button>
            </div>
            <p className="text-sm font-medium">{ticketDetail.subject}</p>
            <div className="grid grid-cols-2 gap-1.5 text-sm">
              <p className="text-muted-foreground">{t("col_category")}</p>
              <p>{t(`category_${ticketDetail.category}`)}</p>
              <p className="text-muted-foreground">{t("col_priority")}</p>
              <p>{t(`priority_${ticketDetail.priority}`)}</p>
              <p className="text-muted-foreground">{t("col_status")}</p>
              <p><Badge variant={statusVariant[ticketDetail.status]}>{t(`tstatus_${ticketDetail.status}`)}</Badge></p>
              <p className="text-muted-foreground">{t("col_created")}</p>
              <p>{ticketDetail.created_at ? fmtDateTime(ticketDetail.created_at) : "—"}</p>
            </div>
            {ticketDetail.resolution_note && (
              <div>
                <p className="mb-1 text-sm font-medium">{t("resolution_note")}</p>
                <p className="rounded-lg bg-muted/50 p-2 text-sm whitespace-pre-wrap">{ticketDetail.resolution_note}</p>
              </div>
            )}
          </div>
        )}
      </Modal>

      <Modal isOpen={newTicketOpen} onClose={() => setNewTicketOpen(false)}>
        <div className="w-[440px] max-w-[92vw] space-y-3 text-start">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-bold">{t("new_ticket_title")}</h2>
            <Button size="icon" variant="ghost" onClick={() => setNewTicketOpen(false)} aria-label={t("cancel")}>
              <X className="h-4 w-4" />
            </Button>
          </div>
          <Input
            value={newTicket.subject}
            onChange={(e) => setNewTicket((s) => ({ ...s, subject: e.target.value }))}
            placeholder={t("new_ticket_subject_ph")}
            maxLength={200}
          />
          <div className="grid grid-cols-2 gap-2">
            <select
              className="h-10 rounded-lg border border-input bg-background px-2 text-sm"
              value={newTicket.category}
              onChange={(e) => setNewTicket((s) => ({ ...s, category: e.target.value }))}
            >
              {["billing", "technical", "inventory", "account", "feature_request", "other"].map((c) => (
                <option key={c} value={c}>{t(`category_${c}`)}</option>
              ))}
            </select>
            <select
              className="h-10 rounded-lg border border-input bg-background px-2 text-sm"
              value={newTicket.priority}
              onChange={(e) => setNewTicket((s) => ({ ...s, priority: e.target.value }))}
            >
              {["low", "normal", "high", "urgent"].map((p) => (
                <option key={p} value={p}>{t(`priority_${p}`)}</option>
              ))}
            </select>
          </div>
          <textarea
            value={newTicket.body}
            onChange={(e) => setNewTicket((s) => ({ ...s, body: e.target.value }))}
            rows={4}
            maxLength={4000}
            placeholder={t("new_ticket_body")}
            className="w-full resize-y rounded-lg border border-input bg-background px-3 py-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          />
          <div className="flex justify-end gap-2">
            <Button variant="outline" size="sm" onClick={() => setNewTicketOpen(false)}>{t("cancel")}</Button>
            <Button size="sm" onClick={createTicket} disabled={newTicketBusy || !newTicket.subject.trim()}>
              {newTicketBusy ? <Loader2 className="h-4 w-4 animate-spin" /> : <TicketIcon className="h-4 w-4" />}
              {t("new_conv_submit")}
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}

function MiniCard({ label, value, tone }: { label: string; value: number; tone: string }) {
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
