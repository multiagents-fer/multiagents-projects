# [MKT-EP-011] Arquitectura Multi-Tenant & Gestion de Tenants

**Sprint**: 9-10
**Priority**: Priority 2
**Epic Owner**: Tech Lead
**Estimated Points**: 110
**Teams**: Backend, Frontend, Infrastructure

---

## Resumen del Epic

Este epic establece la infraestructura multi-tenant completa para el sistema White Label del Vehicle Marketplace. Incluye la creacion del servicio SVC-TNT (Tenant Management), la adicion de tenant_id a todas las tablas existentes, el middleware de resolucion de tenant en el API Gateway, la configuracion DNS para subdominios y dominios custom, y la autenticacion multi-tenant con AWS Cognito. La arquitectura sigue el patron single-instance multi-tenant con segregacion de datos por tenant_id y Row-Level Security en PostgreSQL para garantizar el aislamiento.

## Dependencias Externas

- Certificado wildcard SSL para *.agentsmx.com (AWS ACM)
- Cuenta Stripe o Conekta configurada (para futuro billing, EP-015)
- Acceso DNS para configurar registros wildcard
- AWS ALB con soporte SNI para dominios custom
- Epics EP-001 a EP-010 completados (marketplace base funcional)
- Base de datos PostgreSQL 15 con todas las tablas existentes migradas

---

## User Story 1: [MKT-BE-031][SVC-TNT-DOM] Modelo de Dominio Multi-Tenant

### Descripcion

Como arquitecto del sistema, necesito definir el modelo de dominio completo para multi-tenancy que incluya las entidades Tenant, TenantConfig, TenantPlan y los value objects asociados. Este modelo debe soportar tenants con diferentes estados (active, suspended, trial), diferentes planes (free, basic, pro, enterprise), configuracion de branding, feature toggles, y modelos de revenue configurables. El tenant por defecto (AgentsMX) actua como agregador maestro que muestra vehiculos de todos los tenants.

### Microservicio

- **Nombre**: SVC-TNT
- **Puerto**: 5023
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0, Marshmallow 3.x
- **Base de datos**: PostgreSQL 15 (marketplace DB, schema tenants), Redis 7 (cache)
- **Patron**: Hexagonal Architecture (Ports & Adapters)

### Contexto Tecnico

#### Estructura de Archivos

```
svc-tenant/
  app/
    __init__.py
    cfg/
      __init__.py
      settings.py              # Configuracion por entorno
      database.py              # SQLAlchemy engine, session factory
      redis_config.py          # Redis connection pool
    dom/
      __init__.py
      models/
        __init__.py
        tenant.py              # Tenant domain entity (pure Python)
        tenant_config.py       # TenantConfig domain entity
        tenant_plan.py         # TenantPlan domain entity
        value_objects.py       # TenantStatus, PlanType, BillingModel, etc.
      ports/
        __init__.py
        tenant_repository.py   # ABC: TenantRepository
        tenant_config_repo.py  # ABC: TenantConfigRepository
        tenant_cache.py        # ABC: TenantCachePort
      services/
        __init__.py
        tenant_domain_svc.py   # Validaciones de negocio puras
    app/
      __init__.py
      use_cases/
        __init__.py
        create_tenant.py       # Orquesta creacion de tenant
        update_tenant.py       # Actualizar configuracion
        suspend_tenant.py      # Suspender/reactivar tenant
        get_tenant_metrics.py  # Metricas de uso del tenant
    inf/
      __init__.py
      persistence/
        __init__.py
        tenant_orm.py          # SQLAlchemy ORM models
        tenant_repo_impl.py    # Implementacion TenantRepository
        config_repo_impl.py    # Implementacion TenantConfigRepository
      cache/
        __init__.py
        tenant_cache_redis.py  # Cache de tenant config en Redis
      migrations/
        add_tenant_tables.py   # Alembic migration para tablas tenant
    api/
      __init__.py
      routes/
        __init__.py
        tenant_routes.py       # Admin CRUD endpoints
        tenant_config_routes.py # Config endpoints
        health_routes.py       # GET /health
      schemas/
        __init__.py
        tenant_schema.py       # Marshmallow schemas
        config_schema.py       # Config schemas
      middleware/
        __init__.py
        error_handler.py       # Manejo de errores estandar
    tst/
      __init__.py
      unit/
        test_tenant_domain_svc.py
        test_create_tenant.py
        test_value_objects.py
      integration/
        test_tenant_repo.py
        test_tenant_cache.py
      conftest.py
  Dockerfile
  docker-compose.yml
  requirements.txt
  pyproject.toml
  .env.example
```

#### Modelo de Datos - Tenant

```python
# dom/models/tenant.py
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4
from .value_objects import TenantStatus, PlanType

@dataclass
class Tenant:
    id: UUID = field(default_factory=uuid4)
    name: str = ""                               # "Mi Autos Puebla"
    slug: str = ""                               # "mi-autos-puebla"
    status: TenantStatus = TenantStatus.TRIAL
    plan: PlanType = PlanType.FREE
    subdomain: str = ""                          # "miautos" -> miautos.agentsmx.com
    custom_domain: Optional[str] = None          # "www.miautos.com"
    custom_domain_verified: bool = False
    owner_user_id: UUID = field(default_factory=uuid4)
    contact_email: str = ""
    contact_phone: Optional[str] = None
    max_vehicles: int = 50
    max_users: int = 3
    is_master: bool = False                      # True solo para AgentsMX
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    trial_ends_at: Optional[datetime] = None
    suspended_at: Optional[datetime] = None
    suspension_reason: Optional[str] = None
```

```python
# dom/models/tenant_config.py
from dataclasses import dataclass, field
from typing import Optional
from uuid import UUID

@dataclass
class BrandingConfig:
    logo_url: Optional[str] = None
    logo_dark_url: Optional[str] = None
    favicon_url: Optional[str] = None
    primary_color: str = "#2563EB"               # Blue default
    secondary_color: str = "#1E40AF"
    accent_color: str = "#F59E0B"
    background_color: str = "#FFFFFF"
    text_color: str = "#1F2937"
    font_family: str = "Inter"
    heading_font_family: str = "Inter"
    border_radius: str = "8px"
    header_style: str = "default"                # default, minimal, centered
    footer_style: str = "default"                # default, minimal, full

@dataclass
class FeaturesEnabled:
    financing: bool = True
    insurance: bool = True
    kyc_verification: bool = True
    chat: bool = True
    analytics: bool = False
    reports: bool = False
    seo_tools: bool = False
    notifications_email: bool = True
    notifications_sms: bool = False
    notifications_push: bool = False
    vehicle_comparison: bool = True
    price_history: bool = True
    favorites: bool = True
    share_social: bool = True

@dataclass
class TenantConfig:
    tenant_id: UUID = field(default_factory=lambda: UUID(int=0))
    branding: BrandingConfig = field(default_factory=BrandingConfig)
    features: FeaturesEnabled = field(default_factory=FeaturesEnabled)
    billing_model: str = "subscription"          # subscription, commission, hybrid
    commission_rate_sale: float = 0.05           # 5% default
    commission_rate_financing: float = 0.02      # 2% financing referral
    commission_rate_insurance: float = 0.03      # 3% insurance referral
    subscription_price_monthly: float = 0.0
    subscription_price_annual: float = 0.0
    default_vehicle_visibility: str = "both"     # tenant_only, agentsmx_only, both
    show_powered_by_badge: bool = True
    custom_css: Optional[str] = None             # Pro/Enterprise only
    custom_header_html: Optional[str] = None     # Enterprise only
    meta_title: Optional[str] = None
    meta_description: Optional[str] = None
    google_analytics_id: Optional[str] = None
    facebook_pixel_id: Optional[str] = None
```

```python
# dom/models/value_objects.py
from enum import Enum

class TenantStatus(Enum):
    TRIAL = "trial"
    ACTIVE = "active"
    SUSPENDED = "suspended"
    CANCELLED = "cancelled"

class PlanType(Enum):
    FREE = "free"
    BASIC = "basic"
    PRO = "pro"
    ENTERPRISE = "enterprise"

class BillingModel(Enum):
    SUBSCRIPTION = "subscription"
    COMMISSION = "commission"
    HYBRID = "hybrid"

class VehicleVisibility(Enum):
    TENANT_ONLY = "tenant_only"
    AGENTSMX_ONLY = "agentsmx_only"
    BOTH = "both"
    PRIVATE = "private"
```

#### ORM Model - SQLAlchemy

