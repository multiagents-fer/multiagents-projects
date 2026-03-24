# [MKT-EP-015] Billing, Planes & Revenue Sharing

**Sprint**: 12-14
**Priority**: Priority 2
**Epic Owner**: Tech Lead
**Estimated Points**: 95
**Teams**: Backend, Frontend, Integration

---

## Resumen del Epic

Este epic implementa el sistema completo de billing y revenue sharing para tenants: planes de suscripcion con diferentes niveles de funcionalidad, tracking de comisiones por transaccion, integracion con pasarela de pagos (Stripe/Conekta), generacion de facturas CFDI, y dashboards de revenue tanto para tenants como para el super admin de AgentsMX. El modelo de revenue soporta suscripcion mensual/anual, comision por venta, o hibrido.

## Dependencias Externas

- EP-011 completado (arquitectura multi-tenant, SVC-TNT con modelo de planes)
- EP-014 completado (sindicacion con commission tracking por transaccion)
- Cuenta Stripe Connect o Conekta configurada
- Proveedor de facturacion electronica CFDI (facturapi.io o similar)
- Datos bancarios de AgentsMX para recibir pagos

---

## User Story 1: [MKT-BE-046][SVC-TNT-DOM] Modelo de Planes y Precios

### Descripcion

Como servicio de tenants, necesito un modelo de datos completo para planes de suscripcion que defina las capacidades, limites y precios de cada nivel. Los planes determinan que features tiene disponibles un tenant, cuantos vehiculos y usuarios puede tener, que tasa de comision paga, y si puede usar custom domain o remover el badge "Powered by AgentsMX".

### Microservicio

- **Nombre**: SVC-TNT
- **Puerto**: 5023
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0
- **Base de datos**: PostgreSQL 15
- **Patron**: Hexagonal Architecture - Domain Layer

### Contexto Tecnico

#### Domain Models

```python
# dom/models/plan.py
from dataclasses import dataclass, field
from typing import Optional
from uuid import UUID, uuid4
from decimal import Decimal

@dataclass
class Plan:
    id: UUID = field(default_factory=uuid4)
    name: str = ""                                # "Free", "Basic", "Pro", "Enterprise"
    slug: str = ""                                # "free", "basic", "pro", "enterprise"
    display_name: str = ""                        # "Plan Basico"
    description: str = ""
    is_active: bool = True
    is_public: bool = True                        # Show in pricing page
    sort_order: int = 0

    # Pricing
    price_monthly_mxn: Decimal = Decimal("0.00")
    price_annual_mxn: Decimal = Decimal("0.00")   # Annual = monthly * 10 (2 months free)
    setup_fee_mxn: Decimal = Decimal("0.00")
    currency: str = "MXN"

    # Limits
    max_vehicles: Optional[int] = 50              # None = unlimited
    max_users: Optional[int] = 3                  # None = unlimited
    max_storage_mb: int = 1000                    # 1GB default
    max_api_calls_month: Optional[int] = None     # None = unlimited

    # Commission Rates
    commission_rate_sale: Decimal = Decimal("0.05")         # 5% default
    commission_rate_financing: Decimal = Decimal("0.02")    # 2% financing referral
    commission_rate_insurance: Decimal = Decimal("0.03")    # 3% insurance referral

    # Features Included
    features_included: list[str] = field(default_factory=list)
    custom_domain_allowed: bool = False
    white_label_badge_removable: bool = False
    custom_css_allowed: bool = False
    custom_html_allowed: bool = False
    api_access: bool = False
    priority_support: bool = False
    dedicated_account_manager: bool = False

    # Metadata
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
```

```python
# dom/models/subscription.py
@dataclass
class Subscription:
    id: UUID = field(default_factory=uuid4)
    tenant_id: UUID = field(default_factory=uuid4)
    plan_id: UUID = field(default_factory=uuid4)
    status: str = "active"                  # active, past_due, cancelled, paused
    billing_cycle: str = "monthly"          # monthly, annual
    current_period_start: datetime = field(default_factory=datetime.utcnow)
    current_period_end: datetime = field(default_factory=datetime.utcnow)
    price_mxn: Decimal = Decimal("0.00")    # Current billing amount
    payment_method_id: Optional[str] = None # Stripe/Conekta payment method
    external_subscription_id: Optional[str] = None  # Stripe/Conekta sub ID
    trial_end: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None
    cancel_reason: Optional[str] = None
    created_at: datetime = field(default_factory=datetime.utcnow)

@dataclass
class Invoice:
    id: UUID = field(default_factory=uuid4)
    tenant_id: UUID = field(default_factory=uuid4)
    subscription_id: Optional[UUID] = None
    invoice_type: str = "subscription"       # subscription, commission, setup
    status: str = "draft"                    # draft, pending, paid, failed, cancelled
    amount_mxn: Decimal = Decimal("0.00")
    tax_mxn: Decimal = Decimal("0.00")       # IVA 16%
    total_mxn: Decimal = Decimal("0.00")
    currency: str = "MXN"
    period_start: Optional[datetime] = None
    period_end: Optional[datetime] = None
    due_date: Optional[datetime] = None
    paid_at: Optional[datetime] = None
    external_invoice_id: Optional[str] = None  # Stripe/Conekta invoice ID
    cfdi_uuid: Optional[str] = None           # CFDI fiscal folio
    cfdi_xml_url: Optional[str] = None
    cfdi_pdf_url: Optional[str] = None
    line_items: list[dict] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.utcnow)
```

#### Plan Definitions

```python
# cfg/plan_definitions.py
from decimal import Decimal

PLAN_DEFINITIONS = {
    "free": {
        "name": "Free",
        "display_name": "Plan Gratuito",
        "description": "Ideal para empezar. Publica hasta 50 vehiculos gratis.",
        "price_monthly_mxn": Decimal("0.00"),
        "price_annual_mxn": Decimal("0.00"),
        "max_vehicles": 50,
        "max_users": 3,
        "max_storage_mb": 1000,
        "commission_rate_sale": Decimal("0.05"),        # 5%
        "commission_rate_financing": Decimal("0.02"),
        "commission_rate_insurance": Decimal("0.03"),
        "features_included": [
            "financing", "insurance", "chat", "favorites",
            "vehicle_comparison", "price_history", "share_social",
            "notifications_email",
        ],
        "custom_domain_allowed": False,
        "white_label_badge_removable": False,
        "custom_css_allowed": False,
        "api_access": False,
        "priority_support": False,
    },
    "basic": {
        "name": "Basic",
        "display_name": "Plan Basico",
        "description": "Para dealers en crecimiento. Subdomain propio y mas vehiculos.",
        "price_monthly_mxn": Decimal("2500.00"),
        "price_annual_mxn": Decimal("25000.00"),        # 10 months (2 free)
        "max_vehicles": 500,
        "max_users": 10,
        "max_storage_mb": 5000,
        "commission_rate_sale": Decimal("0.03"),         # 3%
        "commission_rate_financing": Decimal("0.02"),
        "commission_rate_insurance": Decimal("0.02"),
        "features_included": [
            "financing", "insurance", "chat", "favorites",
            "vehicle_comparison", "price_history", "share_social",
            "notifications_email", "notifications_sms", "kyc_verification",
        ],
        "custom_domain_allowed": False,
        "white_label_badge_removable": False,
        "custom_css_allowed": False,
        "api_access": False,
        "priority_support": False,
    },
    "pro": {
        "name": "Pro",
        "display_name": "Plan Profesional",
        "description": "Para dealers serios. Dominio propio, analytics y sin badge.",
        "price_monthly_mxn": Decimal("8000.00"),
        "price_annual_mxn": Decimal("80000.00"),
        "max_vehicles": None,                            # Unlimited
        "max_users": 50,
        "max_storage_mb": 20000,
        "commission_rate_sale": Decimal("0.02"),          # 2%
        "commission_rate_financing": Decimal("0.015"),
        "commission_rate_insurance": Decimal("0.015"),
        "features_included": [
            "financing", "insurance", "chat", "favorites",
            "vehicle_comparison", "price_history", "share_social",
            "notifications_email", "notifications_sms", "notifications_push",
            "kyc_verification", "analytics", "reports", "seo_tools",
        ],
        "custom_domain_allowed": True,
        "white_label_badge_removable": True,
        "custom_css_allowed": True,
        "api_access": False,
        "priority_support": True,
    },
    "enterprise": {
        "name": "Enterprise",
        "display_name": "Plan Empresarial",
        "description": "Para grandes dealers. Todo ilimitado, soporte dedicado, API.",
        "price_monthly_mxn": Decimal("0.00"),             # Custom pricing
        "price_annual_mxn": Decimal("0.00"),
        "max_vehicles": None,
        "max_users": None,
        "max_storage_mb": 100000,
        "commission_rate_sale": Decimal("0.00"),           # Negotiable
        "commission_rate_financing": Decimal("0.00"),
        "commission_rate_insurance": Decimal("0.00"),
        "features_included": [
            "financing", "insurance", "chat", "favorites",
            "vehicle_comparison", "price_history", "share_social",
            "notifications_email", "notifications_sms", "notifications_push",
            "kyc_verification", "analytics", "reports", "seo_tools",
        ],
        "custom_domain_allowed": True,
        "white_label_badge_removable": True,
        "custom_css_allowed": True,
        "custom_html_allowed": True,
        "api_access": True,
        "priority_support": True,
        "dedicated_account_manager": True,
    },
}
```

#### ORM Models

