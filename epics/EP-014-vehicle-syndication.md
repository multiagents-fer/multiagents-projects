# [MKT-EP-014] Sindicacion de Vehiculos (Bidirectional Vehicle Sharing)

**Sprint**: 11-13
**Priority**: Priority 2
**Epic Owner**: Tech Lead
**Estimated Points**: 100
**Teams**: Backend, Frontend, Integration

---

## Resumen del Epic

Este epic implementa el sistema de sindicacion bidireccional de vehiculos entre tenants y el marketplace principal AgentsMX. Un vehiculo puede aparecer en el white label del tenant, en AgentsMX, o en ambos, controlado por el campo visibility. AgentsMX actua como agregador que muestra vehiculos de todos los tenants con atribucion de fuente. El sistema incluye la logica de visibilidad multi-tenant en Elasticsearch, el flujo de compra atribuido al tenant, revenue tracking, y la integracion de dealers existentes (loteros) como tenants.

## Dependencias Externas

- EP-011 completado (tenant_id en vehicles, Elasticsearch multi-tenant)
- EP-013 completado (inventario por tenant con visibility toggle)
- Elasticsearch 8 con indice multi-tenant configurado
- SQS para eventos de sindicacion y re-indexacion
- Datos existentes de scrappers (kavak, albacar, etc.) en scrapper_nacional

---

## User Story 1: [MKT-BE-042][SVC-VEH-DOM] Modelo de Visibilidad de Vehiculos Multi-Tenant

### Descripcion

Como servicio de vehiculos, necesito un modelo de visibilidad que controle donde aparece cada vehiculo. Cada vehiculo tiene un campo visibility con 4 valores posibles: tenant_only (solo en el white label del tenant), agentsmx_only (solo en AgentsMX), both (en ambos), y private (en ninguno, draft). La logica de listado debe respetar esta visibilidad: el white label de un tenant solo muestra vehiculos con su tenant_id y visibility in (tenant_only, both), mientras que AgentsMX muestra vehiculos con visibility in (agentsmx_only, both) de todos los tenants.

### Microservicio

- **Nombre**: SVC-VEH (extension del servicio existente)
- **Puerto**: 5012
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0
- **Base de datos**: PostgreSQL 15, Redis 7, Elasticsearch 8
- **Patron**: Hexagonal Architecture - Domain Layer Extension

### Contexto Tecnico

#### Domain Model Extension

```python
# dom/models/vehicle.py (extended)
from dataclasses import dataclass, field
from typing import Optional
from uuid import UUID
from enum import Enum

class VehicleVisibility(Enum):
    TENANT_ONLY = "tenant_only"        # Only visible on tenant's white label
    AGENTSMX_ONLY = "agentsmx_only"    # Only visible on AgentsMX marketplace
    BOTH = "both"                       # Visible on both
    PRIVATE = "private"                 # Not visible anywhere (draft)

@dataclass
class Vehicle:
    id: UUID
    tenant_id: UUID
    # ... existing fields ...
    visibility: VehicleVisibility = VehicleVisibility.BOTH
    is_syndicated: bool = False         # True if appears on AgentsMX
    syndicated_at: Optional[datetime] = None
    source_name: Optional[str] = None   # "Mi Autos Puebla", "Kavak", etc.
    source_type: str = "tenant"         # tenant, scrapper, direct
```

```python
# dom/services/vehicle_visibility_service.py
from typing import Optional
from uuid import UUID

MASTER_TENANT_ID = UUID("00000000-0000-0000-0000-000000000001")

class VehicleVisibilityService:
    """Pure domain service for vehicle visibility logic."""

    def is_visible_on_tenant(self, vehicle: Vehicle,
                              requesting_tenant_id: UUID) -> bool:
        """Check if vehicle should appear on a specific tenant's site."""
        if vehicle.tenant_id != requesting_tenant_id:
            return False
        return vehicle.visibility in (
            VehicleVisibility.TENANT_ONLY,
            VehicleVisibility.BOTH,
        )

    def is_visible_on_agentsmx(self, vehicle: Vehicle) -> bool:
        """Check if vehicle should appear on AgentsMX marketplace."""
        return vehicle.visibility in (
            VehicleVisibility.AGENTSMX_ONLY,
            VehicleVisibility.BOTH,
        )

    def build_query_filter(self,
                            requesting_tenant_id: UUID) -> dict:
        """Build Elasticsearch filter based on requesting context."""
        if requesting_tenant_id == MASTER_TENANT_ID:
            # AgentsMX: show all vehicles visible on agentsmx
            return {
                "bool": {
                    "should": [
                        {"term": {"visibility": "agentsmx_only"}},
                        {"term": {"visibility": "both"}},
                    ],
                    "minimum_should_match": 1
                }
            }
        else:
            # Tenant white label: show only their vehicles
            return {
                "bool": {
                    "must": [
                        {"term": {"tenant_id": str(requesting_tenant_id)}},
                        {"bool": {
                            "should": [
                                {"term": {"visibility": "tenant_only"}},
                                {"term": {"visibility": "both"}},
                            ],
                            "minimum_should_match": 1
                        }}
                    ]
                }
            }

    def validate_visibility_change(self, vehicle: Vehicle,
                                     new_visibility: VehicleVisibility,
                                     tenant_config: TenantConfig) -> list[str]:
        """Validate if visibility change is allowed. Returns list of errors."""
        errors = []
        if vehicle.status != "active" and new_visibility != VehicleVisibility.PRIVATE:
            errors.append("Vehicle must be active to be visible.")
        if new_visibility in (VehicleVisibility.AGENTSMX_ONLY, VehicleVisibility.BOTH):
            if not tenant_config.syndication_enabled:
                errors.append("Syndication to AgentsMX is not enabled for this tenant.")
        return errors
```

#### ORM Extension

```sql
-- Add visibility column to vehicles table (if not exists)
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS visibility VARCHAR(20)
    NOT NULL DEFAULT 'both';
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS is_syndicated BOOLEAN
    NOT NULL DEFAULT false;
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS syndicated_at TIMESTAMP;
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS source_name VARCHAR(200);
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS source_type VARCHAR(20)
    NOT NULL DEFAULT 'tenant';

-- Index for visibility queries
CREATE INDEX CONCURRENTLY idx_vehicles_visibility
    ON vehicles(visibility) WHERE visibility != 'private';
CREATE INDEX CONCURRENTLY idx_vehicles_tenant_visibility
    ON vehicles(tenant_id, visibility);
```

#### Query Examples

```python
# List vehicles for tenant white label
def list_vehicles_for_tenant(self, tenant_id: UUID,
                              filters: VehicleFilters) -> list[Vehicle]:
    stmt = (
        select(VehicleORM)
        .where(VehicleORM.tenant_id == tenant_id)
        .where(VehicleORM.visibility.in_(["tenant_only", "both"]))
        .where(VehicleORM.status == "active")
    )
    # Apply additional filters...
    return stmt

# List vehicles for AgentsMX marketplace
def list_vehicles_for_agentsmx(self, filters: VehicleFilters) -> list[Vehicle]:
    stmt = (
        select(VehicleORM)
        .where(VehicleORM.visibility.in_(["agentsmx_only", "both"]))
        .where(VehicleORM.status == "active")
    )
    # Apply additional filters...
    return stmt
```

### Criterios de Aceptacion

1. **AC-001**: El campo visibility se agrega a la tabla vehicles con tipo VARCHAR(20) y valores posibles: tenant_only, agentsmx_only, both, private. Default: "both". Todos los vehiculos existentes reciben visibility="both" en la migracion. Se crea indice en (tenant_id, visibility) para queries eficientes.

2. **AC-002**: GET /api/v1/vehicles (publico) en un white label (X-Tenant-ID != master) retorna solo vehiculos donde tenant_id = X-Tenant-ID AND visibility IN (tenant_only, both) AND status = active. Un vehiculo con visibility=agentsmx_only de este tenant NO aparece en su propio white label.

