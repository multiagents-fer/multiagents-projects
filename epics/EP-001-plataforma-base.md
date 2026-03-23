# [MKT-EP-001] Plataforma Base, Arquitectura & Setup Inicial

**Sprint**: 1-2
**Priority**: Critical
**Epic Owner**: Tech Lead
**Estimated Points**: 89
**Teams**: Backend, Frontend, Infrastructure

---

## Resumen del Epic

Este epic establece la base tecnica completa del Vehicle Marketplace. Incluye el API Gateway como punto de entrada unico, el servicio de vehiculos con arquitectura hexagonal, el frontend Angular 18 con design system premium, y toda la infraestructura CI/CD y AWS necesaria para soportar el desarrollo de los demas epics.

## Dependencias Externas

- Cuenta AWS con permisos de administrador
- Repositorio GitHub organizacional creado
- Dominio DNS configurado
- Licencias de herramientas de monitoreo (Datadog/CloudWatch)
- Acceso a base de datos scrapper_nacional (PostgreSQL) con 11,000+ vehiculos

---

## User Story 1: [MKT-BE-001][SVC-GW] API Gateway - Routing, Rate Limiting & Auth Validation

### Descripcion

Como arquitecto del sistema, necesito un API Gateway centralizado que actue como punto de entrada unico para todos los microservicios del marketplace. El gateway debe manejar routing inteligente, rate limiting por tier de usuario, validacion de JWT tokens de AWS Cognito, CORS, request/response transformation, circuit breaker, health checks agregados y logging centralizado.

### Microservicio

- **Nombre**: SVC-GW
- **Puerto**: 8080
- **Tecnologia**: Python 3.11, Flask 3.0
- **Base de datos**: Redis 7 (cache de tokens, rate limiting counters)
- **Patron**: Reverse Proxy + Middleware Chain

### Contexto Tecnico

#### Endpoints del Gateway

```
# Health & Discovery
GET  /health                          -> Gateway health + aggregated services health
GET  /health/:service                 -> Individual service health
GET  /api/v1/discovery                -> Service registry (admin only)

# Proxied Routes (examples)
ANY  /api/v1/auth/**                  -> SVC-AUTH:5010
ANY  /api/v1/users/**                 -> SVC-USR:5011
ANY  /api/v1/vehicles/**              -> SVC-VEH:5012
ANY  /api/v1/purchases/**             -> SVC-PUR:5013
ANY  /api/v1/kyc/**                   -> SVC-KYC:5014
ANY  /api/v1/finance/**               -> SVC-FIN:5015
ANY  /api/v1/insurance/**             -> SVC-INS:5016
ANY  /api/v1/notifications/**         -> SVC-NTF:5017
ANY  /api/v1/chat/**                  -> SVC-CHT:5018
ANY  /api/v1/marketing/**             -> SVC-MKT:5019
ANY  /api/v1/admin/**                 -> SVC-ADM:5020
ANY  /api/v1/reports/**               -> SVC-RPT:5021
ANY  /api/v1/seo/**                   -> SVC-SEO:5022
```

#### Rate Limiting Tiers

```json
{
  "anonymous": {
    "requests_per_minute": 30,
    "requests_per_hour": 500,
    "burst_size": 10
  },
  "authenticated": {
    "requests_per_minute": 120,
    "requests_per_hour": 3000,
    "burst_size": 30
  },
  "dealer": {
    "requests_per_minute": 300,
    "requests_per_hour": 10000,
    "burst_size": 60
  },
  "admin": {
    "requests_per_minute": 1000,
    "requests_per_hour": 50000,
    "burst_size": 200
  }
}
```

#### Estructura de Archivos

```
svc-gateway/
  app/
    __init__.py
    cfg/
      __init__.py
      settings.py              # Configuracion por entorno (dev/staging/prod)
      routes_registry.py       # Mapeo de rutas a servicios
      rate_limit_config.py     # Configuracion de rate limiting por tier
    dom/
      __init__.py
      models/
        route.py               # Route model (path, service, methods, auth_required)
        rate_limit.py          # RateLimitRule, RateLimitCounter
        health.py              # ServiceHealth, AggregatedHealth
      services/
        routing_service.py     # Logica de routing y path matching
        rate_limit_service.py  # Logica de rate limiting (token bucket)
        auth_validation.py     # Validacion de JWT y extraccion de claims
        circuit_breaker.py     # Circuit breaker state machine
    app/
      __init__.py
      use_cases/
        proxy_request.py       # Orquesta: auth -> rate limit -> route -> proxy
        health_check.py        # Agregacion de health checks
        service_discovery.py   # Registro y descubrimiento de servicios
    inf/
      __init__.py
      redis_client.py          # Conexion Redis para cache y counters
      http_proxy.py            # HTTP client para proxying (httpx async)
      cognito_jwks.py          # Cache de JWKS keys de Cognito
      logging_config.py        # Structured logging (JSON format)
      metrics.py               # Prometheus metrics collector
    api/
      __init__.py
      routes/
        health_routes.py       # GET /health, GET /health/:service
        proxy_routes.py        # Catch-all proxy handler
      middleware/
        cors_middleware.py      # CORS headers configuration
        auth_middleware.py      # JWT extraction and validation
        rate_limit_middleware.py # Rate limiting enforcement
        request_id_middleware.py # X-Request-ID generation/propagation
        logging_middleware.py   # Request/response logging
        error_handler.py       # Global error handling and formatting
    tst/
      __init__.py
      unit/
        test_routing_service.py
        test_rate_limit_service.py
        test_auth_validation.py
        test_circuit_breaker.py
      integration/
        test_proxy_request.py
        test_health_check.py
        test_rate_limiting_redis.py
      conftest.py              # Fixtures compartidos
  Dockerfile
  docker-compose.yml
  requirements.txt
  pyproject.toml
  .env.example
```

#### Modelo de Datos - Route Registry

```python
# dom/models/route.py
from dataclasses import dataclass, field
from typing import Optional
from enum import Enum

class AuthLevel(Enum):
    PUBLIC = "public"
    AUTHENTICATED = "authenticated"
    ROLE_REQUIRED = "role_required"
    ADMIN_ONLY = "admin_only"

@dataclass
class RouteConfig:
    path_prefix: str              # e.g., "/api/v1/vehicles"
    target_service: str           # e.g., "SVC-VEH"
    target_host: str              # e.g., "localhost"
    target_port: int              # e.g., 5012
    allowed_methods: list[str]    # e.g., ["GET", "POST", "PUT", "DELETE"]
    auth_level: AuthLevel         # Required auth level
    required_roles: list[str] = field(default_factory=list)
    rate_limit_tier: str = "authenticated"
    timeout_seconds: int = 30
    circuit_breaker_enabled: bool = True
    cache_ttl_seconds: int = 0    # 0 = no cache
    strip_prefix: bool = False
    health_check_path: str = "/health"
```

#### Request/Response - Health Check

```json
// GET /health
// Response 200
{
  "status": "healthy",
  "timestamp": "2026-03-23T10:00:00Z",
  "version": "1.0.0",
  "uptime_seconds": 86400,
  "services": {
    "SVC-AUTH": { "status": "healthy", "latency_ms": 12, "port": 5010 },
    "SVC-USR": { "status": "healthy", "latency_ms": 8, "port": 5011 },
    "SVC-VEH": { "status": "healthy", "latency_ms": 15, "port": 5012 },
    "SVC-PUR": { "status": "degraded", "latency_ms": 250, "port": 5013 },
    "SVC-KYC": { "status": "healthy", "latency_ms": 10, "port": 5014 },
    "SVC-FIN": { "status": "healthy", "latency_ms": 20, "port": 5015 },
    "SVC-INS": { "status": "healthy", "latency_ms": 18, "port": 5016 },
    "SVC-NTF": { "status": "healthy", "latency_ms": 5, "port": 5017 },
    "SVC-CHT": { "status": "unhealthy", "latency_ms": null, "port": 5018, "error": "Connection refused" },
    "SVC-MKT": { "status": "healthy", "latency_ms": 11, "port": 5019 },
    "SVC-ADM": { "status": "healthy", "latency_ms": 9, "port": 5020 },
    "SVC-RPT": { "status": "healthy", "latency_ms": 14, "port": 5021 },
    "SVC-SEO": { "status": "healthy", "latency_ms": 7, "port": 5022 }
  },
  "dependencies": {
    "redis": { "status": "healthy", "latency_ms": 2 },
    "cognito": { "status": "healthy", "latency_ms": 45 }
  }
}
```

#### Request/Response - Error Format

