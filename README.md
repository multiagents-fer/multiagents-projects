# Multiagents Projects - Central Project Management

Central hub for project management, epics, user stories, and tasks for the **AgentsMX** ecosystem.

## Marketplace Automotriz AgentsMX

### Vision
Marketplace automotriz innovador que integra compra-venta de vehiculos, financiamiento multi-financiera en tiempo real, seguros multi-aseguradora, verificacion de identidad (KYC), reportes tecnicos con IA, y analisis de mercado con datos de 18+ fuentes.

### Nomenclatura de Tickets

| Prefijo | Tipo | Ejemplo |
|---------|------|---------|
| `MKT-EP-XXX` | Epica | `[MKT-EP-001] Plataforma Base` |
| `MKT-BE-XXX` | Backend User Story | `[MKT-BE-001] API Base Flask` |
| `MKT-FE-XXX` | Frontend User Story | `[MKT-FE-001] Angular Setup` |
| `MKT-INT-XXX` | Integracion | `[MKT-INT-001] Sync scrapper_nacional` |
| `MKT-INF-XXX` | Infraestructura | `[MKT-INF-001] Setup Monorepo` |

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

### Repositories

| Repo | Tipo | Descripcion |
|------|------|-------------|
| `proj-front-marketplace` | Frontend | Angular 18 Marketplace UI |
| `proj-back-marketplace` | Backend | Flask API Marketplace |
| `proj-back-ai-agents` | Backend | 7 AI Agents (existente) |
| `mod_scrapper_nacional` | Data | 18 fuentes, 11,000+ vehiculos (existente) |
| `proj-worker-marketplace-sync` | Worker | SQS event consumer (existente) |
| `proj-worker-diagnostic-sync` | Worker | OBD-II diagnostic processor (existente) |
| `proj-infra-gps` | Infra | Terraform AWS (existente) |

### How to Use This Repo

1. All project management is tracked via [GitHub Issues](../../issues)
2. Board view in [GitHub Projects](../../projects)
3. Each issue has detailed acceptance criteria (10+ per story)
4. Issues are designed for AI agents (Claude Code) to pick up and implement with full context