3. **AC-003**: GET /api/v1/vehicles (publico) en AgentsMX (X-Tenant-ID = master) retorna vehiculos de TODOS los tenants donde visibility IN (agentsmx_only, both) AND status = active. Incluye campo source_name con el nombre del tenant que publico el vehiculo.

4. **AC-004**: El VehicleVisibilityService es un domain service puro (sin dependencias de infrastructure) que implementa la logica de visibilidad. Los metodos is_visible_on_tenant() y is_visible_on_agentsmx() encapsulan las reglas. El metodo build_query_filter() genera el filtro de Elasticsearch correcto segun el contexto.

5. **AC-005**: Cambiar visibility de un vehiculo dispara un evento SQS "vehicle.visibility_changed" con {vehicle_id, tenant_id, old_visibility, new_visibility}. Un consumer re-indexa el vehiculo en Elasticsearch para que aparezca/desaparezca de las busquedas segun la nueva visibilidad.

6. **AC-006**: Un vehiculo con visibility="private" no aparece en ningun listado publico (ni tenant ni AgentsMX). Solo es visible en el panel admin del tenant que lo posee. Se usa para vehiculos en draft o que el tenant quiere ocultar temporalmente.

7. **AC-007**: La validacion de cambio de visibilidad verifica: (a) vehiculo debe estar en status "active" para ser visible (no draft/sold/archived), (b) el tenant debe tener syndication_enabled=true para usar agentsmx_only o both, (c) cambiar a tenant_only no requiere validacion adicional. Errores descriptivos se retornan en 422.

8. **AC-008**: En AgentsMX, cada vehiculo de un tenant muestra un badge "Publicado por [Tenant Name]" con el logo del tenant. Click en el badge navega al perfil del tenant. Vehiculos propios de AgentsMX (tenant maestro) no muestran badge.

9. **AC-009**: El campo source_type distingue entre: "tenant" (vehiculo subido por un tenant), "scrapper" (vehiculo importado de fuentes externas como Kavak/Albacar), "direct" (vehiculo subido directamente a AgentsMX). Esto permite filtrar por tipo de fuente en la busqueda.

10. **AC-010**: Los aggregations de Elasticsearch (conteos por make, model, price range, etc.) respetan la visibilidad. En un white label, las facetas solo cuentan vehiculos del tenant. En AgentsMX, las facetas cuentan todos los vehiculos visibles.

11. **AC-011**: El performance de queries con filtro de visibilidad no degrada mas del 10% vs queries sin filtro. Se verifica con benchmark: query de busqueda en Elasticsearch con filtro de tenant+visibility vs query sin filtro, medido con 10,000+ documentos.

12. **AC-012**: Los tests unitarios del VehicleVisibilityService cubren todos los escenarios: tenant ve sus vehiculos both y tenant_only, tenant NO ve sus vehiculos agentsmx_only y private, AgentsMX ve vehiculos both y agentsmx_only de todos los tenants, AgentsMX NO ve vehiculos tenant_only ni private.

### Definition of Done

- [ ] Campo visibility agregado con migracion
- [ ] VehicleVisibilityService implementado como domain service
- [ ] Queries de listado filtran por visibility correctamente
- [ ] Elasticsearch re-indexacion en cambio de visibility
- [ ] Event SQS para cambios de visibilidad
- [ ] Tests unitarios cubren todos los escenarios de visibilidad
- [ ] Performance benchmark documentado
- [ ] Code review aprobado

### Notas Tecnicas

- El VehicleVisibilityService es un domain service puro; no debe tener imports de SQLAlchemy o Elasticsearch
- Los queries de Elasticsearch usan bool filter (no query) para mejor caching
- Considerar agregar visibility como routing key en ES para queries mas rapidas por tenant
- El re-index puede ser eventual consistency (1-2 segundos de delay); documentar esto para el frontend
- Para vehiculos legacy (antes de multi-tenant), visibility default es "both"

### Dependencias

- EP-011 Story MKT-BE-034 completada (tenant_id en vehicles)
- EP-003 completado (SVC-VEH base con Elasticsearch)
- SQS configurado para eventos de vehiculos

---

## User Story 2: [MKT-BE-043][SVC-VEH-API] API de Sindicacion

### Descripcion

Como tenant admin, necesito una API para gestionar la sindicacion de mis vehiculos a AgentsMX: publicar vehiculos individuales o en bulk en AgentsMX, despublicar, y ver el estado de sindicacion de todo mi inventario. La sindicacion permite que vehiculos de mi white label tengan mayor exposicion en el marketplace principal de AgentsMX.

### Microservicio

- **Nombre**: SVC-VEH (extension)
- **Puerto**: 5012
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0, Marshmallow 3.x
- **Base de datos**: PostgreSQL 15, Redis 7, Elasticsearch 8
- **Patron**: Hexagonal Architecture - API Layer Extension

### Contexto Tecnico

#### Endpoints

```
# Syndication Management (tenant_admin or tenant_editor)
POST /api/v1/syndication/publish                    -> Publish vehicle(s) to AgentsMX
POST /api/v1/syndication/unpublish                  -> Remove vehicle(s) from AgentsMX
GET  /api/v1/syndication/status                     -> Syndication status of all vehicles
GET  /api/v1/syndication/status/:vehicle_id         -> Syndication status of one vehicle
PUT  /api/v1/syndication/default-visibility         -> Set default visibility for new vehicles
GET  /api/v1/syndication/analytics                  -> Performance of syndicated vehicles on AgentsMX
```

#### Request/Response - Publish to AgentsMX

```json
// POST /api/v1/syndication/publish
{
  "vehicle_ids": ["veh-001", "veh-002", "veh-003"],
  "visibility": "both"
}

// Response 200
{
  "data": {
    "published": [
      {
        "vehicle_id": "veh-001",
        "visibility": "both",
        "syndicated_at": "2026-03-24T10:00:00Z",
        "agentsmx_url": "https://agentsmx.com/vehiculos/veh-001"
      },
      {
        "vehicle_id": "veh-002",
        "visibility": "both",
        "syndicated_at": "2026-03-24T10:00:00Z",
        "agentsmx_url": "https://agentsmx.com/vehiculos/veh-002"
      }
    ],
    "failed": [
      {
        "vehicle_id": "veh-003",
        "error": "Vehicle is in draft status. Publish on your site first."
      }
    ],
    "elasticsearch_reindex_queued": true
  }
}
```

#### Request/Response - Syndication Status

```json
// GET /api/v1/syndication/status?page=1&page_size=20
{
  "data": {
    "summary": {
      "total_vehicles": 234,
      "syndicated_both": 180,
      "tenant_only": 30,
      "agentsmx_only": 5,
      "private": 19
    },
    "vehicles": [
      {
        "id": "veh-001",
        "title": "Toyota Camry 2024",
        "price_mxn": 485000,
        "visibility": "both",
        "is_syndicated": true,
        "syndicated_at": "2026-03-24T10:00:00Z",
        "views_agentsmx_7d": 125,
        "views_tenant_7d": 45,
        "favorites_agentsmx": 8,
        "inquiries_agentsmx": 3
      }
    ],
    "pagination": {
      "page": 1,
      "page_size": 20,
      "total": 234
    }
  }
}
```

#### Request/Response - Syndication Analytics

```json
// GET /api/v1/syndication/analytics?period=30d
{
  "data": {
    "period": "30d",
    "exposure": {
      "total_views_agentsmx": 15230,
      "total_views_tenant": 8940,
      "agentsmx_share_percent": 63.0
    },
    "engagement": {
      "favorites_from_agentsmx": 89,
      "inquiries_from_agentsmx": 34,
      "conversion_rate_agentsmx": 0.22
    },
    "top_performing": [
      {
        "vehicle_id": "veh-001",
        "title": "Toyota Camry 2024",
        "views_agentsmx": 450,
        "favorites": 15,
        "inquiries": 5
      }
    ],
    "recommendation": "12 vehiculos solo estan en tu sitio. Sindicarlos a AgentsMX podria aumentar tus vistas en un 63%."
  }
}
```

#### SQS Events

