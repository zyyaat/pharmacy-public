#!/usr/bin/env python3
"""Phase T2 — support i18n scaffolding (admin-dashboard + pharmacy-app).

Creates the `support` namespace for all 8 locales (ar+en authored, the other
6 translated), adds the nav key, and registers the namespace in
messages/index.ts for both apps. Idempotent — safe to re-run.
"""
import json
import os

ROOT = "/home/z/my-project/pharmacy-public/frontend/apps"

AR = {
    "title": "الدعم والمساعدة",
    "subtitle": "دردشة حية مع فريق الدعم وإدارة التذاكر",
    "tab_chats": "الدردشات",
    "tab_tickets": "التذاكر",
    "live": "مباشر",
    "polling": "تحديث دوري",
    "unread": "غير مقروءة",
    "unanswered": "بلا رد",
    "open_tickets": "تذاكر مفتوحة",
    "urgent_tickets": "تذاكر عاجلة",
    "presence_online": "فريق الدعم متصل",
    "presence_offline": "فريق الدعم غير متصل الآن — سنرد بريدًا عند الحاجة",
    "filter_all": "الكل",
    "filter_unread": "غير المقروءة",
    "filter_unanswered": "بلا رد",
    "filter_closed": "المغلقة",
    "no_conversations": "لا محادثات مطابقة",
    "pick_conversation": "اختر محادثة من القائمة",
    "status_closed_conv": "مغلقة",
    "close_conv": "إغلاق المحادثة",
    "closed_banner": "هذه المحادثة مغلقة — لا يمكن إرسال رسائل جديدة",
    "closed_toast": "أُغلقت المحادثة",
    "placeholder": "اكتب رسالتك… (Enter للإرسال)",
    "send": "إرسال",
    "attach": "إرفاق ملف",
    "typing": "الطرف الآخر يكتب الآن…",
    "attachment": "مرفق",
    "load_failed": "تعذر التحميل",
    "send_failed": "تعذر الإرسال — حاول مجددًا",
    "bad_mime": "نوع الملف غير مدعوم (صور أو PDF فقط)",
    "file_too_large": "الحجم يتجاوز 2MB",
    "upload_failed": "تعذر رفع المرفق",
    "col_number": "الرقم",
    "col_subject": "الموضوع",
    "col_company": "الشركة",
    "col_category": "الفئة",
    "col_priority": "الأولوية",
    "col_status": "الحالة",
    "col_actions": "إجراءات",
    "col_created": "أنشئت",
    "tfilter_active": "النشطة",
    "tfilter_all": "الكل",
    "tfilter_open": "مفتوحة",
    "tfilter_in_progress": "قيد المعالجة",
    "tfilter_waiting_customer": "بانتظار العميل",
    "tfilter_resolved": "محلولة",
    "tfilter_closed": "مغلقة",
    "filter_priority_all": "كل الأولويات",
    "filter_category_all": "كل الفئات",
    "priority_low": "منخفضة",
    "priority_normal": "عادية",
    "priority_high": "عالية",
    "priority_urgent": "عاجلة",
    "category_billing": "فوترة واشتراك",
    "category_technical": "مشكلة تقنية",
    "category_inventory": "مخزون",
    "category_account": "حساب",
    "category_feature_request": "اقتراح ميزة",
    "category_other": "أخرى",
    "tstatus_open": "مفتوحة",
    "tstatus_in_progress": "قيد المعالجة",
    "tstatus_waiting_customer": "بانتظار العميل",
    "tstatus_resolved": "محلولة",
    "tstatus_closed": "مغلقة",
    "no_tickets": "لا تذاكر مطابقة",
    "resolution_note": "ملاحظة الحل",
    "resolution_note_ph": "كيف حُلّت المشكلة؟ (يُسجل في سجل التدقيق)",
    "action_start": "بدء المعالجة",
    "action_wait": "بانتظار العميل",
    "action_resolve": "حل التذكرة",
    "action_close": "إغلاق",
    "action_reopen": "إعادة فتح",
    "action_save_note": "حفظ الملاحظة",
    "ticket_updated_toast": "حُدّثت التذكرة",
    "invalid_transition": "انتقال غير صالح لحالة التذكرة",
    "new_conv_btn": "محادثة جديدة",
    "new_conv_title": "محادثة دعم جديدة",
    "new_conv_message": "رسالتك",
    "new_conv_message_ph": "اشرح استفسارك أو مشكلتك…",
    "new_conv_subject": "الموضوع (اختياري)",
    "new_conv_submit": "إرسال",
    "cancel": "إلغاء",
    "new_ticket_btn": "تذكرة جديدة",
    "new_ticket_title": "تذكرة دعم جديدة",
    "new_ticket_subject": "الموضوع",
    "new_ticket_subject_ph": "ملخص المشكلة في سطر",
    "new_ticket_body": "التفاصيل (اختياري)",
    "my_tickets": "تذاكري",
    "ticket_created_toast": "أُنشئت التذكرة",
    "unread_badge": "غير مقروءة",
    "system_closed_by_platform": "أُغلقت المحادثة من فريق الدعم",
    "system_closed_by_pharmacy": "أُغلقت المحادثة من الشركة",
}