```json
// Standard error response format (all services must follow)
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests. Please retry after 30 seconds.",
    "status": 429,
    "request_id": "req_abc123def456",
    "timestamp": "2026-03-23T10:00:00Z",
    "details": {
      "limit": 30,
      "window": "1m",
      "retry_after_seconds": 30
    }
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: El gateway arranca en el puerto 8080 y responde al endpoint GET /health con status 200 en menos de 100ms, incluyendo el estado agregado de todos los servicios registrados.

2. **AC-002**: Todas las rutas definidas en el routes_registry se proxean correctamente al microservicio destino. Una peticion GET /api/v1/vehicles llega a SVC-VEH:5012/api/v1/vehicles con todos los headers originales mas X-Request-ID y X-Forwarded-For.

3. **AC-003**: El rate limiting funciona con token bucket algorithm en Redis. Un usuario anonimo que excede 30 requests/minuto recibe HTTP 429 con el header Retry-After y el body JSON de error estandar. Los counters se persisten en Redis con TTL automatico.

4. **AC-004**: La validacion JWT funciona contra AWS Cognito JWKS endpoint. Tokens expirados retornan 401, tokens con firma invalida retornan 401, tokens validos propagan los claims (sub, email, roles) como headers X-User-ID, X-User-Email, X-User-Roles al servicio destino.

5. **AC-005**: El circuit breaker implementa tres estados (CLOSED, OPEN, HALF_OPEN). Despues de 5 fallos consecutivos a un servicio, el circuito se abre y retorna 503 inmediatamente por 30 segundos. En HALF_OPEN permite 1 request de prueba.

6. **AC-006**: CORS esta configurado para permitir origenes especificos por entorno (localhost:4200 en dev, dominio produccion en prod). Los preflight OPTIONS requests se responden correctamente con Access-Control-Allow-Headers incluyendo Authorization y Content-Type.

7. **AC-007**: Cada request genera un X-Request-ID unico (UUID v4) si no viene en el request original. Este ID se propaga a todos los servicios downstream y se incluye en todos los logs y responses.

8. **AC-008**: El logging estructurado en formato JSON registra: timestamp, request_id, method, path, status_code, latency_ms, user_id (si autenticado), service_target, rate_limit_remaining. Los logs se envian a stdout para ser capturados por CloudWatch.

9. **AC-009**: El gateway cachea las JWKS keys de Cognito en Redis con TTL de 1 hora. Si Redis no esta disponible, las keys se cachean en memoria local con TTL de 5 minutos como fallback.

10. **AC-010**: Las rutas publicas (marcadas con auth_level=PUBLIC) no requieren JWT token. Las rutas con auth_level=ROLE_REQUIRED validan que el token contenga al menos uno de los roles requeridos en el claim "cognito:groups".

11. **AC-011**: El gateway maneja timeouts de 30 segundos por defecto por servicio (configurable por ruta). Si un servicio no responde en el tiempo configurado, retorna 504 Gateway Timeout con el error estandar.

12. **AC-012**: Existe un endpoint GET /api/v1/discovery (admin only) que retorna el registro completo de servicios con sus estados, versiones y endpoints disponibles.

13. **AC-013**: Las metricas Prometheus se exponen en GET /metrics con: gateway_requests_total, gateway_request_duration_seconds, gateway_circuit_breaker_state, gateway_rate_limit_hits_total, gateway_active_connections.

### Definition of Done

- [ ] Codigo implementado con cobertura de tests >= 85%
- [ ] Tests unitarios para routing_service, rate_limit_service, auth_validation, circuit_breaker
- [ ] Tests de integracion con Redis real y mock services
- [ ] Dockerfile funcional con multi-stage build
- [ ] docker-compose.yml con gateway + Redis + mock services
- [ ] Variables de entorno documentadas en .env.example
- [ ] Logs estructurados verificados con formato JSON valido
- [ ] Rate limiting verificado con tests de carga (k6 o locust)
- [ ] Code review aprobado por al menos 1 peer
- [ ] Desplegado en entorno dev y smoke tests pasando

### Notas Tecnicas

- Usar `httpx` con async para proxying (mejor performance que requests)
- Redis connection pool con max 20 conexiones
- JWKS keys rotation: re-fetch si validacion falla con keys cacheadas
- El gateway NO debe tener logica de negocio, solo routing y cross-cutting concerns
- Considerar usar Werkzeug ProxyFix para headers X-Forwarded-*

### Dependencias

- Redis 7 corriendo (local o Docker)
- AWS Cognito User Pool configurado (puede ser mock en dev)
- Ninguna dependencia de otros microservicios para arrancar (graceful degradation)

---

## User Story 2: [MKT-BE-002][SVC-VEH-CFG] Vehicle Service - Setup Base Hexagonal

### Descripcion

Como desarrollador backend, necesito el servicio de vehiculos configurado con arquitectura hexagonal completa como servicio de referencia para todo el equipo. Este servicio sera el template que seguiran todos los demas microservicios. Debe incluir la estructura de capas (DOM, APP, INF, API, TST, CFG), conexion a PostgreSQL 15 con SQLAlchemy 2.0, schemas con Marshmallow, health check, logging estructurado, y la base para manejar el catalogo de 11,000+ vehiculos.

### Microservicio

- **Nombre**: SVC-VEH
- **Puerto**: 5012
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0, Marshmallow 3.x
- **Base de datos**: PostgreSQL 15 (marketplace DB), Redis 7 (cache)
- **Patron**: Hexagonal Architecture (Ports & Adapters)

### Contexto Tecnico

#### Endpoints Base (Setup)

```
GET  /health                          -> Service health + DB connectivity
GET  /api/v1/vehicles                 -> List vehicles (paginated, cursor-based) [PUBLIC]
GET  /api/v1/vehicles/:id             -> Vehicle detail [PUBLIC]
POST /api/v1/vehicles                 -> Create vehicle [ADMIN/DEALER]
PUT  /api/v1/vehicles/:id             -> Update vehicle [ADMIN/DEALER]
DEL  /api/v1/vehicles/:id             -> Soft delete vehicle [ADMIN]
GET  /api/v1/vehicles/:id/media       -> Vehicle media (photos, videos) [PUBLIC]
GET  /api/v1/vehicles/:id/history     -> Price history [PUBLIC]
GET  /api/v1/vehicles/makes           -> List all makes [PUBLIC]
GET  /api/v1/vehicles/makes/:make/models -> List models by make [PUBLIC]
```

#### Estructura de Archivos

```
svc-vehicle/
  app/
    __init__.py
    cfg/
      __init__.py
      settings.py              # Environment-based config (DB_URL, REDIS_URL, etc.)
      database.py              # SQLAlchemy engine, session factory, Base
      redis_config.py          # Redis connection pool
      elasticsearch_config.py  # ES client configuration
    dom/
      __init__.py
      models/
        __init__.py
        vehicle.py             # Vehicle domain entity (pure Python, no ORM)
        vehicle_media.py       # VehicleMedia domain entity
        price_history.py       # PriceHistory domain entity
        make_model.py          # Make, Model domain entities
        value_objects.py       # VehicleStatus, FuelType, TransmissionType, etc.
      ports/
        __init__.py
        vehicle_repository.py  # Abstract repository interface (Port)
        media_repository.py    # Abstract media repository interface
        cache_port.py          # Abstract cache interface
        search_port.py         # Abstract search engine interface
      services/
        __init__.py
        vehicle_domain_service.py  # Domain logic (price calculation, validation)
      exceptions.py            # Domain exceptions (VehicleNotFound, InvalidVehicle)
    app/
      __init__.py
      use_cases/
        __init__.py
        list_vehicles.py       # ListVehiclesUseCase (pagination, basic filters)
        get_vehicle_detail.py  # GetVehicleDetailUseCase (with media, history)
        create_vehicle.py      # CreateVehicleUseCase (validation, persistence)
        update_vehicle.py      # UpdateVehicleUseCase (partial update)
        delete_vehicle.py      # DeleteVehicleUseCase (soft delete)
        get_makes_models.py    # GetMakesModelsUseCase
      dto/
        __init__.py
        vehicle_dto.py         # Input/Output DTOs for use cases
        pagination_dto.py      # CursorPaginationInput, PaginatedResult
    inf/
      __init__.py
      persistence/
        __init__.py
        sqlalchemy_models.py   # SQLAlchemy ORM models (VehicleModel, etc.)
        vehicle_repository_impl.py  # Concrete repository (SQLAlchemy)
        media_repository_impl.py    # Concrete media repository
      cache/
        __init__.py
        redis_cache_impl.py    # Concrete cache adapter (Redis)
      search/
        __init__.py
        elasticsearch_impl.py  # Concrete search adapter (Elasticsearch)
      mappers/
        __init__.py
        vehicle_mapper.py      # ORM <-> Domain entity mappers
    api/
      __init__.py
      routes/
        __init__.py
        vehicle_routes.py      # Flask Blueprint for /api/v1/vehicles
        health_routes.py       # Flask Blueprint for /health
      schemas/
        __init__.py
        vehicle_schema.py      # Marshmallow schemas (request/response)
        pagination_schema.py   # Pagination query params schema
        error_schema.py        # Standard error response schema
      middleware/
        __init__.py
        error_handler.py       # Global exception to HTTP response mapper
        request_context.py     # Extract user info from gateway headers
    tst/
      __init__.py
      unit/
        dom/
          test_vehicle_domain_service.py
          test_vehicle_entity.py
          test_value_objects.py
        app/
          test_list_vehicles.py
          test_get_vehicle_detail.py
          test_create_vehicle.py
      integration/
        inf/
          test_vehicle_repository.py
          test_redis_cache.py
        api/
          test_vehicle_routes.py
          test_health_routes.py
      conftest.py              # Shared fixtures, test DB setup
      factories.py             # Factory Boy factories for test data
  migrations/
    versions/
      001_create_vehicles_table.py
      002_create_vehicle_media_table.py
      003_create_price_history_table.py
      004_create_makes_models_tables.py
  Dockerfile
  docker-compose.yml
  requirements.txt
  pyproject.toml
  alembic.ini
  .env.example