```python
# Events published to SQS on syndication changes
SYNDICATION_EVENTS = {
    "vehicle.syndicated": {
        "vehicle_id": "uuid",
        "tenant_id": "uuid",
        "visibility": "both|agentsmx_only",
        "timestamp": "iso8601"
    },
    "vehicle.unsyndicated": {
        "vehicle_id": "uuid",
        "tenant_id": "uuid",
        "previous_visibility": "both|agentsmx_only",
        "new_visibility": "tenant_only|private",
        "timestamp": "iso8601"
    },
    "vehicle.visibility_changed": {
        "vehicle_id": "uuid",
        "tenant_id": "uuid",
        "old_visibility": "string",
        "new_visibility": "string",
        "timestamp": "iso8601"
    }
}
```

### Criterios de Aceptacion

1. **AC-001**: POST /api/v1/syndication/publish acepta una lista de vehicle_ids y cambia su visibility a "both" o "agentsmx_only". Solo vehiculos con status="active" pueden ser publicados. Vehiculos en draft retornan error por vehiculo sin detener el batch. Response incluye published[] y failed[] con errores especificos.

2. **AC-002**: POST /api/v1/syndication/unpublish acepta una lista de vehicle_ids y cambia su visibility de "both" a "tenant_only" o de "agentsmx_only" a "private". El vehiculo deja de aparecer en AgentsMX. Response confirma los vehiculos despublicados y la re-indexacion en Elasticsearch.

3. **AC-003**: GET /api/v1/syndication/status retorna un resumen (conteo por visibility) y una lista paginada de vehiculos con su estado de sindicacion. Cada vehiculo incluye: visibility actual, fecha de sindicacion, y metricas de performance en AgentsMX (views, favorites, inquiries de los ultimos 7 dias).

4. **AC-004**: GET /api/v1/syndication/analytics retorna analytics comparativas entre el trafico del tenant y el trafico de AgentsMX para vehiculos sindicados. Incluye: total views por fuente, share porcentual, favorites e inquiries de AgentsMX, conversion rate, y top 5 vehiculos mas performantes en AgentsMX.

5. **AC-005**: La sindicacion emite eventos SQS para cada cambio: "vehicle.syndicated" al publicar en AgentsMX, "vehicle.unsyndicated" al remover de AgentsMX, "vehicle.visibility_changed" para cualquier cambio de visibility. Los consumers re-indexan en Elasticsearch y actualizan cache.

6. **AC-006**: PUT /api/v1/syndication/default-visibility permite configurar la visibility default para nuevos vehiculos del tenant. Valores: both (default), tenant_only, agentsmx_only. Se almacena en TenantConfig.default_vehicle_visibility. Nuevos vehiculos creados heredan este default.

7. **AC-007**: La API incluye una recomendacion inteligente en analytics: si el tenant tiene vehiculos solo en tenant_only, el sistema calcula el incremento potencial de vistas basandose en el ratio promedio de vistas AgentsMX/tenant y lo muestra como "Sindicar X vehiculos podria aumentar vistas en Y%".

8. **AC-008**: Solo vehiculos del tenant actual pueden ser sindicados. Intentar sindicalizar un vehiculo de otro tenant retorna 404. La validacion ocurre tanto en el API layer (tenant_id del JWT) como en la DB (RLS como segunda barrera).

9. **AC-009**: Bulk publish/unpublish soporta hasta 100 vehiculos por operacion. Para mas de 100, retorna 422 con mensaje "Maximum 100 vehicles per batch. Use multiple requests." Si son mas de 20 vehiculos, la operacion es asincrona (202 con job_id).

10. **AC-010**: Cada operacion de sindicacion genera un entry en team_activities: {action: "vehicles_syndicated", details: {count: 3, visibility: "both"}}. Esto permite al equipo del tenant ver quien sindicalizo que vehiculos y cuando.

11. **AC-011**: La re-indexacion de Elasticsearch despues de la sindicacion es eventual (1-5 segundos). El response incluye "elasticsearch_reindex_queued": true para que el frontend pueda mostrar un aviso de que los cambios pueden tardar unos segundos en reflejarse.

12. **AC-012**: Los tests de integracion verifican el flujo completo: crear vehiculo en tenant -> sindicar a AgentsMX -> verificar que aparece en busqueda de AgentsMX -> desindicalizar -> verificar que desaparece de AgentsMX. Test con Elasticsearch real (testcontainers).

### Definition of Done

- [ ] Endpoints de publish/unpublish funcionales con batch support
- [ ] Status y analytics endpoints implementados
- [ ] SQS events para cambios de sindicacion
- [ ] Default visibility configurable
- [ ] Recomendaciones inteligentes en analytics
- [ ] Activity logging para operaciones de sindicacion
- [ ] Tests de integracion con ES real
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- La re-indexacion en ES es asincrona via SQS consumer, no sincrona en el request
- Para bulk operations grandes, considerar SQS con batch processing
- Las metricas de views/favorites por fuente requieren que el tracking de analytics incluya el contexto (tenant vs agentsmx)
- La recomendacion de sindicacion usa una formula simple: (views_agentsmx / views_tenant) * count_tenant_only_vehicles
- Considerar agregar un flag "auto_syndicate" en TenantConfig para sindicacion automatica de nuevos vehiculos

### Dependencias

- Story MKT-BE-042 completada (modelo de visibilidad)
- EP-013 Story MKT-BE-039 (inventario por tenant)
- SQS configurado con colas para eventos de sindicacion
- Elasticsearch 8 con indice multi-tenant

---

## User Story 3: [MKT-BE-044][SVC-VEH-INF] Elasticsearch Multi-Tenant Index

### Descripcion

Como servicio de busqueda, necesito que el indice de Elasticsearch soporte multi-tenancy de manera eficiente. Cada vehiculo indexado incluye tenant_id y visibility como campos filtrables. Las queries se filtran automaticamente segun el contexto: en un white label, solo se retornan vehiculos del tenant con visibilidad correcta; en AgentsMX, se retornan vehiculos de todos los tenants visibles. Las aggregations (facetas de busqueda) tambien respetan los limites de tenant.

### Microservicio

- **Nombre**: SVC-VEH (extension - Elasticsearch infrastructure)
- **Puerto**: 5012
- **Tecnologia**: Python 3.11, elasticsearch-py 8.x
- **Base de datos**: Elasticsearch 8
- **Patron**: Hexagonal Architecture - Infrastructure Layer

### Contexto Tecnico

#### Index Mapping

```json
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "analysis": {
      "analyzer": {
        "spanish_custom": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "spanish_stop", "spanish_stemmer"]
        }
      },
      "filter": {
        "spanish_stop": { "type": "stop", "stopwords": "_spanish_" },
        "spanish_stemmer": { "type": "stemmer", "language": "spanish" }
      }
    }
  },
  "mappings": {
    "properties": {
      "id": { "type": "keyword" },
      "tenant_id": { "type": "keyword" },
      "visibility": { "type": "keyword" },
      "status": { "type": "keyword" },
      "source_name": { "type": "keyword" },
      "source_type": { "type": "keyword" },
      "make": { "type": "keyword", "copy_to": "search_text" },
      "make_display": { "type": "text", "analyzer": "spanish_custom" },
      "model": { "type": "keyword", "copy_to": "search_text" },
      "model_display": { "type": "text", "analyzer": "spanish_custom" },
      "year": { "type": "integer" },
      "price_mxn": { "type": "float" },
      "mileage_km": { "type": "integer" },
      "fuel_type": { "type": "keyword" },
      "transmission": { "type": "keyword" },
      "color": { "type": "keyword" },
      "state": { "type": "keyword" },
      "city": { "type": "keyword" },
      "description": { "type": "text", "analyzer": "spanish_custom" },
      "features": { "type": "keyword" },
      "search_text": { "type": "text", "analyzer": "spanish_custom" },
      "thumbnail_url": { "type": "keyword", "index": false },
      "created_at": { "type": "date" },
      "updated_at": { "type": "date" },
      "views_count": { "type": "integer" },
      "favorites_count": { "type": "integer" },
      "location": { "type": "geo_point" }
    }
  }
}
```

