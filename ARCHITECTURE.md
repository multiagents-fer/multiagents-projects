# Marketplace Automotriz AgentsMX - Arquitectura del Sistema

## 1. Vision General

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         MARKETPLACE AUTOMOTRIZ AgentsMX                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐  │
│  │   COMPRADORES    │  │   VENDEDORES/    │  │      ADMINISTRADORES         │  │
│  │   (Buyers)       │  │   DEALERS        │  │      (Admin Panel)           │  │
│  └────────┬─────────┘  └────────┬─────────┘  └──────────────┬───────────────┘  │
│           │                      │                            │                  │
│  ┌────────▼──────────────────────▼────────────────────────────▼───────────────┐ │
│  │                    ANGULAR 18 FRONTEND (SSR)                               │ │
│  │  proj-front-marketplace | Port 4200 | Tailwind v4 | Standalone Components │ │
│  │                                                                            │ │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────────┐  │ │
│  │  │Catalogo│ │Compra  │ │Finance │ │Seguros │ │ KYC    │ │Admin Panel │  │ │
│  │  │Vehic.  │ │Flow    │ │Wizard  │ │Compare │ │ Flow   │ │Dashboard   │  │ │
│  │  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘ └────────────┘  │ │
│  └────────────────────────────┬───────────────────────────────────────────────┘ │
│                               │ REST + WebSocket + SSE                          │
│  ┌────────────────────────────▼───────────────────────────────────────────────┐ │
│  │                    AWS APPLICATION LOAD BALANCER                            │ │
│  │                    api.marketplace.agentsmx.com                             │ │
│  └────────────────────────────┬───────────────────────────────────────────────┘ │
│                               │                                                 │
│  ┌────────────────────────────▼───────────────────────────────────────────────┐ │
│  │                    FLASK 3.0 BACKEND API                                   │ │
│  │  proj-back-marketplace | Port 5010 | Hexagonal Architecture                │ │
│  │                                                                            │ │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │ │
│  │  │Vehicles │ │Purchase │ │Finance  │ │Insurance│ │  KYC    │           │ │
│  │  │  API    │ │ Flow API│ │  API    │ │  API    │ │  API    │           │ │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘           │ │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │ │
│  │  │  Auth   │ │  Users  │ │  Admin  │ │  Notif  │ │  Chat   │           │ │
│  │  │  API    │ │  API    │ │  API    │ │  API    │ │  WS API │           │ │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘           │ │
│  └────────┬───────────┬──────────┬──────────┬──────────┬─────────────────────┘ │
│           │           │          │          │          │                         │
│  ┌────────▼───┐ ┌─────▼────┐ ┌──▼───┐ ┌───▼────┐ ┌──▼──────────────────────┐ │
│  │PostgreSQL  │ │  Redis   │ │  S3  │ │  SQS   │ │  Elasticsearch          │ │
│  │  15 + RDS  │ │ElastiCa. │ │+CDN  │ │Queues  │ │  Full-text search       │ │
│  └────────────┘ └──────────┘ └──────┘ └────────┘ └─────────────────────────┘ │
│                                                                                 │
│  ┌──────────────────── SERVICIOS EXISTENTES ──────────────────────────────────┐ │
│  │                                                                            │ │
│  │  proj-back-ai-agents (5001)  │  mod_scrapper_nacional (18 fuentes)        │ │
│  │  ├─ Depreciation Agent       │  ├─ 11,000+ vehiculos                     │ │
│  │  ├─ Marketplace Analytics    │  ├─ kavak, albacar, finakar...             │ │
│  │  ├─ Report Builder           │  └─ Sync via SQS events                   │ │
│  │  ├─ Chat Agent               │                                            │ │
│  │  ├─ Scraper Generator        │  proj-worker-marketplace-sync              │ │
│  │  ├─ Report Optimizer         │  ├─ SQS consumer                          │ │
│  │  └─ Market Discovery         │  └─ Price history, media tracking         │ │
│  │                              │                                            │ │
│  │  proj-worker-diagnostic-sync │  proj-back-driver-adapters (5000)          │ │
│  │  ├─ OBD-II PDF processing    │  ├─ 4,000+ vehiculos GPS                 │ │
│  │  └─ Sensor readings, DTCs    │  └─ SeeWorld/WhatsGPS adapter            │ │
│  │                                                                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│  ┌──────────────────── INTEGRACIONES EXTERNAS ────────────────────────────────┐ │
│  │                                                                            │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────────────────┐ │ │
│  │  │  FINANCIERAS    │  │  ASEGURADORAS   │  │  VERIFICACION IDENTIDAD   │ │ │
│  │  │  ├─ Financiera A│  │  ├─ Qualitas    │  │  ├─ INE OCR + CURP       │ │ │
│  │  │  ├─ Financiera B│  │  ├─ GNP         │  │  ├─ Face matching        │ │ │
│  │  │  ├─ Financiera C│  │  ├─ AXA         │  │  ├─ Listas PLD/FT       │ │ │
│  │  │  └─ Adapter Port│  │  └─ Adapter Port│  │  └─ Adapter Port        │ │ │
│  │  └─────────────────┘  └─────────────────┘  └────────────────────────────┘ │ │
│  │                                                                            │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────────────────┐ │ │
│  │  │  AWS COGNITO    │  │  AWS SES        │  │  WHATSAPP BUSINESS API   │ │ │
│  │  │  Auth + MFA     │  │  Email service  │  │  Notifications           │ │ │
│  │  └─────────────────┘  └─────────────────┘  └────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 2. Base de Datos - Schema del Marketplace

