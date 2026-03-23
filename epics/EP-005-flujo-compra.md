# [MKT-EP-005] Flujo de Compra Intuitivo (Purchase Flow)

**Sprint**: 4-6
**Priority**: Critical
**Owner**: Backend & Frontend Teams
**Status**: Draft

---

## Epic Overview

This epic implements the complete vehicle purchase flow from wishlist/favorites management through multi-step purchase completion with real-time tracking. The flow integrates with KYC verification (SVC-KYC), financing (SVC-FIN), insurance (SVC-INS), notifications (SVC-NTF), and chat (SVC-CHT) services. The purchase state machine is the core domain logic, governing all valid transitions and ensuring auditability at every step.

### Purchase State Machine

```
                                    [TIMEOUT 72h]
                                         |
                                         v
  INTENT -----> RESERVED -----> KYC_PENDING -----> FINANCING -----> INSURANCE -----> CONFIRMED -----> COMPLETED
    |               |               |                  |                |                |
    |               |               |                  |                |                |
    v               v               v                  v                v                v
  CANCELLED     CANCELLED       REJECTED           CANCELLED       CANCELLED        CANCELLED
                EXPIRED         (re-submit)        SKIPPED*        SKIPPED*
                                                      |                |
                                                      v                v
                                                  INSURANCE ------> CONFIRMED
                                                  (skip fin)       (skip ins)

  * SKIPPED transitions: Financing and Insurance steps are optional.
    If skipped, the flow advances to the next step automatically.

  Valid Transitions:
  +-----------------+--------------------------------------------------+
  | From State      | To States                                        |
  +-----------------+--------------------------------------------------+
  | intent          | reserved, cancelled                              |
  | reserved        | kyc_pending, cancelled, expired (auto 72h)       |
  | kyc_pending     | financing, rejected (-> documents_pending)       |
  | financing       | insurance, skipped_financing, cancelled          |
  | insurance       | confirmed, skipped_insurance, cancelled          |
  | confirmed       | completed, cancelled                             |
  | completed       | (terminal state)                                 |
  | cancelled       | (terminal state)                                 |
  | expired         | (terminal state)                                 |
  | rejected        | kyc_pending (re-submission)                      |
  +-----------------+--------------------------------------------------+

  Auto-Timeout Rules:
  - reserved -> expired: after 72 hours (configurable per vehicle category)
  - kyc_pending -> expired: after 48 hours if no documents uploaded
  - confirmed -> cancelled: after 7 days if payment not completed
```

### Architecture Context

```
[FE Angular 18] --> [SVC-GW :8080] --> [SVC-PUR :5013] --> [PostgreSQL / Redis]
                                    --> [SVC-USR :5011] --> [PostgreSQL]
                                    --> [SVC-KYC :5014] (KYC check)
                                    --> [SVC-FIN :5015] (Financing options)
                                    --> [SVC-INS :5016] (Insurance quotes)
                                    --> [SVC-NTF :5017] (Notifications)
                                    --> [SVC-CHT :5018] (Purchase chat)
```

### Key Metrics
- Purchase funnel conversion: intent -> completed > 15%
- Average time to complete: < 48 hours
- State transition latency: < 200ms
- Wishlist to intent conversion: > 25%

---

## User Stories

---

### [MKT-BE-011][SVC-USR-API] API de Wishlist y Favoritos

**Description**:
Build a REST API within SVC-USR (port 5011) that manages user wishlists and favorite vehicles. Users can add/remove vehicles, view their complete wishlist with current pricing, receive notifications when a favorited vehicle's price changes, and share their wishlist via a public link. The wishlist stores the price at the time of addition for comparison, and a background worker (WRK-NTF) monitors price changes to trigger notifications.

**Microservice**: SVC-USR (port 5011)
**Layer**: API (routes) + APP (application services) + DOM (wishlist domain) + INF (database, notification adapter)

#### Technical Context

**Endpoints**:

```
POST   /api/v1/users/me/wishlist
       Body: { "vehicle_id": "uuid", "notes": "optional personal note" }
       Response: 201 WishlistItemResponse | 409 AlreadyInWishlist

DELETE /api/v1/users/me/wishlist/{vehicle_id}
       Response: 204 No Content | 404 NotInWishlist

GET    /api/v1/users/me/wishlist
       Query params: ?page=1&per_page=20&sort_by=added_at|price_change&order=desc
       Response: 200 PaginatedWishlistResponse

GET    /api/v1/users/me/wishlist/summary
       Response: 200 { "total_items": 12, "total_value": 2450000, "avg_price_change": -3.2, "alerts_count": 2 }

PATCH  /api/v1/users/me/wishlist/{vehicle_id}
       Body: { "notes": "updated note", "price_alert_threshold": 5.0 }
       Response: 200 WishlistItemResponse

POST   /api/v1/users/me/wishlist/share
       Body: { "vehicle_ids": ["uuid1", "uuid2"], "expires_in_days": 7 }
       Response: 201 { "share_url": "https://marketplace.com/shared/abc123", "expires_at": "..." }

GET    /api/v1/shared/wishlist/{share_token}
       Response: 200 SharedWishlistResponse (no auth required)

POST   /api/v1/users/me/wishlist/{vehicle_id}/toggle
       Response: 200 { "is_favorited": true|false }
```

**Data Models**:

```python
# DOM Layer - domain/models/wishlist.py
class WishlistItem:
    id: UUID
    user_id: UUID
    vehicle_id: UUID
    added_at: datetime
    price_at_addition: Decimal  # MXN
    current_price: Decimal  # MXN (from SVC-VEH)
    price_change_percent: float
    notes: Optional[str]
    price_alert_threshold: float  # percentage, default 5.0
    price_alert_enabled: bool
    last_price_check: datetime
    vehicle_status: str  # available, reserved, sold

class WishlistShare:
    id: UUID
    user_id: UUID
    share_token: str  # unique, URL-safe
    vehicle_ids: List[UUID]
    created_at: datetime
    expires_at: datetime
    view_count: int
    is_active: bool
```

#### Acceptance Criteria

