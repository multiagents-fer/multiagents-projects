# Multiagents Projects - Central Project Management

Central hub for project management, epics, user stories, and tasks for the **AgentsMX** ecosystem.

## Marketplace Automotriz AgentsMX

### Vision
Marketplace automotriz innovador que integra compra-venta de vehiculos, financiamiento multi-financiera en tiempo real, seguros multi-aseguradora, verificacion de identidad (KYC), reportes tecnicos con IA, y analisis de mercado con datos de 18+ fuentes.

### Nomenclatura de Tickets

#### Por Tipo de Issue
| Prefijo | Tipo | Ejemplo |
|---------|------|---------|
| `MKT-EP-XXX` | Epica | `[MKT-EP-001] Plataforma Base` |
| `MKT-US-XXX` | User Story | `[MKT-US-001] Como comprador quiero buscar vehiculos` |
| `MKT-TK-XXX` | Task (implementacion) | `[MKT-TK-001] Crear endpoint GET /vehicles` |

#### Por Microservicio (prefijo del componente)
| Codigo | Microservicio | Repo | Puerto | Descripcion |
|--------|--------------|------|--------|-------------|
| `SVC-GW` | API Gateway | `svc-gateway` | 8080 | Enrutamiento, rate limiting, auth validation |
| `SVC-AUTH` | Auth Service | `svc-auth` | 5010 | Registro, login, JWT, Cognito integration |
| `SVC-USR` | User Service | `svc-users` | 5011 | Perfiles, preferencias, favoritos |
| `SVC-VEH` | Vehicle Service | `svc-vehicles` | 5012 | Catalogo, busqueda, media, filtros |
| `SVC-PUR` | Purchase Service | `svc-purchase` | 5013 | Flujo de compra, state machine, reservaciones |
| `SVC-KYC` | KYC Service | `svc-kyc` | 5014 | Verificacion identidad, OCR, face match |
| `SVC-FIN` | Financing Service | `svc-financing` | 5015 | Cotizador credito, solicitudes, ofertas real-time |
| `SVC-INS` | Insurance Service | `svc-insurance` | 5016 | Cotizador seguros, comparador, contratacion |
| `SVC-NTF` | Notification Service | `svc-notifications` | 5017 | In-app, email, push, WhatsApp, SMS |
| `SVC-CHT` | Chat Service | `svc-chat` | 5018 | WebSocket messaging, conversations |
| `SVC-MKT` | Market Analytics | `svc-market-analytics` | 5019 | Tendencias, indices, demanda |
| `SVC-ADM` | Admin Service | `svc-admin` | 5020 | Dashboard admin, gestion partners |
| `SVC-RPT` | Report Service | `svc-reports` | 5021 | Reportes tecnicos, valuaciones IA |
| `SVC-SEO` | SEO Service | `svc-seo` | 5022 | Sitemap, metadata, structured data |
| `WRK-SYNC` | Marketplace Sync Worker | `wrk-marketplace-sync` | - | SQS consumer, sync scrapper data |
| `WRK-DIAG` | Diagnostic Sync Worker | `wrk-diagnostic-sync` | - | OBD-II PDF processing |
| `WRK-NTF` | Notification Worker | `wrk-notification-dispatch` | - | Async notification delivery |
| `WRK-FIN` | Financing Worker | `wrk-financing-eval` | - | Fan-out/aggregate financiera responses |
| `WRK-INS` | Insurance Worker | `wrk-insurance-eval` | - | Fan-out/aggregate aseguradora responses |

#### Por Capa (dentro de cada microservicio)
| Sufijo | Capa | Ejemplo Ticket |
|--------|------|----------------|
| `-DOM` | Domain (modelos, puertos, excepciones) | `[MKT-TK-001][SVC-VEH-DOM] Crear Vehicle entity` |
| `-APP` | Application (servicios, DTOs, use cases) | `[MKT-TK-002][SVC-VEH-APP] VehicleSearchService` |
| `-INF` | Infrastructure (repos, adapters, cache) | `[MKT-TK-003][SVC-VEH-INF] ElasticsearchAdapter` |
| `-API` | API (routes, schemas, middleware) | `[MKT-TK-004][SVC-VEH-API] GET /api/v1/vehicles` |
| `-TST` | Tests (unit, integration, e2e) | `[MKT-TK-005][SVC-VEH-TST] Vehicle search tests` |
| `-CFG` | Config (Docker, env, CI/CD) | `[MKT-TK-006][SVC-VEH-CFG] Dockerfile + compose` |