```sql
-- =====================================================
-- SCHEMA: marketplace (PostgreSQL 15 + RDS)
-- =====================================================

-- USUARIOS
CREATE TABLE marketplace.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cognito_sub VARCHAR(128) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'buyer', -- buyer, seller, dealer, admin
    avatar_url TEXT,
    location_state VARCHAR(50),
    location_city VARCHAR(100),
    preferences JSONB DEFAULT '{}',
    kyc_status VARCHAR(20) DEFAULT 'not_started', -- not_started, pending, approved, rejected, expired
    kyc_approved_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- VEHICULOS DEL MARKETPLACE
CREATE TABLE marketplace.vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id VARCHAR(255), -- ref a scrapper_nacional.vehicles.id
    source VARCHAR(50) NOT NULL, -- kavak, albacar, dealer_direct, etc.
    brand VARCHAR(100) NOT NULL,
    model VARCHAR(100) NOT NULL,
    year INTEGER NOT NULL,
    price NUMERIC(14,2) NOT NULL,
    original_price NUMERIC(14,2), -- precio antes de descuento
    kms NUMERIC(10,2),
    transmission VARCHAR(20), -- manual, automatica
    fuel_type VARCHAR(20), -- gasolina, diesel, hibrido, electrico
    exterior_color VARCHAR(50),
    interior_color VARCHAR(50),
    engine VARCHAR(50), -- 1.6L, 2.0T, etc.
    doors INTEGER,
    seats INTEGER,
    drivetrain VARCHAR(20), -- FWD, RWD, AWD, 4WD
    location_state VARCHAR(50),
    location_city VARCHAR(100),
    description TEXT,
    features JSONB DEFAULT '[]', -- ["A/C", "GPS", "Camara reversa", ...]
    status VARCHAR(20) DEFAULT 'active', -- active, reserved, sold, inactive
    health_score INTEGER, -- 0-100, from diagnostic agent
    market_value NUMERIC(14,2), -- valuacion IA
    days_on_market INTEGER DEFAULT 0,
    views_count INTEGER DEFAULT 0,
    favorites_count INTEGER DEFAULT 0,
    seller_id UUID REFERENCES marketplace.users(id),
    url TEXT, -- URL original del vehiculo
    vin VARCHAR(17),
    plates VARCHAR(20),
    is_featured BOOLEAN DEFAULT false,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- MEDIA (IMAGENES) DE VEHICULOS
CREATE TABLE marketplace.vehicle_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id UUID NOT NULL REFERENCES marketplace.vehicles(id) ON DELETE CASCADE,
    url TEXT NOT NULL, -- S3 CDN URL
    thumbnail_url TEXT, -- resized thumbnail
    type VARCHAR(20) DEFAULT 'image', -- image, video, 360
    position INTEGER DEFAULT 0, -- orden en el carrusel
    alt_text VARCHAR(255),
    width INTEGER,
    height INTEGER,
    size_bytes INTEGER,
    hash VARCHAR(64), -- dedup
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- FAVORITOS / WISHLIST
CREATE TABLE marketplace.favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES marketplace.users(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES marketplace.vehicles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, vehicle_id)
);

-- HISTORIAL DE PRECIOS
CREATE TABLE marketplace.price_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id UUID NOT NULL REFERENCES marketplace.vehicles(id) ON DELETE CASCADE,
    price NUMERIC(14,2) NOT NULL,
    source VARCHAR(50),
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- INTENCIONES DE COMPRA / PURCHASE FLOW
CREATE TABLE marketplace.purchase_intents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES marketplace.users(id),
    vehicle_id UUID NOT NULL REFERENCES marketplace.vehicles(id),
    status VARCHAR(30) NOT NULL DEFAULT 'intent',
    -- intent → reserved → kyc_pending → kyc_approved → financing_pending →
    -- financing_approved → insurance_pending → insurance_selected →
    -- payment_pending → confirmed → completed → cancelled
    reservation_expires_at TIMESTAMPTZ,
    financing_offer_id UUID, -- ref a financing_offers
    insurance_offer_id UUID, -- ref a insurance_quotes
    total_price NUMERIC(14,2),
    down_payment NUMERIC(14,2),
    notes TEXT,
    cancelled_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- AUDIT LOG DE PURCHASE FLOW
CREATE TABLE marketplace.purchase_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_id UUID NOT NULL REFERENCES marketplace.purchase_intents(id),
    from_status VARCHAR(30),
    to_status VARCHAR(30) NOT NULL,
    actor_id UUID, -- user or system
    actor_type VARCHAR(20) DEFAULT 'user', -- user, system, admin
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- KYC - VERIFICACION DE IDENTIDAD
CREATE TABLE marketplace.kyc_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES marketplace.users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending, documents_uploaded, in_review, approved, rejected, expired
    ine_front_url TEXT, -- S3 encrypted
    ine_back_url TEXT,
    selfie_url TEXT,
    proof_of_address_url TEXT,
    ocr_data JSONB, -- {nombre, curp, direccion, vigencia}
    face_match_score NUMERIC(5,2), -- 0-100
    curp_validated BOOLEAN DEFAULT false,
    pld_checked BOOLEAN DEFAULT false,
    pld_result VARCHAR(20), -- clean, flagged, blocked
    risk_score NUMERIC(5,2),
    rejection_reasons JSONB DEFAULT '[]',
    reviewer_id UUID,
    reviewed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ, -- KYC valid for 6 months
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- SOLICITUDES DE FINANCIAMIENTO
CREATE TABLE marketplace.financing_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES marketplace.users(id),
    vehicle_id UUID NOT NULL REFERENCES marketplace.vehicles(id),
    purchase_id UUID REFERENCES marketplace.purchase_intents(id),
    vehicle_price NUMERIC(14,2) NOT NULL,
    down_payment NUMERIC(14,2) NOT NULL,
    requested_term_months INTEGER NOT NULL, -- 12, 24, 36, 48, 60
    employment_type VARCHAR(30), -- asalariado, independiente, empresario
    monthly_income NUMERIC(14,2),
    bureau_consent BOOLEAN DEFAULT false,
    bureau_consent_at TIMESTAMPTZ,
    status VARCHAR(20) DEFAULT 'draft', -- draft, submitted, evaluating, offers_ready, accepted, rejected
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- OFERTAS DE FINANCIERAS
CREATE TABLE marketplace.financing_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL REFERENCES marketplace.financing_applications(id),
    institution_id UUID NOT NULL REFERENCES marketplace.partner_institutions(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending, evaluating, approved, rejected, expired, accepted
    interest_rate NUMERIC(6,4), -- tasa anual
    cat NUMERIC(6,4), -- Costo Anual Total
    term_months INTEGER,
    monthly_payment NUMERIC(14,2),
    total_to_pay NUMERIC(14,2),
    down_payment_required NUMERIC(14,2),
    conditions JSONB DEFAULT '{}', -- condiciones especiales
    valid_until TIMESTAMPTZ,
    rejection_reason TEXT,
    response_time_ms INTEGER, -- tiempo de respuesta
    raw_response JSONB, -- respuesta original de la financiera
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- COTIZACIONES DE SEGUROS
CREATE TABLE marketplace.insurance_quotes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES marketplace.users(id),
    vehicle_id UUID NOT NULL REFERENCES marketplace.vehicles(id),
    purchase_id UUID REFERENCES marketplace.purchase_intents(id),
    coverage_type VARCHAR(20) NOT NULL, -- basica, amplia, premium
    driver_age INTEGER,
    driver_gender VARCHAR(10),
    driver_zip_code VARCHAR(10),
    driving_history JSONB DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'quoting', -- quoting, quotes_ready, selected, contracted
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- OFERTAS DE ASEGURADORAS
CREATE TABLE marketplace.insurance_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quote_id UUID NOT NULL REFERENCES marketplace.insurance_quotes(id),
    provider_id UUID NOT NULL REFERENCES marketplace.partner_institutions(id),
    status VARCHAR(20) DEFAULT 'quoted', -- quoted, selected, contracted, cancelled
    coverage_type VARCHAR(20) NOT NULL,
    annual_premium NUMERIC(14,2),
    monthly_premium NUMERIC(14,2),
    deductible_percentage NUMERIC(5,2),
    deductible_amount NUMERIC(14,2),
    coverages JSONB NOT NULL, -- {responsabilidad_civil: true, robo_total: true, ...}
    exclusions JSONB DEFAULT '[]',
    valid_until TIMESTAMPTZ,
    policy_number VARCHAR(50),
    raw_response JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- INSTITUCIONES PARTNER (FINANCIERAS Y ASEGURADORAS)
CREATE TABLE marketplace.partner_institutions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    type VARCHAR(20) NOT NULL, -- financiera, aseguradora
    code VARCHAR(50) UNIQUE NOT NULL, -- identificador corto
    logo_url TEXT,
    api_base_url TEXT,
    api_credentials JSONB, -- encrypted at rest
    webhook_url TEXT,
    webhook_secret VARCHAR(255),
    is_active BOOLEAN DEFAULT true,
    config JSONB DEFAULT '{}', -- timeout, retry, circuit_breaker settings
    health_status VARCHAR(20) DEFAULT 'unknown', -- healthy, degraded, down, unknown
    last_health_check TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- NOTIFICACIONES
CREATE TABLE marketplace.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES marketplace.users(id),
    type VARCHAR(50) NOT NULL, -- price_change, vehicle_sold, kyc_approved, offer_received, etc.
    title VARCHAR(255) NOT NULL,
    body TEXT,
    data JSONB DEFAULT '{}', -- payload contextual
    channel VARCHAR(20) DEFAULT 'in_app', -- in_app, email, push, whatsapp, sms
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- CONVERSACIONES (CHAT)
CREATE TABLE marketplace.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id UUID REFERENCES marketplace.vehicles(id),
    buyer_id UUID NOT NULL REFERENCES marketplace.users(id),
    seller_id UUID NOT NULL REFERENCES marketplace.users(id),
    status VARCHAR(20) DEFAULT 'active', -- active, archived, blocked
    last_message_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE marketplace.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES marketplace.conversations(id),
    sender_id UUID NOT NULL REFERENCES marketplace.users(id),
    content TEXT NOT NULL,
    type VARCHAR(20) DEFAULT 'text', -- text, image, file, system
    attachment_url TEXT,
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- BUSQUEDAS GUARDADAS
CREATE TABLE marketplace.saved_searches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES marketplace.users(id),
    name VARCHAR(100),
    filters JSONB NOT NULL, -- {brand: "Toyota", year_min: 2020, price_max: 300000, ...}
    notify_new_matches BOOLEAN DEFAULT true,
    last_notified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- INDICES
CREATE INDEX idx_vehicles_brand_model ON marketplace.vehicles(brand, model);
CREATE INDEX idx_vehicles_year ON marketplace.vehicles(year);
CREATE INDEX idx_vehicles_price ON marketplace.vehicles(price);
CREATE INDEX idx_vehicles_status ON marketplace.vehicles(status);
CREATE INDEX idx_vehicles_location ON marketplace.vehicles(location_state, location_city);
CREATE INDEX idx_vehicles_source ON marketplace.vehicles(source);
CREATE INDEX idx_favorites_user ON marketplace.favorites(user_id);
CREATE INDEX idx_purchase_user ON marketplace.purchase_intents(user_id);
CREATE INDEX idx_purchase_status ON marketplace.purchase_intents(status);
CREATE INDEX idx_notifications_user ON marketplace.notifications(user_id, is_read);
CREATE INDEX idx_messages_conversation ON marketplace.messages(conversation_id, created_at);
```

