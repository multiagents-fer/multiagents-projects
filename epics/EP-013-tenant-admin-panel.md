# [MKT-EP-013] Panel de Administracion por Tenant (Tenant Admin)

**Sprint**: 11-12
**Priority**: Priority 2
**Epic Owner**: Tech Lead
**Estimated Points**: 105
**Teams**: Backend, Frontend

---

## Resumen del Epic

Este epic implementa el panel de administracion dedicado para cada tenant. Cada tenant tiene su propio dashboard con KPIs, gestion de inventario de vehiculos, gestion de equipo (invitar/remover miembros, asignar roles), y configuracion self-service de su branding. El panel esta branded con el tema del tenant y restringe el acceso solo a datos del tenant actual. Los roles tenant_admin y tenant_owner tienen acceso completo, mientras que editor y viewer tienen acceso limitado.

## Dependencias Externas

- EP-011 completado (arquitectura multi-tenant funcional)
- EP-012 completado (theme engine aplicando branding del tenant)
- SVC-ADM existente (EP-009) como base para extensiones
- AWS S3 para upload de imagenes de vehiculos
- SQS para notificaciones de invitaciones de equipo

---

## User Story 1: [MKT-BE-038][SVC-ADM-API] API Admin Scoped por Tenant

### Descripcion

Como servicio de administracion, necesito que todos los endpoints admin existentes se filtren automaticamente por tenant_id del request. Un tenant admin que consulta /admin/dashboard ve solo sus KPIs, /admin/vehicles retorna solo sus vehiculos, y /admin/users retorna solo su equipo. El filtrado es transparente: el tenant_id viene en el JWT y el middleware lo inyecta en todas las queries. Ademas, se introduce el rol tenant_admin que tiene permisos diferentes al super_admin de AgentsMX.

### Microservicio

- **Nombre**: SVC-ADM (extension del servicio existente)
- **Puerto**: 5020
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0
- **Base de datos**: PostgreSQL 15 (con RLS habilitado), Redis 7
- **Patron**: Hexagonal Architecture - Application & API Layer Extension

### Contexto Tecnico

#### Endpoints Existentes Modificados (Scoped por Tenant)

```
# Dashboard (ahora scoped por tenant_id del JWT)
GET  /api/v1/admin/dashboard              -> KPIs del tenant actual
GET  /api/v1/admin/dashboard/charts       -> Charts del tenant actual

# Vehicles (ahora scoped)
GET  /api/v1/admin/vehicles               -> Vehiculos del tenant actual
GET  /api/v1/admin/vehicles/:id           -> Detalle (solo si es del tenant)
POST /api/v1/admin/vehicles               -> Crear (auto-asigna tenant_id)
PUT  /api/v1/admin/vehicles/:id           -> Actualizar (solo si es del tenant)
DEL  /api/v1/admin/vehicles/:id           -> Eliminar (solo si es del tenant)

# Users (ahora scoped)
GET  /api/v1/admin/users                  -> Usuarios del tenant actual
GET  /api/v1/admin/users/:id              -> Detalle (solo si es del tenant)

# Super Admin Only (nuevo guard)
GET  /api/v1/admin/tenants/**             -> SOLO super_admin (403 para tenant_admin)
GET  /api/v1/admin/global/**              -> SOLO super_admin
```

#### Middleware de Tenant Scoping

```python
# api/middleware/tenant_scope_middleware.py
from flask import request, g, abort
from functools import wraps

def tenant_scoped(f):
    """Decorator that ensures all queries are scoped to current tenant."""
    @wraps(f)
    def decorated(*args, **kwargs):
        tenant_id = request.headers.get('X-Tenant-ID')
        if not tenant_id:
            abort(400, "Missing tenant context")

        # Set PostgreSQL session variable for RLS
        db.session.execute(
            text("SET app.current_tenant_id = :tid"),
            {"tid": tenant_id}
        )
        g.tenant_id = tenant_id
        return f(*args, **kwargs)
    return decorated

def require_role(*roles):
    """Decorator that validates user role from JWT."""
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            user_role = request.headers.get('X-User-Roles', '')
            tenant_role = request.headers.get('X-Tenant-Role', '')

            # Super admin can do everything
            if 'super_admin' in user_role:
                return f(*args, **kwargs)

            # Check tenant-specific role
            if not any(r in tenant_role for r in roles):
                abort(403, f"Required role: {', '.join(roles)}")

            return f(*args, **kwargs)
        return decorated
    return decorator
```

#### Dashboard KPIs Response (Tenant Scoped)

```json
// GET /api/v1/admin/dashboard
// X-Tenant-ID: f47ac10b-58cc-4372-a567-0e02b2c3d479
// Response 200
{
  "data": {
    "tenant": {
      "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "name": "Mi Autos Puebla",
      "plan": "pro"
    },
    "kpis": {
      "vehicles": {
        "total": 234,
        "active": 210,
        "draft": 15,
        "sold": 9,
        "limit": null,
        "change_7d": +12
      },
      "users": {
        "registered": 1520,
        "active_30d": 340,
        "new_7d": 45
      },
      "transactions": {
        "total_month": 8,
        "revenue_month_mxn": 2450000.00,
        "avg_ticket_mxn": 306250.00,
        "change_vs_prev_month_percent": 15.3
      },
      "engagement": {
        "page_views_7d": 12500,
        "unique_visitors_7d": 3200,
        "favorites_7d": 89,
        "inquiries_7d": 34,
        "avg_time_on_site_seconds": 195
      }
    },
    "alerts": [
      {
        "type": "warning",
        "message": "3 vehiculos tienen mas de 90 dias sin actualizar precio",
        "action_url": "/admin/vehicles?stale=true"
      }
    ]
  }
}
```

#### Role Hierarchy

```python
# dom/models/value_objects.py
from enum import Enum

class AdminRole(Enum):
    SUPER_ADMIN = "super_admin"     # AgentsMX global admin
    TENANT_OWNER = "tenant_owner"   # Owner of a specific tenant
    TENANT_ADMIN = "tenant_admin"   # Admin of a specific tenant
    TENANT_EDITOR = "tenant_editor" # Can manage inventory
    TENANT_VIEWER = "tenant_viewer" # Read-only access

# Permission matrix
ROLE_PERMISSIONS = {
    "super_admin": ["*"],  # All permissions globally
    "tenant_owner": [
        "dashboard.view", "vehicles.manage", "vehicles.create", "vehicles.delete",
        "users.manage", "users.invite", "users.remove",
        "branding.edit", "features.view", "billing.view", "billing.manage",
        "analytics.view", "reports.view", "settings.edit",
    ],
    "tenant_admin": [
        "dashboard.view", "vehicles.manage", "vehicles.create", "vehicles.delete",
        "users.manage", "users.invite",
        "branding.edit", "features.view", "billing.view",
        "analytics.view", "reports.view",
    ],
    "tenant_editor": [
        "dashboard.view", "vehicles.manage", "vehicles.create",
        "analytics.view",
    ],
    "tenant_viewer": [
        "dashboard.view", "vehicles.view",
        "analytics.view",
    ],
}
```

### Criterios de Aceptacion

1. **AC-001**: GET /api/v1/admin/dashboard retorna KPIs exclusivamente del tenant actual. Un tenant con 234 vehiculos ve "total: 234", no los 11,000+ globales. Los KPIs incluyen: vehiculos (total/active/draft/sold/limit/change_7d), usuarios (registered/active_30d/new_7d), transacciones (total_month/revenue/avg_ticket/change_vs_prev), engagement (page_views/visitors/favorites/inquiries/avg_time).

2. **AC-002**: GET /api/v1/admin/vehicles retorna solo vehiculos donde tenant_id coincide con el del JWT. Soporta paginacion (cursor-based, page_size default 20), filtrado por status (active/draft/sold/archived), busqueda por make/model/vin, y ordenamiento por created_at/price/views. El response incluye visibility (tenant_only/agentsmx_only/both).

3. **AC-003**: POST /api/v1/admin/vehicles auto-asigna el tenant_id del JWT al vehiculo creado. El tenant_admin no puede especificar un tenant_id diferente en el body (se ignora). El vehiculo se crea con la visibility default del tenant (configurada en TenantConfig.default_vehicle_visibility).

4. **AC-004**: PUT /api/v1/admin/vehicles/:id valida que el vehiculo pertenezca al tenant actual. Si un tenant_admin intenta actualizar un vehiculo de otro tenant, retorna 404 (no 403, para no revelar existencia). La RLS de PostgreSQL como segunda barrera previene lectura de datos cross-tenant.