```python
# inf/persistence/tenant_orm.py
from sqlalchemy import Column, String, Boolean, Float, Integer, DateTime, Enum, JSON
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import relationship
from app.cfg.database import Base
import uuid

class TenantORM(Base):
    __tablename__ = "tenants"

    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(200), nullable=False)
    slug = Column(String(100), nullable=False, unique=True, index=True)
    status = Column(Enum("trial","active","suspended","cancelled", name="tenant_status"),
                    nullable=False, default="trial")
    plan = Column(Enum("free","basic","pro","enterprise", name="plan_type"),
                  nullable=False, default="free")
    subdomain = Column(String(63), nullable=False, unique=True, index=True)
    custom_domain = Column(String(253), nullable=True, unique=True, index=True)
    custom_domain_verified = Column(Boolean, default=False)
    owner_user_id = Column(PG_UUID(as_uuid=True), nullable=False, index=True)
    contact_email = Column(String(254), nullable=False)
    contact_phone = Column(String(20), nullable=True)
    max_vehicles = Column(Integer, nullable=False, default=50)
    max_users = Column(Integer, nullable=False, default=3)
    is_master = Column(Boolean, default=False)
    created_at = Column(DateTime, nullable=False, server_default="now()")
    updated_at = Column(DateTime, nullable=False, server_default="now()", onupdate="now()")
    trial_ends_at = Column(DateTime, nullable=True)
    suspended_at = Column(DateTime, nullable=True)
    suspension_reason = Column(String(500), nullable=True)

    config = relationship("TenantConfigORM", uselist=False, back_populates="tenant")

class TenantConfigORM(Base):
    __tablename__ = "tenant_configs"

    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(PG_UUID(as_uuid=True), ForeignKey("tenants.id"),
                       nullable=False, unique=True, index=True)
    branding = Column(JSON, nullable=False, default={})
    features_enabled = Column(JSON, nullable=False, default={})
    billing_model = Column(Enum("subscription","commission","hybrid",
                                name="billing_model"), default="subscription")
    commission_rate_sale = Column(Float, default=0.05)
    commission_rate_financing = Column(Float, default=0.02)
    commission_rate_insurance = Column(Float, default=0.03)
    subscription_price_monthly = Column(Float, default=0.0)
    subscription_price_annual = Column(Float, default=0.0)
    default_vehicle_visibility = Column(String(20), default="both")
    show_powered_by_badge = Column(Boolean, default=True)
    custom_css = Column(String, nullable=True)
    custom_header_html = Column(String, nullable=True)
    meta_title = Column(String(200), nullable=True)
    meta_description = Column(String(500), nullable=True)
    google_analytics_id = Column(String(50), nullable=True)
    facebook_pixel_id = Column(String(50), nullable=True)

    tenant = relationship("TenantORM", back_populates="config")

class CustomDomainMappingORM(Base):
    __tablename__ = "custom_domain_mappings"

    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    domain = Column(String(253), nullable=False, unique=True, index=True)
    tenant_id = Column(PG_UUID(as_uuid=True), ForeignKey("tenants.id"),
                       nullable=False, index=True)
    is_verified = Column(Boolean, default=False)
    ssl_provisioned = Column(Boolean, default=False)
    ssl_certificate_arn = Column(String(500), nullable=True)
    dns_verification_token = Column(String(100), nullable=True)
    verified_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, server_default="now()")
```

#### Port Definition

```python
# dom/ports/tenant_repository.py
from abc import ABC, abstractmethod
from typing import Optional
from uuid import UUID
from ..models.tenant import Tenant

class TenantRepository(ABC):
    @abstractmethod
    def save(self, tenant: Tenant) -> Tenant:
        """Persist a new or updated tenant."""
        ...

    @abstractmethod
    def find_by_id(self, tenant_id: UUID) -> Optional[Tenant]:
        """Find tenant by primary key."""
        ...

    @abstractmethod
    def find_by_slug(self, slug: str) -> Optional[Tenant]:
        """Find tenant by URL slug."""
        ...

    @abstractmethod
    def find_by_subdomain(self, subdomain: str) -> Optional[Tenant]:
        """Find tenant by subdomain prefix."""
        ...

    @abstractmethod
    def find_by_custom_domain(self, domain: str) -> Optional[Tenant]:
        """Find tenant by custom domain."""
        ...

    @abstractmethod
    def find_all(self, status: Optional[str] = None,
                 page: int = 1, page_size: int = 20) -> tuple[list[Tenant], int]:
        """List tenants with optional status filter and pagination."""
        ...

    @abstractmethod
    def count_by_status(self) -> dict[str, int]:
        """Count tenants grouped by status."""
        ...
```

### Criterios de Aceptacion

1. **AC-001**: La entidad Tenant contiene todos los campos requeridos (id UUID, name, slug, status, plan, subdomain, custom_domain, custom_domain_verified, owner_user_id, contact_email, contact_phone, max_vehicles, max_users, is_master, created_at, updated_at, trial_ends_at, suspended_at, suspension_reason) y se persiste correctamente en PostgreSQL.

2. **AC-002**: La entidad TenantConfig almacena branding como JSON (logo_url, logo_dark_url, favicon_url, primary_color, secondary_color, accent_color, background_color, text_color, font_family, heading_font_family, border_radius, header_style, footer_style) y se asocia 1:1 con Tenant via tenant_id.

3. **AC-003**: La entidad TenantConfig almacena features_enabled como JSON con los flags: financing, insurance, kyc_verification, chat, analytics, reports, seo_tools, notifications_email, notifications_sms, notifications_push, vehicle_comparison, price_history, favorites, share_social. Cada flag es booleano y tiene un default definido.

4. **AC-004**: Los value objects TenantStatus (trial/active/suspended/cancelled), PlanType (free/basic/pro/enterprise), BillingModel (subscription/commission/hybrid) y VehicleVisibility (tenant_only/agentsmx_only/both/private) estan implementados como Enums de Python y se validan en la capa de dominio antes de persistir.

5. **AC-005**: Existe un tenant maestro (is_master=True) con un UUID fijo conocido (MASTER_TENANT_ID) que representa a AgentsMX. Este tenant no puede ser suspendido ni eliminado. Las validaciones de dominio rechazan intentos de suspender el tenant maestro con un error TenantDomainError.

6. **AC-006**: El slug del tenant se genera automaticamente a partir del nombre (slugify), es unico, inmutable despues de la creacion, y se valida con regex ^[a-z0-9][a-z0-9-]{2,62}$ (minimo 3 caracteres, maximo 63, solo minusculas, numeros y guiones).

7. **AC-007**: El subdomain se valida como subdominio DNS valido (^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$), es unico en la tabla, y no puede coincidir con subdominios reservados (api, admin, app, www, mail, ftp, staging, dev, test).

8. **AC-008**: El custom_domain se valida como dominio DNS valido, se almacena sin protocolo y sin trailing slash, y tiene un campo booleano is_verified que por defecto es false. La tabla custom_domain_mappings mantiene el mapeo domain -> tenant_id con indices unicos.

9. **AC-009**: Los ports (TenantRepository, TenantConfigRepository, TenantCachePort) estan definidos como ABCs en dom/ports/ con type hints completos. Ningun import de infrastructure existe en las capas dom/ o app/. Las implementaciones en inf/ dependen de los ports, no al reves.

10. **AC-010**: Los tests unitarios cubren al menos 90% de la capa de dominio: validacion de slug, validacion de subdomain, validacion de status transitions (trial->active, active->suspended, suspended->active, cancelled es estado final), y validacion de limites por plan.

11. **AC-011**: La configuracion de billing_model, commission_rate_sale, commission_rate_financing, commission_rate_insurance se almacena en TenantConfig con valores default razonables (5%, 2%, 3% respectivamente). Las tasas de comision se validan entre 0.0 y 1.0 (0% a 100%).

12. **AC-012**: El dominio Tenant implementa transiciones de estado validas: TRIAL puede pasar a ACTIVE o CANCELLED. ACTIVE puede pasar a SUSPENDED o CANCELLED. SUSPENDED puede pasar a ACTIVE o CANCELLED. CANCELLED es estado final. Transiciones invalidas lanzan TenantStatusTransitionError.

### Definition of Done

- [ ] Codigo implementado con cobertura de tests >= 90% en capa domain
- [ ] Tests unitarios para todas las validaciones de dominio (slug, subdomain, status transitions)
- [ ] Tests unitarios para value objects y sus validaciones
- [ ] Modelo ORM creado y migrado con Alembic
- [ ] Port definitions completos con type hints
- [ ] Dockerfile funcional con multi-stage build
- [ ] docker-compose.yml con SVC-TNT + PostgreSQL + Redis
- [ ] Variables de entorno documentadas en .env.example
- [ ] Logs estructurados en formato JSON con structlog
- [ ] Code review aprobado por al menos 1 peer
- [ ] Documentacion de API en docstrings completa

### Notas Tecnicas