## 3. API Endpoints Map

### Vehicles (Port 5010)
```
GET    /api/v1/vehicles                    # Listado paginado con filtros
GET    /api/v1/vehicles/:id                # Detalle completo
GET    /api/v1/vehicles/:id/media          # Galeria de imagenes
GET    /api/v1/vehicles/:id/reports        # Reportes tecnicos (dossier)
GET    /api/v1/vehicles/:id/valuation      # Valuacion IA
GET    /api/v1/vehicles/:id/price-history  # Historial de precios
GET    /api/v1/vehicles/:id/similar        # Vehiculos similares
GET    /api/v1/vehicles/search             # Full-text search (Elasticsearch)
GET    /api/v1/vehicles/filters            # Filtros disponibles con counts
GET    /api/v1/vehicles/compare            # Comparar hasta 4 vehiculos
```

### Auth & Users
```
POST   /api/v1/auth/register              # Registro
POST   /api/v1/auth/login                 # Login
POST   /api/v1/auth/refresh               # Refresh token
POST   /api/v1/auth/logout                # Logout
POST   /api/v1/auth/forgot-password       # Recuperar password
POST   /api/v1/auth/verify-email          # Verificar email
GET    /api/v1/users/me                    # Mi perfil
PUT    /api/v1/users/me                    # Actualizar perfil
GET    /api/v1/users/me/favorites          # Mis favoritos
POST   /api/v1/users/me/favorites/:vid    # Agregar favorito
DELETE /api/v1/users/me/favorites/:vid    # Quitar favorito
GET    /api/v1/users/me/searches           # Busquedas guardadas
POST   /api/v1/users/me/searches           # Guardar busqueda
```