```

#### Modelo de Datos - Vehicle

```python
# dom/models/vehicle.py
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal
from typing import Optional
from .value_objects import (
    VehicleStatus, FuelType, TransmissionType,
    BodyType, DrivetrainType, VehicleCondition
)

@dataclass
class Vehicle:
    id: str                           # UUID
    external_id: Optional[str]        # ID from scrapper_nacional
    source: Optional[str]             # Source name from scrapper
    make: str                         # e.g., "Toyota"
    model: str                        # e.g., "Corolla"
    year: int                         # e.g., 2023
    trim: Optional[str]               # e.g., "SE", "XLE"
    body_type: BodyType               # sedan, suv, truck, etc.
    fuel_type: FuelType               # gasoline, diesel, electric, hybrid
    transmission: TransmissionType    # automatic, manual, cvt
    drivetrain: DrivetrainType        # fwd, rwd, awd, 4wd
    engine_displacement_cc: Optional[int]  # e.g., 1800
    horsepower: Optional[int]         # e.g., 169
    torque_nm: Optional[int]          # e.g., 180
    mileage_km: int                   # Odometer reading
    exterior_color: Optional[str]
    interior_color: Optional[str]
    vin: Optional[str]                # Vehicle Identification Number
    plate_number: Optional[str]       # License plate (masked)
    condition: VehicleCondition       # new, used, certified_pre_owned
    price_usd: Decimal                # Current asking price
    original_price_usd: Optional[Decimal]  # Original MSRP or first listed price
    currency: str = "USD"
    location_province: Optional[str]  # Province/state
    location_city: Optional[str]
    location_lat: Optional[float]     # GPS latitude
    location_lng: Optional[float]     # GPS longitude
    has_gps_tracking: bool = False    # From GPS data (4000+ vehicles)
    features: list[str] = field(default_factory=list)  # ["sunroof", "leather_seats"]
    description: Optional[str] = None
    seller_id: Optional[str] = None   # User ID of seller
    seller_type: str = "dealer"       # "dealer", "private", "platform"
    status: VehicleStatus = VehicleStatus.ACTIVE
    views_count: int = 0
    favorites_count: int = 0
    inquiries_count: int = 0
    is_featured: bool = False
    is_verified: bool = False
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    published_at: Optional[datetime] = None
    deleted_at: Optional[datetime] = None  # Soft delete

# dom/models/value_objects.py
from enum import Enum

class VehicleStatus(Enum):
    DRAFT = "draft"
    ACTIVE = "active"
    RESERVED = "reserved"
    SOLD = "sold"
    EXPIRED = "expired"
    DELETED = "deleted"

class FuelType(Enum):
    GASOLINE = "gasoline"
    DIESEL = "diesel"
    ELECTRIC = "electric"
    HYBRID = "hybrid"
    PLUG_IN_HYBRID = "plug_in_hybrid"
    LPG = "lpg"
    CNG = "cng"

class TransmissionType(Enum):
    AUTOMATIC = "automatic"
    MANUAL = "manual"
    CVT = "cvt"
    SEMI_AUTOMATIC = "semi_automatic"

class BodyType(Enum):
    SEDAN = "sedan"
    SUV = "suv"
    TRUCK = "truck"
    HATCHBACK = "hatchback"
    COUPE = "coupe"
    CONVERTIBLE = "convertible"
    VAN = "van"
    WAGON = "wagon"
    CROSSOVER = "crossover"
    PICKUP = "pickup"

class DrivetrainType(Enum):
    FWD = "fwd"
    RWD = "rwd"
    AWD = "awd"
    FOUR_WD = "4wd"

class VehicleCondition(Enum):
    NEW = "new"
    USED = "used"
    CERTIFIED_PRE_OWNED = "certified_pre_owned"
```

#### SQLAlchemy ORM Model

```python
# inf/persistence/sqlalchemy_models.py
from sqlalchemy import (
    Column, String, Integer, Numeric, Boolean, DateTime,
    Text, Float, Enum as SAEnum, Index, ForeignKey, JSON
)
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from sqlalchemy.orm import relationship
import uuid
from app.cfg.database import Base

class VehicleModel(Base):
    __tablename__ = "vehicles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    external_id = Column(String(255), nullable=True, index=True)
    source = Column(String(100), nullable=True, index=True)
    make = Column(String(100), nullable=False, index=True)
    model = Column(String(100), nullable=False, index=True)
    year = Column(Integer, nullable=False, index=True)
    trim = Column(String(100), nullable=True)
    body_type = Column(String(50), nullable=False, index=True)
    fuel_type = Column(String(50), nullable=False, index=True)
    transmission = Column(String(50), nullable=False)
    drivetrain = Column(String(20), nullable=True)
    engine_displacement_cc = Column(Integer, nullable=True)
    horsepower = Column(Integer, nullable=True)
    torque_nm = Column(Integer, nullable=True)
    mileage_km = Column(Integer, nullable=False, default=0)
    exterior_color = Column(String(50), nullable=True)
    interior_color = Column(String(50), nullable=True)
    vin = Column(String(17), nullable=True, unique=True)
    plate_number = Column(String(20), nullable=True)
    condition = Column(String(30), nullable=False, default="used")
    price_usd = Column(Numeric(12, 2), nullable=False)
    original_price_usd = Column(Numeric(12, 2), nullable=True)
    currency = Column(String(3), nullable=False, default="USD")
    location_province = Column(String(100), nullable=True, index=True)
    location_city = Column(String(100), nullable=True)
    location_lat = Column(Float, nullable=True)
    location_lng = Column(Float, nullable=True)
    has_gps_tracking = Column(Boolean, default=False)
    features = Column(ARRAY(String), default=[])
    description = Column(Text, nullable=True)
    seller_id = Column(UUID(as_uuid=True), nullable=True, index=True)
    seller_type = Column(String(20), nullable=False, default="dealer")
    status = Column(String(20), nullable=False, default="active", index=True)
    views_count = Column(Integer, default=0)
    favorites_count = Column(Integer, default=0)
    inquiries_count = Column(Integer, default=0)
    is_featured = Column(Boolean, default=False, index=True)
    is_verified = Column(Boolean, default=False)
    created_at = Column(DateTime, nullable=False, server_default="now()")
    updated_at = Column(DateTime, nullable=False, server_default="now()", onupdate="now()")
    published_at = Column(DateTime, nullable=True)
    deleted_at = Column(DateTime, nullable=True)

    # Relationships
    media = relationship("VehicleMediaModel", back_populates="vehicle", lazy="selectin")
    price_history = relationship("PriceHistoryModel", back_populates="vehicle", lazy="selectin")

    __table_args__ = (
        Index("idx_vehicles_make_model_year", "make", "model", "year"),
        Index("idx_vehicles_price_status", "price_usd", "status"),
        Index("idx_vehicles_location", "location_province", "location_city"),
        Index("idx_vehicles_created_at", "created_at"),
        Index("idx_vehicles_status_featured", "status", "is_featured"),
    )

class VehicleMediaModel(Base):
    __tablename__ = "vehicle_media"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id"), nullable=False, index=True)
    media_type = Column(String(20), nullable=False)  # "image", "video", "360"
    url = Column(String(500), nullable=False)
    thumbnail_url = Column(String(500), nullable=True)
    alt_text = Column(String(255), nullable=True)
    sort_order = Column(Integer, nullable=False, default=0)
    is_primary = Column(Boolean, default=False)
    width = Column(Integer, nullable=True)
    height = Column(Integer, nullable=True)
    file_size_bytes = Column(Integer, nullable=True)
    created_at = Column(DateTime, nullable=False, server_default="now()")

    vehicle = relationship("VehicleModel", back_populates="media")

class PriceHistoryModel(Base):
    __tablename__ = "price_history"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id"), nullable=False, index=True)
    price_usd = Column(Numeric(12, 2), nullable=False)
    currency = Column(String(3), nullable=False, default="USD")
    recorded_at = Column(DateTime, nullable=False, server_default="now()")
    source = Column(String(50), nullable=True)  # "manual", "sync", "api"

    vehicle = relationship("VehicleModel", back_populates="price_history")

class MakeModel(Base):
    __tablename__ = "makes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(100), nullable=False, unique=True, index=True)
    slug = Column(String(100), nullable=False, unique=True)
    logo_url = Column(String(500), nullable=True)
    country = Column(String(100), nullable=True)
    is_active = Column(Boolean, default=True)
    vehicle_count = Column(Integer, default=0)