#### Multi-Tenant Query Builder

```python
# inf/elasticsearch/multi_tenant_query_builder.py
from uuid import UUID

MASTER_TENANT_ID = UUID("00000000-0000-0000-0000-000000000001")

class MultiTenantQueryBuilder:
    """Builds Elasticsearch queries with tenant isolation."""

    def build_search_query(self, tenant_id: UUID,
                            search_text: str | None = None,
                            filters: dict | None = None,
                            sort: str = "relevance",
                            page: int = 1,
                            page_size: int = 20) -> dict:
        must_clauses = []
        filter_clauses = [self._visibility_filter(tenant_id)]

        # Always filter active vehicles
        filter_clauses.append({"term": {"status": "active"}})

        # Text search
        if search_text:
            must_clauses.append({
                "multi_match": {
                    "query": search_text,
                    "fields": ["search_text^3", "description"],
                    "type": "best_fields",
                    "fuzziness": "AUTO"
                }
            })

        # Apply filters
        if filters:
            if filters.get("make"):
                filter_clauses.append({"term": {"make": filters["make"]}})
            if filters.get("model"):
                filter_clauses.append({"term": {"model": filters["model"]}})
            if filters.get("year_min") or filters.get("year_max"):
                filter_clauses.append({"range": {"year": {
                    "gte": filters.get("year_min"),
                    "lte": filters.get("year_max"),
                }}})
            if filters.get("price_min") or filters.get("price_max"):
                filter_clauses.append({"range": {"price_mxn": {
                    "gte": filters.get("price_min"),
                    "lte": filters.get("price_max"),
                }}})
            if filters.get("fuel_type"):
                filter_clauses.append({"term": {"fuel_type": filters["fuel_type"]}})
            if filters.get("transmission"):
                filter_clauses.append({"term": {"transmission": filters["transmission"]}})
            if filters.get("state"):
                filter_clauses.append({"term": {"state": filters["state"]}})

        query = {
            "bool": {
                "must": must_clauses if must_clauses else [{"match_all": {}}],
                "filter": filter_clauses
            }
        }

        # Aggregations (also tenant-scoped)
        aggs = self._build_aggregations(tenant_id)

        # Sort
        sort_clause = self._build_sort(sort)

        return {
            "query": query,
            "aggs": aggs,
            "sort": sort_clause,
            "from": (page - 1) * page_size,
            "size": page_size,
            "track_total_hits": True,
        }

    def _visibility_filter(self, tenant_id: UUID) -> dict:
        """Build visibility filter based on requesting context."""
        if tenant_id == MASTER_TENANT_ID:
            return {
                "terms": {"visibility": ["agentsmx_only", "both"]}
            }
        return {
            "bool": {
                "must": [
                    {"term": {"tenant_id": str(tenant_id)}},
                    {"terms": {"visibility": ["tenant_only", "both"]}}
                ]
            }
        }

    def _build_aggregations(self, tenant_id: UUID) -> dict:
        """Build aggregations respecting tenant boundaries."""
        # Post-filter aggregations ensure facets are scoped correctly
        return {
            "makes": {
                "terms": { "field": "make", "size": 50 }
            },
            "fuel_types": {
                "terms": { "field": "fuel_type", "size": 10 }
            },
            "transmissions": {
                "terms": { "field": "transmission", "size": 5 }
            },
            "price_ranges": {
                "range": {
                    "field": "price_mxn",
                    "ranges": [
                        { "to": 100000, "key": "bajo_100k" },
                        { "from": 100000, "to": 300000, "key": "100k_300k" },
                        { "from": 300000, "to": 500000, "key": "300k_500k" },
                        { "from": 500000, "to": 1000000, "key": "500k_1m" },
                        { "from": 1000000, "key": "sobre_1m" }
                    ]
                }
            },
            "year_range": {
                "stats": { "field": "year" }
            },
            "states": {
                "terms": { "field": "state", "size": 32 }
            },
            "sources": {
                "terms": { "field": "source_name", "size": 20 }
            }
        }

    def _build_sort(self, sort: str) -> list:
        sort_options = {
            "relevance": [{"_score": "desc"}, {"created_at": "desc"}],
            "price_asc": [{"price_mxn": "asc"}],
            "price_desc": [{"price_mxn": "desc"}],
            "newest": [{"created_at": "desc"}],
            "oldest": [{"created_at": "asc"}],
            "popular": [{"views_count": "desc"}],
            "mileage_asc": [{"mileage_km": "asc"}],
        }
        return sort_options.get(sort, sort_options["relevance"])
```

#### Re-indexation Consumer

```python
# inf/consumers/vehicle_reindex_consumer.py
class VehicleReindexConsumer:
    """SQS consumer that re-indexes vehicles in Elasticsearch."""

    def handle_message(self, message: dict) -> None:
        event_type = message["event_type"]

        if event_type == "vehicle.visibility_changed":
            vehicle_id = message["vehicle_id"]
            new_visibility = message["new_visibility"]
            if new_visibility == "private":
                self._es.delete(index="vehicles", id=vehicle_id,
                                ignore=[404])
            else:
                vehicle = self._repo.find_by_id(vehicle_id)
                self._es.index(index="vehicles", id=str(vehicle.id),
                               document=self._serialize(vehicle))

        elif event_type in ("vehicle.created", "vehicle.updated"):
            vehicle = self._repo.find_by_id(message["vehicle_id"])
            if vehicle.visibility != "private":
                self._es.index(index="vehicles", id=str(vehicle.id),
                               document=self._serialize(vehicle))

        elif event_type == "vehicle.deleted":
            self._es.delete(index="vehicles", id=message["vehicle_id"],
                            ignore=[404])
```

### Criterios de Aceptacion

1. **AC-001**: El index mapping de Elasticsearch incluye campos tenant_id (keyword) y visibility (keyword) como campos filtrables. Ambos campos son obligatorios en cada documento indexado. El mapping incluye analyzer spanish_custom para busqueda en espanol con stemming y stopwords.

2. **AC-002**: El MultiTenantQueryBuilder genera queries correctas para ambos contextos: (a) white label (tenant_id especifico + visibility in tenant_only/both), (b) AgentsMX (sin filtro de tenant_id + visibility in agentsmx_only/both). Se verifican los queries generados con unit tests que inspeccionan la estructura JSON.

3. **AC-003**: Las aggregations (facetas) se calculan respetando el filtro de tenant. En un white label, la faceta "makes" solo cuenta marcas de vehiculos del tenant. En AgentsMX, cuenta todas las marcas de vehiculos visibles. Se verifica con test: tenant con solo Toyotas, faceta retorna solo Toyota.

4. **AC-004**: La busqueda por texto usa multi_match con fuzzy matching sobre campos search_text (boost x3) y description. Buscar "Toyta" (typo) retorna vehiculos Toyota. Buscar "camioneta familiar" retorna vehiculos con esas palabras en la descripcion.

5. **AC-005**: Los sorts disponibles son: relevance (default, por score + created_at), price_asc, price_desc, newest (created_at desc), oldest, popular (views_count desc), mileage_asc. Todos los sorts se aplican despues del filtro de tenant/visibility.

6. **AC-006**: El consumer SQS de re-indexacion maneja eventos: vehicle.created (indexar si no private), vehicle.updated (re-indexar), vehicle.deleted (eliminar del indice), vehicle.visibility_changed (re-indexar o eliminar si private). El consumer es idempotente: procesar el mismo evento dos veces no causa problemas.

7. **AC-007**: Vehiculos con visibility="private" se eliminan del indice de Elasticsearch (no se indexan). Cambiar de private a any_other_visibility re-indexa el vehiculo. Esto garantiza que vehiculos privados no aparecen en ninguna busqueda.

8. **AC-008**: En AgentsMX, la aggregation "sources" muestra los nombres de los tenants como fuentes filtrables. Los usuarios pueden filtrar por "Mi Autos Puebla" o "Kavak" para ver solo vehiculos de esa fuente. Se usa el campo source_name para esta faceta.