EN = {
    "title": "Support",
    "subtitle": "Live chat with the support team and ticket management",
    "tab_chats": "Chats",
    "tab_tickets": "Tickets",
    "live": "Live",
    "polling": "Polling",
    "unread": "Unread",
    "unanswered": "Unanswered",
    "open_tickets": "Open tickets",
    "urgent_tickets": "Urgent tickets",
    "presence_online": "Support is online",
    "presence_offline": "Support is offline — we reply by email when needed",
    "filter_all": "All",
    "filter_unread": "Unread",
    "filter_unanswered": "Unanswered",
    "filter_closed": "Closed",
    "no_conversations": "No matching conversations",
    "pick_conversation": "Pick a conversation from the list",
    "status_closed_conv": "Closed",
    "close_conv": "Close conversation",
    "closed_banner": "This conversation is closed — no new messages",
    "closed_toast": "Conversation closed",
    "placeholder": "Type your message… (Enter to send)",
    "send": "Send",
    "attach": "Attach a file",
    "typing": "The other side is typing…",
    "attachment": "Attachment",
    "load_failed": "Failed to load",
    "send_failed": "Failed to send — try again",
    "bad_mime": "Unsupported file type (images or PDF only)",
    "file_too_large": "File exceeds 2MB",
    "upload_failed": "Attachment upload failed",
    "col_number": "Number",
    "col_subject": "Subject",
    "col_company": "Company",
    "col_category": "Category",
    "col_priority": "Priority",
    "col_status": "Status",
    "col_actions": "Actions",
    "col_created": "Created",
    "tfilter_active": "Active",
    "tfilter_all": "All",
    "tfilter_open": "Open",
    "tfilter_in_progress": "In progress",
    "tfilter_waiting_customer": "Waiting on customer",
    "tfilter_resolved": "Resolved",
    "tfilter_closed": "Closed",
    "filter_priority_all": "All priorities",
    "filter_category_all": "All categories",
    "priority_low": "Low",
    "priority_normal": "Normal",
    "priority_high": "High",
    "priority_urgent": "Urgent",
    "category_billing": "Billing",
    "category_technical": "Technical",
    "category_inventory": "Inventory",
    "category_account": "Account",
    "category_feature_request": "Feature request",
    "category_other": "Other",
    "tstatus_open": "Open",
    "tstatus_in_progress": "In progress",
    "tstatus_waiting_customer": "Waiting on customer",
    "tstatus_resolved": "Resolved",
    "tstatus_closed": "Closed",
    "no_tickets": "No matching tickets",
    "resolution_note": "Resolution note",
    "resolution_note_ph": "How was it resolved? (kept in the audit log)",
    "action_start": "Start working",
    "action_wait": "Wait on customer",
    "action_resolve": "Resolve",
    "action_close": "Close",
    "action_reopen": "Reopen",
    "action_save_note": "Save note",
    "ticket_updated_toast": "Ticket updated",
    "invalid_transition": "Invalid status transition for this ticket",
    "new_conv_btn": "New conversation",
    "new_conv_title": "New support conversation",
    "new_conv_message": "Your message",
    "new_conv_message_ph": "Describe your question or issue…",
    "new_conv_subject": "Subject (optional)",
    "new_conv_submit": "Send",
    "cancel": "Cancel",
    "new_ticket_btn": "New ticket",
    "new_ticket_title": "New support ticket",
    "new_ticket_subject": "Subject",
    "new_ticket_subject_ph": "One-line summary of the issue",
    "new_ticket_body": "Details (optional)",
    "my_tickets": "My tickets",
    "ticket_created_toast": "Ticket created",
    "unread_badge": "Unread",
    "system_closed_by_platform": "Conversation closed by the support team",
    "system_closed_by_pharmacy": "Conversation closed by the company",
}