5. **AC-005**: El middleware tenant_scoped ejecuta SET app.current_tenant_id = :tid en cada request para activar RLS. Si el header X-Tenant-ID esta ausente, retorna 400. Si el tenant_id del header no coincide con el del JWT, retorna 403 "Tenant context mismatch".

6. **AC-006**: Los roles tenant_owner, tenant_admin, tenant_editor, tenant_viewer se evaluan desde el JWT claim custom:tenant_role. La jerarquia es: owner > admin > editor > viewer. Un admin puede hacer todo lo que un editor puede, mas gestion de usuarios y branding.

7. **AC-007**: Las rutas /api/v1/admin/tenants/** solo son accesibles para super_admin. Un tenant_admin que intenta acceder recibe 403 con mensaje "Acceso restringido a super administradores". Las rutas /api/v1/admin/global/** (metricas globales, revenue global) tambien requieren super_admin.

8. **AC-008**: El super_admin puede hacer "impersonate" de un tenant: GET /api/v1/admin/dashboard con header X-Tenant-ID de cualquier tenant retorna los KPIs de ese tenant. Esto permite al equipo de AgentsMX dar soporte a tenants viendo sus datos. Se registra en audit log cada impersonation.

9. **AC-009**: El response del dashboard incluye "alerts" contextauales: vehiculos con precio no actualizado en 90+ dias, uso cercano al limite del plan (>80% vehiculos o usuarios), certificado SSL proximo a expirar, pago pendiente. Maximo 5 alerts ordenados por prioridad.

10. **AC-010**: Los tests de integracion verifican aislamiento total: crean 2 tenants con datos diferentes, hacen requests como cada tenant_admin, y validan que cada uno ve solo sus datos. Un test especifico intenta acceder a un vehiculo de otro tenant y verifica que retorna 404.

11. **AC-011**: El endpoint GET /api/v1/admin/dashboard/charts retorna datos para graficos scoped al tenant: vehiculos por estado (pie chart), transacciones por dia (line chart ultimos 30 dias), top 5 vehiculos mas vistos (bar chart), fuentes de trafico (donut chart). Formato compatible con Chart.js.

12. **AC-012**: El performance de los endpoints admin scoped es comparable al sin scoping: la adicion de SET app.current_tenant_id y RLS no agrega mas de 5ms de latencia por request. Se verifica con benchmark de 100 requests al dashboard.

### Definition of Done

- [ ] Todos los endpoints admin existentes scoped por tenant_id
- [ ] Middleware tenant_scoped implementado y aplicado
- [ ] RLS verificado como segunda barrera de aislamiento
- [ ] Role hierarchy implementada con permission matrix
- [ ] KPIs del dashboard calculados correctamente por tenant
- [ ] Alerts contextuales funcionales
- [ ] Tests de integracion de aislamiento entre tenants
- [ ] Performance benchmark documentado
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- SET app.current_tenant_id debe ejecutarse al inicio de cada request, no una vez por conexion (connection pooling)
- Si el pool de conexiones reutiliza conexiones, el SET del request anterior podria quedar activo; siempre resetear al inicio
- Considerar usar SQLAlchemy event listeners (after_begin) para setear automaticamente
- El impersonate de super_admin debe tener rate limiting especifico y audit trail estricto
- Los alerts se calculan con queries ligeras; considerar pre-calcularlos en un job periodico si son costosos

### Dependencias

- EP-011 completado (tenant_id en todas las tablas, RLS habilitado)
- EP-009 completado (panel admin base)
- SVC-ADM existente como base
- JWT con claims custom:tenant_id y custom:tenant_role

---

## User Story 2: [MKT-FE-031][FE-FEAT-ADM] Dashboard Admin del Tenant

### Descripcion

Como tenant admin, necesito un dashboard de administracion que muestre las metricas clave de mi white label: vehiculos publicados vs limite del plan, usuarios registrados, transacciones y revenue del mes, engagement (visitas, favoritos, consultas). El dashboard debe estar branded con el tema de mi tenant y solo mostrar mis datos. Debe incluir graficos interactivos y alertas accionables.

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
      dashboard/
        domain/
          models/
            dashboard-kpis.model.ts       # KPI interfaces
            dashboard-chart.model.ts      # Chart data interfaces
            dashboard-alert.model.ts      # Alert interface
          ports/
            dashboard-data.port.ts        # Abstract class
        application/
          services/
            dashboard.service.ts          # Orchestration
          use-cases/
            load-dashboard.use-case.ts    # Load all dashboard data
        infrastructure/
          adapters/
            dashboard-api.adapter.ts      # HTTP calls
        presentation/
          pages/
            dashboard-home/
              dashboard-home.page.ts
              dashboard-home.page.html
              dashboard-home.page.spec.ts
          components/
            kpi-card/
              kpi-card.component.ts
              kpi-card.component.html
              kpi-card.component.spec.ts
            usage-bar/
              usage-bar.component.ts       # Plan usage progress bar
              usage-bar.component.html
              usage-bar.component.spec.ts
            revenue-chart/
              revenue-chart.component.ts
              revenue-chart.component.html
              revenue-chart.component.spec.ts
            vehicle-status-chart/
              vehicle-status-chart.component.ts
              vehicle-status-chart.component.html
              vehicle-status-chart.component.spec.ts
            alert-card/
              alert-card.component.ts
              alert-card.component.html
              alert-card.component.spec.ts
            top-vehicles-table/
              top-vehicles-table.component.ts
              top-vehicles-table.component.html
              top-vehicles-table.component.spec.ts
```

#### KPI Card Component

```typescript
// presentation/components/kpi-card/kpi-card.component.ts
@Component({
  selector: 'app-kpi-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="bg-white rounded-theme shadow-sm border border-gray-100 p-6
                hover:shadow-md transition-shadow">
      <div class="flex items-center justify-between mb-4">
        <div class="p-2 rounded-lg" [style.background-color]="iconBgColor()">
          <svg class="w-5 h-5" [style.color]="iconColor()">
            <!-- dynamic icon -->
          </svg>
        </div>
        @if (change() !== null) {
          <span class="text-xs font-medium px-2 py-1 rounded-full"
                [class.bg-green-100]="change()! > 0"
                [class.text-green-700]="change()! > 0"
                [class.bg-red-100]="change()! < 0"
                [class.text-red-700]="change()! < 0"
                [class.bg-gray-100]="change()! === 0"
                [class.text-gray-700]="change()! === 0">
            {{ change()! > 0 ? '+' : '' }}{{ change() }}%
          </span>
        }
      </div>
      <div class="text-2xl font-heading font-bold text-gray-900">
        {{ formattedValue() }}
      </div>
      <div class="text-sm text-gray-500 mt-1">{{ label() }}</div>
      @if (limit() !== null) {
        <div class="mt-3">
          <app-usage-bar
            [current]="numericValue()"
            [max]="limit()!"
          />
        </div>
      }
    </div>
  `,
})
export class KpiCardComponent {
  readonly label = input.required<string>();
  readonly value = input.required<number>();
  readonly format = input<'number' | 'currency' | 'percent'>('number');
  readonly change = input<number | null>(null);
  readonly limit = input<number | null>(null);
  readonly iconBgColor = input<string>('var(--color-primary-light)');
  readonly iconColor = input<string>('var(--color-primary)');

  readonly numericValue = computed(() => this.value());
  readonly formattedValue = computed(() => {
    const v = this.value();
    switch (this.format()) {
      case 'currency': return `$${v.toLocaleString('es-MX')} MXN`;
      case 'percent': return `${v.toFixed(1)}%`;
      default: return v.toLocaleString('es-MX');
    }
  });
}
```

#### Dashboard Home Page

```typescript
// presentation/pages/dashboard-home/dashboard-home.page.ts
@Component({
  selector: 'app-dashboard-home',
  standalone: true,
  imports: [
    KpiCardComponent, UsageBarComponent, RevenueChartComponent,
    VehicleStatusChartComponent, AlertCardComponent, TopVehiclesTableComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './dashboard-home.page.html',
})
export class DashboardHomePage {
  private readonly dashboardSvc = inject(DashboardService);
  private readonly themeEngine = inject(ThemeEngineService);

  readonly tenantName = this.themeEngine.tenantName;
  readonly data = this.dashboardSvc.dashboardData;
  readonly isLoading = this.dashboardSvc.isLoading;
  readonly error = this.dashboardSvc.error;

  constructor() {
    this.dashboardSvc.loadDashboard();
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: El dashboard muestra 4 KPI cards principales en una row de grid responsive (4 columnas en desktop, 2 en tablet, 1 en mobile): Vehiculos Activos (con barra de uso vs limite), Usuarios Registrados, Revenue del Mes (formato moneda MXN), Transacciones del Mes. Cada card muestra el valor, label, y cambio porcentual vs periodo anterior.

2. **AC-002**: Las KPI cards muestran un indicador de tendencia: badge verde con flecha arriba si el cambio es positivo, badge rojo con flecha abajo si es negativo, badge gris si es cero. El cambio se calcula vs los 7 dias anteriores para vehiculos/usuarios y vs el mes anterior para revenue/transacciones.

3. **AC-003**: La barra de uso (UsageBar) se muestra debajo de KPIs que tienen limite (vehiculos y usuarios). Muestra current/max con formato "210 / 500 vehiculos". La barra es verde < 60%, amarilla 60-80%, roja > 80%. Si el tenant tiene plan unlimited, no se muestra la barra.

4. **AC-004**: El grafico de Revenue (line chart) muestra los ultimos 30 dias con revenue diario en MXN. Usa Chart.js con el color primario del tenant. Al hacer hover sobre un punto, muestra tooltip con fecha y monto. Incluye linea punteada de tendencia.

5. **AC-005**: El grafico de Vehiculos por Estado (donut chart) muestra la distribucion: Activos (verde), Draft (gris), Vendidos (azul), Archivados (naranja). Al hacer click en un segmento, navega a /admin/vehicles?status=xxx.

6. **AC-006**: La tabla Top 5 Vehiculos muestra los vehiculos mas vistos del tenant con columnas: imagen thumbnail, titulo (make model year), precio, vistas (7 dias), favoritos, estado. Click en una fila navega al detalle del vehiculo en admin.

7. **AC-007**: Las alertas se muestran como cards en la parte inferior del dashboard con icono, mensaje, y boton de accion. Maximo 5 alertas visibles. Tipos: warning (amarillo), info (azul), error (rojo). Click en el boton navega a la URL de accion.

8. **AC-008**: El dashboard se carga completamente en menos de 2 segundos. Se muestra un skeleton loader (shimmer) mientras los datos se cargan. Si la API falla, se muestra un mensaje de error con boton "Reintentar".

9. **AC-009**: El dashboard esta completamente branded con el tema del tenant: colores de graficos usan primary/secondary/accent, fonts usan font-heading para titulos, border-radius usa el valor del tema, cards usan el shadow del tema. Se verifica visualmente con 2 tenants diferentes.

10. **AC-010**: El dashboard no muestra funcionalidades de super admin: no hay link a "Gestion de Tenants", no hay metricas globales, no hay acceso a configuracion de otros tenants. La navegacion del sidebar solo muestra: Dashboard, Vehiculos, Equipo, Configuracion.

11. **AC-011**: Si el tenant tiene plan Free, se muestra un banner de upgrade discreto: "Desbloquea analytics avanzadas, reportes y mas con el plan Pro". El banner tiene boton "Ver Planes" que navega a /admin/billing. El banner es dismissable (se oculta por 7 dias).

12. **AC-012**: Los tests unitarios verifican: (a) KPI cards renderizan valores correctamente con formato MXN, (b) usage bar cambia color segun porcentaje, (c) graficos reciben datos correctos, (d) skeleton loader se muestra durante carga, (e) error state se muestra cuando API falla.

### Definition of Done

- [ ] Dashboard page con 4 KPI cards responsive
- [ ] UsageBar con indicador visual por nivel de uso
- [ ] Revenue chart (line) con Chart.js
- [ ] Vehicle status chart (donut) con Chart.js
- [ ] Top vehicles table funcional
- [ ] Alert cards con acciones
- [ ] Skeleton loaders durante carga
- [ ] Branding aplicado a todos los elementos
- [ ] Tests unitarios >= 85% cobertura
- [ ] Responsive design verificado en 3 breakpoints
- [ ] Code review aprobado

### Notas Tecnicas

- Usar Chart.js via ng2-charts wrapper para Angular
- Los colores de los graficos deben leerse de CSS variables, no hardcodeados
- Considerar lazy loading del bundle de Chart.js (es pesado, ~200KB)
- Los datos del dashboard se pueden refrescar con polling cada 5 minutos (configurable)
- Para planes con limite null (unlimited), no renderizar la usage bar

### Dependencias

- Story MKT-BE-038 completada (API admin scoped)
- Story MKT-FE-028 completada (theme engine para branding)
- Chart.js + ng2-charts instalados
- Router admin configurado con lazy loading

---

## User Story 3: [MKT-BE-039][SVC-VEH-API] Gestion de Inventario por Tenant

### Descripcion

Como tenant admin, necesito gestionar el inventario de vehiculos de mi white label: subir vehiculos individuales o en bulk (CSV), configurar la visibilidad de cada vehiculo (solo mi sitio, solo AgentsMX, ambos), editar detalles y precios, y ver analytics por vehiculo. Las imagenes se suben a un prefijo S3 especifico del tenant para organizacion y control de costos.

### Microservicio

- **Nombre**: SVC-VEH (extension del servicio existente)
- **Puerto**: 5012
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0, Marshmallow 3.x
- **Base de datos**: PostgreSQL 15 (vehicles scoped), Redis 7, Elasticsearch 8
- **Patron**: Hexagonal Architecture - Extension

### Contexto Tecnico

#### Endpoints Nuevos/Modificados

```
# Tenant Vehicle Management (tenant_admin or tenant_editor)
POST /api/v1/admin/vehicles                    -> Create vehicle (tenant_id auto-assigned)
PUT  /api/v1/admin/vehicles/:id                -> Update vehicle
DEL  /api/v1/admin/vehicles/:id                -> Soft delete
PUT  /api/v1/admin/vehicles/:id/visibility     -> Change visibility (tenant_only/agentsmx_only/both)
POST /api/v1/admin/vehicles/:id/publish        -> Publish (draft -> active)
POST /api/v1/admin/vehicles/:id/unpublish      -> Unpublish (active -> draft)

# Bulk Operations
POST /api/v1/admin/vehicles/bulk/upload        -> CSV bulk upload
GET  /api/v1/admin/vehicles/bulk/template      -> Download CSV template
POST /api/v1/admin/vehicles/bulk/visibility    -> Bulk change visibility
GET  /api/v1/admin/vehicles/bulk/status/:job_id -> Check bulk job status

# Vehicle Media (tenant scoped)
POST /api/v1/admin/vehicles/:id/media          -> Upload images (S3 presigned URL)
DEL  /api/v1/admin/vehicles/:id/media/:media_id -> Delete image
PUT  /api/v1/admin/vehicles/:id/media/reorder  -> Reorder images

# Vehicle Analytics
GET  /api/v1/admin/vehicles/:id/analytics      -> Views, favorites, inquiries per vehicle
```

#### Request/Response - Create Vehicle

```json
// POST /api/v1/admin/vehicles
// X-Tenant-ID: f47ac10b-58cc-4372-a567-0e02b2c3d479 (auto from JWT)
{
  "make": "Toyota",
  "model": "Camry",
  "year": 2024,
  "price_mxn": 485000.00,
  "mileage_km": 15000,
  "fuel_type": "gasoline",
  "transmission": "automatic",
  "color": "Blanco",
  "description": "Toyota Camry 2024, unico dueno, mantenimiento de agencia.",
  "vin": "4T1BZ1HK5RU123456",
  "visibility": "both",
  "features": ["camara_reversa", "bluetooth", "sensor_estacionamiento"],
  "location": {
    "state": "Puebla",
    "city": "Puebla de Zaragoza"
  }
}

// Response 201
{
  "data": {
    "id": "veh-a1b2c3d4",
    "tenant_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "make": "Toyota",
    "model": "Camry",
    "year": 2024,
    "price_mxn": 485000.00,
    "status": "draft",
    "visibility": "both",
    "created_at": "2026-03-24T10:00:00Z",
    "media_upload_url": "https://marketplace-assets.s3.amazonaws.com/tenants/f47ac10b/vehicles/veh-a1b2c3d4/?X-Amz-..."
  }
}
```

#### Request/Response - Bulk Upload CSV

```json
// POST /api/v1/admin/vehicles/bulk/upload
// Content-Type: multipart/form-data
// file: vehicles.csv
// visibility: both

// Response 202
{
  "data": {
    "job_id": "bulk-job-xyz123",
    "status": "processing",
    "total_rows": 150,
    "estimated_duration_seconds": 30,
    "check_status_url": "/api/v1/admin/vehicles/bulk/status/bulk-job-xyz123"
  }
}

// GET /api/v1/admin/vehicles/bulk/status/bulk-job-xyz123
// Response 200
{
  "data": {
    "job_id": "bulk-job-xyz123",
    "status": "completed",
    "total_rows": 150,
    "successful": 142,
    "failed": 8,
    "errors": [
      { "row": 23, "field": "price_mxn", "error": "Price must be positive" },
      { "row": 45, "field": "vin", "error": "Duplicate VIN" }
    ],
    "completed_at": "2026-03-24T10:01:30Z"
  }
}
```

#### Request/Response - Change Visibility

```json
// PUT /api/v1/admin/vehicles/:id/visibility
{
  "visibility": "tenant_only"
}

// Response 200
{
  "data": {
    "id": "veh-a1b2c3d4",
    "visibility": "tenant_only",
    "previous_visibility": "both",
    "elasticsearch_reindexed": true,
    "agentsmx_listing_removed": true
  }
}
```

#### Request/Response - Vehicle Analytics

```json
// GET /api/v1/admin/vehicles/:id/analytics?period=30d
{
  "data": {
    "vehicle_id": "veh-a1b2c3d4",
    "period": "30d",
    "views": {
      "total": 1250,
      "from_tenant": 800,
      "from_agentsmx": 450,
      "daily": [
        { "date": "2026-03-23", "views": 45 },
        { "date": "2026-03-22", "views": 52 }
      ]
    },
    "favorites": {
      "total": 34,
      "added_period": 12,
      "removed_period": 3
    },
    "inquiries": {
      "total": 8,
      "via_chat": 5,
      "via_phone": 3
    },
    "conversion_rate": 0.64
  }
}
```

#### S3 Storage Organization

```
s3://marketplace-assets/
  tenants/
    {tenant_id}/
      branding/
        logo.svg
        favicon.ico
      vehicles/
        {vehicle_id}/
          main.jpg
          photo-1.jpg
          photo-2.jpg
          photo-3.jpg
          thumbnail.jpg      # Auto-generated 200x150
```

### Criterios de Aceptacion

1. **AC-001**: POST /api/v1/admin/vehicles crea un vehiculo con tenant_id auto-asignado desde el JWT. El vehiculo se crea en status "draft" por defecto. La visibility se toma del body o del default del tenant config. Se validan todos los campos requeridos: make, model, year, price_mxn. Retorna 201 con presigned URL para upload de imagenes.

2. **AC-002**: PUT /api/v1/admin/vehicles/:id/visibility permite cambiar la visibilidad entre tenant_only, agentsmx_only, both, y private. El cambio dispara un evento SQS para re-indexar el vehiculo en Elasticsearch. Si se cambia de "both" a "tenant_only", el vehiculo deja de aparecer en la busqueda de AgentsMX. El response confirma el re-index.

3. **AC-003**: POST /api/v1/admin/vehicles/bulk/upload acepta un archivo CSV con columnas: make, model, year, price_mxn, mileage_km, fuel_type, transmission, color, vin, description. El proceso es asincrono (retorna 202 con job_id). El tenant_id se auto-asigna. Maximo 1000 filas por upload. Filas invalidas se reportan con numero de fila, campo y error.

4. **AC-004**: GET /api/v1/admin/vehicles/bulk/template retorna un archivo CSV vacio con headers y 2 filas de ejemplo. Content-Type: text/csv, Content-Disposition: attachment; filename="vehicle_upload_template.csv".

5. **AC-005**: POST /api/v1/admin/vehicles/bulk/visibility permite cambiar la visibility de multiples vehiculos en una sola operacion. Body: {"vehicle_ids": ["id1","id2"], "visibility": "both"}. Maximo 100 vehiculos por operacion. Es asincrono si > 10 vehiculos (retorna 202 con job_id).

6. **AC-006**: POST /api/v1/admin/vehicles/:id/media retorna una presigned URL de S3 para upload directo desde el browser. La URL expira en 15 minutos. El path en S3 es: tenants/{tenant_id}/vehicles/{vehicle_id}/{filename}. Se aceptan JPEG, PNG, WebP. Maximo 10 imagenes por vehiculo, maximo 5MB cada una.

7. **AC-007**: Despues del upload a S3, un Lambda trigger genera automaticamente un thumbnail de 200x150px y lo almacena en el mismo prefijo como thumbnail.jpg. El thumbnail se usa en listados y cards de vehiculos.

8. **AC-008**: PUT /api/v1/admin/vehicles/:id/media/reorder permite cambiar el orden de las imagenes. Body: {"media_ids": ["id3","id1","id2"]}. La primera imagen se convierte en la imagen principal (main) que se muestra en cards y listados.

9. **AC-009**: GET /api/v1/admin/vehicles/:id/analytics retorna analytics del vehiculo para el periodo solicitado (7d/30d/90d): views totales (desglose tenant vs AgentsMX), favorites (added/removed), inquiries (chat/phone), conversion rate (inquiries/views). Incluye array diario de views para grafico.

10. **AC-010**: El bulk upload valida contra limites del plan: si el tenant tiene max_vehicles=500 y ya tiene 490, un upload de 15 vehiculos rechaza las ultimas 5 filas con error "Vehicle limit exceeded (500 max, 490 current)". El upload parcial se permite (primeras 10 se crean).

11. **AC-011**: Las imagenes se sirven via CloudFront CDN con URL formato: https://cdn.agentsmx.com/tenants/{tenant_id}/vehicles/{vehicle_id}/photo-1.jpg. Las URLs tienen TTL de 24 horas en CloudFront. Imagenes borradas se invalidan en CloudFront.

12. **AC-012**: Todos los endpoints de vehicle management solo son accesibles para roles tenant_editor, tenant_admin y tenant_owner. El role tenant_viewer puede ver vehiculos (GET) pero no crear, editar o eliminar (403). La validacion de roles ocurre en el middleware con el decorator @require_role.

### Definition of Done

- [ ] CRUD de vehiculos scoped por tenant funcional
- [ ] Visibility toggle con re-indexacion ES
- [ ] Bulk upload CSV con validacion y reporte de errores
- [ ] S3 presigned URLs para media upload
- [ ] Thumbnail generation automatica
- [ ] Vehicle analytics endpoint funcional
- [ ] Role-based access control verificado
- [ ] Tests de integracion con S3 mock y ES
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- S3 presigned URLs evitan que las imagenes pasen por el backend (upload directo del browser a S3)
- El Lambda de thumbnail generation se triggerea con S3 event notification (ObjectCreated)
- Para bulk upload grande, considerar SQS como cola de procesamiento
- El re-index de ES en cambio de visibility puede ser eventual consistency (segundos de delay)
- VIN debe ser unico dentro del mismo tenant pero puede repetirse entre tenants

### Dependencias

- EP-011 completado (tenant_id en vehicles table)
- EP-003 completado (SVC-VEH base)
- AWS S3 con CORS configurado para upload directo
- Lambda function para thumbnail generation
- Elasticsearch 8 con indice multi-tenant

---

## User Story 4: [MKT-FE-032][FE-FEAT-ADM] Panel de Inventario del Tenant

### Descripcion

Como tenant admin, necesito una interfaz para gestionar el inventario de vehiculos de mi white label: ver todos mis vehiculos en una tabla con busqueda y filtros, cambiar la visibilidad individual o en bulk, subir vehiculos (formulario individual y CSV bulk), editar detalles, y ver analytics por vehiculo. La interfaz debe ser intuitiva y branded con el tema del tenant.

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
      vehicles/
        domain/
          models/
            vehicle-admin.model.ts        # Vehicle admin interfaces
            vehicle-visibility.model.ts   # Visibility enum and types
            bulk-upload.model.ts          # Bulk upload interfaces
          ports/
            vehicle-admin.port.ts         # Abstract class
        application/
          services/
            vehicle-admin.service.ts      # Orchestration
          use-cases/
            list-vehicles.use-case.ts
            change-visibility.use-case.ts
            bulk-upload.use-case.ts
        infrastructure/
          adapters/
            vehicle-admin-api.adapter.ts
        presentation/
          pages/
            vehicle-list/
              vehicle-list.page.ts
              vehicle-list.page.html
              vehicle-list.page.spec.ts
            vehicle-form/
              vehicle-form.page.ts
              vehicle-form.page.html
              vehicle-form.page.spec.ts
            vehicle-analytics/
              vehicle-analytics.page.ts
              vehicle-analytics.page.html
              vehicle-analytics.page.spec.ts
            bulk-upload/
              bulk-upload.page.ts
              bulk-upload.page.html
              bulk-upload.page.spec.ts
          components/
            visibility-toggle/
              visibility-toggle.component.ts
              visibility-toggle.component.html
              visibility-toggle.component.spec.ts
            image-uploader/
              image-uploader.component.ts
              image-uploader.component.html
              image-uploader.component.spec.ts
            csv-uploader/
              csv-uploader.component.ts
              csv-uploader.component.html
              csv-uploader.component.spec.ts
            vehicle-row/
              vehicle-row.component.ts
              vehicle-row.component.html
              vehicle-row.component.spec.ts
```

#### Visibility Toggle Component

```typescript
// presentation/components/visibility-toggle/visibility-toggle.component.ts
@Component({
  selector: 'app-visibility-toggle',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="flex items-center gap-2">
      @for (option of options; track option.value) {
        <button
          (click)="select(option.value)"
          class="px-3 py-1.5 text-xs font-medium rounded-full transition-all"
          [class.bg-primary]="visibility() === option.value"
          [class.text-white]="visibility() === option.value"
          [class.bg-gray-100]="visibility() !== option.value"
          [class.text-gray-600]="visibility() !== option.value"
          [class.hover:bg-gray-200]="visibility() !== option.value">
          {{ option.label }}
        </button>
      }
    </div>
  `,
})
export class VisibilityToggleComponent {
  readonly visibility = input.required<string>();
  readonly visibilityChange = output<string>();

  readonly options = [
    { value: 'both', label: 'Ambos' },
    { value: 'tenant_only', label: 'Mi Sitio' },
    { value: 'agentsmx_only', label: 'AgentsMX' },
    { value: 'private', label: 'Privado' },
  ];

  select(value: string): void {
    this.visibilityChange.emit(value);
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: La pagina Vehicle List muestra una tabla con columnas: checkbox (para seleccion multiple), imagen thumbnail, titulo (make model year), precio (formato $XXX,XXX MXN), estado (badge: active/draft/sold), visibilidad (toggle), vistas (7d), acciones (edit/delete/analytics). Soporta paginacion de 20 items.

2. **AC-002**: La busqueda funciona con debounce de 300ms buscando por make, model, year, VIN. Los filtros laterales permiten filtrar por: estado (multiselect), visibilidad (multiselect), rango de precio (slider), year (rango), fuel_type, transmission. Los filtros activos se muestran como chips removibles.

3. **AC-003**: El VisibilityToggle inline en cada fila permite cambiar la visibilidad con un click. Las opciones son: "Ambos" (verde), "Mi Sitio" (azul), "AgentsMX" (naranja), "Privado" (gris). Al cambiar, se llama a la API y se muestra feedback visual (loading spinner breve, luego confirmacion).

4. **AC-004**: La seleccion multiple (checkboxes) permite seleccionar vehiculos y aplicar acciones bulk: "Cambiar Visibilidad" (dropdown con opciones), "Publicar Seleccionados", "Despublicar Seleccionados", "Eliminar Seleccionados". La barra de acciones bulk aparece fija en la parte superior cuando hay seleccion activa.

5. **AC-005**: La pagina Vehicle Form tiene campos: make (dropdown con autocomplete), model (dropdown filtrado por make), year (dropdown), precio (input numerico con formato), mileage_km (input numerico), fuel_type (radio: gasolina/diesel/electrico/hibrido), transmission (radio: automatica/manual), color, VIN, descripcion (textarea), visibility (toggle), location (state dropdown, city dropdown). Validaciones inline.

6. **AC-006**: El Image Uploader permite arrastrar imagenes (drag & drop) o click para seleccionar. Muestra preview de cada imagen antes de subir. Permite reordenar con drag & drop. La primera imagen se marca como "Principal". Muestra progreso de upload (progress bar por imagen). Maximo 10 imagenes, formato JPG/PNG/WebP, max 5MB.

7. **AC-007**: La pagina Bulk Upload tiene: (a) link para descargar template CSV, (b) zona de drag & drop para subir CSV, (c) preview de las primeras 5 filas parseadas antes de confirmar, (d) progress bar durante procesamiento, (e) resultado con count de exitosos/fallidos y tabla de errores con fila y campo.

8. **AC-008**: La pagina Vehicle Analytics muestra por vehiculo: grafico de vistas diarias (line chart, ultimos 30 dias), desglose de vistas por fuente (tenant vs AgentsMX, pie chart), favoritos (total y tendencia), inquiries (total desglose chat/phone), conversion rate. Compara con promedio del inventario.

9. **AC-009**: El formulario de vehiculo valida en el frontend: make y model requeridos, year entre 1990 y current+1, precio > 0 y < 50,000,000, mileage >= 0, VIN formato valido (17 caracteres alfanumericos), descripcion max 2000 caracteres. Errores se muestran inline debajo de cada campo.

10. **AC-010**: Si el tenant esta cerca del limite de vehiculos (>80%), se muestra un banner warning "Estas usando {current} de {limit} vehiculos. Considera upgrade a plan {next_plan}". Si esta al limite, el boton "Agregar Vehiculo" se deshabilita con tooltip "Has alcanzado el limite de tu plan".

11. **AC-011**: Todos los componentes usan ChangeDetectionStrategy.OnPush con signals. La tabla no re-renderiza completamente al cambiar un vehiculo (solo la fila afectada). El scroll de la tabla es virtual (virtual scrolling) si hay mas de 100 vehiculos para performance.

12. **AC-012**: Los tests verifican: (a) tabla renderiza vehiculos correctamente, (b) busqueda filtra resultados, (c) visibility toggle emite cambio correcto, (d) bulk selection funciona, (e) form validation rechaza datos invalidos, (f) CSV parser detecta errores en filas.

### Definition of Done

- [ ] Vehicle list page con tabla, busqueda, filtros, paginacion
- [ ] Visibility toggle inline funcional
- [ ] Bulk actions (visibility, publish, delete)
- [ ] Vehicle form con validaciones completas
- [ ] Image uploader con drag & drop y reorder
- [ ] CSV bulk upload con preview y error report
- [ ] Vehicle analytics page con graficos
- [ ] Plan limit warnings funcionales
- [ ] Tests unitarios >= 85%
- [ ] Responsive design verificado
- [ ] Code review aprobado

### Notas Tecnicas

- Virtual scrolling con Angular CDK ScrollingModule para listas largas
- Image preview usa FileReader API (local, no sube a S3 hasta confirmar)
- CSV parsing en el frontend con PapaParse library
- Las acciones bulk deben tener confirmacion modal antes de ejecutar
- Considerar lazy loading de la pagina de analytics (Chart.js bundle)

### Dependencias

- Story MKT-BE-039 completada (API de inventario por tenant)
- Story MKT-FE-031 completada (dashboard admin del tenant)
- PapaParse library para CSV parsing
- Angular CDK para virtual scrolling y drag & drop

---

## User Story 5: [MKT-BE-040][SVC-USR-API] Gestion de Equipo del Tenant

### Descripcion

Como tenant admin, necesito gestionar el equipo que tiene acceso a mi panel de administracion: invitar nuevos miembros por email, asignar roles (editor, viewer), cambiar roles, y remover miembros. Las invitaciones se envian por email con un link de registro/vinculacion que conecta al usuario con mi tenant. Cada accion se registra en un activity log.

### Microservicio

- **Nombre**: SVC-USR (extension del servicio existente)
- **Puerto**: 5011
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0
- **Base de datos**: PostgreSQL 15, Redis 7
- **Patron**: Hexagonal Architecture - Extension

### Contexto Tecnico

#### Endpoints

```
# Team Management (tenant_admin or tenant_owner)
GET    /api/v1/admin/team                    -> List team members
POST   /api/v1/admin/team/invite             -> Send invitation email
PUT    /api/v1/admin/team/:user_id/role      -> Change member role
DELETE /api/v1/admin/team/:user_id           -> Remove member from tenant
GET    /api/v1/admin/team/activity           -> Activity log

# Invitation handling (public, token-based)
GET    /api/v1/invitations/:token            -> Get invitation details
POST   /api/v1/invitations/:token/accept     -> Accept invitation (register or link)
POST   /api/v1/invitations/:token/decline    -> Decline invitation
```

#### Data Models

```python
# dom/models/team_invitation.py
@dataclass
class TeamInvitation:
    id: UUID = field(default_factory=uuid4)
    tenant_id: UUID = field(default_factory=uuid4)
    email: str = ""
    role: str = "editor"                    # editor, viewer, admin
    invited_by_user_id: UUID = field(default_factory=uuid4)
    token: str = ""                         # Unique invitation token (URL-safe)
    status: str = "pending"                 # pending, accepted, declined, expired
    created_at: datetime = field(default_factory=datetime.utcnow)
    expires_at: datetime = field(default_factory=lambda: datetime.utcnow() + timedelta(days=7))
    accepted_at: Optional[datetime] = None
    accepted_by_user_id: Optional[UUID] = None

# dom/models/team_activity.py
@dataclass
class TeamActivity:
    id: UUID = field(default_factory=uuid4)
    tenant_id: UUID = field(default_factory=uuid4)
    user_id: UUID = field(default_factory=uuid4)
    user_name: str = ""
    action: str = ""                        # invited, accepted, role_changed, removed, login, vehicle_created, ...
    target_type: Optional[str] = None       # user, vehicle, config
    target_id: Optional[str] = None
    details: dict = field(default_factory=dict)
    ip_address: Optional[str] = None
    timestamp: datetime = field(default_factory=datetime.utcnow)
```

```sql
-- ORM Tables
CREATE TABLE team_invitations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    email VARCHAR(254) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'editor',
    invited_by_user_id UUID NOT NULL REFERENCES users(id),
    token VARCHAR(100) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    expires_at TIMESTAMP NOT NULL,
    accepted_at TIMESTAMP,
    accepted_by_user_id UUID REFERENCES users(id)
);

CREATE INDEX idx_invitations_token ON team_invitations(token);
CREATE INDEX idx_invitations_tenant ON team_invitations(tenant_id);
CREATE INDEX idx_invitations_email ON team_invitations(email);

CREATE TABLE team_activities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    user_id UUID NOT NULL REFERENCES users(id),
    user_name VARCHAR(200) NOT NULL,
    action VARCHAR(50) NOT NULL,
    target_type VARCHAR(50),
    target_id VARCHAR(100),
    details JSONB DEFAULT '{}',
    ip_address VARCHAR(45),
    timestamp TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_activities_tenant_time ON team_activities(tenant_id, timestamp DESC);
CREATE INDEX idx_activities_user ON team_activities(user_id);
```

#### Request/Response - List Team

```json
// GET /api/v1/admin/team
// Response 200
{
  "data": {
    "members": [
      {
        "user_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "Juan Perez",
        "email": "juan@miautos.com",
        "role": "owner",
        "avatar_url": "https://cdn.agentsmx.com/avatars/a1b2c3d4.jpg",
        "joined_at": "2026-03-01T10:00:00Z",
        "last_active_at": "2026-03-24T09:45:00Z",
        "is_current_user": true
      },
      {
        "user_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Maria Garcia",
        "email": "maria@miautos.com",
        "role": "admin",
        "avatar_url": null,
        "joined_at": "2026-03-10T14:00:00Z",
        "last_active_at": "2026-03-23T16:30:00Z",
        "is_current_user": false
      }
    ],
    "pending_invitations": [
      {
        "id": "inv-xyz789",
        "email": "carlos@miautos.com",
        "role": "editor",
        "invited_by": "Juan Perez",
        "created_at": "2026-03-23T10:00:00Z",
        "expires_at": "2026-03-30T10:00:00Z"
      }
    ],
    "limits": {
      "current_members": 3,
      "max_members": 10,
      "current_pending": 1
    }
  }
}
```

#### Request/Response - Invite Member

```json
// POST /api/v1/admin/team/invite
{
  "email": "carlos@miautos.com",
  "role": "editor",
  "message": "Hola Carlos, te invito a administrar nuestro inventario en Mi Autos Puebla."
}

// Response 201
{
  "data": {
    "invitation_id": "inv-xyz789",
    "email": "carlos@miautos.com",
    "role": "editor",
    "status": "pending",
    "invitation_url": "https://miautos.agentsmx.com/invitations/tok_abc123def456",
    "expires_at": "2026-03-30T10:00:00Z"
  }
}
```

#### Invitation Email Template

```
Asunto: Juan Perez te invita a unirte a Mi Autos Puebla

Hola,

Juan Perez te ha invitado a unirte al equipo de Mi Autos Puebla
como Editor en su plataforma de vehiculos.

Mensaje personal: "Hola Carlos, te invito a administrar nuestro
inventario en Mi Autos Puebla."

[Aceptar Invitacion]  (link a invitation_url)

Esta invitacion expira el 30 de Marzo, 2026.

Si no esperabas esta invitacion, puedes ignorar este correo.

--
Mi Autos Puebla
Powered by AgentsMX
```

### Criterios de Aceptacion

1. **AC-001**: GET /api/v1/admin/team retorna la lista de miembros del tenant con campos: user_id, name, email, role, avatar_url, joined_at, last_active_at, is_current_user. Incluye invitaciones pendientes con id, email, role, invited_by, created_at, expires_at. Incluye limites del plan (current_members/max_members).

2. **AC-002**: POST /api/v1/admin/team/invite envia un email de invitacion con un token unico URL-safe (32 bytes, base64url encoded). La invitacion tiene TTL de 7 dias. Si el email ya tiene una invitacion pending para este tenant, retorna 409 "Invitation already pending for this email". Si el usuario ya es miembro, retorna 409 "User is already a member".

3. **AC-003**: El email de invitacion esta branded con el tenant: usa el nombre del tenant, el logo del tenant, y colores del tenant. Incluye el nombre del invitante, el rol asignado, mensaje personal opcional, y boton de aceptar con link a la URL de invitacion del white label.

4. **AC-004**: POST /api/v1/invitations/:token/accept funciona en dos escenarios: (a) si el usuario ya existe en el sistema, crea UserTenantMembership y redirige al admin del tenant, (b) si el usuario no existe, redirige al formulario de registro con el email pre-llenado y el token en la URL; tras completar registro, se crea el membership.

5. **AC-005**: PUT /api/v1/admin/team/:user_id/role permite cambiar el rol de un miembro. Validaciones: (a) solo owner o admin pueden cambiar roles, (b) no se puede elevar a owner (solo puede haber 1), (c) un admin no puede cambiar el rol de otro admin (solo owner), (d) no se puede bajar el rol del ultimo admin (debe haber al menos 1 admin).

6. **AC-006**: DELETE /api/v1/admin/team/:user_id remueve al miembro del tenant (soft delete del UserTenantMembership, status -> removed). El usuario pierde acceso al admin de este tenant pero mantiene su cuenta en otros tenants. No se puede remover al owner. No se puede remover al ultimo admin.

7. **AC-007**: GET /api/v1/admin/team/activity retorna el log de actividades del equipo paginado (default 50, max 200). Cada entry tiene: user_name, action, target, details, timestamp. Acciones logueadas: member_invited, member_accepted, member_removed, role_changed, vehicle_created, vehicle_updated, branding_updated, login.

8. **AC-008**: Las invitaciones se validan contra limites del plan: si max_members=10 y ya hay 8 miembros + 2 pendientes, nueva invitacion retorna 422 "Member limit reached (10 max, 8 active, 2 pending invitations)". El calculo incluye miembros activos + invitaciones pending.

9. **AC-009**: Las invitaciones expiradas (>7 dias) se ignoran en links y se muestran como "expired" en la lista de pending. Un job diario limpia invitaciones expiradas hace mas de 30 dias. Se puede reenviar una invitacion expirada (genera nuevo token).

10. **AC-010**: Solo roles tenant_owner y tenant_admin pueden gestionar equipo. Un tenant_editor que intenta invitar retorna 403. Un tenant_viewer que intenta listar el equipo retorna 403. La permission "users.manage" es requerida para todas las operaciones de equipo.

11. **AC-011**: Cada accion de equipo dispara una notificacion: invitacion enviada (email al invitado), invitacion aceptada (email al invitante), miembro removido (email al removido), rol cambiado (email al miembro). Las notificaciones se envian via SVC-NTF con tenant context.

12. **AC-012**: Los tests de integracion verifican el flujo completo: create invitation -> accept invitation -> verify membership -> change role -> remove member. Un test verifica que un usuario aceptando invitacion de tenant A puede seguir accediendo a tenant B donde ya era miembro.

### Definition of Done

- [ ] CRUD de team members funcional
- [ ] Invitation flow (create, accept, decline, expire)
- [ ] Email templates branded por tenant
- [ ] Role management con validaciones de jerarquia
- [ ] Activity log funcional
- [ ] Plan limits enforced
- [ ] Tests de integracion del flujo completo
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- El token de invitacion debe ser criptograficamente seguro (secrets.token_urlsafe(32))
- Emails se envian via SQS -> SVC-NTF para desacoplar
- Considerar rate limiting en invitations: max 20 invitations/dia por tenant para evitar spam
- La tabla team_activities puede crecer rapido; considerar TTL de 1 ano y particionamiento por tenant_id
- El activity log NO debe registrar datos sensibles (passwords, tokens)

### Dependencias

- EP-011 completado (user_tenant_memberships table)
- EP-011 Story MKT-BE-035 (multi-tenant auth, membership model)
- SVC-NTF funcional (EP-010) para envio de emails
- SVC-USR existente (EP-002) como base

---

## User Story 6: [MKT-FE-033][FE-FEAT-ADM] Gestion de Equipo UI

### Descripcion

Como tenant admin, necesito una interfaz para gestionar mi equipo: ver la lista de miembros con sus roles y actividad reciente, invitar nuevos miembros por email, cambiar roles, y remover miembros. La interfaz debe ser clara sobre los permisos de cada rol y respetar los limites del plan.

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
      team/
        domain/
          models/
            team-member.model.ts
            invitation.model.ts
            team-activity.model.ts
            team-role.model.ts
          ports/
            team-management.port.ts
        application/
          services/
            team.service.ts
        infrastructure/
          adapters/
            team-api.adapter.ts
        presentation/
          pages/
            team-list/
              team-list.page.ts
              team-list.page.html
              team-list.page.spec.ts
            activity-log/
              activity-log.page.ts
              activity-log.page.html
              activity-log.page.spec.ts
          components/
            member-card/
              member-card.component.ts
              member-card.component.html
              member-card.component.spec.ts
            invite-modal/
              invite-modal.component.ts
              invite-modal.component.html
              invite-modal.component.spec.ts
            role-selector/
              role-selector.component.ts
              role-selector.component.html
              role-selector.component.spec.ts
            permissions-matrix/
              permissions-matrix.component.ts
              permissions-matrix.component.html
              permissions-matrix.component.spec.ts
```

#### Role Definitions for UI

```typescript
// domain/models/team-role.model.ts
export interface RoleDefinition {
  value: string;
  label: string;
  description: string;
  permissions: string[];
  color: string;
}

export const ROLE_DEFINITIONS: RoleDefinition[] = [
  {
    value: 'owner',
    label: 'Propietario',
    description: 'Control total del tenant. Solo puede haber uno.',
    permissions: ['Todo'],
    color: '#7C3AED',
  },
  {
    value: 'admin',
    label: 'Administrador',
    description: 'Gestiona equipo, inventario, branding y configuracion.',
    permissions: ['Dashboard', 'Vehiculos', 'Equipo', 'Branding', 'Analytics', 'Reportes'],
    color: '#2563EB',
  },
  {
    value: 'editor',
    label: 'Editor',
    description: 'Gestiona inventario de vehiculos y ve analytics.',
    permissions: ['Dashboard', 'Vehiculos (crear/editar)', 'Analytics'],
    color: '#059669',
  },
  {
    value: 'viewer',
    label: 'Visor',
    description: 'Acceso de solo lectura al dashboard y vehiculos.',
    permissions: ['Dashboard (solo ver)', 'Vehiculos (solo ver)'],
    color: '#6B7280',
  },
];
```

### Criterios de Aceptacion

1. **AC-001**: La pagina Team List muestra miembros activos como cards con: avatar (o iniciales en circulo coloreado), nombre, email, rol (badge con color del rol), fecha de ingreso, y ultima actividad (relative time: "hace 2 horas"). El owner se muestra primero con badge dorado. El usuario actual tiene badge "(Tu)".

2. **AC-002**: Las invitaciones pendientes se muestran en una seccion separada con: email, rol asignado, invitado por, fecha de envio, dias restantes antes de expiracion. Cada invitacion tiene acciones: "Reenviar" (genera nuevo token, extiende TTL), "Cancelar" (marca como cancelled).

3. **AC-003**: El boton "Invitar Miembro" abre un modal con: input de email (validacion de formato), selector de rol (dropdown con description de cada rol), textarea de mensaje personalizado (opcional), y boton "Enviar Invitacion". El modal muestra el conteo current/max de miembros.

4. **AC-004**: El RoleSelector muestra cada rol como card clickeable con nombre, descripcion, y lista de permisos. El rol actualmente seleccionado tiene border del color primario. El rol "owner" no es seleccionable en invitaciones (solo puede haber 1). Los roles incompatibles con el plan se muestran grayed out.

5. **AC-005**: El PermissionsMatrix muestra una tabla con roles en columnas y permisos en filas. Check marks verdes indican permisos incluidos, X rojas indican permisos no incluidos. Se muestra al hacer click en "Ver permisos detallados" en el modal de invitacion.

6. **AC-006**: Cambiar el rol de un miembro se hace via dropdown en su card. Solo los roles validos aparecen como opciones (segun jerarquia). Al cambiar, se muestra confirmacion "Cambiar rol de Maria de Admin a Editor?" con boton confirmar. Toast de exito o error.

7. **AC-007**: Remover un miembro requiere confirmacion modal: "Estas seguro de remover a Maria Garcia? Perdera acceso al panel de administracion de [Tenant Name]." con boton rojo "Remover Miembro". El boton de remover no aparece para el owner ni para el propio usuario.

8. **AC-008**: El Activity Log muestra un timeline vertical con: icono del tipo de accion (persona para miembros, coche para vehiculos, paleta para branding), nombre del usuario, accion en texto legible ("Juan invito a carlos@email.com como Editor"), timestamp relative. Paginacion infinita (scroll para cargar mas).

9. **AC-009**: Si el tenant esta al limite de miembros, el boton "Invitar Miembro" se muestra como disabled con tooltip "Has alcanzado el limite de {max} miembros de tu plan". Un link "Upgrade tu plan" aparece debajo.

10. **AC-010**: Las acciones de equipo respetan el rol del usuario actual: si es admin, puede invitar, cambiar roles de editores/viewers, y remover editores/viewers. Si es owner, puede ademas cambiar roles de admins y remover admins. Acciones no permitidas no se muestran (hidden, no disabled).

11. **AC-011**: Todos los componentes son standalone con OnPush change detection. El modal de invitacion se cierra con Escape o click fuera. Los formularios tienen validacion reactiva. Los toasts de confirmacion usan el color primario del tenant.

12. **AC-012**: Los tests unitarios verifican: (a) member cards renderizan correctamente con diferentes roles, (b) invite modal valida email y respeta limites, (c) role selector muestra opciones correctas segun jerarquia, (d) permissions matrix es precisa, (e) remove confirmation funciona.

### Definition of Done

- [ ] Team list page con member cards y pending invitations
- [ ] Invite modal con validaciones
- [ ] Role selector con descriptions y permissions
- [ ] Change role con confirmacion
- [ ] Remove member con confirmacion
- [ ] Activity log con timeline
- [ ] Plan limits enforced en UI
- [ ] Tests unitarios >= 85%
- [ ] Responsive design verificado
- [ ] Code review aprobado

### Notas Tecnicas

- Avatars se generan con iniciales si no hay imagen: primer caracter de nombre + primer caracter de apellido
- El color del avatar de iniciales se genera deterministicamente del user_id (hash -> color palette)
- El modal de invitacion debe prevenir envios duplicados (disable boton despues de click)
- Relative time se calcula con una pipe custom o date-fns/formatDistanceToNow
- Considerar WebSocket o polling (30s) para actualizar la lista cuando otro admin hace cambios

### Dependencias

- Story MKT-BE-040 completada (API de equipo)
- Story MKT-FE-031 completada (dashboard admin con sidebar)
- Angular CDK Dialog para modals

---

## User Story 7: [MKT-BE-041][SVC-TNT-API] Configuracion del Tenant (Self-Service)

### Descripcion

Como tenant admin, necesito poder configurar mi propio white label dentro de los limites de mi plan: actualizar branding (logo, colores), ver mi uso y billing, y acceder a mi configuracion actual. No puedo cambiar mi plan (requiere super admin) ni activar features premium que mi plan no incluye. Esta es la version self-service del panel de configuracion.

### Microservicio

- **Nombre**: SVC-TNT
- **Puerto**: 5023
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0
- **Base de datos**: PostgreSQL 15, Redis 7
- **Patron**: Hexagonal Architecture - API Layer

### Contexto Tecnico

#### Endpoints

```
# Self-service configuration (tenant_admin or tenant_owner)
GET  /api/v1/my-tenant/config              -> My tenant's current configuration
PUT  /api/v1/my-tenant/branding            -> Update my branding (within plan limits)
GET  /api/v1/my-tenant/usage               -> My usage vs plan limits
GET  /api/v1/my-tenant/billing             -> My billing info and invoices
GET  /api/v1/my-tenant/plan                -> My current plan details and available upgrades
```

#### Request/Response - My Tenant Config

```json
// GET /api/v1/my-tenant/config
// (tenant_id from JWT)
{
  "data": {
    "tenant": {
      "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "name": "Mi Autos Puebla",
      "slug": "mi-autos-puebla",
      "plan": "basic",
      "status": "active",
      "urls": {
        "subdomain": "https://miautos.agentsmx.com",
        "custom_domain": null,
        "admin": "https://miautos.agentsmx.com/admin"
      }
    },
    "branding": {
      "logo_url": "https://cdn.agentsmx.com/tenants/f47ac10b/logo.svg",
      "primary_color": "#E11D48",
      "secondary_color": "#BE123C",
      "accent_color": "#FB923C",
      "font_family": "Poppins",
      "border_radius": "12px",
      "is_editable": true
    },
    "features": {
      "financing": { "enabled": true, "available_in_plan": true },
      "insurance": { "enabled": true, "available_in_plan": true },
      "analytics": { "enabled": false, "available_in_plan": false, "upgrade_to": "pro" },
      "reports": { "enabled": false, "available_in_plan": false, "upgrade_to": "pro" },
      "chat": { "enabled": true, "available_in_plan": true },
      "seo_tools": { "enabled": false, "available_in_plan": false, "upgrade_to": "pro" }
    },
    "plan_limits": {
      "vehicles": { "current": 234, "max": 500, "percent": 46.8 },
      "users": { "current": 5, "max": 10, "percent": 50.0 },
      "custom_domain": { "allowed": false, "upgrade_to": "pro" },
      "remove_badge": { "allowed": false, "upgrade_to": "pro" }
    }
  }
}
```

#### Request/Response - Update My Branding

```json
// PUT /api/v1/my-tenant/branding
{
  "primary_color": "#DC2626",
  "accent_color": "#F97316"
}

// Response 200
{
  "data": {
    "branding": {
      "primary_color": "#DC2626",
      "accent_color": "#F97316",
      "updated_at": "2026-03-24T10:30:00Z"
    },
    "cache_invalidated": true
  }
}

// Response 403 (plan restriction)
{
  "error": {
    "code": "PLAN_RESTRICTION",
    "message": "Custom CSS is only available on Pro and Enterprise plans.",
    "status": 403,
    "upgrade_to": "pro"
  }
}
```

#### Request/Response - My Usage

```json
// GET /api/v1/my-tenant/usage
{
  "data": {
    "period": "current_month",
    "vehicles": {
      "active": 234,
      "draft": 15,
      "total": 249,
      "limit": 500,
      "percent_used": 49.8,
      "days_until_limit": null
    },
    "users": {
      "active": 5,
      "total": 5,
      "limit": 10,
      "percent_used": 50.0
    },
    "storage": {
      "used_mb": 1250,
      "limit_mb": 5000,
      "percent_used": 25.0
    },
    "api_calls": {
      "total_month": 15230,
      "limit_month": null,
      "daily_avg": 507
    }
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: GET /api/v1/my-tenant/config retorna la configuracion completa del tenant del JWT. Cada feature incluye "enabled" (estado actual) y "available_in_plan" (si el plan lo permite). Features no disponibles incluyen "upgrade_to" indicando el plan necesario. Los plan_limits muestran current/max/percent para vehiculos, usuarios, storage.

2. **AC-002**: PUT /api/v1/my-tenant/branding permite actualizar campos de branding permitidos por el plan. Plan Free/Basic: logo, primary_color, secondary_color, accent_color, font_family, border_radius. Plan Pro: ademas custom_css, header_style, footer_style. Plan Enterprise: ademas custom_header_html. Campos no permitidos retornan 403 con PLAN_RESTRICTION.

3. **AC-003**: PUT /api/v1/my-tenant/branding valida los mismos campos que la API admin: colores hex validos, fonts de la whitelist, border_radius CSS valido. El branding update invalida el cache Redis y el CSS generado. El response confirma cache_invalidated=true.

4. **AC-004**: GET /api/v1/my-tenant/usage retorna metricas de uso detalladas: vehiculos (active/draft/total/limit/percent), usuarios (active/total/limit/percent), storage (used_mb/limit_mb/percent), api_calls (total_month/limit/daily_avg). Los limites vienen del plan del tenant.

5. **AC-005**: GET /api/v1/my-tenant/billing retorna informacion de billing: plan actual (nombre, precio, fecha de inicio), metodo de pago (ultimos 4 digitos, tipo), proxima factura (fecha, monto), historial de facturas (lista con fecha, monto, status, download_url). Para tenants Free, la seccion de billing muestra solo el plan con opcion de upgrade.

6. **AC-006**: GET /api/v1/my-tenant/plan retorna detalles del plan actual y comparacion con planes superiores. Cada plan muestra: nombre, precio, features incluidos, limites. El plan actual esta marcado como "current". Planes superiores tienen boton "Upgrade" (que redirige a super admin por ahora, automatizado en EP-015).

7. **AC-007**: El tenant admin NO puede: cambiar su propio plan (requiere super admin), activar features no incluidas en su plan, exceder limites de vehiculos/usuarios, acceder a datos de otros tenants, configurar custom domain si su plan no lo permite. Cada restriccion retorna 403 con codigo especifico.

8. **AC-008**: Los endpoints /api/v1/my-tenant/* solo son accesibles para roles tenant_admin y tenant_owner. El role tenant_editor puede leer config (GET) pero no modificar branding (PUT retorna 403). El role tenant_viewer no tiene acceso a /my-tenant (403).

9. **AC-009**: El campo custom_css en branding se sanitiza para prevenir XSS: no se permiten tags <script>, no se permiten URLs con javascript:, no se permite @import de dominios externos, no se permite position:fixed (podria cubrir la UI). El sanitizador retorna errores especificos de que regla se violo.

10. **AC-010**: Cada cambio de branding genera un registro en team_activities: {action: "branding_updated", details: {fields_changed: ["primary_color", "accent_color"]}}. El activity log es consultable desde /admin/team/activity.

11. **AC-011**: Los limites de plan se evaluan en tiempo real: crear un vehiculo verifica contra max_vehicles, invitar un miembro verifica contra max_users. Si el tenant downgrade a un plan con limites menores y ya excede los limites, los items existentes no se eliminan pero no puede crear nuevos.

12. **AC-012**: Los tests unitarios verifican: (a) plan restrictions se aplican correctamente, (b) branding update invalida cache, (c) usage calculation es precisa, (d) custom_css sanitization bloquea XSS, (e) role restrictions se aplican, (f) downgrade con exceso de limites no elimina datos.

### Definition of Done

- [ ] Self-service config endpoint funcional
- [ ] Branding update con plan restrictions
- [ ] Usage metrics calculadas correctamente
- [ ] Billing info endpoint funcional
- [ ] Plan comparison endpoint funcional
- [ ] Custom CSS sanitization implementada
- [ ] Role-based access enforced
- [ ] Activity logging en cambios
- [ ] Tests unitarios >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- El endpoint /my-tenant no necesita :id en la URL porque el tenant se resuelve del JWT
- Custom CSS sanitization puede usar bleach o cssutils para parsing seguro
- Los plan_limits deben reflejar el estado actual en tiempo real (no cache)
- Si billing se implementa con Stripe (EP-015), estos endpoints retornaran datos de Stripe via API
- Considerar webhooks de Stripe para actualizar plan_limits automaticamente al cambiar plan

### Dependencias

- Story MKT-BE-032 completada (API admin de tenants)
- Story MKT-BE-036 completada (API white label config)
- EP-012 completado (theme engine para aplicar cambios de branding)
- SVC-TNT funcional con modelos de plan
