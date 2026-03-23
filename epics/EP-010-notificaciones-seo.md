# [MKT-EP-010] Notificaciones, Comunicacion & SEO

**Sprint**: 7-8
**Priority**: Medium
**Epic Owner**: Tech Lead - SVC-NTF / SVC-CHT / SVC-SEO
**Stakeholders**: Product, Marketing, Frontend Lead, DevOps
**Estimated Effort**: 52 story points

---

## Epic Overview

This epic delivers the communication and discoverability layer of the Vehicle Marketplace. It covers multi-channel notifications (in-app, email, push, WhatsApp, SMS), real-time chat between buyers, sellers, and support, SEO backend for sitemaps and structured data, and Angular Universal SSR for search engine optimization. Together, these capabilities ensure users are informed, can communicate efficiently, and that the marketplace is highly discoverable by search engines.

### Business Goals
- Keep users engaged with timely, relevant notifications across their preferred channels
- Enable direct buyer-seller communication to reduce friction in the purchase process
- Maximize organic search traffic through SEO best practices and structured data
- Achieve top Core Web Vitals scores for search ranking advantage
- Support PWA capabilities for mobile-first users

### Architecture Context
- **Notification Service**: SVC-NTF (:5017)
- **Chat Service**: SVC-CHT (:5018)
- **SEO Service**: SVC-SEO (:5022)
- **Worker**: WRK-NTF (async notification dispatch)
- **Message Broker**: SQS for async notification delivery
- **Real-time**: WebSocket via SVC-NTF (notifications) and SVC-CHT (messaging)
- **Email**: AWS SES with HTML templates
- **Push**: Firebase Cloud Messaging (FCM)
- **WhatsApp**: WhatsApp Business API
- **SMS**: AWS SNS for SMS fallback
- **SSR**: Angular Universal with Node.js

---

## User Stories

---

### US-1: [MKT-BE-028][SVC-NTF] Servicio de Notificaciones Multicanal

**Description**:
Implement a comprehensive notification service that dispatches messages across multiple channels: in-app via WebSocket, email via AWS SES with HTML templates, push notifications via Firebase Cloud Messaging (FCM), WhatsApp messages via WhatsApp Business API, and SMS as a fallback via AWS SNS. The service respects user channel preferences, dispatches asynchronously via SQS, supports templated messages with variable interpolation, and tracks delivery status per channel.

**Microservice**: SVC-NTF (:5017)
**Layer**: API + APP + DOM + INF
**Worker**: WRK-NTF (async dispatch)

#### Technical Context

**Endpoints**:
```
POST   /api/v1/notifications/send                # Send a notification (internal, service-to-service)
GET    /api/v1/notifications                      # Get user notifications (paginated)
PATCH  /api/v1/notifications/{id}/read            # Mark as read
PATCH  /api/v1/notifications/read-all             # Mark all as read
GET    /api/v1/notifications/unread-count         # Get unread count
GET    /api/v1/notifications/preferences          # Get user channel preferences
PUT    /api/v1/notifications/preferences          # Update channel preferences
WSS    /api/v1/notifications/ws                   # WebSocket for real-time in-app notifications
```

**Send Notification Request (Service-to-Service)**:
```json
{
  "recipient_user_id": "usr_abc123",
  "notification_type": "financing_offer_received",
  "priority": "high",
  "channels": null,
  "data": {
    "institution_name": "Banco Nacional",
    "monthly_payment": 11890.50,
    "annual_rate": 11.9,
    "application_id": "app_x9y8z7",
    "vehicle_title": "Toyota Camry 2024 SE"
  },
  "action_url": "/financing/applications/app_x9y8z7",
  "idempotency_key": "fin_offer_app_x9y8z7_inst_001"
}
```

**Notification Response (User-facing)**:
```json
{
  "data": [
    {
      "notification_id": "ntf_001",
      "type": "financing_offer_received",
      "title": "Nueva oferta de credito",
      "body": "Banco Nacional te ha aprobado un credito con mensualidad de $11,890.50",
      "icon": "credit_card",
      "action_url": "/financing/applications/app_x9y8z7",
      "is_read": false,
      "channels_delivered": ["in_app", "email", "push"],
      "created_at": "2026-03-23T10:12:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 45
  },
  "unread_count": 12
}
```

**User Preferences**:
```json
{
  "user_id": "usr_abc123",
  "channels": {
    "in_app": {
      "enabled": true
    },
    "email": {
      "enabled": true,
      "address": "juan@example.com"
    },
    "push": {
      "enabled": true,
      "fcm_tokens": ["token1", "token2"]
    },
    "whatsapp": {
      "enabled": true,
      "phone": "+5215512345678"
    },
    "sms": {
      "enabled": false,
      "phone": "+5215512345678"
    }
  },
  "quiet_hours": {
    "enabled": true,
    "start": "22:00",
    "end": "08:00",
    "timezone": "America/Mexico_City"
  },
  "notification_types": {
    "financing_updates": true,
    "insurance_updates": true,
    "chat_messages": true,
    "marketing_promotions": false,
    "system_alerts": true,
    "vehicle_price_changes": true
  }
}
```

**Data Model**:
```
Notification (DOM)
  - notification_id: UUID (PK)
  - recipient_user_id: UUID (FK, indexed)
  - notification_type: String(50)
  - priority: Enum(LOW, NORMAL, HIGH, URGENT)
  - title: String(200)
  - body: Text
  - icon: String(50)
  - action_url: String(255)
  - data: JSONB
  - is_read: Boolean default false
  - read_at: DateTime nullable
  - created_at: DateTime (indexed)
  - expires_at: DateTime nullable

NotificationDelivery (DOM)
  - delivery_id: UUID (PK)
  - notification_id: UUID (FK)
  - channel: Enum(IN_APP, EMAIL, PUSH, WHATSAPP, SMS)
  - status: Enum(QUEUED, SENT, DELIVERED, FAILED, BOUNCED)
  - external_id: String(100) nullable
  - sent_at: DateTime nullable
  - delivered_at: DateTime nullable
  - failed_at: DateTime nullable
  - error_message: Text nullable
  - retry_count: Integer default 0
  - created_at: DateTime

NotificationTemplate (DOM)
  - template_id: UUID (PK)
  - notification_type: String(50) UNIQUE
  - channel: Enum(IN_APP, EMAIL, PUSH, WHATSAPP, SMS)
  - title_template: String(200)
  - body_template: Text
  - html_template: Text nullable (for email)
  - variables: JSONB
  - is_active: Boolean default true
  - created_at: DateTime
  - updated_at: DateTime

UserNotificationPreference (DOM)
  - preference_id: UUID (PK)
  - user_id: UUID (FK, UNIQUE)
  - channel_preferences: JSONB
  - quiet_hours: JSONB
  - type_preferences: JSONB
  - updated_at: DateTime

FcmToken (INF)
  - token_id: UUID (PK)
  - user_id: UUID (FK)
  - token: String(255)
  - device_type: Enum(ANDROID, IOS, WEB)
  - device_name: String(100)
  - is_active: Boolean default true
  - last_used_at: DateTime
  - created_at: DateTime
```