FR = {
    **EN,
    "title": "Assistance", "subtitle": "Discussion en direct avec l'équipe d'assistance et gestion des tickets",
    "tab_chats": "Discussions", "tab_tickets": "Tickets", "live": "En direct", "polling": "Interrogation",
    "unread": "Non lus", "unanswered": "Sans réponse", "open_tickets": "Tickets ouverts", "urgent_tickets": "Tickets urgents",
    "presence_online": "L'assistance est en ligne", "presence_offline": "Assistance hors ligne — réponse par e-mail si besoin",
    "filter_all": "Tous", "filter_unread": "Non lus", "filter_unanswered": "Sans réponse", "filter_closed": "Fermés",
    "no_conversations": "Aucune discussion", "pick_conversation": "Choisissez une discussion",
    "status_closed_conv": "Fermée", "close_conv": "Fermer la discussion", "closed_banner": "Discussion fermée — aucun nouveau message",
    "closed_toast": "Discussion fermée", "placeholder": "Écrivez votre message… (Entrée pour envoyer)",
    "send": "Envoyer", "attach": "Joindre un fichier", "typing": "En train d'écrire…", "attachment": "Pièce jointe",
    "load_failed": "Échec du chargement", "send_failed": "Échec de l'envoi — réessayez",
    "bad_mime": "Type de fichier non pris en charge (images ou PDF)", "file_too_large": "Fichier > 2 Mo",
    "upload_failed": "Échec du téléversement", "col_number": "Numéro", "col_subject": "Objet", "col_company": "Entreprise",
    "col_category": "Catégorie", "col_priority": "Priorité", "col_status": "Statut", "col_actions": "Actions", "col_created": "Créé",
    "tfilter_active": "Actifs", "tfilter_open": "Ouverts", "tfilter_in_progress": "En cours",
    "tfilter_waiting_customer": "En attente client", "tfilter_resolved": "Résolus", "tfilter_closed": "Fermés",
    "filter_priority_all": "Toutes priorités", "filter_category_all": "Toutes catégories",
    "priority_low": "Basse", "priority_normal": "Normale", "priority_high": "Haute", "priority_urgent": "Urgente",
    "category_billing": "Facturation", "category_technical": "Technique", "category_inventory": "Stock",
    "category_account": "Compte", "category_feature_request": "Suggestion", "category_other": "Autre",
    "tstatus_open": "Ouvert", "tstatus_in_progress": "En cours", "tstatus_waiting_customer": "En attente client",
    "tstatus_resolved": "Résolu", "tstatus_closed": "Fermé", "no_tickets": "Aucun ticket",
    "resolution_note": "Note de résolution", "resolution_note_ph": "Comment a-t-elle été résolue ? (journal d'audit)",
    "action_start": "Prendre en charge", "action_wait": "Attendre le client", "action_resolve": "Résoudre",
    "action_close": "Fermer", "action_reopen": "Réouvrir", "action_save_note": "Enregistrer la note",
    "ticket_updated_toast": "Ticket mis à jour", "invalid_transition": "Transition de statut invalide",
    "new_conv_btn": "Nouvelle discussion", "new_conv_title": "Nouvelle discussion d'assistance", "new_conv_message": "Votre message",
    "new_conv_message_ph": "Décrivez votre question…", "new_conv_subject": "Objet (facultatif)", "new_conv_submit": "Envoyer",
    "cancel": "Annuler", "new_ticket_btn": "Nouveau ticket", "new_ticket_title": "Nouveau ticket d'assistance",
    "new_ticket_subject": "Objet", "new_ticket_subject_ph": "Résumé en une ligne", "new_ticket_body": "Détails (facultatif)",
    "my_tickets": "Mes tickets", "ticket_created_toast": "Ticket créé", "unread_badge": "Non lus",
    "system_closed_by_platform": "Discussion fermée par l'assistance", "system_closed_by_pharmacy": "Discussion fermée par l'entreprise",
}