### Purchase Flow
```
POST   /api/v1/purchase/intent             # Crear intencion de compra
GET    /api/v1/purchase/:id                # Estado de compra
PUT    /api/v1/purchase/:id/status         # Actualizar estado
GET    /api/v1/purchase/:id/timeline       # Timeline de la compra
POST   /api/v1/purchase/:id/cancel         # Cancelar
GET    /api/v1/purchase/my                  # Mis compras
```

### KYC
```
GET    /api/v1/kyc/status                  # Estado KYC del usuario
POST   /api/v1/kyc/documents               # Upload documentos
POST   /api/v1/kyc/selfie                  # Upload selfie
POST   /api/v1/kyc/proof-of-address        # Upload comprobante domicilio
POST   /api/v1/kyc/submit                  # Enviar a verificacion
GET    /api/v1/kyc/history                 # Historial de verificaciones
```

### Financing
```
POST   /api/v1/financing/calculate         # Calculadora rapida
POST   /api/v1/financing/apply             # Solicitud formal
GET    /api/v1/financing/:id               # Estado de solicitud
GET    /api/v1/financing/:id/offers        # Ofertas recibidas
POST   /api/v1/financing/:id/accept/:oid  # Aceptar oferta
WS     /api/v1/financing/:id/stream        # WebSocket ofertas real-time
GET    /api/v1/financing/institutions       # Financieras disponibles
```