class ModelModel(Base):
    __tablename__ = "models"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    make_id = Column(UUID(as_uuid=True), ForeignKey("makes.id"), nullable=False, index=True)
    name = Column(String(100), nullable=False, index=True)
    slug = Column(String(100), nullable=False)
    is_active = Column(Boolean, default=True)
    vehicle_count = Column(Integer, default=0)
```

#### Marshmallow Schemas

```python
# api/schemas/vehicle_schema.py
from marshmallow import Schema, fields, validate, pre_load

class VehicleListQuerySchema(Schema):
    cursor = fields.String(load_default=None)
    limit = fields.Integer(load_default=20, validate=validate.Range(min=1, max=100))
    sort_by = fields.String(
        load_default="created_at",
        validate=validate.OneOf(["created_at", "price_usd", "year", "mileage_km", "views_count"])
    )
    sort_order = fields.String(load_default="desc", validate=validate.OneOf(["asc", "desc"]))
    make = fields.String(load_default=None)
    model = fields.String(load_default=None)
    year_min = fields.Integer(load_default=None)
    year_max = fields.Integer(load_default=None)
    price_min = fields.Decimal(load_default=None)
    price_max = fields.Decimal(load_default=None)
    fuel_type = fields.String(load_default=None)
    transmission = fields.String(load_default=None)
    body_type = fields.String(load_default=None)
    condition = fields.String(load_default=None)
    province = fields.String(load_default=None)
    status = fields.String(load_default="active")

class VehicleResponseSchema(Schema):
    id = fields.UUID()
    make = fields.String()
    model = fields.String()
    year = fields.Integer()
    trim = fields.String(allow_none=True)
    body_type = fields.String()
    fuel_type = fields.String()
    transmission = fields.String()
    drivetrain = fields.String(allow_none=True)
    mileage_km = fields.Integer()
    exterior_color = fields.String(allow_none=True)
    condition = fields.String()
    price_usd = fields.Decimal(as_string=True)
    original_price_usd = fields.Decimal(as_string=True, allow_none=True)
    currency = fields.String()
    location_province = fields.String(allow_none=True)
    location_city = fields.String(allow_none=True)
    has_gps_tracking = fields.Boolean()
    features = fields.List(fields.String())
    seller_type = fields.String()
    status = fields.String()
    views_count = fields.Integer()
    favorites_count = fields.Integer()
    is_featured = fields.Boolean()
    is_verified = fields.Boolean()
    primary_image_url = fields.String(allow_none=True)
    created_at = fields.DateTime()
    published_at = fields.DateTime(allow_none=True)

class VehicleDetailResponseSchema(VehicleResponseSchema):
    description = fields.String(allow_none=True)
    vin = fields.String(allow_none=True)
    engine_displacement_cc = fields.Integer(allow_none=True)
    horsepower = fields.Integer(allow_none=True)
    torque_nm = fields.Integer(allow_none=True)
    interior_color = fields.String(allow_none=True)
    location_lat = fields.Float(allow_none=True)
    location_lng = fields.Float(allow_none=True)
    seller_id = fields.UUID(allow_none=True)
    inquiries_count = fields.Integer()
    media = fields.List(fields.Nested("VehicleMediaSchema"))
    price_history = fields.List(fields.Nested("PriceHistorySchema"))

class VehicleCreateSchema(Schema):
    make = fields.String(required=True, validate=validate.Length(min=1, max=100))
    model = fields.String(required=True, validate=validate.Length(min=1, max=100))
    year = fields.Integer(required=True, validate=validate.Range(min=1900, max=2027))
    trim = fields.String(allow_none=True)
    body_type = fields.String(required=True)
    fuel_type = fields.String(required=True)
    transmission = fields.String(required=True)
    drivetrain = fields.String(allow_none=True)
    engine_displacement_cc = fields.Integer(allow_none=True)
    horsepower = fields.Integer(allow_none=True)
    mileage_km = fields.Integer(required=True, validate=validate.Range(min=0))
    exterior_color = fields.String(allow_none=True)
    interior_color = fields.String(allow_none=True)
    condition = fields.String(required=True)
    price_usd = fields.Decimal(required=True, validate=validate.Range(min=0))
    location_province = fields.String(allow_none=True)
    location_city = fields.String(allow_none=True)
    features = fields.List(fields.String(), load_default=[])
    description = fields.String(allow_none=True)
```

#### Request/Response Examples

```json
// GET /api/v1/vehicles?limit=2&sort_by=price_usd&sort_order=asc
// Response 200
{
  "data": [
    {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "make": "Toyota",
      "model": "Corolla",
      "year": 2021,
      "trim": "SE",
      "body_type": "sedan",
      "fuel_type": "gasoline",
      "transmission": "cvt",
      "drivetrain": "fwd",
      "mileage_km": 35000,
      "exterior_color": "White",
      "condition": "used",
      "price_usd": "18500.00",
      "original_price_usd": "22000.00",
      "currency": "USD",
      "location_province": "Panama",
      "location_city": "Ciudad de Panama",
      "has_gps_tracking": true,
      "features": ["backup_camera", "bluetooth", "cruise_control"],
      "seller_type": "dealer",
      "status": "active",
      "views_count": 342,
      "favorites_count": 28,
      "is_featured": false,
      "is_verified": true,
      "primary_image_url": "https://cdn.marketplace.com/vehicles/a1b2c3d4/main.webp",
      "created_at": "2026-03-20T14:30:00Z",
      "published_at": "2026-03-20T15:00:00Z"
    }
  ],
  "pagination": {
    "next_cursor": "eyJpZCI6ImExYjJjM2Q0IiwicHJpY2UiOjE4NTAwfQ==",
    "prev_cursor": null,
    "has_next": true,
    "has_prev": false,
    "limit": 2,
    "total_count": 11247
  },
  "meta": {
    "applied_filters": {
      "status": "active",
      "sort_by": "price_usd",
      "sort_order": "asc"
    }
  }
}
```

```json
// POST /api/v1/vehicles
// Headers: Authorization: Bearer <jwt_token>
// Body:
{
  "make": "Honda",
  "model": "Civic",
  "year": 2023,
  "trim": "Sport",
  "body_type": "sedan",
  "fuel_type": "gasoline",
  "transmission": "cvt",
  "drivetrain": "fwd",
  "mileage_km": 12000,
  "exterior_color": "Sonic Gray",
  "interior_color": "Black",
  "condition": "used",
  "price_usd": 24500.00,
  "location_province": "Panama",
  "location_city": "Ciudad de Panama",
  "features": ["sunroof", "apple_carplay", "android_auto", "lane_departure_warning"],
  "description": "Well maintained Honda Civic Sport with low mileage."
}

