#!/usr/bin/env bash
set -e

REPO="multiagents-fer/multiagents-projects"

echo "========================================="
echo "  Vehicle Marketplace - Issue Creator"
echo "  Epics 1-5 with all User Stories"
echo "========================================="

# ─────────────────────────────────────────────
# CREATE LABELS
# ─────────────────────────────────────────────
echo ""
echo ">>> Creating labels..."

gh label create "epic"                --repo "$REPO" --color "0052CC" --force 2>/dev/null || true
gh label create "user-story"          --repo "$REPO" --color "1D76DB" --force 2>/dev/null || true
gh label create "task"                --repo "$REPO" --color "5319E7" --force 2>/dev/null || true
gh label create "backend"             --repo "$REPO" --color "D93F0B" --force 2>/dev/null || true
gh label create "frontend"            --repo "$REPO" --color "0E8A16" --force 2>/dev/null || true
gh label create "integration"         --repo "$REPO" --color "FBCA04" --force 2>/dev/null || true
gh label create "infrastructure"      --repo "$REPO" --color "B60205" --force 2>/dev/null || true
gh label create "priority-critical"   --repo "$REPO" --color "FF0000" --force 2>/dev/null || true
gh label create "priority-high"       --repo "$REPO" --color "FF6600" --force 2>/dev/null || true
gh label create "priority-medium"     --repo "$REPO" --color "FFCC00" --force 2>/dev/null || true
gh label create "priority-low"        --repo "$REPO" --color "99CC00" --force 2>/dev/null || true
gh label create "sprint-1"            --repo "$REPO" --color "C2E0C6" --force 2>/dev/null || true
gh label create "sprint-2"            --repo "$REPO" --color "C2E0C6" --force 2>/dev/null || true
gh label create "sprint-3"            --repo "$REPO" --color "C2E0C6" --force 2>/dev/null || true
gh label create "sprint-4"            --repo "$REPO" --color "C2E0C6" --force 2>/dev/null || true
gh label create "sprint-5"            --repo "$REPO" --color "C2E0C6" --force 2>/dev/null || true
gh label create "sprint-6"            --repo "$REPO" --color "C2E0C6" --force 2>/dev/null || true
gh label create "sprint-7"            --repo "$REPO" --color "C2E0C6" --force 2>/dev/null || true
gh label create "sprint-8"            --repo "$REPO" --color "C2E0C6" --force 2>/dev/null || true

echo ">>> Labels created."
sleep 2

###############################################################################
# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 1: [MKT-EP-001] Plataforma Base, Arquitectura & Setup Inicial
# ═══════════════════════════════════════════════════════════════════════════════
###############################################################################
echo ""
echo ">>> EPIC 1: Plataforma Base, Arquitectura & Setup Inicial"

gh issue create --repo "$REPO" \
  --title "[MKT-EP-001] Plataforma Base, Arquitectura & Setup Inicial" \
  --label "epic,priority-critical,sprint-1" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Setup completo de la arquitectura base del marketplace de vehiculos incluyendo monorepo structure, CI/CD pipelines, Docker environments, y design system foundation. Este epic establece toda la infraestructura tecnica necesaria para que los equipos de backend y frontend puedan trabajar en paralelo de forma eficiente.

## Contexto Tecnico
- **Backend**: Flask 3.0 con arquitectura hexagonal, SQLAlchemy 2.0 async, Marshmallow para serializacion, PostgreSQL 15, Redis para cache, Elasticsearch para busqueda
- **Frontend**: Angular 18 standalone components, Tailwind CSS v4, Angular Material/PrimeNG
- **Infra**: AWS ECS Fargate, RDS PostgreSQL 15, ElastiCache Redis, S3, CloudFront, SQS, Terraform
- **Auth**: AWS Cognito User Pools + Identity Pools
- **Datos existentes**: 11,000+ vehiculos de 18 fuentes en scrapper_nacional DB
- **Servicios existentes**: proj-back-ai-agents (7 agents), proj-back-driver-adapters, proj-worker-marketplace-sync

## Criterios de Aceptacion
- [ ] CA-01: Repositorios proj-back-marketplace y proj-front-marketplace creados con estructura base
- [ ] CA-02: Backend Flask 3.0 levanta con health check respondiendo en /api/health
- [ ] CA-03: Frontend Angular 18 compila y sirve en modo desarrollo
- [ ] CA-04: Docker Compose orquesta backend, frontend, PostgreSQL, Redis, Elasticsearch localmente
- [ ] CA-05: Pipeline CI/CD ejecuta build, test, lint en cada PR
- [ ] CA-06: Infraestructura AWS definida en Terraform y aplicable en environment dev
- [ ] CA-07: Design system base con tokens, tipografia y color system implementado
- [ ] CA-08: Comunicacion entre backend y frontend verificada con endpoint de prueba
- [ ] CA-09: Documentacion de arquitectura y setup local disponible en cada repo
- [ ] CA-10: Todos los environments (dev, staging, prod) configurados y desplegables
- [ ] CA-11: Monitoring basico con CloudWatch configurado
- [ ] CA-12: Secrets management con AWS Secrets Manager integrado

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
Este epic es bloqueante para todos los demas. Debe completarse en Sprint 1 para desbloquear el trabajo paralelo de los equipos.

## Dependencias
- Cuenta AWS con permisos de administracion
- Organizacion GitHub multiagents-fer configurada
- Dominio DNS configurado para el marketplace

## User Stories Contenidas
- [MKT-INF-001] Setup del Repositorio y Monorepo Structure
- [MKT-BE-001] API Base Flask con Arquitectura Hexagonal
- [MKT-FE-001] Angular 18 Project Setup con Design System Premium
- [MKT-INF-002] Pipeline CI/CD con GitHub Actions
- [MKT-INF-003] Infraestructura AWS con Terraform
ISSUE_EOF
)"
echo "  Created: [MKT-EP-001]"
sleep 2

# ─── MKT-INF-001 ───────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-INF-001] Setup del Repositorio y Monorepo Structure" \
  --label "user-story,infrastructure,priority-critical,sprint-1" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Crear y configurar los repositorios proj-back-marketplace y proj-front-marketplace con la estructura de carpetas correcta, configuraciones de linting, formatting, pre-commit hooks, y Docker Compose para desarrollo local completo.

## Contexto Tecnico
El marketplace se compone de dos repositorios principales que se comunican via REST API. El backend usa arquitectura hexagonal (ports and adapters) con Flask, y el frontend usa Angular 18 con standalone components. Ambos deben poder levantarse localmente con un solo comando docker-compose up.

### Estructura Backend (proj-back-marketplace):
```
proj-back-marketplace/
  src/
    domain/
      models/          # Entidades de dominio (Vehicle, User, Purchase)
      ports/           # Interfaces/ABCs (VehicleRepository, UserRepository)
      services/        # Domain services
      exceptions/      # Domain exceptions
    application/
      use_cases/       # Application use cases
      dto/             # Data Transfer Objects
      services/        # Application services (orchestration)
    infrastructure/
      adapters/        # SQLAlchemy repos, Redis cache, S3 storage
      database/        # DB config, Alembic migrations
      external/        # External service clients (Cognito, AI Agents)
      messaging/       # SQS consumers/producers
    api/
      routes/          # Flask blueprints
      middleware/       # Auth, CORS, error handling, logging
      schemas/         # Marshmallow schemas
      docs/            # OpenAPI specs
  tests/
    unit/
    integration/
    e2e/
  migrations/
  docker/
  Dockerfile
  docker-compose.yml
  pyproject.toml
```

### Estructura Frontend (proj-front-marketplace):
```
proj-front-marketplace/
  src/
    app/
      core/            # Guards, interceptors, singleton services
      shared/          # Shared components, pipes, directives
      features/        # Feature modules (vehicles, auth, profile, purchase)
      layouts/         # Layout components (main, auth, admin)
      design-system/   # Design tokens, base components
    assets/
    environments/
    styles/
      tokens/          # CSS custom properties
      base/            # Reset, typography, utilities
      components/      # Component-specific styles
  Dockerfile
  angular.json
  tailwind.config.ts
```

## Criterios de Aceptacion
- [ ] CA-01: Repositorio proj-back-marketplace creado con estructura hexagonal completa (domain/ports, application/services, infrastructure/adapters, api/routes) y pyproject.toml con dependencias (Flask==3.0.*, SQLAlchemy==2.0.*, marshmallow==3.*, PyJWT, boto3, redis, elasticsearch)
- [ ] CA-02: Repositorio proj-front-marketplace creado con Angular 18 standalone, Tailwind CSS v4, y estructura features/core/shared con angular.json configurado
- [ ] CA-03: Docker Compose levanta todos los servicios (backend Flask :5000, frontend Angular :4200, PostgreSQL 15 :5432, Redis :6379, Elasticsearch :9200) con un solo comando docker-compose up
- [ ] CA-04: Pre-commit hooks configurados: backend (black, isort, flake8, mypy) y frontend (eslint, prettier, stylelint)
- [ ] CA-05: Archivo .env.example documentado con todas las variables de entorno necesarias: DATABASE_URL, REDIS_URL, ELASTICSEARCH_URL, AWS_REGION, COGNITO_USER_POOL_ID, S3_BUCKET
- [ ] CA-06: Makefile con comandos: make setup, make run, make test, make lint, make migrate para backend; npm scripts equivalentes para frontend
- [ ] CA-07: .gitignore completo para Python (venv, __pycache__, .env) y Angular (node_modules, dist, .angular/cache) con proteccion contra secrets
- [ ] CA-08: README.md en cada repo con instrucciones de setup local paso a paso, arquitectura overview, y convenciones de codigo
- [ ] CA-09: Volumenes Docker configurados para hot-reload en desarrollo (codigo fuente montado, no copiado)
- [ ] CA-10: Health check endpoints en Docker Compose con dependencias correctas (backend espera a PostgreSQL y Redis)
- [ ] CA-11: Base de datos PostgreSQL inicializada con schema base y usuario de aplicacion con permisos minimos
- [ ] CA-12: Network Docker con subnet dedicada y nombres de servicio resolvibles (db, redis, elasticsearch, backend, frontend)

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Python 3.12+ para backend
- Node 20 LTS para frontend
- PostgreSQL 15 con extensiones: uuid-ossp, pg_trgm
- Redis 7.x para cache y sessions
- Elasticsearch 8.x para busqueda full-text

## Dependencias
- Ninguna (primer issue a implementar)

## Epica Padre
[MKT-EP-001] Plataforma Base, Arquitectura & Setup Inicial
ISSUE_EOF
)"
echo "  Created: [MKT-INF-001]"
sleep 2

# ─── MKT-BE-001 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-001] API Base Flask con Arquitectura Hexagonal" \
  --label "user-story,backend,priority-critical,sprint-1" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar la aplicacion Flask 3.0 base con arquitectura hexagonal completa, incluyendo SQLAlchemy 2.0 async, Marshmallow, JWT middleware, structured logging, CORS, y error handling global. Foundation sobre la que se construiran todos los endpoints.

## Contexto Tecnico
La API sigue estrictamente el patron hexagonal (ports and adapters). Flujo: Request -> API Route -> Marshmallow Schema (validate) -> Use Case -> Domain Service -> Port (ABC) -> Adapter (SQLAlchemy) -> DB.

### Stack:
- Flask 3.0 con blueprints
- SQLAlchemy 2.0 async session (asyncpg driver)
- Marshmallow 3.x
- PyJWT + AWS Cognito token validation
- structlog con JSON output
- OpenAPI 3.0 via Flask-RESTX o flasgger

### Modelo base de dominio:
```python
class Vehicle:
    id: UUID
    external_id: str       # ID de scrapper_nacional
    brand: str
    model: str
    year: int
    price: Decimal
    mileage: int
    transmission: str      # manual, automatic, cvt
    fuel_type: str         # gasoline, diesel, electric, hybrid
    color: str
    location: str
    source: str            # fuente de scrapping
    status: VehicleStatus  # active, sold, reserved, inactive
    images: List[VehicleImage]
    created_at: datetime
    updated_at: datetime
```

## Criterios de Aceptacion
- [ ] CA-01: Flask app factory pattern implementado con create_app() que acepta configuracion por environment (dev, staging, prod) y registra blueprints, middleware, y extensions
- [ ] CA-02: Health check GET /api/health retorna 200 con version, uptime, y estado de conexiones (db, redis, elasticsearch) en menos de 200ms
- [ ] CA-03: SQLAlchemy 2.0 configurado con async sessions, connection pooling (pool_size=20, max_overflow=10), y Alembic migrations con flask db upgrade
- [ ] CA-04: Marshmallow schemas base con validacion automatica, error messages en espanol, campos nested, paginacion meta, y HATEOAS links
- [ ] CA-05: JWT middleware que valida tokens de AWS Cognito (RS256, issuer, audience, expiration), extrae claims, inyecta current_user en contexto Flask
- [ ] CA-06: CORS con whitelist de origins configurable, headers permitidos (Authorization, Content-Type, X-Request-ID), y metodos (GET, POST, PUT, PATCH, DELETE)
- [ ] CA-07: Error handling global con excepciones de dominio mapeadas: DomainNotFound->404, DomainValidation->422, DomainConflict->409, DomainUnauthorized->401, DomainForbidden->403; formato consistente {error: {code, message, details}}
- [ ] CA-08: Structured logging con structlog en JSON: timestamp, level, request_id, user_id, method, path, status_code, duration_ms, correlation_id
- [ ] CA-09: Rate limiting con Flask-Limiter y Redis: 100 req/min publicos, 30 req/min auth, 1000 req/min autenticados; headers X-RateLimit-Limit/Remaining/Reset
- [ ] CA-10: Request/Response logging middleware que registra method, path, query params, body sanitizado, response status, duracion
- [ ] CA-11: Dependency injection container para inyectar adapters en use cases, facilitando testing con mocks
- [ ] CA-12: OpenAPI 3.0 auto-generada desde Marshmallow schemas, disponible en /api/docs con Swagger UI interactivo con JWT auth

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- flask.g para request context (user, request_id)
- Custom Flask CLI commands para tareas admin
- Gunicorn con workers async para produccion
- @dataclass para DTOs internos, Marshmallow solo en API boundary

## Dependencias
- [MKT-INF-001] Setup del Repositorio y Monorepo Structure

## Epica Padre
[MKT-EP-001] Plataforma Base, Arquitectura & Setup Inicial
ISSUE_EOF
)"
echo "  Created: [MKT-BE-001]"
sleep 2

# ─── MKT-FE-001 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-001] Angular 18 Project Setup con Design System Premium" \
  --label "user-story,frontend,priority-critical,sprint-1" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Configurar Angular 18 con standalone components, Tailwind CSS v4, y design system premium de marketplace vehicular. Incluye design tokens, tipografia scale, color system con dark mode, grid 8px, y componentes base (buttons, inputs, cards, modals, toasts, badges, avatars).

## Contexto Tecnico
Frontend premium estilo Carvana/Kavak. Design system consistente, accesible (WCAG 2.1 AA), responsive-first. Angular signals para state management.

### Design Tokens:
```typescript
export const colors = {
  primary: { 50: '#E3F2FD', 500: '#2196F3', 900: '#0D47A1' },
  secondary: { 50: '#FFF3E0', 500: '#FF9800', 900: '#E65100' },
  success: { 500: '#4CAF50' },
  warning: { 500: '#FF9800' },
  error: { 500: '#F44336' },
  neutral: { 50: '#FAFAFA', 900: '#212121' },
};

export const typography = {
  'display-lg': { size: '3.5rem', weight: 700, lineHeight: 1.1 },
  'heading-lg': { size: '2rem', weight: 600, lineHeight: 1.25 },
  'body-md': { size: '1rem', weight: 400, lineHeight: 1.6 },
  'caption': { size: '0.75rem', weight: 400, lineHeight: 1.4 },
};
```

Breakpoints: Mobile 0-639px, Tablet 640-1023px, Desktop 1024-1279px, Wide 1280px+

## Criterios de Aceptacion
- [ ] CA-01: Angular 18 con standalone components, strict mode; ng serve levanta sin errores en localhost:4200
- [ ] CA-02: Tailwind CSS v4 integrado con design tokens custom (colores, spacing 8px, typography scale, breakpoints, border-radius, shadows) en tailwind.config.ts con purge para produccion
- [ ] CA-03: Design tokens como CSS custom properties en :root y [data-theme="dark"] con toggle dark mode funcional que persiste en localStorage y respeta prefers-color-scheme
- [ ] CA-04: Componente Button con variantes (primary, secondary, outline, ghost, danger), tamanos (sm, md, lg), estados (default, hover, active, disabled, loading con spinner), iconos opcionales usando signals
- [ ] CA-05: Componente Input con tipos (text, email, password toggle, number, search), estados (default, focus, error, disabled), label flotante, helper text, error message, prefix/suffix icons
- [ ] CA-06: Componente Card con variantes (default, elevated, outlined, interactive hover), slots (header, media, body, footer, actions), badge overlay (nuevo, oferta, vendido)
- [ ] CA-07: Componente Modal/Dialog con backdrop blur, animacion enter/exit, tamanos (sm, md, lg, fullscreen), close Escape/click outside, focus trap, stacking
- [ ] CA-08: Componente Toast con tipos (success, warning, error, info), posicion configurable, auto-dismiss, dismiss manual, stack hasta 5, animaciones slide
- [ ] CA-09: Layout system: AppShell (header+sidebar+content+footer), Header (logo, nav, search, user menu), Sidebar (collapsible), Footer; responsive con hamburger mobile
- [ ] CA-10: HTTP interceptors: AuthInterceptor (JWT), ErrorInterceptor (toast global), LoadingInterceptor (loader), CacheInterceptor (GET cache)
- [ ] CA-11: Routing con lazy loading por feature, AuthGuard, RoleGuard, resolvers, breadcrumbs automaticos desde route data
- [ ] CA-12: State management con signals: AuthStore (user, token, isAuthenticated), UIStore (theme, sidebar, loading, toasts) con persistencia localStorage
- [ ] CA-13: Storybook configurado con stories para cada componente del design system

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- @angular/cdk para a11y (FocusTrap, LiveAnnouncer)
- Fonts: Inter body, Montserrat/Poppins headings
- Iconos: Lucide o Heroicons (tree-shakeable)
- provideHttpClient(withInterceptors([...])) para standalone