9. **AC-009**: El tenant_id se usa como routing key en Elasticsearch para vehiculos de tenants individuales. Esto mejora el performance de queries scoped a un tenant porque los shards consultados se reducen. Para AgentsMX (cross-tenant), la query va a todos los shards.

10. **AC-010**: Un full re-index de los 11,000+ vehiculos actuales completa en menos de 5 minutos. Se provee un script de bulk re-index que lee de PostgreSQL y escribe a ES en batches de 500 documentos. El script soporta re-index parcial por tenant_id.

11. **AC-011**: La latencia de busqueda es menor a 100ms (p95) para queries tipicas (texto + 2-3 filtros + aggregations) con 50,000 documentos indexados. Se verifica con benchmark usando datos sinteticos.

12. **AC-012**: Los tests de integracion usan Elasticsearch real (via testcontainers o ES local) y verifican: indexacion correcta, busqueda multi-tenant, aggregations scoped, re-indexacion via consumer, eliminacion de vehiculos private, fuzzy search, sort options.

### Definition of Done

- [ ] Index mapping creado con tenant_id y visibility
- [ ] MultiTenantQueryBuilder implementado y testeado
- [ ] Aggregations respentan boundaries de tenant
- [ ] Consumer SQS de re-indexacion funcional
- [ ] Script de bulk re-index disponible
- [ ] Spanish analyzer configurado y verificado
- [ ] Performance benchmark < 100ms p95
- [ ] Tests de integracion con ES real
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- Usar elasticsearch-py 8.x con API async para mejor performance
- El routing key por tenant mejora performance pero complica re-index global; documentar trade-offs
- Para Spanish analyzer: usar elision filter para "el", "la", "los", "las"
- Considerar un indice alias (vehicles_v1 -> vehicles) para zero-downtime re-index
- El bulk re-index debe usar scroll API o search_after para datasets grandes

### Dependencias

- Story MKT-BE-042 completada (modelo de visibilidad con campos en DB)
- EP-003 completado (Elasticsearch base configurado)
- SQS colas de eventos de vehiculos
- testcontainers o Elasticsearch local para tests

---

## User Story 4: [MKT-FE-034][FE-FEAT-CAT] Catalogo Multi-Tenant Aware

### Descripcion

Como usuario del marketplace, necesito que el catalogo de vehiculos se adapte segun el contexto: en un white label, veo solo vehiculos del tenant con el branding del tenant; en AgentsMX, veo vehiculos de todos los tenants con un badge que indica la fuente. Los filtros incluyen la posibilidad de filtrar por fuente/tenant en AgentsMX. Al hacer click en el badge de un tenant, navego a una pagina de perfil del tenant.

### Microservicio

- **Nombre**: Frontend Angular 18 - Catalog Module
- **Puerto**: 4200 (dev)
- **Tecnologia**: Angular 18, TypeScript 5.4, Tailwind CSS v4, Standalone Components, Signals
- **Patron**: Hexagonal Architecture (Frontend) - Presentation Layer

### Contexto Tecnico

#### Structure de Archivos

```
src/app/
  features/
    catalog/
      presentation/
        components/
          vehicle-card/
            vehicle-card.component.ts       # Extended with source badge
            vehicle-card.component.html
            vehicle-card.component.spec.ts
          source-badge/
            source-badge.component.ts       # "Publicado por [Tenant]" badge
            source-badge.component.html
            source-badge.component.spec.ts
          source-filter/
            source-filter.component.ts      # Filter by source (AgentsMX only)
            source-filter.component.html
            source-filter.component.spec.ts
          tenant-profile-card/
            tenant-profile-card.component.ts
            tenant-profile-card.component.html
            tenant-profile-card.component.spec.ts
        pages/
          tenant-profile/
            tenant-profile.page.ts          # /tenants/:slug page
            tenant-profile.page.html
            tenant-profile.page.spec.ts
```

#### Source Badge Component

```typescript
// presentation/components/source-badge/source-badge.component.ts
@Component({
  selector: 'app-source-badge',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (showBadge()) {
      <a [routerLink]="['/tenants', sourceSlug()]"
         class="inline-flex items-center gap-1.5 px-2 py-1 rounded-full
                bg-gray-50 hover:bg-gray-100 transition-colors
                text-xs text-gray-600 hover:text-gray-800"
         [title]="'Ver todos los vehiculos de ' + sourceName()">
        @if (sourceLogoUrl()) {
          <img [src]="sourceLogoUrl()" [alt]="sourceName()"
               class="h-4 w-4 rounded-full object-cover" />
        }
        <span>{{ sourceName() }}</span>
      </a>
    }
  `,
})
export class SourceBadgeComponent {
  readonly sourceName = input.required<string>();
  readonly sourceSlug = input.required<string>();
  readonly sourceLogoUrl = input<string | null>(null);
  readonly sourceType = input<string>('tenant');

  private readonly themeEngine = inject(ThemeEngineService);

  readonly showBadge = computed(() => {
    // Show badge only on AgentsMX (master tenant)
    const config = this.themeEngine.config();
    return config?.tenant.slug === 'agentsmx';
  });
}
```

#### Vehicle Card Extended Template

```html
<!-- vehicle-card.component.html (extended) -->
<article class="bg-white rounded-theme shadow-sm border border-gray-100
                overflow-hidden hover:shadow-md transition-all group">
  <!-- Image -->
  <div class="relative aspect-[4/3] overflow-hidden">
    <img [src]="vehicle().thumbnail_url"
         [alt]="vehicle().title"
         class="w-full h-full object-cover group-hover:scale-105 transition-transform"
         loading="lazy" />

    <!-- Source Badge (only on AgentsMX) -->
    <div class="absolute top-2 left-2">
      <app-source-badge
        [sourceName]="vehicle().source_name"
        [sourceSlug]="vehicle().source_slug"
        [sourceLogoUrl]="vehicle().source_logo_url"
        [sourceType]="vehicle().source_type" />
    </div>

    <!-- Favorite Button -->
    <button class="absolute top-2 right-2 p-2 rounded-full bg-white/80
                   hover:bg-white transition-colors"
            (click)="toggleFavorite($event)">
      <svg class="w-5 h-5"
           [class.text-red-500]="isFavorited()"
           [class.fill-red-500]="isFavorited()"
           [class.text-gray-400]="!isFavorited()">
        <!-- heart icon -->
      </svg>
    </button>
  </div>

  <!-- Content -->
  <div class="p-4">
    <h3 class="font-heading font-semibold text-gray-900 truncate">
      {{ vehicle().make }} {{ vehicle().model }} {{ vehicle().year }}
    </h3>
    <p class="text-xl font-bold text-primary mt-1">
      {{ vehicle().price_mxn | currency:'MXN':'symbol':'1.0-0' }}
    </p>
    <div class="flex items-center gap-3 mt-2 text-xs text-gray-500">
      <span>{{ vehicle().mileage_km | number }} km</span>
      <span class="w-1 h-1 rounded-full bg-gray-300"></span>
      <span>{{ vehicle().fuel_type }}</span>
      <span class="w-1 h-1 rounded-full bg-gray-300"></span>
      <span>{{ vehicle().transmission }}</span>
    </div>
    <div class="flex items-center gap-2 mt-2 text-xs text-gray-400">
      <svg class="w-3.5 h-3.5"><!-- location icon --></svg>
      <span>{{ vehicle().city }}, {{ vehicle().state }}</span>
    </div>
  </div>