- El UUID del tenant maestro AgentsMX debe ser una constante conocida (ej: 00000000-0000-0000-0000-000000000001) para facilitar migraciones y queries
- Usar SQLAlchemy 2.0 style con select() en lugar de query()
- El branding y features_enabled se almacenan como JSON en PostgreSQL para flexibilidad, pero se mapean a dataclasses en el dominio
- Considerar particionamiento por tenant_id en tablas de alto volumen (vehicles, price_history) en el futuro
- Redis TTL para cache de tenant config: 5 minutos (balancear entre consistencia y performance)

### Dependencias

- PostgreSQL 15 corriendo con extensiones uuid-ossp y pgcrypto
- Redis 7 para cache de configuracion
- Ninguna dependencia de otros microservicios (es un servicio independiente)
- EP-001 completado (API Gateway funcional para routing)

---

## User Story 2: [MKT-BE-032][SVC-TNT-API] API de Gestion de Tenants (CRUD)

### Descripcion

Como super administrador de AgentsMX, necesito una API RESTful completa para crear, leer, actualizar, suspender y activar tenants. Esta API es de uso interno (super admin) y permite gestionar todo el ciclo de vida de un tenant: desde su creacion con plan trial, pasando por la activacion con plan pagado, hasta la suspension por falta de pago o la cancelacion.

### Microservicio

- **Nombre**: SVC-TNT
- **Puerto**: 5023
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0, Marshmallow 3.x
- **Base de datos**: PostgreSQL 15, Redis 7
- **Patron**: Hexagonal Architecture - API Layer

### Contexto Tecnico

#### Endpoints

```
# Tenant Management (Super Admin Only)
POST   /api/v1/admin/tenants                    -> Create new tenant
GET    /api/v1/admin/tenants                    -> List all tenants (paginated, filterable)
GET    /api/v1/admin/tenants/:id                -> Get tenant detail with config
PUT    /api/v1/admin/tenants/:id                -> Update tenant info
DELETE /api/v1/admin/tenants/:id                -> Soft delete (cancel) tenant
PUT    /api/v1/admin/tenants/:id/suspend        -> Suspend tenant
PUT    /api/v1/admin/tenants/:id/activate       -> Activate tenant
GET    /api/v1/admin/tenants/:id/metrics        -> Usage metrics for tenant
GET    /api/v1/admin/tenants/:id/audit-log      -> Audit log for tenant

# Health
GET    /health                                   -> Service health
```

#### Request/Response - Create Tenant

```json
// POST /api/v1/admin/tenants
// Request Body
{
  "name": "Mi Autos Puebla",
  "subdomain": "miautos",
  "contact_email": "admin@miautos.com",
  "contact_phone": "+5212221234567",
  "plan": "basic",
  "owner_user_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "branding": {
    "primary_color": "#E11D48",
    "secondary_color": "#BE123C",
    "accent_color": "#FB923C"
  },
  "features": {
    "financing": true,
    "insurance": true,
    "chat": true,
    "kyc_verification": false
  }
}

// Response 201
{
  "data": {
    "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "name": "Mi Autos Puebla",
    "slug": "mi-autos-puebla",
    "subdomain": "miautos",
    "custom_domain": null,
    "status": "trial",
    "plan": "basic",
    "contact_email": "admin@miautos.com",
    "max_vehicles": 500,
    "max_users": 10,
    "trial_ends_at": "2026-04-23T00:00:00Z",
    "created_at": "2026-03-24T10:00:00Z",
    "urls": {
      "subdomain_url": "https://miautos.agentsmx.com",
      "admin_url": "https://miautos.agentsmx.com/admin"
    }
  }
}
```

#### Request/Response - List Tenants

```json
// GET /api/v1/admin/tenants?status=active&plan=pro&page=1&page_size=20
// Response 200
{
  "data": [
    {
      "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "name": "Mi Autos Puebla",
      "slug": "mi-autos-puebla",
      "status": "active",
      "plan": "pro",
      "subdomain": "miautos",
      "custom_domain": "www.miautos.com",
      "vehicle_count": 234,
      "user_count": 5,
      "created_at": "2026-03-24T10:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "page_size": 20,
    "total_items": 45,
    "total_pages": 3
  }
}
```

#### Request/Response - Suspend Tenant

```json
// PUT /api/v1/admin/tenants/:id/suspend
// Request Body
{
  "reason": "Falta de pago - 30 dias vencido"
}

// Response 200
{
  "data": {
    "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "status": "suspended",
    "suspended_at": "2026-03-24T15:30:00Z",
    "suspension_reason": "Falta de pago - 30 dias vencido"
  }
}
```

#### Request/Response - Tenant Metrics

```json
// GET /api/v1/admin/tenants/:id/metrics
// Response 200
{
  "data": {
    "tenant_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "period": "current_month",
    "vehicles": {
      "total": 234,
      "active": 210,
      "limit": 500,
      "usage_percent": 46.8
    },
    "users": {
      "total": 5,
      "active": 4,
      "limit": 10,
      "usage_percent": 50.0
    },
    "transactions": {
      "total": 12,
      "revenue_mxn": 450000.00,
      "commission_mxn": 13500.00
    },
    "traffic": {
      "page_views": 15230,
      "unique_visitors": 4521,
      "avg_session_duration_seconds": 185
    }
  }
}
```

#### Marshmallow Schemas

```python
# api/schemas/tenant_schema.py
from marshmallow import Schema, fields, validate, validates, ValidationError

class BrandingSchema(Schema):
    logo_url = fields.Url(allow_none=True)
    logo_dark_url = fields.Url(allow_none=True)
    favicon_url = fields.Url(allow_none=True)
    primary_color = fields.String(validate=validate.Regexp(r'^#[0-9A-Fa-f]{6}$'))
    secondary_color = fields.String(validate=validate.Regexp(r'^#[0-9A-Fa-f]{6}$'))
    accent_color = fields.String(validate=validate.Regexp(r'^#[0-9A-Fa-f]{6}$'))
    background_color = fields.String(validate=validate.Regexp(r'^#[0-9A-Fa-f]{6}$'))
    text_color = fields.String(validate=validate.Regexp(r'^#[0-9A-Fa-f]{6}$'))
    font_family = fields.String(validate=validate.Length(max=100))
    border_radius = fields.String(validate=validate.Regexp(r'^\d+px$'))

class FeaturesSchema(Schema):
    financing = fields.Boolean()
    insurance = fields.Boolean()
    kyc_verification = fields.Boolean()
    chat = fields.Boolean()
    analytics = fields.Boolean()
    reports = fields.Boolean()
    seo_tools = fields.Boolean()

class CreateTenantSchema(Schema):
    name = fields.String(required=True, validate=validate.Length(min=3, max=200))
    subdomain = fields.String(required=True,
                              validate=validate.Regexp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'))
    contact_email = fields.Email(required=True)
    contact_phone = fields.String(validate=validate.Regexp(r'^\+\d{10,15}$'))
    plan = fields.String(validate=validate.OneOf(["free","basic","pro","enterprise"]))
    owner_user_id = fields.UUID(required=True)
    branding = fields.Nested(BrandingSchema, load_default={})
    features = fields.Nested(FeaturesSchema, load_default={})

    @validates("subdomain")
    def validate_subdomain_not_reserved(self, value: str) -> None:
        reserved = {"api","admin","app","www","mail","ftp","staging","dev","test",
                     "dashboard","console","portal","support","help","docs","status"}
        if value in reserved:
            raise ValidationError(f"Subdomain '{value}' is reserved.")

class UpdateTenantSchema(Schema):
    name = fields.String(validate=validate.Length(min=3, max=200))
    contact_email = fields.Email()
    contact_phone = fields.String(validate=validate.Regexp(r'^\+\d{10,15}$'))
    plan = fields.String(validate=validate.OneOf(["free","basic","pro","enterprise"]))
    max_vehicles = fields.Integer(validate=validate.Range(min=1))
    max_users = fields.Integer(validate=validate.Range(min=1))
    branding = fields.Nested(BrandingSchema)
    features = fields.Nested(FeaturesSchema)

class TenantResponseSchema(Schema):
    id = fields.UUID()
    name = fields.String()
    slug = fields.String()
    subdomain = fields.String()
    custom_domain = fields.String(allow_none=True)
    custom_domain_verified = fields.Boolean()
    status = fields.String()
    plan = fields.String()
    contact_email = fields.Email()
    max_vehicles = fields.Integer()
    max_users = fields.Integer()
    is_master = fields.Boolean()
    created_at = fields.DateTime()
    updated_at = fields.DateTime()
    trial_ends_at = fields.DateTime(allow_none=True)
```

### Criterios de Aceptacion

1. **AC-001**: POST /api/v1/admin/tenants crea un tenant con estado "trial", genera slug automatico desde el nombre, asigna limites segun el plan seleccionado (free: 50 vehiculos/3 usuarios, basic: 500/10, pro: unlimited/50, enterprise: unlimited/unlimited), y retorna 201 con el tenant creado incluyendo URLs de subdomain.