## Dependencias
- [MKT-INF-001] Setup del Repositorio y Monorepo Structure

## Epica Padre
[MKT-EP-001] Plataforma Base, Arquitectura & Setup Inicial
ISSUE_EOF
)"
echo "  Created: [MKT-FE-001]"
sleep 2

# ─── MKT-INF-002 ───────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-INF-002] Pipeline CI/CD con GitHub Actions" \
  --label "user-story,infrastructure,priority-critical,sprint-1" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Pipelines CI/CD completos con GitHub Actions para backend y frontend: build, test, lint, security scanning, Docker image build, push a ECR, deploy a ECS Fargate (dev/staging/prod).

## Contexto Tecnico
Cada repo tiene workflows CI (PRs) y CD (merge). Deploy a staging es automatico en merge a develop; produccion requiere approval manual. Imagenes Docker en ECR, deploy en ECS Fargate con rolling updates.

## Criterios de Aceptacion
- [ ] CA-01: CI backend en cada PR: lint (black, isort, flake8, mypy), tests (pytest --cov threshold 80%), security (bandit, safety), Docker build test; PR bloqueado si falla
- [ ] CA-02: CI frontend en cada PR: lint (eslint, prettier, stylelint), tests (ng test --code-coverage threshold 80%), build prod (ng build --configuration=production), Lighthouse CI (perf>80, a11y>90)
- [ ] CA-03: CD backend en push develop: build Docker con tag git-sha, push ECR, actualizar ECS task definition, deploy staging, smoke tests
- [ ] CA-04: CD frontend en push develop: build Angular prod, Docker nginx, push ECR, deploy staging, invalidar CloudFront cache
- [ ] CA-05: Deploy produccion (push main) requiere manual approval, environment protection rules, mismas steps contra recursos prod
- [ ] CA-06: GitHub Actions secrets por environment: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, ECR_REGISTRY, ECS_CLUSTER, DATABASE_URL, REDIS_URL
- [ ] CA-07: Matrix strategy: backend Python 3.12 + PostgreSQL 15 + Redis 7; frontend Node 20 + Chrome headless
- [ ] CA-08: Cache de dependencias: pip (pyproject.toml hash), npm (package-lock.json hash), Docker layer caching
- [ ] CA-09: Notificaciones Slack en deploy exitoso/fallido con commit, autor, environment, link workflow; badge status en README
- [ ] CA-10: Branch protection: require PR reviews (1+), require status checks, require up-to-date branch, no force push main/develop
- [ ] CA-11: Rollback automatico si smoke tests fallan post-deploy: revertir a task definition anterior y notificar
- [ ] CA-12: Coverage reports como artifacts y comment en PR

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- OIDC para AWS auth si posible
- Concurrency: cancelar runs previos en misma branch
- Timeout 15min CI, 30min CD
- Considerar Dependabot/Renovate

## Dependencias
- [MKT-INF-001] Setup del Repositorio
- Cuenta AWS con ECR repositories

## Epica Padre
[MKT-EP-001] Plataforma Base, Arquitectura & Setup Inicial
ISSUE_EOF
)"
echo "  Created: [MKT-INF-002]"
sleep 2

# ─── MKT-INF-003 ───────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-INF-003] Infraestructura AWS con Terraform" \
  --label "user-story,infrastructure,priority-critical,sprint-1" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Toda la infraestructura AWS del marketplace con Terraform: VPC, subnets, ECS Fargate, RDS PostgreSQL, ElastiCache Redis, S3, CloudFront, Cognito, SQS, SNS, CloudWatch.

## Contexto Tecnico
Infraestructura reproducible, versionada, parametrizada por environment. State en S3 con DynamoDB locking.

### Arquitectura:
```
Internet -> Route53 -> CloudFront -> ALB -> ECS Fargate Cluster
  Backend Service (Flask, 2-10 tasks auto-scaling)
  Frontend Service (Nginx+Angular, 2-5 tasks)
  -> RDS PostgreSQL 15 (Multi-AZ)
  -> ElastiCache Redis 7
  -> OpenSearch / Elasticsearch
  -> S3 (images, documents)
  -> SQS (async queues) / SNS (notifications)
  -> Cognito (auth)
```