</article>
```

### Criterios de Aceptacion

1. **AC-001**: En un white label, el catalogo muestra solo vehiculos del tenant. No hay badge de fuente. El branding del tenant se aplica: colores primarios en precios, fonts del tenant en titulos, border-radius del tenant en cards. Los filtros no incluyen "fuente" ya que todos los vehiculos son del tenant.

2. **AC-002**: En AgentsMX, cada vehiculo de un tenant muestra un badge "Publicado por [Tenant Name]" con el logo pequeno del tenant (16x16px redondeado). Vehiculos propios de AgentsMX (tenant maestro) no muestran badge. Vehiculos de scrappers muestran badge con el nombre de la fuente (Kavak, Albacar, etc.).

3. **AC-003**: Click en el badge de fuente navega a /tenants/:slug que muestra el perfil del tenant: nombre, logo grande, descripcion, vehiculos del tenant (grid), link al white label del tenant. Esta pagina es publica y no requiere autenticacion.

4. **AC-004**: En AgentsMX, los filtros laterales incluyen una seccion "Fuente" que lista las fuentes disponibles con conteo de vehiculos: "Mi Autos Puebla (234)", "Kavak (1,200)", etc. Click en una fuente filtra el catalogo. Se pueden seleccionar multiples fuentes.

5. **AC-005**: Las facetas de busqueda (makes, fuel_types, price_ranges, etc.) se calculan correctamente segun el contexto. En white label, solo cuentan vehiculos del tenant. En AgentsMX, cuentan todos los vehiculos visibles. Se verifica: tenant con solo Toyotas muestra "Toyota (234)" como unica marca.

6. **AC-006**: La paginacion funciona correctamente en ambos contextos. En white label con 234 vehiculos y page_size=20, hay 12 paginas. En AgentsMX con 11,000+ vehiculos, la paginacion es fluida. Considerar infinite scroll como alternativa a paginacion tradicional.

7. **AC-007**: El detalle de vehiculo (/vehicles/:id) muestra el badge de fuente en AgentsMX. Si el vehiculo es de un tenant, incluye un banner lateral: "Este vehiculo es ofrecido por [Tenant Name]" con boton "Visitar [Tenant Name]" que abre el white label del tenant.

8. **AC-008**: La busqueda por texto funciona en ambos contextos con los mismos resultados de relevancia. Buscar "Toyota Camry" en white label retorna solo Camrys del tenant. Buscar "Toyota Camry" en AgentsMX retorna Camrys de todos los tenants con fuente indicada.

9. **AC-009**: Las vehicle cards son responsive: 1 columna en mobile (<640px), 2 columnas en tablet (640-1024px), 3 columnas en desktop (1024-1280px), 4 columnas en wide (>1280px). El badge de fuente no se trunca en mobile.

10. **AC-010**: La pagina de tenant profile (/tenants/:slug) muestra: hero banner con logo y nombre del tenant, estadisticas (total vehiculos, ubicacion), grid de vehiculos del tenant (los primeros 20), boton "Ver todos en [Tenant Name]" que redirige al white label del tenant, y link "Visitar sitio web" al custom domain si existe.

11. **AC-011**: Si un usuario navega directamente a un vehiculo con visibility=tenant_only en AgentsMX (ej: via URL compartida), recibe 404 con mensaje "Este vehiculo no esta disponible en AgentsMX". Si navega a un vehiculo de tenant suspendido, recibe 404.

12. **AC-012**: Los tests verifican: (a) badge se muestra solo en AgentsMX, (b) badge no aparece en white label, (c) source filter funciona, (d) facetas son correctas por contexto, (e) tenant profile renderiza correctamente, (f) 404 para vehiculos no visibles.

### Definition of Done

- [ ] Vehicle card con source badge en AgentsMX
- [ ] Source filter en facetas de busqueda
- [ ] Tenant profile page funcional
- [ ] Catalogo scoped por tenant en white labels
- [ ] Responsive design verificado
- [ ] Tests unitarios >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- El source_logo_url debe ser thumbnail pequeno (16x16 o 32x32) para no afectar performance
- Lazy loading de imagenes con loading="lazy" para vehicle cards
- El tenant profile page usa resolver de ruta para cargar datos antes de renderizar
- Considerar prefetch de datos de tenant cuando el usuario hace hover sobre el badge
- Las URLs de tenant profile deben ser SEO-friendly: /tenants/mi-autos-puebla

### Dependencias

- Story MKT-BE-044 completada (ES multi-tenant)
- Story MKT-FE-028 completada (theme engine)
- EP-003 completado (catalogo base)
- Router configurado con ruta /tenants/:slug

---

## User Story 5: [MKT-BE-045][SVC-PUR-DOM] Purchase Flow Multi-Tenant

### Descripcion

Como servicio de compras, necesito que el flujo de compra respete el contexto multi-tenant: una compra realizada en un white label se atribuye al tenant, las comisiones se calculan segun el plan del tenant, las notificaciones van tanto al comprador como al tenant admin, y el revenue se trackea por tenant para reconciliacion. Compras de vehiculos de un tenant en AgentsMX generan commission split.

### Microservicio

- **Nombre**: SVC-PUR (extension del servicio existente)
- **Puerto**: 5013
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0
- **Base de datos**: PostgreSQL 15, Redis 7
- **Patron**: Hexagonal Architecture - Domain Layer Extension

### Contexto Tecnico

#### Domain Model Extension

```python
# dom/models/purchase.py (extended)
@dataclass
class Purchase:
    id: UUID
    # ... existing fields ...
    tenant_id: UUID                     # Tenant where purchase was initiated
    vehicle_tenant_id: UUID             # Tenant that owns the vehicle
    purchase_context: str               # "tenant_whitelabel" or "agentsmx"
    commission_rate: float = 0.0        # AgentsMX commission rate
    commission_amount_mxn: float = 0.0  # Calculated commission
    tenant_revenue_mxn: float = 0.0     # Revenue attributed to tenant
    financing_referral_amount: float = 0.0
    insurance_referral_amount: float = 0.0

@dataclass
class CommissionCalculation:
    purchase_id: UUID
    vehicle_price_mxn: float
    commission_rate: float              # From tenant's plan
    commission_amount_mxn: float        # price * rate
    financing_referral_rate: float      # If financing was used
    financing_referral_amount: float
    insurance_referral_rate: float      # If insurance was used
    insurance_referral_amount: float
    total_agentsmx_revenue: float       # commission + referrals
    tenant_net_revenue: float           # price - total_agentsmx_revenue
    calculated_at: datetime
```

```python
# dom/services/commission_service.py
class CommissionService:
    """Pure domain service for commission calculations."""

    def calculate(self, vehicle_price: float,
                  tenant_plan: TenantPlan,
                  has_financing: bool = False,
                  has_insurance: bool = False) -> CommissionCalculation:
        commission_rate = tenant_plan.commission_rate_sale
        commission = vehicle_price * commission_rate

        financing_referral = 0.0
        if has_financing:
            financing_referral = vehicle_price * tenant_plan.commission_rate_financing

        insurance_referral = 0.0
        if has_insurance:
            insurance_referral = vehicle_price * tenant_plan.commission_rate_insurance

        total_agentsmx = commission + financing_referral + insurance_referral
        tenant_net = vehicle_price - total_agentsmx

        return CommissionCalculation(
            commission_rate=commission_rate,
            commission_amount_mxn=round(commission, 2),
            financing_referral_rate=tenant_plan.commission_rate_financing,
            financing_referral_amount=round(financing_referral, 2),
            insurance_referral_rate=tenant_plan.commission_rate_insurance,
            insurance_referral_amount=round(insurance_referral, 2),
            total_agentsmx_revenue=round(total_agentsmx, 2),
            tenant_net_revenue=round(tenant_net, 2),
            calculated_at=datetime.utcnow(),
        )
```

#### Purchase Flow Variations

```
Scenario 1: User buys on tenant white label
  - tenant_id = tenant's UUID
  - vehicle_tenant_id = same tenant
  - purchase_context = "tenant_whitelabel"
  - commission calculated per tenant's plan
  - Notification to: buyer + tenant_admin

Scenario 2: User buys tenant vehicle on AgentsMX
  - tenant_id = master tenant (AgentsMX)
  - vehicle_tenant_id = original tenant
  - purchase_context = "agentsmx"
  - commission calculated per vehicle owner's plan
  - Notification to: buyer + tenant_admin + AgentsMX admin