**Component Structure**:
```
svc-ntf/
  domain/
    models/notification.py
    models/notification_delivery.py
    models/notification_template.py
    models/user_notification_preference.py
    services/notification_service.py
    services/template_renderer.py
    services/channel_router.py
    ports/notification_channel_port.py
  application/
    use_cases/send_notification_use_case.py
    use_cases/get_user_notifications_use_case.py
    use_cases/mark_read_use_case.py
    use_cases/update_preferences_use_case.py
    dto/send_notification_dto.py
    dto/notification_response_dto.py
    validators/notification_validator.py
  infrastructure/
    channels/
      in_app_channel.py
      email_channel.py
      push_channel.py
      whatsapp_channel.py
      sms_channel.py
    templates/
      email_templates/
        financing_offer.html
        insurance_quote.html
        transaction_confirmation.html
        welcome.html
      whatsapp_templates/
        financing_offer.json
    messaging/
      sqs_publisher.py
    websocket/
      notification_ws_handler.py
      ws_connection_manager.py
    repositories/
      notification_repository.py
      delivery_repository.py
      template_repository.py
      preference_repository.py
    external/
      ses_client.py
      fcm_client.py
      whatsapp_client.py
      sns_sms_client.py
  api/
    routes/notification_routes.py
    routes/preference_routes.py
    schemas/notification_schema.py
  config/
    notification_config.py

wrk-ntf/
  consumers/
    notification_consumer.py
  dispatchers/
    channel_dispatcher.py
  config/
    worker_config.py
```

#### Acceptance Criteria

1. **AC-01**: POST /api/v1/notifications/send (internal) accepts recipient_user_id, notification_type, priority, data, and optional channels override; creates a Notification record and publishes dispatch messages to SQS; returns 202 Accepted.
2. **AC-02**: Channel routing: if channels is null in the request, the system consults the user's NotificationPreference to determine which channels are enabled for the given notification_type; if channels are specified explicitly, those are used regardless of preferences (for system-critical notifications).
3. **AC-03**: Template rendering: each notification_type has templates per channel; the TemplateRenderer interpolates variables from the data field into title_template and body_template (using Jinja2 syntax {{ variable }}); missing variables render as empty string with a warning log.
4. **AC-04**: Email channel: WRK-NTF renders the HTML email template with data variables, sends via AWS SES, tracks delivery status via SES webhooks (delivery, bounce, complaint); emails include unsubscribe link in footer compliant with CAN-SPAM.
5. **AC-05**: Push channel: WRK-NTF sends push notification via FCM to all active FcmTokens for the user; payload includes title, body, icon, action_url, and data for client-side handling; invalid tokens (FCM returns NotRegistered) are deactivated automatically.
6. **AC-06**: WhatsApp channel: WRK-NTF sends message via WhatsApp Business API using pre-approved message templates; template variables are mapped from notification data; messages sent only to users who have opted in and have a verified WhatsApp number.
7. **AC-07**: SMS channel: WRK-NTF sends SMS via AWS SNS as fallback when other channels fail or for URGENT priority; SMS is limited to 160 characters using a text-only template; SMS sending respects a daily limit of 5 SMS per user to avoid spam.
8. **AC-08**: In-app channel: notification is stored in the database and pushed to the connected WebSocket client immediately; if the user is not connected, the notification is stored and delivered on next connection or when GET /notifications is called.
9. **AC-09**: Quiet hours: notifications with priority LOW or NORMAL are queued and delivered after quiet_hours.end; HIGH and URGENT priority notifications bypass quiet hours; queued notifications are processed by WRK-NTF at the start of the next active window.
10. **AC-10**: Idempotency: the idempotency_key in the send request prevents duplicate notifications; if a notification with the same key was sent in the last 24 hours, the request is silently accepted (200) without creating a duplicate.
11. **AC-11**: GET /api/v1/notifications returns paginated notifications for the authenticated user, sorted by created_at descending; supports filter by type, is_read, and date range; includes unread_count in the response.
12. **AC-12**: PATCH /api/v1/notifications/{id}/read marks a single notification as read with read_at timestamp; PATCH /notifications/read-all marks all unread notifications as read; GET /notifications/unread-count returns the current count (cached in Redis, invalidated on new notification or read action).
13. **AC-13**: WebSocket /api/v1/notifications/ws pushes new notifications in real-time; connection requires valid JWT; reconnection replays missed notifications since last_seen_id; heartbeat ping every 30 seconds.
14. **AC-14**: PUT /api/v1/notifications/preferences allows users to enable/disable channels, set quiet hours (start time, end time, timezone), and opt in/out of notification types; preferences are persisted and take effect immediately.

#### Definition of Done
- Multi-channel notification service with SQS dispatch
- Email (SES), Push (FCM), WhatsApp, SMS (SNS) integrations
- In-app WebSocket delivery
- Template system with per-channel templates
- User preferences with quiet hours
- Idempotency enforcement
- Unit tests >= 95% coverage
- Integration tests with localstack (SQS, SES, SNS)
- End-to-end test: trigger notification -> verify delivery on 3+ channels
- Code reviewed and merged to develop

#### Technical Notes
- Use Jinja2 for template rendering (consistent with Flask)
- SES requires verified sender domain and email addresses
- FCM requires Firebase project configuration and server key
- WhatsApp Business API requires Meta Business verification and template approval (24-48h)
- SMS via SNS: use Transactional SMS type for reliability; monitor spend limits
- WebSocket connections should use Redis Pub/Sub for multi-instance broadcasting
- Consider using Amazon Pinpoint as a unified notification orchestrator in the future

#### Dependencies
- AWS SES for email delivery
- Firebase Cloud Messaging for push notifications
- WhatsApp Business API account
- AWS SNS for SMS
- AWS SQS for async dispatch
- Redis for WebSocket broadcasting and unread count cache

---

### US-2: [MKT-BE-029][SVC-CHT] Chat en Tiempo Real WebSocket

**Description**:
Implement a real-time chat service enabling messaging between buyers and sellers, and between buyers and customer support. The service uses WebSocket for real-time message delivery, maintains conversation history in PostgreSQL, supports file/image attachments stored in S3, and provides typing indicators and read receipts.

**Microservice**: SVC-CHT (:5018)
**Layer**: API + APP + DOM + INF

#### Technical Context

**Endpoints**:
```
WSS    /api/v1/chat/ws                           # WebSocket for real-time messaging
GET    /api/v1/chat/conversations                 # List user conversations
GET    /api/v1/chat/conversations/{id}            # Get conversation detail
GET    /api/v1/chat/conversations/{id}/messages   # Get message history (paginated)
POST   /api/v1/chat/conversations                 # Start new conversation
POST   /api/v1/chat/conversations/{id}/messages   # Send message (REST fallback)
POST   /api/v1/chat/conversations/{id}/attachments # Upload file attachment
```

**WebSocket Message Types**:

Client -> Server:
```json
{
  "type": "message",
  "conversation_id": "conv_001",
  "content": "Hola, me interesa el Toyota Camry. Esta disponible?",
  "attachment_ids": []
}
```
```json
{
  "type": "typing_start",
  "conversation_id": "conv_001"
}
```
```json
{
  "type": "typing_stop",
  "conversation_id": "conv_001"
}
```
```json
{
  "type": "read_receipt",
  "conversation_id": "conv_001",
  "last_read_message_id": "msg_005"
}
```

Server -> Client:
```json
{
  "type": "new_message",
  "conversation_id": "conv_001",
  "message": {
    "message_id": "msg_006",
    "sender_id": "usr_seller01",
    "sender_name": "AutoMax Motors",
    "sender_avatar_url": "/avatars/automax.jpg",
    "content": "Si, esta disponible! Puedo agendar una cita para verlo.",
    "attachments": [],
    "sent_at": "2026-03-23T10:15:00Z"
  }
}
```
```json
{
  "type": "typing_indicator",
  "conversation_id": "conv_001",
  "user_id": "usr_seller01",
  "user_name": "AutoMax Motors",
  "is_typing": true
}
```
```json
{
  "type": "read_receipt",
  "conversation_id": "conv_001",
  "reader_id": "usr_seller01",
  "last_read_message_id": "msg_005"
}
```