### Insurance
```
POST   /api/v1/insurance/quote             # Cotizar seguros
GET    /api/v1/insurance/:id               # Estado de cotizacion
GET    /api/v1/insurance/:id/offers        # Ofertas de aseguradoras
POST   /api/v1/insurance/:id/select/:oid  # Seleccionar oferta
POST   /api/v1/insurance/:id/contract      # Contratar poliza
GET    /api/v1/insurance/providers          # Aseguradoras disponibles
```

### Admin
```
GET    /api/v1/admin/dashboard             # KPIs
GET    /api/v1/admin/users                 # Gestion usuarios
GET    /api/v1/admin/vehicles              # Gestion inventario
POST   /api/v1/admin/vehicles/bulk         # Upload masivo
GET    /api/v1/admin/partners              # Gestion partners
POST   /api/v1/admin/partners              # Alta partner
PUT    /api/v1/admin/partners/:id          # Editar partner
GET    /api/v1/admin/transactions          # Historial transacciones
GET    /api/v1/admin/audit-log             # Audit log
```

### Notifications & Chat
```
GET    /api/v1/notifications               # Mis notificaciones
PUT    /api/v1/notifications/:id/read      # Marcar leida
PUT    /api/v1/notifications/read-all      # Marcar todas leidas
GET    /api/v1/notifications/preferences   # Preferencias
PUT    /api/v1/notifications/preferences   # Actualizar preferencias
WS     /api/v1/chat/ws                     # WebSocket chat
GET    /api/v1/chat/conversations          # Mis conversaciones
GET    /api/v1/chat/:conv_id/messages      # Mensajes de conversacion
POST   /api/v1/chat/:conv_id/messages      # Enviar mensaje
```