1. **AC-001**: POST `/api/v1/users/me/wishlist` adds a vehicle to the authenticated user's wishlist. The `price_at_addition` is captured from SVC-VEH at the time of addition. Returns 201 with the created item or 409 if the vehicle is already in the wishlist.
2. **AC-002**: DELETE `/api/v1/users/me/wishlist/{vehicle_id}` removes the vehicle from the wishlist. Returns 204 on success or 404 if the vehicle is not in the wishlist.
3. **AC-003**: GET `/api/v1/users/me/wishlist` returns a paginated list of wishlist items enriched with current vehicle data from SVC-VEH (title, thumbnail, current price, status). Each item includes `price_change_percent` calculated as `((current_price - price_at_addition) / price_at_addition) * 100`.
4. **AC-004**: Wishlist items are sortable by `added_at` (default), `price_change` (ascending = biggest drops first), `current_price`, and `vehicle_name`. Sort direction is configurable via `order` parameter.
5. **AC-005**: POST `/api/v1/users/me/wishlist/{vehicle_id}/toggle` provides a single endpoint for add/remove. If the vehicle is in the wishlist, it is removed and `is_favorited: false` is returned. If not, it is added and `is_favorited: true` is returned.
6. **AC-006**: PATCH endpoint allows updating `notes` (max 500 characters) and `price_alert_threshold` (minimum 1.0, maximum 50.0 percent). Validation errors return 400 with field-level error messages.
7. **AC-007**: WRK-NTF worker checks all active wishlist items every 30 minutes. When a vehicle's price changes by more than the user's `price_alert_threshold` percentage, a notification is sent via SVC-NTF (email and push). The notification includes: vehicle name, old price, new price, change percentage, and a deep link to the vehicle.
8. **AC-008**: POST `/api/v1/users/me/wishlist/share` generates a unique, URL-safe share token and creates a public link that displays the selected vehicles without requiring authentication. The share link expires after the specified number of days (default 7, max 30).
9. **AC-009**: GET `/api/v1/shared/wishlist/{share_token}` returns the shared wishlist with vehicle details (no auth required). Expired or invalid tokens return 404. Each view increments the `view_count`.
10. **AC-010**: GET `/api/v1/users/me/wishlist/summary` returns aggregated stats: total items count, total estimated value, average price change across all items, and count of items with active price alerts.
11. **AC-011**: When a wishlisted vehicle is sold or removed from the marketplace, the wishlist item's `vehicle_status` is updated to `sold` or `removed`, and the user receives a notification.
12. **AC-012**: Maximum wishlist size is 100 items per user. Attempting to add beyond 100 returns 400 with `{ "error": "wishlist_limit_reached", "max_items": 100 }`.
13. **AC-013**: All wishlist endpoints require valid JWT authentication except the shared wishlist view. Rate limit: 30 requests per minute per user.

#### Definition of Done
- All endpoints implemented with proper validation and error handling
- Price change detection working via WRK-NTF worker
- Share link generation and public access working
- Toggle endpoint provides idempotent add/remove behavior
- Unit tests for price change calculation and alert threshold logic
- Integration tests for all endpoints
- API documented in OpenAPI format

#### Technical Notes
- Use a composite unique index on `(user_id, vehicle_id)` to prevent duplicate wishlist entries at the database level.
- Price enrichment (current_price) should use a batch call to SVC-VEH to avoid N+1 queries when loading the wishlist page.
- Share tokens should be cryptographically random (use `secrets.token_urlsafe(16)`).
- Consider a Redis sorted set for quick "is this vehicle favorited?" lookups to support the heart toggle on vehicle cards.

#### Dependencies
- SVC-VEH (port 5012): Vehicle data and current pricing
- SVC-NTF (port 5017): Price change notifications
- WRK-NTF: Background price monitoring worker
- Redis 7: Quick favorite lookup cache

---

### [MKT-BE-012][SVC-PUR-API] API de Intencion de Compra y Reservacion

**Description**:
Build a REST API within SVC-PUR (port 5013) that manages purchase intents and vehicle reservations. A user can express intent to purchase a vehicle, which transitions to a reservation that locks the vehicle for 24-72 hours (configurable by vehicle category). The API manages the initial states of the purchase flow (intent -> reserved -> kyc_pending) and integrates with SVC-VEH for vehicle locking, SVC-KYC for verification status checks, and SVC-NTF for status change notifications.

**Microservice**: SVC-PUR (port 5013)
**Layer**: API (routes) + APP (application services) + DOM (purchase intent domain) + INF (service adapters)

#### Technical Context

**Endpoints**:

```
POST   /api/v1/purchases/intent
       Body: {
         "vehicle_id": "uuid",
         "contact_preference": "whatsapp|email|phone",
         "financing_interest": true,
         "insurance_interest": true,
         "comments": "optional"
       }
       Response: 201 PurchaseIntentResponse | 409 VehicleAlreadyReserved | 400 ValidationError

POST   /api/v1/purchases/{purchase_id}/reserve
       Response: 200 { "purchase_id": "uuid", "status": "reserved", "reserved_until": "datetime", "reservation_hours": 72 }
       | 409 VehicleAlreadyReserved | 412 InvalidStateTransition

POST   /api/v1/purchases/{purchase_id}/advance
       Body: { "action": "proceed_to_kyc" | "skip_financing" | "skip_insurance" | "confirm" }
       Response: 200 PurchaseStateResponse | 412 InvalidStateTransition

POST   /api/v1/purchases/{purchase_id}/cancel
       Body: { "reason": "changed_mind" | "found_better" | "price_too_high" | "other", "comments": "" }
       Response: 200 { "status": "cancelled", "cancelled_at": "datetime" }

GET    /api/v1/purchases/{purchase_id}
       Response: 200 PurchaseDetailResponse

GET    /api/v1/purchases/me
       Query params: ?status=active|completed|cancelled&page=1&per_page=10
       Response: 200 PaginatedPurchaseList

GET    /api/v1/purchases/{purchase_id}/timeline
       Response: 200 PurchaseTimeline

GET    /api/v1/purchases/{purchase_id}/documents
       Response: 200 PurchaseDocuments

GET    /api/v1/purchases/vehicle/{vehicle_id}/availability
       Response: 200 { "available": true|false, "reserved_by_current_user": false, "reserved_until": null }
```