```sql
CREATE TABLE plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) NOT NULL UNIQUE,
    slug VARCHAR(50) NOT NULL UNIQUE,
    display_name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_public BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,
    price_monthly_mxn NUMERIC(10,2) NOT NULL DEFAULT 0,
    price_annual_mxn NUMERIC(10,2) NOT NULL DEFAULT 0,
    setup_fee_mxn NUMERIC(10,2) NOT NULL DEFAULT 0,
    max_vehicles INTEGER,
    max_users INTEGER,
    max_storage_mb INTEGER NOT NULL DEFAULT 1000,
    max_api_calls_month INTEGER,
    commission_rate_sale NUMERIC(5,4) NOT NULL DEFAULT 0.0500,
    commission_rate_financing NUMERIC(5,4) NOT NULL DEFAULT 0.0200,
    commission_rate_insurance NUMERIC(5,4) NOT NULL DEFAULT 0.0300,
    features_included JSONB NOT NULL DEFAULT '[]',
    custom_domain_allowed BOOLEAN NOT NULL DEFAULT false,
    white_label_badge_removable BOOLEAN NOT NULL DEFAULT false,
    custom_css_allowed BOOLEAN NOT NULL DEFAULT false,
    custom_html_allowed BOOLEAN NOT NULL DEFAULT false,
    api_access BOOLEAN NOT NULL DEFAULT false,
    priority_support BOOLEAN NOT NULL DEFAULT false,
    dedicated_account_manager BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    plan_id UUID NOT NULL REFERENCES plans(id),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    billing_cycle VARCHAR(10) NOT NULL DEFAULT 'monthly',
    current_period_start TIMESTAMP NOT NULL,
    current_period_end TIMESTAMP NOT NULL,
    price_mxn NUMERIC(10,2) NOT NULL,
    payment_method_id VARCHAR(100),
    external_subscription_id VARCHAR(100),
    trial_end TIMESTAMP,
    cancelled_at TIMESTAMP,
    cancel_reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_subscriptions_tenant ON subscriptions(tenant_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);

CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    subscription_id UUID REFERENCES subscriptions(id),
    invoice_number VARCHAR(20) NOT NULL UNIQUE,
    invoice_type VARCHAR(20) NOT NULL DEFAULT 'subscription',
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    subtotal_mxn NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_mxn NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_mxn NUMERIC(12,2) NOT NULL DEFAULT 0,
    currency VARCHAR(3) NOT NULL DEFAULT 'MXN',
    period_start TIMESTAMP,
    period_end TIMESTAMP,
    due_date TIMESTAMP,
    paid_at TIMESTAMP,
    external_invoice_id VARCHAR(100),
    cfdi_uuid VARCHAR(36),
    cfdi_xml_url TEXT,
    cfdi_pdf_url TEXT,
    line_items JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_invoices_tenant ON invoices(tenant_id);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_period ON invoices(period_start, period_end);
```

#### Plan Comparison Logic

```python
# dom/services/plan_service.py
class PlanService:
    """Domain service for plan logic."""

    def can_upgrade(self, current_plan: Plan, target_plan: Plan) -> bool:
        plan_order = {"free": 0, "basic": 1, "pro": 2, "enterprise": 3}
        return plan_order.get(target_plan.slug, 0) > plan_order.get(current_plan.slug, 0)

    def can_downgrade(self, current_plan: Plan, target_plan: Plan,
                      tenant_usage: TenantUsage) -> tuple[bool, list[str]]:
        """Check if downgrade is possible. Returns (can_downgrade, blockers)."""
        blockers = []
        if target_plan.max_vehicles and tenant_usage.vehicle_count > target_plan.max_vehicles:
            blockers.append(
                f"Tienes {tenant_usage.vehicle_count} vehiculos. "
                f"El plan {target_plan.display_name} permite {target_plan.max_vehicles}."
            )
        if target_plan.max_users and tenant_usage.user_count > target_plan.max_users:
            blockers.append(
                f"Tienes {tenant_usage.user_count} usuarios. "
                f"El plan {target_plan.display_name} permite {target_plan.max_users}."
            )
        if not target_plan.custom_domain_allowed and tenant_usage.has_custom_domain:
            blockers.append(
                "Tu dominio personalizado se desactivara con este plan."
            )
        return (len(blockers) == 0, blockers)

    def calculate_proration(self, current_sub: Subscription,
                             new_plan: Plan) -> Decimal:
        """Calculate prorated amount for mid-cycle upgrade."""
        days_remaining = (current_sub.current_period_end - datetime.utcnow()).days
        total_days = (current_sub.current_period_end - current_sub.current_period_start).days
        if total_days == 0:
            return new_plan.price_monthly_mxn

        daily_rate_current = current_sub.price_mxn / Decimal(total_days)
        daily_rate_new = new_plan.price_monthly_mxn / Decimal(total_days)
        proration = (daily_rate_new - daily_rate_current) * Decimal(days_remaining)
        return max(proration, Decimal("0.00"))
```

### Criterios de Aceptacion

1. **AC-001**: La tabla plans contiene los 4 planes predefinidos (Free, Basic, Pro, Enterprise) con todos los campos: precios (monthly/annual en MXN), limites (vehicles/users/storage), comisiones (sale/financing/insurance), features incluidos, y flags de capacidades (custom_domain, badge_removable, custom_css, api_access).

2. **AC-002**: Plan Free: $0/mes, 50 vehiculos, 3 usuarios, 1GB storage, comision 5%, features basicos (financing, insurance, chat, favorites), sin custom domain, badge obligatorio. Verificar que un tenant Free no puede activar analytics ni reports.

3. **AC-003**: Plan Basic: $2,500/mes o $25,000/anual (2 meses gratis), 500 vehiculos, 10 usuarios, 5GB storage, comision 3%, features basicos + SMS + KYC. Sin custom domain, badge obligatorio. Verificar que el precio annual es exactamente 10x el mensual.

4. **AC-004**: Plan Pro: $8,000/mes o $80,000/anual, vehiculos ilimitados, 50 usuarios, 20GB storage, comision 2%, todos los features, custom domain, badge removible, custom CSS. Verificar que max_vehicles es NULL (unlimited) y no 0.

5. **AC-005**: Plan Enterprise: precios custom (0 en tabla, negociados por ventas), todo ilimitado, comision negociable, API access, soporte dedicado, account manager. Los campos de precio quedan en 0 y se configuran manualmente por el super admin per-tenant.

6. **AC-006**: La entidad Subscription vincula un tenant con un plan: status (active/past_due/cancelled/paused), billing_cycle (monthly/annual), periodo actual (start/end), precio actual, external IDs (Stripe/Conekta). Un tenant tiene maximo 1 subscription activa.

7. **AC-007**: La entidad Invoice almacena cada factura: numero secuencial (INV-2026-00001), tipo (subscription/commission/setup), status (draft/pending/paid/failed/cancelled), montos (subtotal/tax/total en MXN), line_items como JSON, y referencias CFDI (uuid, xml_url, pdf_url).

8. **AC-008**: El PlanService valida upgrades y downgrades: upgrade siempre es posible (Free->Basic, Basic->Pro, etc.). Downgrade solo es posible si el tenant cumple con los limites del plan inferior. Si tiene 234 vehiculos y baja a Free (50 max), retorna blockers con mensaje claro.

9. **AC-009**: El calculo de prorrateo para upgrades mid-cycle es correcto: si un tenant en Basic ($2,500/mes) sube a Pro ($8,000/mes) a mitad de mes, paga la diferencia proporcional a los dias restantes. El calculo usa Decimal para precision monetaria (no float).

10. **AC-010**: El precio annual incluye descuento de 2 meses gratis: Basic annual = $25,000 (no $30,000), Pro annual = $80,000 (no $96,000). Este descuento se calcula como: price_annual = price_monthly * 10.

11. **AC-011**: Los montos se almacenan en NUMERIC(12,2) en PostgreSQL (no FLOAT). El IVA se calcula como 16% del subtotal. Total = subtotal + IVA. Todos los montos se redondean a 2 decimales. Se verifican con tests que usan Decimal para comparaciones exactas.

12. **AC-012**: Los tests unitarios verifican: (a) plan definitions son completas y consistentes, (b) upgrade/downgrade validation, (c) proration calculation con diferentes escenarios (inicio de mes, mitad, final), (d) IVA calculation, (e) invoice number generation es secuencial y unico.

### Definition of Done

- [ ] Tabla plans creada con 4 planes predefinidos
- [ ] Tabla subscriptions creada con indices
- [ ] Tabla invoices creada con numero secuencial
- [ ] PlanService con validacion de upgrade/downgrade
- [ ] Proration calculation implementado
- [ ] Todos los montos usan Decimal (no float)
- [ ] Tests unitarios con precision monetaria
- [ ] Cobertura >= 90% en domain layer
- [ ] Code review aprobado

### Notas Tecnicas

- Usar Decimal de Python y NUMERIC de PostgreSQL para TODOS los montos financieros
- Los planes se seedean en la migracion; cambios de precio se hacen via migracion (no UI)
- Para Enterprise, los precios custom se configuran via super admin en TenantConfig, no en Plan
- El invoice_number sigue formato INV-YYYY-NNNNN con secuencia global
- IVA en Mexico es 16%; si se expande a otros paises, hacer el % configurable

### Dependencias

- EP-011 Story MKT-BE-031 completada (modelo de tenant)
- PostgreSQL 15 con extension uuid-ossp

---

## User Story 2: [MKT-BE-047][SVC-TNT-API] API de Billing y Suscripciones

### Descripcion

Como servicio de billing, necesito una API que permita a los tenants gestionar su suscripcion: ver su plan actual, suscribirse a un plan, cambiar de plan (upgrade/downgrade), ver historial de facturas, y gestionar su metodo de pago. La API se integra con Stripe/Conekta para procesamiento de pagos y gestiona el ciclo de vida completo de la suscripcion.

### Microservicio

- **Nombre**: SVC-TNT
- **Puerto**: 5023
- **Tecnologia**: Python 3.11, Flask 3.0, stripe-python / conekta-python
- **Base de datos**: PostgreSQL 15, Redis 7
- **Patron**: Hexagonal Architecture - API & Application Layer

### Contexto Tecnico

#### Endpoints