ES = {
    **EN,
    "title": "Soporte", "subtitle": "Chat en vivo con el equipo de soporte y gestión de tickets",
    "tab_chats": "Chats", "tab_tickets": "Tickets", "live": "En vivo", "polling": "Sondeo",
    "unread": "No leídos", "unanswered": "Sin respuesta", "open_tickets": "Tickets abiertos", "urgent_tickets": "Tickets urgentes",
    "presence_online": "Soporte en línea", "presence_offline": "Soporte fuera de línea — respondemos por correo si hace falta",
    "filter_all": "Todos", "filter_unread": "No leídos", "filter_unanswered": "Sin respuesta", "filter_closed": "Cerrados",
    "no_conversations": "Sin conversaciones", "pick_conversation": "Elige una conversación",
    "status_closed_conv": "Cerrada", "close_conv": "Cerrar conversación", "closed_banner": "Conversación cerrada — sin mensajes nuevos",
    "closed_toast": "Conversación cerrada", "placeholder": "Escribe tu mensaje… (Enter para enviar)",
    "send": "Enviar", "attach": "Adjuntar archivo", "typing": "El otro está escribiendo…", "attachment": "Adjunto",
    "load_failed": "Error al cargar", "send_failed": "Error al enviar — reintenta",
    "bad_mime": "Tipo de archivo no admitido (imágenes o PDF)", "file_too_large": "Supera 2 MB",
    "upload_failed": "Error al subir el adjunto", "col_number": "Número", "col_subject": "Asunto", "col_company": "Empresa",
    "col_category": "Categoría", "col_priority": "Prioridad", "col_status": "Estado", "col_actions": "Acciones", "col_created": "Creado",
    "tfilter_active": "Activos", "tfilter_open": "Abiertos", "tfilter_in_progress": "En progreso",
    "tfilter_waiting_customer": "Esperando cliente", "tfilter_resolved": "Resueltos", "tfilter_closed": "Cerrados",
    "filter_priority_all": "Todas las prioridades", "filter_category_all": "Todas las categorías",
    "priority_low": "Baja", "priority_normal": "Normal", "priority_high": "Alta", "priority_urgent": "Urgente",
    "category_billing": "Facturación", "category_technical": "Técnico", "category_inventory": "Inventario",
    "category_account": "Cuenta", "category_feature_request": "Sugerencia", "category_other": "Otro",
    "tstatus_open": "Abierto", "tstatus_in_progress": "En progreso", "tstatus_waiting_customer": "Esperando cliente",
    "tstatus_resolved": "Resuelto", "tstatus_closed": "Cerrado", "no_tickets": "Sin tickets",
    "resolution_note": "Nota de resolución", "resolution_note_ph": "¿Cómo se resolvió? (registro de auditoría)",
    "action_start": "Empezar", "action_wait": "Esperar cliente", "action_resolve": "Resolver",
    "action_close": "Cerrar", "action_reopen": "Reabrir", "action_save_note": "Guardar nota",
    "ticket_updated_toast": "Ticket actualizado", "invalid_transition": "Transición de estado inválida",
    "new_conv_btn": "Nueva conversación", "new_conv_title": "Nueva conversación de soporte", "new_conv_message": "Tu mensaje",
    "new_conv_message_ph": "Describe tu consulta…", "new_conv_subject": "Asunto (opcional)", "new_conv_submit": "Enviar",
    "cancel": "Cancelar", "new_ticket_btn": "Nuevo ticket", "new_ticket_title": "Nuevo ticket de soporte",
    "new_ticket_subject": "Asunto", "new_ticket_subject_ph": "Resumen en una línea", "new_ticket_body": "Detalles (opcional)",
    "my_tickets": "Mis tickets", "ticket_created_toast": "Ticket creado", "unread_badge": "No leídos",
    "system_closed_by_platform": "Conversación cerrada por soporte", "system_closed_by_pharmacy": "Conversación cerrada por la empresa",
}