### Market Analytics
```
GET    /api/v1/market/trends               # Tendencias de mercado
GET    /api/v1/market/price-index          # Indice de precios
GET    /api/v1/market/demand               # Demanda por segmento
GET    /api/v1/market/sources              # Datos por fuente
```

## 4. Frontend Routes Map (Angular 18)

```
/                                    → Landing / Home
/auth/login                          → Login
/auth/register                       → Registro multi-step
/auth/forgot-password                → Recuperar contrasena
/auth/verify-email                   → Verificar email

/vehicles                            → Catalogo con filtros
/vehicles/:id                        → Detalle de vehiculo
/vehicles/:id/report                 → Reporte tecnico
/vehicles/compare                    → Comparacion

/purchase/:id                        → Wizard de compra
/purchase/:id/tracking               → Tracking de compra

/financing/calculator                → Cotizador de credito
/financing/:id/offers                → Ofertas de financieras

/insurance/quote                     → Cotizador de seguros
/insurance/:id/compare               → Comparador de seguros

/profile                             → Mi perfil
/profile/favorites                   → Mis favoritos
/profile/purchases                   → Mis compras
/profile/kyc                         → Verificacion de identidad
/profile/notifications               → Notificaciones
/profile/settings                    → Configuracion

/market                              → Dashboard de mercado
/market/trends                       → Tendencias
/market/analysis                     → Analisis de precios

/admin                               → Dashboard admin
/admin/users                         → Gestion usuarios
/admin/vehicles                      → Gestion inventario
/admin/partners                      → Gestion partners
/admin/transactions                  → Transacciones
/admin/settings                      → Configuracion sistema

/chat                                → Mis conversaciones
/chat/:id                            → Conversacion
```

## 5. Hexagonal Architecture (Backend)