```
# Billing Management (tenant_admin or tenant_owner)
GET    /api/v1/billing/plans                  -> List available plans with comparison
GET    /api/v1/billing/current                -> Current subscription details
POST   /api/v1/billing/subscribe              -> Create subscription to a plan
PUT    /api/v1/billing/upgrade                -> Upgrade to higher plan
PUT    /api/v1/billing/downgrade              -> Downgrade to lower plan
POST   /api/v1/billing/cancel                 -> Cancel subscription
GET    /api/v1/billing/invoices               -> Invoice history
GET    /api/v1/billing/invoices/:id           -> Invoice detail with line items
GET    /api/v1/billing/invoices/:id/pdf       -> Download invoice PDF
GET    /api/v1/billing/commissions            -> Commission breakdown
GET    /api/v1/billing/payment-methods        -> List payment methods
POST   /api/v1/billing/payment-methods        -> Add payment method
DELETE /api/v1/billing/payment-methods/:id    -> Remove payment method

# Webhook (internal, called by Stripe/Conekta)
POST   /api/v1/webhooks/stripe                -> Stripe webhook handler
POST   /api/v1/webhooks/conekta               -> Conekta webhook handler

# Admin (super_admin)
GET    /api/v1/admin/billing/overview          -> Global billing overview (MRR, ARR, etc.)
GET    /api/v1/admin/billing/tenants           -> Revenue per tenant
POST   /api/v1/admin/billing/tenants/:id/credit -> Apply credit to tenant
```

#### Request/Response - List Plans

```json
// GET /api/v1/billing/plans
{
  "data": {
    "plans": [
      {
        "id": "plan-free-uuid",
        "name": "Free",
        "display_name": "Plan Gratuito",
        "description": "Ideal para empezar. Publica hasta 50 vehiculos gratis.",
        "price_monthly_mxn": 0,
        "price_annual_mxn": 0,
        "limits": {
          "vehicles": 50,
          "users": 3,
          "storage_mb": 1000
        },
        "commission_rate": "5%",
        "features": {
          "financing": true,
          "insurance": true,
          "chat": true,
          "analytics": false,
          "reports": false,
          "custom_domain": false,
          "remove_badge": false,
          "api_access": false
        },
        "is_current": true,
        "is_recommended": false
      },
      {
        "id": "plan-basic-uuid",
        "name": "Basic",
        "display_name": "Plan Basico",
        "price_monthly_mxn": 2500,
        "price_annual_mxn": 25000,
        "annual_savings_mxn": 5000,
        "annual_savings_percent": 17,
        "limits": {
          "vehicles": 500,
          "users": 10,
          "storage_mb": 5000
        },
        "commission_rate": "3%",
        "features": {
          "financing": true,
          "insurance": true,
          "chat": true,
          "analytics": false,
          "reports": false,
          "custom_domain": false,
          "remove_badge": false,
          "api_access": false
        },
        "is_current": false,
        "is_recommended": true
      }
    ],
    "current_plan": "free",
    "billing_cycle": null
  }
}
```

#### Request/Response - Subscribe

```json
// POST /api/v1/billing/subscribe
{
  "plan_id": "plan-basic-uuid",
  "billing_cycle": "monthly",
  "payment_method_token": "tok_stripe_abc123"
}

// Response 200
{
  "data": {
    "subscription": {
      "id": "sub-xyz789",
      "plan": "Basic",
      "status": "active",
      "billing_cycle": "monthly",
      "price_mxn": 2500.00,
      "current_period_start": "2026-03-24T00:00:00Z",
      "current_period_end": "2026-04-24T00:00:00Z",
      "next_invoice_date": "2026-04-24T00:00:00Z",
      "next_invoice_amount_mxn": 2900.00
    },
    "invoice": {
      "id": "inv-abc123",
      "invoice_number": "INV-2026-00042",
      "subtotal_mxn": 2500.00,
      "tax_mxn": 400.00,
      "total_mxn": 2900.00,
      "status": "paid",
      "cfdi_pdf_url": "https://cdn.agentsmx.com/invoices/INV-2026-00042.pdf"
    }
  }
}
```

#### Request/Response - Commission Breakdown

```json
// GET /api/v1/billing/commissions?period=2026-03
{
  "data": {
    "period": "2026-03",
    "summary": {
      "total_sales": 8,
      "total_revenue_mxn": 2450000.00,
      "total_commission_mxn": 73500.00,
      "total_financing_referral_mxn": 24500.00,
      "total_insurance_referral_mxn": 18375.00,
      "total_deductions_mxn": 116375.00,
      "net_revenue_mxn": 2333625.00
    },
    "transactions": [
      {
        "purchase_id": "pur-001",
        "date": "2026-03-15",
        "vehicle": "Toyota Camry 2024",
        "sale_price_mxn": 485000.00,
        "commission_rate": 0.03,
        "commission_mxn": 14550.00,
        "financing_used": true,
        "financing_referral_mxn": 4850.00,
        "insurance_used": false,
        "insurance_referral_mxn": 0.00,
        "total_deduction_mxn": 19400.00,
        "context": "agentsmx"
      }
    ],
    "pagination": {
      "page": 1,
      "page_size": 20,
      "total": 8
    }
  }
}
```

#### Webhook Handling

```python
# api/routes/webhook_routes.py
import stripe

@webhook_bp.route("/api/v1/webhooks/stripe", methods=["POST"])
def handle_stripe_webhook():
    payload = request.get_data()
    sig_header = request.headers.get("Stripe-Signature")

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, STRIPE_WEBHOOK_SECRET
        )
    except (ValueError, stripe.error.SignatureVerificationError):
        abort(400)

    event_type = event["type"]
    data = event["data"]["object"]

    handlers = {
        "invoice.payment_succeeded": handle_payment_success,
        "invoice.payment_failed": handle_payment_failed,
        "customer.subscription.updated": handle_subscription_updated,
        "customer.subscription.deleted": handle_subscription_cancelled,
    }

    handler = handlers.get(event_type)
    if handler:
        handler(data)

    return jsonify({"received": True}), 200
```

### Criterios de Aceptacion

1. **AC-001**: GET /api/v1/billing/plans retorna los 4 planes con toda la informacion: precios (mensual/anual con descuento calculado), limites, comisiones, features. Marca el plan actual del tenant con is_current=true. Marca el plan recomendado con is_recommended=true (el siguiente nivel al actual).

2. **AC-002**: POST /api/v1/billing/subscribe crea una suscripcion en Stripe/Conekta con el plan y ciclo seleccionado. Procesa el primer pago inmediatamente. Si el pago es exitoso, activa la suscripcion, genera factura con CFDI, y actualiza el plan del tenant en la base de datos. Si falla, retorna 402 con detalle del error.

3. **AC-003**: PUT /api/v1/billing/upgrade calcula el prorrateo automaticamente: cobra la diferencia proporcional a los dias restantes del periodo actual e inicia el nuevo plan. Si el tenant tenia Basic a $2,500 y sube a Pro a $8,000 a mitad de mes, cobra ~$2,750 de diferencia. Se genera factura de prorrateo.

4. **AC-004**: PUT /api/v1/billing/downgrade valida que el tenant cumpla los limites del plan inferior ANTES de procesar. Si hay blockers (excede vehiculos o usuarios), retorna 422 con la lista de blockers y no procesa el cambio. El downgrade se efectiviza al final del periodo actual (no inmediato).

5. **AC-005**: POST /api/v1/billing/cancel cancela la suscripcion. El acceso se mantiene hasta el final del periodo actual. Al finalizar, el tenant pasa a plan Free automaticamente. Se requiere cancel_reason (dropdown: "Muy caro", "No lo uso", "Cambio a competencia", "Otro"). Se envia email de confirmacion.

6. **AC-006**: GET /api/v1/billing/invoices retorna historial de facturas paginado con: numero, fecha, tipo (subscription/commission), monto, status (paid/pending/failed), y link de descarga PDF. Filtrable por tipo, status y rango de fechas. Ordenado por fecha descendente.

7. **AC-007**: GET /api/v1/billing/invoices/:id/pdf retorna el PDF de la factura con formato mexicano: datos del emisor (AgentsMX), datos del receptor (tenant), conceptos, subtotal, IVA 16%, total, y si aplica, sello digital CFDI. Content-Type: application/pdf.

8. **AC-008**: GET /api/v1/billing/commissions?period=YYYY-MM retorna el desglose de comisiones del mes: resumen (total ventas, revenue, comisiones, referrals, neto) y detalle por transaccion (vehiculo, precio, tasa, monto comision, financing/insurance referrals, contexto de venta).

9. **AC-009**: El webhook de Stripe maneja los eventos: invoice.payment_succeeded (marcar factura como paid), invoice.payment_failed (marcar como failed, notificar tenant, retry en 3/5/7 dias), customer.subscription.updated (sync cambios), customer.subscription.deleted (cancelar subscription local). El webhook valida firma de Stripe.

10. **AC-010**: Si un pago falla, el sistema implementa retry logic: primer reintento a los 3 dias, segundo a los 5 dias, tercero a los 7 dias. Si los 3 reintentos fallan, la suscripcion se marca como past_due, se notifica al tenant con urgencia, y despues de 15 dias se suspende el tenant.

11. **AC-011**: POST /api/v1/billing/payment-methods acepta un token de Stripe/Conekta y lo asocia al tenant. Solo se permite 1 metodo de pago activo (reemplaza el anterior). Se valida que el metodo de pago sea tarjeta de credito/debito o transferencia SPEI. Retorna ultimos 4 digitos y tipo.

12. **AC-012**: El endpoint admin GET /api/v1/admin/billing/overview retorna metricas globales: MRR (Monthly Recurring Revenue), ARR (Annual Recurring Revenue), churn rate (% cancelaciones del mes), ARPU (Average Revenue Per User), lifetime value promedio, distribucion por plan (count y revenue).

13. **AC-013**: Todos los endpoints de billing requieren rol tenant_owner o tenant_admin. El tenant_owner es el unico que puede cancelar la suscripcion. Ambos pueden ver facturas y comisiones. El super_admin puede ver billing de cualquier tenant y aplicar creditos.

### Definition of Done

- [ ] API de planes, suscripciones y facturas funcional
- [ ] Integracion con Stripe o Conekta para pagos
- [ ] Webhook handler para eventos de pago
- [ ] Proration calculation para upgrades
- [ ] Downgrade validation con blockers
- [ ] Commission breakdown endpoint
- [ ] Payment retry logic implementado
- [ ] Admin billing overview funcional
- [ ] Tests de integracion con Stripe mock
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- Usar stripe-python o conekta-python oficial SDK
- Stripe test mode para desarrollo y staging; live mode solo en produccion
- Los webhooks de Stripe deben ser idempotentes (mismo evento puede llegar multiples veces)
- Almacenar siempre el external_id de Stripe/Conekta para reconciliacion
- Nunca almacenar numeros completos de tarjeta; solo ultimos 4 digitos y brand (Visa, Mastercard)
- CFDI requiere: RFC del emisor, RFC del receptor (opcional para persona fisica), uso de CFDI