TR = {
    **EN,
    "title": "Destek", "subtitle": "Destek ekibiyle canlı sohbet ve talep yönetimi",
    "tab_chats": "Sohbetler", "tab_tickets": "Talepler", "live": "Canlı", "polling": "Sorgulama",
    "unread": "Okunmamış", "unanswered": "Yanıtsız", "open_tickets": "Açık talepler", "urgent_tickets": "Acil talepler",
    "presence_online": "Destek çevrimiçi", "presence_offline": "Destek çevrimdışı — gerektiğinde e-postayla yanıtlarız",
    "filter_all": "Tümü", "filter_unread": "Okunmamış", "filter_unanswered": "Yanıtsız", "filter_closed": "Kapalı",
    "no_conversations": "Sohbet yok", "pick_conversation": "Listeden bir sohbet seçin",
    "status_closed_conv": "Kapalı", "close_conv": "Sohbeti kapat", "closed_banner": "Sohbet kapandı — yeni mesaj yok",
    "closed_toast": "Sohbet kapatıldı", "placeholder": "Mesajınızı yazın… (göndermek için Enter)",
    "send": "Gönder", "attach": "Dosya ekle", "typing": "Karşı taraf yazıyor…", "attachment": "Ek",
    "load_failed": "Yükleme başarısız", "send_failed": "Gönderme başarısız — tekrar deneyin",
    "bad_mime": "Desteklenmeyen dosya türü (yalnızca görsel/PDF)", "file_too_large": "2MB sınırı aşıldı",
    "upload_failed": "Ek yükleme başarısız", "col_number": "Numara", "col_subject": "Konu", "col_company": "Şirket",
    "col_category": "Kategori", "col_priority": "Öncelik", "col_status": "Durum", "col_actions": "İşlemler", "col_created": "Oluşturuldu",
    "tfilter_active": "Aktif", "tfilter_open": "Açık", "tfilter_in_progress": "İşlemde",
    "tfilter_waiting_customer": "Müşteri bekleniyor", "tfilter_resolved": "Çözüldü", "tfilter_closed": "Kapalı",
    "filter_priority_all": "Tüm öncelikler", "filter_category_all": "Tüm kategoriler",
    "priority_low": "Düşük", "priority_normal": "Normal", "priority_high": "Yüksek", "priority_urgent": "Acil",
    "category_billing": "Faturalama", "category_technical": "Teknik", "category_inventory": "Stok",
    "category_account": "Hesap", "category_feature_request": "Özellik talebi", "category_other": "Diğer",
    "tstatus_open": "Açık", "tstatus_in_progress": "İşlemde", "tstatus_waiting_customer": "Müşteri bekleniyor",
    "tstatus_resolved": "Çözüldü", "tstatus_closed": "Kapalı", "no_tickets": "Talep yok",
    "resolution_note": "Çözüm notu", "resolution_note_ph": "Nasıl çözüldü? (denetim kaydında saklanır)",
    "action_start": "İşlemeye başla", "action_wait": "Müşteriyi bekle", "action_resolve": "Çöz",
    "action_close": "Kapat", "action_reopen": "Yeniden aç", "action_save_note": "Notu kaydet",
    "ticket_updated_toast": "Talep güncellendi", "invalid_transition": "Geçersiz durum geçişi",
    "new_conv_btn": "Yeni sohbet", "new_conv_title": "Yeni destek sohbeti", "new_conv_message": "Mesajınız",
    "new_conv_message_ph": "Sorununuzu açıklayın…", "new_conv_subject": "Konu (isteğe bağlı)", "new_conv_submit": "Gönder",
    "cancel": "İptal", "new_ticket_btn": "Yeni talep", "new_ticket_title": "Yeni destek talebi",
    "new_ticket_subject": "Konu", "new_ticket_subject_ph": "Tek satırlık özet", "new_ticket_body": "Ayrıntılar (isteğe bağlı)",
    "my_tickets": "Taleplerim", "ticket_created_toast": "Talep oluşturuldu", "unread_badge": "Okunmamış",
    "system_closed_by_platform": "Sohbet destek ekibi tarafından kapatıldı", "system_closed_by_pharmacy": "Sohbet şirket tarafından kapatıldı",
}

ZH = {
    **EN,
    "title": "客服支持", "subtitle": "与支持团队实时聊天并管理工单",
    "tab_chats": "聊天", "tab_tickets": "工单", "live": "实时", "polling": "轮询",
    "unread": "未读", "unanswered": "未回复", "open_tickets": "进行中的工单", "urgent_tickets": "紧急工单",
    "presence_online": "客服在线", "presence_offline": "客服离线 — 必要时会通过邮件回复",
    "filter_all": "全部", "filter_unread": "未读", "filter_unanswered": "未回复", "filter_closed": "已关闭",
    "no_conversations": "没有会话", "pick_conversation": "请从列表中选择一个会话",
    "status_closed_conv": "已关闭", "close_conv": "关闭会话", "closed_banner": "会话已关闭 — 无法发送新消息",
    "closed_toast": "会话已关闭", "placeholder": "输入消息…（回车发送）",
    "send": "发送", "attach": "附件", "typing": "对方正在输入…", "attachment": "附件",
    "load_failed": "加载失败", "send_failed": "发送失败 — 请重试",
    "bad_mime": "不支持的文件类型（仅图片或 PDF）", "file_too_large": "超过 2MB",
    "upload_failed": "附件上传失败", "col_number": "编号", "col_subject": "主题", "col_company": "公司",
    "col_category": "分类", "col_priority": "优先级", "col_status": "状态", "col_actions": "操作", "col_created": "创建时间",
    "tfilter_active": "进行中", "tfilter_open": "打开", "tfilter_in_progress": "处理中",
    "tfilter_waiting_customer": "等待客户", "tfilter_resolved": "已解决", "tfilter_closed": "已关闭",
    "filter_priority_all": "全部优先级", "filter_category_all": "全部分类",
    "priority_low": "低", "priority_normal": "普通", "priority_high": "高", "priority_urgent": "紧急",
    "category_billing": "账务", "category_technical": "技术", "category_inventory": "库存",
    "category_account": "账户", "category_feature_request": "功能建议", "category_other": "其他",
    "tstatus_open": "打开", "tstatus_in_progress": "处理中", "tstatus_waiting_customer": "等待客户",
    "tstatus_resolved": "已解决", "tstatus_closed": "已关闭", "no_tickets": "没有工单",
    "resolution_note": "解决方案备注", "resolution_note_ph": "如何解决的？（记录在审计日志中）",
    "action_start": "开始处理", "action_wait": "等待客户", "action_resolve": "解决",
    "action_close": "关闭", "action_reopen": "重新打开", "action_save_note": "保存备注",
    "ticket_updated_toast": "工单已更新", "invalid_transition": "无效的状态变更",
    "new_conv_btn": "新会话", "new_conv_title": "新的客服会话", "new_conv_message": "您的消息",
    "new_conv_message_ph": "描述您的问题…", "new_conv_subject": "主题（可选）", "new_conv_submit": "发送",
    "cancel": "取消", "new_ticket_btn": "新工单", "new_ticket_title": "新的支持工单",
    "new_ticket_subject": "主题", "new_ticket_subject_ph": "一句话概述", "new_ticket_body": "详情（可选）",
    "my_tickets": "我的工单", "ticket_created_toast": "工单已创建", "unread_badge": "未读",
    "system_closed_by_platform": "会话已由客服团队关闭", "system_closed_by_pharmacy": "会话已由公司关闭",
}