Scenario 3: User buys AgentsMX-native vehicle on AgentsMX
  - tenant_id = master tenant
  - vehicle_tenant_id = master tenant
  - purchase_context = "agentsmx"
  - No commission (own vehicle)
  - Notification to: buyer + AgentsMX admin
```

#### Revenue Tracking

```python
# dom/models/revenue_tracking.py
@dataclass
class TenantRevenueEntry:
    id: UUID
    tenant_id: UUID
    purchase_id: UUID
    period: str                         # "2026-03"
    vehicle_price_mxn: float
    commission_paid_mxn: float
    financing_referral_paid: float
    insurance_referral_paid: float
    net_revenue_mxn: float
    purchase_context: str               # Where the sale happened
    created_at: datetime
```

```sql
CREATE TABLE tenant_revenue_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    purchase_id UUID NOT NULL REFERENCES purchases(id),
    period VARCHAR(7) NOT NULL,          -- "2026-03"
    vehicle_price_mxn NUMERIC(12,2) NOT NULL,
    commission_paid_mxn NUMERIC(12,2) NOT NULL DEFAULT 0,
    financing_referral_paid NUMERIC(12,2) NOT NULL DEFAULT 0,
    insurance_referral_paid NUMERIC(12,2) NOT NULL DEFAULT 0,
    net_revenue_mxn NUMERIC(12,2) NOT NULL,
    purchase_context VARCHAR(20) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_revenue_tenant_period ON tenant_revenue_entries(tenant_id, period);
CREATE INDEX idx_revenue_period ON tenant_revenue_entries(period);
```

### Criterios de Aceptacion

1. **AC-001**: Cuando un usuario inicia una compra en un white label, la purchase se crea con tenant_id del tenant actual, vehicle_tenant_id del dueno del vehiculo (mismo tenant en este caso), y purchase_context="tenant_whitelabel". La commission se calcula segun el plan del tenant: Free 5%, Basic 3%, Pro 2%, Enterprise negotiable.

2. **AC-002**: Cuando un usuario compra un vehiculo de tenant X en AgentsMX, la purchase se crea con tenant_id=master, vehicle_tenant_id=tenant_X, purchase_context="agentsmx". La commission se calcula usando el plan de tenant X. Las notificaciones van al buyer, al admin de tenant X, y al admin de AgentsMX.

3. **AC-003**: El CommissionService es un domain service puro que calcula: (a) commission base = price * tenant_commission_rate, (b) financing referral = price * financing_rate (si aplica), (c) insurance referral = price * insurance_rate (si aplica), (d) total_agentsmx = a+b+c, (e) tenant_net = price - total_agentsmx. Todos los montos redondeados a 2 decimales.

4. **AC-004**: Para vehiculos nativos de AgentsMX (vehicle_tenant_id = master), no se calcula comision (commission_rate = 0, commission_amount = 0). El revenue completo es de AgentsMX.

5. **AC-005**: Un TenantRevenueEntry se crea para cada compra que involucre un vehiculo de tenant. El entry incluye: tenant_id, purchase_id, periodo (YYYY-MM), desglose de montos (precio, comision, referrals, neto). Esta tabla alimenta los reportes de revenue por tenant.

6. **AC-006**: Las notificaciones de compra incluyen contexto de tenant: en white label, el email de confirmacion al buyer usa el branding del tenant. En AgentsMX, si el vehiculo es de un tenant, el email incluye "Vehiculo ofrecido por [Tenant Name]" con informacion de contacto del tenant.

7. **AC-007**: GET /api/v1/admin/revenue (tenant scoped) retorna el revenue del tenant: total del mes, desglose por compra (precio, comision pagada, referrals pagados, neto), comparacion vs mes anterior, y grafico mensual de ultimos 12 meses.

8. **AC-008**: GET /api/v1/admin/revenue/reconciliation retorna el reporte de reconciliacion mensual para el super admin: por cada tenant, total ventas, total comisiones, total referrals, total a pagar/cobrar. Este reporte alimenta el proceso de facturacion.

9. **AC-009**: Si un tenant esta en plan Free y tiene una venta de $500,000 MXN, la comision es $25,000 MXN (5%). Si el buyer uso financiamiento referido, se agrega 2% ($10,000). Total AgentsMX: $35,000. Tenant net: $465,000. Se verifica con test con numeros exactos.

10. **AC-010**: El flujo de compra no se interrumpe si el calculo de comision falla (graceful degradation). Se registra un log error y la compra procede con commission_amount=0. Un job de reconciliacion posterior puede corregir comisiones faltantes.

11. **AC-011**: Las transacciones de compra son atomicas: la compra, el revenue entry, y la notificacion se procesan en una transaccion de DB. Si la notificacion falla (SQS), la compra no se revierte (notificacion es best-effort via SQS).

12. **AC-012**: Los tests verifican los 3 escenarios de compra (white label, AgentsMX con vehiculo de tenant, AgentsMX con vehiculo propio), calculo de comisiones con diferentes planes y combinaciones (con/sin financiamiento, con/sin seguro), y creacion correcta de revenue entries.

### Definition of Done

- [ ] Purchase model extendido con campos multi-tenant
- [ ] CommissionService implementado y testeado
- [ ] Revenue tracking table y entries funcionales
- [ ] Notificaciones con contexto de tenant
- [ ] Revenue endpoints para tenant y super admin
- [ ] Tests unitarios para commission calculations
- [ ] Tests de integracion para los 3 escenarios de compra
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- Usar NUMERIC(12,2) en PostgreSQL para montos financieros (no FLOAT)
- Las comisiones se almacenan por transaccion, no se recalculan; si el plan cambia, comisiones existentes no cambian
- El periodo (YYYY-MM) facilita queries de reportes mensuales con indice
- Considerar eventos SQS para revenue entries (desacoplar del flujo de compra principal)
- Para Enterprise con comisiones negociables, usar campo custom en TenantConfig

### Dependencias

- EP-011 completado (tenant_id en purchases)
- EP-005 completado (flujo de compra base)
- EP-011 Story MKT-BE-031 (TenantConfig con commission rates)
- SVC-NTF para notificaciones con tenant context

---

## User Story 6: [MKT-INT-006] Integracion Loteros/Dealers como Tenants

### Descripcion

Como sistema de integracion, necesito un flujo simplificado de onboarding para dealers pequenos (loteros) existentes en Mexico. Un lotero puede registrarse, obtener automaticamente un tenant con plan Free, importar su inventario existente (del scrapper o por CSV), y tener su propio white label funcionando en minutos. Los sources existentes (kavak, albacar, etc.) se mapean como "system tenants" para atribucion correcta en el marketplace.

### Microservicio

- **Nombre**: SVC-TNT + SVC-VEH (coordinacion entre ambos)
- **Puerto**: 5023 (SVC-TNT), 5012 (SVC-VEH)
- **Tecnologia**: Python 3.11, Flask 3.0
- **Base de datos**: PostgreSQL 15 (marketplace + scrapper_nacional)
- **Patron**: Hexagonal Architecture - Application Layer (Orchestration)

### Contexto Tecnico

#### Endpoints

```
# Self-service onboarding (public, with auth after registration)
POST /api/v1/onboarding/register             -> Register dealer + create tenant
GET  /api/v1/onboarding/status               -> Onboarding progress
POST /api/v1/onboarding/import-inventory     -> Import from scrapper data or CSV
POST /api/v1/onboarding/complete             -> Finalize onboarding

# System tenant management (internal/admin)
POST /api/v1/admin/system-tenants/create     -> Create system tenant for scrapper source
GET  /api/v1/admin/system-tenants            -> List system tenants (kavak, albacar, etc.)
POST /api/v1/admin/system-tenants/:id/sync   -> Sync scrapper data to system tenant
```

#### Onboarding Flow

```
1. Dealer visits agentsmx.com/for-dealers
   |
   v
2. Registration form: name, email, phone, business name, state, city
   |
   v
3. Auto-create: User (Cognito) + Tenant (plan=free, status=trial)
   |
   v