### Dependencias

- Story MKT-BE-046 completada (modelo de planes y subscriptions)
- Cuenta Stripe Connect o Conekta configurada con API keys
- EP-014 Story MKT-BE-045 (revenue tracking per transaction)

---

## User Story 3: [MKT-BE-048][SVC-TNT-APP] Calculo de Comisiones y Revenue Sharing

### Descripcion

Como servicio de billing, necesito calcular automaticamente las comisiones de AgentsMX en cada transaccion de venta, referral de financiamiento y referral de seguro. Las comisiones varian por plan del tenant y se registran en la tabla tenant_revenue_entries para reconciliacion mensual. El sistema genera un reporte mensual por tenant con el desglose de comisiones a cobrar o creditos a aplicar.

### Microservicio

- **Nombre**: SVC-TNT (Application Layer)
- **Puerto**: 5023
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0
- **Base de datos**: PostgreSQL 15
- **Patron**: Hexagonal Architecture - Application Layer

### Contexto Tecnico

#### Commission Calculation Flow

```
Purchase Event (SQS)
  |
  v
1. Extract: vehicle_price, tenant_id, has_financing, has_insurance
  |
  v
2. Lookup tenant's plan -> get commission rates
  |
  v
3. Calculate:
   - Sale commission = price * plan.commission_rate_sale
   - Financing referral = price * plan.commission_rate_financing (if applicable)
   - Insurance referral = price * plan.commission_rate_insurance (if applicable)
  |
  v
4. Create TenantRevenueEntry with all amounts
  |
  v
5. Update monthly running totals in Redis (for dashboard KPIs)
  |
  v
6. At month end: generate MonthlyReconciliation report
```

#### Monthly Reconciliation Model

```python
# dom/models/reconciliation.py
@dataclass
class MonthlyReconciliation:
    id: UUID = field(default_factory=uuid4)
    tenant_id: UUID = field(default_factory=uuid4)
    period: str = ""                                # "2026-03"
    status: str = "draft"                           # draft, reviewed, approved, invoiced

    # Subscription
    subscription_amount_mxn: Decimal = Decimal("0.00")
    subscription_paid: bool = False

    # Commissions
    total_sales_count: int = 0
    total_sales_volume_mxn: Decimal = Decimal("0.00")
    total_commission_mxn: Decimal = Decimal("0.00")
    total_financing_referral_mxn: Decimal = Decimal("0.00")
    total_insurance_referral_mxn: Decimal = Decimal("0.00")

    # Totals
    total_agentsmx_revenue_mxn: Decimal = Decimal("0.00")  # subscription + commissions
    total_tenant_net_mxn: Decimal = Decimal("0.00")

    # Payout
    payout_amount_mxn: Decimal = Decimal("0.00")    # Amount to pay to tenant (future)
    payout_status: str = "pending"                   # pending, processing, paid
    payout_date: Optional[datetime] = None

    generated_at: datetime = field(default_factory=datetime.utcnow)
    reviewed_by: Optional[UUID] = None
    approved_by: Optional[UUID] = None
```

```sql
CREATE TABLE monthly_reconciliations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    period VARCHAR(7) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    subscription_amount_mxn NUMERIC(12,2) NOT NULL DEFAULT 0,
    subscription_paid BOOLEAN NOT NULL DEFAULT false,
    total_sales_count INTEGER NOT NULL DEFAULT 0,
    total_sales_volume_mxn NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_commission_mxn NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_financing_referral_mxn NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_insurance_referral_mxn NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_agentsmx_revenue_mxn NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_tenant_net_mxn NUMERIC(14,2) NOT NULL DEFAULT 0,
    payout_amount_mxn NUMERIC(14,2) NOT NULL DEFAULT 0,
    payout_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    payout_date TIMESTAMP,
    generated_at TIMESTAMP NOT NULL DEFAULT now(),
    reviewed_by UUID REFERENCES users(id),
    approved_by UUID REFERENCES users(id),
    UNIQUE(tenant_id, period)
);

CREATE INDEX idx_reconciliation_period ON monthly_reconciliations(period);
CREATE INDEX idx_reconciliation_status ON monthly_reconciliations(status);
```

#### Commission Consumer (SQS)

```python
# app/use_cases/calculate_commission.py
class CalculateCommissionUseCase:
    def __init__(self, tenant_repo: TenantRepository,
                 plan_repo: PlanRepository,
                 revenue_repo: RevenueRepository,
                 commission_svc: CommissionService):
        self._tenant_repo = tenant_repo
        self._plan_repo = plan_repo
        self._revenue_repo = revenue_repo
        self._commission_svc = commission_svc

    def execute(self, event: PurchaseCompletedEvent) -> TenantRevenueEntry:
        # Get tenant and their plan
        tenant = self._tenant_repo.find_by_id(event.vehicle_tenant_id)
        plan = self._plan_repo.find_by_id(tenant.plan_id)

        # Calculate commission
        calc = self._commission_svc.calculate(
            vehicle_price=event.vehicle_price_mxn,
            tenant_plan=plan,
            has_financing=event.has_financing,
            has_insurance=event.has_insurance,
        )

        # Create revenue entry
        entry = TenantRevenueEntry(
            tenant_id=tenant.id,
            purchase_id=event.purchase_id,
            period=event.purchase_date.strftime("%Y-%m"),
            vehicle_price_mxn=event.vehicle_price_mxn,
            commission_paid_mxn=calc.commission_amount_mxn,
            financing_referral_paid=calc.financing_referral_amount,
            insurance_referral_paid=calc.insurance_referral_amount,
            net_revenue_mxn=calc.tenant_net_revenue,
            purchase_context=event.purchase_context,
        )

        self._revenue_repo.save(entry)
        return entry
```

#### Reconciliation Generator

```python
# app/use_cases/generate_reconciliation.py
class GenerateReconciliationUseCase:
    """Monthly job that generates reconciliation reports."""

    def execute(self, period: str) -> list[MonthlyReconciliation]:
        """Generate reconciliation for all active tenants for given period."""
        tenants = self._tenant_repo.find_active()
        reconciliations = []

        for tenant in tenants:
            if tenant.is_master:
                continue  # Skip AgentsMX master tenant

            entries = self._revenue_repo.find_by_tenant_and_period(
                tenant.id, period
            )
            subscription = self._subscription_repo.find_active(tenant.id)

            recon = MonthlyReconciliation(
                tenant_id=tenant.id,
                period=period,
                subscription_amount_mxn=(
                    subscription.price_mxn if subscription else Decimal("0.00")
                ),
                subscription_paid=self._is_subscription_paid(subscription, period),
                total_sales_count=len(entries),
                total_sales_volume_mxn=sum(e.vehicle_price_mxn for e in entries),
                total_commission_mxn=sum(e.commission_paid_mxn for e in entries),
                total_financing_referral_mxn=sum(
                    e.financing_referral_paid for e in entries
                ),
                total_insurance_referral_mxn=sum(
                    e.insurance_referral_paid for e in entries
                ),
            )

            recon.total_agentsmx_revenue_mxn = (
                recon.subscription_amount_mxn +
                recon.total_commission_mxn +
                recon.total_financing_referral_mxn +
                recon.total_insurance_referral_mxn
            )
            recon.total_tenant_net_mxn = (
                recon.total_sales_volume_mxn - recon.total_commission_mxn -
                recon.total_financing_referral_mxn -
                recon.total_insurance_referral_mxn
            )

            self._recon_repo.save(recon)
            reconciliations.append(recon)

        return reconciliations
```

### Criterios de Aceptacion

1. **AC-001**: Cuando un evento purchase.completed llega por SQS, el sistema calcula automaticamente la comision usando las tasas del plan del tenant propietario del vehiculo. El calculo usa Decimal para precision. El TenantRevenueEntry se crea atomicamente con la compra.

2. **AC-002**: Para un tenant en plan Basic (comision 3%): venta de vehiculo a $485,000 genera comision de $14,550.00. Si se uso financiamiento (2%): $9,700.00 adicionales. Si se uso seguro (2%): $9,700.00 adicionales. Total AgentsMX: $33,950.00. Tenant net: $451,050.00. Verificado con test con numeros exactos.

3. **AC-003**: Para un tenant en plan Free (comision 5%): misma venta genera comision de $24,250.00. Con financiamiento (2%): $9,700.00. Con seguro (3%): $14,550.00. Total AgentsMX: $48,500.00. Tenant net: $436,500.00. La diferencia entre Free y Basic incentiva el upgrade.

4. **AC-004**: Las comisiones por compras en el white label del tenant (purchase_context="tenant_whitelabel") se calculan igual que en AgentsMX. No hay descuento por "compra directa". El contexto se registra para analytics pero no afecta la tasa.

5. **AC-005**: El job mensual de reconciliacion (ejecutado el 1 de cada mes a las 6:00 AM CST) genera un MonthlyReconciliation para cada tenant activo. Incluye: subscription amount, total sales, commissions, referrals, neto. Se marca como "draft" para revision manual.

6. **AC-006**: El flujo de aprobacion de reconciliacion es: draft -> reviewed (por finance team) -> approved (por finance manager) -> invoiced (factura de comision generada). Solo super_admin puede mover entre estados. Cada cambio registra quien lo hizo.

7. **AC-007**: GET /api/v1/admin/billing/reconciliation?period=2026-03 retorna las reconciliaciones de todos los tenants para el periodo: tenant name, plan, subscription, commissions, referrals, total AgentsMX revenue, status. Filtrable por status y plan. Exportable a CSV.

8. **AC-008**: Si un tenant Enterprise tiene comision negociada de 1.5% (diferente al default), el calculo usa el rate especifico del tenant almacenado en TenantConfig, no el rate del plan. El plan define defaults, TenantConfig puede override.

9. **AC-009**: Si el calculo de comision falla (ej: tenant no encontrado, plan sin rates), el evento SQS se reintenta 3 veces con exponential backoff (1min, 5min, 25min). Si falla los 3 intentos, se mueve a una dead-letter queue y se alerta al equipo de finance.