HI = {
    **EN,
    "title": "सहायता", "subtitle": "सहायता टीम के साथ लाइव चैट और टिकट प्रबंधन",
    "tab_chats": "चैट", "tab_tickets": "टिकट", "live": "लाइव", "polling": "पोलिंग",
    "unread": "अपठित", "unanswered": "अनुत्तरित", "open_tickets": "खुले टिकट", "urgent_tickets": "अत्यावश्यक टिकट",
    "presence_online": "सहायता ऑनलाइन है", "presence_offline": "सहायता ऑफ़लाइन है — आवश्यकता पर ईमेल से उत्तर देंगे",
    "filter_all": "सभी", "filter_unread": "अपठित", "filter_unanswered": "अनुत्तरित", "filter_closed": "बंद",
    "no_conversations": "कोई बातचीत नहीं", "pick_conversation": "सूची से एक बातचीत चुनें",
    "status_closed_conv": "बंद", "close_conv": "बातचीत बंद करें", "closed_banner": "यह बातचीत बंद है — नए संदेश नहीं",
    "closed_toast": "बातचीत बंद हुई", "placeholder": "अपना संदेश लिखें… (भेजने के लिए Enter)",
    "send": "भेजें", "attach": "फ़ाइल जोड़ें", "typing": "सामने वाला टाइप कर रहा है…", "attachment": "अनुलग्नक",
    "load_failed": "लोड विफल", "send_failed": "भेजना विफल — पुनः प्रयास करें",
    "bad_mime": "फ़ाइल प्रकार समर्थित नहीं (केवल चित्र/PDF)", "file_too_large": "2MB से बड़ी फ़ाइल",
    "upload_failed": "अनुलग्नक अपलोड विफल", "col_number": "नंबर", "col_subject": "विषय", "col_company": "कंपनी",
    "col_category": "श्रेणी", "col_priority": "प्राथमिकता", "col_status": "स्थिति", "col_actions": "क्रियाएँ", "col_created": "बनाया गया",
    "tfilter_active": "सक्रिय", "tfilter_open": "खुले", "tfilter_in_progress": "प्रगति में",
    "tfilter_waiting_customer": "ग्राहक की प्रतीक्षा", "tfilter_resolved": "हल किए", "tfilter_closed": "बंद",
    "filter_priority_all": "सभी प्राथमिकताएँ", "filter_category_all": "सभी श्रेणियाँ",
    "priority_low": "निम्न", "priority_normal": "सामान्य", "priority_high": "उच्च", "priority_urgent": "अत्यावश्यक",
    "category_billing": "बिलिंग", "category_technical": "तकनीकी", "category_inventory": "इन्वेंटरी",
    "category_account": "खाता", "category_feature_request": "सुविधा सुझाव", "category_other": "अन्य",
    "tstatus_open": "खुला", "tstatus_in_progress": "प्रगति में", "tstatus_waiting_customer": "ग्राहक की प्रतीक्षा",
    "tstatus_resolved": "हल किया", "tstatus_closed": "बंद", "no_tickets": "कोई टिकट नहीं",
    "resolution_note": "समाधान नोट", "resolution_note_ph": "कैसे हल हुआ? (ऑडिट लॉग में सुरक्षित)",
    "action_start": "कार्य शुरू करें", "action_wait": "ग्राहक की प्रतीक्षा करें", "action_resolve": "हल करें",
    "action_close": "बंद करें", "action_reopen": "पुनः खोलें", "action_save_note": "नोट सहेजें",
    "ticket_updated_toast": "टिकट अपडेट हुआ", "invalid_transition": "स्थिति परिवर्तन अमान्य",
    "new_conv_btn": "नई बातचीत", "new_conv_title": "नई सहायता बातचीत", "new_conv_message": "आपका संदेश",
    "new_conv_message_ph": "अपनी समस्या बताएं…", "new_conv_subject": "विषय (वैकल्पिक)", "new_conv_submit": "भेजें",
    "cancel": "रद्द करें", "new_ticket_btn": "नया टिकट", "new_ticket_title": "नया सहायता टिकट",
    "new_ticket_subject": "विषय", "new_ticket_subject_ph": "एक पंक्ति में सारांश", "new_ticket_body": "विवरण (वैकल्पिक)",
    "my_tickets": "मेरे टिकट", "ticket_created_toast": "टिकट बनाया गया", "unread_badge": "अपठित",
    "system_closed_by_platform": "सहायता टीम ने बातचीत बंद की", "system_closed_by_pharmacy": "कंपनी ने बातचीत बंद की",
}