4. Onboarding wizard:
   a. Configure branding (logo upload, color selection - 5 presets)
   b. Import inventory (3 options):
      - CSV upload
      - Manual entry (1 vehicle to start)
      - Connect existing source (if they're already in scrapper_nacional)
   c. Review & confirm
   |
   v
5. White label live at {slug}.agentsmx.com
   |
   v
6. Welcome email with: link to admin panel, quick-start guide, support contact
```

#### Request/Response - Register Dealer

```json
// POST /api/v1/onboarding/register
{
  "dealer_name": "Autos Don Pepe",
  "owner_name": "Jose Perez",
  "email": "pepe@autosdonpepe.com",
  "phone": "+5212221234567",
  "password": "SecurePass123!",
  "state": "Puebla",
  "city": "Puebla de Zaragoza",
  "accept_terms": true
}

// Response 201
{
  "data": {
    "user": {
      "id": "usr-abc123",
      "email": "pepe@autosdonpepe.com",
      "name": "Jose Perez"
    },
    "tenant": {
      "id": "tnt-xyz789",
      "name": "Autos Don Pepe",
      "slug": "autos-don-pepe",
      "subdomain": "autosdonpepe",
      "plan": "free",
      "status": "trial",
      "trial_ends_at": "2026-04-23T00:00:00Z",
      "url": "https://autosdonpepe.agentsmx.com"
    },
    "access_token": "eyJhbGciOiJSUzI1NiIs...",
    "onboarding_url": "https://autosdonpepe.agentsmx.com/onboarding"
  }
}
```

#### Request/Response - Import from Scrapper

```json
// POST /api/v1/onboarding/import-inventory
{
  "source": "scrapper_nacional",
  "source_dealer_name": "Autos Don Pepe",
  "match_criteria": {
    "state": "Puebla",
    "dealer_name_contains": "Don Pepe"
  }
}

// Response 200
{
  "data": {
    "matched_vehicles": 23,
    "preview": [
      {
        "make": "Nissan",
        "model": "Versa",
        "year": 2023,
        "price_mxn": 285000,
        "source_url": "https://scrapper.example/vehicles/12345"
      }
    ],
    "import_ready": true,
    "confirmation_required": true
  }
}

// POST /api/v1/onboarding/import-inventory/confirm
{
  "confirm": true,
  "visibility": "both"
}

// Response 202
{
  "data": {
    "job_id": "import-job-abc",
    "total_vehicles": 23,
    "status": "processing"
  }
}
```

#### System Tenants for Existing Sources

```python
# Map existing scrapper sources to system tenants
SYSTEM_TENANT_MAPPINGS = {
    "kavak": {
        "name": "Kavak",
        "slug": "kavak",
        "is_system_tenant": True,
        "source_type": "scrapper",
        "auto_sync": True,  # Automatically sync new vehicles from scrapper
    },
    "albacar": {
        "name": "Albacar",
        "slug": "albacar",
        "is_system_tenant": True,
        "source_type": "scrapper",
        "auto_sync": True,
    },
    "seminuevos_com": {
        "name": "Seminuevos.com",
        "slug": "seminuevos",
        "is_system_tenant": True,
        "source_type": "scrapper",
        "auto_sync": True,
    },
    # ... 18 sources total
}
```

### Criterios de Aceptacion

1. **AC-001**: POST /api/v1/onboarding/register crea en una sola operacion: (a) usuario en Cognito con email/password, (b) usuario en DB con datos de perfil, (c) tenant con plan=free y status=trial, (d) TenantConfig con defaults, (e) UserTenantMembership con role=owner. Retorna access_token para que el dealer inicie sesion inmediatamente.

2. **AC-002**: El slug del tenant se genera automaticamente desde dealer_name (slugify). El subdomain se genera limpiando caracteres especiales (ej: "Autos Don Pepe" -> slug "autos-don-pepe", subdomain "autosdonpepe"). Si hay colision, se agrega un sufijo numerico (autosdonpepe1).

3. **AC-003**: El trial period es de 30 dias. Durante el trial, el tenant tiene todas las funcionalidades del plan Free. Al expirar, se notifica 7 dias antes, 1 dia antes, y al expirar. Si no upgrade, el white label sigue activo pero con banner "Trial expirado - Upgrade para continuar".

4. **AC-004**: El onboarding wizard tiene 3 pasos: (a) Branding basico (elegir 1 de 5 presets de colores + upload logo opcional), (b) Importar inventario (CSV, manual, o conectar fuente), (c) Review y confirmar. El progreso se guarda, el dealer puede salir y retomar.

5. **AC-005**: La importacion desde scrapper_nacional busca vehiculos existentes que coincidan con criterios del dealer: state, city, dealer_name. Muestra un preview de los vehiculos encontrados (primeros 5) y pide confirmacion antes de importar. Los vehiculos importados se asignan al tenant con visibility=both.

6. **AC-006**: Los 18 sources existentes del scrapper (kavak, albacar, etc.) se mapean como "system tenants" con flag is_system_tenant=True. Estos tenants se crean automaticamente por el admin y no tienen un owner humano. Sus vehiculos se sincronizan periodicamente desde el scrapper.

7. **AC-007**: Un sync job periodico (cada 6 horas) actualiza los vehiculos de system tenants desde scrapper_nacional: nuevos vehiculos se crean, vehiculos eliminados del source se marcan como archived, precios actualizados se reflejan con entry en price_history. El job es idempotente.

8. **AC-008**: POST /api/v1/admin/system-tenants/create (super admin) crea un tenant de sistema para una fuente del scrapper. Requiere: source_name, display_name, logo_url. El tenant se crea con plan="enterprise" (sin limites), status="active", y branding con el logo de la fuente.

9. **AC-009**: El landing page /for-dealers es una pagina publica que explica los beneficios del white label: "Tu propio sitio de autos en minutos", precios de planes, testimonios, y boton "Registrate Gratis". Es SEO-optimizada con meta tags, schema.org markup, y responsive design.

10. **AC-010**: Despues del onboarding, se envia un email de bienvenida al dealer con: link al admin panel, link al white label publico, guia rapida (PDF) de como administrar su inventario, y contacto de soporte. El email usa el branding seleccionado durante el onboarding.

11. **AC-011**: El registro valida: email unico en el sistema (no solo en el tenant), telefono formato mexicano (+52...), password con requisitos de seguridad (8+ chars, mayuscula, numero), accept_terms=true requerido, dealer_name minimo 3 caracteres. Errores especificos por campo.

12. **AC-012**: Los tests de integracion verifican el flujo completo de onboarding: register -> create tenant -> import vehicles -> complete. Un test verifica que el white label es accesible via subdomain despues del onboarding. Un test verifica el sync de system tenants desde scrapper data.

13. **AC-013**: Metricas de onboarding se trackean: tasa de conversion (visitas a /for-dealers -> registros), tasa de completado (registros -> onboarding completado), tiempo promedio de onboarding, inventario importado promedio. Se exponen en el dashboard de super admin.

### Definition of Done

- [ ] Endpoint de registro de dealer funcional
- [ ] Auto-creacion de tenant + user + membership
- [ ] Onboarding wizard de 3 pasos
- [ ] Importacion desde scrapper_nacional funcional
- [ ] System tenants para 18 fuentes existentes
- [ ] Sync job periodico funcional
- [ ] Landing page /for-dealers creada
- [ ] Email de bienvenida funcional
- [ ] Tests de integracion del flujo completo
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- La importacion desde scrapper_nacional requiere acceso read-only a la DB de scrapper
- Considerar usar una vista (VIEW) en PostgreSQL para unificar scrapper_nacional con la tabla vehicles
- El sync job debe ser resiliente a datos incompletos del scrapper (campos faltantes)
- Para system tenants, el branding se configura una vez por el admin; no tienen panel de self-service
- El onboarding debe completarse en menos de 5 minutos para minimizar abandono

### Dependencias

- EP-011 completado (arquitectura multi-tenant)
- EP-013 completado (inventario por tenant)
- Acceso read-only a la DB scrapper_nacional
- SVC-NTF para emails de bienvenida
- Landing page /for-dealers diseñada (mockup)