**Data Models**:

```python
# DOM Layer - domain/models/purchase.py
class Purchase:
    id: UUID
    user_id: UUID
    vehicle_id: UUID
    status: PurchaseStatus
    contact_preference: str
    financing_interest: bool
    insurance_interest: bool
    comments: Optional[str]
    reserved_at: Optional[datetime]
    reserved_until: Optional[datetime]
    kyc_verified_at: Optional[datetime]
    financing_approved_at: Optional[datetime]
    insurance_confirmed_at: Optional[datetime]
    confirmed_at: Optional[datetime]
    completed_at: Optional[datetime]
    cancelled_at: Optional[datetime]
    cancellation_reason: Optional[str]
    created_at: datetime
    updated_at: datetime
    version: int  # optimistic locking

class PurchaseStatus(Enum):
    INTENT = "intent"
    RESERVED = "reserved"
    KYC_PENDING = "kyc_pending"
    FINANCING = "financing"
    INSURANCE = "insurance"
    CONFIRMED = "confirmed"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    EXPIRED = "expired"
    REJECTED = "rejected"

class PurchaseTransition:
    id: UUID
    purchase_id: UUID
    from_status: PurchaseStatus
    to_status: PurchaseStatus
    triggered_by: str  # user_id or "system"
    trigger_reason: str
    metadata: dict
    created_at: datetime

class ReservationConfig:
    vehicle_category: str
    reservation_hours: int  # 24 for economy, 48 for mid, 72 for luxury
    max_extensions: int
    extension_hours: int
```

#### Acceptance Criteria

1. **AC-001**: POST `/api/v1/purchases/intent` creates a purchase intent for the authenticated user and the specified vehicle. Returns 201 with the purchase object in `intent` status. Returns 409 if the vehicle is already reserved by another user. A user cannot have more than one active purchase intent for the same vehicle.
2. **AC-002**: POST `/api/v1/purchases/{purchase_id}/reserve` transitions the purchase from `intent` to `reserved` status. The vehicle is locked in SVC-VEH (preventing other reservations). The `reserved_until` timestamp is set based on the vehicle category: 24h for economy, 48h for mid-range, 72h for luxury.
3. **AC-003**: Vehicle reservation uses optimistic locking (`version` field) to prevent race conditions. If two users attempt to reserve the same vehicle simultaneously, only the first succeeds; the second receives 409.
4. **AC-004**: POST `/api/v1/purchases/{purchase_id}/advance` moves the purchase to the next valid state based on the `action` parameter. Invalid transitions return 412 with `{ "error": "invalid_transition", "current_status": "...", "requested_action": "...", "valid_actions": [...] }`.
5. **AC-005**: POST `/api/v1/purchases/{purchase_id}/cancel` transitions any non-terminal state to `cancelled`. The cancellation reason is required (enum) and optional comments are stored. The vehicle lock in SVC-VEH is released immediately upon cancellation.
6. **AC-006**: Every state transition is recorded in the `PurchaseTransition` audit log with: from_status, to_status, triggered_by (user ID or "system" for auto-transitions), trigger_reason, and metadata (e.g., IP address, user agent). The audit log is append-only and immutable.
7. **AC-007**: WRK-NTF worker runs every 5 minutes and checks for expired reservations. Purchases in `reserved` status past their `reserved_until` timestamp are automatically transitioned to `expired`. The user receives a notification. The vehicle lock is released.
8. **AC-008**: GET `/api/v1/purchases/{purchase_id}/timeline` returns a chronological list of all state transitions for the purchase, including timestamps, actors, and human-readable descriptions. This feeds the frontend timeline component.
9. **AC-009**: GET `/api/v1/purchases/me` returns the authenticated user's purchases, filterable by status group: `active` (intent through confirmed), `completed`, `cancelled` (includes expired). Default is `active`. Paginated.
10. **AC-010**: GET `/api/v1/purchases/vehicle/{vehicle_id}/availability` returns the vehicle's availability status. If reserved by the current user, `reserved_by_current_user: true` and the countdown timer data are included.
11. **AC-011**: When a purchase transitions to `kyc_pending`, the system checks SVC-KYC for the user's current KYC status. If KYC is already `approved` and not expired, the purchase automatically advances to `financing` (or `insurance` if financing is skipped).
12. **AC-012**: Each state transition triggers a webhook-style event published to Redis pub/sub. SVC-NTF subscribes and sends appropriate notifications (email, push, SMS) for: reservation confirmed, reservation expiring (1 hour warning), KYC needed, purchase confirmed, purchase completed.
13. **AC-013**: The API supports idempotent operations: re-submitting a reserve request for an already-reserved purchase (by the same user) returns 200 with the current state, not 409 or a duplicate reservation.
14. **AC-014**: All endpoints require JWT authentication. A user can only access their own purchases. Admin users (via SVC-ADM) can access any purchase. Unauthorized access returns 403.

#### Definition of Done
- All endpoints implemented with proper state validation
- State machine transitions enforced at the domain layer
- Optimistic locking preventing race conditions
- Audit log capturing all transitions
- Auto-expiration via WRK-NTF worker
- Vehicle locking/unlocking via SVC-VEH integration
- Webhook events published for all transitions
- Unit tests for state machine (all valid and invalid transitions)
- Integration tests for complete purchase flows
- Load test: 50 concurrent reservation attempts on same vehicle, exactly 1 succeeds

#### Technical Notes
- State machine validation should be a pure domain function: `def can_transition(current: PurchaseStatus, target: PurchaseStatus) -> bool`.
- Use PostgreSQL advisory locks or SELECT FOR UPDATE for the reservation race condition, in addition to optimistic locking.
- Redis pub/sub for webhook events; consider using Redis Streams for durability.
- The `version` field increments on every update; use `WHERE version = :expected_version` in the UPDATE query.