// Response 201
{
  "data": {
    "id": "f1e2d3c4-b5a6-7890-fedc-ba0987654321",
    "make": "Honda",
    "model": "Civic",
    "year": 2023,
    "status": "draft",
    "created_at": "2026-03-23T10:00:00Z"
  },
  "message": "Vehicle created successfully. Status: draft. Publish when ready."
}
```

### Criterios de Aceptacion

1. **AC-001**: El servicio arranca en el puerto 5012 con Flask 3.0 y responde GET /health con status 200, incluyendo conectividad a PostgreSQL y Redis.

2. **AC-002**: La arquitectura hexagonal esta correctamente implementada: las capas DOM y APP no tienen imports de Flask, SQLAlchemy, ni ninguna libreria de infraestructura. Solo dependen de interfaces (ports).

3. **AC-003**: El endpoint GET /api/v1/vehicles retorna una lista paginada con cursor-based pagination. El cursor es un string opaco (base64 encoded) que contiene el ID y el campo de ordenamiento.

4. **AC-004**: El endpoint GET /api/v1/vehicles/:id retorna el detalle completo del vehiculo incluyendo media y price_history como nested objects. Si el vehiculo no existe, retorna 404 con el formato de error estandar.

5. **AC-005**: El endpoint POST /api/v1/vehicles valida todos los campos requeridos con Marshmallow. Los errores de validacion retornan 422 con detalle de cada campo invalido.

6. **AC-006**: Las migraciones de Alembic crean correctamente las tablas vehicles, vehicle_media, price_history, makes y models con todos los indices definidos.

7. **AC-007**: El mapper entre domain entities y ORM models funciona bidireccionalmente sin perdida de datos. Vehicle (domain) <-> VehicleModel (ORM) mantiene todos los campos.

8. **AC-008**: El servicio implementa soft delete: DELETE /api/v1/vehicles/:id solo marca deleted_at con timestamp, no elimina el registro. Los queries de listado excluyen vehiculos con deleted_at != null.

9. **AC-009**: Los endpoints GET /api/v1/vehicles/makes y GET /api/v1/vehicles/makes/:make/models retornan las marcas y modelos con conteo de vehiculos activos.

10. **AC-010**: Redis cache esta implementado para GET /api/v1/vehicles/:id con TTL de 5 minutos. El cache se invalida automaticamente en PUT y DELETE del mismo vehiculo.

11. **AC-011**: El servicio tiene al menos 85% de cobertura de tests. Los tests unitarios del dominio no requieren base de datos ni servicios externos.

12. **AC-012**: Las factories de test (Factory Boy) generan datos realistas para Vehicle, VehicleMedia y PriceHistory, facilitando la creacion de fixtures de prueba.

13. **AC-013**: El servicio soporta los query params de filtrado (make, model, year_min, year_max, price_min, price_max, fuel_type, transmission, body_type, condition, province) y los aplica correctamente al query SQL.

### Definition of Done

- [ ] Estructura hexagonal creada y verificada (no hay imports cruzados entre capas)
- [ ] Todos los endpoints implementados y testeados
- [ ] Migraciones de Alembic ejecutan sin errores en base limpia
- [ ] Tests unitarios (dominio y aplicacion) con cobertura >= 85%
- [ ] Tests de integracion (repositorio, rutas) con PostgreSQL de test
- [ ] Marshmallow schemas validan correctamente todos los campos
- [ ] Dockerfile y docker-compose funcionando
- [ ] .env.example con todas las variables documentadas
- [ ] Swagger/OpenAPI generado y accesible en /docs (Flasgger o similar)

### Notas Tecnicas

- Usar SQLAlchemy 2.0 style (select() en lugar de query()) para todas las consultas
- El cursor de paginacion debe ser estable: mismo cursor, mismos resultados (usar ID como tiebreaker)
- Los campos Decimal (price_usd) se serializan como strings en JSON para evitar perdida de precision
- La tabla vehicles tendra ~11,000 registros iniciales del sync con scrapper_nacional
- Considerar composite indexes para los queries mas comunes (make+model+year, price+status)

### Dependencias

- PostgreSQL 15 corriendo con base de datos "marketplace" creada
- Redis 7 corriendo (para cache layer)
- Depende de MKT-INF-001 para CI/CD pero puede desarrollarse en paralelo

---

## User Story 3: [MKT-FE-001][FE-CORE] Angular 18 + Design System Premium

### Descripcion

Como desarrollador frontend, necesito la aplicacion Angular 18 configurada con un design system premium que establezca la identidad visual del marketplace de vehiculos. Debe incluir standalone components, signals-based state management, Tailwind CSS v4, un sistema de temas (light/dark), componentes base reutilizables, layout system responsive, y configuracion de routing con lazy loading.

### Microservicio

- **Nombre**: FE-CORE (Frontend Application)
- **Puerto**: 4200 (dev server)
- **Tecnologia**: Angular 18, Tailwind CSS v4, TypeScript 5.4+
- **Patron**: Standalone Components, Signals-based State, Feature-based Structure

### Contexto Tecnico

#### Estructura de Archivos

```
frontend/
  src/
    app/
      core/
        guards/
          auth.guard.ts            # canActivate for protected routes
          guest.guard.ts           # Redirect if already logged in
          role.guard.ts            # Role-based route protection
        interceptors/
          auth.interceptor.ts      # Attach JWT to requests
          error.interceptor.ts     # Global HTTP error handling
          loading.interceptor.ts   # Track pending requests
          retry.interceptor.ts     # Retry failed requests (configurable)
        services/
          api.service.ts           # Base HTTP service with typed methods
          auth-state.service.ts    # Signal-based auth state management
          theme.service.ts         # Theme toggle (light/dark/system)
          toast.service.ts         # Toast notification service
          storage.service.ts       # LocalStorage/SessionStorage wrapper
          breakpoint.service.ts    # Responsive breakpoint observer
          seo.service.ts           # Meta tags, structured data
          analytics.service.ts     # Event tracking abstraction
        models/
          api-response.model.ts    # Generic API response types
          pagination.model.ts      # Cursor pagination types
          user.model.ts            # User interface
          vehicle.model.ts         # Vehicle interfaces
        config/
          api.config.ts            # API base URLs per environment
          app.config.ts            # Application-wide constants
          routes.config.ts         # Route definitions
      shared/
        components/
          ui/
            button/
              button.component.ts      # Primary, secondary, outline, ghost variants
              button.component.html
              button.component.spec.ts
            input/
              input.component.ts       # Text, email, password, number with validation
              input.component.html
            select/
              select.component.ts      # Custom select with search
              select.component.html
            checkbox/
              checkbox.component.ts
            radio/
              radio.component.ts
            toggle/
              toggle.component.ts
            badge/
              badge.component.ts       # Status badges (active, sold, reserved)
            avatar/
              avatar.component.ts      # User avatar with fallback initials
            card/
              card.component.ts        # Generic card container
            modal/
              modal.component.ts       # Dialog overlay with animations
              modal.service.ts
            dropdown/
              dropdown.component.ts
            tooltip/
              tooltip.directive.ts
            skeleton/
              skeleton.component.ts    # Loading skeleton placeholders
            spinner/
              spinner.component.ts     # Loading spinner
            empty-state/
              empty-state.component.ts # "No results" illustrations
            pagination/
              pagination.component.ts  # Cursor-based pagination controls
            breadcrumb/
              breadcrumb.component.ts
            tabs/
              tabs.component.ts
          layout/
            header/
              header.component.ts      # Main navigation header
              header.component.html
              mobile-menu/
                mobile-menu.component.ts  # Hamburger slide-out menu
            footer/
              footer.component.ts
            sidebar/
              sidebar.component.ts     # Collapsible sidebar for dashboard
            page-layout/
              page-layout.component.ts # Main content wrapper with header/footer
            dashboard-layout/
              dashboard-layout.component.ts  # Sidebar + content layout
        pipes/
          currency-format.pipe.ts    # Format prices: "$18,500" / "USD 18,500"
          relative-time.pipe.ts      # "2 hours ago", "3 days ago"
          truncate.pipe.ts           # Truncate text with ellipsis
          mileage-format.pipe.ts     # "35,000 km"
          phone-format.pipe.ts       # Format phone numbers
        directives/
          click-outside.directive.ts  # Detect click outside element
          lazy-image.directive.ts     # Intersection Observer lazy loading
          infinite-scroll.directive.ts # Infinite scroll detection
          autofocus.directive.ts
        animations/
          fade.animation.ts
          slide.animation.ts
          scale.animation.ts
      features/
        home/
          home.component.ts           # Landing page
          home.routes.ts
        vehicles/
          vehicle-catalog/            # Grid/List view
          vehicle-detail/             # Full detail page
          vehicle-compare/            # Side-by-side comparison
          vehicles.routes.ts
        auth/
          login/
          register/
          forgot-password/
          auth.routes.ts
        profile/
          dashboard/
          settings/
          favorites/
          profile.routes.ts
        (other features added in later epics)
      app.component.ts
      app.component.html
      app.config.ts                   # provideRouter, provideHttpClient, etc.
      app.routes.ts                   # Top-level lazy-loaded routes
    assets/
      images/
        logo.svg
        logo-dark.svg
        placeholder-vehicle.svg
        empty-states/
      icons/
        (custom SVG icons)
    styles/
      _variables.css                  # CSS custom properties (design tokens)
      _typography.css                 # Font scales and text styles
      _animations.css                 # Shared keyframes
      _utilities.css                  # Custom utility classes
      global.css                      # Tailwind imports + global resets
    environments/
      environment.ts                  # Dev environment config
      environment.staging.ts
      environment.prod.ts
  tailwind.config.ts                  # Tailwind v4 configuration
  angular.json
  tsconfig.json
  package.json
  .eslintrc.json
  .prettierrc