10. **AC-010**: Los running totals mensuales (total commissions, total revenue) se mantienen en Redis para queries rapidas del dashboard. Key: "billing:running:{tenant_id}:{YYYY-MM}". Se actualizan atomicamente con INCRBYFLOAT. Se reconcilian con la DB en el job mensual.

11. **AC-011**: Las comisiones NO se cobran automaticamente (por ahora). Se generan como facturas de comision que el tenant debe pagar por separado, o se deducen del payout (futuro). El sistema registra el monto adeudado pero no lo cobra hasta implementar payouts (EP futuro).

12. **AC-012**: Los tests verifican: (a) calculo correcto para cada plan con y sin financing/insurance, (b) reconciliacion mensual genera entries para todos los tenants activos, (c) running totals en Redis se actualizan correctamente, (d) retry logic en caso de fallo, (e) enterprise con rates custom.

### Definition of Done

- [ ] Commission calculation consumer funcional (SQS)
- [ ] TenantRevenueEntry creado por cada transaccion
- [ ] Monthly reconciliation job implementado
- [ ] Reconciliation approval workflow (draft->reviewed->approved->invoiced)
- [ ] Running totals en Redis para dashboard
- [ ] Admin reconciliation endpoint con export CSV
- [ ] Retry logic con dead-letter queue
- [ ] Tests con precision Decimal
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- El consumer SQS debe ser idempotente: si recibe el mismo purchase_id dos veces, no duplica la comision
- Usar SQS FIFO queue para garantizar orden y deduplicacion (message_group_id = tenant_id)
- Los running totals en Redis son para performance del dashboard; la fuente de verdad es PostgreSQL
- Considerar un servicio separado de billing en el futuro si la complejidad crece
- Para CFDI de comisiones: el emisor es el tenant, el receptor es AgentsMX (inverso a la suscripcion)

### Dependencias

- Story MKT-BE-046 completada (modelo de planes)
- Story MKT-BE-047 completada (API de billing base)
- EP-014 Story MKT-BE-045 (purchase flow con commission fields)
- SQS colas configuradas (purchase events + dead-letter)
- Redis 7 para running totals

---

## User Story 4: [MKT-FE-035][FE-FEAT-ADM] Panel de Billing del Tenant

### Descripcion

Como tenant admin, necesito un panel de billing dentro de mi admin que muestre: mi plan actual con uso vs limites, prompts de upgrade cuando estoy cerca de los limites, historial de facturas con descarga PDF, desglose de comisiones por transaccion, y gestion de metodo de pago. El panel debe ser claro y transparente sobre los costos.

### Microservicio

- **Nombre**: Frontend Angular 18 - Admin Module
- **Puerto**: 4200 (dev)
- **Tecnologia**: Angular 18, TypeScript 5.4, Tailwind CSS v4, Standalone Components, Signals
- **Patron**: Hexagonal Architecture (Frontend) - Presentation Layer

### Contexto Tecnico

#### Estructura de Archivos

```
src/app/
  features/
    admin/
      billing/
        domain/
          models/
            billing.model.ts             # Billing interfaces
            plan.model.ts                # Plan comparison interfaces
            invoice.model.ts             # Invoice interfaces
            commission.model.ts          # Commission interfaces
          ports/
            billing.port.ts              # Abstract class
        application/
          services/
            billing.service.ts           # Orchestration
        infrastructure/
          adapters/
            billing-api.adapter.ts       # HTTP calls
        presentation/
          pages/
            billing-overview/
              billing-overview.page.ts
              billing-overview.page.html
              billing-overview.page.spec.ts
            plan-comparison/
              plan-comparison.page.ts
              plan-comparison.page.html
              plan-comparison.page.spec.ts
            invoice-list/
              invoice-list.page.ts
              invoice-list.page.html
              invoice-list.page.spec.ts
            commission-breakdown/
              commission-breakdown.page.ts
              commission-breakdown.page.html
              commission-breakdown.page.spec.ts
          components/
            plan-card/
              plan-card.component.ts
              plan-card.component.html
              plan-card.component.spec.ts
            usage-meter/
              usage-meter.component.ts
              usage-meter.component.html
              usage-meter.component.spec.ts
            invoice-row/
              invoice-row.component.ts
              invoice-row.component.html
              invoice-row.component.spec.ts
            payment-method-card/
              payment-method-card.component.ts
              payment-method-card.component.html
              payment-method-card.component.spec.ts
            upgrade-prompt/
              upgrade-prompt.component.ts
              upgrade-prompt.component.html
              upgrade-prompt.component.spec.ts
```

#### Plan Card Component

```typescript
// presentation/components/plan-card/plan-card.component.ts
@Component({
  selector: 'app-plan-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="relative bg-white rounded-xl shadow-sm border p-6
                transition-all hover:shadow-md"
         [class.border-primary]="isCurrent()"
         [class.border-gray-200]="!isCurrent()"
         [class.ring-2]="isCurrent()"
         [class.ring-primary/20]="isCurrent()">

      @if (isRecommended()) {
        <div class="absolute -top-3 left-1/2 -translate-x-1/2 px-3 py-1
                    bg-primary text-white text-xs font-medium rounded-full">
          Recomendado
        </div>
      }

      @if (isCurrent()) {
        <div class="absolute -top-3 right-4 px-3 py-1
                    bg-green-500 text-white text-xs font-medium rounded-full">
          Plan Actual
        </div>
      }

      <h3 class="text-lg font-heading font-bold text-gray-900">
        {{ plan().display_name }}
      </h3>
      <p class="text-sm text-gray-500 mt-1">{{ plan().description }}</p>

      <div class="mt-4">
        @if (plan().price_monthly_mxn > 0) {
          <div class="flex items-baseline gap-1">
            <span class="text-3xl font-bold text-gray-900">
              ${{ plan().price_monthly_mxn | number:'1.0-0' }}
            </span>
            <span class="text-sm text-gray-500">MXN/mes</span>
          </div>
          @if (plan().annual_savings_percent) {
            <p class="text-xs text-green-600 mt-1">
              Ahorra {{ plan().annual_savings_percent }}% con plan anual
            </p>
          }
        } @else {
          <div class="text-3xl font-bold text-gray-900">Gratis</div>
        }
      </div>

      <ul class="mt-6 space-y-3">
        <li class="flex items-center gap-2 text-sm">
          <svg class="w-4 h-4 text-green-500 flex-shrink-0"><!-- check --></svg>
          {{ plan().limits.vehicles ? plan().limits.vehicles + ' vehiculos' : 'Vehiculos ilimitados' }}
        </li>
        <li class="flex items-center gap-2 text-sm">
          <svg class="w-4 h-4 text-green-500 flex-shrink-0"><!-- check --></svg>
          {{ plan().limits.users ? plan().limits.users + ' usuarios' : 'Usuarios ilimitados' }}
        </li>
        <li class="flex items-center gap-2 text-sm">
          <svg class="w-4 h-4 text-green-500 flex-shrink-0"><!-- check --></svg>
          Comision {{ plan().commission_rate }}
        </li>
        @for (feature of planFeatureList(); track feature.name) {
          <li class="flex items-center gap-2 text-sm"
              [class.text-gray-400]="!feature.included">
            <svg class="w-4 h-4 flex-shrink-0"
                 [class.text-green-500]="feature.included"
                 [class.text-gray-300]="!feature.included">
              <!-- check or x -->
            </svg>
            {{ feature.name }}
          </li>
        }
      </ul>

      <div class="mt-6">
        @if (isCurrent()) {
          <button disabled
                  class="w-full py-2 rounded-lg bg-gray-100 text-gray-500
                         text-sm font-medium cursor-not-allowed">
            Plan Actual
          </button>
        } @else if (isUpgrade()) {
          <button (click)="onSelect.emit(plan())"
                  class="w-full py-2 rounded-lg bg-primary text-white
                         text-sm font-medium hover:bg-primary-hover transition-colors">
            Upgrade
          </button>
        } @else {
          <button (click)="onSelect.emit(plan())"
                  class="w-full py-2 rounded-lg border border-gray-300 text-gray-700
                         text-sm font-medium hover:bg-gray-50 transition-colors">
            Downgrade
          </button>
        }
      </div>
    </div>
  `,
})
export class PlanCardComponent {
  readonly plan = input.required<PlanInfo>();
  readonly currentPlan = input.required<string>();
  readonly onSelect = output<PlanInfo>();

  readonly isCurrent = computed(() => this.plan().name === this.currentPlan());
  readonly isRecommended = computed(() => this.plan().is_recommended);
  readonly isUpgrade = computed(() => {
    const order: Record<string, number> = { free: 0, basic: 1, pro: 2, enterprise: 3 };
    return (order[this.plan().name] ?? 0) > (order[this.currentPlan()] ?? 0);
  });