```
proj-back-marketplace/
├── app/
│   ├── __init__.py                  # create_app() factory
│   ├── config.py                    # Configuration by environment
│   ├── extensions.py                # Flask extensions init
│   │
│   ├── domain/                      # ZERO external dependencies
│   │   ├── models/
│   │   │   ├── user.py              # User entity
│   │   │   ├── vehicle.py           # Vehicle entity
│   │   │   ├── purchase.py          # PurchaseIntent entity + state machine
│   │   │   ├── kyc.py               # KYCVerification entity
│   │   │   ├── financing.py         # FinancingApplication, Offer entities
│   │   │   ├── insurance.py         # InsuranceQuote, Offer entities
│   │   │   ├── notification.py      # Notification entity
│   │   │   └── conversation.py      # Conversation, Message entities
│   │   ├── ports/
│   │   │   ├── vehicle_repository.py       # ABC
│   │   │   ├── user_repository.py          # ABC
│   │   │   ├── purchase_repository.py      # ABC
│   │   │   ├── kyc_repository.py           # ABC
│   │   │   ├── financing_repository.py     # ABC
│   │   │   ├── insurance_repository.py     # ABC
│   │   │   ├── notification_repository.py  # ABC
│   │   │   ├── search_engine.py            # ABC (Elasticsearch)
│   │   │   ├── storage_service.py          # ABC (S3)
│   │   │   ├── cache_service.py            # ABC (Redis)
│   │   │   ├── financial_institution.py    # ABC (adapter per financiera)
│   │   │   ├── insurance_provider.py       # ABC (adapter per aseguradora)
│   │   │   ├── identity_verifier.py        # ABC (KYC provider)
│   │   │   └── notification_channel.py     # ABC (email, push, whatsapp)
│   │   ├── events/
│   │   │   ├── vehicle_events.py
│   │   │   ├── purchase_events.py
│   │   │   └── notification_events.py
│   │   └── exceptions/
│   │       ├── vehicle_exceptions.py
│   │       ├── purchase_exceptions.py
│   │       └── kyc_exceptions.py
│   │
│   ├── application/                 # Use cases / orchestration
│   │   ├── services/
│   │   │   ├── vehicle_service.py
│   │   │   ├── search_service.py
│   │   │   ├── purchase_service.py
│   │   │   ├── kyc_service.py
│   │   │   ├── financing_service.py
│   │   │   ├── insurance_service.py
│   │   │   ├── notification_service.py
│   │   │   ├── chat_service.py
│   │   │   └── admin_service.py
│   │   └── dto/
│   │       ├── vehicle_dto.py
│   │       ├── purchase_dto.py
│   │       └── financing_dto.py
│   │
│   ├── infrastructure/              # Implementations
│   │   ├── persistence/
│   │   │   ├── sqlalchemy_models.py
│   │   │   ├── vehicle_sqlalchemy_repo.py
│   │   │   ├── user_sqlalchemy_repo.py
│   │   │   └── ...
│   │   ├── search/
│   │   │   └── elasticsearch_adapter.py
│   │   ├── storage/
│   │   │   └── s3_adapter.py
│   │   ├── cache/
│   │   │   └── redis_adapter.py
│   │   ├── auth/
│   │   │   └── cognito_adapter.py
│   │   ├── financial/
│   │   │   ├── financiera_a_adapter.py
│   │   │   ├── financiera_b_adapter.py
│   │   │   └── ...
│   │   ├── insurance/
│   │   │   ├── qualitas_adapter.py
│   │   │   ├── gnp_adapter.py
│   │   │   └── ...
│   │   ├── kyc/
│   │   │   └── kyc_provider_adapter.py
│   │   └── messaging/
│   │       ├── ses_email_adapter.py
│   │       ├── fcm_push_adapter.py
│   │       └── whatsapp_adapter.py
│   │
│   └── api/                         # Routes (thin controllers)
│       ├── v1/
│       │   ├── vehicles.py
│       │   ├── auth.py
│       │   ├── users.py
│       │   ├── purchase.py
│       │   ├── kyc.py
│       │   ├── financing.py
│       │   ├── insurance.py
│       │   ├── admin.py
│       │   ├── notifications.py
│       │   ├── chat.py
│       │   └── market.py
│       ├── schemas/                  # Marshmallow schemas
│       │   ├── vehicle_schema.py
│       │   ├── user_schema.py
│       │   └── ...
│       └── middleware/
│           ├── auth_middleware.py
│           ├── rate_limit.py
│           └── error_handler.py
│
├── migrations/                      # Alembic
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── docker-compose.yml
├── Dockerfile
├── pyproject.toml
└── README.md
```

## 6. Frontend Architecture (Angular 18)