```

#### Design Tokens (CSS Custom Properties)

```css
/* styles/_variables.css */
:root {
  /* Primary - Deep Blue (trust, automotive premium) */
  --color-primary-50: #eff6ff;
  --color-primary-100: #dbeafe;
  --color-primary-200: #bfdbfe;
  --color-primary-300: #93c5fd;
  --color-primary-400: #60a5fa;
  --color-primary-500: #3b82f6;
  --color-primary-600: #2563eb;
  --color-primary-700: #1d4ed8;
  --color-primary-800: #1e40af;
  --color-primary-900: #1e3a8a;

  /* Accent - Emerald (success, go, deals) */
  --color-accent-50: #ecfdf5;
  --color-accent-500: #10b981;
  --color-accent-600: #059669;
  --color-accent-700: #047857;

  /* Neutral */
  --color-neutral-50: #fafafa;
  --color-neutral-100: #f5f5f5;
  --color-neutral-200: #e5e5e5;
  --color-neutral-300: #d4d4d4;
  --color-neutral-400: #a3a3a3;
  --color-neutral-500: #737373;
  --color-neutral-600: #525252;
  --color-neutral-700: #404040;
  --color-neutral-800: #262626;
  --color-neutral-900: #171717;

  /* Semantic */
  --color-success: #10b981;
  --color-warning: #f59e0b;
  --color-error: #ef4444;
  --color-info: #3b82f6;

  /* Typography */
  --font-sans: 'Inter', system-ui, -apple-system, sans-serif;
  --font-display: 'Plus Jakarta Sans', var(--font-sans);
  --font-mono: 'JetBrains Mono', monospace;

  /* Font Sizes (fluid) */
  --text-xs: clamp(0.694rem, 0.66rem + 0.17vw, 0.8rem);
  --text-sm: clamp(0.833rem, 0.78rem + 0.27vw, 1rem);
  --text-base: clamp(1rem, 0.93rem + 0.36vw, 1.25rem);
  --text-lg: clamp(1.2rem, 1.1rem + 0.5vw, 1.563rem);
  --text-xl: clamp(1.44rem, 1.29rem + 0.75vw, 1.953rem);
  --text-2xl: clamp(1.728rem, 1.51rem + 1.09vw, 2.441rem);
  --text-3xl: clamp(2.074rem, 1.77rem + 1.52vw, 3.052rem);

  /* Spacing Scale */
  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --space-5: 1.25rem;
  --space-6: 1.5rem;
  --space-8: 2rem;
  --space-10: 2.5rem;
  --space-12: 3rem;
  --space-16: 4rem;
  --space-20: 5rem;

  /* Shadows (elevated cards, modals) */
  --shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
  --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -2px rgba(0, 0, 0, 0.1);
  --shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -4px rgba(0, 0, 0, 0.1);
  --shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 8px 10px -6px rgba(0, 0, 0, 0.1);
  --shadow-card: 0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.06);
  --shadow-card-hover: 0 10px 25px rgba(0,0,0,0.12), 0 4px 10px rgba(0,0,0,0.08);

  /* Border Radius */
  --radius-sm: 0.375rem;
  --radius-md: 0.5rem;
  --radius-lg: 0.75rem;
  --radius-xl: 1rem;
  --radius-2xl: 1.5rem;
  --radius-full: 9999px;

  /* Transitions */
  --transition-fast: 150ms ease;
  --transition-base: 250ms ease;
  --transition-slow: 350ms ease;

  /* Z-Index Scale */
  --z-dropdown: 50;
  --z-sticky: 100;
  --z-modal-backdrop: 200;
  --z-modal: 300;
  --z-toast: 400;
  --z-tooltip: 500;

  /* Container */
  --container-max: 1440px;
  --container-padding: 1rem;
}

/* Dark Theme */
[data-theme="dark"] {
  --color-neutral-50: #171717;
  --color-neutral-100: #262626;
  --color-neutral-200: #404040;
  --color-neutral-300: #525252;
  --color-neutral-400: #737373;
  --color-neutral-500: #a3a3a3;
  --color-neutral-600: #d4d4d4;
  --color-neutral-700: #e5e5e5;
  --color-neutral-800: #f5f5f5;
  --color-neutral-900: #fafafa;
  --shadow-card: 0 1px 3px rgba(0,0,0,0.3), 0 1px 2px rgba(0,0,0,0.2);
  --shadow-card-hover: 0 10px 25px rgba(0,0,0,0.4), 0 4px 10px rgba(0,0,0,0.3);
}
```

#### Signal-Based State Example

```typescript
// core/services/auth-state.service.ts
import { Injectable, signal, computed } from '@angular/core';

export interface AuthUser {
  id: string;
  email: string;
  name: string;
  avatar_url: string | null;
  roles: string[];
  token: string;
}

@Injectable({ providedIn: 'root' })
export class AuthStateService {
  private readonly _user = signal<AuthUser | null>(null);
  private readonly _loading = signal<boolean>(true);

  readonly user = this._user.asReadonly();
  readonly loading = this._loading.asReadonly();
  readonly isAuthenticated = computed(() => this._user() !== null);
  readonly isAdmin = computed(() => this._user()?.roles.includes('admin') ?? false);
  readonly isDealer = computed(() => this._user()?.roles.includes('dealer') ?? false);
  readonly userName = computed(() => this._user()?.name ?? 'Guest');
  readonly userInitials = computed(() => {
    const name = this._user()?.name;
    if (!name) return '?';
    return name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  });

  setUser(user: AuthUser): void {
    this._user.set(user);
    this._loading.set(false);
  }

  clearUser(): void {
    this._user.set(null);
    this._loading.set(false);
  }

  updateToken(token: string): void {
    const current = this._user();
    if (current) {
      this._user.set({ ...current, token });
    }
  }
}
```

#### Routing Configuration

```typescript
// app.routes.ts
import { Routes } from '@angular/router';
import { authGuard } from './core/guards/auth.guard';
import { guestGuard } from './core/guards/guest.guard';
import { PageLayoutComponent } from './shared/components/layout/page-layout/page-layout.component';
import { DashboardLayoutComponent } from './shared/components/layout/dashboard-layout/dashboard-layout.component';

export const routes: Routes = [
  {
    path: '',
    component: PageLayoutComponent,
    children: [
      {
        path: '',
        loadComponent: () => import('./features/home/home.component')
          .then(m => m.HomeComponent),
        title: 'Vehicle Marketplace - Find Your Perfect Car'
      },
      {
        path: 'vehicles',
        loadChildren: () => import('./features/vehicles/vehicles.routes')
          .then(m => m.VEHICLE_ROUTES)
      },
      {
        path: 'auth',
        canActivate: [guestGuard],
        loadChildren: () => import('./features/auth/auth.routes')
          .then(m => m.AUTH_ROUTES)
      }
    ]
  },
  {
    path: 'dashboard',
    component: DashboardLayoutComponent,
    canActivate: [authGuard],
    loadChildren: () => import('./features/profile/profile.routes')
      .then(m => m.PROFILE_ROUTES)
  },
  {
    path: '**',
    loadComponent: () => import('./features/not-found/not-found.component')
      .then(m => m.NotFoundComponent)
  }
];
```

### Criterios de Aceptacion

1. **AC-001**: La aplicacion Angular 18 arranca con `ng serve` en puerto 4200 sin errores. Usa standalone components exclusivamente (ningun NgModule en la aplicacion).

2. **AC-002**: Tailwind CSS v4 esta configurado y funcional. Las clases de utilidad se aplican correctamente. El CSS custom properties system (design tokens) esta implementado y todas las variables definidas en _variables.css funcionan.

3. **AC-003**: El tema dark/light funciona correctamente. El ThemeService detecta la preferencia del sistema (prefers-color-scheme), permite toggle manual, y persiste la preferencia en localStorage. El cambio de tema es instantaneo sin flash.

4. **AC-004**: Todos los componentes UI base (button, input, select, checkbox, radio, toggle, badge, avatar, card, modal, skeleton, spinner, empty-state, pagination, breadcrumb, tabs) estan implementados como standalone components con inputs tipados y variants.

5. **AC-005**: El layout responsive funciona en 4 breakpoints: mobile (<640px), tablet (640-1024px), desktop (1024-1440px), wide (>1440px). El header muestra hamburger menu en mobile, nav links en desktop.

6. **AC-006**: El routing esta configurado con lazy loading para todas las feature modules. La navegacion entre rutas no recarga la pagina. Los guards de autenticacion funcionan (redirige a /auth/login si no autenticado).

7. **AC-007**: El ApiService base esta implementado con metodos tipados (get<T>, post<T>, put<T>, delete<T>) y soporte para cursor-based pagination. Los interceptors de auth, error y loading estan configurados.

8. **AC-008**: Las animaciones de transicion estan implementadas: fade-in para pages, slide para mobile menu, scale para modals. Respetan prefers-reduced-motion.

9. **AC-009**: Los pipes personalizados (currency-format, relative-time, truncate, mileage-format) funcionan correctamente y estan testeados unitariamente. El currency pipe formatea "18500" como "$18,500".

10. **AC-010**: El skeleton loading esta implementado para cards de vehiculos y listas. Mientras los datos cargan, se muestran skeletons con animacion de pulso que coinciden con la forma del contenido final.

11. **AC-011**: La directiva lazy-image usa Intersection Observer para cargar imagenes solo cuando entran al viewport. Muestra un placeholder blur mientras carga.

12. **AC-012**: El ESLint y Prettier estan configurados con reglas estrictas. El proyecto compila sin warnings de TypeScript en modo strict.

13. **AC-013**: Las fuentes 'Inter' y 'Plus Jakarta Sans' estan optimizadas con font-display: swap y se pre-cargan en el index.html para evitar FOIT (Flash of Invisible Text).

### Definition of Done

- [ ] Angular 18 project creado con standalone components
- [ ] Tailwind CSS v4 configurado y funcional
- [ ] Design tokens implementados en CSS custom properties
- [ ] Tema dark/light funcional con persistencia
- [ ] Todos los componentes UI base implementados y documentados
- [ ] Layout responsive verificado en 4 breakpoints
- [ ] Routing con lazy loading configurado
- [ ] Interceptors (auth, error, loading) implementados
- [ ] Signal-based state management para auth implementado
- [ ] Tests unitarios para servicios core y pipes (>= 80% cobertura)
- [ ] ESLint + Prettier configurados sin errores
- [ ] Build de produccion (`ng build`) sin errores ni warnings

### Notas Tecnicas

- Usar Angular 18 signals en lugar de RxJS BehaviorSubject para estado local del componente
- RxJS se mantiene para streams HTTP y eventos complejos (websockets)
- Tailwind v4 usa la nueva engine basada en Rust (Lightning CSS)
- Las imagenes del CDN deben servirse en formato WebP con fallback a JPG
- Los iconos deben ser SVG inline (no font icons) para accesibilidad y performance
- La configuracion de CSP (Content Security Policy) se define en el backend/gateway

### Dependencias

- Node.js 20 LTS
- Angular CLI 18.x
- Acceso al CDN para assets
- API Gateway (MKT-BE-001) para llamadas al backend (puede usar mocks en desarrollo)

---

## User Story 4: [MKT-INF-001][INF-CI] Pipeline CI/CD con GitHub Actions

### Descripcion

Como ingeniero DevOps, necesito un pipeline de CI/CD completo en GitHub Actions que automatice testing, linting, building y deployment de todos los microservicios y el frontend. El pipeline debe soportar multiple entornos (dev, staging, prod), correr tests en paralelo, construir imagenes Docker, y deployar a AWS ECS/ECR.

### Microservicio

- **Nombre**: INF-CI (Infrastructure - Continuous Integration/Deployment)
- **Tecnologia**: GitHub Actions, Docker, AWS ECR/ECS
- **Patron**: Trunk-based development con feature branches

### Contexto Tecnico

#### Estructura de Archivos

```
.github/
  workflows/
    ci-backend.yml                # Lint + Test para servicios Python
    ci-frontend.yml               # Lint + Test + Build para Angular
    cd-deploy-dev.yml             # Deploy automatico a dev (merge a develop)
    cd-deploy-staging.yml         # Deploy a staging (merge a main)
    cd-deploy-prod.yml            # Deploy a produccion (release tag)
    pr-checks.yml                 # Checks obligatorios para PRs
    security-scan.yml             # SAST + dependency scan semanal
    db-migrations.yml             # Run Alembic migrations
  actions/
    setup-python/
      action.yml                  # Composite action: Python + pip cache
    setup-node/
      action.yml                  # Composite action: Node + npm cache
    build-push-ecr/
      action.yml                  # Composite action: Docker build + ECR push
  CODEOWNERS
  pull_request_template.md