**Conversations List Response**:
```json
{
  "data": [
    {
      "conversation_id": "conv_001",
      "type": "buyer_seller",
      "vehicle_id": "veh_abc123",
      "vehicle_title": "Toyota Camry 2024 SE",
      "vehicle_image_url": "https://cdn.example.com/vehicles/veh_abc123/thumb.jpg",
      "participants": [
        {
          "user_id": "usr_buyer01",
          "name": "Juan Perez",
          "avatar_url": "/avatars/juan.jpg",
          "is_online": true
        },
        {
          "user_id": "usr_seller01",
          "name": "AutoMax Motors",
          "avatar_url": "/avatars/automax.jpg",
          "is_online": false,
          "last_seen": "2026-03-23T09:30:00Z"
        }
      ],
      "last_message": {
        "content": "Si, esta disponible! Puedo agendar una cita.",
        "sender_name": "AutoMax Motors",
        "sent_at": "2026-03-23T10:15:00Z"
      },
      "unread_count": 2,
      "created_at": "2026-03-22T14:00:00Z",
      "updated_at": "2026-03-23T10:15:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 8
  }
}
```

**Data Model**:
```
Conversation (DOM)
  - conversation_id: UUID (PK)
  - type: Enum(BUYER_SELLER, BUYER_SUPPORT)
  - vehicle_id: UUID (FK, nullable)
  - status: Enum(ACTIVE, ARCHIVED, BLOCKED)
  - created_at: DateTime
  - updated_at: DateTime (indexed)

ConversationParticipant (DOM)
  - participant_id: UUID (PK)
  - conversation_id: UUID (FK)
  - user_id: UUID (FK)
  - role: Enum(BUYER, SELLER, SUPPORT)
  - joined_at: DateTime
  - last_read_message_id: UUID nullable
  - last_read_at: DateTime nullable
  - is_muted: Boolean default false
  - notifications_enabled: Boolean default true

Message (DOM)
  - message_id: UUID (PK)
  - conversation_id: UUID (FK, indexed)
  - sender_id: UUID (FK)
  - content: Text (encrypted)
  - content_type: Enum(TEXT, IMAGE, FILE, SYSTEM)
  - is_edited: Boolean default false
  - edited_at: DateTime nullable
  - is_deleted: Boolean default false
  - deleted_at: DateTime nullable
  - sent_at: DateTime (indexed)
  - created_at: DateTime

MessageAttachment (DOM)
  - attachment_id: UUID (PK)
  - message_id: UUID (FK)
  - file_name: String(255)
  - file_type: String(50)
  - file_size_bytes: Integer
  - s3_key: String(255)
  - cdn_url: String(255)
  - thumbnail_url: String(255) nullable
  - created_at: DateTime

UserPresence (INF - Redis)
  - Key: presence:{user_id}
  - Value: {is_online: bool, last_seen: timestamp, active_conversations: []}
  - TTL: 120 seconds (refreshed by heartbeat)
```

**Component Structure**:
```
svc-cht/
  domain/
    models/conversation.py
    models/conversation_participant.py
    models/message.py
    models/message_attachment.py
    services/conversation_service.py
    services/message_service.py
    services/presence_service.py
  application/
    use_cases/create_conversation_use_case.py
    use_cases/send_message_use_case.py
    use_cases/get_conversation_history_use_case.py
    use_cases/upload_attachment_use_case.py
    dto/conversation_dto.py
    dto/message_dto.py
    validators/message_validator.py
  infrastructure/
    websocket/
      chat_ws_handler.py
      ws_connection_manager.py
      typing_indicator_manager.py
    repositories/
      conversation_repository.py
      message_repository.py
      participant_repository.py
    presence/
      redis_presence_service.py
    storage/
      s3_attachment_storage.py
    pubsub/
      redis_chat_pubsub.py
    encryption/
      message_encryptor.py
  api/
    routes/chat_routes.py
    routes/conversation_routes.py
    schemas/chat_schema.py
  config/
    chat_config.py
```

#### Acceptance Criteria

1. **AC-01**: WebSocket connection at /api/v1/chat/ws requires valid JWT; on connection, the user's presence is set to online in Redis (key `presence:{user_id}`, TTL 120s, refreshed by heartbeat); on disconnect, presence is removed after TTL expiry.
2. **AC-02**: POST /api/v1/chat/conversations creates a new conversation; required: type (buyer_seller or buyer_support), participant user_ids; for buyer_seller, vehicle_id is required (the conversation is linked to a specific vehicle listing); duplicate conversations (same participants + vehicle) return the existing conversation.
3. **AC-03**: Sending a message (via WebSocket or REST POST) creates a Message record, encrypts content at rest, and broadcasts the new_message event to all conversation participants connected via WebSocket; if a participant is offline, a notification is sent via SVC-NTF.
4. **AC-04**: Typing indicators: when a user sends typing_start, a typing_indicator event is broadcast to other participants in the conversation; the indicator auto-expires after 5 seconds if no new typing_start is received; typing_stop explicitly clears the indicator.
5. **AC-05**: Read receipts: when a user sends read_receipt with last_read_message_id, the ConversationParticipant.last_read_message_id is updated, and a read_receipt event is broadcast to other participants; the conversation's unread_count for the reading user is recalculated.
6. **AC-06**: GET /api/v1/chat/conversations returns paginated conversations for the authenticated user, sorted by updated_at descending (most recent activity first); each conversation includes: last message preview (truncated to 100 chars), unread_count, participants with online status, and associated vehicle info.
7. **AC-07**: GET /api/v1/chat/conversations/{id}/messages returns paginated message history, sorted by sent_at ascending; supports cursor-based pagination (before message_id) for infinite scroll loading of older messages; default page size is 50.
8. **AC-08**: File attachments: POST /conversations/{id}/attachments accepts multipart upload; allowed types: JPEG, PNG, GIF, PDF, DOCX (max 10MB per file, max 5 files per message); files are stored in S3 with CDN URL; images generate a 200px thumbnail; the attachment_ids are included in the subsequent message.
9. **AC-09**: Message content is encrypted at rest using AES-256-GCM; encryption keys are managed per conversation via AWS KMS; messages are decrypted only when delivered to authorized participants.
10. **AC-10**: System messages are generated automatically for events: conversation created ("Juan inicio una conversacion sobre Toyota Camry 2024"), vehicle sold ("Este vehiculo ha sido vendido"), support assigned ("Un agente de soporte se ha unido a la conversacion").
11. **AC-11**: Presence: online status of participants is tracked via Redis; presence is visible in conversation list and header; last_seen timestamp is stored when user goes offline; presence updates are broadcast to conversation participants.
12. **AC-12**: A user can block another user in a conversation; blocked users cannot send messages (attempt returns 403); blocking creates a SYSTEM message "El usuario ha bloqueado esta conversacion"; admins can unblock.
13. **AC-13**: WebSocket connections support reconnection with replay: on reconnect, the client sends the last received message_id; the server replays any missed messages since that ID.

#### Definition of Done
- WebSocket chat handler with message types (message, typing, read receipt)
- REST API for conversations and message history
- Redis presence tracking
- File attachment upload with S3 storage
- Message encryption at rest
- Notification integration for offline users
- Unit tests >= 95% coverage
- Integration tests for WebSocket flows
- Load test: 500 concurrent WebSocket connections, 100 messages/second
- Code reviewed and merged to develop

#### Technical Notes
- Use Flask-SocketIO with Redis message queue for horizontal scaling
- Message encryption should use per-conversation keys derived from a master key
- Consider message retention policy (archive conversations older than 1 year)
- Typing indicator debounce on client side (emit typing_start max once per 3 seconds)
- For cursor-based pagination, use message_id (UUID v7 for time-ordering) as cursor
- Consider implementing message search with Elasticsearch in a future iteration

#### Dependencies
- SVC-USR for participant profile data (name, avatar)
- SVC-VEH for vehicle context in conversations
- SVC-NTF for offline message notifications
- AWS S3 for file storage
- AWS KMS for encryption key management
- Redis for presence and WebSocket pub/sub

---

### US-3: [MKT-FE-025][FE-FEAT-NTF] Centro de Notificaciones