#### Dependencies
- SVC-VEH (port 5012): Vehicle locking/unlocking
- SVC-KYC (port 5014): KYC status check
- SVC-NTF (port 5017): Status change notifications
- SVC-FIN (port 5015): Financing availability check
- SVC-INS (port 5016): Insurance availability check
- WRK-NTF: Auto-expiration worker
- Redis 7: Pub/sub for events, Celery broker

---

### [MKT-BE-013][SVC-PUR-DOM] Motor de Estado de Compra - State Machine

**Description**:
Implement the core purchase state machine as a pure domain component within SVC-PUR. The state machine defines all valid states, transitions, guards (preconditions), actions (side effects), and timeout rules. It is the single source of truth for purchase flow logic and is designed to be fully unit-testable with no infrastructure dependencies.

**Microservice**: SVC-PUR (port 5013)
**Layer**: DOM (domain models and services)

#### Technical Context

**State Machine Implementation**:

```python
# DOM Layer - domain/services/purchase_state_machine.py
from enum import Enum
from dataclasses import dataclass
from typing import Callable, Optional, List

class PurchaseStatus(Enum):
    INTENT = "intent"
    RESERVED = "reserved"
    KYC_PENDING = "kyc_pending"
    FINANCING = "financing"
    INSURANCE = "insurance"
    CONFIRMED = "confirmed"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    EXPIRED = "expired"
    REJECTED = "rejected"

class PurchaseAction(Enum):
    RESERVE = "reserve"
    PROCEED_TO_KYC = "proceed_to_kyc"
    KYC_APPROVED = "kyc_approved"
    KYC_REJECTED = "kyc_rejected"
    PROCEED_TO_FINANCING = "proceed_to_financing"
    SKIP_FINANCING = "skip_financing"
    FINANCING_APPROVED = "financing_approved"
    PROCEED_TO_INSURANCE = "proceed_to_insurance"
    SKIP_INSURANCE = "skip_insurance"
    INSURANCE_CONFIRMED = "insurance_confirmed"
    CONFIRM = "confirm"
    COMPLETE = "complete"
    CANCEL = "cancel"
    EXPIRE = "expire"
    RESUBMIT_KYC = "resubmit_kyc"

@dataclass
class Transition:
    from_status: PurchaseStatus
    to_status: PurchaseStatus
    action: PurchaseAction
    guard: Optional[Callable] = None  # Precondition check
    on_enter: Optional[Callable] = None  # Side effect on entering new state
    timeout_hours: Optional[int] = None  # Auto-timeout for target state

class PurchaseStateMachine:
    TRANSITIONS: List[Transition] = [
        Transition(PurchaseStatus.INTENT, PurchaseStatus.RESERVED, PurchaseAction.RESERVE,
                   guard=lambda ctx: ctx.vehicle_available, timeout_hours=72),
        Transition(PurchaseStatus.INTENT, PurchaseStatus.CANCELLED, PurchaseAction.CANCEL),
        Transition(PurchaseStatus.RESERVED, PurchaseStatus.KYC_PENDING, PurchaseAction.PROCEED_TO_KYC,
                   timeout_hours=48),
        Transition(PurchaseStatus.RESERVED, PurchaseStatus.CANCELLED, PurchaseAction.CANCEL),
        Transition(PurchaseStatus.RESERVED, PurchaseStatus.EXPIRED, PurchaseAction.EXPIRE),
        Transition(PurchaseStatus.KYC_PENDING, PurchaseStatus.FINANCING, PurchaseAction.KYC_APPROVED),
        Transition(PurchaseStatus.KYC_PENDING, PurchaseStatus.REJECTED, PurchaseAction.KYC_REJECTED),
        Transition(PurchaseStatus.REJECTED, PurchaseStatus.KYC_PENDING, PurchaseAction.RESUBMIT_KYC,
                   timeout_hours=48),
        Transition(PurchaseStatus.FINANCING, PurchaseStatus.INSURANCE, PurchaseAction.FINANCING_APPROVED),
        Transition(PurchaseStatus.FINANCING, PurchaseStatus.INSURANCE, PurchaseAction.SKIP_FINANCING),
        Transition(PurchaseStatus.FINANCING, PurchaseStatus.CANCELLED, PurchaseAction.CANCEL),
        Transition(PurchaseStatus.INSURANCE, PurchaseStatus.CONFIRMED, PurchaseAction.INSURANCE_CONFIRMED),
        Transition(PurchaseStatus.INSURANCE, PurchaseStatus.CONFIRMED, PurchaseAction.SKIP_INSURANCE),
        Transition(PurchaseStatus.INSURANCE, PurchaseStatus.CANCELLED, PurchaseAction.CANCEL),
        Transition(PurchaseStatus.CONFIRMED, PurchaseStatus.COMPLETED, PurchaseAction.COMPLETE,
                   timeout_hours=168),  # 7 days
        Transition(PurchaseStatus.CONFIRMED, PurchaseStatus.CANCELLED, PurchaseAction.CANCEL),
    ]

    def get_valid_actions(self, current_status: PurchaseStatus) -> List[PurchaseAction]: ...
    def can_transition(self, current: PurchaseStatus, action: PurchaseAction) -> bool: ...
    def execute_transition(self, purchase: Purchase, action: PurchaseAction, context: dict) -> TransitionResult: ...
    def get_timeout(self, status: PurchaseStatus) -> Optional[int]: ...
```

#### Acceptance Criteria