2. **AC-002**: POST /api/v1/admin/tenants valida que el subdomain no este en la lista de reservados (api, admin, app, www, mail, ftp, staging, dev, test, dashboard, console, portal, support, help, docs, status), que sea unico en la base de datos, y que cumpla el formato DNS valido. Retorna 409 si el subdomain ya existe y 422 si es invalido.

3. **AC-003**: GET /api/v1/admin/tenants soporta paginacion (page, page_size con default 20, max 100), filtrado por status (trial/active/suspended/cancelled), filtrado por plan (free/basic/pro/enterprise), busqueda por nombre (query param search, ILIKE), y ordenamiento por created_at o name (sort_by, sort_order).

4. **AC-004**: GET /api/v1/admin/tenants/:id retorna el tenant completo con su TenantConfig embebido (branding, features, billing config). Retorna 404 si el tenant no existe. Incluye conteos actuales de vehiculos y usuarios para mostrar el uso vs limites.

5. **AC-005**: PUT /api/v1/admin/tenants/:id permite actualizar name, contact_email, contact_phone, plan, max_vehicles, max_users, branding y features. El slug y subdomain son inmutables despues de la creacion. Retorna 422 si se intenta cambiar el slug.

6. **AC-006**: PUT /api/v1/admin/tenants/:id/suspend cambia el status a "suspended", registra suspended_at con timestamp actual, almacena el suspension_reason, y emite un evento SQS "tenant.suspended" que notifica al tenant via email. Un tenant maestro (is_master=True) no puede ser suspendido, retorna 403.

7. **AC-007**: PUT /api/v1/admin/tenants/:id/activate cambia el status de "trial" o "suspended" a "active". Si viene de "trial", verifica que tenga un metodo de pago registrado (o plan free). Si viene de "suspended", limpia suspended_at y suspension_reason. Emite evento "tenant.activated".

8. **AC-008**: GET /api/v1/admin/tenants/:id/metrics retorna metricas de uso del tenant: total vehiculos (activos/inactivos vs limite), total usuarios (activos vs limite), transacciones del mes actual (count, revenue_mxn, commission_mxn), y trafico (page_views, unique_visitors). Los datos se agregan de las tablas existentes filtradas por tenant_id.

9. **AC-009**: Todos los endpoints de admin requieren autenticacion JWT con rol "super_admin" en el claim cognito:groups. Requests sin token retornan 401, requests con token pero sin rol super_admin retornan 403 con mensaje descriptivo.

10. **AC-010**: La creacion de tenant genera automaticamente un TenantConfig con valores default segun el plan: Free (badge obligatorio, sin custom domain, features basicos), Basic (badge obligatorio, subdomain, financing+insurance), Pro (badge removible, custom domain, todos los features), Enterprise (todo habilitado + custom CSS/HTML).

11. **AC-011**: DELETE /api/v1/admin/tenants/:id realiza soft delete cambiando status a "cancelled". No elimina datos, solo marca como cancelado. Los vehiculos del tenant dejan de aparecer en AgentsMX. El tenant no puede ser reactivado despues de cancelar (estado final). Retorna 403 si es tenant maestro.

12. **AC-012**: Cada mutacion (create, update, suspend, activate, cancel) genera un registro en la tabla tenant_audit_log con: tenant_id, action, actor_user_id, previous_state (JSON), new_state (JSON), timestamp. GET /api/v1/admin/tenants/:id/audit-log retorna este historial paginado.

13. **AC-013**: El cache de Redis se invalida automaticamente en cada mutacion del tenant (update, suspend, activate). La key de cache sigue el patron "tenant:{id}:config" y "tenant:domain:{domain}" con TTL de 5 minutos.

14. **AC-014**: Todos los endpoints retornan errores en el formato estandar del marketplace: {"error": {"code": "TENANT_NOT_FOUND", "message": "...", "status": 404, "request_id": "...", "timestamp": "..."}}. Los codigos de error incluyen: TENANT_NOT_FOUND, TENANT_ALREADY_EXISTS, SUBDOMAIN_RESERVED, SUBDOMAIN_TAKEN, INVALID_STATUS_TRANSITION, MASTER_TENANT_PROTECTED.

### Definition of Done

- [ ] Todos los endpoints implementados y funcionando
- [ ] Marshmallow schemas con validaciones completas
- [ ] Tests unitarios para use cases (create, update, suspend, activate)
- [ ] Tests de integracion con PostgreSQL real via TestClient
- [ ] Paginacion, filtrado y busqueda verificados
- [ ] Audit log funcional y consultable
- [ ] Cache Redis invalidado correctamente en mutaciones
- [ ] Error handling estandar con codigos especificos
- [ ] Cobertura >= 85% global, 100% en domain
- [ ] Code review aprobado

### Notas Tecnicas

- Usar Flask-RESTful o Flask blueprints para organizar rutas
- Marshmallow load() para validacion de input, dump() para serializar output
- Considerar rate limiting especifico para endpoints de admin (mas permisivo)
- Los eventos SQS para tenant.suspended / tenant.activated se implementaran como fire-and-forget; si SQS falla, la operacion principal no debe fallar
- Usar structlog para logging con tenant_id como campo contextual

### Dependencias

- Story MKT-BE-031 completada (modelos de dominio)
- SVC-AUTH funcional con soporte de rol super_admin
- Redis 7 para cache
- SQS para eventos (puede ser mock en dev con localstack)

---

## User Story 3: [MKT-BE-033][SVC-GW-INF] Tenant Resolution Middleware

### Descripcion

Como API Gateway, necesito un middleware que resuelva automaticamente el tenant de cada request entrante basandose en tres estrategias: (1) subdomain del Host header (miautos.agentsmx.com -> tenant "miautos"), (2) custom domain del Host header (www.miautos.com -> lookup en tabla custom_domain_mappings), o (3) header explicito X-Tenant-ID (para llamadas internas entre servicios). El tenant resuelto se inyecta en el contexto del request y se propaga a todos los servicios downstream.

### Microservicio

- **Nombre**: SVC-GW (modificacion del gateway existente)
- **Puerto**: 8080
- **Tecnologia**: Python 3.11, Flask 3.0
- **Base de datos**: Redis 7 (cache de resoluciones)
- **Patron**: Middleware Chain (extension del gateway existente)

### Contexto Tecnico

#### Flujo de Resolucion

```
Request entrante
  |
  v
1. Extraer Host header
  |
  v
2. Es *.agentsmx.com?
  |-- SI --> Extraer subdomain --> Buscar en cache/DB --> tenant_id
  |-- NO --> Es custom domain? --> Buscar en custom_domain_mappings --> tenant_id
  |
  v
3. No se resolvio por Host? --> Buscar X-Tenant-ID header --> tenant_id
  |
  v
4. No se resolvio? --> Default: Master Tenant (AgentsMX)
  |
  v
5. Tenant encontrado? --> Verificar status != suspended/cancelled
  |-- Suspended --> 503 "Sitio temporalmente no disponible"
  |-- Cancelled --> 404 "Sitio no encontrado"
  |-- Active/Trial --> Continuar
  |
  v
6. Inyectar headers: X-Tenant-ID, X-Tenant-Slug, X-Tenant-Plan
  |
  v
7. Propagar a servicio downstream
```

#### Middleware Code Structure

```python
# svc-gateway/app/api/middleware/tenant_resolution_middleware.py
from flask import request, g
from typing import Optional
from uuid import UUID

MASTER_TENANT_ID = "00000000-0000-0000-0000-000000000001"
AGENTSMX_DOMAINS = {"agentsmx.com", "www.agentsmx.com"}
SUBDOMAIN_PATTERN = re.compile(r'^([a-z0-9][a-z0-9-]*[a-z0-9]?)\.agentsmx\.com$')

class TenantResolutionMiddleware:
    def __init__(self, tenant_cache: TenantCachePort,
                 tenant_repo: TenantRepository):
        self._cache = tenant_cache
        self._repo = tenant_repo

    def resolve(self) -> TenantContext:
        host = request.host.lower().split(':')[0]  # Remove port
        tenant = self._resolve_by_subdomain(host)
        if not tenant:
            tenant = self._resolve_by_custom_domain(host)
        if not tenant:
            tenant = self._resolve_by_header()
        if not tenant:
            tenant = self._get_master_tenant()
        self._validate_tenant_status(tenant)
        return tenant
```

#### Cache Strategy

```python
# Cache keys and TTLs
TENANT_CACHE_PREFIX = "tenant"
CACHE_TTL_SECONDS = 300  # 5 minutes

# Cache key patterns:
# "tenant:subdomain:{subdomain}" -> tenant_id
# "tenant:domain:{domain}" -> tenant_id
# "tenant:id:{tenant_id}" -> full tenant context JSON
# "tenant:config:{tenant_id}" -> tenant config JSON
```