  readonly planFeatureList = computed(() => [
    { name: 'Financiamiento', included: this.plan().features.financing },
    { name: 'Seguros', included: this.plan().features.insurance },
    { name: 'Chat', included: this.plan().features.chat },
    { name: 'Analytics', included: this.plan().features.analytics },
    { name: 'Reportes', included: this.plan().features.reports },
    { name: 'Dominio propio', included: this.plan().features.custom_domain },
    { name: 'Sin badge AgentsMX', included: this.plan().features.remove_badge },
    { name: 'API Access', included: this.plan().features.api_access },
  ]);
}
```

### Criterios de Aceptacion

1. **AC-001**: La pagina Billing Overview muestra: card del plan actual con nombre, precio, proximo cobro (fecha y monto), y barras de uso (vehiculos, usuarios, storage). Si el uso es > 80%, la barra se muestra en amarillo; > 95% en rojo. Incluye boton "Cambiar Plan" que navega a la comparacion.

2. **AC-002**: El componente UpgradePrompt se muestra automaticamente cuando el tenant alcanza > 80% de algun limite: "Estas usando 410 de 500 vehiculos. Upgrade a Pro para vehiculos ilimitados." Con boton "Ver Plan Pro". Se puede cerrar (dismiss) y reaparece despues de 7 dias.

3. **AC-003**: La pagina Plan Comparison muestra los 4 planes en cards lado a lado (grid de 4 columnas en desktop, carousel en mobile). El plan actual esta marcado con badge "Plan Actual" y border primario. El plan recomendado tiene badge "Recomendado". Cada card lista: precio, limites, comision, features.

4. **AC-004**: Al seleccionar un plan para upgrade, se muestra un modal de confirmacion con: plan actual vs nuevo plan, diferencia de precio, prorrateo calculado ("Se cobraran $2,750 MXN por los 15 dias restantes del mes"), y total a pagar hoy. Boton "Confirmar Upgrade" procesa el pago.

5. **AC-005**: Al seleccionar un plan para downgrade, se muestra modal con: plan actual vs nuevo plan, advertencias de lo que se pierde (custom domain, analytics, etc.), blockers si existen ("Tienes 234 vehiculos, el plan Free permite 50"). Si hay blockers, el boton esta disabled con tooltip explicativo.

6. **AC-006**: La pagina Invoice List muestra tabla con: numero de factura, fecha, tipo (Suscripcion/Comision), monto total (con IVA), status (badge: Pagada verde, Pendiente amarillo, Fallida rojo), y boton de descarga PDF/CFDI. Filtrable por tipo y status, paginada de 10 items.

7. **AC-007**: Click en "Descargar" de una factura ofrece dos opciones: "PDF" (factura visual) y "CFDI XML" (archivo fiscal). Ambos se descargan directamente desde S3 via presigned URL. Si no hay CFDI disponible, solo se muestra PDF.

8. **AC-008**: La pagina Commission Breakdown muestra: resumen del mes (total ventas, total comisiones, total referrals, neto) y tabla detallada por transaccion (fecha, vehiculo, precio, comision %, monto, financing referral, insurance referral, contexto). Selector de mes para ver periodos anteriores.

9. **AC-009**: El PaymentMethodCard muestra: tipo de tarjeta (icono Visa/Mastercard/Amex), ultimos 4 digitos, fecha de expiracion, y boton "Cambiar". Al cambiar, se abre Stripe Elements/Conekta checkout para ingresar nueva tarjeta. El metodo anterior se reemplaza automaticamente.

10. **AC-010**: Si el tenant esta en plan Free, la seccion de metodo de pago no se muestra (no tiene cobros). Al intentar upgrade desde Free, el flujo incluye agregar metodo de pago antes de confirmar la suscripcion.

11. **AC-011**: Todos los montos se muestran con formato mexicano: "$2,500.00 MXN", "$14,550.00 MXN". El separador de miles es coma, el separador decimal es punto. Se usa pipe currency de Angular con locale 'es-MX'.

12. **AC-012**: Los tests verifican: (a) plan cards renderizan correctamente con is_current y is_recommended, (b) upgrade modal calcula prorrateo correcto, (c) downgrade modal muestra blockers, (d) invoice table pagina y filtra, (e) commission breakdown totaliza correctamente.

### Definition of Done

- [ ] Billing overview page con plan, uso y proximo cobro
- [ ] Plan comparison page con 4 plan cards
- [ ] Upgrade/downgrade modals con confirmacion
- [ ] Invoice list con descarga PDF/CFDI
- [ ] Commission breakdown con detalle por transaccion
- [ ] Payment method management
- [ ] Upgrade prompt automatico
- [ ] Tests unitarios >= 85%
- [ ] Responsive design verificado
- [ ] Code review aprobado

### Notas Tecnicas

- Usar Stripe Elements o Conekta Checkout para captura segura de tarjetas (PCI compliance)
- Los montos de prorrateo se calculan en el backend; el frontend solo los muestra
- Para carousel de planes en mobile, usar Angular CDK o swiper.js
- Los PDFs de facturas pueden tardar en generarse; mostrar "Generando..." si no esta listo
- El dismiss del upgrade prompt se almacena en localStorage con timestamp

### Dependencias

- Story MKT-BE-047 completada (API de billing)
- Story MKT-BE-048 completada (commission calculation)
- Stripe Elements JS o Conekta Checkout JS cargados

---

## User Story 5: [MKT-FE-036][FE-FEAT-ADM] Panel de Revenue del Super Admin

### Descripcion

Como super admin de AgentsMX, necesito un dashboard de revenue global que muestre las metricas financieras clave del negocio: MRR, ARR, churn rate, ARPU, revenue por tenant, distribucion por plan, comisiones pendientes de cobro, y alertas de pagos vencidos. Este panel permite al equipo de finanzas de AgentsMX tener visibilidad completa del estado financiero del negocio de white labels.

### Microservicio

- **Nombre**: Frontend Angular 18 - Admin Module
- **Puerto**: 4200 (dev)
- **Tecnologia**: Angular 18, TypeScript 5.4, Tailwind CSS v4, Chart.js, Signals
- **Patron**: Hexagonal Architecture (Frontend) - Presentation Layer

### Contexto Tecnico

#### Estructura de Archivos

```
src/app/
  features/
    admin/
      revenue/
        domain/
          models/
            revenue-metrics.model.ts      # MRR, ARR, churn, ARPU
            tenant-revenue.model.ts       # Per-tenant revenue
            plan-distribution.model.ts    # Distribution by plan
            reconciliation.model.ts       # Monthly reconciliation
          ports/
            revenue-dashboard.port.ts
        application/
          services/
            revenue-dashboard.service.ts
        infrastructure/
          adapters/
            revenue-api.adapter.ts
        presentation/
          pages/
            revenue-overview/
              revenue-overview.page.ts
              revenue-overview.page.html
              revenue-overview.page.spec.ts
            tenant-revenue/
              tenant-revenue.page.ts
              tenant-revenue.page.html
              tenant-revenue.page.spec.ts
            reconciliation-list/
              reconciliation-list.page.ts
              reconciliation-list.page.html
              reconciliation-list.page.spec.ts
          components/
            mrr-chart/
              mrr-chart.component.ts
              mrr-chart.component.html
              mrr-chart.component.spec.ts
            plan-distribution-chart/
              plan-distribution-chart.component.ts
              plan-distribution-chart.component.html
              plan-distribution-chart.component.spec.ts
            revenue-kpi-card/
              revenue-kpi-card.component.ts
              revenue-kpi-card.component.html
              revenue-kpi-card.component.spec.ts
            overdue-alert/
              overdue-alert.component.ts
              overdue-alert.component.html
              overdue-alert.component.spec.ts
            reconciliation-row/
              reconciliation-row.component.ts
              reconciliation-row.component.html
              reconciliation-row.component.spec.ts
```

#### Revenue Dashboard Data Model

```typescript
// domain/models/revenue-metrics.model.ts
export interface RevenueMetrics {
  mrr: number;                    // Monthly Recurring Revenue
  mrr_change_percent: number;     // vs previous month
  arr: number;                    // Annual Recurring Revenue (MRR * 12)
  churn_rate: number;             // % of cancelled tenants this month
  arpu: number;                   // Average Revenue Per User (MRR / active tenants)
  ltv: number;                    // Lifetime Value (ARPU / churn_rate)
  total_tenants: number;
  active_tenants: number;
  paying_tenants: number;
  total_revenue_month: number;    // Subscriptions + commissions
  subscription_revenue: number;
  commission_revenue: number;
}

export interface PlanDistribution {
  plan: string;
  count: number;
  revenue_mxn: number;
  percent_total: number;
}

export interface TenantRevenueRow {
  tenant_id: string;
  tenant_name: string;
  plan: string;
  subscription_mxn: number;
  commissions_mxn: number;
  total_revenue_mxn: number;
  vehicles: number;
  transactions_month: number;
  status: 'current' | 'past_due' | 'at_risk';
}