1. **AC-001**: The state machine defines exactly 10 states: intent, reserved, kyc_pending, financing, insurance, confirmed, completed, cancelled, expired, rejected. Terminal states are: completed, cancelled, expired.
2. **AC-002**: The state machine defines all 16 valid transitions as listed in the TRANSITIONS table. Any transition not explicitly defined is invalid and raises `InvalidTransitionError`.
3. **AC-003**: `get_valid_actions(status)` returns the list of valid actions for a given status. For example, `get_valid_actions(PurchaseStatus.RESERVED)` returns `[PROCEED_TO_KYC, CANCEL, EXPIRE]`.
4. **AC-004**: `can_transition(current, action)` returns `True` if the transition is valid and all guards pass. Returns `False` otherwise. This is a pure function with no side effects.
5. **AC-005**: Guard functions receive a context dictionary with: `vehicle_available`, `kyc_status`, `financing_approved`, `insurance_confirmed`, `user_verified`. Guards are evaluated before the transition executes. If a guard fails, the transition is rejected with a descriptive error.
6. **AC-006**: `execute_transition(purchase, action, context)` validates the transition, evaluates guards, updates the purchase status, records the transition in the audit log, and returns a `TransitionResult` containing: `success`, `new_status`, `transition_record`, `side_effects` (list of actions to execute, e.g., "send_notification", "lock_vehicle").
7. **AC-007**: The state machine supports timeout configuration per state: reserved=72h (configurable), kyc_pending=48h, confirmed=168h (7 days). `get_timeout(status)` returns the timeout in hours or None for states without timeouts.
8. **AC-008**: The `CANCEL` action is valid from any non-terminal state (intent, reserved, kyc_pending, financing, insurance, confirmed). Attempting to cancel a terminal state returns `InvalidTransitionError`.
9. **AC-009**: The `EXPIRE` action is only valid from `reserved` status and can only be triggered by the system (not by user action). The context must include `triggered_by: "system"`.
10. **AC-010**: The `RESUBMIT_KYC` action transitions from `rejected` back to `kyc_pending`, allowing the user to re-upload documents. A maximum of 3 resubmissions is enforced via a counter in the purchase metadata.
11. **AC-011**: The state machine is a pure domain component with zero dependencies on Flask, SQLAlchemy, Redis, or any infrastructure. It operates only on domain objects and plain Python types. This ensures it is fully unit-testable.
12. **AC-012**: Side effects (notifications, vehicle locking, webhook events) are returned as a list of `SideEffect` objects from `execute_transition()`, not executed inline. The application layer (APP) is responsible for executing side effects, maintaining separation of concerns.
13. **AC-013**: The state machine validates that financing and insurance steps can be skipped (`SKIP_FINANCING`, `SKIP_INSURANCE`) only if the user explicitly opted out. The `financing_interest` and `insurance_interest` flags from the purchase intent are checked as guards.

#### Definition of Done
- State machine implemented as a pure domain service
- All 10 states and 16 transitions defined
- Guard functions for all conditional transitions
- Side effect declarations (not execution) for all transitions
- 100% unit test coverage of all transitions (valid and invalid)
- Property-based tests: no sequence of valid actions can reach an undefined state
- No infrastructure imports in the domain layer
- Transition audit records generated for every state change

#### Technical Notes
- The state machine pattern can be implemented using a simple dictionary lookup or a library like `transitions`.
- Guard functions should be composable: `guard=all_of(vehicle_available, user_verified)`.
- Side effects are value objects (data classes), not callables. Example: `SideEffect(type="notification", payload={"template": "reservation_confirmed", "user_id": "..."})`.
- Consider using an event-sourcing approach where the purchase state is derived from the sequence of transitions.
- Timeout enforcement is handled by the infrastructure layer (WRK-NTF worker), not the state machine itself. The state machine only declares timeouts.

#### Dependencies
- None (pure domain component)

---

### [MKT-FE-011][FE-FEAT-PRF] Wishlist - Favoritos con Notificaciones de Precio

**Description**:
Build Angular 18 standalone components for managing the user's vehicle wishlist. The feature includes a heart toggle button (usable on any vehicle card across the app), a dedicated wishlist page with sorting and price change indicators, a badge counter in the navigation, and real-time price alert notifications. All state is managed via Angular signals with optimistic UI updates.

**Frontend Module**: FE-FEAT-PRF (Profile Feature)
**Framework**: Angular 18 (standalone components, signals)
**Styling**: Tailwind CSS v4

#### Technical Context

**Component Structure**:

```
src/app/features/profile/
  components/
    wishlist/
      wishlist-page.component.ts              # Full wishlist page
      wishlist-page.component.html
      wishlist-item-card.component.ts          # Individual vehicle in wishlist
      wishlist-summary.component.ts            # Stats bar (total, value, alerts)
      wishlist-share-dialog.component.ts       # Share link generation modal
  shared/
    components/
      favorite-toggle/
        favorite-toggle.component.ts           # Heart button (used globally)
      wishlist-badge/
        wishlist-badge.component.ts            # Nav bar badge with count
  services/
    wishlist.service.ts                        # HTTP calls to SVC-USR
  store/
    wishlist.store.ts                          # Global signal store
```

**Signal Store**:

```typescript
// wishlist.store.ts (global, provided in root)
@Injectable({ providedIn: 'root' })
export class WishlistStore {
  items = signal<WishlistItem[]>([]);
  loading = signal<boolean>(false);
  totalCount = signal<number>(0);
  favoriteIds = signal<Set<string>>(new Set());

  // Computed
  hasItems = computed(() => this.totalCount() > 0);
  priceDropCount = computed(() =>
    this.items().filter(i => i.price_change_percent < 0).length
  );
  totalValue = computed(() =>
    this.items().reduce((sum, i) => sum + i.current_price, 0)
  );

  // Methods
  isFavorited(vehicleId: string): boolean {
    return this.favoriteIds().has(vehicleId);
  }

  toggleFavorite(vehicleId: string): void { /* optimistic update */ }
  loadWishlist(page: number, sortBy: string): void { }
  shareWishlist(vehicleIds: string[], expiryDays: number): void { }
}
```

#### Acceptance Criteria