```
proj-front-marketplace/
├── src/
│   ├── app/
│   │   ├── core/
│   │   │   ├── domain/
│   │   │   │   ├── models/
│   │   │   │   │   ├── vehicle.model.ts
│   │   │   │   │   ├── user.model.ts
│   │   │   │   │   ├── purchase.model.ts
│   │   │   │   │   ├── financing.model.ts
│   │   │   │   │   ├── insurance.model.ts
│   │   │   │   │   └── notification.model.ts
│   │   │   │   └── ports/
│   │   │   │       ├── vehicle.port.ts
│   │   │   │       ├── auth.port.ts
│   │   │   │       ├── purchase.port.ts
│   │   │   │       ├── financing.port.ts
│   │   │   │       ├── insurance.port.ts
│   │   │   │       └── notification.port.ts
│   │   │   ├── application/
│   │   │   │   ├── state/
│   │   │   │   │   ├── auth.state.ts          # Signals-based
│   │   │   │   │   ├── vehicle-filters.state.ts
│   │   │   │   │   ├── cart.state.ts
│   │   │   │   │   └── notification.state.ts
│   │   │   │   └── services/
│   │   │   │       └── ...
│   │   │   └── infrastructure/
│   │   │       ├── adapters/
│   │   │       │   ├── vehicle-api.adapter.ts
│   │   │       │   ├── auth-cognito.adapter.ts
│   │   │       │   ├── purchase-api.adapter.ts
│   │   │       │   ├── financing-api.adapter.ts
│   │   │       │   ├── insurance-api.adapter.ts
│   │   │       │   └── notification-api.adapter.ts
│   │   │       ├── interceptors/
│   │   │       │   ├── jwt.interceptor.ts
│   │   │       │   └── error.interceptor.ts
│   │   │       └── guards/
│   │   │           ├── auth.guard.ts
│   │   │           └── kyc.guard.ts
│   │   │
│   │   ├── features/                # Lazy-loaded routes
│   │   │   ├── landing/
│   │   │   ├── auth/
│   │   │   │   ├── login/
│   │   │   │   ├── register/
│   │   │   │   └── forgot-password/
│   │   │   ├── vehicles/
│   │   │   │   ├── catalog/         # Grid + Filters
│   │   │   │   ├── detail/          # Detail + Carousel
│   │   │   │   └── compare/
│   │   │   ├── purchase/
│   │   │   │   ├── wizard/          # Multi-step buy flow
│   │   │   │   └── tracking/
│   │   │   ├── financing/
│   │   │   │   ├── calculator/
│   │   │   │   ├── application/
│   │   │   │   └── offers/
│   │   │   ├── insurance/
│   │   │   │   ├── quote/
│   │   │   │   ├── compare/
│   │   │   │   └── contract/
│   │   │   ├── profile/
│   │   │   │   ├── overview/
│   │   │   │   ├── favorites/
│   │   │   │   ├── purchases/
│   │   │   │   ├── kyc/
│   │   │   │   └── settings/
│   │   │   ├── market/
│   │   │   │   ├── trends/
│   │   │   │   └── analysis/
│   │   │   ├── admin/
│   │   │   │   ├── dashboard/
│   │   │   │   ├── users/
│   │   │   │   ├── vehicles/
│   │   │   │   ├── partners/
│   │   │   │   └── transactions/
│   │   │   └── chat/
│   │   │
│   │   ├── shared/
│   │   │   ├── components/
│   │   │   │   ├── vehicle-card/
│   │   │   │   ├── photo-carousel/
│   │   │   │   ├── price-tag/
│   │   │   │   ├── filter-panel/
│   │   │   │   ├── range-slider/
│   │   │   │   ├── kpi-card/
│   │   │   │   ├── stepper/
│   │   │   │   ├── empty-state/
│   │   │   │   ├── skeleton-loader/
│   │   │   │   ├── confirmation-dialog/
│   │   │   │   └── toast/
│   │   │   ├── directives/
│   │   │   ├── pipes/
│   │   │   └── animations/
│   │   │
│   │   └── layout/
│   │       ├── header/
│   │       ├── footer/
│   │       ├── sidebar/
│   │       └── main-layout/
│   │
│   ├── assets/
│   ├── environments/
│   └── styles/
│       ├── _variables.scss
│       ├── _typography.scss
│       ├── _animations.scss
│       └── global.scss
│
├── angular.json
├── tailwind.config.js
├── package.json
└── README.md
```

## 7. Flujos Principales

### Flujo de Compra (Purchase Flow)
```
[Catalogo] → [Detalle Vehiculo] → [Click "Comprar"]
                                        │
                                        ▼
                                  ¿Usuario logueado?
                                  NO → [Login/Register]
                                  SI ↓
                                        │
                                        ▼
                                  ¿KYC aprobado?
                                  NO → [Flujo KYC] → Esperar aprobacion
                                  SI ↓
                                        │
                                        ▼
                              [Step 1: Confirmar vehiculo]
                                        │
                              [Step 2: ¿Financiamiento?]
                              SI → [Cotizador] → [Ofertas real-time] → [Seleccionar]
                              NO ↓
                                        │
                              [Step 3: ¿Seguro?]
                              SI → [Cotizador] → [Comparador] → [Seleccionar]
                              NO ↓
                                        │
                              [Step 4: Resumen + Total]
                                        │
                              [Step 5: Confirmar compra]
                                        │
                              [Tracking page con timeline]
```

### Flujo de Financiamiento Real-Time
```
[Usuario llena solicitud] → POST /financing/apply
                                    │
                              [Fan-out SQS]
                              ┌─────┼─────┐
                              ▼     ▼     ▼
                          [Fin.A] [Fin.B] [Fin.C]
                              │     │     │
                              ▼     ▼     ▼
                          [Eval]  [Eval]  [Eval]
                              │     │     │
                              └─────┼─────┘
                                    ▼
                          [WebSocket push ofertas]
                          [Cards aparecen en real-time]
                                    │
                          [Usuario compara y selecciona]
```