## Criterios de Aceptacion
- [ ] CA-01: VPC con 3 AZs, subnets publicas (ALB, NAT), privadas (ECS, RDS, ElastiCache), aisladas (RDS), flow logs, CIDR no conflictivos
- [ ] CA-02: ECS Fargate: backend (CPU 512, Mem 1024, desired 2, max 10), frontend (CPU 256, Mem 512, desired 2, max 5), auto-scaling CPU>70%
- [ ] CA-03: RDS PostgreSQL 15 Multi-AZ, db.t3.medium (dev: t3.micro single-AZ), backups 35 dias, encryption KMS, security group solo ECS
- [ ] CA-04: ElastiCache Redis 7 cluster mode disabled, cache.t3.medium (dev: t3.micro), encryption transit+rest, automatic failover
- [ ] CA-05: S3 buckets: vehicles-images (public via CloudFront), documents (private), backups (lifecycle 90d), versioning, SSE-S3, CORS
- [ ] CA-06: CloudFront: origins S3 + ALB (/api/*), custom domain, ACM cert, WAF basico (rate limit, geo), cache behaviors optimizados
- [ ] CA-07: Cognito User Pool: password policy (8+ chars, upper, lower, number, symbol), email verification, custom attrs (role, phone), OAuth2 flows
- [ ] CA-08: SQS: vehicle-sync, valuation-requests, notification-events, purchase-events; cada una con DLQ, retention 14d, visibility timeout
- [ ] CA-09: SNS: vehicle-price-change, vehicle-sold, purchase-status-change, user-notifications; subscriptions a SQS y Lambda/SES
- [ ] CA-10: CloudWatch: log groups por servicio (30d dev, 90d prod), metricas custom (latency, error rate), alarmas (CPU>80%, 5xx>1%), dashboard
- [ ] CA-11: Terraform state en S3 + DynamoDB locking, modulos por servicio, encryption, versioning
- [ ] CA-12: IAM least privilege: ECS task role (S3, SQS, SNS, Cognito, Secrets Manager), execution role (ECR, CloudWatch), CI/CD role (ECR, ECS)
- [ ] CA-13: Variables parametrizadas con tfvars (dev, staging, prod), outputs para CI/CD (ALB DNS, ECR URLs, RDS endpoint, Redis endpoint)

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Terraform >= 1.6 con backend S3
- Tagging: Project=marketplace, Environment=dev/staging/prod, ManagedBy=terraform
- terraform-docs para auto-documentacion

## Dependencias
- Cuenta AWS con permisos admin
- Dominio DNS
- [MKT-INF-001] Setup del Repositorio

## Epica Padre
[MKT-EP-001] Plataforma Base, Arquitectura & Setup Inicial
ISSUE_EOF
)"
echo "  Created: [MKT-INF-003]"
sleep 2

###############################################################################
# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 2: [MKT-EP-002] Sistema de Autenticacion, Registro & Perfiles
# ═══════════════════════════════════════════════════════════════════════════════
###############################################################################
echo ""
echo ">>> EPIC 2: Sistema de Autenticacion, Registro & Perfiles de Usuario"

gh issue create --repo "$REPO" \
  --title "[MKT-EP-002] Sistema de Autenticacion, Registro & Perfiles de Usuario" \
  --label "epic,priority-critical,sprint-2" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Sistema completo de autenticacion con AWS Cognito, registro de usuarios (compradores, vendedores, admin), gestion de perfiles, social login, MFA, y dashboard de usuario.

## Contexto Tecnico
- Auth: AWS Cognito User Pools con JWT tokens
- Social Login: Google OAuth 2.0, Apple Sign-In
- Roles: buyer, seller, dealer, admin
- Backend: Flask endpoints + Cognito SDK
- Frontend: Angular auth flows con guards y interceptors

## Criterios de Aceptacion
- [ ] CA-01: Registro funcional con email/password y social login (Google, Apple)
- [ ] CA-02: Login/logout con JWT refresh tokens
- [ ] CA-03: Roles y permisos implementados (buyer, seller, dealer, admin)
- [ ] CA-04: Email verification y password reset flows completos
- [ ] CA-05: Perfil de usuario CRUD con avatar upload
- [ ] CA-06: Dashboard de usuario con historial y favoritos
- [ ] CA-07: MFA opcional configurado en Cognito
- [ ] CA-08: Rate limiting en auth endpoints
- [ ] CA-09: Frontend: multi-step registro, login, forgot password screens
- [ ] CA-10: Session management y token refresh automatico

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## User Stories Contenidas
- [MKT-BE-002] API de Registro de Usuarios
- [MKT-BE-003] API de Autenticacion JWT + Cognito
- [MKT-FE-002] Flujo de Registro Multi-Step
- [MKT-FE-003] Pantallas de Login y Recuperacion de Contrasena
- [MKT-BE-004] API de Gestion de Perfiles de Usuario
- [MKT-FE-004] Dashboard de Perfil de Usuario

## Dependencias
- [MKT-EP-001] Plataforma Base completada
ISSUE_EOF
)"
echo "  Created: [MKT-EP-002]"
sleep 2

# ─── MKT-BE-002 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-002] API de Registro de Usuarios" \
  --label "user-story,backend,priority-critical,sprint-2" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
API de registro de usuarios con email/password, Google OAuth, Apple Sign-In. Soporte para roles (buyer, seller, dealer, admin), email verification, password reset, y creacion de perfil basico.

## Contexto Tecnico
Registro via AWS Cognito. Backend actua como intermediario: valida datos, crea usuario en Cognito, crea perfil en DB local, y emite JWT. Cognito maneja password hashing, email verification, y MFA.

### Endpoints:
```
POST /api/auth/register          - Registro email/password
POST /api/auth/register/google   - Registro con Google OAuth
POST /api/auth/register/apple    - Registro con Apple Sign-In
POST /api/auth/verify-email      - Verificar email con codigo
POST /api/auth/resend-verification - Reenviar codigo verificacion
POST /api/auth/forgot-password   - Solicitar reset password
POST /api/auth/reset-password    - Confirmar reset con codigo
```

### Modelo User:
```python
class User:
    id: UUID
    cognito_sub: str          # Cognito user sub
    email: str
    role: UserRole            # buyer, seller, dealer, admin
    first_name: str
    last_name: str
    phone: Optional[str]
    location: Optional[str]
    avatar_url: Optional[str]
    preferences: Dict         # vehicle preferences JSON
    is_verified: bool
    is_active: bool
    created_at: datetime
    updated_at: datetime
```

## Criterios de Aceptacion
- [ ] CA-01: POST /api/auth/register acepta {email, password, first_name, last_name, role} y crea usuario en Cognito + perfil en DB; retorna 201 con {user_id, message: "verification_email_sent"}
- [ ] CA-02: Validacion de password: minimo 8 caracteres, 1 mayuscula, 1 minuscula, 1 numero, 1 caracter especial; retorna 422 con detalles si no cumple
- [ ] CA-03: POST /api/auth/register/google acepta {google_token} y verifica con Google OAuth API, crea/vincula usuario en Cognito via federated identity, crea perfil en DB
- [ ] CA-04: POST /api/auth/register/apple acepta {apple_token, apple_user} con validacion del identity token de Apple, crea usuario en Cognito
- [ ] CA-05: POST /api/auth/verify-email acepta {email, code} y confirma en Cognito; retorna 200 y activa el usuario; codigo expira en 24h
- [ ] CA-06: POST /api/auth/forgot-password envia codigo de reset via Cognito a email registrado; retorna 200 siempre (no revela si email existe)
- [ ] CA-07: POST /api/auth/reset-password acepta {email, code, new_password} y actualiza en Cognito; invalida todas las sessions activas
- [ ] CA-08: Roles asignados como custom attribute en Cognito y columna en DB; buyer es default; seller/dealer requiere verificacion adicional posterior
- [ ] CA-09: Email duplicado retorna 409 Conflict con mensaje claro; phone duplicado es warning no bloqueante
- [ ] CA-10: Rate limiting: maximo 5 registros por IP por hora, 3 intentos de verificacion por email por hora, 3 forgot-password por email por hora
- [ ] CA-11: Eventos de registro publicados a SNS topic user-registered para triggers downstream (email bienvenida, analytics)
- [ ] CA-12: Logging estructurado de cada registro: timestamp, email (hashed), role, source (email/google/apple), IP (anonimizada), success/failure reason

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Usar boto3 cognito-idp client para operaciones Cognito
- Manejar CognitoIdentityProviderException para errores de Cognito
- No almacenar passwords en DB local (solo Cognito)
- Tests con moto (mock AWS) para Cognito

## Dependencias
- [MKT-BE-001] API Base Flask
- [MKT-INF-003] Cognito User Pool creado

## Epica Padre
[MKT-EP-002] Sistema de Autenticacion, Registro & Perfiles de Usuario
ISSUE_EOF
)"
echo "  Created: [MKT-BE-002]"
sleep 2

# ─── MKT-BE-003 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-003] API de Autenticacion JWT + Cognito" \
  --label "user-story,backend,priority-critical,sprint-2" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Login/logout, refresh tokens, MFA opcional, session management, y rate limiting en auth endpoints. JWT tokens emitidos por Cognito y validados en cada request.

## Contexto Tecnico
### Endpoints:
```
POST /api/auth/login             - Login email/password
POST /api/auth/login/google      - Login con Google
POST /api/auth/login/apple       - Login con Apple
POST /api/auth/refresh           - Refresh access token
POST /api/auth/logout            - Logout (invalidar refresh token)
GET  /api/auth/me                - Current user info
POST /api/auth/mfa/setup         - Iniciar setup MFA
POST /api/auth/mfa/verify        - Verificar MFA code
POST /api/auth/mfa/disable       - Desactivar MFA
```

### Token Structure:
- Access Token: 1h expiry, contiene user_id, email, role, permissions
- Refresh Token: 30d expiry, stored en HttpOnly cookie
- ID Token: user profile claims

## Criterios de Aceptacion
- [ ] CA-01: POST /api/auth/login acepta {email, password}, autentica con Cognito InitiateAuth, retorna {access_token, refresh_token, id_token, expires_in, user} con access_token en body y refresh_token en HttpOnly secure cookie
- [ ] CA-02: POST /api/auth/refresh acepta refresh_token (de cookie o body), llama Cognito con REFRESH_TOKEN_AUTH, retorna nuevo access_token sin requerir login
- [ ] CA-03: POST /api/auth/logout invalida refresh token en Cognito (GlobalSignOut), limpia cookie, retorna 204; funciona incluso con access_token expirado si refresh_token es valido
- [ ] CA-04: GET /api/auth/me retorna perfil del usuario autenticado con campos: id, email, role, first_name, last_name, avatar_url, preferences, created_at; requiere access_token valido
- [ ] CA-05: MFA setup flow: POST /mfa/setup retorna QR code (TOTP), POST /mfa/verify acepta code y activa MFA; login subsecuente requiere MFA challenge con Cognito SOFTWARE_TOKEN_MFA
- [ ] CA-06: Login con credenciales incorrectas retorna 401 con mensaje generico "Invalid credentials" (no revelar si email existe); despues de 5 intentos fallidos, Cognito bloquea temporalmente la cuenta
- [ ] CA-07: Token validation middleware verifica: signature (RS256 con JWKS de Cognito), issuer (Cognito user pool), expiration, audience (app client id); cachea JWKS por 1h en Redis
- [ ] CA-08: Rate limiting auth endpoints: 10 login attempts/IP/min, 5 refresh/user/min, 3 mfa-verify/user/min; responde 429 con Retry-After header
- [ ] CA-09: Session tracking en DB: device info (User-Agent parsed), IP (geo-located), last_active, created_at; endpoint GET /api/auth/sessions lista sessions activas, DELETE revoca session especifica
- [ ] CA-10: Social login (Google, Apple) redirige a Cognito hosted UI o valida token directamente; unifica cuentas si email ya existe con diferente provider
- [ ] CA-11: Decoradores de autorizacion: @require_auth (cualquier usuario autenticado), @require_role('admin'), @require_permission('vehicles:write') aplicables a cualquier endpoint
- [ ] CA-12: Audit log de auth events: login_success, login_failure, logout, password_change, mfa_enabled, mfa_disabled con timestamp, user_id, IP, device; stored en tabla auth_events

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- JWKS endpoint de Cognito: https://cognito-idp.{region}.amazonaws.com/{userPoolId}/.well-known/jwks.json
- Usar PyJWT con algorithms=["RS256"] para validar tokens
- Refresh token rotation no soportado nativamente por Cognito; implementar deteccion de reuse

## Dependencias
- [MKT-BE-002] API de Registro de Usuarios
- [MKT-INF-003] Cognito configurado

## Epica Padre
[MKT-EP-002] Sistema de Autenticacion, Registro & Perfiles de Usuario
ISSUE_EOF
)"
echo "  Created: [MKT-BE-003]"
sleep 2

# ─── MKT-FE-002 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-002] Flujo de Registro Multi-Step" \
  --label "user-story,frontend,priority-high,sprint-2" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Flujo de registro multi-step con 3 pasos: 1) Email/password o social login, 2) Datos personales, 3) Preferencias vehiculares. Validacion en tiempo real, progress indicator, y mobile-first design.

## Contexto Tecnico
Standalone Angular component con reactive forms, step navigation, y llamadas al backend API. Debe ser visualmente atractivo y minimizar friccion para maximizar conversion.

### Steps:
- Step 1: Metodo de registro (email/password con strength meter, o Google/Apple buttons)
- Step 2: Datos personales (nombre, apellido, telefono con mask, ubicacion con autocomplete)
- Step 3: Preferencias (tipo vehiculo checkbox, rango presupuesto slider, marcas favoritas multiselect)

## Criterios de Aceptacion
- [ ] CA-01: Step 1 muestra formulario email/password con validacion en tiempo real (email format, password strength meter con requisitos visibles) y botones de Google/Apple social login prominentes con divider "o registrate con email"
- [ ] CA-02: Password strength meter visual muestra: weak (rojo), fair (naranja), good (amarillo), strong (verde) con checklist de requisitos (8+ chars, uppercase, lowercase, number, special) que se marcan en verde conforme se cumplen
- [ ] CA-03: Step 2 muestra campos: nombre (required), apellido (required), telefono (opcional, con mask +52 formato mexicano), ubicacion (opcional, con autocomplete de ciudades/estados de Mexico)
- [ ] CA-04: Step 3 muestra preferencias: tipo vehiculo (sedan, SUV, pickup, hatchback, coupe, van - checkboxes con iconos), rango presupuesto (dual range slider min-max con formateo MXN), marcas favoritas (multiselect con logos de marcas populares)
- [ ] CA-05: Progress indicator horizontal muestra 3 steps con iconos, labels, estado actual (active, completed, pending), y permite navegar a steps completados clickeando
- [ ] CA-06: Navegacion: boton "Siguiente" (disabled si validacion no pasa), boton "Anterior" (desde step 2 y 3), boton "Omitir" en step 3 (preferencias opcionales)
- [ ] CA-07: Social login (Google/Apple) completa step 1 automaticamente, pre-llena datos disponibles del provider (nombre, email, avatar) en step 2
- [ ] CA-08: Validacion en tiempo real de email disponibilidad con debounce 500ms llamando al backend; muestra check verde si disponible, error rojo si ya registrado
- [ ] CA-09: Al completar step 3 (o omitir), llama POST /api/auth/register, muestra loading state en boton, y redirige a pantalla de "revisa tu email" con animacion de sobre
- [ ] CA-10: Manejo de errores: errores de red muestran toast con retry, errores de validacion backend se muestran inline en campo correspondiente, errores 409 (email existe) sugieren login con link
- [ ] CA-11: Responsive: mobile muestra steps como cards verticales con scroll, tablet/desktop muestra wizard horizontal; formularios full-width en mobile, max-width 500px en desktop
- [ ] CA-12: Datos del formulario persisten en sessionStorage entre steps (no se pierden si navega atras); se limpian al completar registro o cerrar tab

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Usar Angular reactive forms con FormGroup per step
- Animaciones de transicion entre steps con Angular animations
- Google Sign-In SDK y Apple Sign-In JS para social login
- Analytic events: registration_started, step_completed, registration_completed, registration_abandoned

## Dependencias
- [MKT-FE-001] Angular Project Setup
- [MKT-BE-002] API de Registro

## Epica Padre
[MKT-EP-002] Sistema de Autenticacion, Registro & Perfiles de Usuario
ISSUE_EOF
)"
echo "  Created: [MKT-FE-002]"
sleep 2

# ─── MKT-FE-003 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-003] Pantallas de Login y Recuperacion de Contrasena" \
  --label "user-story,frontend,priority-high,sprint-2" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Pantallas de login con email/password y social login, flujo de forgot password, y remember me. UI premium y accesible.

## Contexto Tecnico
Login standalone component. Forgot password es flujo de 2 pantallas: solicitar reset + ingresar codigo + nueva password.

## Criterios de Aceptacion
- [ ] CA-01: Pantalla login con layout split: izquierda formulario, derecha imagen hero vehiculo con overlay gradient y tagline del marketplace; mobile solo muestra formulario
- [ ] CA-02: Formulario login: email input con validacion, password input con toggle visibility, checkbox "Recordarme", link "Olvidaste tu contrasena?", boton "Iniciar Sesion" con loading state
- [ ] CA-03: Botones social login: "Continuar con Google" y "Continuar con Apple" con iconos oficiales, separados del form con divider "o inicia sesion con"
- [ ] CA-04: Validacion: email required + format, password required + min 8 chars; errores inline bajo cada campo; boton disabled hasta formulario valido
- [ ] CA-05: Al submit, llama POST /api/auth/login; success redirige a pagina anterior o home; error 401 muestra "Credenciales incorrectas" inline; error 429 muestra "Demasiados intentos, espera X minutos"
- [ ] CA-06: "Recordarme" persiste email en localStorage y pre-llena al volver; si no marcado, limpia al cerrar browser
- [ ] CA-07: Forgot password step 1: input email + boton "Enviar codigo"; llama POST /api/auth/forgot-password; muestra "Si el email existe, recibiras un codigo" siempre
- [ ] CA-08: Forgot password step 2: input codigo (6 digitos con auto-advance entre campos), input nueva password con strength meter, boton "Restablecer"; llama POST /api/auth/reset-password
- [ ] CA-09: Link "No tienes cuenta? Registrate" navega al flujo de registro; link "Volver al login" desde forgot password
- [ ] CA-10: Accesibilidad: todos los inputs con labels asociados, focus visible, navegacion con Tab completa, aria-live para mensajes de error, contrast ratio WCAG AA
- [ ] CA-11: Animaciones: fade-in al cargar, shake en error de credenciales, transicion suave entre login y forgot password
- [ ] CA-12: Redirect post-login: si habia URL guardada (returnUrl query param), redirigir alli; si no, ir a home; si user es admin, ir a /admin/dashboard

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Usar AuthStore signal para guardar token post-login
- HttpOnly cookie para refresh token (set by backend)
- Auto-redirect si ya autenticado (AuthGuard inverso)

## Dependencias
- [MKT-FE-001] Angular Project Setup
- [MKT-BE-003] API de Autenticacion

## Epica Padre
[MKT-EP-002] Sistema de Autenticacion, Registro & Perfiles de Usuario
ISSUE_EOF
)"
echo "  Created: [MKT-FE-003]"
sleep 2

# ─── MKT-BE-004 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-004] API de Gestion de Perfiles de Usuario" \
  --label "user-story,backend,priority-high,sprint-2" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
CRUD de perfil de usuario, avatar upload a S3, preferencias de notificacion, historial de actividad, y gestion de favoritos/wishlist.

## Contexto Tecnico
### Endpoints:
```
GET    /api/users/me/profile           - Obtener perfil completo
PUT    /api/users/me/profile           - Actualizar perfil
POST   /api/users/me/avatar            - Upload avatar a S3
DELETE /api/users/me/avatar            - Eliminar avatar
GET    /api/users/me/preferences       - Obtener preferencias
PUT    /api/users/me/preferences       - Actualizar preferencias
GET    /api/users/me/notifications     - Configuracion notificaciones
PUT    /api/users/me/notifications     - Actualizar config notificaciones
GET    /api/users/me/activity          - Historial de actividad
GET    /api/users/me/favorites         - Listar favoritos
POST   /api/users/me/favorites/:vehicleId - Agregar favorito
DELETE /api/users/me/favorites/:vehicleId - Eliminar favorito
```

### Modelo UserProfile extendido:
```python
class UserProfile:
    user_id: UUID
    bio: Optional[str]
    date_of_birth: Optional[date]
    address: Optional[Address]
    notification_prefs: NotificationPreferences
    vehicle_prefs: VehiclePreferences
    search_history: List[SearchEntry]
    favorite_vehicles: List[UUID]  # vehicle IDs
```

## Criterios de Aceptacion
- [ ] CA-01: GET /api/users/me/profile retorna perfil completo con datos personales, preferencias, conteo de favoritos, fecha de registro; solo accesible con JWT valido
- [ ] CA-02: PUT /api/users/me/profile acepta actualizacion parcial (PATCH semantics) de campos: first_name, last_name, phone, location, bio, date_of_birth; valida formato de cada campo
- [ ] CA-03: POST /api/users/me/avatar acepta multipart/form-data con imagen (max 5MB, formatos jpg/png/webp), redimensiona a 200x200 y 50x50, sube a S3 con key users/{id}/avatar.{ext}, retorna URL de CDN
- [ ] CA-04: Preferencias de notificacion configurables: email_new_vehicles (bool), email_price_changes (bool), email_promotions (bool), push_enabled (bool), sms_enabled (bool); defaults true para new_vehicles y price_changes
- [ ] CA-05: Historial de actividad registra: vehiculos vistos, busquedas realizadas, favoritos agregados/removidos, compras iniciadas; GET /activity retorna ultimos 50 con paginacion cursor
- [ ] CA-06: Favoritos: POST agrega vehiculo a wishlist (max 100), DELETE remueve, GET lista con info basica del vehiculo (brand, model, year, price, image); retorna 404 si vehiculo no existe, 409 si ya es favorito
- [ ] CA-07: Cuando precio de vehiculo favorito cambia, se publica evento a SNS vehicle-price-change con {user_id, vehicle_id, old_price, new_price} para notificacion
- [ ] CA-08: Validacion de phone: formato E.164, verificacion via SMS code (Cognito VerifyUserAttribute); phone es opcional pero si se provee debe verificarse
- [ ] CA-09: Endpoint GET /api/users/me/stats retorna estadisticas: total_favorites, total_searches, total_views, member_since, profile_completeness_percentage
- [ ] CA-10: Soft delete de cuenta: DELETE /api/users/me desactiva usuario en Cognito y DB (is_active=false), anonimiza datos personales despues de 30 dias via cron job
- [ ] CA-11: Upload avatar genera presigned URL de S3 para upload directo desde frontend (mas eficiente); endpoint retorna {upload_url, fields, cdn_url}
- [ ] CA-12: Cache de perfil en Redis (TTL 5 min) invalidado en cada PUT; favoritos cacheados con TTL 1 min

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Pillow para image processing (resize, optimize)
- S3 presigned URLs expiran en 15 min
- Activity log es append-only, considerar tabla particionada por fecha
- Usar Marshmallow schema para validar preferences JSON

## Dependencias
- [MKT-BE-003] API de Autenticacion
- [MKT-INF-003] S3 bucket creado

## Epica Padre
[MKT-EP-002] Sistema de Autenticacion, Registro & Perfiles de Usuario
ISSUE_EOF
)"
echo "  Created: [MKT-BE-004]"
sleep 2

# ─── MKT-FE-004 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-004] Dashboard de Perfil de Usuario" \
  --label "user-story,frontend,priority-high,sprint-2" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Dashboard de usuario con vista/edicion de perfil, cambio de contrasena, configuracion de notificaciones, historial de busquedas y favoritos, y estadisticas de actividad.

## Contexto Tecnico
Layout con sidebar navigation (perfil, seguridad, notificaciones, favoritos, actividad) y content area. Angular standalone components con reactive forms y signals.

## Criterios de Aceptacion
- [ ] CA-01: Sidebar navigation con secciones: Mi Perfil (icono user), Seguridad (icono shield), Notificaciones (icono bell), Mis Favoritos (icono heart con badge count), Actividad (icono clock); item activo resaltado; mobile: tabs horizontales
- [ ] CA-02: Seccion Mi Perfil: avatar con overlay "Cambiar foto" al hover, upload drag-and-drop o click, crop modal; formulario editable con nombre, apellido, telefono, ubicacion, bio; boton guardar con loading
- [ ] CA-03: Seccion Seguridad: cambiar contrasena (current, new, confirm con strength meter), activar/desactivar MFA con QR code modal, lista de sesiones activas con "Cerrar sesion" por dispositivo
- [ ] CA-04: Seccion Notificaciones: toggles agrupados por categoria (vehiculos nuevos, cambios de precio, promociones, actualizaciones del sistema) por canal (email, push, SMS); guardar preferencias con feedback toast
- [ ] CA-05: Seccion Favoritos: grid de vehicle cards favoritas con filtros (marca, precio, estado), ordenar por fecha agregado o precio, boton remover favorito con confirmacion; empty state con CTA "Explorar vehiculos"
- [ ] CA-06: Seccion Actividad: timeline de acciones recientes (vehiculos vistos, busquedas, favoritos) con icono, descripcion, timestamp relativo ("hace 2 horas"); lazy loading al scroll
- [ ] CA-07: Stats cards en header del dashboard: total favoritos, busquedas este mes, vehiculos vistos, miembro desde; con animacion de conteo al cargar
- [ ] CA-08: Avatar upload: preview inmediato pre-upload, progress bar durante upload, crop circular con zoom/pan, formatos aceptados (jpg, png, webp), max 5MB con validacion client-side
- [ ] CA-09: Formularios con validacion en tiempo real, dirty checking (confirmar si navega con cambios sin guardar), y autosave draft en sessionStorage
- [ ] CA-10: Responsive: mobile full-width con tabs top navigation, tablet sidebar collapsible, desktop sidebar fija 250px + content area
- [ ] CA-11: Profile completeness bar: porcentaje de completitud con suggestions de campos faltantes ("Agrega tu telefono para mayor seguridad")
- [ ] CA-12: Deep linking: cada seccion tiene URL unica (/profile, /profile/security, /profile/notifications, /profile/favorites, /profile/activity) para navegacion directa y sharing

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Usar Angular CDK drag-drop para avatar upload area
- Image crop: ngx-image-cropper o custom con canvas
- Skeleton loaders mientras carga datos del perfil
- Optimistic UI para toggle favoritos

## Dependencias
- [MKT-FE-001] Angular Project Setup
- [MKT-BE-004] API de Gestion de Perfiles

## Epica Padre
[MKT-EP-002] Sistema de Autenticacion, Registro & Perfiles de Usuario
ISSUE_EOF
)"
echo "  Created: [MKT-FE-004]"
sleep 2

###############################################################################
# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 3: [MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda
# ═══════════════════════════════════════════════════════════════════════════════
###############################################################################
echo ""
echo ">>> EPIC 3: Catalogo de Vehiculos & Motor de Busqueda"

gh issue create --repo "$REPO" \
  --title "[MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda" \
  --label "epic,priority-critical,sprint-3" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Catalogo completo de vehiculos con busqueda avanzada full-text (Elasticsearch), filtros dinamicos, carrusel de fotos, vista de detalle rica, comparacion side-by-side, e integracion con scrapper_nacional para datos de 18 fuentes.

## Contexto Tecnico
- 11,000+ vehiculos de 18 fuentes en scrapper_nacional DB
- Elasticsearch para busqueda y filtros faceted
- Redis para cache de listados y filtros
- S3 + CloudFront para imagenes de vehiculos
- Worker SQS para sync incremental desde scrapper_nacional
- ML recommendations para vehiculos similares (proj-back-ai-agents)

## Criterios de Aceptacion
- [ ] CA-01: Listado de vehiculos con paginacion performante (<200ms)
- [ ] CA-02: Busqueda full-text con autocompletado
- [ ] CA-03: Filtros avanzados con conteos dinamicos
- [ ] CA-04: Detalle de vehiculo con galeria, specs, historial precios
- [ ] CA-05: Comparacion de hasta 4 vehiculos
- [ ] CA-06: Sync incremental desde scrapper_nacional
- [ ] CA-07: Cache inteligente con invalidacion
- [ ] CA-08: Vista grid/list alternables
- [ ] CA-09: Mobile-first responsive design
- [ ] CA-10: SEO-friendly URLs y meta tags

## User Stories Contenidas
- [MKT-BE-005] API de Listado de Vehiculos con Paginacion
- [MKT-BE-006] API de Busqueda Avanzada y Filtros
- [MKT-BE-007] API de Detalle de Vehiculo con Media
- [MKT-FE-005] Pagina de Catalogo con Grid/List View
- [MKT-FE-006] Panel de Filtros Avanzados (Sidebar)
- [MKT-FE-007] Pagina de Detalle de Vehiculo con Carrusel de Fotos
- [MKT-FE-008] Herramienta de Comparacion de Vehiculos
- [MKT-INT-001] Integracion con scrapper_nacional para Datos de Vehiculos

## Dependencias
- [MKT-EP-001] Plataforma Base completada
- [MKT-EP-002] Autenticacion (para favoritos y historial)
ISSUE_EOF
)"
echo "  Created: [MKT-EP-003]"
sleep 2

# ─── MKT-BE-005 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-005] API de Listado de Vehiculos con Paginacion" \
  --label "user-story,backend,priority-critical,sprint-3" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
GET /api/vehicles con paginacion cursor-based, sorting multiple, campos seleccionables (sparse fieldsets), y cache Redis. Endpoint principal del catalogo.

## Contexto Tecnico
### Endpoint:
```
GET /api/vehicles?cursor=xxx&limit=20&sort=-price&fields=id,brand,model,year,price,mileage,image_url,location
```

### Response:
```json
{
  "data": [...vehicles],
  "meta": {
    "total": 11234,
    "limit": 20,
    "next_cursor": "eyJpZCI6...",
    "prev_cursor": "eyJpZCI6...",
    "has_more": true
  },
  "links": {
    "self": "/api/vehicles?cursor=xxx&limit=20",
    "next": "/api/vehicles?cursor=yyy&limit=20",
    "prev": "/api/vehicles?cursor=zzz&limit=20"
  }
}
```

## Criterios de Aceptacion
- [ ] CA-01: GET /api/vehicles retorna lista paginada con cursor-based pagination (no offset); cursor es opaco (base64 encoded composite key); default limit=20, max limit=100
- [ ] CA-02: Sorting soporta multiples campos con prefijo -/+ para desc/asc: sort=-price (mas caro primero), sort=year,-price (por ano asc, precio desc); default sort=-created_at
- [ ] CA-03: Sparse fieldsets via query param fields=id,brand,model,year,price,mileage,image_url reducen payload; si no se especifica, retorna set completo de campos publicos
- [ ] CA-04: Response incluye meta con total count, limit, cursors, has_more; y links HATEOAS (self, next, prev) para navegacion
- [ ] CA-05: Cache Redis con key basada en hash de query params (cursor, limit, sort, fields, filters); TTL 60 segundos; cache-miss fetches de DB y popula cache
- [ ] CA-06: Vehicle card data optimizada: id, brand, model, year, price (formateado MXN), mileage (formateado km), transmission, fuel_type, location, image_url (thumbnail 400x300), badges (is_new, has_offer, is_reserved), source, created_at
- [ ] CA-07: Filtro por status: solo vehiculos active por default; parametro include_status=reserved,sold para admin/dealer endpoints
- [ ] CA-08: Response time < 200ms para p95 con cache hit, < 500ms para cache miss con 11,000+ vehiculos; medido con middleware de timing
- [ ] CA-09: ETag header basado en hash de response para client-side caching; responde 304 Not Modified si If-None-Match coincide
- [ ] CA-10: Query optimization: select solo columnas necesarias, eager load de primera imagen (no N+1), indice compuesto en (status, created_at) y (status, price)
- [ ] CA-11: Rate limiting: 60 req/min para anonimos, 120 req/min para autenticados; rate limit mas alto para search bots identificados
- [ ] CA-12: Logging de cada request con: query params, result count, cache hit/miss, response time; para analytics de busquedas populares

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Cursor pagination es mas eficiente que offset para datasets grandes
- Cursor encode: base64(json({id, sort_value}))
- Considerar materialized view para conteo total si es lento
- Indices: CREATE INDEX idx_vehicles_status_created ON vehicles(status, created_at DESC)

## Dependencias
- [MKT-BE-001] API Base Flask
- [MKT-INT-001] Datos de vehiculos sincronizados

## Epica Padre
[MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda
ISSUE_EOF
)"
echo "  Created: [MKT-BE-005]"
sleep 2

# ─── MKT-BE-006 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-006] API de Busqueda Avanzada y Filtros" \
  --label "user-story,backend,priority-critical,sprint-3" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Busqueda full-text con Elasticsearch, filtros faceted (marca, modelo, ano, precio, km, transmision, combustible, color, ubicacion, fuente), conteos dinamicos, geolocalizacion, y autocompletado.

## Contexto Tecnico
### Endpoints:
```
GET /api/vehicles/search?q=honda+civic&brand=Honda&year_min=2020&year_max=2024&price_min=200000&price_max=500000&transmission=automatic&sort=-relevance&limit=20
GET /api/vehicles/search/suggestions?q=hon     # autocompletado
GET /api/vehicles/search/filters               # filtros disponibles con conteos
GET /api/vehicles/search/nearby?lat=19.43&lng=-99.13&radius=50km
```

### Elasticsearch Index Mapping:
```json
{
  "properties": {
    "brand": { "type": "keyword", "fields": { "search": { "type": "text", "analyzer": "spanish" }}},
    "model": { "type": "keyword", "fields": { "search": { "type": "text" }}},
    "year": { "type": "integer" },
    "price": { "type": "float" },
    "mileage": { "type": "integer" },
    "transmission": { "type": "keyword" },
    "fuel_type": { "type": "keyword" },
    "color": { "type": "keyword" },
    "location": { "type": "geo_point" },
    "location_text": { "type": "keyword" },
    "source": { "type": "keyword" },
    "description": { "type": "text", "analyzer": "spanish" },
    "full_text": { "type": "text", "analyzer": "spanish" },
    "suggest": { "type": "completion" }
  }
}
```

## Criterios de Aceptacion
- [ ] CA-01: GET /api/vehicles/search con parametro q realiza busqueda full-text en Elasticsearch sobre campos: brand, model, description, con boosting (brand^3, model^2, description^1) y analyzer spanish
- [ ] CA-02: Filtros range soportados: year_min/year_max, price_min/price_max, mileage_min/mileage_max; se traducen a Elasticsearch range queries
- [ ] CA-03: Filtros keyword soportados: brand (multi-value OR), model (multi-value), transmission (manual/automatic/cvt), fuel_type (gasoline/diesel/electric/hybrid), color, location_text, source; todos como term queries
- [ ] CA-04: GET /api/vehicles/search/filters retorna filtros disponibles con conteos (aggregations): { brands: [{name: "Honda", count: 450}, ...], transmissions: [{name: "automatic", count: 3200}, ...] }; conteos reflejan filtros activos (faceted)
- [ ] CA-05: GET /api/vehicles/search/suggestions?q=hon retorna top 10 sugerencias de autocompletado usando Elasticsearch completion suggester: ["Honda Civic", "Honda CR-V", "Honda Accord"]; response < 50ms
- [ ] CA-06: GET /api/vehicles/search/nearby?lat=X&lng=Y&radius=50km usa geo_distance query; retorna vehiculos ordenados por distancia con campo distance_km en response
- [ ] CA-07: Relevance scoring configurable: vehiculos con mas fotos, mejor precio, mas recientes reciben boost; score incluye: text_match * recency_boost * completeness_boost
- [ ] CA-08: Elasticsearch index sincronizado con PostgreSQL via event-driven (vehicle created/updated/deleted events en SQS trigger reindex); lag maximo 30 segundos
- [ ] CA-09: Search analytics: cada busqueda se registra con {query, filters, results_count, user_id, timestamp} para mejorar relevance y trends; almacenado en tabla search_logs
- [ ] CA-10: Zero-results handling: si busqueda retorna 0 resultados, sugerir busquedas alternativas (did_you_mean con fuzzy matching) y vehiculos populares como fallback
- [ ] CA-11: Cache de filtros disponibles en Redis (TTL 5 min) ya que cambian poco; cache de suggestions (TTL 10 min); search results NO cacheados (dinamicos)
- [ ] CA-12: Performance: search response < 300ms p95 con 11,000+ docs, suggestions < 100ms p95; pagination con search_after de Elasticsearch (no from/size para deep pages)

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Elasticsearch 8.x con Python elasticsearch-py async client
- Index alias para zero-downtime reindex
- Custom spanish analyzer con stopwords y synonyms (e.g., "carro"="auto"="vehiculo")
- Consider search templates para queries complejas reutilizables

## Dependencias
- [MKT-BE-001] API Base Flask
- [MKT-INF-003] Elasticsearch desplegado
- [MKT-INT-001] Datos sincronizados e indexados

## Epica Padre
[MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda
ISSUE_EOF
)"
echo "  Created: [MKT-BE-006]"
sleep 2

# ─── MKT-BE-007 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-007] API de Detalle de Vehiculo con Media" \
  --label "user-story,backend,priority-critical,sprint-3" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
GET /api/vehicles/:id con informacion completa, galeria de imagenes via CDN, vehiculos similares con ML, historial de precios, y reportes tecnicos asociados.

## Contexto Tecnico
### Endpoints:
```
GET /api/vehicles/:id                  - Detalle completo
GET /api/vehicles/:id/images           - Galeria de imagenes
GET /api/vehicles/:id/similar          - Vehiculos similares (ML)
GET /api/vehicles/:id/price-history    - Historial de precios
GET /api/vehicles/:id/share            - Generar share link
```

### Response modelo completo:
```json
{
  "data": {
    "id": "uuid",
    "brand": "Honda", "model": "Civic", "variant": "EX-T",
    "year": 2023, "price": 425000, "original_price": 450000,
    "mileage": 15000, "transmission": "automatic",
    "fuel_type": "gasoline", "engine": "1.5T 174hp",
    "color": "Blanco", "interior_color": "Negro",
    "doors": 4, "seats": 5, "drivetrain": "FWD",
    "vin": "xxx", "plate_state": "CDMX",
    "location": {"city": "CDMX", "state": "CDMX", "lat": 19.43, "lng": -99.13},
    "description": "...",
    "features": ["Pantalla tactil", "CarPlay", "Camara reversa"],
    "images": [{"url": "cdn://...", "thumbnail": "cdn://...", "order": 1}],
    "source": {"name": "Kavak", "url": "...", "scraped_at": "..."},
    "status": "active",
    "health_score": 85,
    "has_report": true,
    "price_trend": "down",
    "days_listed": 15,
    "views_count": 234,
    "favorites_count": 12
  },
  "similar": [...top 6 similar vehicles],
  "price_history": [{"date": "2024-01-15", "price": 450000}, ...]
}
```

## Criterios de Aceptacion
- [ ] CA-01: GET /api/vehicles/:id retorna vehiculo completo con todos los campos del modelo incluyendo specs, features, location, source info, stats (views, favorites), health_score si tiene reporte
- [ ] CA-02: Imagenes servidas via CloudFront CDN URLs con variantes: original (max 1920px), large (1024px), medium (640px), thumbnail (400x300), y tiny (200x150) para lazy loading
- [ ] CA-03: GET /api/vehicles/:id/similar retorna 6 vehiculos similares usando algoritmo basado en: misma marca/modelo (+50 score), rango de precio +-20% (+30), rango de ano +-2 (+10), misma ubicacion (+10); ordenados por score desc
- [ ] CA-04: GET /api/vehicles/:id/price-history retorna array de {date, price, source} con todos los cambios de precio registrados desde la primera vez que se scrapeo; maximo 365 dias
- [ ] CA-05: View counter incrementado atomicamente en cada GET de detalle; usando Redis INCR para performance, sync a DB cada 5 minutos via background task
- [ ] CA-06: Cache de detalle en Redis con TTL 5 min, invalidado cuando vehiculo se actualiza (event listener); cache de similares TTL 30 min; cache de price history TTL 1 hora
- [ ] CA-07: Si vehiculo no existe retorna 404; si vehiculo fue vendido, retorna datos con status="sold" y mensaje sugeriendo similares disponibles
- [ ] CA-08: GET /api/vehicles/:id/share genera short URL via servicio interno y retorna {url, whatsapp_url, facebook_url, twitter_url} con UTM params para tracking
- [ ] CA-09: Campos calculados incluidos: days_listed (diff created_at a hoy), price_per_km (price/mileage), is_good_deal (comparado con mercado), depreciation_rate
- [ ] CA-10: Respuesta incluye links a acciones disponibles: contact_dealer, schedule_test_drive, start_purchase, request_report; cada link con condiciones (requiere auth, disponible)
- [ ] CA-11: Response time < 150ms p95 con cache hit; < 400ms cache miss; similar vehicles puede ser async (lazy loaded)
- [ ] CA-12: SEO metadata incluida en response: og_title, og_description, og_image para social sharing; canonical URL para evitar duplicados por source

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Vehiculos similares: inicialmente algoritmo basado en reglas; despues reemplazar con ML recommendation de proj-back-ai-agents
- View count: Redis INCR + periodic flush a PostgreSQL (cron cada 5 min)
- Image variants generadas al momento de sync (Lambda trigger en S3 upload)

## Dependencias
- [MKT-BE-005] API de Listado
- [MKT-INT-001] Datos sincronizados con imagenes

## Epica Padre
[MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda
ISSUE_EOF
)"
echo "  Created: [MKT-BE-007]"
sleep 2

# ─── MKT-FE-005 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-005] Pagina de Catalogo con Grid/List View" \
  --label "user-story,frontend,priority-critical,sprint-3" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Pagina principal del catalogo con vista grid (cards) y lista alternables, vehicle cards ricas, infinite scroll, skeleton loaders, y layout responsive (4 cols desktop, 2 tablet, 1 mobile).

## Contexto Tecnico
Standalone component con virtual scrolling para performance, Angular signals para state, y comunicacion con filtros sidebar.

## Criterios de Aceptacion
- [ ] CA-01: Toggle grid/list view con iconos y transicion animada; preferencia persiste en localStorage; grid default en desktop, list en mobile
- [ ] CA-02: Vehicle card en grid: imagen principal (lazy loaded, aspect-ratio 4:3), badge esquina (Nuevo/Usado/Oferta/Reservado), marca+modelo (heading), ano+km+transmision (specs line), precio formateado MXN con descuento tachado si aplica, ubicacion con icono, boton corazon favorito, fuente con icono pequeno
- [ ] CA-03: Vehicle card en list: layout horizontal con imagen izquierda (250px), info centro expandible, precio derecha; mas detalles visibles que grid (descripcion corta, features top 3)
- [ ] CA-04: Infinite scroll con intersection observer: carga 20 vehiculos mas al llegar al final; loading spinner al bottom; mensaje "No hay mas resultados" al final; scroll to top button flotante
- [ ] CA-05: Skeleton loaders durante carga inicial y paginacion: cards skeleton con shimmer animation mimetizan layout real (imagen placeholder, text lines, price block)
- [ ] CA-06: Responsive grid: 4 columnas en wide (1280px+), 3 en desktop (1024px+), 2 en tablet (640px+), 1 en mobile (<640px); gap de 16px entre cards
- [ ] CA-07: Sort bar encima de resultados con: total count ("11,234 vehiculos encontrados"), dropdown sort (Relevancia, Precio menor, Precio mayor, Mas reciente, Menor km, Mayor km), view toggle
- [ ] CA-08: Empty state cuando no hay resultados: ilustracion, mensaje "No encontramos vehiculos con estos filtros", sugerencias (ampliar rango de precio, quitar filtros), boton "Limpiar filtros"
- [ ] CA-09: Vehicle card hover effect: sombra elevada, imagen zoom sutil; click navega a detalle; click en corazon toglea favorito sin navegar (stopPropagation); optimistic UI para favorito
- [ ] CA-10: URL sync: filtros y sort se reflejan en query params de URL para sharing y bookmarking; al cargar pagina con query params, se aplican automaticamente
- [ ] CA-11: Performance: virtual scrolling con Angular CDK para renderizar solo cards visibles; image lazy loading con loading="lazy" nativo; total bundle de catalogo < 200KB gzipped
- [ ] CA-12: Accesibilidad: role="list" y role="listitem", focus management con Tab, card entera es clickeable link, precio anunciado con aria-label completo ("Honda Civic 2023, $425,000 pesos")

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Usar @angular/cdk/scrolling para virtual scroll
- Image format: WebP con fallback JPEG
- Intersection Observer para infinite scroll trigger
- Signal para vehiclesList, isLoading, hasMore, sortBy, viewMode

## Dependencias
- [MKT-FE-001] Angular Project Setup
- [MKT-BE-005] API de Listado

## Epica Padre
[MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda
ISSUE_EOF
)"
echo "  Created: [MKT-FE-005]"
sleep 2

# ─── MKT-FE-006 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-006] Panel de Filtros Avanzados (Sidebar)" \
  --label "user-story,frontend,priority-critical,sprint-3" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Panel lateral de filtros avanzados con categorias colapsables, range sliders, checkboxes con conteo, chips de filtros activos, contador en tiempo real, filtro por mapa, y bottom sheet en mobile.

## Contexto Tecnico
Sidebar component que se comunica con catalogo via signals. Filtros se sinccronizan con URL query params. Conteos vienen de Elasticsearch aggregations.

## Criterios de Aceptacion
- [ ] CA-01: Sidebar fija a la izquierda (280px width) en desktop, colapsable en tablet (icono toggle), bottom sheet deslizable en mobile (swipe up para expandir, drag down para colapsar)
- [ ] CA-02: Secciones colapsables con animacion accordion: Marca (checkbox list), Modelo (dependiente de marca), Ano (range slider), Precio (range slider), Kilometraje (range slider), Transmision (checkboxes), Combustible (checkboxes), Color (swatches circulares), Ubicacion (dropdown), Fuente (checkboxes)
- [ ] CA-03: Range sliders dual-thumb para precio (min $0 - max $2,000,000 MXN), ano (min 2000 - max 2025), km (min 0 - max 300,000); con inputs numericos editables a los lados; formateo MXN para precio
- [ ] CA-04: Checkbox filters con conteo: cada opcion muestra numero de vehiculos disponibles en parentesis, e.g., "Honda (450)", "Toyota (380)"; conteos se actualizan en tiempo real al aplicar otros filtros (faceted)
- [ ] CA-05: Modelo dropdown se filtra por marcas seleccionadas; si marca cambia, modelos se recargan; multi-select para marcas y modelos
- [ ] CA-06: Color filter como circulos de color clickeables con check overlay cuando seleccionado; colores agrupados si hay muchos (azul claro + azul oscuro = "Azul")
- [ ] CA-07: Chips de filtros activos arriba del catalogo: cada chip muestra "Filtro: Valor" con X para remover individual; boton "Limpiar todo" al final; chips scrolleable horizontal si muchos
- [ ] CA-08: Contador de resultados actualizado en tiempo real con debounce 300ms al cambiar cualquier filtro; muestra spinner mientras actualiza; "1,234 vehiculos encontrados"
- [ ] CA-09: Filtro por mapa: boton "Filtrar por area" abre modal con Google Maps / Mapbox; usuario dibuja rectangulo o circulo; se aplica como geo filter; muestra pins de vehiculos en mapa
- [ ] CA-10: Search box de texto en top del sidebar para busqueda full-text con autocompletado (debounce 300ms, muestra sugerencias dropdown, Enter para buscar)
- [ ] CA-11: Filtros persisten en URL query params: ?brand=Honda,Toyota&price_min=200000&price_max=500000&transmission=automatic; al cargar URL, filtros se aplican automaticamente
- [ ] CA-12: Mobile bottom sheet: boton flotante "Filtros (3)" con badge de filtros activos; al tocar, bottom sheet sube con todos los filtros; boton "Ver X resultados" cierra sheet y aplica

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Range sliders: ngx-slider o custom con Angular CDK
- Debounce filter changes con rxjs debounceTime o signal effect
- URL sync con Angular Router queryParams
- Mapa: Google Maps API o Mapbox GL JS

## Dependencias
- [MKT-FE-001] Angular Project Setup
- [MKT-BE-006] API de Busqueda y Filtros
- [MKT-FE-005] Pagina de Catalogo

## Epica Padre
[MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda
ISSUE_EOF
)"
echo "  Created: [MKT-FE-006]"
sleep 2

# ─── MKT-FE-007 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-007] Pagina de Detalle de Vehiculo con Carrusel de Fotos" \
  --label "user-story,frontend,priority-critical,sprint-3" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Pagina de detalle premium con hero carrusel fullscreen, galeria lightbox, tabs de informacion (descripcion, specs, reporte, historial precios), sidebar de compra, vehiculos similares, share, y contact dealer.

## Contexto Tecnico
Route: /vehicles/:id/:slug (SEO-friendly). Standalone component con lazy-loaded sub-components. Responsive con mobile-first approach.

## Criterios de Aceptacion
- [ ] CA-01: Hero carrusel de fotos: imagen principal grande (16:9 aspect ratio), thumbnails horizontales debajo (scrolleable), click en thumbnail cambia principal con crossfade animation, swipe en mobile, flechas prev/next en desktop, contador "3/15 fotos"
- [ ] CA-02: Fullscreen lightbox al click en imagen: fondo oscuro, imagen grande centrada, flechas navegacion, thumbnails strip abajo, zoom con pinch/scroll, close con X o Escape, swipe para navegar en mobile
- [ ] CA-03: Tabs de informacion debajo del carrusel: Descripcion (texto + features list con iconos), Especificaciones (tabla key-value agrupada por categoria: motor, exterior, interior, seguridad), Reporte Tecnico (si disponible, link a vista de reporte), Historial de Precios (grafica lineal con tooltips)
- [ ] CA-04: Sidebar derecha sticky (scroll con contenido): precio grande en verde con descuento tachado rojo si aplica, badge "Buen precio" si is_good_deal, botones CTA: "Me interesa" (primario grande), "Cotizar financiamiento", "Cotizar seguro"; info seller/dealer abajo con avatar, nombre, rating
- [ ] CA-05: Seccion vehiculos similares como carousel horizontal al final: 6 cards scrolleables, flechas prev/next, swipe mobile; titulo "Vehiculos similares"
- [ ] CA-06: Share button con dropdown: Copiar link (con feedback "Copiado!"), Compartir por WhatsApp (abre wa.me con mensaje pre-formado), Facebook, Twitter; usa Web Share API en mobile si disponible
- [ ] CA-07: Contact dealer section: boton "Contactar vendedor" abre modal con formulario (nombre, telefono, mensaje predefinido editable); o boton WhatsApp directo si dealer tiene numero
- [ ] CA-08: Breadcrumbs: Home > Vehiculos > {Marca} > {Modelo} > {Ano} {Modelo} {Variante}; cada nivel es link clickeable que navega al catalogo con ese filtro
- [ ] CA-09: Specs table: filas agrupadas (Motor y rendimiento: motor, potencia, torque, transmision; Exterior: color, puertas, llantas; Interior: asientos, color interior, materiales; Seguridad: airbags, ABS, control estabilidad); iconos por spec
- [ ] CA-10: Historial de precios: grafica Chart.js o ngx-charts con line chart, eje X fechas, eje Y precio MXN; tooltip con precio y fuente en cada punto; indicador de tendencia (sube/baja/estable)
- [ ] CA-11: Responsive: mobile todo en columna unica (carrusel arriba, precio sticky bottom bar, tabs scroll horizontal), tablet sidebar colapsable, desktop full layout con sidebar
- [ ] CA-12: SEO: meta tags dinamicos (og:title, og:description, og:image, og:price:amount, og:price:currency), structured data JSON-LD (schema.org/Car), canonical URL

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Carrusel: Swiper.js (best mobile support) o custom con Angular animations
- Lightbox: custom con Angular CDK overlay
- Charts: ngx-charts o Chart.js con ng2-charts
- Lazy load tabs content (solo carga al activar tab)
- Preload next/prev vehicle para navegacion rapida

## Dependencias
- [MKT-FE-001] Angular Project Setup
- [MKT-BE-007] API de Detalle de Vehiculo
- [MKT-FE-005] Catalogo (para navegacion)

## Epica Padre
[MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda
ISSUE_EOF
)"
echo "  Created: [MKT-FE-007]"
sleep 2

# ─── MKT-FE-008 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-008] Herramienta de Comparacion de Vehiculos" \
  --label "user-story,frontend,priority-medium,sprint-4" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Seleccionar hasta 4 vehiculos para comparar side-by-side en tabla comparativa con highlight de diferencias, precios, especificaciones, y reportes.

## Contexto Tecnico
Feature accesible desde catalogo (boton "Comparar" en cards) y desde detalle. Vehiculos seleccionados se guardan en signal store. Pagina dedicada /vehicles/compare.

## Criterios de Aceptacion
- [ ] CA-01: Boton "Comparar" en vehicle cards y detalle page; toggle que agrega/remueve de lista de comparacion; maximo 4 vehiculos, si intenta agregar 5to muestra toast "Maximo 4 vehiculos para comparar"
- [ ] CA-02: Floating comparison bar en bottom cuando hay 1+ vehiculos seleccionados: muestra mini thumbnails de vehiculos agregados, boton X para remover cada uno, boton "Comparar (N)" para ir a pagina de comparacion; se oculta si lista vacia
- [ ] CA-03: Pagina /vehicles/compare muestra tabla comparativa: columnas = vehiculos, filas = atributos; header de cada columna tiene imagen, marca+modelo+ano, precio, boton remover
- [ ] CA-04: Secciones de comparacion agrupadas: Precio y valor (precio, precio/km, tendencia, dias en listado), Motor (motor, potencia, torque, transmision, combustible), Dimensiones (puertas, asientos, cajuela), Equipamiento (lista de features con check/X por vehiculo)
- [ ] CA-05: Highlight de diferencias: celdas con mejor valor en verde (menor precio, menor km, mas features), peor valor en rojo sutil; toggle para mostrar/ocultar highlights
- [ ] CA-06: Filas colapsables por seccion con expand/collapse all; seccion "Diferencias solamente" toggle que oculta filas donde todos los vehiculos tienen el mismo valor
- [ ] CA-07: Sticky header con imagenes y precios que permanece visible al hacer scroll vertical en la tabla
- [ ] CA-08: Boton "Agregar vehiculo" cuando hay menos de 4: abre modal de busqueda rapida para agregar directamente desde comparador
- [ ] CA-09: Responsive: desktop tabla horizontal scroll si >3 vehiculos, tablet 2 columnas max con scroll, mobile card-by-card view con tabs por vehiculo (no tabla)
- [ ] CA-10: Share comparison: boton genera URL con IDs de vehiculos en query params (/vehicles/compare?ids=uuid1,uuid2,uuid3) para compartir comparacion
- [ ] CA-11: Persist comparison list en localStorage para mantener entre sesiones; limpiar automaticamente vehiculos que ya no estan activos (sold/removed)
- [ ] CA-12: CTA por vehiculo en footer de columna: "Me interesa" boton que navega a flujo de compra de ese vehiculo especifico

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Signal store para comparison list (max 4 UUIDs)
- Batch API call: GET /api/vehicles?ids=uuid1,uuid2,uuid3,uuid4 para cargar todos a la vez
- Print-friendly CSS para imprimir comparacion
- Analytics: track comparisons (vehiculos comparados, accion post-comparacion)

## Dependencias
- [MKT-FE-005] Catalogo
- [MKT-FE-007] Detalle de Vehiculo
- [MKT-BE-007] API de Detalle

## Epica Padre
[MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda
ISSUE_EOF
)"
echo "  Created: [MKT-FE-008]"
sleep 2

# ─── MKT-INT-001 ───────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-INT-001] Integracion con scrapper_nacional para Datos de Vehiculos" \
  --label "user-story,integration,priority-critical,sprint-3" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Sincronizar datos de vehiculos desde scrapper_nacional DB al marketplace. Mapeo de campos, normalizacion, sync incremental (nuevos, actualizados, eliminados), y worker SQS para procesamiento asincrono.

## Contexto Tecnico
scrapper_nacional tiene 11,000+ vehiculos de 18 fuentes (Kavak, Seminuevos.com, AutoTrader MX, etc.) en PostgreSQL. El marketplace necesita una copia normalizada en su propia DB + indexada en Elasticsearch.

### Flujo de sync:
```
scrapper_nacional DB -> CDC (Change Data Capture) via triggers/polling
  -> SQS queue vehicle-sync
    -> Worker consumer (proj-worker-marketplace-sync)
      -> Normalize & validate
        -> Insert/Update marketplace DB
          -> Index in Elasticsearch
            -> Generate image thumbnails (S3)
```

### Campo mapping (scrapper -> marketplace):
```python
FIELD_MAP = {
    'titulo': parse_brand_model_year,  # "Honda Civic 2023" -> brand, model, year
    'precio': 'price',                  # Decimal, MXN
    'kilometraje': 'mileage',           # int, clean "45,000 km" -> 45000
    'transmision': normalize_transmission, # "Automatica" -> "automatic"
    'combustible': normalize_fuel,       # "Gasolina" -> "gasoline"
    'color': normalize_color,            # "Blanco Perla" -> "Blanco"
    'ubicacion': parse_location,         # "CDMX, Mexico" -> {city, state, lat, lng}
    'imagenes': 'images',               # Array of URLs to download and re-host
    'fuente': 'source',                 # Source website name
    'url_original': 'source_url',       # Original listing URL
    'fecha_scraping': 'scraped_at',
}
```

## Criterios de Aceptacion
- [ ] CA-01: Worker SQS consumer procesa mensajes del queue vehicle-sync con eventos: vehicle_created, vehicle_updated, vehicle_deleted; cada mensaje contiene scrapper vehicle ID y event type
- [ ] CA-02: Mapeo de campos completo: titulo parseado a brand+model+year+variant usando regex y lookup table de marcas/modelos; precio limpiado de formato; km extraido de string; transmision y combustible normalizados a enum values
- [ ] CA-03: Normalizacion de ubicacion: texto libre parseado a {city, state} con geocoding a {lat, lng} usando servicio de geocoding (Google Maps o Nominatim); cache de geocoding en Redis para evitar llamadas repetidas
- [ ] CA-04: Imagenes descargadas de fuente original, redimensionadas a variantes (original, large, medium, thumbnail, tiny), subidas a S3 con estructura s3://bucket/vehicles/{id}/{hash}.webp; URLs de CDN almacenadas en DB
- [ ] CA-05: Sync incremental: solo procesa vehiculos nuevos o con cambios (basado en hash de campos clave); vehiculos removidos de fuente se marcan como inactive (soft delete), no se eliminan
- [ ] CA-06: Deduplicacion: detectar mismo vehiculo en multiples fuentes usando heuristica (brand+model+year+mileage+location similarity); merge sources, mantener mejor precio como referencia
- [ ] CA-07: Validacion: vehiculos con datos incompletos (sin precio, sin imagenes, sin ubicacion) se marcan como draft y no aparecen en catalogo publico; log de issues de calidad de datos
- [ ] CA-08: Elasticsearch indexing: despues de insert/update en DB, indexar documento en Elasticsearch con mapping correcto; bulk indexing para initial load (11,000+ docs)
- [ ] CA-09: Initial full sync: comando CLI flask sync-vehicles --full que hace sync completo de todos los vehiculos de scrapper_nacional; debe completar en menos de 30 minutos para 11,000 vehiculos
- [ ] CA-10: Monitoring: metricas de sync publicadas a CloudWatch: vehicles_synced (count), sync_duration (ms), sync_errors (count), sync_lag (seconds between scrape and availability); alarma si lag > 5 minutos
- [ ] CA-11: Error handling: mensajes fallidos van a DLQ despues de 3 reintentos; dashboard de DLQ para retry manual; notificacion Slack cuando DLQ tiene mensajes
- [ ] CA-12: Price history tracking: cada cambio de precio se registra en tabla vehicle_price_history con {vehicle_id, price, source, recorded_at} para grafica de historial

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- proj-worker-marketplace-sync ya existe como repo base; extender con logica de marketplace
- Usar Pillow para image processing, boto3 para S3 upload
- Elasticsearch bulk API para initial indexing
- Considerar CDC con Debezium si polling es insuficiente

## Dependencias
- [MKT-BE-001] API Base Flask (modelos de dominio)
- [MKT-INF-003] S3, SQS, Elasticsearch desplegados
- Acceso lectura a scrapper_nacional DB

## Epica Padre
[MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda
ISSUE_EOF
)"
echo "  Created: [MKT-INT-001]"
sleep 2

###############################################################################
# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 4: [MKT-EP-004] Reportes Tecnicos, Valuacion & Evaluacion de Mercado
# ═══════════════════════════════════════════════════════════════════════════════
###############################################################################
echo ""
echo ">>> EPIC 4: Reportes Tecnicos, Valuacion & Evaluacion de Mercado"

gh issue create --repo "$REPO" \
  --title "[MKT-EP-004] Reportes Tecnicos, Valuacion & Evaluacion de Mercado" \
  --label "epic,priority-high,sprint-4" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Integracion con sistema de reportes tecnicos (diagnosticos OBD-II), valuacion de vehiculos con IA basada en datos reales de 18 fuentes, y dashboard de analisis de mercado con tendencias, indices de precios, y demanda.

## Contexto Tecnico
- Datos de diagnostico: diagnostic_scans, sensor_readings, dtc_faults del sistema existente
- AI Agents: Depreciation Agent, Marketplace Analytics Agent, Report Builder Agent en proj-back-ai-agents
- 11,000+ vehiculos comparables para valuacion
- 18 fuentes de datos para analisis de mercado

## Criterios de Aceptacion
- [ ] CA-01: Reportes tecnicos accesibles por vehiculo con score de salud
- [ ] CA-02: Valuacion de mercado con IA retorna precio justo y depreciacion
- [ ] CA-03: Dashboard de tendencias de mercado con graficas interactivas
- [ ] CA-04: Integracion con AI agents funcional y asincrona
- [ ] CA-05: PDF descargable de reportes
- [ ] CA-06: Mapa de calor de precios por ubicacion
- [ ] CA-07: Comparacion entre fuentes de datos
- [ ] CA-08: Indices de precios por segmento actualizados
- [ ] CA-09: Datos de demanda basados en busquedas
- [ ] CA-10: Performance: valuaciones en menos de 5s

## User Stories Contenidas
- [MKT-BE-008] API de Reportes Tecnicos por Vehiculo
- [MKT-BE-009] API de Valuacion de Mercado con IA
- [MKT-BE-010] API de Analisis de Mercado
- [MKT-FE-009] Vista de Reporte Tecnico del Vehiculo
- [MKT-FE-010] Dashboard de Analisis de Mercado
- [MKT-INT-002] Integracion con AI Agents para Valuacion

## Dependencias
- [MKT-EP-003] Catalogo de Vehiculos
- proj-back-ai-agents operativo
ISSUE_EOF
)"
echo "  Created: [MKT-EP-004]"
sleep 2

# ─── MKT-BE-008 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-008] API de Reportes Tecnicos por Vehiculo" \
  --label "user-story,backend,priority-high,sprint-4" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
API para acceder a reportes tecnicos de vehiculos: diagnosticos OBD-II, dossier completo, score de salud por sistema, codigos DTC, y lecturas de sensores.

## Contexto Tecnico
### Endpoints:
```
GET /api/vehicles/:id/reports                    - Lista de reportes disponibles
GET /api/vehicles/:id/reports/:reportId          - Reporte especifico
GET /api/vehicles/:id/dossier                    - Dossier completo consolidado
GET /api/vehicles/:id/health-score               - Score de salud resumen
GET /api/vehicles/:id/reports/:reportId/pdf      - Descargar PDF
```

### Modelo de datos:
```python
class VehicleReport:
    id: UUID
    vehicle_id: UUID
    scan_date: datetime
    scanner_type: str          # OBD-II, custom
    overall_score: int         # 0-100
    systems: List[SystemScore] # motor: 90, transmision: 85, frenos: 95...
    dtc_codes: List[DTCFault]  # P0301: Misfire cylinder 1
    sensor_readings: List[SensorReading]
    recommendations: List[str]
    technician_notes: Optional[str]

class SystemScore:
    system_name: str    # engine, transmission, brakes, electrical, suspension, exhaust, hvac
    score: int          # 0-100
    status: str         # good, warning, critical
    details: str
```

## Criterios de Aceptacion
- [ ] CA-01: GET /api/vehicles/:id/reports retorna lista de reportes con {id, scan_date, overall_score, scanner_type, systems_summary}; ordenados por fecha desc; paginados
- [ ] CA-02: GET /api/vehicles/:id/health-score retorna score consolidado: overall (0-100), por sistema (engine, transmission, brakes, electrical, suspension, exhaust, hvac), status semaforo (good >80, warning 50-80, critical <50)
- [ ] CA-03: GET /api/vehicles/:id/dossier retorna dossier completo: ultimo reporte tecnico, historial de precios, datos de mercado, comparacion con similares, recomendacion compra (buy/wait/avoid)
- [ ] CA-04: Codigos DTC incluyen: code (P0301), severity (critical/warning/info), system_affected, description en espanol, estimated_repair_cost_range, is_active flag
- [ ] CA-05: Sensor readings incluyen: sensor_name, value, unit, min_expected, max_expected, status (normal/abnormal), timestamp; formateados para graficacion
- [ ] CA-06: GET /api/vehicles/:id/reports/:reportId/pdf genera PDF con WeasyPrint o ReportLab: header con logo, info vehiculo, score visual (gauge), tabla sistemas, DTCs, recomendaciones; retorna Content-Type: application/pdf
- [ ] CA-07: Integracion con tablas existentes: diagnostic_scans (join por VIN o vehicle_id), sensor_readings (time series), dtc_faults (codigos activos/historicos)
- [ ] CA-08: Cache de health score en Redis (TTL 1h) ya que reportes no cambian frecuentemente; cache de PDF generado en S3 (regenerar solo si hay nuevo reporte)
- [ ] CA-09: Acceso controlado: health score es publico (visible en catalogo), reporte detallado requiere autenticacion, dossier completo requiere compra o suscripcion premium
- [ ] CA-10: Vehiculos sin reportes: health-score retorna {available: false, message: "Sin reporte tecnico disponible"}; esto NO bloquea la compra, es informativo
- [ ] CA-11: Score calculation algorithm: weighted average de systems (engine 25%, transmission 20%, brakes 20%, electrical 15%, suspension 10%, exhaust 5%, hvac 5%); DTCs activos reducen score del sistema afectado
- [ ] CA-12: Historial de scores: registrar score cada vez que se genera nuevo reporte para mostrar tendencia de salud del vehiculo en el tiempo

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Datos de diagnostico pueden venir de proj-back-driver-adapters
- PDF generation puede ser async (generar en background, retornar URL cuando listo)
- DTCs: usar base de datos OBD-II standard para descriptions
- Score historico permite detectar degradacion del vehiculo

## Dependencias
- [MKT-BE-007] API de Detalle de Vehiculo
- Acceso a datos de diagnostic_scans

## Epica Padre
[MKT-EP-004] Reportes Tecnicos, Valuacion & Evaluacion de Mercado
ISSUE_EOF
)"
echo "  Created: [MKT-BE-008]"
sleep 2

# ─── MKT-BE-009 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-009] API de Valuacion de Mercado con IA" \
  --label "user-story,backend,priority-high,sprint-4" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Valuacion de vehiculos basada en datos reales de mercado (11,000+ comparables) con precio justo, depreciacion proyectada, y recomendacion de compra. Integra con Depreciation Agent de proj-back-ai-agents.

## Contexto Tecnico
### Endpoints:
```
POST /api/vehicles/:id/valuation       - Solicitar valuacion completa
GET  /api/vehicles/:id/valuation       - Obtener ultima valuacion
GET  /api/vehicles/:id/fair-price      - Precio justo rapido (cached)
POST /api/valuation/estimate           - Estimacion sin vehiculo especifico (por params)
```

### Response valuacion:
```json
{
  "vehicle_id": "uuid",
  "valuation_date": "2024-01-15",
  "current_price": 425000,
  "fair_market_value": 410000,
  "price_rating": "slightly_overpriced",  // great_deal, fair, slightly_over, overpriced
  "price_difference_pct": 3.6,
  "comparable_vehicles": 45,
  "depreciation": {
    "year_1": { "value": 380000, "pct": -7.3 },
    "year_2": { "value": 355000, "pct": -13.4 },
    "year_3": { "value": 330000, "pct": -19.5 }
  },
  "market_position": {
    "percentile": 65,
    "below_avg_pct": 40,
    "at_avg_pct": 35,
    "above_avg_pct": 25
  },
  "recommendation": "fair",
  "confidence_score": 0.87,
  "factors": [
    { "factor": "mileage", "impact": "positive", "detail": "15% below average for year" },
    { "factor": "location", "impact": "neutral", "detail": "CDMX average market" },
    { "factor": "condition", "impact": "positive", "detail": "Health score 85/100" }
  ]
}
```

## Criterios de Aceptacion
- [ ] CA-01: POST /api/vehicles/:id/valuation inicia valuacion asincrona via SQS queue valuation-requests; retorna 202 Accepted con {valuation_id, status: "processing", estimated_time: "5s"}; GET retorna resultado cuando listo
- [ ] CA-02: Fair market value calculado con: promedio ponderado de vehiculos comparables (misma marca+modelo, ano +-1, km +-20%), ajustado por ubicacion, condicion (health score), y tendencia de mercado
- [ ] CA-03: Price rating categorizado: great_deal (<-10% vs fair value), fair (-10% to +5%), slightly_overpriced (+5% to +15%), overpriced (>+15%); con porcentaje exacto de diferencia
- [ ] CA-04: Depreciacion proyectada a 1, 2, 3 anos usando modelo del Depreciation Agent; basado en curvas historicas de depreciacion por marca/modelo/segmento
- [ ] CA-05: Market position: percentil del precio actual vs mercado (percentil 65 = mas caro que 65% de similares); distribucion below/at/above average
- [ ] CA-06: Confidence score (0-1) basado en: cantidad de comparables (mas = mayor confianza), varianza de precios (menos = mayor), completitud de datos del vehiculo
- [ ] CA-07: Factors analysis: lista de factores que influyen en la valuacion con impacto (positive/negative/neutral) y detalle; minimo 5 factores analizados
- [ ] CA-08: GET /api/vehicles/:id/fair-price retorna solo {fair_market_value, price_rating, confidence} de forma rapida (cached, < 100ms); util para mostrar badge en listado
- [ ] CA-09: POST /api/valuation/estimate acepta {brand, model, year, mileage, transmission, location} sin vehiculo especifico; util para vendedores que quieren saber cuanto vale su auto
- [ ] CA-10: Cache de valuaciones en Redis (TTL 24h) ya que datos de mercado no cambian rapidamente; invalidar si vehiculo cambia de precio
- [ ] CA-11: Integracion con Depreciation Agent via HTTP call a proj-back-ai-agents: POST /agents/depreciation/predict con payload del vehiculo; timeout 10s, fallback a modelo estadistico simple si agent no responde
- [ ] CA-12: Audit log: cada valuacion registrada con input params, resultado, comparables usados, modelo utilizado, latencia; para monitoreo de calidad de valuaciones

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Modelo estadistico fallback: median price de comparables con ajuste por km y ano
- Comparable vehicles query: marca+modelo exacto, ano +-1, km +-20%, excluyendo outliers (>2 std dev)
- Depreciacion: curvas diferentes por segmento (lujo deprecia mas rapido que economico)

## Dependencias
- [MKT-BE-007] API de Detalle
- [MKT-INT-001] Datos de vehiculos sincronizados
- [MKT-INT-002] Integracion AI Agents

## Epica Padre
[MKT-EP-004] Reportes Tecnicos, Valuacion & Evaluacion de Mercado
ISSUE_EOF
)"
echo "  Created: [MKT-BE-009]"
sleep 2

# ─── MKT-BE-010 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-010] API de Analisis de Mercado" \
  --label "user-story,backend,priority-high,sprint-4" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
APIs de analisis de mercado: tendencias de precios por marca/modelo, indice de precios por segmento, demanda por busquedas, y datos agregados de 18 fuentes con 11,000+ vehiculos.

## Contexto Tecnico
### Endpoints:
```
GET /api/market/trends?brand=Honda&model=Civic&period=6m
GET /api/market/price-index?segment=sedan&period=12m
GET /api/market/demand?period=30d
GET /api/market/sources/comparison
GET /api/market/top-vehicles?by=views|favorites|sales&limit=10
GET /api/market/heatmap?type=price|supply
```

## Criterios de Aceptacion
- [ ] CA-01: GET /api/market/trends retorna series temporales de precio promedio por brand/model con granularidad configurable (daily, weekly, monthly); incluye min, max, avg, median, count por periodo
- [ ] CA-02: GET /api/market/price-index retorna indice de precios por segmento (sedan, SUV, pickup, hatchback, luxury) normalizado a base 100; permite comparar evolucion entre segmentos
- [ ] CA-03: GET /api/market/demand retorna metricas de demanda: top searched brands/models, search volume trends, ratio oferta/demanda por segmento, tiempo promedio de venta estimado
- [ ] CA-04: GET /api/market/sources/comparison retorna comparacion entre las 18 fuentes: conteo vehiculos, precio promedio, rango de precios, frescura de datos (last scraped), cobertura geografica
- [ ] CA-05: GET /api/market/top-vehicles retorna rankings: mas vistos, mas favoriteados, mejor precio, mayor descuento, mas recientes; configurable por periodo (7d, 30d, 90d)
- [ ] CA-06: GET /api/market/heatmap retorna datos geolocalizados para mapa de calor: por precio promedio o por densidad de oferta; agrupados por ciudad/estado; formato GeoJSON compatible
- [ ] CA-07: Datos pre-calculados via cron jobs nocturnos: trends, indices, y rankings se calculan y almacenan en tabla market_analytics; endpoints leen de tabla, no calculan en tiempo real
- [ ] CA-08: Cache agresivo en Redis: trends TTL 6h, price-index TTL 12h, demand TTL 1h, top-vehicles TTL 30min; invalidacion solo por cron de recalculo
- [ ] CA-09: Filtros temporales consistentes: period accepts 7d, 30d, 90d, 6m, 12m; default 30d; date_from/date_to para rango custom
- [ ] CA-10: Response incluye metadata: data_points_count, date_range, last_updated, confidence_level; para que frontend muestre frescura de datos
- [ ] CA-11: Datos de demanda derivados de search_logs: queries mas frecuentes, filtros mas usados, horarios pico de busqueda, conversion rate (busqueda->detalle->compra)
- [ ] CA-12: Export endpoints: GET /api/market/trends/export?format=csv|json genera archivo descargable con datos historicos; util para analistas

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Pre-calculo con Celery beat o Flask-APScheduler
- Materialized views en PostgreSQL para aggregations pesadas
- Considerar Apache Superset o Metabase para internal analytics
- GeoJSON format para integracion con Mapbox/Google Maps

## Dependencias
- [MKT-BE-005] API de Listado (datos de vehiculos)
- [MKT-BE-006] API de Busqueda (search logs)
- [MKT-INT-001] Datos sincronizados

## Epica Padre
[MKT-EP-004] Reportes Tecnicos, Valuacion & Evaluacion de Mercado
ISSUE_EOF
)"
echo "  Created: [MKT-BE-010]"
sleep 2

# ─── MKT-FE-009 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-009] Vista de Reporte Tecnico del Vehiculo" \
  --label "user-story,frontend,priority-high,sprint-5" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Vista de reporte tecnico: semaforo de salud por sistema, codigos DTC con descripcion, historial de diagnosticos, PDF descargable, y graficas de sensores. Accesible desde detalle de vehiculo.

## Contexto Tecnico
Tab o seccion dedicada en pagina de detalle de vehiculo. Componentes standalone con graficas interactivas. Acceso: health score publico, detalle requiere auth.

## Criterios de Aceptacion
- [ ] CA-01: Score general prominente: gauge circular animado (0-100) con color gradient (rojo<50, naranja 50-80, verde>80), numero grande en centro, label "Salud del Vehiculo", ultimo scan date
- [ ] CA-02: Semaforo por sistema: cards o filas para cada sistema (Motor, Transmision, Frenos, Electrico, Suspension, Escape, Climatizacion) con icono, nombre, score bar horizontal, indicador color (verde/amarillo/rojo), detalle expandible
- [ ] CA-03: Seccion Codigos DTC: tabla con columnas (Codigo, Severidad badge, Sistema, Descripcion, Costo estimado reparacion); filtrable por severidad; activos destacados vs historicos en gris
- [ ] CA-04: Historial de diagnosticos: timeline vertical con fecha, score, cambio vs anterior (flecha arriba/abajo con delta), resumen de issues encontrados; click expande detalle de cada scan
- [ ] CA-05: Graficas de sensores: line charts para lecturas clave (temperatura motor, RPM promedio, voltaje bateria, presion aceite) con zona normal sombreada y valores fuera de rango destacados
- [ ] CA-06: Boton "Descargar PDF" genera y descarga reporte completo; loading state mientras se genera; si ya existe en cache, descarga inmediata
- [ ] CA-07: Estado "Sin reporte": cuando vehiculo no tiene diagnosticos, mostrar ilustracion con mensaje "Este vehiculo no cuenta con reporte tecnico", sugerencia de solicitar inspeccion
- [ ] CA-08: Comparacion con promedio: score del vehiculo vs score promedio de marca+modelo+ano similar; "Este vehiculo esta 12% arriba del promedio para Honda Civic 2023"
- [ ] CA-09: Recomendaciones: lista de acciones sugeridas basadas en DTCs y scores (ej. "Revisar sistema de frenos - score bajo", "Cambio de aceite recomendado - sensor presion")
- [ ] CA-10: Responsive: mobile cards apiladas, gauges reducidos, tabla DTCs como cards; graficas con scroll horizontal; PDF se abre en nueva tab en mobile
- [ ] CA-11: Animaciones: gauges se llenan al scroll into view (intersection observer), scores cuentan desde 0, bars se expanden; mejora la percepcion de calidad
- [ ] CA-12: Acceso gated: health score visible para todos, detalle (DTCs, sensores, historial) requiere autenticacion; modal "Inicia sesion para ver el reporte completo" con CTA login

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Gauge: custom SVG component con Angular animations
- Charts: ngx-charts o Chart.js para line/area charts
- PDF: trigger backend generation, poll for completion, download
- Animaciones: IntersectionObserver + Angular animation triggers

## Dependencias
- [MKT-FE-007] Pagina de Detalle
- [MKT-BE-008] API de Reportes Tecnicos

## Epica Padre
[MKT-EP-004] Reportes Tecnicos, Valuacion & Evaluacion de Mercado
ISSUE_EOF
)"
echo "  Created: [MKT-FE-009]"
sleep 2

# ─── MKT-FE-010 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-010] Dashboard de Analisis de Mercado" \
  --label "user-story,frontend,priority-medium,sprint-5" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Dashboard interactivo de analisis de mercado: graficas de tendencias de precios, comparacion entre fuentes, mapa de calor por ubicacion, top marcas/modelos, y tiempo promedio de venta.

## Contexto Tecnico
Pagina dedicada /market/analytics. Dashboard con widgets configurables, graficas interactivas, y filtros globales. Datos de API de mercado pre-calculados.

## Criterios de Aceptacion
- [ ] CA-01: Layout dashboard con grid de widgets: hero chart arriba (tendencia de precios general), 4 KPI cards (total vehiculos, precio promedio, cambio vs mes anterior, tiempo promedio venta), charts grid abajo
- [ ] CA-02: Grafica de tendencias: line chart multi-serie con precio promedio por segmento (sedan, SUV, pickup, etc.) a lo largo del tiempo; selector de periodo (7d, 30d, 90d, 6m, 12m); tooltips con detalle al hover
- [ ] CA-03: Comparacion entre fuentes: bar chart horizontal con las 18 fuentes, mostrando conteo de vehiculos y precio promedio; ordenable por cualquier metrica; click en fuente filtra todo el dashboard
- [ ] CA-04: Mapa de calor: mapa de Mexico con overlay de calor por precio promedio (rojo=caro, azul=barato) o por densidad de oferta (mas oscuro=mas vehiculos); toggle entre modos; zoom interactivo con Mapbox/Google Maps
- [ ] CA-05: Top rankings widgets: Top 10 marcas mas buscadas (bar chart), Top 10 modelos mas favoriteados (bar chart), Mejores ofertas del momento (vehicle cards mini); tabs para alternar entre rankings
- [ ] CA-06: Price distribution: histograma de precios del mercado completo con bins de $50K MXN; overlay de kde curve; markers para precio del vehiculo actual si viene desde detalle
- [ ] CA-07: Filtros globales del dashboard: marca, modelo, ano, segmento, ubicacion; afectan todas las graficas simultaneamente; chips de filtros activos
- [ ] CA-08: KPI cards animados: numero grande con animacion de conteo, porcentaje de cambio vs periodo anterior con flecha (verde arriba, rojo abajo), sparkline mini chart de ultimos 30 dias
- [ ] CA-09: Exportar datos: boton export por grafica (PNG imagen, CSV datos); boton export full dashboard (PDF reporte completo con todas las graficas)
- [ ] CA-10: Responsive: mobile widgets apilados full-width, graficas con scroll horizontal, mapa full-width; tablet 2 columnas; desktop 3-4 columnas con sidebar filtros
- [ ] CA-11: Real-time feel: datos se refrescan cada 5 minutos con indicador "Actualizado hace X minutos"; refresh manual con boton; loading skeleton durante refresh
- [ ] CA-12: Acceso: dashboard basico publico (tendencias, top rankings), dashboard avanzado (mapa calor, comparacion fuentes, export) requiere cuenta registrada

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Charts library: ngx-charts (Angular native) o ECharts (mas features) con ngx-echarts
- Map: Mapbox GL JS con ngx-mapbox-gl o Google Maps con @angular/google-maps
- Dashboard grid: Angular CDK drag-drop para widgets reposicionables (future feature)
- Cache agresivo de datos del dashboard en service con signals

## Dependencias
- [MKT-FE-001] Angular Project Setup
- [MKT-BE-010] API de Analisis de Mercado

## Epica Padre
[MKT-EP-004] Reportes Tecnicos, Valuacion & Evaluacion de Mercado
ISSUE_EOF
)"
echo "  Created: [MKT-FE-010]"
sleep 2

# ─── MKT-INT-002 ───────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-INT-002] Integracion con AI Agents para Valuacion" \
  --label "user-story,integration,priority-high,sprint-4" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Conectar marketplace con proj-back-ai-agents: Depreciation Agent (prediccion depreciacion), Marketplace Analytics Agent (analisis mercado), Report Builder Agent (generacion reportes). Comunicacion via HTTP + SQS para tareas pesadas.

## Contexto Tecnico
proj-back-ai-agents expone 7 agents via REST API. El marketplace consume 3 de ellos. Llamadas sincronas para queries rapidas, async via SQS para procesamiento pesado (valuaciones batch).

### AI Agents endpoints existentes:
```
POST /agents/depreciation/predict       - Prediccion de depreciacion
POST /agents/marketplace/analyze        - Analisis de mercado
POST /agents/report-builder/generate    - Generar reporte completo
GET  /agents/status                     - Health check de agents
```

### Flujo asincrono:
```
Marketplace API -> SQS valuation-requests
  -> Worker reads queue
    -> Calls AI Agent REST API
      -> Agent processes with ML model
        -> Response stored in marketplace DB
          -> SNS notification: valuation-completed
            -> User notified
```

## Criterios de Aceptacion
- [ ] CA-01: HTTP client configurado para proj-back-ai-agents con base URL configurable por environment, timeout 15s para sync calls, retry con exponential backoff (3 intentos, 1s/2s/4s delay)
- [ ] CA-02: Depreciation Agent integration: POST /agents/depreciation/predict con {brand, model, year, mileage, condition_score, location} retorna {depreciation_curve: [{year, value, pct}], confidence}; cache resultado 24h en Redis
- [ ] CA-03: Marketplace Analytics Agent: POST /agents/marketplace/analyze con {brand, model, year, region} retorna {market_position, price_distribution, demand_score, trend}; cache 6h
- [ ] CA-04: Report Builder Agent: POST /agents/report-builder/generate con {vehicle_id, include_sections: [valuation, technical, market]} retorna {report_url} con PDF completo; async, timeout 30s
- [ ] CA-05: Circuit breaker implementado: si agent falla 5 veces consecutivas, abrir circuito por 60s; durante circuito abierto, usar fallback (modelo estadistico simple); publicar metrica circuit_breaker_state
- [ ] CA-06: Async valuations via SQS: POST /api/vehicles/:id/valuation enqueue mensaje a valuation-requests; worker consume, llama agent, almacena resultado; frontend polling o WebSocket para resultado
- [ ] CA-07: Batch processing: endpoint POST /api/valuation/batch acepta lista de vehicle IDs, enqueue individual messages a SQS, retorna batch_id; GET /api/valuation/batch/:batchId retorna progreso y resultados parciales
- [ ] CA-08: Agent health monitoring: cron job cada 5 min llama GET /agents/status; si unhealthy, alert a Slack y switch a fallback mode; dashboard de status de agents en admin panel
- [ ] CA-09: Request/response logging: cada llamada a agent se registra con {agent_name, input_hash, response_time, status, error_if_any}; metricas agregadas en CloudWatch
- [ ] CA-10: Fallback models: si Depreciation Agent no responde, usar tabla de depreciacion promedio por segmento; si Analytics no responde, usar aggregations de PostgreSQL; si Report Builder falla, generar PDF basico local
- [ ] CA-11: Authentication: llamadas a AI agents incluyen API key en header X-API-Key; key rotada mensualmente, almacenada en Secrets Manager
- [ ] CA-12: Rate limiting outbound: maximo 50 calls/min al Depreciation Agent, 20 calls/min a Analytics, 10 calls/min a Report Builder; cola de espera si se excede

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Usar httpx (async) o requests-futures para HTTP calls
- Circuit breaker: pybreaker library
- SQS visibility timeout: 60s para valuation (agent puede tardar)
- Considerar gRPC si latencia HTTP es issue (futuro)

## Dependencias
- [MKT-BE-001] API Base Flask
- [MKT-INF-003] SQS queues creadas
- proj-back-ai-agents desplegado y operativo

## Epica Padre
[MKT-EP-004] Reportes Tecnicos, Valuacion & Evaluacion de Mercado
ISSUE_EOF
)"
echo "  Created: [MKT-INT-002]"
sleep 2

###############################################################################
# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 5: [MKT-EP-005] Flujo de Compra Intuitivo (Purchase Flow)
# ═══════════════════════════════════════════════════════════════════════════════
###############################################################################
echo ""
echo ">>> EPIC 5: Flujo de Compra Intuitivo (Purchase Flow)"

gh issue create --repo "$REPO" \
  --title "[MKT-EP-005] Flujo de Compra Intuitivo (Purchase Flow)" \
  --label "epic,priority-high,sprint-5" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Flujo de compra paso a paso super intuitivo, desde wishlist hasta confirmacion. Incluye favoritos con notificaciones, intencion de compra, reservacion temporal, maquina de estados, wizard multi-step, y tracking de proceso.

## Contexto Tecnico
- State machine: intent -> reserved -> kyc_pending -> financing -> insurance -> confirmed -> completed
- Reservacion temporal: 24-72h configurable con countdown
- KYC verification integrado
- Financiamiento y seguro opcionales (cotizaciones)
- Real-time tracking con WebSocket o polling

## Criterios de Aceptacion
- [ ] CA-01: Wishlist funcional con notificaciones de cambio precio
- [ ] CA-02: Flujo de compra multi-step guiado
- [ ] CA-03: Reservacion temporal con countdown
- [ ] CA-04: State machine con transiciones validas y audit log
- [ ] CA-05: KYC integration punto
- [ ] CA-06: Cotizacion de financiamiento integrada
- [ ] CA-07: Cotizacion de seguro integrada
- [ ] CA-08: Tracking de compra en tiempo real
- [ ] CA-09: Chat con vendedor
- [ ] CA-10: Cancelacion con reglas de negocio

## User Stories Contenidas
- [MKT-BE-011] API de Wishlist y Favoritos
- [MKT-BE-012] API de Intencion de Compra y Reservacion
- [MKT-BE-013] Motor de Estado de Compra (State Machine)
- [MKT-FE-011] Boton de Favoritos y Wishlist Page
- [MKT-FE-012] Wizard de Compra Multi-Step
- [MKT-FE-013] Pagina de Tracking de Compra

## Dependencias
- [MKT-EP-002] Autenticacion (usuario verificado)
- [MKT-EP-003] Catalogo (vehiculo seleccionado)
ISSUE_EOF
)"
echo "  Created: [MKT-EP-005]"
sleep 2

# ─── MKT-BE-011 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-011] API de Wishlist y Favoritos" \
  --label "user-story,backend,priority-high,sprint-5" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
CRUD de favoritos por usuario, notificaciones de cambio de precio y vehiculo vendido, y compartir lista de favoritos via link publico.

## Contexto Tecnico
### Endpoints:
```
GET    /api/users/me/favorites                    - Listar favoritos con paginacion
POST   /api/users/me/favorites                    - Agregar favorito {vehicle_id}
DELETE /api/users/me/favorites/:vehicleId          - Remover favorito
GET    /api/users/me/favorites/check/:vehicleId    - Verificar si es favorito
POST   /api/users/me/favorites/share               - Generar link compartible
GET    /api/favorites/shared/:shareId              - Ver lista compartida (publico)
GET    /api/users/me/favorites/alerts              - Listar alertas de favoritos
PUT    /api/users/me/favorites/alerts              - Configurar alertas
```

### Modelo:
```python
class UserFavorite:
    id: UUID
    user_id: UUID
    vehicle_id: UUID
    price_at_addition: Decimal     # precio cuando se agrego
    notify_price_change: bool      # default true
    notify_sold: bool              # default true
    price_threshold_pct: int       # notificar si baja X% (default 5)
    added_at: datetime

class FavoriteAlert:
    id: UUID
    favorite_id: UUID
    alert_type: str       # price_drop, price_increase, sold, back_in_stock
    old_value: str
    new_value: str
    is_read: bool
    created_at: datetime
```

## Criterios de Aceptacion
- [ ] CA-01: POST /api/users/me/favorites acepta {vehicle_id}, crea registro con precio actual del vehiculo; retorna 201; maximo 100 favoritos por usuario, 400 si excede con mensaje claro
- [ ] CA-02: GET /api/users/me/favorites retorna lista con datos del vehiculo (brand, model, year, price, current_price, image, status) + metadata favorito (added_at, price_change_since_added); paginado, sorteable por added_at o price
- [ ] CA-03: GET /api/users/me/favorites/check/:vehicleId retorna {is_favorite: true/false} en <50ms (cache Redis); usado por frontend para toggle de corazon
- [ ] CA-04: Cuando precio de un vehiculo cambia, worker compara con price_at_addition de todos los favoritos que lo contienen; si cambio >= price_threshold_pct, crea FavoriteAlert y publica a SNS
- [ ] CA-05: Cuando vehiculo se marca como sold/inactive, crea alerta para todos los usuarios que lo tienen en favoritos; incluye sugerencia de vehiculos similares
- [ ] CA-06: POST /api/users/me/favorites/share genera UUID unico como share_id, crea snapshot de la lista actual; GET /api/favorites/shared/:shareId retorna lista sin requerir auth (publico, read-only)
- [ ] CA-07: Alertas configurables por favorito: notify_price_change (on/off), notify_sold (on/off), price_threshold_pct (1-50%); PUT bulk update para todos los favoritos a la vez
- [ ] CA-08: GET /api/users/me/favorites/alerts retorna alertas no leidas primero, luego leidas; con filtro por tipo; mark as read individual o bulk; badge count endpoint para navbar
- [ ] CA-09: DELETE favorito es soft delete (para analytics de conversion: cuantos quitan favorito antes/despues de comprar); hard delete despues de 30 dias
- [ ] CA-10: Batch check: GET /api/users/me/favorites/check?vehicle_ids=id1,id2,id3 retorna mapa {id1: true, id2: false, id3: true}; util para listado de catalogo (saber cuales tienen corazon)
- [ ] CA-11: Analytics events publicados: favorite_added, favorite_removed, alert_generated, alert_read, shared_list_created, shared_list_viewed; para metricas de engagement
- [ ] CA-12: Cache: lista de favorite IDs en Redis set por user (TTL 5min) para check rapido; invalidar en add/remove; alerts count cacheado (TTL 1min)

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Redis SET para O(1) lookup de is_favorite
- SNS para fan-out de price change notifications a todos los favoritors
- Shared list es snapshot inmutable (no se actualiza si user modifica)
- Consider WebSocket para real-time alerts push

## Dependencias
- [MKT-BE-004] API de Perfiles (user context)
- [MKT-BE-005] API de Listado (vehicle data)

## Epica Padre
[MKT-EP-005] Flujo de Compra Intuitivo (Purchase Flow)
ISSUE_EOF
)"
echo "  Created: [MKT-BE-011]"
sleep 2

# ─── MKT-BE-012 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-012] API de Intencion de Compra y Reservacion" \
  --label "user-story,backend,priority-high,sprint-5" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
API para crear intencion de compra, reservar vehiculo temporalmente (24-72h), y gestionar el flujo de estados de la transaccion.

## Contexto Tecnico
### Endpoints:
```
POST   /api/purchases/intent              - Crear intencion de compra
GET    /api/purchases/:id                  - Obtener estado de compra
PUT    /api/purchases/:id/reserve          - Confirmar reservacion
PUT    /api/purchases/:id/cancel           - Cancelar compra
GET    /api/purchases/me                   - Mis compras (historial)
GET    /api/purchases/:id/requirements     - Documentos/pasos requeridos
PUT    /api/purchases/:id/kyc              - Enviar KYC data
PUT    /api/purchases/:id/financing        - Seleccionar financiamiento
PUT    /api/purchases/:id/insurance        - Seleccionar seguro
PUT    /api/purchases/:id/confirm          - Confirmar compra final
```

### Modelo:
```python
class Purchase:
    id: UUID
    user_id: UUID
    vehicle_id: UUID
    status: PurchaseStatus  # intent, reserved, kyc_pending, financing, insurance, confirmed, completed, cancelled, expired
    price_at_intent: Decimal
    reservation_expires_at: Optional[datetime]
    kyc_completed: bool
    financing_option_id: Optional[UUID]
    insurance_option_id: Optional[UUID]
    cancellation_reason: Optional[str]
    created_at: datetime
    updated_at: datetime

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
```

## Criterios de Aceptacion
- [ ] CA-01: POST /api/purchases/intent acepta {vehicle_id} y crea compra en estado INTENT con precio capturado; retorna 201 con {purchase_id, status, next_steps}; requiere auth, un solo intent activo por vehiculo por usuario
- [ ] CA-02: PUT /api/purchases/:id/reserve cambia estado a RESERVED, establece reservation_expires_at (configurable 24/48/72h por tipo de vehiculo); vehiculo se marca como reserved en catalogo; retorna countdown
- [ ] CA-03: Reservacion expira automaticamente: cron job cada minuto verifica reservaciones expiradas, cambia estado a EXPIRED, libera vehiculo en catalogo, notifica usuario via email y push
- [ ] CA-04: PUT /api/purchases/:id/cancel cambia estado a CANCELLED con cancellation_reason obligatorio; reglas: intent/reserved pueden cancelar libremente; kyc_pending o posterior puede tener penalizacion configurable
- [ ] CA-05: GET /api/purchases/:id/requirements retorna checklist dinamico de pasos pendientes: [{step: "kyc", status: "pending", required: true}, {step: "financing", status: "not_started", required: false}, {step: "insurance", status: "not_started", required: false}]
- [ ] CA-06: PUT /api/purchases/:id/kyc acepta datos de verificacion (INE/IFE foto frontal y trasera, selfie, comprobante domicilio); almacena en S3 encriptado; cambia estado a KYC_PENDING -> procesamiento async -> KYC_APPROVED/KYC_REJECTED
- [ ] CA-07: PUT /api/purchases/:id/financing acepta {financing_option_id} de opciones pre-cotizadas; vincula financiamiento a la compra; campo opcional (puede comprar sin financiamiento)
- [ ] CA-08: PUT /api/purchases/:id/insurance acepta {insurance_option_id}; vincula seguro; opcional pero recomendado
- [ ] CA-09: PUT /api/purchases/:id/confirm solo valida si KYC aprobado; cambia estado a CONFIRMED; publica evento purchase-confirmed a SNS; genera numero de orden
- [ ] CA-10: GET /api/purchases/me retorna historial de compras del usuario con status, vehiculo info basica, fecha; filtro por status; paginado
- [ ] CA-11: Concurrencia: si dos usuarios intentan reservar mismo vehiculo, primero en ejecutar reserve gana; segundo recibe 409 Conflict con "Vehiculo ya reservado"; usar lock optimista en DB
- [ ] CA-12: Eventos publicados a SNS para cada transicion: purchase_created, vehicle_reserved, kyc_submitted, financing_selected, purchase_confirmed, purchase_cancelled, reservation_expired; para tracking y analytics

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Lock optimista: version column en vehicles, check en UPDATE ... WHERE version = expected_version
- KYC docs en S3 con encryption SSE-KMS, acceso solo desde backend
- Cron para expiracion: APScheduler o Celery beat, cada minuto
- Idempotency key en POST intent para evitar duplicados

## Dependencias
- [MKT-BE-003] Autenticacion
- [MKT-BE-007] Detalle de Vehiculo
- [MKT-BE-013] Motor de Estado

## Epica Padre
[MKT-EP-005] Flujo de Compra Intuitivo (Purchase Flow)
ISSUE_EOF
)"
echo "  Created: [MKT-BE-012]"
sleep 2

# ─── MKT-BE-013 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-BE-013] Motor de Estado de Compra (State Machine)" \
  --label "user-story,backend,priority-high,sprint-5" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Maquina de estados para el flujo de compra con transiciones validas, validaciones por transicion, audit log completo, webhooks para notificar cambios, y timeout automatico para reservaciones.

## Contexto Tecnico
### State machine diagram:
```
INTENT --> RESERVED --> KYC_PENDING --> FINANCING --> INSURANCE --> CONFIRMED --> COMPLETED
  |           |             |              |             |             |
  +--> CANCELLED <----------+--------------+-------------+             |
  |                                                                     |
  |           +-- EXPIRED (auto, timeout)                               |
  |           |                                                         |
  +-----------+                                                         |
                                                                        +--> COMPLETED
```

### Transiciones validas:
```python
TRANSITIONS = {
    'INTENT':       ['RESERVED', 'CANCELLED'],
    'RESERVED':     ['KYC_PENDING', 'CANCELLED', 'EXPIRED'],
    'KYC_PENDING':  ['FINANCING', 'INSURANCE', 'CONFIRMED', 'CANCELLED'],
    'FINANCING':    ['INSURANCE', 'CONFIRMED', 'CANCELLED'],
    'INSURANCE':    ['CONFIRMED', 'CANCELLED'],
    'CONFIRMED':    ['COMPLETED', 'CANCELLED'],
    'COMPLETED':    [],  # terminal
    'CANCELLED':    [],  # terminal
    'EXPIRED':      [],  # terminal
}
```

## Criterios de Aceptacion
- [ ] CA-01: State machine implementada como domain service con metodo transition(purchase_id, target_state, metadata) que valida transicion, ejecuta guards, actualiza estado, y emite evento
- [ ] CA-02: Guards por transicion: INTENT->RESERVED requiere vehiculo disponible; RESERVED->KYC_PENDING no requiere nada; *->CONFIRMED requiere KYC aprobado; cada guard es un callable registrado
- [ ] CA-03: Audit log en tabla purchase_state_log: {id, purchase_id, from_state, to_state, triggered_by (user_id o "system"), metadata (JSON), ip_address, timestamp}; inmutable, append-only
- [ ] CA-04: Transition hooks: pre_transition (validaciones, side effects como reservar vehiculo), post_transition (notificaciones, analytics); hooks registrados por transicion especifica
- [ ] CA-05: Webhooks configurables: cada transicion puede trigger webhook a URL registrada con payload {purchase_id, from_state, to_state, timestamp, vehicle_id, user_id}; retry 3 veces con backoff
- [ ] CA-06: Timeout automatico para RESERVED: scheduler verifica cada minuto, si reservation_expires_at < now(), ejecuta transition a EXPIRED; publica evento; libera vehiculo
- [ ] CA-07: Concurrency safe: transiciones usan SELECT ... FOR UPDATE en purchase row para evitar race conditions; si dos transiciones compiten, una falla con ConflictError
- [ ] CA-08: GET /api/purchases/:id/transitions retorna lista de transiciones disponibles desde estado actual con: [{target_state, label, description, requirements_met: bool, missing_requirements: [...]}]
- [ ] CA-09: Bulk operations para admin: POST /api/admin/purchases/bulk-transition acepta lista de purchase_ids y target_state; util para completar multiples compras a la vez
- [ ] CA-10: Metricas de state machine: tiempo promedio en cada estado, tasa de conversion por step (funnel), tasa de cancelacion por estado, motivos de cancelacion top; publicadas a CloudWatch
- [ ] CA-11: State machine configurable: transiciones, guards, timeouts definidos en config (no hardcoded) para poder ajustar flujo sin deploy; config versionada
- [ ] CA-12: Rollback support: admin endpoint para revertir ultimo cambio de estado en casos excepcionales; requiere role admin + justificacion; registrado en audit log como "manual_rollback"

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Considerar library: python-statemachine o transitions
- FOR UPDATE con timeout para evitar deadlocks
- Audit log puede crecer rapido, particionar por mes
- Guards deben ser idempotentes (pueden ejecutarse multiples veces)

## Dependencias
- [MKT-BE-012] API de Intencion de Compra
- [MKT-BE-001] API Base Flask (domain services)

## Epica Padre
[MKT-EP-005] Flujo de Compra Intuitivo (Purchase Flow)
ISSUE_EOF
)"
echo "  Created: [MKT-BE-013]"
sleep 2

# ─── MKT-FE-011 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-011] Boton de Favoritos y Wishlist Page" \
  --label "user-story,frontend,priority-high,sprint-5" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Heart icon toggle en cards y detalle, wishlist page con grid de favoritos, filtros, badge contador en navbar, y notificaciones de cambio de precio.

## Contexto Tecnico
FavoritesStore signal que mantiene Set de vehicle IDs favoritos. Sync con backend on init. Optimistic UI para toggle inmediato.

## Criterios de Aceptacion
- [ ] CA-01: Heart icon en vehicle cards (esquina superior derecha) y detalle page (junto al precio): outline cuando no favorito, filled rojo cuando favorito; click toglea con animacion scale+color (heart beat)
- [ ] CA-02: Optimistic UI: al click, update inmediato del icono localmente; si API falla, revertir con toast de error "No se pudo guardar favorito"; debounce de 300ms para evitar double-click
- [ ] CA-03: Si usuario no autenticado clickea favorito, mostrar modal "Inicia sesion para guardar favoritos" con botones Login y Registrarse; post-login, agregar el favorito automaticamente
- [ ] CA-04: Badge contador en navbar: icono corazon con numero de favoritos (rojo si hay alertas no leidas); click navega a /favorites; badge animado al agregar nuevo favorito
- [ ] CA-05: Wishlist page (/favorites): grid de vehicle cards (mismo componente que catalogo) con estado favorito ya marcado; empty state con ilustracion y CTA "Explorar vehiculos"
- [ ] CA-06: Filtros en wishlist: por marca (dropdown multi-select), rango de precio, status (disponible/vendido/reservado); sort por fecha agregado (default), precio, cambio de precio
- [ ] CA-07: Indicadores de cambio de precio en cards de wishlist: badge verde "Bajo $X" o rojo "Subio $X" con porcentaje de cambio desde que se agrego a favoritos
- [ ] CA-08: Alertas de favoritos: bell icon en wishlist header con dropdown de alertas recientes (precio bajo, vehiculo vendido); click en alerta navega al vehiculo; mark as read
- [ ] CA-09: Accion "Compartir mi lista": boton que genera link publico; muestra modal con link copiable, botones WhatsApp/social share; preview del link compartido
- [ ] CA-10: Bulk actions: checkbox en cada card, barra de acciones bulk aparece con "Remover seleccionados" y "Comparar seleccionados"; select all checkbox
- [ ] CA-11: Responsive: mobile cards full-width 1 col, alertas como bottom sheet, filtros como modal; tablet 2 cols; desktop 3-4 cols con sidebar filtros
- [ ] CA-12: FavoritesStore inicializa cargando GET /api/users/me/favorites/check?vehicle_ids=... para vehiculos visibles en pantalla; cache en memory signal; sync completo en background al login

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Heart animation: CSS keyframes con scale(1.3) + color transition
- FavoritesStore: signal(Set<string>) con add/remove/has methods
- Batch check on catalog load para saber cuales marcar
- Web Share API para mobile native share dialog

## Dependencias
- [MKT-FE-005] Catalogo (vehicle cards)
- [MKT-FE-007] Detalle (heart en detalle)
- [MKT-BE-011] API Wishlist

## Epica Padre
[MKT-EP-005] Flujo de Compra Intuitivo (Purchase Flow)
ISSUE_EOF
)"
echo "  Created: [MKT-FE-011]"
sleep 2

# ─── MKT-FE-012 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-012] Wizard de Compra Multi-Step" \
  --label "user-story,frontend,priority-high,sprint-6" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Wizard de compra de 5 pasos: resumen vehiculo, KYC, financiamiento, seguro, confirmacion. Progress bar, save and continue, mobile optimized.

## Contexto Tecnico
Route: /purchase/:vehicleId. Standalone component con child routes por step. PurchaseStore signal con estado de cada paso. Backend state machine dicta pasos disponibles.

### Steps:
1. Resumen vehiculo + confirmar interes -> crea purchase intent
2. KYC (si no verificado) -> upload docs
3. Financiamiento (opcional) -> seleccionar plan
4. Seguro (opcional) -> seleccionar poliza
5. Confirmacion final -> resumen total + confirmar

## Criterios de Aceptacion
- [ ] CA-01: Step 1 - Resumen: imagen principal vehiculo, specs clave (marca, modelo, ano, km, transmision), precio destacado, valuacion de mercado (badge si es buen precio), boton "Confirmar Interes" que llama POST /api/purchases/intent
- [ ] CA-02: Step 2 - KYC: si usuario ya verificado, skip automatico con checkmark; si no, formulario: upload INE frontal/trasera (drag-drop o camera capture), selfie con liveness check placeholder, comprobante domicilio; progress bar de upload; submit llama PUT /api/purchases/:id/kyc
- [ ] CA-03: Step 3 - Financiamiento: cards con opciones de credito pre-cotizadas (banco, tasa, plazo, mensualidad, CAT); tabla comparativa; slider de enganche (10%-50%); opcion "Pagar de contado" prominente; seleccionar llama PUT /api/purchases/:id/financing
- [ ] CA-04: Step 4 - Seguro: cards con polizas disponibles (aseguradora, cobertura, prima anual, deducible); comparativa de coberturas; opcion "Lo contrato despues"; seleccionar llama PUT /api/purchases/:id/insurance
- [ ] CA-05: Step 5 - Confirmacion: resumen completo (vehiculo, precio, financiamiento seleccionado, seguro seleccionado, total), checkbox "Acepto terminos y condiciones" (link a PDF), boton "Confirmar Compra" grande verde; llama PUT /api/purchases/:id/confirm
- [ ] CA-06: Progress bar horizontal: 5 steps con iconos y labels, step actual resaltado, steps completados con checkmark verde, steps futuros en gris; click en step completado permite volver
- [ ] CA-07: Save and continue: estado de cada step guardado en backend (via API calls); si usuario abandona y vuelve, retoma donde quedo; banner "Tienes una compra en progreso" en detalle del vehiculo
- [ ] CA-08: Countdown timer visible cuando vehiculo esta reservado: "Reserva expira en 23:45:12" con formato HH:MM:SS; warning visual cuando < 1 hora; expiracion redirige a pagina informativa
- [ ] CA-09: Validaciones por step: Step 1 requiere auth; Step 2 requiere docs completos; Step 3/4 opcionales; Step 5 requiere KYC aprobado + terminos aceptados; boton siguiente disabled si validacion no pasa
- [ ] CA-10: Mobile optimized: steps como cards verticales con scroll, formularios full-width, uploads con camera capture nativo, bottom bar sticky con boton "Siguiente" y precio total
- [ ] CA-11: Error handling: si API falla en cualquier step, mostrar error inline con retry; si vehiculo ya no disponible, mostrar modal con sugerencias de similares; si reserva expiro, informar y sugerir re-intentar
- [ ] CA-12: Analytics de funnel: trackear entrada a cada step, tiempo en cada step, abandonos por step, completion rate; eventos: purchase_step_viewed, purchase_step_completed, purchase_abandoned

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Cada step es lazy-loaded child route de /purchase/:vehicleId
- PurchaseStore signal: {purchaseId, currentStep, vehicleData, kycStatus, financingOption, insuranceOption}
- File upload: presigned URLs de S3 para upload directo
- Countdown: setInterval con signal update cada segundo
- Route guard: CanDeactivate para confirmar si tiene cambios sin guardar

## Dependencias
- [MKT-FE-007] Detalle de Vehiculo (navegacion)
- [MKT-BE-012] API de Compra
- [MKT-BE-013] Motor de Estado

## Epica Padre
[MKT-EP-005] Flujo de Compra Intuitivo (Purchase Flow)
ISSUE_EOF
)"
echo "  Created: [MKT-FE-012]"
sleep 2

# ─── MKT-FE-013 ────────────────────────────────────────────────────────────
gh issue create --repo "$REPO" \
  --title "[MKT-FE-013] Pagina de Tracking de Compra" \
  --label "user-story,frontend,priority-high,sprint-6" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Pagina de tracking del proceso de compra: timeline visual, estado actual con detalle, documentos requeridos/completados, chat con vendedor, y countdown para reservaciones.

## Contexto Tecnico
Route: /purchases/:purchaseId/tracking. Polling cada 30s para actualizar estado (o WebSocket en futuro). Accesible desde dashboard de usuario seccion "Mis Compras".

## Criterios de Aceptacion
- [ ] CA-01: Timeline vertical prominente: cada estado como nodo circular con icono, label, timestamp; estado actual pulsante con color primario; estados completados en verde con check; futuros en gris; linea conectora entre nodos
- [ ] CA-02: Estado actual detallado: card grande con icono, titulo del estado, descripcion de que esta pasando, que se espera del usuario (accion requerida si la hay), y estimado de tiempo para siguiente estado
- [ ] CA-03: Documentos checklist: lista de documentos requeridos con status (pendiente, subido, verificado, rechazado); boton "Subir" para pendientes; icono de estado por documento; mensaje de rechazo si aplica con opcion re-subir
- [ ] CA-04: Seccion vehiculo: mini card del vehiculo comprado (imagen, marca, modelo, ano, precio acordado) siempre visible como referencia; link a detalle del vehiculo
- [ ] CA-05: Chat con vendedor: widget de chat embebido (estilo Intercom/WhatsApp); mensajes de texto, enviar imagenes; historial de conversacion; indicador "en linea"/"visto hace X min"; notificacion de nuevo mensaje
- [ ] CA-06: Countdown para reservacion: si estado es RESERVED, timer prominente con formato dias:horas:minutos:segundos; barra de progreso visual; warning styling cuando <2 horas; alerta cuando <30 minutos
- [ ] CA-07: Acciones contextuales por estado: RESERVED muestra "Continuar con KYC" boton; KYC_PENDING muestra "Subir documentos faltantes"; CONFIRMED muestra "Descargar comprobante"; cada estado tiene CTA diferente
- [ ] CA-08: Historial de transiciones: seccion colapsable con log de todos los cambios de estado (fecha, hora, de->a, detalle); util para transparencia y dispute resolution
- [ ] CA-09: Notificaciones push: cuando estado cambia, usuario recibe notificacion (browser push si permitido, email siempre); al abrir tracking, marca notificaciones como leidas
- [ ] CA-10: Cancelacion: boton "Cancelar compra" visible en estados cancelables; click abre modal de confirmacion con select de motivo (cambio de opinion, encontre mejor opcion, problemas financieros, otro+texto); submit llama cancel API
- [ ] CA-11: Responsive: mobile timeline horizontal scrolleable o vertical compacto, chat fullscreen, documentos como cards apiladas; tablet layout 2 columnas (timeline+estado izq, docs+chat der); desktop 3 columnas
- [ ] CA-12: Share status: boton "Compartir progreso" genera imagen/card con estado actual para compartir via WhatsApp (util para informar a familia); sin datos sensibles, solo estado general

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos

## Notas Tecnicas
- Polling: HttpClient interval con switchMap cada 30s; consider SSE (Server-Sent Events) para real-time
- Chat: puede ser WebSocket custom o integracion con servicio externo (SendBird, PubNub, custom con SQS)
- Push notifications: Web Push API con service worker
- Timeline component: custom SVG o CSS con flexbox vertical

## Dependencias
- [MKT-FE-012] Wizard de Compra
- [MKT-BE-012] API de Compra (GET status)
- [MKT-BE-013] Motor de Estado (transiciones)

## Epica Padre
[MKT-EP-005] Flujo de Compra Intuitivo (Purchase Flow)
ISSUE_EOF
)"
echo "  Created: [MKT-FE-013]"
sleep 2

###############################################################################
# DONE
###############################################################################
echo ""
echo "========================================="
echo "  ALL ISSUES CREATED SUCCESSFULLY!"
echo "========================================="
echo ""
echo "Summary:"
echo "  - 5 Epics created"
echo "  - 5 Infrastructure/Integration stories"
echo "  - 10 Backend stories"
echo "  - 9 Frontend stories"
echo "  - 2 Integration stories"
echo "  - Total: 31 issues"
echo ""
echo "Labels: 18 created"
echo ""
echo "Done!"