1. **AC-001**: The `favorite-toggle` component renders a heart icon that is outlined when not favorited and filled (solid red) when favorited. Clicking toggles the state via the `/toggle` endpoint. The component accepts a `vehicleId` input and can be placed on any vehicle card in the application.
2. **AC-002**: The toggle performs an optimistic UI update: the heart fills immediately on click, and if the API call fails, the state reverts and a toast error is shown. The toggle is debounced (300ms) to prevent rapid double-taps.
3. **AC-003**: The navigation bar displays a `wishlist-badge` component showing the total wishlist count. The badge updates in real-time when items are added/removed. If the count is 0, the badge is hidden. If > 99, it shows "99+".
4. **AC-004**: The wishlist page displays all favorited vehicles as cards in a responsive grid (1 column mobile, 2 tablet, 3 desktop). Each card shows: vehicle thumbnail, title, current price, price at addition, price change percentage (green for increase, red for decrease with arrow icon), date added, and a remove button.
5. **AC-005**: Price change is displayed prominently: a green upward arrow with "+X%" for price increases, a red downward arrow with "-X%" for decreases, and a gray dash for no change. Vehicles with price drops > 5% have a "Price Drop!" badge.
6. **AC-006**: The wishlist page has a sort dropdown with options: "Recently Added" (default), "Biggest Price Drop", "Lowest Price", "Highest Price". Sorting calls the API with the appropriate `sort_by` parameter and updates the list.
7. **AC-007**: A summary bar at the top of the wishlist page shows: total items, total estimated value (formatted as MXN currency), number of items with price drops, and number of active price alerts. Data comes from the `/wishlist/summary` endpoint.
8. **AC-008**: A "Share Wishlist" button opens a dialog where the user can select which vehicles to include (checkboxes, default all) and set expiry (1, 7, or 30 days). On submit, the share URL is generated and displayed with a "Copy Link" button. The dialog shows a success state with the URL.
9. **AC-009**: When the user receives a price alert notification (via push notification or in-app), clicking it navigates to the wishlist page with the affected vehicle highlighted (scrolled into view with a brief highlight animation).
10. **AC-010**: The wishlist page shows an empty state when no vehicles are favorited, with a message "Your wishlist is empty" and a call-to-action button linking to the vehicle search page.
11. **AC-011**: The `favoriteIds` signal is loaded on app initialization (after login) so that heart toggles across the app reflect the correct state immediately without waiting for the full wishlist to load.
12. **AC-012**: The wishlist supports infinite scroll or pagination. Initial load fetches 20 items. Scrolling to the bottom loads the next page. A loading spinner appears during pagination.
13. **AC-013**: All wishlist interactions are accessible: heart toggle has `aria-label="Add to favorites"` / `"Remove from favorites"`, wishlist badge has `aria-label="Wishlist: N items"`, and keyboard navigation works for all interactive elements.

#### Definition of Done
- Favorite toggle component working globally on all vehicle cards
- Wishlist page with sorting, price indicators, and share functionality
- Navigation badge reflecting real-time count
- Optimistic UI updates with error rollback
- Signal-based state management (no RxJS subscriptions in components)
- Unit tests for WishlistStore, toggle logic, price formatting
- Responsive layout tested on mobile/tablet/desktop
- Accessibility audit passed (ARIA labels, keyboard navigation)

#### Technical Notes
- The `WishlistStore` is `providedIn: 'root'` so it persists across route navigation.
- On app initialization, call a lightweight endpoint to load just the `favoriteIds` set (not the full wishlist data). This avoids heavy API calls on every page load.
- Use `@HostListener('click')` or `(click)` binding on the heart toggle, not a form submission.
- Price formatting should use Angular's `CurrencyPipe` with locale `'es-MX'` and currency `'MXN'`.

#### Dependencies
- SVC-USR API (MKT-BE-011): All wishlist endpoints
- SVC-NTF (port 5017): Push notifications for price alerts
- Angular CDK: a11y module for focus management

---

### [MKT-FE-012][FE-FEAT-PUR] Wizard de Compra Multi-Step

**Description**:
Build a multi-step purchase wizard as an Angular 18 standalone component. The wizard guides the user through 5 steps: (1) Confirm Vehicle, (2) KYC Verification (if needed), (3) Financing (optional), (4) Insurance (optional), (5) Summary & Confirm. The wizard maintains state across steps using signals, validates each step before allowing progression, and communicates with SVC-PUR to advance the purchase state machine. Steps that are not applicable (KYC already approved, financing/insurance not desired) are automatically skipped.

**Frontend Module**: FE-FEAT-PUR (Purchase Feature)
**Framework**: Angular 18 (standalone components, signals)
**Styling**: Tailwind CSS v4

#### Technical Context

**Component Structure**:

```
src/app/features/purchase/
  components/
    purchase-wizard/
      purchase-wizard-page.component.ts        # Wizard container with step management
      purchase-wizard-page.component.html
      wizard-stepper/
        wizard-stepper.component.ts             # Visual step indicator bar
      step-confirm-vehicle/
        step-confirm-vehicle.component.ts       # Step 1: Vehicle details + confirm
      step-kyc/
        step-kyc.component.ts                   # Step 2: KYC status / upload redirect
      step-financing/
        step-financing.component.ts             # Step 3: Financing options
      step-insurance/
        step-insurance.component.ts             # Step 4: Insurance quotes
      step-summary/
        step-summary.component.ts               # Step 5: Final summary + confirm
  services/
    purchase-wizard.service.ts
  store/
    purchase-wizard.store.ts
  guards/
    purchase-step.guard.ts                      # Prevents accessing future steps directly
```

**Signal Store**:

```typescript
// purchase-wizard.store.ts
export class PurchaseWizardStore {
  // Core state
  purchaseId = signal<string | null>(null);
  currentStep = signal<number>(1);
  purchaseStatus = signal<PurchaseStatus>('intent');
  vehicle = signal<VehicleDetail | null>(null);

  // Step states
  steps = signal<WizardStep[]>([
    { number: 1, label: 'Confirm Vehicle', status: 'active', required: true, skippable: false },
    { number: 2, label: 'Identity Verification', status: 'pending', required: true, skippable: false },
    { number: 3, label: 'Financing', status: 'pending', required: false, skippable: true },
    { number: 4, label: 'Insurance', status: 'pending', required: false, skippable: true },
    { number: 5, label: 'Summary & Confirm', status: 'pending', required: true, skippable: false },
  ]);

  // Step-specific data
  kycStatus = signal<KycStatus | null>(null);
  financingOptions = signal<FinancingOption[]>([]);
  selectedFinancing = signal<FinancingOption | null>(null);
  insuranceQuotes = signal<InsuranceQuote[]>([]);
  selectedInsurance = signal<InsuranceQuote | null>(null);

  // Computed
  isLastStep = computed(() => this.currentStep() === this.visibleSteps().length);
  canProceed = computed(() => this.currentStepValid());
  visibleSteps = computed(() => this.steps().filter(s => s.status !== 'skipped'));
  completionPercent = computed(() => {
    const completed = this.steps().filter(s => s.status === 'completed').length;
    return Math.round((completed / this.visibleSteps().length) * 100);
  });
}
```