```

#### Pipeline CI Backend

```yaml
# .github/workflows/ci-backend.yml
name: CI - Backend Services

on:
  pull_request:
    paths:
      - 'svc-*/**'
      - 'shared-libs/**'
  push:
    branches: [develop, main]
    paths:
      - 'svc-*/**'

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      services: ${{ steps.changes.outputs.services }}
    steps:
      - uses: actions/checkout@v4
      - id: changes
        # Detect which svc-* directories changed

  lint-and-test:
    needs: detect-changes
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: ${{ fromJson(needs.detect-changes.outputs.services) }}
      fail-fast: false
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: marketplace_test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:7
        ports: ['6379:6379']
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s

    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-python
        with:
          python-version: '3.11'
          service-path: ${{ matrix.service }}

      - name: Lint (ruff)
        run: |
          cd ${{ matrix.service }}
          ruff check .
          ruff format --check .

      - name: Type Check (mypy)
        run: |
          cd ${{ matrix.service }}
          mypy app/ --ignore-missing-imports

      - name: Run Tests
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/marketplace_test
          REDIS_URL: redis://localhost:6379/0
          FLASK_ENV: testing
        run: |
          cd ${{ matrix.service }}
          pytest app/tst/ -v --cov=app --cov-report=xml --cov-fail-under=85

      - name: Upload Coverage
        uses: codecov/codecov-action@v4
        with:
          file: ${{ matrix.service }}/coverage.xml
          flags: ${{ matrix.service }}
```

#### Pipeline CI Frontend

```yaml
# .github/workflows/ci-frontend.yml
name: CI - Frontend

on:
  pull_request:
    paths: ['frontend/**']
  push:
    branches: [develop, main]
    paths: ['frontend/**']

jobs:
  lint-test-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-node
        with:
          node-version: '20'

      - name: Lint
        run: |
          cd frontend
          npx eslint src/ --max-warnings 0

      - name: Type Check
        run: |
          cd frontend
          npx tsc --noEmit

      - name: Unit Tests
        run: |
          cd frontend
          npx ng test --watch=false --code-coverage --browsers=ChromeHeadless

      - name: Build (Production)
        run: |
          cd frontend
          npx ng build --configuration=production

      - name: Bundle Size Check
        run: |
          cd frontend
          # Fail if main bundle exceeds 250KB gzipped
          npx bundlesize
```

### Criterios de Aceptacion

1. **AC-001**: El workflow ci-backend.yml detecta automaticamente cuales servicios (svc-*) cambiaron en el PR y solo ejecuta lint/test para esos servicios, no para todos.

2. **AC-002**: Los tests de backend corren con PostgreSQL 15 y Redis 7 como service containers. Las migraciones se ejecutan antes de los tests.

3. **AC-003**: El linting usa ruff para Python (check + format) y ESLint para Angular. Ambos fallan el pipeline si hay errores.

4. **AC-004**: La cobertura de tests se reporta a Codecov con flags por servicio. El pipeline falla si la cobertura esta por debajo del 85% para backend o 80% para frontend.

5. **AC-005**: El pipeline de frontend incluye build de produccion. Si el build falla, el PR no se puede mergear.

6. **AC-006**: Un PR a develop o main requiere: (a) todos los checks pasando, (b) al menos 1 review aprobado, (c) branch actualizado con base. Esto se configura en branch protection rules.

7. **AC-007**: El workflow cd-deploy-dev.yml se ejecuta automaticamente al mergear a develop: construye imagenes Docker, las sube a ECR, y actualiza los servicios en ECS del entorno dev.

8. **AC-008**: El workflow cd-deploy-staging.yml se ejecuta al mergear a main: construye imagenes, sube a ECR, y deployea a staging. Requiere aprobacion manual para produccion.

9. **AC-009**: Las imagenes Docker usan multi-stage builds. La imagen final de cada servicio Python no excede 200MB. La imagen del frontend (nginx) no excede 50MB.

10. **AC-010**: Los secrets de AWS (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, etc.) se configuran como GitHub Secrets a nivel de organizacion/repositorio, nunca hardcodeados.

11. **AC-011**: El pipeline de seguridad (security-scan.yml) corre semanalmente y en cada PR: ejecuta trivy para vulnerabilidades de dependencias y bandit para analisis estatico de Python.

12. **AC-012**: El pipeline completo de un PR (detect changes + lint + test + build) tarda menos de 8 minutos para un solo servicio y menos de 15 minutos para el frontend.

### Definition of Done

- [ ] Todos los workflows de GitHub Actions creados y funcionales
- [ ] Branch protection rules configuradas para develop y main
- [ ] Composite actions reutilizables creadas (setup-python, setup-node, build-push-ecr)
- [ ] Service containers (PostgreSQL, Redis) funcionando en CI
- [ ] Codecov integrado y reportando cobertura
- [ ] Deploy automatico a dev verificado
- [ ] Deploy a staging con aprobacion manual verificado
- [ ] Tiempos de ejecucion dentro de limites (<8 min por servicio)
- [ ] Security scan configurado y funcional
- [ ] CODEOWNERS y PR template creados

### Notas Tecnicas

- Usar pip cache en setup-python para reducir tiempos de instalacion
- Usar npm cache en setup-node para reducir tiempos de instalacion
- Considerar matrix strategy para correr tests de multiples servicios en paralelo
- Las imagenes Docker deben taggearse con: git SHA, branch name y "latest" para develop
- Usar GITHUB_TOKEN para operaciones de git dentro de workflows
- El db-migrations.yml se ejecuta manualmente o como pre-deploy step

### Dependencias

- Repositorio GitHub creado con permisos de admin
- AWS ECR repositories creados (1 por servicio)
- AWS ECS cluster configurado (ver MKT-INF-002)
- GitHub Secrets configurados (AWS credentials, Codecov token)

---

## User Story 5: [MKT-INF-002][INF-NET] Infraestructura AWS Base con Terraform

### Descripcion

Como ingeniero de infraestructura, necesito toda la infraestructura AWS base definida como codigo con Terraform. Incluye VPC, subnets, security groups, ECS Fargate cluster, ECR repositories, RDS PostgreSQL 15, ElastiCache Redis 7, ALB, Route53, ACM certificates, CloudWatch logging, y los parametros de Systems Manager para configuracion.

### Microservicio

- **Nombre**: INF-NET (Infrastructure - Networking & Cloud)
- **Tecnologia**: Terraform 1.7+, AWS
- **Patron**: Infrastructure as Code, modular Terraform

### Contexto Tecnico

#### Estructura de Archivos

```
infrastructure/
  terraform/
    environments/
      dev/
        main.tf                    # Dev-specific overrides
        terraform.tfvars           # Dev variable values
        backend.tf                 # S3 backend config for dev state
      staging/
        main.tf
        terraform.tfvars
        backend.tf
      prod/
        main.tf
        terraform.tfvars
        backend.tf
    modules/
      networking/
        main.tf                    # VPC, subnets, NAT gateway, route tables
        variables.tf
        outputs.tf
      ecs/
        main.tf                    # ECS Fargate cluster, task definitions, services
        variables.tf
        outputs.tf
        iam.tf                     # Task execution roles, task roles
      rds/
        main.tf                    # RDS PostgreSQL 15, parameter groups, subnet groups
        variables.tf
        outputs.tf
      elasticache/
        main.tf                    # ElastiCache Redis 7 cluster
        variables.tf
        outputs.tf
      alb/
        main.tf                    # Application Load Balancer, target groups, listeners
        variables.tf
        outputs.tf
      ecr/
        main.tf                    # ECR repositories (1 per service)
        variables.tf
        outputs.tf
      cloudwatch/
        main.tf                    # Log groups, alarms, dashboards
        variables.tf
        outputs.tf
      cognito/
        main.tf                    # Cognito User Pool, App Client, Domain
        variables.tf
        outputs.tf
      s3/
        main.tf                    # S3 buckets (media, static assets, backups)
        variables.tf
        outputs.tf
      elasticsearch/
        main.tf                    # OpenSearch (Elasticsearch) domain
        variables.tf
        outputs.tf
      sqs/
        main.tf                    # SQS queues for async workers
        variables.tf
        outputs.tf
      ssm/
        main.tf                    # SSM Parameter Store entries
        variables.tf
        outputs.tf
    global/
      main.tf                     # Global resources (Route53 zone, ACM certs)
      variables.tf
      outputs.tf
      backend.tf