**Description**:
Build the notification center for the Angular 18 frontend. The notification center includes a bell icon with unread count badge in the header, a dropdown panel showing recent notifications, a full-page notification list with filters, mark read/unread functionality, and a preferences settings panel. The component connects via WebSocket for real-time notification delivery.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-NTF (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/notifications/
  notification-bell/
    notification-bell.component.ts
    notification-bell.component.html
    notification-bell.component.spec.ts
  notification-dropdown/
    notification-dropdown.component.ts
    notification-dropdown.component.html
  notification-list/
    notification-list.component.ts
    notification-list.component.html
  notification-item/
    notification-item.component.ts
    notification-item.component.html
  notification-preferences/
    notification-preferences.component.ts
    notification-preferences.component.html
  services/
    notification.service.ts
    notification-websocket.service.ts
  state/
    notification.store.ts
```

**Notification Store**:
```typescript
@Injectable({ providedIn: 'root' })
export class NotificationStore {
  readonly notifications = signal<Notification[]>([]);
  readonly unreadCount = signal<number>(0);
  readonly isDropdownOpen = signal<boolean>(false);
  readonly isLoading = signal<boolean>(false);
  readonly filter = signal<NotificationFilter>({
    type: null,
    isRead: null,
    dateRange: null
  });
  readonly preferences = signal<NotificationPreferences | null>(null);
  readonly wsConnectionState = signal<'connected' | 'connecting' | 'disconnected'>('disconnected');

  readonly recentNotifications = computed(() =>
    this.notifications().slice(0, 5)
  );
  readonly hasUnread = computed(() => this.unreadCount() > 0);
}
```

**Bell Icon Component**:
```html
<!-- Notification bell in header -->
<button class="relative p-2 rounded-full hover:bg-gray-100
               transition-colors"
        (click)="toggleDropdown()"
        [attr.aria-label]="'Notifications: ' + store.unreadCount() + ' unread'">
  <!-- Bell SVG icon -->
  <svg class="w-6 h-6 text-gray-600" fill="none" stroke="currentColor"
       viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
  </svg>

  <!-- Unread badge -->
  @if (store.hasUnread()) {
    <span class="absolute -top-1 -right-1 flex items-center justify-center
                 min-w-[20px] h-5 px-1 text-xs font-bold text-white
                 bg-red-500 rounded-full animate-pulse">
      {{ store.unreadCount() > 99 ? '99+' : store.unreadCount() }}
    </span>
  }
</button>
```

#### Acceptance Criteria

1. **AC-01**: A bell icon is displayed in the application header (visible on all pages for authenticated users); the icon shows an unread count badge (red circle with count) when unread notifications exist; count caps at "99+" for counts > 99.
2. **AC-02**: Clicking the bell icon opens a dropdown panel showing the 5 most recent notifications; each notification shows: type icon, title (bold if unread), body preview (truncated to 80 chars), relative timestamp ("hace 5 min", "hace 2 horas", "ayer"); clicking a notification navigates to the action_url and marks it as read.
3. **AC-03**: The dropdown includes a "Mark all as read" link at the top and a "View all" link at the bottom that navigates to the full notification list page.
4. **AC-04**: The full notification list page (/notifications) displays all notifications with infinite scroll pagination (load 20 at a time); each notification shows: type icon, title, full body text, timestamp, read/unread visual indicator (bold text + blue dot for unread).
5. **AC-05**: Filter controls on the full list page: type filter (dropdown with options: All, Financing, Insurance, Chat, System, Promotions), read status filter (All, Unread, Read), date range filter (Today, This Week, This Month, Custom); filters are applied client-side for cached results and server-side for paginated loads.
6. **AC-06**: Each notification has a context menu (click three-dot icon or right-click): "Mark as read/unread", "Delete", "Mute this type"; mark as read/unread toggles the is_read state and updates the badge count.
7. **AC-07**: WebSocket connection for real-time delivery: the notification service connects to /notifications/ws on app initialization; when a new notification arrives, it appears at the top of the dropdown with a slide-down animation, the badge count increments, and a brief toast notification appears (if not on the notifications page).
8. **AC-08**: Notification sound: a subtle notification sound plays when a new notification arrives (if browser supports and user has not muted); the sound is configurable in preferences.
9. **AC-09**: A "Notification Settings" page (accessible from dropdown gear icon or preferences link) allows users to configure: enable/disable each channel (in-app, email, push, WhatsApp, SMS), set quiet hours (start time, end time, timezone), opt in/out of notification types (financing, insurance, chat, marketing, system, price changes); save calls PUT /preferences endpoint.
10. **AC-10**: Push notification permission: the app requests browser push notification permission on first login; if granted, the FCM token is registered via the notification service; if denied, the push option in preferences shows "Browser permission denied" with instructions.
11. **AC-11**: The bell icon and dropdown are responsive: on mobile, clicking the bell navigates directly to the full notification list page (no dropdown); on desktop, the dropdown is positioned below the bell icon with a max-height and scroll.
12. **AC-12**: Empty state: when no notifications exist, the dropdown and list page show "No notifications yet" with a friendly illustration; when all filters return no results, show "No notifications matching your filters" with a clear filters button.
13. **AC-13**: Accessibility: the bell button has an aria-label announcing the unread count; new notifications are announced via aria-live region; notification items are keyboard navigable with Enter to activate.

#### Definition of Done
- Bell icon with badge, dropdown, and full list page implemented
- WebSocket integration for real-time delivery
- Filter and search functionality
- Preferences settings page
- Mark read/unread, delete, mute actions
- Push notification permission flow
- Unit tests >= 90% coverage
- E2E test: receive notification -> see in dropdown -> click -> navigate
- Accessibility audit passed
- Code reviewed and merged to develop

#### Technical Notes
- WebSocket service should be initialized in the app root (singleton, connected after authentication)
- Unread count should be fetched from GET /unread-count on init and updated locally via WebSocket
- Consider using service worker for background push notifications (PWA)
- Notification sound file should be < 50KB (short chime)
- Dropdown should use Angular CDK Overlay for positioning
- Toast notifications via a shared toast service (not duplicating with the notification center)

#### Dependencies
- US-1 (Notification backend API + WebSocket)
- Shared header component (for bell icon placement)
- Angular CDK Overlay (for dropdown positioning)
- Firebase SDK (for FCM token registration)

---

### US-4: [MKT-FE-026][FE-FEAT-CHT] Chat Widget Integrado

**Description**:
Build an integrated chat widget for the Angular 18 frontend featuring a floating chat button, a slide-out drawer with conversation list, real-time messaging with typing indicators, read receipts, and image/file sending capabilities. The widget is available on all pages and provides seamless communication between buyers and sellers.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-CHT (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/chat/
  chat-widget/
    chat-widget.component.ts
    chat-widget.component.html
    chat-widget.component.spec.ts
  chat-button/
    chat-button.component.ts
    chat-button.component.html
  conversation-list/
    conversation-list.component.ts
    conversation-list.component.html
  conversation-item/
    conversation-item.component.ts
    conversation-item.component.html
  message-thread/
    message-thread.component.ts
    message-thread.component.html
  message-bubble/
    message-bubble.component.ts
    message-bubble.component.html
  message-input/
    message-input.component.ts
    message-input.component.html
  typing-indicator/
    typing-indicator.component.ts
    typing-indicator.component.html
  file-preview/
    file-preview.component.ts
    file-preview.component.html
  services/
    chat.service.ts
    chat-websocket.service.ts
  state/
    chat.store.ts
  animations/
    chat.animations.ts
```

**Chat Store**:
```typescript
@Injectable({ providedIn: 'root' })
export class ChatStore {
  readonly isOpen = signal<boolean>(false);
  readonly activeView = signal<'list' | 'thread'>('list');
  readonly conversations = signal<Conversation[]>([]);
  readonly activeConversationId = signal<string | null>(null);
  readonly messages = signal<Map<string, Message[]>>(new Map());
  readonly typingUsers = signal<Map<string, TypingUser>>(new Map());
  readonly isConnected = signal<boolean>(false);
  readonly totalUnread = signal<number>(0);
  readonly isSending = signal<boolean>(false);
  readonly attachments = signal<PendingAttachment[]>([]);

  readonly activeConversation = computed(() =>
    this.conversations().find(c => c.conversationId === this.activeConversationId()) ?? null
  );
  readonly activeMessages = computed(() =>
    this.messages().get(this.activeConversationId() ?? '') ?? []
  );
  readonly activeTypingUser = computed(() =>
    this.typingUsers().get(this.activeConversationId() ?? '') ?? null
  );
}
```

**Floating Button**:
```html
<!-- Floating chat button (bottom-right) -->
<button
  class="fixed bottom-6 right-6 w-14 h-14 rounded-full bg-blue-600
         text-white shadow-lg hover:bg-blue-700 hover:shadow-xl
         transition-all duration-300 flex items-center justify-center
         z-50"
  [class.scale-0]="store.isOpen()"
  (click)="openChat()"
  aria-label="Open chat">
  <!-- Chat icon SVG -->
  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"/>
  </svg>

  <!-- Unread badge on button -->
  @if (store.totalUnread() > 0) {
    <span class="absolute -top-1 -right-1 flex items-center justify-center
                 w-5 h-5 text-xs font-bold bg-red-500 text-white rounded-full">
      {{ store.totalUnread() > 9 ? '9+' : store.totalUnread() }}
    </span>
  }
</button>
```

**Chat Drawer Layout**:
```html
<!-- Chat drawer (right side) -->
<div class="fixed bottom-0 right-0 w-full sm:w-96 h-[600px] sm:h-[500px]
            sm:bottom-6 sm:right-6 bg-white rounded-t-2xl sm:rounded-2xl
            shadow-2xl flex flex-col z-50 overflow-hidden"
     [@drawerAnimation]="store.isOpen() ? 'open' : 'closed'">

  <!-- Header -->
  <div class="flex items-center justify-between p-4 border-b bg-blue-600 text-white">
    @if (store.activeView() === 'list') {
      <h3 class="font-semibold">Mensajes</h3>
    } @else {
      <button (click)="backToList()" class="p-1 hover:bg-blue-700 rounded">
        <!-- Back arrow -->
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M15 19l-7-7 7-7"/>
        </svg>
      </button>
      <span class="font-semibold truncate mx-2">
        {{ store.activeConversation()?.participantName }}
      </span>
    }
    <button (click)="closeChat()" class="p-1 hover:bg-blue-700 rounded">
      <!-- X icon -->
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M6 18L18 6M6 6l12 12"/>
      </svg>
    </button>
  </div>

  <!-- Content area -->
  @if (store.activeView() === 'list') {
    <app-conversation-list />
  } @else {
    <app-message-thread />
  }
</div>
```

#### Acceptance Criteria

1. **AC-01**: A floating circular chat button is displayed in the bottom-right corner on all pages for authenticated users; the button shows an unread message count badge; clicking the button opens the chat drawer with a scale-up animation; the button hides when the drawer is open.
2. **AC-02**: The chat drawer is a panel (fixed position, 500px tall on desktop, full-height on mobile) containing either the conversation list or a message thread; a smooth slide/scale animation transitions between open and closed states.
3. **AC-03**: Conversation list displays all user conversations sorted by most recent message; each item shows: participant avatar (with green dot if online), participant name, vehicle title (if applicable), last message preview (truncated), relative timestamp, unread count badge (if > 0); clicking a conversation opens the message thread.
4. **AC-04**: Message thread displays the full conversation with messages in chronological order; sent messages appear on the right (blue bubble), received on the left (gray bubble); each bubble shows: message content, timestamp, and for sent messages a delivery indicator (single check = sent, double check = delivered, blue double check = read).
5. **AC-05**: Typing indicator: when the other participant is typing, an animated "..." indicator appears at the bottom of the thread (three dots pulsing); the indicator auto-hides after 5 seconds of no typing activity.
6. **AC-06**: Message input area at the bottom of the thread includes: text input (auto-expanding textarea, max 1000 chars), attachment button (opens file picker for images/documents), send button (enabled only when text or attachment present); Enter key sends the message (Shift+Enter for newline).
7. **AC-07**: Image/file attachments: clicking the attachment button allows selecting files (JPEG, PNG, GIF, PDF, max 10MB); selected files show as previews above the input area (images as thumbnails, documents as file icon + name); an X button removes pending attachments; on send, files are uploaded to S3 then the message is sent with attachment_ids.
8. **AC-08**: Starting a new conversation: on the vehicle detail page, a "Chat with seller" button initiates a conversation (POST /conversations with vehicle_id and seller user_id); if a conversation already exists for that vehicle + buyer + seller, the existing conversation is opened.
9. **AC-09**: Real-time delivery: the chat WebSocket service connects on authentication; new messages from other users appear instantly with a brief slide-up animation in the thread; if the drawer is closed, the unread badge on the floating button increments and a subtle notification sound plays.
10. **AC-10**: Infinite scroll for message history: scrolling to the top of the thread loads older messages (cursor-based pagination); a loading spinner appears during fetch; scroll position is preserved after loading older messages.
11. **AC-11**: Online/offline indicator: participants' online status is shown via a green dot on their avatar in the conversation list and thread header; when a participant goes offline, the dot disappears and "Last seen: [timestamp]" is shown.
12. **AC-12**: The chat widget is responsive: on mobile (< 640px), the drawer occupies the full screen width and height (bottom sheet behavior); on desktop, it's a 384px-wide, 500px-tall panel anchored to the bottom-right; animations adapt to screen size.
13. **AC-13**: Empty states: conversation list empty -> "No conversations yet. Start chatting by visiting a vehicle listing!" with illustration; message thread empty (new conversation) -> "Say hello! Send your first message about [Vehicle Title]".

#### Definition of Done
- Floating button with unread badge
- Chat drawer with conversation list and message thread
- WebSocket integration for real-time messaging
- Typing indicators and read receipts
- File/image attachment upload
- Online presence indicators
- Smooth animations for all transitions
- Unit tests >= 90% coverage
- E2E test: open chat -> send message -> receive reply -> send image
- Performance: < 100ms message render after WebSocket delivery
- Code reviewed and merged to develop

#### Technical Notes
- Chat WebSocket should share the connection manager with notifications (or use separate connection)
- Message bubbles should use `@defer` for image attachment loading
- Consider lazy-loading the entire chat widget (not needed until user interacts)
- Use `IntersectionObserver` for infinite scroll trigger (top of message thread)
- Sound playback should respect browser autoplay policies (require user interaction first)
- On mobile, use `overscroll-behavior: contain` to prevent background scroll

#### Dependencies
- US-2 (Chat backend API + WebSocket)
- Vehicle detail page ("Chat with seller" button)
- Shared avatar component
- S3 pre-signed upload URL endpoint

---

### US-5: [MKT-BE-030][SVC-SEO] SEO Backend - Sitemap & Metadata

**Description**:
Implement the SEO backend service that generates dynamic sitemaps, Open Graph and Twitter Card metadata for vehicle pages, Schema.org Vehicle structured data for rich search results, and manages canonical URLs. This service ensures that the 11,000+ vehicle listings are discoverable and richly represented in search engine results pages (SERPs).

**Microservice**: SVC-SEO (:5022)
**Layer**: API + APP + INF

#### Technical Context

**Endpoints**:
```
GET    /sitemap.xml                              # Main sitemap index
GET    /sitemap-vehicles.xml                     # Vehicle listings sitemap
GET    /sitemap-vehicles-{page}.xml              # Paginated vehicle sitemaps
GET    /sitemap-pages.xml                        # Static pages sitemap
GET    /api/v1/seo/metadata/{vehicle_id}         # Vehicle page metadata
GET    /api/v1/seo/structured-data/{vehicle_id}  # Schema.org structured data
GET    /robots.txt                               # Robots.txt
```

**Sitemap Index**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <sitemap>
    <loc>https://marketplace.com/sitemap-pages.xml</loc>
    <lastmod>2026-03-23</lastmod>
  </sitemap>
  <sitemap>
    <loc>https://marketplace.com/sitemap-vehicles-1.xml</loc>
    <lastmod>2026-03-23</lastmod>
  </sitemap>
  <sitemap>
    <loc>https://marketplace.com/sitemap-vehicles-2.xml</loc>
    <lastmod>2026-03-23</lastmod>
  </sitemap>
</sitemapindex>
```

**Vehicle Sitemap Page**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
  <url>
    <loc>https://marketplace.com/vehiculos/toyota-camry-2024-se-veh_abc123</loc>
    <lastmod>2026-03-23</lastmod>
    <changefreq>daily</changefreq>
    <priority>0.8</priority>
    <image:image>
      <image:loc>https://cdn.example.com/vehicles/veh_abc123/1.jpg</image:loc>
      <image:title>Toyota Camry 2024 SE - Vista frontal</image:title>
    </image:image>
  </url>
</urlset>
```

**Vehicle Metadata Response**:
```json
{
  "vehicle_id": "veh_abc123",
  "canonical_url": "https://marketplace.com/vehiculos/toyota-camry-2024-se-veh_abc123",
  "title": "Toyota Camry 2024 SE | Marketplace Vehiculos - $450,000 MXN",
  "description": "Toyota Camry 2024 SE en excelente estado. Motor 2.5L, transmision automatica, 15,000 km. Precio: $450,000 MXN. Financiamiento disponible.",
  "keywords": "Toyota Camry 2024, auto seminuevo, comprar camry, Toyota CDMX",
  "open_graph": {
    "og:title": "Toyota Camry 2024 SE - $450,000 MXN",
    "og:description": "Toyota Camry 2024 SE en excelente estado. 15,000 km. Financiamiento disponible.",
    "og:image": "https://cdn.example.com/vehicles/veh_abc123/og-1200x630.jpg",
    "og:image:width": "1200",
    "og:image:height": "630",
    "og:url": "https://marketplace.com/vehiculos/toyota-camry-2024-se-veh_abc123",
    "og:type": "product",
    "og:locale": "es_MX",
    "og:site_name": "Marketplace Vehiculos"
  },
  "twitter_card": {
    "twitter:card": "summary_large_image",
    "twitter:title": "Toyota Camry 2024 SE - $450,000 MXN",
    "twitter:description": "Toyota Camry 2024 SE en excelente estado. Financiamiento disponible.",
    "twitter:image": "https://cdn.example.com/vehicles/veh_abc123/og-1200x630.jpg"
  },
  "alternate_urls": {
    "es": "https://marketplace.com/vehiculos/toyota-camry-2024-se-veh_abc123"
  }
}
```

**Schema.org Structured Data Response**:
```json
{
  "@context": "https://schema.org",
  "@type": "Car",
  "name": "Toyota Camry 2024 SE",
  "description": "Toyota Camry 2024 SE en excelente estado. Motor 2.5L, transmision automatica.",
  "brand": {
    "@type": "Brand",
    "name": "Toyota"
  },
  "model": "Camry",
  "vehicleModelDate": "2024",
  "bodyType": "Sedan",
  "fuelType": "Gasolina",
  "vehicleTransmission": "Automatica",
  "mileageFromOdometer": {
    "@type": "QuantitativeValue",
    "value": 15000,
    "unitCode": "KMT"
  },
  "color": "Blanco",
  "vehicleInteriorColor": "Negro",
  "numberOfDoors": 4,
  "vehicleSeatingCapacity": 5,
  "vehicleEngine": {
    "@type": "EngineSpecification",
    "engineDisplacement": {
      "@type": "QuantitativeValue",
      "value": 2.5,
      "unitCode": "LTR"
    },
    "fuelType": "Gasolina"
  },
  "offers": {
    "@type": "Offer",
    "price": 450000.00,
    "priceCurrency": "MXN",
    "availability": "https://schema.org/InStock",
    "url": "https://marketplace.com/vehiculos/toyota-camry-2024-se-veh_abc123",
    "seller": {
      "@type": "AutoDealer",
      "name": "AutoMax Motors",
      "address": {
        "@type": "PostalAddress",
        "addressLocality": "Ciudad de Mexico",
        "addressRegion": "CDMX",
        "addressCountry": "MX"
      }
    }
  },
  "image": [
    "https://cdn.example.com/vehicles/veh_abc123/1.jpg",
    "https://cdn.example.com/vehicles/veh_abc123/2.jpg",
    "https://cdn.example.com/vehicles/veh_abc123/3.jpg"
  ],
  "url": "https://marketplace.com/vehiculos/toyota-camry-2024-se-veh_abc123"
}
```

**Data Model**:
```
SeoMetadata (DOM)
  - metadata_id: UUID (PK)
  - entity_type: Enum(VEHICLE, PAGE, CATEGORY)
  - entity_id: UUID
  - canonical_url: String(500)
  - slug: String(255) UNIQUE
  - title: String(200)
  - description: String(500)
  - keywords: String(500)
  - og_image_url: String(500)
  - structured_data: JSONB
  - is_indexable: Boolean default true
  - last_generated_at: DateTime
  - created_at: DateTime
  - updated_at: DateTime

SitemapEntry (INF)
  - entry_id: UUID (PK)
  - url: String(500)
  - entity_type: String(20)
  - entity_id: UUID
  - lastmod: Date
  - changefreq: Enum(ALWAYS, HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY, NEVER)
  - priority: Decimal(2,1)
  - images: JSONB
  - is_active: Boolean default true
  - created_at: DateTime
  - updated_at: DateTime

SlugHistory (INF)
  - history_id: UUID (PK)
  - entity_type: String(20)
  - entity_id: UUID
  - old_slug: String(255)
  - new_slug: String(255)
  - redirected_at: DateTime
  - created_at: DateTime
```

**Component Structure**:
```
svc-seo/
  domain/
    models/seo_metadata.py
    models/sitemap_entry.py
    models/slug_history.py
    services/metadata_generator_service.py
    services/structured_data_service.py
    services/slug_service.py
  application/
    use_cases/generate_vehicle_metadata_use_case.py
    use_cases/generate_sitemap_use_case.py
    use_cases/generate_structured_data_use_case.py
    dto/metadata_dto.py
    dto/structured_data_dto.py
  infrastructure/
    repositories/metadata_repository.py
    repositories/sitemap_repository.py
    repositories/slug_history_repository.py
    clients/vehicle_service_client.py
    generators/
      sitemap_xml_generator.py
      og_image_generator.py
      robots_txt_generator.py
    cache/
      sitemap_cache.py
      metadata_cache.py
  api/
    routes/seo_routes.py
    routes/sitemap_routes.py
    schemas/metadata_schema.py
  config/
    seo_config.py
```

#### Acceptance Criteria

1. **AC-01**: GET /sitemap.xml returns a sitemap index XML listing all sub-sitemaps: sitemap-pages.xml (static pages), sitemap-vehicles-{n}.xml (paginated vehicle listings, max 5000 URLs per file); response Content-Type is application/xml; cached in Redis with TTL 3600s.
2. **AC-02**: GET /sitemap-vehicles-{page}.xml returns a valid sitemap XML with vehicle URLs; each URL includes: loc (canonical URL with SEO-friendly slug), lastmod (vehicle's updated_at date), changefreq (daily), priority (0.8); vehicle images are included using the sitemap image extension namespace.
3. **AC-03**: Vehicle sitemaps are regenerated every 6 hours by a scheduled task; new/updated/deleted vehicles are reflected in the next generation; the sitemap includes only published, indexable vehicles.
4. **AC-04**: GET /api/v1/seo/metadata/{vehicle_id} returns metadata for a vehicle page: title (brand + model + year + version + price, max 60 chars), description (features summary, max 160 chars), keywords, canonical URL, Open Graph tags (og:title, og:description, og:image 1200x630, og:type=product, og:locale=es_MX), Twitter Card tags (summary_large_image format).
5. **AC-05**: The og:image is a pre-generated 1200x630px image optimized for social sharing; it is generated from the vehicle's primary image with a branded overlay (price badge, marketplace logo); stored in S3/CDN.
6. **AC-06**: GET /api/v1/seo/structured-data/{vehicle_id} returns Schema.org Car type JSON-LD with: brand, model, year, bodyType, fuelType, transmission, mileage, color, engine specs, offers (price, currency, availability, seller), images array, URL; the data validates against Google's Rich Results Test.
7. **AC-07**: Canonical URLs use SEO-friendly slugs: /vehiculos/{brand}-{model}-{year}-{version}-{vehicle_id_short}; slugs are generated from vehicle data, lowercased, accents removed, spaces replaced with hyphens; slug uniqueness is enforced.
8. **AC-08**: When a vehicle is updated causing a slug change (e.g., version corrected), the old slug is stored in SlugHistory; requests to old slugs return 301 redirect to the new canonical URL; redirect chains are prevented (always redirect to current slug).
9. **AC-09**: GET /robots.txt returns a dynamically generated robots.txt allowing all crawlers on vehicle pages and sitemaps; disallowing admin paths (/admin/*), API endpoints (/api/*), and user-specific paths (/account/*, /financing/applications/*); includes sitemap reference.
10. **AC-10**: Metadata is cached in Redis with key `seo:meta:{vehicle_id}` and TTL 3600s; cache is invalidated when the vehicle is updated (via Redis pub/sub from SVC-VEH); sitemap cache uses key `seo:sitemap:{page}` with TTL 21600s (6h).
11. **AC-11**: The metadata generator handles edge cases: vehicles without images use a default OG image; vehicles without description generate one from specs; very long titles are truncated with ellipsis at 60 chars.
12. **AC-12**: A scheduled daily report counts: total indexed vehicles, new URLs added, redirects active, sitemap sizes, and any metadata generation errors; report is logged and available via admin dashboard (SVC-ADM).

#### Definition of Done
- Sitemap generation with pagination and image extension
- Metadata endpoint with OG + Twitter Card tags
- Schema.org structured data validated with Google Rich Results Test
- SEO-friendly slug generation with redirect history
- Robots.txt generation
- Redis caching with invalidation
- Unit tests >= 95% coverage
- Integration test: create vehicle -> verify in sitemap -> verify metadata -> verify structured data
- Validate structured data with Google/Bing tools
- Code reviewed and merged to develop

#### Technical Notes
- Use `lxml` for XML generation (faster than stdlib xml.etree)
- OG image generation: use `Pillow` to composite vehicle image with brand overlay
- Schema.org validation: test with Google's Structured Data Testing Tool
- Sitemap URLs must be absolute (include domain)
- Consider prerendering OG images for all vehicles as a batch job
- Slug generation should use `python-slugify` with transliteration for accent removal

#### Dependencies
- SVC-VEH for vehicle data
- AWS S3 / CDN for OG images
- Redis for caching
- Google Search Console for sitemap submission

---

### US-6: [MKT-FE-027][FE-SSR] SEO Frontend - SSR & Performance

**Description**:
Implement Angular Universal Server-Side Rendering (SSR) for vehicle detail pages and key landing pages, lazy image loading, Core Web Vitals optimization, and PWA manifest configuration. SSR ensures that search engine crawlers receive fully rendered HTML with metadata and structured data, while performance optimizations ensure top Lighthouse scores.

**Microservice**: Frontend (Angular 18 + Angular Universal)
**Layer**: FE-SSR

#### Technical Context

**SSR Architecture**:
```
Angular Universal Setup:
  server.ts              # Express server for SSR
  src/app/app.config.server.ts  # Server-side providers
  src/app/app.routes.server.ts  # Server-side route config

SSR Flow:
  1. Crawler/User requests /vehiculos/toyota-camry-2024-se-veh_abc123
  2. Express server receives request
  3. Angular Universal renders the page server-side
  4. SVC-SEO metadata is injected into <head> (title, meta, OG, structured data)
  5. Fully rendered HTML is sent to client
  6. Client-side Angular hydrates the page (takes over interactivity)
```

**Component Structure**:
```
src/
  server.ts
  app/
    app.config.server.ts
    app.routes.server.ts
    core/
      seo/
        seo.service.ts
        meta-tags.service.ts
        structured-data.service.ts
        canonical-url.service.ts
      performance/
        image-lazy-load.directive.ts
        preconnect.service.ts
        critical-css.service.ts
      pwa/
        service-worker.config.ts
        manifest.webmanifest
```

**SEO Service (SSR-aware)**:
```typescript
// seo.service.ts
@Injectable({ providedIn: 'root' })
export class SeoService {
  constructor(
    private meta: Meta,
    private title: Title,
    @Inject(DOCUMENT) private document: Document,
    @Inject(PLATFORM_ID) private platformId: Object,
    private seoApi: SeoApiService
  ) {}

  async setVehicleMetadata(vehicleId: string): Promise<void> {
    const metadata = await firstValueFrom(
      this.seoApi.getMetadata(vehicleId)
    );

    // Set title
    this.title.setTitle(metadata.title);

    // Set meta tags
    this.meta.updateTag({ name: 'description', content: metadata.description });
    this.meta.updateTag({ name: 'keywords', content: metadata.keywords });

    // Set Open Graph
    Object.entries(metadata.open_graph).forEach(([property, content]) => {
      this.meta.updateTag({ property, content: content as string });
    });

    // Set Twitter Card
    Object.entries(metadata.twitter_card).forEach(([name, content]) => {
      this.meta.updateTag({ name, content: content as string });
    });

    // Set canonical URL
    this.setCanonicalUrl(metadata.canonical_url);

    // Add structured data (JSON-LD)
    if (isPlatformServer(this.platformId)) {
      this.addStructuredData(metadata.structured_data);
    }
  }

  private setCanonicalUrl(url: string): void {
    let link: HTMLLinkElement = this.document.querySelector('link[rel="canonical"]')
      || this.document.createElement('link');
    link.setAttribute('rel', 'canonical');
    link.setAttribute('href', url);
    this.document.head.appendChild(link);
  }

  private addStructuredData(data: any): void {
    const script = this.document.createElement('script');
    script.type = 'application/ld+json';
    script.text = JSON.stringify(data);
    this.document.head.appendChild(script);
  }
}
```

**Image Lazy Load Directive**:
```typescript
// image-lazy-load.directive.ts
@Directive({
  selector: 'img[appLazyLoad]',
  standalone: true
})
export class ImageLazyLoadDirective implements OnInit {
  @Input('appLazyLoad') src!: string;
  @Input() placeholder: string = '/assets/placeholder-vehicle.svg';

  constructor(
    private el: ElementRef<HTMLImageElement>,
    @Inject(PLATFORM_ID) private platformId: Object
  ) {}

  ngOnInit(): void {
    if (isPlatformServer(this.platformId)) {
      // SSR: set actual src for crawlers
      this.el.nativeElement.src = this.src;
      return;
    }

    this.el.nativeElement.src = this.placeholder;
    this.el.nativeElement.setAttribute('loading', 'lazy');
    this.el.nativeElement.setAttribute('decoding', 'async');

    if ('IntersectionObserver' in window) {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            this.el.nativeElement.src = this.src;
            observer.unobserve(this.el.nativeElement);
          }
        });
      }, { rootMargin: '200px' });
      observer.observe(this.el.nativeElement);
    } else {
      this.el.nativeElement.src = this.src;
    }
  }
}
```

**PWA Manifest**:
```json
{
  "name": "Marketplace de Vehiculos",
  "short_name": "Vehiculos MKT",
  "description": "Compra y vende vehiculos con financiamiento y seguros",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#2563eb",
  "orientation": "portrait-primary",
  "icons": [
    {
      "src": "/assets/icons/icon-72x72.png",
      "sizes": "72x72",
      "type": "image/png"
    },
    {
      "src": "/assets/icons/icon-96x96.png",
      "sizes": "96x96",
      "type": "image/png"
    },
    {
      "src": "/assets/icons/icon-128x128.png",
      "sizes": "128x128",
      "type": "image/png"
    },
    {
      "src": "/assets/icons/icon-144x144.png",
      "sizes": "144x144",
      "type": "image/png"
    },
    {
      "src": "/assets/icons/icon-192x192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/assets/icons/icon-512x512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

#### Acceptance Criteria

1. **AC-01**: Angular Universal SSR is configured for the following routes: /vehiculos/{slug} (vehicle detail), / (homepage), /vehiculos (vehicle listing), /financiamiento (financing landing), /seguros (insurance landing); server-side rendered HTML includes full page content, not just an empty `<app-root>`.
2. **AC-02**: Vehicle detail pages rendered via SSR include in the HTML `<head>`: `<title>` tag with vehicle title, `<meta name="description">` with vehicle summary, all Open Graph meta tags (og:title, og:description, og:image, og:url, og:type), Twitter Card meta tags, `<link rel="canonical">` with SEO-friendly URL.
3. **AC-03**: Schema.org Vehicle structured data is injected as a `<script type="application/ld+json">` block in the server-rendered HTML; the JSON-LD validates against Google's Rich Results Test for Car type.
4. **AC-04**: Client-side hydration: after SSR HTML is delivered, the Angular client-side app hydrates (takes over) without re-rendering; no visible flash of content or layout shift during hydration; hydration uses Angular 18's built-in hydration support.
5. **AC-05**: Image lazy loading: vehicle images below the fold use native `loading="lazy"` and `decoding="async"` attributes; the first image (hero/primary) is eagerly loaded with `fetchpriority="high"`; a low-resolution placeholder (blurred SVG or solid color) is shown until the full image loads.
6. **AC-06**: Core Web Vitals targets: LCP (Largest Contentful Paint) < 2.5s, FID (First Input Delay) < 100ms, CLS (Cumulative Layout Shift) < 0.1; these are measured on vehicle detail pages which are the most traffic-heavy.
7. **AC-07**: Critical CSS: above-the-fold CSS is inlined in the SSR response `<head>` to prevent render-blocking; remaining CSS is loaded asynchronously; no external CSS files block initial render.
8. **AC-08**: Preconnect hints are added for critical third-party origins: CDN domain (vehicle images), Google Fonts (if used), analytics domains; `<link rel="preconnect">` tags are included in the server-rendered HTML.
9. **AC-09**: PWA manifest is configured with: app name, icons (72-512px), theme color (#2563eb), start URL, display mode (standalone); the service worker caches: app shell (HTML/CSS/JS), vehicle list API responses (stale-while-revalidate), and vehicle images (cache-first with 7-day expiry).
10. **AC-10**: Service worker strategies: app shell files use cache-first (updated on new deployment); API responses use stale-while-revalidate (serve cached, fetch fresh in background); images use cache-first with max-age 7 days; the service worker is registered only in production builds.
11. **AC-11**: SSR performance: server-side render time for a vehicle detail page is < 500ms (measured at the Express server); the SSR server handles 50 concurrent requests without degradation; a TTL-based cache (Redis, 5 min) is used for SSR-rendered HTML of popular pages.
12. **AC-12**: Fallback behavior: if SSR fails (timeout, error), the server returns the client-only SPA (index.html) with a 200 status and appropriate meta tags from a fallback template; SSR errors are logged but never shown to users.
13. **AC-13**: Lighthouse audit: vehicle detail pages score >= 90 on Performance, >= 90 on SEO, >= 90 on Accessibility, >= 90 on Best Practices in Lighthouse CI on both mobile and desktop.

#### Definition of Done
- Angular Universal SSR configured and working for key routes
- Meta tags and structured data injected server-side
- Client-side hydration working without flicker
- Image lazy loading with eager first image
- Core Web Vitals meeting targets (LCP < 2.5s, FID < 100ms, CLS < 0.1)
- PWA manifest and service worker configured
- Lighthouse scores >= 90 across all categories
- SSR response caching in Redis
- Unit tests for SEO service and directives
- Integration test: fetch SSR page -> verify meta tags in HTML -> verify hydration
- Lighthouse CI integrated in CI/CD pipeline
- Code reviewed and merged to develop

#### Technical Notes
- Use Angular 18's built-in hydration (`provideClientHydration()`) instead of older transfer state approach
- SSR cache key: URL path + query params hash; invalidate on vehicle update via Redis pub/sub
- For CLS prevention: set explicit width/height on images, use aspect-ratio CSS, reserve space for dynamic content
- Consider using `NgOptimizedImage` directive (Angular built-in) for automatic image optimization
- Service worker: use Angular's `@angular/service-worker` package for seamless integration
- Monitor Core Web Vitals in production via `web-vitals` library sending to analytics

#### Dependencies
- US-5 (SEO metadata and structured data API)
- Angular Universal (@angular/ssr package)
- Express server for SSR
- Redis for SSR response caching
- CDN for image delivery with resize capabilities

---

## Cross-Cutting Concerns

### Security
- WebSocket connections authenticated via JWT
- Chat messages encrypted at rest (AES-256-GCM)
- File attachments scanned for malware before storage
- Notification preferences require authenticated user
- WhatsApp and SMS sending rate-limited to prevent abuse

### Observability
- Notification delivery metrics: sent, delivered, failed, bounce rate per channel
- Chat metrics: messages per day, active conversations, avg response time
- SEO metrics: indexed pages, crawl errors, structured data validation results
- Core Web Vitals monitoring in production

### Performance
- Notification WebSocket: support 10,000 concurrent connections
- Chat WebSocket: support 5,000 concurrent connections
- SSR render time: < 500ms p95
- Sitemap generation: < 60s for 11,000 vehicles
- Redis caching throughout for sub-100ms API responses

### Compliance
- CAN-SPAM compliance for email notifications (unsubscribe link)
- WhatsApp Business API terms compliance (opt-in required)
- LFPDPPP for user communication preferences
- Accessibility: WCAG 2.1 AA for notification center and chat

---

## Epic Dependencies Graph

```
EP-010 Dependencies:
  SVC-USR (EP-002) --> User profiles, preferences, FCM tokens
  SVC-VEH (EP-003) --> Vehicle data for chat context, SEO metadata
  SVC-FIN (EP-007) --> Financing notification events
  SVC-INS (EP-008) --> Insurance notification events
  SVC-ADM (EP-009) --> Admin alerts, SEO reports
  AWS SES --> Email delivery
  Firebase --> Push notifications
  WhatsApp Business API --> WhatsApp messaging
  AWS SNS --> SMS fallback
  AWS S3 --> File attachments, OG images
```

## Release Plan

| Sprint | Stories | Focus |
|--------|---------|-------|
| Sprint 7 | US-1, US-2, US-3, US-4 | Notifications + Chat (Backend + Frontend) |
| Sprint 8 | US-5, US-6 | SEO Backend + SSR + Performance |