#### Acceptance Criteria

1. **AC-001**: The wizard displays a horizontal stepper at the top showing all applicable steps with their labels, numbers, and status (pending/active/completed/skipped). The current step is highlighted. Completed steps show a checkmark. Skipped steps are visually distinct (grayed out, dashed border).
2. **AC-002**: **Step 1 - Confirm Vehicle**: Displays the vehicle's full details (image gallery, title, price, specs, seller info) and a reservation summary (reservation duration, expiry countdown timer). A "Confirm & Continue" button creates the purchase intent (if not already created) and advances to Step 2.
3. **AC-003**: **Step 2 - KYC Verification**: Checks the user's KYC status via SVC-KYC. If KYC is `approved` and not expired, this step shows "Verified" with a green checkmark and auto-advances to Step 3 after 2 seconds. If KYC is `not_started` or `expired`, it shows instructions and a button to navigate to the KYC upload flow (separate route). If `in_review`, it shows a waiting state with estimated time.
4. **AC-004**: **Step 3 - Financing (Optional)**: If the user indicated `financing_interest: true`, displays available financing options from SVC-FIN (monthly payment, APR, term, total cost). The user selects an option or clicks "Skip - Pay Cash". If `financing_interest: false`, this step is automatically skipped.
5. **AC-005**: **Step 4 - Insurance (Optional)**: If the user indicated `insurance_interest: true`, displays insurance quotes from SVC-INS (coverage type, monthly premium, deductible, provider). The user selects a quote or clicks "Skip - I'll insure separately". If `insurance_interest: false`, this step is automatically skipped.
6. **AC-006**: **Step 5 - Summary & Confirm**: Displays a complete summary: vehicle details, selected financing (if any), selected insurance (if any), total cost breakdown, estimated delivery timeline. A "Confirm Purchase" button triggers the final confirmation via SVC-PUR. A terms & conditions checkbox must be checked before the button is enabled.
7. **AC-007**: The wizard prevents accessing future steps directly (via URL or browser navigation). A route guard checks that all previous required steps are completed. Attempting to access Step 4 without completing Step 2 redirects to the earliest incomplete step.
8. **AC-008**: The "Back" button on each step navigates to the previous step without losing data. Step data is preserved in the signal store. Going back and forward does not re-trigger API calls if the data is already loaded.
9. **AC-009**: Each step transition calls the SVC-PUR `/advance` endpoint to synchronize the backend state machine. If the backend rejects the transition (412), the wizard shows an error and does not advance. The wizard and backend states are always in sync.
10. **AC-010**: A completion progress bar below the stepper shows the percentage of steps completed (e.g., "40% complete - Step 2 of 5"). The progress updates as steps are completed or skipped.
11. **AC-011**: If the reservation countdown timer reaches zero during the wizard, a modal is displayed: "Your reservation has expired. Please start over." with a button to return to the vehicle detail page. The wizard state is cleared.
12. **AC-012**: The wizard is fully responsive. On mobile, the stepper becomes a compact indicator showing "Step X of Y" with the current step name. Step content takes full width. Navigation buttons are sticky at the bottom.
13. **AC-013**: All form inputs within steps have client-side validation. Invalid fields show inline error messages. The "Continue" button is disabled until all required fields in the current step are valid. Validation rules match the backend API validation.
14. **AC-014**: On browser refresh or navigation away, a confirmation dialog warns "You have an unsaved purchase in progress. Are you sure you want to leave?" The wizard state is persisted to `sessionStorage` and restored on return.

#### Definition of Done
- All 5 wizard steps implemented as standalone components
- Stepper navigation working with step validation
- Backend state machine synchronization on each transition
- Auto-skip logic for optional/pre-completed steps
- Reservation countdown timer functional
- Route guards preventing invalid step access
- Session persistence for wizard state
- Unit tests for step validation, auto-skip logic, timer
- E2E test for complete happy-path flow
- Responsive layout tested on all breakpoints

#### Technical Notes
- Use Angular Router with child routes for each step: `/purchase/:purchaseId/step/1`, etc.
- The countdown timer should use `interval()` from RxJS converted to a signal, updating every second.
- Auto-skip logic: in `ngOnInit` of each step, check if the step should be skipped and call `next()` immediately.
- Session persistence: serialize the wizard store to `sessionStorage` on every state change using `effect()`.
- Consider using Angular's `@defer` for lazy-loading step components that are below the fold.

#### Dependencies
- SVC-PUR API (MKT-BE-012): Purchase intent, reservation, advance endpoints
- SVC-KYC API (MKT-BE-016): KYC status check
- SVC-FIN (port 5015): Financing options
- SVC-INS (port 5016): Insurance quotes
- KYC Upload Flow (MKT-FE-014): Navigation target from Step 2

---

### [MKT-FE-013][FE-FEAT-PUR] Pagina de Tracking de Compra con Timeline

**Description**:
Build a purchase tracking page as an Angular 18 standalone component that displays the complete purchase journey as a visual timeline. The page shows the current status prominently, a vertical timeline of all past and upcoming steps, associated documents, a direct chat link to the seller/support, and countdown timers for time-sensitive states (reservation expiry, KYC deadline). The page supports real-time updates via polling or WebSocket.

**Frontend Module**: FE-FEAT-PUR (Purchase Feature)
**Framework**: Angular 18 (standalone components, signals)
**Styling**: Tailwind CSS v4