export interface OverdueAlert {
  tenant_id: string;
  tenant_name: string;
  amount_overdue_mxn: number;
  days_overdue: number;
  last_payment_attempt: string;
  retry_count: number;
}
```

### Criterios de Aceptacion

1. **AC-001**: La pagina Revenue Overview muestra 6 KPI cards en grid: MRR (Monthly Recurring Revenue con cambio % vs mes anterior), ARR (MRR * 12), Churn Rate (% cancelaciones), ARPU (MRR / tenants pagadores), Total Tenants (activos/pagadores/trial), Revenue del Mes (suscripciones + comisiones). Cada card muestra valor, cambio y trend sparkline.

2. **AC-002**: El grafico MRR (line chart) muestra la evolucion del MRR durante los ultimos 12 meses. Incluye dos lineas: MRR de suscripciones y MRR total (suscripciones + comisiones). Al hacer hover, muestra tooltip con desglose: "$X suscripciones + $Y comisiones = $Z total". Color primario para suscripciones, accent para comisiones.

3. **AC-003**: El grafico Plan Distribution (donut chart) muestra cuantos tenants hay en cada plan y el revenue que generan. Segmentos: Free (gris), Basic (azul), Pro (verde), Enterprise (morado). Click en un segmento filtra la tabla de tenants por ese plan.

4. **AC-004**: La tabla Revenue per Tenant muestra: nombre del tenant, plan, suscripcion mensual, comisiones del mes, total revenue, # vehiculos, # transacciones, status (current/past_due/at_risk). Ordenable por cualquier columna. Buscable por nombre. Exportable a CSV.

5. **AC-005**: Los tenants "at risk" se identifican automaticamente: tenants que bajaron en uso > 50% vs mes anterior, tenants en plan trial que expiran en < 7 dias, tenants con pago fallido. Se marcan con badge rojo "En riesgo" en la tabla.

6. **AC-006**: La seccion Overdue Alerts muestra tenants con pagos vencidos en cards rojas: nombre, monto adeudado, dias de atraso, # intentos de cobro, boton "Contactar". Los alertas se ordenan por monto descendente. Solo visible para super_admin.

7. **AC-007**: La pagina Reconciliation List muestra las reconciliaciones mensuales por tenant con flujo de aprobacion: tabs "Draft" / "Reviewed" / "Approved" / "Invoiced". Cada reconciliacion muestra: tenant, suscripcion, comisiones, referrals, total AgentsMX, status. Boton "Aprobar" avanza el estado.

8. **AC-008**: El export CSV de revenue per tenant incluye: tenant_name, plan, subscription_mxn, commission_mxn, financing_referral_mxn, insurance_referral_mxn, total_revenue_mxn, vehicles_count, transactions_count. Nombre del archivo: "revenue_YYYY-MM.csv".

9. **AC-009**: El dashboard muestra un resumen de revenue breakdown: pie chart con suscripciones (%), comisiones de venta (%), referrals de financiamiento (%), referrals de seguro (%). Esto permite ver cuales son las principales fuentes de ingreso.

10. **AC-010**: El churn rate se calcula como: tenants que cancelaron en el mes / total tenants activos al inicio del mes * 100. Se muestra con indicador: < 3% verde, 3-5% amarillo, > 5% rojo. Incluye detalle de tenants que cancelaron con razon de cancelacion.

11. **AC-011**: Todos los datos financieros se muestran con formato MXN ($XXX,XXX.XX MXN). Los porcentajes se muestran con 1 decimal (X.X%). Los graficos usan colores consistentes: verde para positivo, rojo para negativo, gris para neutral.

12. **AC-012**: Solo usuarios con rol super_admin pueden acceder al panel de revenue. La ruta /admin/revenue tiene guard que verifica el rol. Tenant admins que intentan acceder ven 403. Ningun dato financiero global se expone a tenant admins.

13. **AC-013**: Los tests verifican: (a) KPI cards calculan MRR/ARR/ARPU correctamente, (b) churn rate se muestra con color correcto por nivel, (c) plan distribution chart refleja datos reales, (d) overdue alerts se ordenan por monto, (e) reconciliation workflow avanza estados correctamente.

### Definition of Done

- [ ] Revenue overview page con 6 KPI cards
- [ ] MRR evolution chart (12 meses)
- [ ] Plan distribution chart
- [ ] Revenue per tenant table con search, sort, export
- [ ] Overdue alerts section
- [ ] Reconciliation workflow (draft->reviewed->approved->invoiced)
- [ ] CSV export funcional
- [ ] Access control para super_admin only
- [ ] Tests unitarios >= 85%
- [ ] Responsive design verificado
- [ ] Code review aprobado

### Notas Tecnicas

- Los datos de revenue se cachean en Redis con TTL de 15 minutos (metricas no necesitan ser real-time)
- Chart.js con ng2-charts para graficos; considerar lazy load del bundle
- El export CSV se genera en el frontend para datasets < 1000 rows; para mas, usar endpoint backend
- Los reconciliation states se gestionan con estado optimista (actualizar UI antes de API response)
- Considerar agregar proyecciones de revenue (forecast basado en trend de MRR)

### Dependencias

- Story MKT-BE-047 completada (API admin billing overview)
- Story MKT-BE-048 completada (reconciliation data)
- Chart.js + ng2-charts instalados
- Rol super_admin configurado en auth

---

## User Story 6: [MKT-BE-049][SVC-TNT-INF] Integracion Pasarela de Pagos (Stripe/Conekta)

### Descripcion

Como servicio de billing, necesito integrarme con una pasarela de pagos (Stripe Connect para mercado global o Conekta para mercado mexicano) para procesar suscripciones recurrentes, cobros unicos (setup fee, proration), y gestionar metodos de pago. La integracion incluye: creacion de customers, gestion de subscriptions, emision de invoices, manejo de webhooks, y generacion de facturas CFDI (Comprobante Fiscal Digital por Internet) requeridas por el SAT mexicano.

### Microservicio

- **Nombre**: SVC-TNT (Infrastructure Layer)
- **Puerto**: 5023
- **Tecnologia**: Python 3.11, stripe-python 7.x / conekta 6.x, facturapi
- **Base de datos**: PostgreSQL 15
- **Patron**: Hexagonal Architecture - Infrastructure Layer (Adapter)

### Contexto Tecnico

#### Payment Gateway Port

```python
# dom/ports/payment_gateway.py
from abc import ABC, abstractmethod
from decimal import Decimal
from typing import Optional

class PaymentGatewayPort(ABC):
    """Port for payment processing. Implemented by Stripe or Conekta adapter."""

    @abstractmethod
    def create_customer(self, tenant_id: str, email: str,
                        name: str) -> str:
        """Create customer in payment gateway. Returns external customer ID."""
        ...

    @abstractmethod
    def create_subscription(self, customer_id: str, plan_id: str,
                             billing_cycle: str,
                             payment_method_token: str) -> SubscriptionResult:
        """Create recurring subscription. Returns subscription details."""
        ...

    @abstractmethod
    def update_subscription(self, subscription_id: str,
                             new_plan_id: str) -> SubscriptionResult:
        """Update existing subscription (upgrade/downgrade)."""
        ...

    @abstractmethod
    def cancel_subscription(self, subscription_id: str,
                             at_period_end: bool = True) -> bool:
        """Cancel subscription. at_period_end=True means cancel at end of billing period."""
        ...

    @abstractmethod
    def charge_one_time(self, customer_id: str,
                         amount_mxn: Decimal,
                         description: str) -> ChargeResult:
        """Process one-time charge (setup fee, proration)."""
        ...

    @abstractmethod
    def add_payment_method(self, customer_id: str,
                            payment_method_token: str) -> PaymentMethodResult:
        """Attach payment method to customer."""
        ...

    @abstractmethod
    def list_payment_methods(self, customer_id: str) -> list[PaymentMethodInfo]:
        """List customer's payment methods."""
        ...

    @abstractmethod
    def get_invoice(self, invoice_id: str) -> InvoiceInfo:
        """Get invoice details from payment gateway."""
        ...
```

```python
# dom/ports/fiscal_invoice.py
class FiscalInvoicePort(ABC):
    """Port for CFDI invoice generation (SAT Mexico compliance)."""

    @abstractmethod
    def create_cfdi(self, invoice_data: CFDIInvoiceData) -> CFDIResult:
        """Generate CFDI XML and PDF."""
        ...

    @abstractmethod
    def cancel_cfdi(self, cfdi_uuid: str, reason: str) -> bool:
        """Cancel a CFDI invoice."""
        ...

    @abstractmethod
    def get_cfdi_status(self, cfdi_uuid: str) -> str:
        """Check CFDI status with SAT."""
        ...
```

#### Stripe Adapter

```python
# inf/payment/stripe_adapter.py
import stripe
from decimal import Decimal

class StripePaymentAdapter(PaymentGatewayPort):
    def __init__(self, api_key: str, webhook_secret: str):
        stripe.api_key = api_key
        self._webhook_secret = webhook_secret

    def create_customer(self, tenant_id: str, email: str,
                        name: str) -> str:
        customer = stripe.Customer.create(
            email=email,
            name=name,
            metadata={"tenant_id": tenant_id},
        )
        return customer.id

    def create_subscription(self, customer_id: str, plan_id: str,
                             billing_cycle: str,
                             payment_method_token: str) -> SubscriptionResult:
        # Attach payment method
        stripe.PaymentMethod.attach(
            payment_method_token,
            customer=customer_id,
        )
        stripe.Customer.modify(
            customer_id,
            invoice_settings={"default_payment_method": payment_method_token},
        )

        # Create subscription
        price_id = self._get_stripe_price_id(plan_id, billing_cycle)
        subscription = stripe.Subscription.create(
            customer=customer_id,
            items=[{"price": price_id}],
            payment_behavior="default_incomplete",
            expand=["latest_invoice.payment_intent"],
        )

        return SubscriptionResult(
            external_id=subscription.id,
            status=subscription.status,
            current_period_start=datetime.fromtimestamp(
                subscription.current_period_start
            ),
            current_period_end=datetime.fromtimestamp(
                subscription.current_period_end
            ),
            client_secret=(
                subscription.latest_invoice.payment_intent.client_secret
                if subscription.latest_invoice
                else None
            ),
        )

    def cancel_subscription(self, subscription_id: str,
                             at_period_end: bool = True) -> bool:
        if at_period_end:
            stripe.Subscription.modify(
                subscription_id,
                cancel_at_period_end=True,
            )
        else:
            stripe.Subscription.delete(subscription_id)
        return True

    def charge_one_time(self, customer_id: str,
                         amount_mxn: Decimal,
                         description: str) -> ChargeResult:
        # Convert to centavos for Stripe
        amount_centavos = int(amount_mxn * 100)
        intent = stripe.PaymentIntent.create(
            amount=amount_centavos,
            currency="mxn",
            customer=customer_id,
            description=description,
            confirm=True,
        )
        return ChargeResult(
            external_id=intent.id,
            status=intent.status,
            amount_mxn=amount_mxn,
        )
```

#### Conekta Adapter

```python
# inf/payment/conekta_adapter.py
import conekta

class ConektaPaymentAdapter(PaymentGatewayPort):
    """Conekta adapter for Mexican payment methods (SPEI, OXXO, cards)."""

    def __init__(self, api_key: str):
        conekta.api_key = api_key
        conekta.api_version = "2.0.0"

    def create_customer(self, tenant_id: str, email: str,
                        name: str) -> str:
        customer = conekta.Customer.create({
            "name": name,
            "email": email,
            "metadata": {"tenant_id": tenant_id},
        })
        return customer.id

    def create_subscription(self, customer_id: str, plan_id: str,
                             billing_cycle: str,
                             payment_method_token: str) -> SubscriptionResult:
        customer = conekta.Customer.find(customer_id)
        customer.createPaymentSource({
            "type": "card",
            "token_id": payment_method_token,
        })

        subscription = customer.createSubscription({
            "plan_id": self._get_conekta_plan_id(plan_id, billing_cycle),
        })

        return SubscriptionResult(
            external_id=subscription.id,
            status=subscription.status,
            current_period_start=datetime.fromtimestamp(
                subscription.subscription_start
            ),
            current_period_end=datetime.fromtimestamp(
                subscription.billing_cycle_end
            ),
        )
```

#### CFDI Adapter (FacturAPI)

```python
# inf/fiscal/facturapi_adapter.py
import requests