UR = {
    **EN,
    "title": "سہارا", "subtitle": "سہارا ٹیم کے ساتھ براہِ راست گفتگو اور ٹکٹ کا انتظام",
    "tab_chats": "گفتگوئیں", "tab_tickets": "ٹکٹ", "live": "براہِ راست", "polling": "معائنہ",
    "unread": "غیر مطالعہ شدہ", "unanswered": "بغیر جواب", "open_tickets": "کھلے ٹکٹ", "urgent_tickets": "اضطراری ٹکٹ",
    "presence_online": "سہارا ٹیم آن لائن ہے", "presence_offline": "سہارا ٹیم آف لائن ہے — ضرورت پر ای میل سے جواب دیں گے",
    "filter_all": "سب", "filter_unread": "غیر مطالعہ شدہ", "filter_unanswered": "بغیر جواب", "filter_closed": "بند",
    "no_conversations": "کوئی گفتگو نہیں", "pick_conversation": "فہرست سے ایک گفتگو منتخب کریں",
    "status_closed_conv": "بند", "close_conv": "گفتگو بند کریں", "closed_banner": "یہ گفتگو بند ہے — نئے پیغامات ممکن نہیں",
    "closed_toast": "گفتگو بند ہو گئی", "placeholder": "اپنا پیغام لکھیں… (بھیجنے کے لیے Enter)",
    "send": "بھیجیں", "attach": "فائل منسلک کریں", "typing": "سامنے والا لکھ رہا ہے…", "attachment": "منسلکہ",
    "load_failed": "لوڈ ناکام", "send_failed": "بھیجنا ناکام — دوبارہ کوشش کریں",
    "bad_mime": "فائل کی قسم معاون نہیں (صرف تصاویر/PDF)", "file_too_large": "2MB سے زیادہ",
    "upload_failed": "منسلکہ اپلوڈ ناکام", "col_number": "نمبر", "col_subject": "موضوع", "col_company": "کمپنی",
    "col_category": "قسم", "col_priority": "ترجیح", "col_status": "حالت", "col_actions": "-actions", "col_created": "تخلیق",
    "tfilter_active": "فعال", "tfilter_open": "کھلے", "tfilter_in_progress": "جاری",
    "tfilter_waiting_customer": "گاہک کا انتظار", "tfilter_resolved": "حل شدہ", "tfilter_closed": "بند",
    "filter_priority_all": "سب ترجیحات", "filter_category_all": "سب اقسام",
    "priority_low": "کم", "priority_normal": "عام", "priority_high": "زیادہ", "priority_urgent": "اضطراری",
    "category_billing": "بلنگ", "category_technical": "تکنیکی", "category_inventory": "اسٹاک",
    "category_account": "اکاؤنٹ", "category_feature_request": "فیچر تجویز", "category_other": "دیگر",
    "tstatus_open": "کھلا", "tstatus_in_progress": "جاری", "tstatus_waiting_customer": "گاہک کا انتظار",
    "tstatus_resolved": "حل شدہ", "tstatus_closed": "بند", "no_tickets": "کوئی ٹکٹ نہیں",
    "resolution_note": "حل کا نوٹ", "resolution_note_ph": "کیسے حل ہوا؟ (آڈٹ لاگ میں محفوظ)",
    "action_start": "کام شروع کریں", "action_wait": "گاہک کا انتظار کریں", "action_resolve": "حل کریں",
    "action_close": "بند کریں", "action_reopen": "دوبارہ کھولیں", "action_save_note": "نوٹ محفوظ کریں",
    "ticket_updated_toast": "ٹکٹ اپڈیٹ ہوا", "invalid_transition": "حالت کی تبدیلی غلط ہے",
    "new_conv_btn": "نئی گفتگو", "new_conv_title": "نئی سہارا گفتگو", "new_conv_message": "آپ کا پیغام",
    "new_conv_message_ph": "اپنا مسئلہ بیان کریں…", "new_conv_subject": "موضوع (اختیاری)", "new_conv_submit": "بھیجیں",
    "cancel": "منسوخ", "new_ticket_btn": "نیا ٹکٹ", "new_ticket_title": "نیا سہارا ٹکٹ",
    "new_ticket_subject": "موضوع", "new_ticket_subject_ph": "ایک سطر میں خلاصہ", "new_ticket_body": "تفصیل (اختیاری)",
    "my_tickets": "میرے ٹکٹ", "ticket_created_toast": "ٹکٹ بنا دیا گیا", "unread_badge": "غیر مطالعہ شدہ",
    "system_closed_by_platform": "سہارا ٹیم نے گفتگو بند کی", "system_closed_by_pharmacy": "کمپنی نے گفتگو بند کی",
}
UR["col_actions"] = "کارروائیاں"  # fix accidental hyphen