#### Technical Context

**Component Structure**:

```
src/app/features/purchase/
  components/
    purchase-tracking/
      purchase-tracking-page.component.ts      # Page-level smart component
      purchase-tracking-page.component.html
      status-header/
        status-header.component.ts              # Large status indicator + countdown
      purchase-timeline/
        purchase-timeline.component.ts          # Vertical timeline
        timeline-event.component.ts             # Individual timeline event
      purchase-documents/
        purchase-documents.component.ts         # Document list with download
      purchase-actions/
        purchase-actions.component.ts           # Context-sensitive action buttons
      purchase-chat/
        purchase-chat-link.component.ts         # Chat integration shortcut
  services/
    purchase-tracking.service.ts
  store/
    purchase-tracking.store.ts
```

**Signal Store**:

```typescript
// purchase-tracking.store.ts
export class PurchaseTrackingStore {
  purchase = signal<PurchaseDetail | null>(null);
  timeline = signal<TimelineEvent[]>([]);
  documents = signal<PurchaseDocument[]>([]);
  loading = signal<boolean>(false);
  pollingActive = signal<boolean>(true);

  // Computed
  currentStatus = computed(() => this.purchase()?.status ?? 'unknown');
  isTerminal = computed(() =>
    ['completed', 'cancelled', 'expired'].includes(this.currentStatus())
  );
  countdown = computed(() => {
    const p = this.purchase();
    if (!p?.reserved_until) return null;
    return differenceInSeconds(new Date(p.reserved_until), new Date());
  });
  nextAction = computed(() => this.determineNextAction());
  progressPercent = computed(() => this.calculateProgress());
}
```

#### Acceptance Criteria

1. **AC-001**: The status header displays the current purchase status as a large, colored badge (green for completed, blue for active states, red for cancelled/expired, yellow for pending action). Below the badge, a one-line description explains what is happening and what the user needs to do next.
2. **AC-002**: For time-sensitive states (reserved, kyc_pending, confirmed), a countdown timer is displayed showing days, hours, minutes, and seconds remaining. The timer updates every second. When less than 1 hour remains, the timer turns red and pulses.
3. **AC-003**: The vertical timeline displays all state transitions chronologically from bottom (oldest) to top (newest). Each event shows: timestamp (relative and absolute), status name, description, actor (user or system), and an icon. Future (expected) steps are shown as grayed-out placeholders above the current step.
4. **AC-004**: Timeline events have different visual treatments: completed events have a solid green circle connector, the current event has a pulsing blue circle, future events have a dashed gray circle, and cancelled/rejected events have a red circle with an X.
5. **AC-005**: The documents section lists all documents associated with the purchase: KYC documents (with status), financing agreement (if applicable), insurance policy (if applicable), purchase confirmation, and vehicle transfer documents. Each document shows: name, upload date, status (pending/approved/rejected), and a download button.
6. **AC-006**: Context-sensitive action buttons appear based on the current status. For `kyc_pending`: "Upload Documents" button. For `financing`: "Review Financing Options" button. For `confirmed`: "Complete Payment" button. For `completed`: "Rate Your Experience" button. For `cancelled`: "Start New Purchase" button.
7. **AC-007**: A "Chat with Seller" button opens a chat window (integration with SVC-CHT on port 5018) pre-populated with the purchase context (vehicle ID, purchase ID). If the purchase is in an active state, a "Chat with Support" button is also available.
8. **AC-008**: The page polls the purchase detail and timeline endpoints every 15 seconds while the purchase is in a non-terminal state. Polling stops when the purchase reaches a terminal state (completed, cancelled, expired). A "Last updated: X seconds ago" indicator shows the data freshness.
9. **AC-009**: When a status change is detected during polling, a toast notification is shown ("Status updated to: Reserved") and the timeline animates the new event sliding in from the top. A subtle sound can optionally play (user preference).
10. **AC-010**: The progress bar at the top of the page shows the overall purchase progress as a percentage based on the state: intent=10%, reserved=25%, kyc_pending=40%, financing=55%, insurance=70%, confirmed=85%, completed=100%.
11. **AC-011**: The page is accessible via `/purchases/:purchaseId/tracking`. If the purchase does not belong to the authenticated user, a 403 page is shown. If the purchase does not exist, a 404 page is shown.
12. **AC-012**: On mobile, the timeline switches from a two-sided layout to a single-column left-aligned layout. The status header and countdown are sticky at the top. Documents and chat sections collapse into accordions.
13. **AC-013**: The tracking page includes a "Cancel Purchase" button (visible for non-terminal states) that shows a confirmation dialog with the cancellation reason form. On confirm, it calls the cancel endpoint and updates the page.
14. **AC-014**: When the purchase is in `completed` state, the page shows a celebration animation (confetti or similar lightweight animation) on first load and displays a summary card with the vehicle photo, final price, and purchase date.

#### Definition of Done
- Tracking page displaying real-time purchase status
- Vertical timeline with past, current, and future events
- Countdown timer working for time-sensitive states
- Document list with download capability
- Chat integration link functional
- Polling updating the page every 15 seconds
- Cancel flow with confirmation dialog
- Unit tests for countdown calculation, progress percentage, status-to-action mapping
- E2E test for page load and status transitions
- Responsive layout tested on all breakpoints
- Accessibility audit passed

#### Technical Notes
- Use `setInterval` or RxJS `timer` converted to signal for the countdown timer. Clean up on destroy.
- Polling can use `effect()` with `untracked()` to avoid circular signal dependencies.
- The celebration animation on completion can use a lightweight library like `canvas-confetti` (< 5KB gzipped).
- Timeline data comes from the `/purchases/:id/timeline` endpoint. Merge with expected future steps client-side.
- Consider using Server-Sent Events (SSE) instead of polling for real-time updates in a future iteration.

#### Dependencies
- SVC-PUR API (MKT-BE-012): Purchase detail, timeline, cancel endpoints
- SVC-CHT (port 5018): Chat integration
- SVC-KYC (port 5014): Document status
- Angular CDK: a11y, overlay for dialogs