#### Gateway Route Updates

```
# New routes for tenant resolution
ANY  /api/v1/tenants/**                -> SVC-TNT:5023
ANY  /api/v1/admin/tenants/**          -> SVC-TNT:5023
ANY  /api/v1/whitelabel/**             -> SVC-WHL:5024

# Updated health check
GET  /health                           -> Includes SVC-TNT and SVC-WHL
```

#### DNS Configuration

```
# Wildcard DNS for subdomains
*.agentsmx.com    A     <ALB_IP>
*.agentsmx.com    AAAA  <ALB_IPv6>

# Main domain
agentsmx.com      A     <ALB_IP>
www.agentsmx.com  CNAME agentsmx.com

# Example tenant custom domain (tenant configures this in their DNS)
www.miautos.com   CNAME custom.agentsmx.com
```

### Criterios de Aceptacion

1. **AC-001**: El middleware extrae correctamente el subdomain del Host header. Una request a "miautos.agentsmx.com" resuelve al tenant con subdomain="miautos". Una request a "www.agentsmx.com" o "agentsmx.com" resuelve al tenant maestro (AgentsMX).

2. **AC-002**: El middleware resuelve custom domains consultando la tabla custom_domain_mappings. Una request a "www.miautos.com" busca primero en cache Redis, si no existe busca en la tabla, y retorna el tenant_id correspondiente. Solo dominios con is_verified=true y ssl_provisioned=true se resuelven.

3. **AC-003**: El header X-Tenant-ID tiene la menor prioridad y se usa solo para comunicacion inter-servicio. Si el Host header ya resolvio un tenant, X-Tenant-ID se ignora. El header solo se acepta en requests internas (verificado por IP o token de servicio).

4. **AC-004**: Si no se puede resolver ningun tenant (Host desconocido, sin X-Tenant-ID), el middleware defaultea al tenant maestro AgentsMX con MASTER_TENANT_ID. Esto garantiza que agentsmx.com siempre funcione.

5. **AC-005**: Tenants con status "suspended" retornan HTTP 503 con body {"error": {"code": "TENANT_SUSPENDED", "message": "Este sitio esta temporalmente no disponible"}}. Tenants con status "cancelled" retornan HTTP 404 con body {"error": {"code": "TENANT_NOT_FOUND", "message": "Sitio no encontrado"}}.

6. **AC-006**: El middleware inyecta los headers X-Tenant-ID (UUID), X-Tenant-Slug (string), X-Tenant-Plan (string) en el request antes de proxearlo al servicio downstream. Estos headers se propagan a todos los microservicios que los usan para filtrar datos.

7. **AC-007**: La resolucion usa cache Redis con TTL de 5 minutos. Cache miss resulta en query a DB. El cache se organiza con keys: "tenant:subdomain:{subdomain}", "tenant:domain:{domain}", "tenant:id:{id}". Cache hit rate esperado > 95% en estado estable.

8. **AC-008**: Si Redis no esta disponible, el middleware hace fallback a query directa a la base de datos (graceful degradation). Un log warning se emite cuando Redis esta caido. El servicio no se detiene por falta de cache.

9. **AC-009**: El middleware se ejecuta ANTES del auth middleware y ANTES del rate limiting. El tenant_id se necesita para aplicar rate limits especificos por plan de tenant y para propagar contexto a la autenticacion.