#### Frontend (Angular 18)
| Codigo | Modulo | Descripcion |
|--------|--------|-------------|
| `FE-CORE` | Core | Domain models, ports, state management (signals) |
| `FE-FEAT-AUTH` | Feature: Auth | Login, register, forgot-password |
| `FE-FEAT-CAT` | Feature: Catalog | Vehicle grid, filters, search |
| `FE-FEAT-DET` | Feature: Detail | Vehicle detail, photo carousel |
| `FE-FEAT-PUR` | Feature: Purchase | Buy wizard, tracking |
| `FE-FEAT-FIN` | Feature: Financing | Calculator, application, offers |
| `FE-FEAT-INS` | Feature: Insurance | Quote, compare, contract |
| `FE-FEAT-PRF` | Feature: Profile | Profile, favorites, KYC, settings |
| `FE-FEAT-MKT` | Feature: Market | Trends, analysis dashboards |
| `FE-FEAT-ADM` | Feature: Admin | Admin dashboard, inventory, partners |
| `FE-FEAT-CHT` | Feature: Chat | Chat widget, conversations |
| `FE-SHARED` | Shared | Reusable components, pipes, directives |
| `FE-LAYOUT` | Layout | Header, footer, sidebar, main layout |

#### Infraestructura
| Codigo | Componente | Descripcion |
|--------|-----------|-------------|
| `INF-NET` | Networking | VPC, subnets, ALB, security groups |
| `INF-CMP` | Compute | ECS Fargate, task definitions, ASG |
| `INF-DB` | Database | RDS PostgreSQL, ElastiCache Redis, Elasticsearch |
| `INF-STR` | Storage | S3 buckets, CloudFront CDN |
| `INF-MSG` | Messaging | SQS queues, SNS topics, EventBridge |
| `INF-SEC` | Security | Cognito, IAM, KMS, WAF |
| `INF-MON` | Monitoring | CloudWatch, X-Ray, Grafana |
| `INF-CI` | CI/CD | GitHub Actions, ECR, deploy pipelines |

#### Ejemplo Completo de Ticket para IA
```
Titulo: [MKT-TK-042][SVC-FIN-API] POST /api/v1/financing/apply - Solicitud de credito multi-financiera

Labels: task, backend, mod-financing, sprint-5, priority-high, SVC-FIN, ready-for-dev

Descripcion:
  Microservicio: SVC-FIN (svc-financing, puerto 5015)
  Capa: API (routes + schemas)
  Repo: multiagents-fer/svc-financing
  Dependencias: SVC-AUTH (JWT validation), SVC-KYC (status check), WRK-FIN (fan-out)
  ...
```

### Epicas

| # | Epica | Sprint | Prioridad |
|---|-------|--------|-----------|
| EP-001 | Plataforma Base, Arquitectura & Setup | Sprint 1-2 | Critical |
| EP-002 | Autenticacion, Registro & Perfiles | Sprint 2-3 | Critical |
| EP-003 | Catalogo de Vehiculos & Motor de Busqueda | Sprint 2-4 | Critical |
| EP-004 | Reportes Tecnicos, Valuacion & Mercado | Sprint 3-5 | High |
| EP-005 | Flujo de Compra Intuitivo | Sprint 4-6 | Critical |
| EP-006 | Verificacion de Identidad (KYC) | Sprint 5-6 | High |
| EP-007 | Cotizador de Financiamiento | Sprint 5-7 | High |
| EP-008 | Marketplace de Seguros | Sprint 6-8 | High |
| EP-009 | Panel de Administracion | Sprint 3-8 | Medium |
| EP-010 | Notificaciones, Comunicacion & SEO | Sprint 7-8 | Medium |

### Tech Stack

- **Backend**: Python 3.11 + Flask 3.0 + SQLAlchemy 2.0 + Marshmallow
- **Frontend**: Angular 18 + Tailwind CSS v4 + Standalone Components + Signals
- **Database**: PostgreSQL 15 + Redis 7 + Elasticsearch 8
- **Auth**: AWS Cognito + JWT
- **Infra**: AWS ECS Fargate + RDS + S3 + CloudFront + SQS + Terraform
- **AI**: Claude API (Anthropic) via proj-back-ai-agents
- **CI/CD**: GitHub Actions
- **Messaging**: AWS SQS + SNS + EventBridge
- **API Gateway**: Custom Flask gateway or AWS API Gateway

### Microservices Architecture