CATALOGS = {"ar": AR, "en": EN, "fr": FR, "es": ES, "tr": TR, "zh": ZH, "hi": HI, "ur": UR}

NAV_WORD = {"ar": "الدعم", "en": "Support", "fr": "Assistance", "es": "Soporte", "tr": "Destek", "zh": "客服", "hi": "सहायता", "ur": "سہارا"}

APPS = ["admin-dashboard", "pharmacy-app"]

for app in APPS:
    for locale, catalog in CATALOGS.items():
        base = f"{ROOT}/{app}/src/i18n/messages/{locale}"
        os.makedirs(base, exist_ok=True)
        path = f"{base}/support.json"
        if not os.path.exists(path):
            with open(path, "w", encoding="utf-8") as f:
                json.dump(catalog, f, ensure_ascii=False, indent=2)
                f.write("\n")
        # nav key
        nav_path = f"{base}/nav.json"
        with open(nav_path, encoding="utf-8") as f:
            nav = json.load(f)
        if "support" not in nav:
            nav["support"] = NAV_WORD[locale]
            with open(nav_path, "w", encoding="utf-8") as f:
                json.dump(nav, f, ensure_ascii=False, indent=2)
                f.write("\n")
    print(app, "messages written")

# Register the namespace in messages/index.ts for both apps (idempotent).
for app in APPS:
    idx_path = f"{ROOT}/{app}/src/i18n/messages/index.ts"
    with open(idx_path, encoding="utf-8") as f:
        content = f.read()
    if "messages/ar/support.json" in content:
        print(app, "index.ts already registers support")
        continue
    for locale in CATALOGS:
        content = content.replace(
            f"import urCommon from './ur/common.json'",
            f"import urCommon from './ur/common.json'",
            1,
        )
    # insert imports right after each locale's last existing import line
    lines = content.split("\n")
    out = []
    for line in lines:
        out.append(line)
        for locale in CATALOGS:
            marker = f"import {locale}Libraries from './{locale}/libraries.json'"
            if line == marker:
                out.append(f"import {locale}Support from './{locale}/support.json'")
    content = "\n".join(out)
    # add to catalogs maps: after "libraries: xxLibraries," lines
    for locale in CATALOGS:
        content = content.replace(
            f"    libraries: {locale}Libraries,",
            f"    libraries: {locale}Libraries,\n    support: {locale}Support,",
        )
    with open(idx_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(app, "index.ts patched")

# Key parity check
base_keys = set(AR.keys())
for locale, catalog in CATALOGS.items():
    keys = set(catalog.keys())
    missing = base_keys - keys
    extra = keys - base_keys
    status = "OK" if not missing else f"MISSING {sorted(missing)[:5]}"
    print(f"parity {locale}: {status} (extra: {len(extra)})")