10. **AC-010**: Las rutas del gateway se actualizan para incluir SVC-TNT:5023 (/api/v1/tenants/**, /api/v1/admin/tenants/**) y SVC-WHL:5024 (/api/v1/whitelabel/**). El health check agregado incluye el estado de estos dos nuevos servicios.

11. **AC-011**: La latencia anadida por el middleware de resolucion de tenant es menor a 5ms con cache hit y menor a 50ms con cache miss. Esto se verifica con tests de performance que miden el overhead del middleware.

12. **AC-012**: Los tests incluyen escenarios: subdomain valido, custom domain valido, custom domain no verificado (rechazado), tenant suspendido (503), tenant cancelado (404), fallback a master, header X-Tenant-ID, Redis caido (fallback a DB), dominio desconocido (master).

### Definition of Done

- [ ] Middleware implementado e integrado en el pipeline del gateway
- [ ] Cache Redis funcional con TTL y fallback a DB
- [ ] Tests unitarios para cada estrategia de resolucion
- [ ] Tests de integracion con Redis y PostgreSQL reales
- [ ] Tests de performance verificando latencia < 5ms (cache hit)
- [ ] Rutas del gateway actualizadas para SVC-TNT y SVC-WHL
- [ ] Logging estructurado con tenant_id en cada log line
- [ ] Documentacion de configuracion DNS para subdominios
- [ ] Code review aprobado

### Notas Tecnicas

- Usar el patron de resolver en cadena (chain of responsibility) para las tres estrategias
- El Host header puede incluir puerto en desarrollo (localhost:4200), siempre hacer split(':')[0]
- En desarrollo local, usar /etc/hosts para simular subdominios: 127.0.0.1 miautos.agentsmx.local
- Considerar usar lua_nginx o similar si la resolucion necesita estar antes de Flask (performance critica)
- El wildcard DNS solo funciona para un nivel de subdomain; "sub.sub.agentsmx.com" no se soporta

### Dependencias

- Story MKT-BE-031 completada (modelo de datos con tenant tables)
- Story MKT-BE-032 completada (API de tenants para que existan tenants en DB)
- SVC-GW existente (EP-001) como base
- Redis 7 para cache
- DNS wildcard *.agentsmx.com configurado

---

## User Story 4: [MKT-BE-034][SVC-TNT-INF] Database Migration - Add tenant_id to All Tables

### Descripcion

Como arquitecto del sistema, necesito una migracion de base de datos que agregue la columna tenant_id (UUID) a todas las tablas existentes del marketplace. Esta es la migracion mas critica del sistema multi-tenant: debe ejecutarse sin downtime, con un valor default que asigne todos los registros existentes al tenant maestro AgentsMX, y debe crear los indices compuestos necesarios para que las queries filtradas por tenant_id sean eficientes. Ademas, se implementa Row-Level Security (RLS) en PostgreSQL para garantizar que ningun servicio pueda accidentalmente leer datos de otro tenant.

### Microservicio

- **Nombre**: SVC-TNT (migracion ejecutada desde este servicio)
- **Puerto**: 5023
- **Tecnologia**: Alembic, SQLAlchemy 2.0, PostgreSQL 15
- **Patron**: Database Migration

### Contexto Tecnico

#### Tablas a Modificar

```sql
-- Tablas que reciben tenant_id (UUID, NOT NULL, DEFAULT master_tenant_uuid)
-- Todas las tablas existentes de los 14 servicios:

-- SVC-VEH tables
ALTER TABLE vehicles ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE vehicle_media ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE price_history ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE makes ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE models ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';

-- SVC-USR tables
ALTER TABLE users ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE user_profiles ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE favorites ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE saved_searches ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';

-- SVC-PUR tables
ALTER TABLE purchases ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE purchase_steps ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';

-- SVC-KYC tables
ALTER TABLE kyc_verifications ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE kyc_documents ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';

-- SVC-FIN tables
ALTER TABLE financing_applications ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE financing_offers ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';

-- SVC-INS tables
ALTER TABLE insurance_quotes ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE insurance_policies ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';

-- SVC-NTF tables
ALTER TABLE notifications ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE notification_preferences ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';

-- SVC-CHT tables
ALTER TABLE conversations ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE messages ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';

-- SVC-MKT tables
ALTER TABLE campaigns ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE promotions ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';

-- SVC-RPT tables
ALTER TABLE reports ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE analytics_events ADD COLUMN tenant_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001';
```

#### Indices Compuestos

```sql
-- Indices compuestos para queries eficientes filtradas por tenant_id
-- Patron: idx_{table}_{tenant_id}_{existing_index_columns}

CREATE INDEX CONCURRENTLY idx_vehicles_tenant_status ON vehicles(tenant_id, status);
CREATE INDEX CONCURRENTLY idx_vehicles_tenant_make ON vehicles(tenant_id, make_id);
CREATE INDEX CONCURRENTLY idx_vehicles_tenant_price ON vehicles(tenant_id, price);
CREATE INDEX CONCURRENTLY idx_vehicles_tenant_created ON vehicles(tenant_id, created_at DESC);
CREATE INDEX CONCURRENTLY idx_vehicles_tenant_visibility ON vehicles(tenant_id, visibility);

CREATE INDEX CONCURRENTLY idx_users_tenant_email ON users(tenant_id, email);
CREATE INDEX CONCURRENTLY idx_users_tenant_status ON users(tenant_id, status);

CREATE INDEX CONCURRENTLY idx_purchases_tenant_status ON purchases(tenant_id, status);
CREATE INDEX CONCURRENTLY idx_purchases_tenant_created ON purchases(tenant_id, created_at DESC);

CREATE INDEX CONCURRENTLY idx_favorites_tenant_user ON favorites(tenant_id, user_id);
CREATE INDEX CONCURRENTLY idx_conversations_tenant_user ON conversations(tenant_id, user_id);
CREATE INDEX CONCURRENTLY idx_notifications_tenant_user ON notifications(tenant_id, user_id, is_read);

CREATE INDEX CONCURRENTLY idx_price_history_tenant_vehicle ON price_history(tenant_id, vehicle_id, recorded_at DESC);
CREATE INDEX CONCURRENTLY idx_analytics_events_tenant_date ON analytics_events(tenant_id, event_date);
```

#### Row-Level Security

```sql
-- Habilitar RLS en tablas criticas
ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Politica: app user solo ve datos de su tenant
CREATE POLICY tenant_isolation_vehicles ON vehicles
    USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

CREATE POLICY tenant_isolation_users ON users
    USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

CREATE POLICY tenant_isolation_purchases ON purchases
    USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

-- Politica para master tenant: ve todo
CREATE POLICY master_sees_all_vehicles ON vehicles
    USING (current_setting('app.current_tenant_id')::uuid = '00000000-0000-0000-0000-000000000001');

-- Bypass RLS para migraciones y superuser
ALTER TABLE vehicles FORCE ROW LEVEL SECURITY;
-- El usuario de migracion tiene BYPASSRLS
```

#### Alembic Migration Script

```python
# inf/migrations/versions/001_add_tenant_id_to_all_tables.py
"""Add tenant_id to all existing tables for multi-tenant support."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "001_tenant_id"
down_revision = "previous_migration_id"

MASTER_TENANT_ID = "00000000-0000-0000-0000-000000000001"

TABLES_TO_MIGRATE = [
    "vehicles", "vehicle_media", "price_history", "makes", "models",
    "users", "user_profiles", "favorites", "saved_searches",
    "purchases", "purchase_steps",
    "kyc_verifications", "kyc_documents",
    "financing_applications", "financing_offers",
    "insurance_quotes", "insurance_policies",
    "notifications", "notification_preferences",
    "conversations", "messages",
    "campaigns", "promotions",
    "reports", "analytics_events"
]

def upgrade():
    # Step 1: Add column with default (non-blocking)
    for table in TABLES_TO_MIGRATE:
        op.add_column(table,
            sa.Column("tenant_id", UUID(as_uuid=True),
                      nullable=True))  # nullable first for zero-downtime

    # Step 2: Backfill with master tenant ID
    for table in TABLES_TO_MIGRATE:
        op.execute(
            f"UPDATE {table} SET tenant_id = '{MASTER_TENANT_ID}' "
            f"WHERE tenant_id IS NULL"
        )

    # Step 3: Set NOT NULL after backfill
    for table in TABLES_TO_MIGRATE:
        op.alter_column(table, "tenant_id", nullable=False,
                        server_default=MASTER_TENANT_ID)

    # Step 4: Add foreign key to tenants table
    for table in TABLES_TO_MIGRATE:
        op.create_foreign_key(
            f"fk_{table}_tenant_id", table, "tenants",
            ["tenant_id"], ["id"]
        )

def downgrade():
    for table in reversed(TABLES_TO_MIGRATE):
        op.drop_constraint(f"fk_{table}_tenant_id", table)
        op.drop_column(table, "tenant_id")
```

### Criterios de Aceptacion

1. **AC-001**: La columna tenant_id (UUID, NOT NULL) se agrega a todas las 26 tablas listadas sin downtime. La migracion usa el patron add-nullable -> backfill -> set-not-null para evitar locks exclusivos en tablas grandes.

2. **AC-002**: Todos los registros existentes reciben el valor default MASTER_TENANT_ID (00000000-0000-0000-0000-000000000001) correspondiente al tenant maestro AgentsMX. Se verifica con query: SELECT COUNT(*) FROM vehicles WHERE tenant_id != MASTER_TENANT_ID debe ser 0 despues de la migracion.

3. **AC-003**: Se crean indices compuestos CONCURRENTLY para las combinaciones mas frecuentes: (tenant_id, status), (tenant_id, make_id), (tenant_id, price), (tenant_id, created_at), (tenant_id, user_id), (tenant_id, email). La creacion con CONCURRENTLY evita locks de tabla.

4. **AC-004**: La foreign key fk_{table}_tenant_id referencia la tabla tenants(id) en todas las tablas migradas. INSERT con tenant_id inexistente falla con foreign key violation.

5. **AC-005**: Row-Level Security se habilita en las tablas criticas (vehicles, users, purchases, favorites, conversations, notifications). La politica tenant_isolation garantiza que queries con SET app.current_tenant_id = '{uuid}' solo retornan filas de ese tenant.

6. **AC-006**: La politica master_sees_all permite al tenant maestro (AgentsMX) ver registros de todos los tenants. Esto es necesario para el marketplace agregado. Se verifica con: SET app.current_tenant_id = MASTER_TENANT_ID; SELECT COUNT(*) FROM vehicles; retorna el total global.

7. **AC-007**: La migracion de downgrade elimina las foreign keys, los indices y las columnas tenant_id en orden inverso. Se verifica que downgrade + upgrade es idempotente ejecutando ambos en secuencia.

8. **AC-008**: Los 11,000+ vehiculos existentes migran correctamente con tenant_id = MASTER_TENANT_ID. Se verifica que no hay vehiculos huerfanos (sin tenant_id) y que los indices no estan corruptos con REINDEX CONCURRENTLY.

9. **AC-009**: El performance de queries existentes no degrada mas del 10% despues de agregar tenant_id. Se verifican los query plans con EXPLAIN ANALYZE en las 5 queries mas frecuentes (list vehicles, search, detail, favorites, purchases) antes y despues de la migracion.

10. **AC-010**: Cada microservicio existente (SVC-VEH, SVC-USR, SVC-PUR, etc.) puede seguir funcionando sin cambios de codigo inmediatos, porque el default server_default=MASTER_TENANT_ID asegura que registros nuevos sin tenant_id explicito se asignan a AgentsMX.

11. **AC-011**: Un script de validacion post-migracion verifica: (a) todas las tablas tienen tenant_id, (b) no hay NULLs, (c) todos los foreign keys son validos, (d) los indices existen y no estan invalid, (e) RLS esta habilitado en las tablas correctas.

12. **AC-012**: La migracion se ejecuta en menos de 30 minutos para la base de datos actual (11,000+ vehiculos, estimacion de ~50,000 registros totales). Se documenta el plan de ejecucion con tiempos estimados por tabla.

### Definition of Done

- [ ] Script Alembic creado y probado en entorno dev
- [ ] Migracion ejecutada en staging sin errores
- [ ] Indices compuestos creados CONCURRENTLY
- [ ] RLS habilitado y politicas verificadas
- [ ] Script de validacion post-migracion pasa
- [ ] Performance benchmarks antes/despues documentados
- [ ] Downgrade probado y funcional
- [ ] Plan de rollback documentado
- [ ] Tiempo de ejecucion < 30 minutos verificado
- [ ] Code review aprobado por DBA o Tech Lead

### Notas Tecnicas

- Ejecutar la migracion en ventana de bajo trafico (3-5 AM CST)
- Monitorear locks con pg_stat_activity durante la migracion
- CREATE INDEX CONCURRENTLY no puede ejecutarse dentro de una transaccion; Alembic necesita autocommit
- Para tablas con millones de filas en el futuro, considerar batch updates (UPDATE ... LIMIT 10000 en loop)
- El usuario de la aplicacion debe tener SET en app.current_tenant_id; el usuario de migracion necesita BYPASSRLS
- Backup completo de la DB antes de ejecutar

### Dependencias

- Story MKT-BE-031 completada (tabla tenants debe existir antes de agregar foreign keys)
- Acceso a PostgreSQL 15 con permisos de superuser para RLS
- Ventana de mantenimiento aprobada por operaciones

---

## User Story 5: [MKT-INF-004] DNS & Domain Configuration

### Descripcion

Como ingeniero de infraestructura, necesito configurar la infraestructura DNS y SSL para soportar subdominios automaticos (*.agentsmx.com) y dominios custom de tenants. Esto incluye certificado wildcard en AWS ACM, configuracion de ALB con SNI para multiples certificados SSL, CloudFront distributions para CDN, y un sistema automatizado para provisionar SSL en dominios custom via Let's Encrypt o ACM.

### Microservicio

- **Nombre**: Infraestructura (no es microservicio, es configuracion AWS)
- **Tecnologia**: AWS ALB, ACM, Route53, CloudFront, Terraform/CloudFormation
- **Patron**: Infrastructure as Code

### Contexto Tecnico

#### Arquitectura DNS

```
                    Internet
                       |
                       v
              +--------+--------+
              |   Route 53      |
              |   DNS Zones     |
              +--------+--------+
                       |
           +-----------+-----------+
           |                       |
    *.agentsmx.com          custom domains
    (wildcard A record)     (CNAME -> custom.agentsmx.com)
           |                       |
           v                       v
        +--+--+                 +--+--+
        | ALB |<--- SNI ------>| ALB |
        |     |  (same ALB,    |     |
        |     |   different    |     |
        |     |   certs)       |     |
        +--+--+                +--+--+
           |
           v
    +------+------+
    | ECS/Fargate |
    | SVC-GW:8080 |
    | (tenant     |
    |  resolution)|
    +-------------+
```

#### AWS Resources

```hcl
# Route 53 Hosted Zone
resource "aws_route53_zone" "main" {
  name = "agentsmx.com"
}

# Wildcard DNS Record
resource "aws_route53_record" "wildcard" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "*.agentsmx.com"
  type    = "A"
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Wildcard SSL Certificate (ACM)
resource "aws_acm_certificate" "wildcard" {
  domain_name               = "*.agentsmx.com"
  subject_alternative_names = ["agentsmx.com"]
  validation_method         = "DNS"
}

# ALB with multiple SSL certificates (SNI)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.wildcard.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

# Additional certificates for custom domains are added via:
resource "aws_lb_listener_certificate" "custom_domain" {
  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate.custom_domain_cert.arn
}

# CloudFront Distribution for static assets per tenant
resource "aws_cloudfront_distribution" "tenant_cdn" {
  origin {
    domain_name = aws_s3_bucket.tenant_assets.bucket_regional_domain_name
    origin_id   = "S3-tenant-assets"
  }

  aliases = ["cdn.agentsmx.com"]

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-tenant-assets"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cdn_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
```

#### Custom Domain SSL Automation Flow

```
1. Tenant configures custom domain via admin UI
   |
   v
2. System generates DNS verification token (CNAME record)
   - _acme-challenge.www.miautos.com -> token.acm-validations.aws
   |
   v
3. Tenant adds CNAME record in their DNS provider
   |
   v
4. Background job polls DNS resolution (every 5 min, max 72 hours)
   |
   v
5. DNS verified -> Request ACM certificate for custom domain
   |
   v
6. ACM validates and issues certificate
   |
   v
7. Certificate attached to ALB listener via SNI
   |
   v
8. ALB listener rule routes custom domain to gateway
   |
   v
9. custom_domain_mappings updated: is_verified=true, ssl_provisioned=true
   |
   v
10. Tenant's custom domain is live with HTTPS
```

### Criterios de Aceptacion

1. **AC-001**: Un registro DNS wildcard *.agentsmx.com tipo A apunta al ALB. Cualquier subdomain (ejemplo: miautos.agentsmx.com, cochesbajio.agentsmx.com) resuelve correctamente al ALB sin necesidad de crear registros individuales.

2. **AC-002**: Un certificado wildcard SSL de AWS ACM cubre *.agentsmx.com y agentsmx.com como SAN. El certificado se renueva automaticamente 30 dias antes de expirar. Se verifica con: curl -v https://test.agentsmx.com muestra certificado valido para *.agentsmx.com.

3. **AC-003**: El ALB usa TLS 1.3 como protocolo minimo (policy ELBSecurityPolicy-TLS13-1-2-2021-06). Conexiones con TLS 1.1 o inferior son rechazadas. Se verifica con: openssl s_client -connect agentsmx.com:443 muestra TLSv1.3.

4. **AC-004**: El ALB soporta SNI (Server Name Indication) para servir multiples certificados SSL. El certificado wildcard sirve para todos los subdominios, y certificados adicionales se pueden agregar via aws_lb_listener_certificate para dominios custom.

5. **AC-005**: El flujo de verificacion de dominio custom funciona: (a) sistema genera token CNAME, (b) tenant agrega registro DNS, (c) job de polling verifica resolucion cada 5 minutos, (d) tras verificacion exitosa, se solicita certificado ACM, (e) tras emision del certificado, se adjunta al ALB listener.

6. **AC-006**: Si la verificacion DNS no se completa en 72 horas, el intento se marca como fallido y se notifica al tenant via email con instrucciones para reintentar. El polling se detiene para no consumir recursos indefinidamente.

7. **AC-007**: HTTP a HTTPS redirect esta configurado: todas las requests a puerto 80 retornan 301 a la misma URL en puerto 443. Esto aplica tanto para subdominios como para dominios custom.

8. **AC-008**: CloudFront distribution sirve assets estaticos (logos, imagenes de vehiculos) por tenant desde S3 con prefijo tenant-specific: s3://marketplace-assets/{tenant_id}/. Cache TTL default de 24 horas para imagenes. Cache invalidation API disponible.

9. **AC-009**: La infraestructura esta definida como IaC (Terraform o CloudFormation) en el repositorio. Un cambio en el codigo genera un plan de ejecucion revisable antes de aplicar. Incluye: Route53 zone, wildcard record, ACM certificates, ALB configuration, CloudFront distribution.

10. **AC-010**: Existe un health check en el ALB que verifica /health del gateway cada 30 segundos. Si el gateway esta unhealthy, el ALB deja de rutear trafico. El health check incluye verificacion de dependencias criticas (PostgreSQL, Redis).

11. **AC-011**: Se pueden agregar hasta 25 certificados SSL adicionales al ALB listener (limite de AWS). Para tenants que excedan este limite, se documenta la estrategia de escalar con ALBs adicionales o usar CloudFront con custom SSL.

12. **AC-012**: Los costos estimados se documentan: ALB ($0.0225/hora + LCU), ACM certificates (gratis), Route53 ($0.50/hosted zone + $0.40/M queries), CloudFront (primeros 1TB gratis). El costo mensual estimado para 20 tenants con custom domain es menor a $150 USD.

### Definition of Done

- [ ] Terraform/CloudFormation code en repositorio
- [ ] Wildcard DNS configurado y probado
- [ ] Certificado wildcard SSL emitido y activo
- [ ] ALB con SNI configurado y probado
- [ ] HTTP -> HTTPS redirect funcional
- [ ] CloudFront distribution creada y probada
- [ ] Flujo de custom domain documentado paso a paso
- [ ] Costos estimados documentados
- [ ] Tests de conectividad SSL desde multiples regiones
- [ ] Code review de IaC aprobado

### Notas Tecnicas

- ACM certificates son gratis en AWS pero solo funcionan con servicios AWS (ALB, CloudFront)
- El limite de 25 certificados por ALB listener es hard limit de AWS; para escalar, considerar ALBs por grupo de tenants
- CloudFront puede manejar custom domains directamente con certificados propios, pero agrega complejidad
- Para Mexico, la latencia a us-east-1 es ~50ms; considerar us-west-2 o sa-east-1 para menor latencia
- Wildcard DNS solo cubre un nivel: *.agentsmx.com cubre foo.agentsmx.com pero NO foo.bar.agentsmx.com

### Dependencias

- Cuenta AWS con permisos para Route53, ACM, ALB, CloudFront, S3
- Dominio agentsmx.com registrado y nameservers apuntando a Route53
- EP-001 completado (ALB y gateway existentes)
- Presupuesto AWS aprobado (~$150/mes para 20 tenants)

---

## User Story 6: [MKT-BE-035][SVC-AUTH-INF] Multi-Tenant Authentication

### Descripcion

Como sistema de autenticacion, necesito soportar usuarios que pertenecen a multiples tenants simultaneamente. Un usuario registrado en miautos.agentsmx.com puede tambien iniciar sesion en agentsmx.com con las mismas credenciales. El JWT token debe incluir un claim tenant_id que indica en que contexto esta operando el usuario actualmente, y el sistema debe soportar cambio de contexto entre tenants sin necesidad de re-autenticarse.

### Microservicio

- **Nombre**: SVC-AUTH (modificacion del servicio existente)
- **Puerto**: 5010
- **Tecnologia**: Python 3.11, Flask 3.0, AWS Cognito
- **Base de datos**: PostgreSQL 15 (user_tenant_memberships), Redis 7
- **Patron**: Hexagonal Architecture - Extension

### Contexto Tecnico

#### Modelo de Datos - User-Tenant Relationship

```python
# Nuevo modelo: relacion muchos-a-muchos entre users y tenants
@dataclass
class UserTenantMembership:
    id: UUID = field(default_factory=uuid4)
    user_id: UUID = field(default_factory=uuid4)
    tenant_id: UUID = field(default_factory=uuid4)
    role: TenantRole = TenantRole.MEMBER        # member, editor, admin, owner
    is_primary: bool = False                     # Tenant principal del usuario
    joined_at: datetime = field(default_factory=datetime.utcnow)
    invited_by: Optional[UUID] = None
    status: str = "active"                       # active, suspended, removed

class TenantRole(Enum):
    MEMBER = "member"          # Puede comprar/ver vehiculos
    EDITOR = "editor"          # Puede gestionar inventario
    ADMIN = "admin"            # Puede gestionar equipo y config
    OWNER = "owner"            # Dueno del tenant (1 por tenant)
```

```sql
-- ORM Table
CREATE TABLE user_tenant_memberships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    role VARCHAR(20) NOT NULL DEFAULT 'member',
    is_primary BOOLEAN NOT NULL DEFAULT false,
    joined_at TIMESTAMP NOT NULL DEFAULT now(),
    invited_by UUID REFERENCES users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    UNIQUE(user_id, tenant_id)
);

CREATE INDEX idx_membership_user ON user_tenant_memberships(user_id);
CREATE INDEX idx_membership_tenant ON user_tenant_memberships(tenant_id);
```

#### JWT Token Structure (Extended)

```json
{
  "sub": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "email": "juan@email.com",
  "cognito:groups": ["buyer", "tenant_admin"],
  "custom:tenant_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "custom:tenant_slug": "miautos",
  "custom:tenant_role": "admin",
  "custom:tenant_ids": "f47ac10b-...,00000000-...",
  "iat": 1711288800,
  "exp": 1711289700,
  "iss": "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_xxxxx"
}
```

#### Endpoints (Nuevos/Modificados)

```
# Existing endpoints modified for multi-tenant
POST /api/v1/auth/login                 -> Include tenant_id in JWT based on domain
POST /api/v1/auth/register              -> Auto-create membership for current tenant
POST /api/v1/auth/refresh               -> Refresh token maintains tenant context

# New endpoints for tenant context
GET  /api/v1/auth/tenants               -> List tenants user belongs to
POST /api/v1/auth/switch-tenant         -> Switch tenant context (new JWT)
GET  /api/v1/auth/current-context       -> Current user + tenant context
```

#### Request/Response - Login on White Label

```json
// POST /api/v1/auth/login
// Request (on miautos.agentsmx.com - tenant resolved from domain)
{
  "email": "juan@email.com",
  "password": "SecurePass123!"
}

// Response 200
{
  "data": {
    "access_token": "eyJhbGciOiJSUzI1NiIs...",
    "refresh_token": "eyJjdHkiOiJKV1QiLCJl...",
    "expires_in": 900,
    "token_type": "Bearer",
    "user": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "email": "juan@email.com",
      "name": "Juan Perez",
      "current_tenant": {
        "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
        "name": "Mi Autos Puebla",
        "slug": "miautos",
        "role": "member"
      },
      "available_tenants": [
        {
          "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
          "name": "Mi Autos Puebla",
          "slug": "miautos",
          "role": "member"
        },
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "AgentsMX",
          "slug": "agentsmx",
          "role": "member"
        }
      ]
    }
  }
}
```

#### Request/Response - Switch Tenant

```json
// POST /api/v1/auth/switch-tenant
// Request
{
  "tenant_id": "00000000-0000-0000-0000-000000000001"
}

// Response 200
{
  "data": {
    "access_token": "eyJhbGciOiJSUzI1NiIs...",
    "refresh_token": "eyJjdHkiOiJKV1QiLCJl...",
    "expires_in": 900,
    "current_tenant": {
      "id": "00000000-0000-0000-0000-000000000001",
      "name": "AgentsMX",
      "slug": "agentsmx",
      "role": "member"
    }
  }
}
```

#### Cognito Configuration

```python
# AWS Cognito custom attributes for multi-tenant
COGNITO_CUSTOM_ATTRIBUTES = [
    {
        "Name": "custom:tenant_id",
        "AttributeDataType": "String",
        "Mutable": True,
        "StringAttributeConstraints": {"MaxLength": "36"}
    },
    {
        "Name": "custom:tenant_ids",
        "AttributeDataType": "String",
        "Mutable": True,
        "StringAttributeConstraints": {"MaxLength": "2000"}
    },
    {
        "Name": "custom:tenant_role",
        "AttributeDataType": "String",
        "Mutable": True,
        "StringAttributeConstraints": {"MaxLength": "20"}
    }
]
```

### Criterios de Aceptacion

1. **AC-001**: La tabla user_tenant_memberships se crea con campos id, user_id, tenant_id, role, is_primary, joined_at, invited_by, status, y constraint UNIQUE(user_id, tenant_id). Permite que un usuario pertenezca a multiples tenants con diferentes roles.

2. **AC-002**: POST /api/v1/auth/login en un white label (ej: miautos.agentsmx.com) genera un JWT con custom:tenant_id correspondiente al tenant resuelto del dominio. El response incluye current_tenant y available_tenants del usuario.

3. **AC-003**: POST /api/v1/auth/register en un white label crea el usuario en Cognito Y crea automaticamente un UserTenantMembership con role="member" para el tenant actual Y para el tenant maestro AgentsMX. El usuario queda registrado en ambos contextos.

4. **AC-004**: POST /api/v1/auth/switch-tenant valida que el usuario tenga membership activa en el tenant destino, genera un nuevo JWT con el nuevo tenant_id, e invalida el token anterior en Redis (blacklist). Retorna 403 si el usuario no pertenece al tenant.

5. **AC-005**: GET /api/v1/auth/tenants retorna la lista de tenants a los que pertenece el usuario actual con su rol en cada uno. Incluye tenant name, slug, logo_url (del branding) y role. Ordenado por is_primary DESC, joined_at ASC.

6. **AC-006**: Los custom attributes de Cognito (custom:tenant_id, custom:tenant_ids, custom:tenant_role) se actualizan en cada login y switch-tenant. custom:tenant_ids contiene una lista CSV de todos los tenant_ids del usuario para validacion rapida sin DB hit.

7. **AC-007**: Un usuario registrado en miautos.agentsmx.com puede hacer login en www.agentsmx.com con las mismas credenciales. El JWT resultante tendra custom:tenant_id del tenant maestro AgentsMX. El response incluye Mi Autos Puebla en available_tenants.

8. **AC-008**: El rol del usuario en cada tenant es independiente: puede ser "admin" en su propio tenant y "member" en AgentsMX. Los permisos se evaluan basandose en el custom:tenant_role del JWT actual, no en un rol global.

9. **AC-009**: Cuando un tenant se suspende, los memberships de sus usuarios permanecen intactas pero el login en ese tenant retorna 503 (resuelto por el tenant resolution middleware, no por auth). Los usuarios aun pueden usar otros tenants.

10. **AC-010**: El refresh token mantiene el contexto de tenant. POST /api/v1/auth/refresh genera un nuevo access_token con el mismo tenant_id. Si el usuario quiere cambiar de tenant, debe usar switch-tenant explicitamente.

11. **AC-011**: Existe una validacion de que cada tenant tiene exactamente un usuario con role="owner" y al menos un usuario con role="admin". La eliminacion del ultimo admin o owner se rechaza con error LAST_ADMIN_CANNOT_BE_REMOVED.

12. **AC-012**: Los tokens blacklisted (por switch-tenant o logout) se almacenan en Redis con TTL igual al tiempo restante de expiracion del token. El auth middleware verifica el blacklist antes de aceptar un token como valido.

13. **AC-013**: Todos los logs de autenticacion incluyen tenant_id como campo contextual. Un login exitoso genera un log: {"event": "login_success", "user_id": "...", "tenant_id": "...", "tenant_slug": "...", "ip": "..."}. Login fallido incluye tenant_id del dominio intentado.

### Definition of Done

- [ ] Tabla user_tenant_memberships creada con Alembic
- [ ] Cognito custom attributes configurados
- [ ] Login/register modificados para multi-tenant
- [ ] Switch-tenant endpoint funcional con token rotation
- [ ] Tests unitarios para membership logic y role validation
- [ ] Tests de integracion para login cross-tenant
- [ ] Token blacklist en Redis funcional
- [ ] Logging con tenant context verificado
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- AWS Cognito tiene limite de 50 custom attributes; usar CSV en custom:tenant_ids en vez de atributos separados
- El limite de custom:tenant_ids es 2000 chars; con UUIDs de 36 chars + coma, soporta ~55 tenants por usuario
- Para mas de 55 tenants por usuario (unlikely), usar solo la tabla user_tenant_memberships sin custom attribute
- Pre-token generation Lambda trigger de Cognito puede inyectar claims custom en el JWT
- Considerar un endpoint /api/v1/auth/impersonate para super admin (con audit trail estricto)

### Dependencias

- Story MKT-BE-031 completada (tabla tenants)
- Story MKT-BE-034 completada (tenant_id en tabla users)
- SVC-AUTH existente (EP-002) como base
- AWS Cognito User Pool configurado con custom attributes
- Redis 7 para token blacklist