```
                    ┌──────────────────┐
                    │   CloudFront     │
                    │   (CDN + SSL)    │
                    └────────┬─────────┘
                             │
              ┌──────────────▼──────────────┐
              │     ALB (Load Balancer)      │
              │   api.marketplace.agentsmx   │
              └──────┬──────────────┬────────┘
                     │              │
         ┌───────────▼───┐  ┌──────▼──────────┐
         │  SVC-GW:8080  │  │  Angular SSR    │
         │  API Gateway  │  │  (Static S3)    │
         └───────┬───────┘  └─────────────────┘
                 │
    ┌────────────┼────────────────────────────────┐
    │            │            │         │         │
┌───▼───┐  ┌────▼────┐  ┌────▼───┐ ┌───▼───┐ ┌──▼────┐
│SVC-AUTH│  │SVC-VEH  │  │SVC-PUR │ │SVC-FIN│ │SVC-INS│
│ :5010  │  │ :5012   │  │ :5013  │ │ :5015 │ │ :5016 │
└───┬────┘  └────┬────┘  └───┬────┘ └───┬───┘ └──┬────┘
    │            │           │         │        │
    └────────────┴───────────┴─────────┴────────┘
                         │
              ┌──────────▼──────────┐
              │   PostgreSQL (RDS)  │
              │   + Redis + ES      │
              └─────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼─────┐  ┌──────▼──────┐  ┌─────▼─────┐
    │WRK-SYNC  │  │WRK-FIN      │  │WRK-NTF    │
    │(SQS)     │  │(SQS fan-out)│  │(SQS async)│
    └──────────┘  └─────────────┘  └───────────┘
```

### Repositories (Microservices)

#### Nuevos (Marketplace)
| Repo | Codigo | Puerto | Descripcion |
|------|--------|--------|-------------|
| `svc-gateway` | SVC-GW | 8080 | API Gateway - routing, rate limiting |
| `svc-auth` | SVC-AUTH | 5010 | Auth - Cognito, JWT, registro |
| `svc-users` | SVC-USR | 5011 | Usuarios - perfiles, favoritos |
| `svc-vehicles` | SVC-VEH | 5012 | Vehiculos - catalogo, search, media |
| `svc-purchase` | SVC-PUR | 5013 | Compras - flujo, state machine |
| `svc-kyc` | SVC-KYC | 5014 | KYC - verificacion identidad |
| `svc-financing` | SVC-FIN | 5015 | Financiamiento - cotizador, ofertas |
| `svc-insurance` | SVC-INS | 5016 | Seguros - cotizador, comparador |
| `svc-notifications` | SVC-NTF | 5017 | Notificaciones multicanal |
| `svc-chat` | SVC-CHT | 5018 | Chat WebSocket |
| `svc-market-analytics` | SVC-MKT | 5019 | Analytics de mercado |
| `svc-admin` | SVC-ADM | 5020 | Panel administrativo |
| `svc-reports` | SVC-RPT | 5021 | Reportes tecnicos + valuacion |
| `svc-seo` | SVC-SEO | 5022 | SEO, sitemap, metadata |
| `proj-front-marketplace` | FE | 4200 | Angular 18 frontend |
| `wrk-notification-dispatch` | WRK-NTF | - | Worker despacho notificaciones |
| `wrk-financing-eval` | WRK-FIN | - | Worker evaluacion financieras |
| `wrk-insurance-eval` | WRK-INS | - | Worker evaluacion aseguradoras |

#### Existentes (Reutilizados)
| Repo | Codigo | Puerto | Descripcion |
|------|--------|--------|-------------|
| `proj-back-ai-agents` | SVC-AI | 5001 | 7 AI Agents (existente) |
| `proj-back-driver-adapters` | SVC-DRV | 5000 | GPS adapters (existente) |
| `proj-back-marketplace-dashboard` | SVC-DASH | 5050 | Dashboard analytics (existente) |
| `mod_scrapper_nacional` | MOD-SCR | - | 18 fuentes scraping (existente) |
| `proj-worker-marketplace-sync` | WRK-SYNC | - | SQS marketplace sync (existente) |
| `proj-worker-diagnostic-sync` | WRK-DIAG | - | OBD-II diagnostics (existente) |

### How to Use This Repo

1. All project management is tracked via [GitHub Issues](../../issues)
2. Board view in [GitHub Projects](../../projects)
3. Each issue has detailed acceptance criteria (10+ per story)
4. Issues are designed for AI agents (Claude Code) to pick up and implement with full context