class FacturapiCFDIAdapter(FiscalInvoicePort):
    """CFDI generation via facturapi.io for SAT compliance."""

    BASE_URL = "https://www.facturapi.io/v2"

    def __init__(self, api_key: str):
        self._headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

    def create_cfdi(self, invoice_data: CFDIInvoiceData) -> CFDIResult:
        payload = {
            "customer": {
                "legal_name": invoice_data.customer_name,
                "email": invoice_data.customer_email,
                "tax_id": invoice_data.customer_rfc,
                "tax_system": invoice_data.customer_tax_system,
                "address": {
                    "zip": invoice_data.customer_zip,
                },
            },
            "items": [
                {
                    "quantity": item.quantity,
                    "product": {
                        "description": item.description,
                        "product_key": item.sat_product_key,
                        "unit_key": item.sat_unit_key,
                        "unit_name": item.unit_name,
                        "price": float(item.unit_price),
                    },
                }
                for item in invoice_data.items
            ],
            "use": invoice_data.cfdi_use,              # "G03" for general expenses
            "payment_form": invoice_data.payment_form,  # "04" for card
            "series": "WL",                             # White Label series
        }

        response = requests.post(
            f"{self.BASE_URL}/invoices",
            json=payload,
            headers=self._headers,
        )
        response.raise_for_status()
        data = response.json()

        return CFDIResult(
            cfdi_uuid=data["uuid"],
            cfdi_xml_url=data["xml_url"],
            cfdi_pdf_url=data["pdf_url"],
            invoice_number=data["folio_number"],
            status="valid",
        )

    def cancel_cfdi(self, cfdi_uuid: str, reason: str) -> bool:
        response = requests.delete(
            f"{self.BASE_URL}/invoices/{cfdi_uuid}",
            json={"motive": reason},
            headers=self._headers,
        )
        return response.status_code == 200
```

#### Webhook Event Handlers

```python
# app/use_cases/handle_payment_webhook.py
class HandlePaymentWebhookUseCase:
    def __init__(self, subscription_repo: SubscriptionRepository,
                 invoice_repo: InvoiceRepository,
                 tenant_repo: TenantRepository,
                 notification_svc: NotificationPort,
                 cfdi_adapter: FiscalInvoicePort):
        self._sub_repo = subscription_repo
        self._invoice_repo = invoice_repo
        self._tenant_repo = tenant_repo
        self._notifications = notification_svc
        self._cfdi = cfdi_adapter

    def handle_payment_success(self, data: dict) -> None:
        """Handle successful payment."""
        subscription = self._sub_repo.find_by_external_id(
            data["subscription"]
        )
        if not subscription:
            return

        # Update subscription status
        subscription.status = "active"
        self._sub_repo.save(subscription)

        # Create invoice record
        invoice = Invoice(
            tenant_id=subscription.tenant_id,
            subscription_id=subscription.id,
            invoice_type="subscription",
            status="paid",
            subtotal_mxn=Decimal(str(data["amount_paid"])) / 100,
            paid_at=datetime.utcnow(),
            external_invoice_id=data["id"],
        )
        invoice.tax_mxn = invoice.subtotal_mxn * Decimal("0.16")
        invoice.total_mxn = invoice.subtotal_mxn + invoice.tax_mxn
        self._invoice_repo.save(invoice)

        # Generate CFDI
        tenant = self._tenant_repo.find_by_id(subscription.tenant_id)
        try:
            cfdi = self._cfdi.create_cfdi(
                self._build_cfdi_data(tenant, invoice)
            )
            invoice.cfdi_uuid = cfdi.cfdi_uuid
            invoice.cfdi_xml_url = cfdi.cfdi_xml_url
            invoice.cfdi_pdf_url = cfdi.cfdi_pdf_url
            self._invoice_repo.save(invoice)
        except Exception as e:
            # CFDI failure should not block payment
            log.error("CFDI generation failed",
                      tenant_id=str(tenant.id), error=str(e))

        # Notify tenant
        self._notifications.send_payment_confirmation(
            tenant.id, invoice
        )

    def handle_payment_failed(self, data: dict) -> None:
        """Handle failed payment."""
        subscription = self._sub_repo.find_by_external_id(
            data["subscription"]
        )
        if not subscription:
            return

        subscription.status = "past_due"
        self._sub_repo.save(subscription)

        # Notify tenant of failed payment
        tenant = self._tenant_repo.find_by_id(subscription.tenant_id)
        self._notifications.send_payment_failed(
            tenant.id,
            amount_mxn=Decimal(str(data["amount_due"])) / 100,
            retry_date=self._calculate_next_retry(data),
        )
```

### Criterios de Aceptacion

1. **AC-001**: El PaymentGatewayPort define una interfaz abstracta con metodos para: create_customer, create_subscription, update_subscription, cancel_subscription, charge_one_time, add_payment_method, list_payment_methods, get_invoice. Implementaciones para Stripe y Conekta existen como adapters intercambiables.

2. **AC-002**: El StripePaymentAdapter implementa todos los metodos del port usando stripe-python SDK. Los montos se convierten de MXN (Decimal) a centavos (int) para la API de Stripe. Los customer_id y subscription_id de Stripe se almacenan en la DB local para reconciliacion.

3. **AC-003**: El ConektaPaymentAdapter implementa los mismos metodos para el mercado mexicano. Soporta metodos de pago locales: tarjeta de credito/debito, SPEI (transferencia bancaria), OXXO (pago en efectivo). La seleccion entre Stripe y Conekta es configurable por entorno.

4. **AC-004**: El FiscalInvoicePort define la interfaz para generacion de CFDI. El FacturapiCFDIAdapter implementa: create_cfdi (genera XML + PDF), cancel_cfdi, get_cfdi_status. Cada CFDI incluye: datos del emisor (AgentsMX), datos del receptor (tenant), concepto, IVA 16%, sello digital.

5. **AC-005**: El webhook de Stripe valida la firma del request usando el webhook_secret. Requests con firma invalida retornan 400. El handler es idempotente: si el mismo evento llega dos veces, no se duplica la factura. La idempotencia se garantiza verificando external_invoice_id antes de crear.

6. **AC-006**: Al recibir invoice.payment_succeeded: (a) subscription se marca como "active", (b) invoice se crea con status "paid", (c) CFDI se genera automaticamente, (d) email de confirmacion se envia al tenant con link a la factura PDF. Si CFDI falla, la operacion principal no se revierte (CFDI es best-effort).

7. **AC-007**: Al recibir invoice.payment_failed: (a) subscription se marca como "past_due", (b) email de notificacion se envia al tenant con fecha del proximo reintento, (c) despues de 3 reintentos fallidos (dias 3, 5, 7), se envia email urgente, (d) despues de 15 dias sin pago, el tenant se suspende automaticamente.

8. **AC-008**: La generacion de CFDI incluye los campos requeridos por el SAT: RFC del emisor (AgentsMX), RFC del receptor (tenant, si lo tiene), uso de CFDI (G03 - Gastos en general), forma de pago (04 - Tarjeta, 03 - Transferencia), producto (clave SAT 81112101 - Servicios de comercio electronico), unidad (E48 - Unidad de servicio).

9. **AC-009**: Los metodos de pago se almacenan de forma segura: solo se guarda el external_payment_method_id de Stripe/Conekta, los ultimos 4 digitos y el brand (Visa/Mastercard). NUNCA se almacena el numero completo de tarjeta, CVV o fecha de expiracion completa en nuestra base de datos.

10. **AC-010**: La seleccion de pasarela de pagos es configurable via variable de entorno PAYMENT_GATEWAY=stripe o PAYMENT_GATEWAY=conekta. El dependency injection resuelve el adapter correcto. En tests, se usa un MockPaymentAdapter que simula ambas pasarelas.

11. **AC-011**: Los tests de integracion mockean las APIs de Stripe y Conekta (no hacen llamadas reales). Los mocks simulan: creacion exitosa de customer/subscription, pago exitoso, pago fallido, webhook de pago exitoso, webhook de pago fallido. Se verifica que el estado local de la DB refleja correctamente cada escenario.

12. **AC-012**: El retry logic para pagos fallidos se implementa con SQS delayed messages: primer retry a +3 dias, segundo a +5 dias, tercero a +7 dias. Cada retry intenta cobrar con el metodo de pago on file. Si el retry tiene exito, la subscription vuelve a "active" y se genera CFDI normalmente.

13. **AC-013**: Un job mensual (dia 1, 8:00 AM CST) genera CFDIs pendientes: revisa todas las invoices con status="paid" y cfdi_uuid=NULL, e intenta generar el CFDI. Esto cubre casos donde la generacion automatica fallo. Reporta al super admin los CFDIs que no pudieron generarse con el error.

14. **AC-014**: Las metricas de la pasarela de pagos se exponen: total pagos procesados/mes, tasa de exito (%), monto total cobrado, pagos fallidos por razon (tarjeta rechazada, fondos insuficientes, etc.). Estas metricas alimentan el dashboard de super admin.

### Definition of Done

- [ ] PaymentGatewayPort definido como ABC
- [ ] StripePaymentAdapter implementado y funcional
- [ ] ConektaPaymentAdapter implementado y funcional
- [ ] FiscalInvoicePort y FacturapiCFDIAdapter implementados
- [ ] Webhook handlers para payment success/failed
- [ ] Retry logic con SQS delayed messages
- [ ] CFDI generation automatica post-pago
- [ ] Job mensual de CFDIs pendientes
- [ ] Tests con mocks de Stripe, Conekta y FacturAPI
- [ ] Ningun dato de tarjeta almacenado (PCI compliance)
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- Stripe test keys: pk_test_xxx, sk_test_xxx; Conekta test keys: key_xxx
- Para CFDI en desarrollo, usar sandbox de FacturAPI o PAC de pruebas
- Los webhooks de Stripe deben tener retry configurado (Stripe reintenta hasta por 3 dias)
- Conekta maneja montos en centavos (como Stripe); siempre convertir
- PCI DSS: usar Stripe Elements/Conekta Checkout en frontend para que los datos de tarjeta nunca toquen nuestro backend
- El RFC del tenant es opcional para personas fisicas; si no lo tiene, el CFDI se genera como "publico en general" (RFC XAXX010101000)

### Dependencias

- Story MKT-BE-046 completada (modelo de planes y subscriptions)
- Story MKT-BE-047 completada (API de billing)
- Cuenta Stripe Connect o Conekta con API keys
- Cuenta FacturAPI con certificados del SAT
- SQS para retry logic de pagos fallidos
- SVC-NTF para notificaciones de pago