```

#### Networking Module - VPC Design

```hcl
# modules/networking/main.tf
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr  # "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project}-${var.environment}-vpc"
    Project     = var.project
    Environment = var.environment
  }
}

# Public Subnets (ALB, NAT Gateway)
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)  # 10.0.0.0/24, 10.0.1.0/24
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.environment}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# Private Subnets (ECS Tasks, RDS, ElastiCache)
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)  # 10.0.10.0/24, 10.0.11.0/24
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project}-${var.environment}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# Database Subnets (isolated, no internet access)
resource "aws_subnet" "database" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)  # 10.0.20.0/24, 10.0.21.0/24
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project}-${var.environment}-database-${var.availability_zones[count.index]}"
    Tier = "database"
  }
}
```

#### ECS Service Definitions

```hcl
# modules/ecs/main.tf
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# One service definition per microservice
locals {
  services = {
    "svc-gateway"      = { port = 8080, cpu = 512,  memory = 1024, desired_count = 2, health_path = "/health" }
    "svc-auth"         = { port = 5010, cpu = 256,  memory = 512,  desired_count = 2, health_path = "/health" }
    "svc-user"         = { port = 5011, cpu = 256,  memory = 512,  desired_count = 2, health_path = "/health" }
    "svc-vehicle"      = { port = 5012, cpu = 512,  memory = 1024, desired_count = 2, health_path = "/health" }
    "svc-purchase"     = { port = 5013, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
    "svc-kyc"          = { port = 5014, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
    "svc-finance"      = { port = 5015, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
    "svc-insurance"    = { port = 5016, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
    "svc-notification" = { port = 5017, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
    "svc-chat"         = { port = 5018, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
    "svc-marketing"    = { port = 5019, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
    "svc-admin"        = { port = 5020, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
    "svc-report"       = { port = 5021, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
    "svc-seo"          = { port = 5022, cpu = 256,  memory = 512,  desired_count = 1, health_path = "/health" }
  }
}
```

#### Environment Variables (Dev)

```hcl
# environments/dev/terraform.tfvars
project     = "mkt-vehicles"
environment = "dev"
region      = "us-east-1"

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# RDS
rds_instance_class    = "db.t3.medium"
rds_allocated_storage = 50
rds_engine_version    = "15.4"
rds_database_name     = "marketplace"
rds_multi_az          = false

# ElastiCache
redis_node_type   = "cache.t3.small"
redis_num_nodes   = 1

# OpenSearch (Elasticsearch)
es_instance_type  = "t3.medium.search"
es_instance_count = 1
es_volume_size    = 20

# ECS
ecs_gateway_desired_count = 1  # Override for dev

# Cognito
cognito_domain_prefix = "mkt-vehicles-dev"
```

### Criterios de Aceptacion

1. **AC-001**: `terraform plan` ejecuta sin errores para los tres entornos (dev, staging, prod). El state se almacena en S3 con DynamoDB locking.

2. **AC-002**: La VPC tiene 3 tiers de subnets (public, private, database) en 2 AZs minimo. El NAT Gateway permite acceso a internet desde subnets privadas. Las subnets de database no tienen acceso a internet.

3. **AC-003**: El ECS Fargate cluster esta creado con Container Insights habilitado. Cada microservicio tiene su task definition con CPU/memory configurado segun la tabla de services.

4. **AC-004**: RDS PostgreSQL 15 esta configurado en las subnets de database con backup automatico (7 dias retencion en dev, 30 en prod), encryption at rest, y parameter group optimizado.

5. **AC-005**: ElastiCache Redis 7 esta en subnets privadas con encryption in transit y at rest. Security group permite acceso solo desde ECS tasks.

6. **AC-006**: El ALB esta en subnets publicas con HTTPS listener (ACM certificate) y redireccion HTTP->HTTPS. El path-based routing envia /api/* al gateway y /* al frontend.

7. **AC-007**: ECR repositories existen para cada servicio (14 repos) con lifecycle policy que mantiene solo las ultimas 10 imagenes.

8. **AC-008**: CloudWatch log groups existen para cada servicio con retencion de 30 dias en dev y 90 dias en prod. Alarmas configuradas para CPU > 80%, Memory > 80%, y 5xx errors > 10/min.

9. **AC-009**: Cognito User Pool esta creado con: password policy (8+ chars, upper, lower, number, special), email verification, custom attributes para roles, y app client para el frontend.

10. **AC-010**: S3 buckets creados para: vehicle media (con CloudFront), static assets, backups de DB, y Terraform state. Todos con encryption y versioning.

11. **AC-011**: SQS queues creadas para workers: sync-queue (WRK-SYNC), finance-queue (WRK-FIN), insurance-queue (WRK-INS), notification-queue (WRK-NTF) con dead-letter queues configuradas.

12. **AC-012**: SSM Parameter Store contiene todos los parametros de configuracion (DB URLs, Redis URLs, API keys) encriptados con KMS. Los ECS tasks tienen permisos IAM para leer solo sus parametros.

13. **AC-013**: Security groups siguen principio de menor privilegio: ECS tasks solo acceden a RDS (5432), Redis (6379), y ElastiCache. RDS solo acepta conexiones de ECS. ALB acepta 80/443 desde internet.

### Definition of Done

- [ ] Todos los modulos Terraform creados y documentados
- [ ] `terraform plan` exitoso para dev, staging, prod
- [ ] `terraform apply` exitoso en entorno dev
- [ ] VPC con 3-tier subnets verificada
- [ ] ECS cluster con al menos gateway task running
- [ ] RDS PostgreSQL 15 accesible desde ECS tasks
- [ ] Redis accesible desde ECS tasks
- [ ] ALB con HTTPS sirviendo requests
- [ ] CloudWatch logs recibiendo logs de servicios
- [ ] Security groups auditados con principio de menor privilegio
- [ ] Terraform state en S3 con locking
- [ ] Variables sensibles en SSM Parameter Store (no en tfvars)

### Notas Tecnicas

- Usar Terraform workspaces O directorios separados por entorno (preferimos directorios)
- Los modulos deben ser genericos y reutilizables, las especificidades van en tfvars
- Usar data sources para AMIs y account ID en lugar de hardcodear
- El OpenSearch domain reemplaza Elasticsearch en AWS (API compatible)
- Considerar AWS App Mesh para service mesh en futuras iteraciones
- NAT Gateway es costoso: usar 1 en dev, 2 (HA) en prod

### Dependencias

- Cuenta AWS con permisos para crear todos los recursos listados
- Dominio registrado y zona DNS en Route53
- Terraform 1.7+ instalado en CI runners
- S3 bucket para Terraform state (bootstrap manual)
- KMS key para encripcion de SSM parameters

---

## Resumen de Dependencias entre Stories

```
MKT-INF-002 (AWS Infra)
    |
    v
MKT-INF-001 (CI/CD) --- depende de ---> ECR repos de INF-002
    |
    v
MKT-BE-001 (Gateway) <--- no depende de otros servicios
    |
    v
MKT-BE-002 (Vehicle Service) <--- depende de Gateway para routing
    |
    v
MKT-FE-001 (Angular App) <--- depende de Gateway para API calls (puede usar mocks)
```

## Estimacion de Esfuerzo

| Story | Estimacion | Developers |
|-------|-----------|------------|
| MKT-BE-001 (Gateway) | 13 points | 1 Backend Sr |
| MKT-BE-002 (Vehicle Service) | 21 points | 1 Backend Sr + 1 Backend Jr |
| MKT-FE-001 (Angular App) | 21 points | 1 Frontend Sr + 1 Frontend Jr |
| MKT-INF-001 (CI/CD) | 13 points | 1 DevOps |
| MKT-INF-002 (AWS Infra) | 21 points | 1 DevOps |
| **Total** | **89 points** | **Sprint 1-2** |
