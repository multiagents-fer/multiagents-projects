# [MKT-EP-003] Catalogo de Vehiculos & Motor de Busqueda

**Sprint**: 2-4
**Priority**: Critical
**Epic Owner**: Tech Lead
**Estimated Points**: 110
**Teams**: Backend, Frontend, Data Engineering

---

## Resumen del Epic

Este epic implementa la funcionalidad core del marketplace: el catalogo de vehiculos con listado paginado, busqueda avanzada con Elasticsearch, detalle de vehiculo con media y precio historico, comparacion side-by-side, y el worker de sincronizacion que importa los 11,000+ vehiculos de scrapper_nacional. Es el epic que los usuarios mas utilizaran y el que genera el mayor impacto en la experiencia.

## Dependencias Externas

- Elasticsearch 8 cluster configurado (MKT-INF-002)
- Base de datos scrapper_nacional con 11,000+ vehiculos de 18 fuentes
- AWS SQS para eventos de sincronizacion
- CDN configurado para imagenes de vehiculos (CloudFront + S3)
- GPS data para 4,000+ vehiculos (tabla existente)
- 7 AI agents para enriquecimiento de datos (futuro)

---

## User Story 1: [MKT-BE-005][SVC-VEH-API] API Listado de Vehiculos con Paginacion Cursor-Based

### Descripcion

Como usuario del marketplace, necesito poder ver una lista paginada de vehiculos disponibles. La API debe usar cursor-based pagination para rendimiento consistente con datasets grandes (11,000+ registros), soportar ordenamiento multiple, y devolver datos optimizados para cards de listado (no el detalle completo).

### Microservicio

- **Nombre**: SVC-VEH
- **Puerto**: 5012
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0
- **Base de datos**: PostgreSQL 15, Redis 7 (cache)
- **Patron**: Hexagonal Architecture

### Contexto Tecnico

#### Endpoints

```
GET /api/v1/vehicles                    # List vehicles (paginated) [PUBLIC]
GET /api/v1/vehicles/count              # Get total count with filters [PUBLIC]
GET /api/v1/vehicles/facets             # Get filter facet counts [PUBLIC]
GET /api/v1/vehicles/makes              # List available makes [PUBLIC]
GET /api/v1/vehicles/makes/:make/models # List models by make [PUBLIC]
GET /api/v1/vehicles/featured           # Featured vehicles (homepage) [PUBLIC]
GET /api/v1/vehicles/recent             # Recently added vehicles [PUBLIC]
GET /api/v1/vehicles/popular            # Most viewed vehicles [PUBLIC]
```

#### Query Parameters

```
# Pagination
cursor          string    Opaque cursor for next/prev page
limit           int       Items per page (1-100, default: 20)

# Sorting
sort_by         string    Field to sort by: created_at|price_usd|year|mileage_km|views_count|favorites_count
sort_order      string    asc|desc (default: desc)

# Filters
make            string    Filter by make (exact match, case-insensitive)
model           string    Filter by model (requires make)
year_min        int       Minimum year
year_max        int       Maximum year
price_min       decimal   Minimum price (USD)
price_max       decimal   Maximum price (USD)
mileage_min     int       Minimum mileage (km)
mileage_max     int       Maximum mileage (km)
fuel_type       string    gasoline|diesel|electric|hybrid|plug_in_hybrid
transmission    string    automatic|manual|cvt|semi_automatic
body_type       string    sedan|suv|truck|hatchback|coupe|convertible|van|wagon|crossover|pickup
drivetrain      string    fwd|rwd|awd|4wd
condition       string    new|used|certified_pre_owned
province        string    Filter by province/location
seller_type     string    dealer|private|platform
is_featured     bool      Only featured vehicles
is_verified     bool      Only verified vehicles
has_gps         bool      Only vehicles with GPS tracking
color           string    Filter by exterior color
features        string    Comma-separated features: sunroof,leather_seats,backup_camera
status          string    active (default, hidden from public for non-active)
```

#### Cursor-Based Pagination Implementation

```python
# app/use_cases/list_vehicles.py
import base64
import json
from dataclasses import dataclass
from typing import Optional, Any
from decimal import Decimal

@dataclass
class CursorData:
    """Cursor contains the sort field value and ID for deterministic pagination."""
    sort_value: Any      # Value of the sort field at cursor position
    id: str              # Vehicle ID as tiebreaker
    direction: str       # "next" or "prev"

    def encode(self) -> str:
        data = {
            "sv": str(self.sort_value) if self.sort_value else None,
            "id": self.id,
            "d": self.direction
        }
        return base64.urlsafe_b64encode(json.dumps(data).encode()).decode()

    @classmethod
    def decode(cls, cursor_str: str) -> "CursorData":
        data = json.loads(base64.urlsafe_b64decode(cursor_str.encode()).decode())
        return cls(
            sort_value=data["sv"],
            id=data["id"],
            direction=data.get("d", "next")
        )

@dataclass
class PaginatedResult:
    items: list
    next_cursor: Optional[str]
    prev_cursor: Optional[str]
    has_next: bool
    has_prev: bool
    limit: int
    total_count: int         # Cached count (may be approximate for large datasets)

class ListVehiclesUseCase:
    def __init__(self, vehicle_repo, cache):
        self.vehicle_repo = vehicle_repo
        self.cache = cache

    def execute(self, filters: dict, sort_by: str, sort_order: str,
                limit: int, cursor: Optional[str] = None) -> PaginatedResult:
        cursor_data = CursorData.decode(cursor) if cursor else None

        # Fetch limit + 1 to determine has_next
        vehicles = self.vehicle_repo.find_paginated(
            filters=filters,
            sort_by=sort_by,
            sort_order=sort_order,
            limit=limit + 1,
            cursor_data=cursor_data
        )

        has_next = len(vehicles) > limit
        if has_next:
            vehicles = vehicles[:limit]

        # Build cursors
        next_cursor = None
        prev_cursor = None
        if has_next and vehicles:
            last = vehicles[-1]
            next_cursor = CursorData(
                sort_value=getattr(last, sort_by),
                id=str(last.id),
                direction="next"
            ).encode()

        if cursor_data and vehicles:
            first = vehicles[0]
            prev_cursor = CursorData(
                sort_value=getattr(first, sort_by),
                id=str(first.id),
                direction="prev"
            ).encode()

        # Get total count (cached for 5 minutes)
        cache_key = f"vehicles:count:{hash(frozenset(filters.items()))}"
        total_count = self.cache.get(cache_key)
        if total_count is None:
            total_count = self.vehicle_repo.count(filters)
            self.cache.set(cache_key, total_count, ttl=300)

        return PaginatedResult(
            items=vehicles,
            next_cursor=next_cursor,
            prev_cursor=prev_cursor,
            has_next=has_next,
            has_prev=cursor_data is not None,
            limit=limit,
            total_count=total_count
        )
```

#### SQLAlchemy Repository - Paginated Query

```python
# inf/persistence/vehicle_repository_impl.py
from sqlalchemy import select, and_, or_, func, desc, asc
from sqlalchemy.orm import Session
from app.dom.ports.vehicle_repository import VehicleRepository
from app.inf.persistence.sqlalchemy_models import VehicleModel

class SQLAlchemyVehicleRepository(VehicleRepository):
    def __init__(self, session: Session):
        self.session = session

    def find_paginated(self, filters: dict, sort_by: str, sort_order: str,
                       limit: int, cursor_data=None) -> list:
        stmt = select(VehicleModel).where(VehicleModel.deleted_at.is_(None))

        # Apply filters
        if filters.get("make"):
            stmt = stmt.where(func.lower(VehicleModel.make) == filters["make"].lower())
        if filters.get("model"):
            stmt = stmt.where(func.lower(VehicleModel.model) == filters["model"].lower())
        if filters.get("year_min"):
            stmt = stmt.where(VehicleModel.year >= filters["year_min"])
        if filters.get("year_max"):
            stmt = stmt.where(VehicleModel.year <= filters["year_max"])
        if filters.get("price_min"):
            stmt = stmt.where(VehicleModel.price_usd >= filters["price_min"])
        if filters.get("price_max"):
            stmt = stmt.where(VehicleModel.price_usd <= filters["price_max"])
        if filters.get("mileage_min"):
            stmt = stmt.where(VehicleModel.mileage_km >= filters["mileage_min"])
        if filters.get("mileage_max"):
            stmt = stmt.where(VehicleModel.mileage_km <= filters["mileage_max"])
        if filters.get("fuel_type"):
            stmt = stmt.where(VehicleModel.fuel_type == filters["fuel_type"])
        if filters.get("transmission"):
            stmt = stmt.where(VehicleModel.transmission == filters["transmission"])
        if filters.get("body_type"):
            stmt = stmt.where(VehicleModel.body_type == filters["body_type"])
        if filters.get("drivetrain"):
            stmt = stmt.where(VehicleModel.drivetrain == filters["drivetrain"])
        if filters.get("condition"):
            stmt = stmt.where(VehicleModel.condition == filters["condition"])
        if filters.get("province"):
            stmt = stmt.where(VehicleModel.location_province == filters["province"])
        if filters.get("seller_type"):
            stmt = stmt.where(VehicleModel.seller_type == filters["seller_type"])
        if filters.get("is_featured") is not None:
            stmt = stmt.where(VehicleModel.is_featured == filters["is_featured"])
        if filters.get("has_gps") is not None:
            stmt = stmt.where(VehicleModel.has_gps_tracking == filters["has_gps"])
        if filters.get("color"):
            stmt = stmt.where(func.lower(VehicleModel.exterior_color) == filters["color"].lower())
        if filters.get("features"):
            for feature in filters["features"]:
                stmt = stmt.where(VehicleModel.features.contains([feature]))
        if filters.get("status"):
            stmt = stmt.where(VehicleModel.status == filters["status"])
        else:
            stmt = stmt.where(VehicleModel.status == "active")

        # Apply cursor
        sort_column = getattr(VehicleModel, sort_by)
        if cursor_data:
            if sort_order == "desc":
                if cursor_data.direction == "next":
                    stmt = stmt.where(
                        or_(
                            sort_column < cursor_data.sort_value,
                            and_(
                                sort_column == cursor_data.sort_value,
                                VehicleModel.id < cursor_data.id
                            )
                        )
                    )
                else:
                    stmt = stmt.where(
                        or_(
                            sort_column > cursor_data.sort_value,
                            and_(
                                sort_column == cursor_data.sort_value,
                                VehicleModel.id > cursor_data.id
                            )
                        )
                    )
            else:  # asc
                if cursor_data.direction == "next":
                    stmt = stmt.where(
                        or_(
                            sort_column > cursor_data.sort_value,
                            and_(
                                sort_column == cursor_data.sort_value,
                                VehicleModel.id > cursor_data.id
                            )
                        )
                    )

        # Apply sort
        if sort_order == "desc":
            stmt = stmt.order_by(desc(sort_column), desc(VehicleModel.id))
        else:
            stmt = stmt.order_by(asc(sort_column), asc(VehicleModel.id))

        stmt = stmt.limit(limit)
        result = self.session.execute(stmt)
        return list(result.scalars().all())

    def count(self, filters: dict) -> int:
        stmt = select(func.count(VehicleModel.id)).where(
            VehicleModel.deleted_at.is_(None)
        )
        # Apply same filters as find_paginated...
        result = self.session.execute(stmt)
        return result.scalar_one()
```

#### Request/Response Examples

```json
// GET /api/v1/vehicles?limit=3&sort_by=price_usd&sort_order=asc&body_type=suv&year_min=2020
// Response 200:
{
  "data": [
    {
      "id": "veh-uuid-001",
      "make": "Hyundai",
      "model": "Tucson",
      "year": 2021,
      "trim": "SEL",
      "body_type": "suv",
      "fuel_type": "gasoline",
      "transmission": "automatic",
      "mileage_km": 42000,
      "exterior_color": "White",
      "condition": "used",
      "price_usd": "22900.00",
      "original_price_usd": "28000.00",
      "currency": "USD",
      "location_province": "Panama",
      "location_city": "Ciudad de Panama",
      "has_gps_tracking": true,
      "seller_type": "dealer",
      "is_featured": false,
      "is_verified": true,
      "views_count": 187,
      "favorites_count": 14,
      "primary_image_url": "https://cdn.marketplace.com/vehicles/veh-uuid-001/main.webp",
      "created_at": "2026-03-18T09:00:00Z",
      "published_at": "2026-03-18T09:30:00Z"
    },
    {
      "id": "veh-uuid-002",
      "make": "Toyota",
      "model": "RAV4",
      "year": 2022,
      "trim": "XLE",
      "body_type": "suv",
      "fuel_type": "hybrid",
      "transmission": "cvt",
      "mileage_km": 18000,
      "exterior_color": "Silver",
      "condition": "certified_pre_owned",
      "price_usd": "31500.00",
      "original_price_usd": "36000.00",
      "currency": "USD",
      "location_province": "Chiriqui",
      "location_city": "David",
      "has_gps_tracking": false,
      "seller_type": "dealer",
      "is_featured": true,
      "is_verified": true,
      "views_count": 523,
      "favorites_count": 41,
      "primary_image_url": "https://cdn.marketplace.com/vehicles/veh-uuid-002/main.webp",
      "created_at": "2026-03-15T14:20:00Z",
      "published_at": "2026-03-15T15:00:00Z"
    },
    {
      "id": "veh-uuid-003",
      "make": "Kia",
      "model": "Sportage",
      "year": 2023,
      "trim": "EX",
      "body_type": "suv",
      "fuel_type": "gasoline",
      "transmission": "automatic",
      "mileage_km": 8500,
      "exterior_color": "Black",
      "condition": "used",
      "price_usd": "33200.00",
      "original_price_usd": null,
      "currency": "USD",
      "location_province": "Panama",
      "location_city": "San Miguelito",
      "has_gps_tracking": true,
      "seller_type": "private",
      "is_featured": false,
      "is_verified": false,
      "views_count": 95,
      "favorites_count": 7,
      "primary_image_url": "https://cdn.marketplace.com/vehicles/veh-uuid-003/main.webp",
      "created_at": "2026-03-20T11:00:00Z",
      "published_at": "2026-03-20T12:00:00Z"
    }
  ],
  "pagination": {
    "next_cursor": "eyJzdiI6IjMzMjAwLjAwIiwiaWQiOiJ2ZWgtdXVpZC0wMDMiLCJkIjoibmV4dCJ9",
    "prev_cursor": null,
    "has_next": true,
    "has_prev": false,
    "limit": 3,
    "total_count": 847
  },
  "meta": {
    "applied_filters": {
      "body_type": "suv",
      "year_min": 2020,
      "status": "active"
    },
    "sort": {
      "field": "price_usd",
      "order": "asc"
    }
  }
}
```

```json
// GET /api/v1/vehicles/facets?body_type=suv&year_min=2020
// Response 200 (counts per filter option):
{
  "data": {
    "makes": [
      { "value": "Toyota", "count": 156 },
      { "value": "Hyundai", "count": 98 },
      { "value": "Kia", "count": 87 },
      { "value": "Honda", "count": 72 },
      { "value": "Nissan", "count": 65 },
      { "value": "Chevrolet", "count": 54 }
    ],
    "fuel_types": [
      { "value": "gasoline", "count": 612 },
      { "value": "hybrid", "count": 124 },
      { "value": "diesel", "count": 78 },
      { "value": "electric", "count": 33 }
    ],
    "transmissions": [
      { "value": "automatic", "count": 721 },
      { "value": "cvt", "count": 89 },
      { "value": "manual", "count": 37 }
    ],
    "conditions": [
      { "value": "used", "count": 654 },
      { "value": "certified_pre_owned", "count": 142 },
      { "value": "new", "count": 51 }
    ],
    "provinces": [
      { "value": "Panama", "count": 523 },
      { "value": "Chiriqui", "count": 112 },
      { "value": "Colon", "count": 78 },
      { "value": "Cocle", "count": 45 }
    ],
    "price_range": {
      "min": 8500.00,
      "max": 125000.00,
      "avg": 28750.00,
      "median": 24500.00
    },
    "year_range": {
      "min": 2020,
      "max": 2026
    },
    "mileage_range": {
      "min": 0,
      "max": 195000,
      "avg": 38500
    }
  }
}
```

```json
// GET /api/v1/vehicles/featured?limit=6
// Response 200:
{
  "data": [
    {
      "id": "veh-uuid-feat-1",
      "make": "Mercedes-Benz",
      "model": "GLC 300",
      "year": 2024,
      "price_usd": "62500.00",
      "mileage_km": 5200,
      "primary_image_url": "https://cdn.marketplace.com/vehicles/veh-uuid-feat-1/main.webp",
      "is_featured": true,
      "is_verified": true,
      "badge": "Premium"
    }
  ],
  "total_count": 24
}
```

### Criterios de Aceptacion

1. **AC-001**: GET /api/v1/vehicles retorna una lista paginada con cursor-based pagination. El cursor es un string opaco base64 que contiene el valor del campo de ordenamiento y el ID del vehiculo como tiebreaker.

2. **AC-002**: La paginacion es estable: si se agrega un vehiculo nuevo entre requests, no aparecen duplicados ni se saltan items. El cursor garantiza determinismo usando (sort_value, id) como clave compuesta.

3. **AC-003**: Todos los filtros (make, model, year, price, mileage, fuel_type, transmission, body_type, drivetrain, condition, province, seller_type, features, color, has_gps) se aplican correctamente y son acumulativos (AND logic).

4. **AC-004**: El ordenamiento funciona para todos los campos soportados (created_at, price_usd, year, mileage_km, views_count, favorites_count) en ambas direcciones (asc, desc). El default es created_at desc.

5. **AC-005**: GET /api/v1/vehicles/facets retorna conteos por cada opcion de filtro, considerando los filtros ya aplicados. Esto permite al frontend mostrar "(156)" al lado de "Toyota" en el filtro de marcas.

6. **AC-006**: GET /api/v1/vehicles/makes retorna la lista de todas las marcas con vehicle_count > 0, ordenadas alfabeticamente. Incluye slug y logo_url. Resultado cacheado en Redis por 1 hora.

7. **AC-007**: GET /api/v1/vehicles/makes/:make/models retorna los modelos de una marca con conteo de vehiculos. Cacheado en Redis por 1 hora.

8. **AC-008**: GET /api/v1/vehicles/featured retorna vehiculos marcados como is_featured=true, ordenados por views_count desc. Maximo 12 resultados. Cacheado 15 minutos.

9. **AC-009**: El response no incluye campos pesados (description, vin, seller_id) en el listado, solo los necesarios para las cards del catalogo. El detalle completo se obtiene con GET /api/v1/vehicles/:id.

10. **AC-010**: El total_count en pagination es un conteo cacheado (5 min TTL) para evitar COUNT(*) costosos en cada request. Es un conteo aproximado que se refresca periodicamente.

11. **AC-011**: La respuesta incluye un campo "meta" con los filtros aplicados y el criterio de ordenamiento para debugging y para que el frontend pueda reflejar el estado actual.

12. **AC-012**: Los vehiculos con status != "active" o deleted_at != null nunca aparecen en los listados publicos. Solo admins pueden ver vehiculos draft/sold/expired via endpoints admin.

13. **AC-013**: El tiempo de respuesta de GET /api/v1/vehicles con filtros comunes no excede 200ms para las primeras paginas (sin cursor) y 100ms para paginas con cursor (con indices optimizados).

### Definition of Done

- [ ] Endpoint de listado con cursor pagination implementado y testeado
- [ ] Todos los filtros funcionando correctamente
- [ ] Ordenamiento por todos los campos soportados
- [ ] Endpoint de facets implementado
- [ ] Endpoints de makes/models implementados
- [ ] Endpoints featured/recent/popular implementados
- [ ] Redis cache para counts, facets, makes/models
- [ ] Response optimizado (solo campos de card, no detalle)
- [ ] Tests unitarios y de integracion >= 85%
- [ ] Performance verificado (< 200ms con 11k+ registros)

### Notas Tecnicas

- Los indices de PostgreSQL son criticos: (make, model, year), (price_usd, status), (status, is_featured), (created_at) deben existir
- El cursor es URL-safe base64 para poder usarse en query strings
- Para el conteo total, considerar pg_stat_user_tables.n_live_tup como estimado rapido si el conteo exacto es muy lento
- Los facets son costosos - cachear agresivamente y considerar pre-calcular con materialized views

### Dependencias

- MKT-BE-002: Vehicle Service setup base (esquema de tablas)
- MKT-BE-001: Gateway para routing
- PostgreSQL con datos iniciales (sync de scrapper_nacional - MKT-INT-001)

---

## User Story 2: [MKT-BE-006][SVC-VEH-API] Busqueda Avanzada con Elasticsearch y Filtros Dinamicos

### Descripcion

Como usuario del marketplace, necesito poder buscar vehiculos con texto libre (ej: "Toyota Corolla 2022 blanco automatico") y recibir resultados relevantes con ranking inteligente. La busqueda avanzada usa Elasticsearch para full-text search, fuzzy matching, autocompletado, sugerencias, y filtros dinamicos con faceted search.

### Microservicio

- **Nombre**: SVC-VEH
- **Puerto**: 5012
- **Tecnologia**: Python 3.11, Elasticsearch 8 (via elasticsearch-py)
- **Patron**: Hexagonal Architecture (Search Port/Adapter)

### Contexto Tecnico

#### Endpoints

```
GET  /api/v1/vehicles/search             # Full-text search with ES [PUBLIC]
GET  /api/v1/vehicles/search/suggest     # Autocomplete suggestions [PUBLIC]
GET  /api/v1/vehicles/search/similar/:id # Similar vehicles to a given one [PUBLIC]
POST /api/v1/vehicles/search/by-image    # Search by uploaded image (future AI) [PUBLIC]
```

#### Elasticsearch Index Mapping

```json
// Index: marketplace_vehicles
{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1,
    "analysis": {
      "analyzer": {
        "vehicle_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "asciifolding", "vehicle_synonyms", "edge_ngram_filter"]
        },
        "autocomplete_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "asciifolding", "edge_ngram_filter"]
        },
        "search_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "asciifolding", "vehicle_synonyms"]
        }
      },
      "filter": {
        "edge_ngram_filter": {
          "type": "edge_ngram",
          "min_gram": 2,
          "max_gram": 15
        },
        "vehicle_synonyms": {
          "type": "synonym",
          "synonyms": [
            "suv, camioneta, sport utility",
            "pickup, pick-up, pick up",
            "automatico, automatic, auto",
            "manual, mecanico, estandar, standard",
            "sedan, berlina",
            "electrico, electric, ev",
            "hibrido, hybrid",
            "gasolina, gasoline, naftero",
            "diesel, gasoil",
            "4x4, 4wd, traccion total, four wheel drive",
            "awd, all wheel drive, traccion integral",
            "turbo, turbocharged, turbocargado",
            "cuero, leather, piel",
            "techo solar, sunroof, moonroof",
            "camara trasera, backup camera, retroceso"
          ]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "id": { "type": "keyword" },
      "make": {
        "type": "text",
        "analyzer": "vehicle_analyzer",
        "search_analyzer": "search_analyzer",
        "fields": {
          "keyword": { "type": "keyword" },
          "suggest": { "type": "completion", "analyzer": "autocomplete_analyzer" }
        }
      },
      "model": {
        "type": "text",
        "analyzer": "vehicle_analyzer",
        "search_analyzer": "search_analyzer",
        "fields": {
          "keyword": { "type": "keyword" },
          "suggest": { "type": "completion", "analyzer": "autocomplete_analyzer" }
        }
      },
      "year": { "type": "integer" },
      "trim": { "type": "text", "analyzer": "vehicle_analyzer", "fields": { "keyword": { "type": "keyword" } } },
      "body_type": { "type": "keyword" },
      "fuel_type": { "type": "keyword" },
      "transmission": { "type": "keyword" },
      "drivetrain": { "type": "keyword" },
      "engine_displacement_cc": { "type": "integer" },
      "horsepower": { "type": "integer" },
      "mileage_km": { "type": "integer" },
      "exterior_color": { "type": "keyword" },
      "interior_color": { "type": "keyword" },
      "condition": { "type": "keyword" },
      "price_usd": { "type": "float" },
      "original_price_usd": { "type": "float" },
      "location_province": { "type": "keyword" },
      "location_city": { "type": "keyword" },
      "location": { "type": "geo_point" },
      "has_gps_tracking": { "type": "boolean" },
      "features": { "type": "keyword" },
      "description": {
        "type": "text",
        "analyzer": "vehicle_analyzer",
        "search_analyzer": "search_analyzer"
      },
      "seller_type": { "type": "keyword" },
      "status": { "type": "keyword" },
      "views_count": { "type": "integer" },
      "favorites_count": { "type": "integer" },
      "is_featured": { "type": "boolean" },
      "is_verified": { "type": "boolean" },
      "primary_image_url": { "type": "keyword", "index": false },
      "created_at": { "type": "date" },
      "published_at": { "type": "date" },
      "make_model_year": {
        "type": "text",
        "analyzer": "vehicle_analyzer",
        "search_analyzer": "search_analyzer",
        "fields": {
          "suggest": { "type": "completion", "analyzer": "autocomplete_analyzer" }
        }
      }
    }
  }
}
```

#### Elasticsearch Query Builder

```python
# inf/search/elasticsearch_impl.py
from elasticsearch import Elasticsearch
from typing import Optional

class ElasticsearchVehicleSearch:
    def __init__(self, es_client: Elasticsearch, index_name: str = "marketplace_vehicles"):
        self.es = es_client
        self.index = index_name

    def search(self, query: str, filters: dict, sort_by: str = "_score",
               sort_order: str = "desc", page: int = 1, size: int = 20) -> dict:
        must_clauses = []
        filter_clauses = [{"term": {"status": "active"}}]

        # Full-text search
        if query:
            must_clauses.append({
                "multi_match": {
                    "query": query,
                    "fields": [
                        "make^5",
                        "model^5",
                        "make_model_year^4",
                        "trim^3",
                        "description^1",
                        "features^2",
                        "exterior_color^2"
                    ],
                    "type": "best_fields",
                    "fuzziness": "AUTO",
                    "prefix_length": 2,
                    "minimum_should_match": "75%"
                }
            })

        # Structured filters
        if filters.get("make"):
            filter_clauses.append({"term": {"make.keyword": filters["make"]}})
        if filters.get("model"):
            filter_clauses.append({"term": {"model.keyword": filters["model"]}})
        if filters.get("year_min") or filters.get("year_max"):
            year_range = {}
            if filters.get("year_min"): year_range["gte"] = filters["year_min"]
            if filters.get("year_max"): year_range["lte"] = filters["year_max"]
            filter_clauses.append({"range": {"year": year_range}})
        if filters.get("price_min") or filters.get("price_max"):
            price_range = {}
            if filters.get("price_min"): price_range["gte"] = filters["price_min"]
            if filters.get("price_max"): price_range["lte"] = filters["price_max"]
            filter_clauses.append({"range": {"price_usd": price_range}})
        if filters.get("mileage_max"):
            filter_clauses.append({"range": {"mileage_km": {"lte": filters["mileage_max"]}}})
        if filters.get("fuel_type"):
            filter_clauses.append({"term": {"fuel_type": filters["fuel_type"]}})
        if filters.get("transmission"):
            filter_clauses.append({"term": {"transmission": filters["transmission"]}})
        if filters.get("body_type"):
            filter_clauses.append({"term": {"body_type": filters["body_type"]}})
        if filters.get("condition"):
            filter_clauses.append({"term": {"condition": filters["condition"]}})
        if filters.get("province"):
            filter_clauses.append({"term": {"location_province": filters["province"]}})
        if filters.get("features"):
            for feature in filters["features"]:
                filter_clauses.append({"term": {"features": feature}})
        if filters.get("has_gps"):
            filter_clauses.append({"term": {"has_gps_tracking": True}})
        if filters.get("is_verified"):
            filter_clauses.append({"term": {"is_verified": True}})

        # Geo filter (within radius)
        if filters.get("lat") and filters.get("lng") and filters.get("radius_km"):
            filter_clauses.append({
                "geo_distance": {
                    "distance": f"{filters['radius_km']}km",
                    "location": {
                        "lat": filters["lat"],
                        "lon": filters["lng"]
                    }
                }
            })

        # Build query
        body = {
            "query": {
                "bool": {
                    "must": must_clauses if must_clauses else [{"match_all": {}}],
                    "filter": filter_clauses
                }
            },
            "aggs": {
                "makes": {"terms": {"field": "make.keyword", "size": 50}},
                "body_types": {"terms": {"field": "body_type", "size": 20}},
                "fuel_types": {"terms": {"field": "fuel_type", "size": 10}},
                "transmissions": {"terms": {"field": "transmission", "size": 10}},
                "conditions": {"terms": {"field": "condition", "size": 5}},
                "provinces": {"terms": {"field": "location_province", "size": 20}},
                "price_stats": {"stats": {"field": "price_usd"}},
                "year_stats": {"stats": {"field": "year"}},
                "mileage_stats": {"stats": {"field": "mileage_km"}},
                "price_histogram": {
                    "histogram": {"field": "price_usd", "interval": 5000}
                }
            },
            "from": (page - 1) * size,
            "size": size,
            "highlight": {
                "fields": {
                    "description": {"fragment_size": 150, "number_of_fragments": 1},
                    "features": {}
                }
            }
        }

        # Sorting
        if sort_by == "_score" and query:
            body["sort"] = [
                "_score",
                {"is_featured": {"order": "desc"}},
                {"created_at": {"order": "desc"}}
            ]
        elif sort_by:
            body["sort"] = [{sort_by: {"order": sort_order}}, {"_id": {"order": "asc"}}]

        # Boost featured and verified
        if not must_clauses:
            body["query"]["bool"]["should"] = [
                {"term": {"is_featured": {"value": True, "boost": 3}}},
                {"term": {"is_verified": {"value": True, "boost": 1.5}}}
            ]

        return self.es.search(index=self.index, body=body)

    def suggest(self, query: str, size: int = 5) -> dict:
        body = {
            "suggest": {
                "make_suggest": {
                    "prefix": query,
                    "completion": {
                        "field": "make.suggest",
                        "size": size,
                        "skip_duplicates": True,
                        "fuzzy": {"fuzziness": "AUTO"}
                    }
                },
                "model_suggest": {
                    "prefix": query,
                    "completion": {
                        "field": "model.suggest",
                        "size": size,
                        "skip_duplicates": True,
                        "fuzzy": {"fuzziness": "AUTO"}
                    }
                },
                "combined_suggest": {
                    "prefix": query,
                    "completion": {
                        "field": "make_model_year.suggest",
                        "size": size,
                        "skip_duplicates": True,
                        "fuzzy": {"fuzziness": "AUTO"}
                    }
                }
            }
        }
        return self.es.search(index=self.index, body=body)

    def find_similar(self, vehicle_id: str, size: int = 6) -> dict:
        # Get the vehicle document
        vehicle = self.es.get(index=self.index, id=vehicle_id)
        source = vehicle["_source"]

        body = {
            "query": {
                "bool": {
                    "must_not": [{"term": {"id": vehicle_id}}],
                    "filter": [{"term": {"status": "active"}}],
                    "should": [
                        {"term": {"make.keyword": {"value": source["make"], "boost": 3}}},
                        {"term": {"body_type": {"value": source["body_type"], "boost": 2}}},
                        {"range": {"year": {"gte": source["year"] - 2, "lte": source["year"] + 2, "boost": 1.5}}},
                        {"range": {"price_usd": {
                            "gte": source["price_usd"] * 0.7,
                            "lte": source["price_usd"] * 1.3,
                            "boost": 2
                        }}},
                        {"term": {"fuel_type": {"value": source["fuel_type"], "boost": 1}}},
                        {"term": {"transmission": {"value": source["transmission"], "boost": 1}}},
                        {"term": {"location_province": {"value": source.get("location_province", ""), "boost": 1.5}}}
                    ],
                    "minimum_should_match": 2
                }
            },
            "size": size
        }
        return self.es.search(index=self.index, body=body)
```

#### Request/Response Examples

```json
// GET /api/v1/vehicles/search?q=toyota+suv+automatico&price_max=35000&page=1&size=5
// Response 200:
{
  "data": [
    {
      "id": "veh-uuid-010",
      "make": "Toyota",
      "model": "RAV4",
      "year": 2022,
      "trim": "XLE",
      "body_type": "suv",
      "fuel_type": "hybrid",
      "transmission": "cvt",
      "mileage_km": 18000,
      "price_usd": "31500.00",
      "location_province": "Panama",
      "primary_image_url": "https://cdn.marketplace.com/vehicles/veh-uuid-010/main.webp",
      "is_featured": true,
      "is_verified": true,
      "score": 12.45,
      "highlight": {
        "description": ["<em>Toyota</em> RAV4 <em>SUV</em> con transmision <em>automatica</em>..."]
      }
    }
  ],
  "pagination": {
    "page": 1,
    "size": 5,
    "total_hits": 67,
    "total_pages": 14
  },
  "aggregations": {
    "makes": [
      { "key": "Toyota", "doc_count": 42 },
      { "key": "Honda", "doc_count": 15 },
      { "key": "Hyundai", "doc_count": 10 }
    ],
    "body_types": [
      { "key": "suv", "doc_count": 52 },
      { "key": "crossover", "doc_count": 15 }
    ],
    "fuel_types": [
      { "key": "gasoline", "doc_count": 38 },
      { "key": "hybrid", "doc_count": 22 },
      { "key": "electric", "doc_count": 7 }
    ],
    "price_stats": {
      "min": 12500.0,
      "max": 34900.0,
      "avg": 24750.0,
      "count": 67
    }
  },
  "meta": {
    "query": "toyota suv automatico",
    "search_time_ms": 45,
    "applied_filters": {
      "price_max": 35000
    }
  }
}
```

```json
// GET /api/v1/vehicles/search/suggest?q=toy
// Response 200:
{
  "data": {
    "makes": [
      { "text": "Toyota", "score": 10.0 }
    ],
    "models": [
      { "text": "Tacoma", "score": 5.0 },
      { "text": "Tundra", "score": 4.0 }
    ],
    "combined": [
      { "text": "Toyota Corolla 2023", "score": 8.0 },
      { "text": "Toyota RAV4 2022", "score": 7.5 },
      { "text": "Toyota Camry 2021", "score": 6.0 },
      { "text": "Toyota Tacoma 2023", "score": 5.5 }
    ]
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: GET /api/v1/vehicles/search acepta un query param "q" con texto libre y retorna vehiculos rankeados por relevancia (_score). El multi_match busca en make, model, make_model_year, trim, description, features, y color con boost diferenciado.

2. **AC-002**: La busqueda soporta fuzzy matching: "Toyita" encuentra "Toyota", "Corrola" encuentra "Corolla". El fuzziness es AUTO (permite 1-2 ediciones dependiendo de la longitud del termino).

3. **AC-003**: Los sinonimos funcionan: buscar "camioneta" encuentra SUVs y pickups, buscar "automatico" encuentra vehiculos con transmission=automatic y cvt, buscar "electrico" encuentra fuel_type=electric.

4. **AC-004**: Los filtros estructurados (price, year, mileage, etc.) se combinan con la busqueda full-text. Los filtros van en la clausula "filter" del bool query (no afectan el score, solo filtran).

5. **AC-005**: Las aggregations retornan conteos por make, body_type, fuel_type, transmission, condition, province, y estadisticas de precio/ano/mileage. Los conteos reflejan los filtros actualmente aplicados.

6. **AC-006**: GET /api/v1/vehicles/search/suggest retorna autocompletado con prefijo en menos de 50ms. Sugiere makes, models, y combinaciones "make model year" con deduplicacion.

7. **AC-007**: GET /api/v1/vehicles/search/similar/:id retorna hasta 6 vehiculos similares basados en: misma marca (boost alto), mismo body_type, ano similar (+/- 2), precio similar (+/- 30%), misma provincia.

8. **AC-008**: La busqueda geo-espacial funciona: si se pasan lat, lng y radius_km, solo retorna vehiculos dentro del radio especificado. Los vehiculos con GPS tracking data tienen coordenadas precisas.

9. **AC-009**: Los vehiculos featured tienen boost en el ranking cuando no hay query de texto (browsing mode). Cuando hay query, el score de relevancia predomina sobre featured.

10. **AC-010**: El response incluye highlight con fragmentos del description donde se encontraron los terminos de busqueda, con tags <em> para resaltar en el frontend.

11. **AC-011**: La sincronizacion PostgreSQL -> Elasticsearch se mantiene via eventos: al crear/actualizar/eliminar un vehiculo en PostgreSQL, se actualiza el documento en ES. Reindexacion completa disponible via endpoint admin.

12. **AC-012**: La busqueda funciona en paginacion offset-based (page/size) porque ES no soporta cursor-based nativamente. El total de paginas se calcula como ceil(total_hits / size).

### Definition of Done

- [ ] Elasticsearch index creado con mapping y analyzers
- [ ] Search endpoint con multi_match y fuzzy
- [ ] Sinonimos configurados para terminos vehiculares
- [ ] Suggest endpoint con completion suggester
- [ ] Similar vehicles endpoint funcional
- [ ] Geo-distance filter implementado
- [ ] Aggregations para faceted search
- [ ] Highlight en resultados
- [ ] Sync PG -> ES implementado (create/update/delete events)
- [ ] Tests de integracion con ES
- [ ] Tiempo de respuesta < 100ms para queries comunes

### Notas Tecnicas

- Elasticsearch 8 en AWS es Amazon OpenSearch Service (API compatible)
- El index mapping incluye un campo "make_model_year" que es una concatenacion para el autocomplete
- Los sinonimos deben mantenerse en un archivo separado y actualizarse sin re-index
- Para el sync PG -> ES, considerar debounce de 1 segundo para evitar updates excesivos en batch imports
- El suggest usa el completion suggester (in-memory, muy rapido) no el phrase suggester

### Dependencias

- MKT-BE-005: API de listado (comparten el mismo servicio SVC-VEH)
- Elasticsearch 8 cluster (MKT-INF-002)
- MKT-INT-001: Datos iniciales sincronizados

---

## User Story 3: [MKT-BE-007][SVC-VEH-API] Detalle de Vehiculo con Media, Similares, Price History

### Descripcion

Como usuario interesado en un vehiculo, necesito ver toda la informacion detallada del vehiculo incluyendo todas sus fotos y videos, historial de precios, vehiculos similares, informacion del vendedor, y datos de GPS si disponibles. La pagina de detalle es la mas importante para la conversion.

### Microservicio

- **Nombre**: SVC-VEH
- **Puerto**: 5012

### Contexto Tecnico

#### Endpoints

```
GET /api/v1/vehicles/:id                  # Full vehicle detail [PUBLIC]
GET /api/v1/vehicles/:id/media            # Vehicle media gallery [PUBLIC]
GET /api/v1/vehicles/:id/price-history    # Price changes over time [PUBLIC]
GET /api/v1/vehicles/:id/similar          # Similar vehicles [PUBLIC]
GET /api/v1/vehicles/:id/location         # GPS location data [PUBLIC]
POST /api/v1/vehicles/:id/view            # Register a view [PUBLIC]
POST /api/v1/vehicles/:id/inquiry         # Submit an inquiry [AUTH]
```

#### Request/Response Examples

```json
// GET /api/v1/vehicles/veh-uuid-010
// Response 200:
{
  "data": {
    "id": "veh-uuid-010",
    "external_id": "scrp-nat-5678",
    "source": "encuentra24",
    "make": "Toyota",
    "model": "RAV4",
    "year": 2022,
    "trim": "XLE Premium",
    "body_type": "suv",
    "fuel_type": "hybrid",
    "transmission": "cvt",
    "drivetrain": "awd",
    "engine_displacement_cc": 2487,
    "horsepower": 219,
    "torque_nm": 239,
    "mileage_km": 18000,
    "exterior_color": "Magnetic Gray Metallic",
    "interior_color": "Black SofTex",
    "vin": "2T3P1RFV*NW******",
    "condition": "certified_pre_owned",
    "price_usd": "31500.00",
    "original_price_usd": "36000.00",
    "currency": "USD",
    "location_province": "Panama",
    "location_city": "Ciudad de Panama",
    "location_lat": 9.0192,
    "location_lng": -79.5195,
    "has_gps_tracking": true,
    "features": [
      "sunroof",
      "leather_seats",
      "apple_carplay",
      "android_auto",
      "adaptive_cruise_control",
      "lane_departure_warning",
      "blind_spot_monitor",
      "backup_camera",
      "heated_seats",
      "wireless_charging",
      "jbl_premium_audio",
      "power_liftgate"
    ],
    "description": "2022 Toyota RAV4 XLE Premium Hybrid AWD in excellent condition. Single owner, all service records available. Toyota certified pre-owned with extended warranty until 2028. Features include panoramic sunroof, JBL premium audio system, wireless charging pad, and full suite of Toyota Safety Sense 2.5+.",
    "seller_id": "seller-uuid-001",
    "seller_type": "dealer",
    "seller": {
      "id": "seller-uuid-001",
      "name": "Premium Auto Panama",
      "type": "dealer",
      "avatar_url": "https://cdn.marketplace.com/dealers/seller-uuid-001/logo.webp",
      "rating": 4.7,
      "total_reviews": 89,
      "total_vehicles": 34,
      "member_since": "2024-06-15",
      "verified": true,
      "response_time_hours": 2
    },
    "status": "active",
    "views_count": 524,
    "favorites_count": 41,
    "inquiries_count": 8,
    "is_featured": true,
    "is_verified": true,
    "media": [
      {
        "id": "media-uuid-001",
        "type": "image",
        "url": "https://cdn.marketplace.com/vehicles/veh-uuid-010/exterior-front.webp",
        "thumbnail_url": "https://cdn.marketplace.com/vehicles/veh-uuid-010/exterior-front-thumb.webp",
        "alt_text": "Toyota RAV4 2022 - Exterior Front View",
        "sort_order": 0,
        "is_primary": true,
        "width": 1920,
        "height": 1280
      },
      {
        "id": "media-uuid-002",
        "type": "image",
        "url": "https://cdn.marketplace.com/vehicles/veh-uuid-010/exterior-side.webp",
        "thumbnail_url": "https://cdn.marketplace.com/vehicles/veh-uuid-010/exterior-side-thumb.webp",
        "alt_text": "Toyota RAV4 2022 - Side Profile",
        "sort_order": 1,
        "is_primary": false,
        "width": 1920,
        "height": 1280
      },
      {
        "id": "media-uuid-003",
        "type": "image",
        "url": "https://cdn.marketplace.com/vehicles/veh-uuid-010/interior-dashboard.webp",
        "thumbnail_url": "https://cdn.marketplace.com/vehicles/veh-uuid-010/interior-dashboard-thumb.webp",
        "alt_text": "Toyota RAV4 2022 - Interior Dashboard",
        "sort_order": 2,
        "is_primary": false,
        "width": 1920,
        "height": 1280
      }
    ],
    "price_history": [
      { "price_usd": "36000.00", "recorded_at": "2026-01-15T00:00:00Z", "source": "sync" },
      { "price_usd": "34500.00", "recorded_at": "2026-02-01T00:00:00Z", "source": "sync" },
      { "price_usd": "33000.00", "recorded_at": "2026-02-20T00:00:00Z", "source": "manual" },
      { "price_usd": "31500.00", "recorded_at": "2026-03-10T00:00:00Z", "source": "manual" }
    ],
    "price_analysis": {
      "price_trend": "decreasing",
      "total_drop_usd": 4500.00,
      "total_drop_percentage": 12.5,
      "days_on_market": 67,
      "avg_price_similar": 33200.00,
      "price_rating": "good_deal"
    },
    "created_at": "2026-01-15T14:20:00Z",
    "updated_at": "2026-03-10T09:00:00Z",
    "published_at": "2026-01-15T15:00:00Z"
  }
}
```

```json
// GET /api/v1/vehicles/veh-uuid-010/price-history
// Response 200:
{
  "data": {
    "vehicle_id": "veh-uuid-010",
    "current_price": "31500.00",
    "history": [
      { "price_usd": "36000.00", "recorded_at": "2026-01-15T00:00:00Z", "source": "sync" },
      { "price_usd": "34500.00", "recorded_at": "2026-02-01T00:00:00Z", "source": "sync" },
      { "price_usd": "33000.00", "recorded_at": "2026-02-20T00:00:00Z", "source": "manual" },
      { "price_usd": "31500.00", "recorded_at": "2026-03-10T00:00:00Z", "source": "manual" }
    ],
    "analysis": {
      "price_trend": "decreasing",
      "total_change_usd": -4500.00,
      "total_change_percentage": -12.5,
      "avg_change_per_month": -2250.00,
      "days_on_market": 67,
      "market_comparison": {
        "avg_price_same_model_year": 33200.00,
        "percentile": 25,
        "rating": "good_deal"
      }
    }
  }
}
```

```json
// POST /api/v1/vehicles/veh-uuid-010/inquiry
// Headers: Authorization: Bearer <jwt>
// Request:
{
  "message": "Hi, I am interested in this RAV4. Is it still available? Can I schedule a test drive?",
  "preferred_contact": "whatsapp",
  "phone_number": "+50760001234"
}

// Response 201:
{
  "data": {
    "inquiry_id": "inq-uuid-001",
    "vehicle_id": "veh-uuid-010",
    "status": "pending",
    "created_at": "2026-03-23T10:30:00Z"
  },
  "message": "Inquiry sent successfully. The seller will be notified."
}
```

### Criterios de Aceptacion

1. **AC-001**: GET /api/v1/vehicles/:id retorna el detalle completo del vehiculo incluyendo todos los campos, media (fotos/videos ordenados), price_history, y price_analysis. El response incluye la informacion basica del vendedor.

2. **AC-002**: El VIN se muestra parcialmente enmascarado (ultimos 6 caracteres ocultos) para usuarios no autenticados. Usuarios autenticados que hayan enviado inquiry ven el VIN completo.

3. **AC-003**: POST /api/v1/vehicles/:id/view registra una vista del vehiculo. Se usa fingerprint (IP + User-Agent hash) para evitar conteo duplicado. Las vistas se acumulan en batch cada 5 minutos via Redis (no se hace UPDATE en cada request).

4. **AC-004**: El price_analysis incluye: tendencia (increasing/stable/decreasing), cambio total en USD y porcentaje, dias en el mercado, precio promedio de vehiculos similares, y un rating (great_deal, good_deal, fair_price, above_market, overpriced).

5. **AC-005**: GET /api/v1/vehicles/:id/similar retorna hasta 6 vehiculos similares usando la logica de ES (misma marca, body type similar, precio +/-30%, ano +/-2). Los similares no incluyen vehiculos del mismo vendedor.

6. **AC-006**: GET /api/v1/vehicles/:id/media retorna todos los media del vehiculo ordenados por sort_order, incluyendo URLs de imagen completa y thumbnail. Soporta tipos: image, video, 360.

7. **AC-007**: POST /api/v1/vehicles/:id/inquiry requiere autenticacion, valida el mensaje (min 10 caracteres), y crea un inquiry que notifica al vendedor via SVC-NTF. Limita a 3 inquiries por usuario por vehiculo.

8. **AC-008**: El detalle incluye la informacion del vendedor: nombre, tipo, rating, cantidad de reviews, vehiculos activos, tiempo de respuesta promedio, y si esta verificado.

9. **AC-009**: GET /api/v1/vehicles/:id/location retorna los datos de GPS si has_gps_tracking=true: ultima ubicacion conocida, historial de ubicaciones (ultimos 30 dias), y un flag indicando si la ubicacion es en tiempo real o historica.

10. **AC-010**: El endpoint de detalle tiene cache en Redis con TTL de 5 minutos. El cache se invalida automaticamente al actualizar el vehiculo o al registrar un cambio de precio.

11. **AC-011**: Si el vehiculo no existe o esta eliminado, retorna 404. Si el vehiculo esta en status draft, solo el seller y admins pueden verlo (retorna 403 para otros).

12. **AC-012**: El response incluye breadcrumb data: [Home, Vehiculos, {Make}, {Model}, {Year} {Make} {Model} {Trim}] para navegacion y SEO.

### Definition of Done

- [ ] Detalle completo con media y price history
- [ ] Price analysis con comparacion de mercado
- [ ] Similar vehicles via Elasticsearch
- [ ] View counter con deduplicacion
- [ ] Inquiry creation con notificacion
- [ ] Seller info incluida en detalle
- [ ] GPS location data cuando disponible
- [ ] VIN masking para no autenticados
- [ ] Cache Redis implementado
- [ ] Tests >= 85% cobertura

### Notas Tecnicas

- El price_rating se calcula comparando con el percentil del precio en vehiculos del mismo make+model+year (+/-1)
- Las vistas se acumulan en un sorted set de Redis (ZINCRBY) y se flush a PostgreSQL cada 5 minutos via un scheduled task
- El seller info se obtiene via HTTP call a SVC-USR (cacheado 30 min) - no se duplican los datos del seller en la tabla vehicles
- La masking del VIN es: "2T3P1RFV*NW******" (primeros 8 + last 6 masked)
- Para la comparacion de mercado, pre-calcular los promedios por make+model+year diariamente (background job)

### Dependencias

- MKT-BE-005: API de listado (mismo servicio)
- MKT-BE-006: Elasticsearch para similares
- MKT-BE-004: SVC-USR para datos del vendedor
- MKT-BE-017: SVC-NTF para notificar inquiries

---

## User Story 4: [MKT-FE-005][FE-FEAT-CAT] Catalogo Grid/List View con Infinite Scroll

### Descripcion

Como usuario del marketplace, necesito una vista de catalogo que muestre los vehiculos disponibles en formato grid o lista, con infinite scroll para cargar mas vehiculos al hacer scroll down. La experiencia debe ser fluida, rapida y visualmente atractiva.

### Microservicio

- **Nombre**: FE-FEAT-CAT (Frontend Feature - Catalog)
- **Puerto**: 4200
- **Tecnologia**: Angular 18, Tailwind CSS v4, Standalone Components, Signals

### Contexto Tecnico

#### Componentes

```
features/
  vehicles/
    vehicle-catalog/
      catalog-page.component.ts            # Container: filters + results
      catalog-page.component.html
      catalog-page.component.spec.ts
      components/
        vehicle-card/
          vehicle-card.component.ts         # Card for grid view
          vehicle-card.component.html
          vehicle-card.component.spec.ts
        vehicle-list-item/
          vehicle-list-item.component.ts    # Row for list view
          vehicle-list-item.component.html
        catalog-toolbar/
          catalog-toolbar.component.ts      # Sort, view toggle, result count
          catalog-toolbar.component.html
        search-bar/
          search-bar.component.ts           # Search with autocomplete
          search-bar.component.html
        active-filters/
          active-filters.component.ts       # Tags showing applied filters
          active-filters.component.html
      services/
        catalog-state.service.ts            # Signal-based catalog state
        vehicle-api.service.ts              # HTTP calls to SVC-VEH
    vehicles.routes.ts
```

#### Vehicle Card Component

```typescript
// vehicle-card.component.ts
import { Component, input, output, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { CurrencyFormatPipe } from '../../../../shared/pipes/currency-format.pipe';
import { MileageFormatPipe } from '../../../../shared/pipes/mileage-format.pipe';
import { RelativeTimePipe } from '../../../../shared/pipes/relative-time.pipe';
import { LazyImageDirective } from '../../../../shared/directives/lazy-image.directive';
import { BadgeComponent } from '../../../../shared/components/ui/badge/badge.component';

export interface VehicleCard {
  id: string;
  make: string;
  model: string;
  year: number;
  trim: string | null;
  body_type: string;
  fuel_type: string;
  transmission: string;
  mileage_km: number;
  exterior_color: string | null;
  condition: string;
  price_usd: string;
  original_price_usd: string | null;
  location_province: string | null;
  location_city: string | null;
  has_gps_tracking: boolean;
  seller_type: string;
  is_featured: boolean;
  is_verified: boolean;
  views_count: number;
  favorites_count: number;
  primary_image_url: string | null;
  created_at: string;
  is_favorited?: boolean;
}

@Component({
  selector: 'app-vehicle-card',
  standalone: true,
  imports: [
    CommonModule, RouterLink,
    CurrencyFormatPipe, MileageFormatPipe, RelativeTimePipe,
    LazyImageDirective, BadgeComponent
  ],
  template: `
    <article class="group relative bg-white dark:bg-neutral-800 rounded-xl shadow-card
                    hover:shadow-card-hover transition-shadow duration-300 overflow-hidden cursor-pointer">
      <!-- Image Container -->
      <div class="relative aspect-[4/3] overflow-hidden">
        <img [appLazyImage]="vehicle().primary_image_url || '/assets/images/placeholder-vehicle.svg'"
             [alt]="imageAlt()"
             class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500" />

        <!-- Badges overlay -->
        <div class="absolute top-3 left-3 flex gap-2">
          @if (vehicle().is_featured) {
            <app-badge variant="premium">Premium</app-badge>
          }
          @if (vehicle().condition === 'new') {
            <app-badge variant="success">Nuevo</app-badge>
          }
          @if (hasDiscount()) {
            <app-badge variant="warning">-{{ discountPercentage() }}%</app-badge>
          }
        </div>

        <!-- Favorite button -->
        <button (click)="onFavoriteClick($event)"
                class="absolute top-3 right-3 w-10 h-10 rounded-full bg-white/80 dark:bg-neutral-900/80
                       backdrop-blur-sm flex items-center justify-center hover:bg-white transition-colors">
          <svg [class.fill-red-500]="vehicle().is_favorited"
               [class.text-red-500]="vehicle().is_favorited"
               class="w-5 h-5 text-neutral-500" fill="none" stroke="currentColor"
               viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                  d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
          </svg>
        </button>

        <!-- GPS indicator -->
        @if (vehicle().has_gps_tracking) {
          <div class="absolute bottom-3 left-3 px-2 py-1 bg-green-500/90 text-white text-xs rounded-full
                      flex items-center gap-1">
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
              <path d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" />
            </svg>
            GPS
          </div>
        }
      </div>

      <!-- Content -->
      <a [routerLink]="['/vehicles', vehicle().id]" class="block p-4">
        <!-- Title -->
        <h3 class="font-display font-semibold text-neutral-900 dark:text-neutral-100 text-lg leading-tight">
          {{ vehicle().year }} {{ vehicle().make }} {{ vehicle().model }}
          @if (vehicle().trim) { <span class="text-neutral-500 font-normal">{{ vehicle().trim }}</span> }
        </h3>

        <!-- Key specs -->
        <div class="mt-2 flex items-center gap-3 text-sm text-neutral-500 dark:text-neutral-400">
          <span>{{ vehicle().mileage_km | mileageFormat }}</span>
          <span class="w-1 h-1 rounded-full bg-neutral-300"></span>
          <span>{{ vehicle().transmission }}</span>
          <span class="w-1 h-1 rounded-full bg-neutral-300"></span>
          <span>{{ vehicle().fuel_type }}</span>
        </div>

        <!-- Location -->
        <div class="mt-2 flex items-center gap-1 text-sm text-neutral-400">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
          </svg>
          {{ vehicle().location_city || vehicle().location_province || 'Panama' }}
        </div>

        <!-- Price -->
        <div class="mt-3 flex items-baseline gap-2">
          <span class="text-2xl font-bold text-primary-600 dark:text-primary-400">
            {{ vehicle().price_usd | currencyFormat }}
          </span>
          @if (vehicle().original_price_usd && hasDiscount()) {
            <span class="text-sm text-neutral-400 line-through">
              {{ vehicle().original_price_usd | currencyFormat }}
            </span>
          }
        </div>

        <!-- Footer -->
        <div class="mt-3 pt-3 border-t border-neutral-100 dark:border-neutral-700
                    flex items-center justify-between text-xs text-neutral-400">
          <span>{{ vehicle().created_at | relativeTime }}</span>
          <div class="flex items-center gap-3">
            <span class="flex items-center gap-1">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
              </svg>
              {{ vehicle().views_count }}
            </span>
            <span class="flex items-center gap-1">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
              </svg>
              {{ vehicle().favorites_count }}
            </span>
          </div>
        </div>
      </a>
    </article>
  `
})
export class VehicleCardComponent {
  readonly vehicle = input.required<VehicleCard>();
  readonly favoriteToggle = output<string>();

  readonly imageAlt = computed(() => {
    const v = this.vehicle();
    return `${v.year} ${v.make} ${v.model} ${v.trim || ''} - ${v.exterior_color || ''}`.trim();
  });

  readonly hasDiscount = computed(() => {
    const v = this.vehicle();
    return v.original_price_usd && parseFloat(v.original_price_usd) > parseFloat(v.price_usd);
  });

  readonly discountPercentage = computed(() => {
    const v = this.vehicle();
    if (!v.original_price_usd) return 0;
    const original = parseFloat(v.original_price_usd);
    const current = parseFloat(v.price_usd);
    return Math.round(((original - current) / original) * 100);
  });

  onFavoriteClick(event: Event): void {
    event.preventDefault();
    event.stopPropagation();
    this.favoriteToggle.emit(this.vehicle().id);
  }
}
```

#### Catalog State Service

```typescript
// catalog-state.service.ts
import { Injectable, signal, computed } from '@angular/core';
import { VehicleCard } from '../components/vehicle-card/vehicle-card.component';

export type ViewMode = 'grid' | 'list';
export type SortField = 'created_at' | 'price_usd' | 'year' | 'mileage_km' | 'views_count';

export interface CatalogFilters {
  q: string;
  make: string;
  model: string;
  yearMin: number | null;
  yearMax: number | null;
  priceMin: number | null;
  priceMax: number | null;
  mileageMax: number | null;
  fuelType: string;
  transmission: string;
  bodyType: string;
  condition: string;
  province: string;
  sellerType: string;
  isFeatured: boolean | null;
  hasGps: boolean | null;
}

@Injectable()
export class CatalogStateService {
  // View state
  readonly viewMode = signal<ViewMode>('grid');
  readonly sortBy = signal<SortField>('created_at');
  readonly sortOrder = signal<'asc' | 'desc'>('desc');

  // Data state
  readonly vehicles = signal<VehicleCard[]>([]);
  readonly isLoading = signal(false);
  readonly isLoadingMore = signal(false);
  readonly nextCursor = signal<string | null>(null);
  readonly totalCount = signal(0);
  readonly hasMore = computed(() => this.nextCursor() !== null);

  // Filters
  readonly filters = signal<CatalogFilters>({
    q: '', make: '', model: '',
    yearMin: null, yearMax: null,
    priceMin: null, priceMax: null,
    mileageMax: null,
    fuelType: '', transmission: '', bodyType: '',
    condition: '', province: '', sellerType: '',
    isFeatured: null, hasGps: null,
  });

  readonly activeFilterCount = computed(() => {
    const f = this.filters();
    let count = 0;
    if (f.make) count++;
    if (f.model) count++;
    if (f.yearMin || f.yearMax) count++;
    if (f.priceMin || f.priceMax) count++;
    if (f.mileageMax) count++;
    if (f.fuelType) count++;
    if (f.transmission) count++;
    if (f.bodyType) count++;
    if (f.condition) count++;
    if (f.province) count++;
    if (f.sellerType) count++;
    if (f.hasGps) count++;
    return count;
  });

  // Facets (from API)
  readonly facets = signal<any>(null);

  appendVehicles(newVehicles: VehicleCard[]): void {
    this.vehicles.update(current => [...current, ...newVehicles]);
  }

  resetVehicles(): void {
    this.vehicles.set([]);
    this.nextCursor.set(null);
    this.totalCount.set(0);
  }

  updateFilter(key: keyof CatalogFilters, value: any): void {
    this.filters.update(f => ({ ...f, [key]: value }));
  }

  clearFilters(): void {
    this.filters.set({
      q: '', make: '', model: '',
      yearMin: null, yearMax: null,
      priceMin: null, priceMax: null,
      mileageMax: null,
      fuelType: '', transmission: '', bodyType: '',
      condition: '', province: '', sellerType: '',
      isFeatured: null, hasGps: null,
    });
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: La pagina de catalogo muestra vehiculos en formato grid (3 columnas desktop, 2 tablet, 1 mobile) con cards que incluyen: imagen con lazy loading, make/model/year, precio (con descuento si aplica), mileage, transmision, combustible, ubicacion, views/favorites counts, badges (featured, new, discount).

2. **AC-002**: El usuario puede alternar entre vista grid y vista lista. La vista lista muestra la imagen a la izquierda (horizontal) con mas detalles al lado derecho. La preferencia de vista se persiste en localStorage.

3. **AC-003**: El infinite scroll carga automaticamente la siguiente pagina cuando el usuario scrollea al 80% del contenido visible. Muestra un skeleton loader con 3-4 cards mientras carga. Si no hay mas resultados, muestra "Has visto todos los vehiculos".

4. **AC-004**: La barra de herramientas superior muestra: conteo total de resultados ("847 vehiculos encontrados"), selector de ordenamiento (dropdown), toggle grid/list, y los filtros activos como tags removibles.

5. **AC-005**: El search bar con autocomplete muestra sugerencias mientras el usuario escribe (debounce 300ms). Las sugerencias vienen del endpoint /search/suggest y muestran marcas, modelos, y combinaciones. Al seleccionar una sugerencia, ejecuta la busqueda.

6. **AC-006**: Los filtros activos se muestran como chips/tags debajo del toolbar. Cada tag tiene un boton X para remover ese filtro. Existe un boton "Limpiar todos" que resetea todos los filtros.

7. **AC-007**: Al cambiar cualquier filtro, ordenamiento, o ejecutar una busqueda, la lista se resetea (scroll to top) y carga la primera pagina con los nuevos parametros. La URL se actualiza con los query params de los filtros (deep linking).

8. **AC-008**: El boton de favorito en cada card funciona: click agrega/quita de favoritos via SVC-USR, actualiza el icono (corazon relleno/vacio) inmediatamente (optimistic update), y si falla la API, revierte el cambio con un toast de error.

9. **AC-009**: Las imagenes usan la directiva lazy-image con Intersection Observer. Mientras no son visibles, muestran un placeholder de color solido (basado en el color predominante de la imagen o neutral). Al entrar al viewport, cargan con fade-in.

10. **AC-010**: Si la busqueda no retorna resultados, muestra un empty state con ilustracion y sugerencias: "No encontramos vehiculos con estos filtros. Intenta ampliar tu busqueda."

11. **AC-011**: El conteo de resultados se actualiza reactivamente con cada cambio de filtro. El numero muestra animacion de counting up.

12. **AC-012**: El state del catalogo (filtros, sort, view mode, scroll position) se preserva al navegar al detalle y volver. El usuario retoma exactamente donde estaba.

### Definition of Done

- [ ] Grid view con cards responsive implementado
- [ ] List view alternativo implementado
- [ ] Infinite scroll con cursor pagination
- [ ] Search bar con autocomplete
- [ ] Toolbar con sort, view toggle, result count
- [ ] Active filters as removable tags
- [ ] Favorite toggle con optimistic update
- [ ] Lazy image loading con Intersection Observer
- [ ] Empty state para sin resultados
- [ ] URL sync con query params (deep linking)
- [ ] State preservation al navegar y volver
- [ ] Tests unitarios >= 80%

### Notas Tecnicas

- Usar la directiva infiniteScroll custom que emite un evento cuando el sentinel element entra al viewport
- La URL sync usa Angular Router queryParams: al cambiar filtros, se actualiza la URL sin navegar
- Al cargar la pagina con query params en la URL, se inicializan los filtros desde la URL
- El skeleton de las cards debe coincidir con las dimensiones reales para evitar CLS (Cumulative Layout Shift)
- Considerar virtual scrolling (Angular CDK) si el rendimiento con 100+ cards en DOM es un problema

### Dependencias

- MKT-FE-001: UI components (card, badge, skeleton, spinner, empty-state)
- MKT-BE-005: API de listado con pagination
- MKT-BE-006: API de search con suggest
- MKT-BE-004: SVC-USR para favoritos (check batch + toggle)

---

## User Story 5: [MKT-FE-006][FE-FEAT-CAT] Panel de Filtros Avanzados (Sidebar Desktop, Bottom Sheet Mobile)

### Descripcion

Como usuario buscando un vehiculo especifico, necesito un panel de filtros avanzados que me permita refinar los resultados por multiples criterios (marca, modelo, ano, precio, tipo de combustible, transmision, etc.). En desktop se muestra como sidebar izquierda, en mobile como bottom sheet.

### Microservicio

- **Nombre**: FE-FEAT-CAT
- **Puerto**: 4200

### Contexto Tecnico

#### Componentes

```
features/
  vehicles/
    vehicle-catalog/
      components/
        filter-panel/
          filter-panel.component.ts           # Desktop sidebar / Mobile bottom sheet
          filter-panel.component.html
          filter-panel.component.spec.ts
          sections/
            filter-make-model/
              filter-make-model.component.ts  # Make + Model cascading selects
            filter-price-range/
              filter-price-range.component.ts # Dual range slider + inputs
            filter-year-range/
              filter-year-range.component.ts  # Year min/max selects
            filter-body-type/
              filter-body-type.component.ts   # Visual body type selector (icons)
            filter-fuel-type/
              filter-fuel-type.component.ts   # Checkbox group
            filter-transmission/
              filter-transmission.component.ts # Checkbox group
            filter-condition/
              filter-condition.component.ts   # Radio buttons
            filter-location/
              filter-location.component.ts    # Province select + radius
            filter-mileage/
              filter-mileage.component.ts     # Max mileage slider
            filter-extras/
              filter-extras.component.ts      # Toggles: GPS, verified, featured
        bottom-sheet/
          bottom-sheet.component.ts           # Reusable bottom sheet for mobile
          bottom-sheet.component.html
```

#### Filter Panel Layout (HTML Template)

```html
<!-- filter-panel.component.html -->
<!-- Desktop: Sidebar -->
<aside class="hidden lg:block w-80 shrink-0 sticky top-20 h-[calc(100vh-5rem)] overflow-y-auto
              border-r border-neutral-200 dark:border-neutral-700 p-4 space-y-6">

  <div class="flex items-center justify-between">
    <h2 class="text-lg font-display font-semibold text-neutral-900 dark:text-neutral-100">Filtros</h2>
    @if (state.activeFilterCount() > 0) {
      <button (click)="clearAll()" class="text-sm text-primary-600 hover:text-primary-700">
        Limpiar ({{ state.activeFilterCount() }})
      </button>
    }
  </div>

  <!-- Make & Model -->
  <app-filter-make-model
    [makes]="facets()?.makes || []"
    [models]="models()"
    [selectedMake]="state.filters().make"
    [selectedModel]="state.filters().model"
    (makeChange)="onMakeChange($event)"
    (modelChange)="onModelChange($event)"
  />

  <!-- Price Range -->
  <app-filter-price-range
    [min]="facets()?.price_range?.min || 0"
    [max]="facets()?.price_range?.max || 200000"
    [selectedMin]="state.filters().priceMin"
    [selectedMax]="state.filters().priceMax"
    (rangeChange)="onPriceChange($event)"
  />

  <!-- Year Range -->
  <app-filter-year-range
    [min]="facets()?.year_range?.min || 2000"
    [max]="facets()?.year_range?.max || 2026"
    [selectedMin]="state.filters().yearMin"
    [selectedMax]="state.filters().yearMax"
    (rangeChange)="onYearChange($event)"
  />

  <!-- Body Type (visual icons) -->
  <app-filter-body-type
    [options]="facets()?.body_types || []"
    [selected]="state.filters().bodyType"
    (selectionChange)="onBodyTypeChange($event)"
  />

  <!-- Fuel Type -->
  <app-filter-fuel-type
    [options]="facets()?.fuel_types || []"
    [selected]="state.filters().fuelType"
    (selectionChange)="onFuelTypeChange($event)"
  />

  <!-- Transmission -->
  <app-filter-transmission
    [options]="facets()?.transmissions || []"
    [selected]="state.filters().transmission"
    (selectionChange)="onTransmissionChange($event)"
  />

  <!-- Condition -->
  <app-filter-condition
    [options]="facets()?.conditions || []"
    [selected]="state.filters().condition"
    (selectionChange)="onConditionChange($event)"
  />

  <!-- Location -->
  <app-filter-location
    [provinces]="facets()?.provinces || []"
    [selected]="state.filters().province"
    (selectionChange)="onProvinceChange($event)"
  />

  <!-- Max Mileage -->
  <app-filter-mileage
    [max]="facets()?.mileage_range?.max || 300000"
    [selected]="state.filters().mileageMax"
    (valueChange)="onMileageChange($event)"
  />

  <!-- Extras -->
  <app-filter-extras
    [hasGps]="state.filters().hasGps"
    (hasGpsChange)="onGpsChange($event)"
  />
</aside>

<!-- Mobile: Bottom Sheet Trigger -->
<div class="lg:hidden fixed bottom-4 left-4 right-4 z-40">
  <button (click)="openMobileFilters()"
          class="w-full py-3 px-6 bg-primary-600 text-white rounded-full shadow-lg
                 flex items-center justify-center gap-2 font-medium">
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
    </svg>
    Filtros
    @if (state.activeFilterCount() > 0) {
      <span class="ml-1 w-6 h-6 rounded-full bg-white text-primary-600 text-sm font-bold
                   flex items-center justify-center">
        {{ state.activeFilterCount() }}
      </span>
    }
  </button>
</div>

<!-- Mobile: Bottom Sheet -->
<app-bottom-sheet [isOpen]="isMobileFiltersOpen()" (close)="closeMobileFilters()">
  <div class="p-4 space-y-6 pb-24">
    <!-- Same filter sections as desktop -->
    <app-filter-make-model ... />
    <app-filter-price-range ... />
    <!-- etc. -->
  </div>
  <div class="sticky bottom-0 p-4 bg-white dark:bg-neutral-800 border-t flex gap-3">
    <button (click)="clearAll()" class="flex-1 py-3 border border-neutral-300 rounded-lg font-medium">
      Limpiar
    </button>
    <button (click)="applyAndClose()" class="flex-1 py-3 bg-primary-600 text-white rounded-lg font-medium">
      Ver {{ state.totalCount() }} resultados
    </button>
  </div>
</app-bottom-sheet>
```

### Criterios de Aceptacion

1. **AC-001**: En desktop (>= 1024px), los filtros se muestran como sidebar sticky a la izquierda del catalogo, ocupando 320px de ancho. El sidebar es scrollable independientemente del contenido principal.

2. **AC-002**: En mobile (< 1024px), los filtros se ocultan. Un boton floating "Filtros" en la parte inferior abre un bottom sheet con todos los filtros. El bottom sheet se puede cerrar con swipe down o boton X.

3. **AC-003**: El filtro de Make/Model es cascading: al seleccionar una marca, el select de modelos se actualiza con los modelos de esa marca (via /api/v1/vehicles/makes/:make/models). Si no hay marca seleccionada, el select de modelos esta deshabilitado.

4. **AC-004**: El filtro de precio es un dual range slider con dos thumbs (min y max) y campos de input numerico sincronizados. Al mover un thumb, el input se actualiza y viceversa. Los valores se formatean como moneda ($15,000).

5. **AC-005**: El filtro de body type muestra iconos visuales (siluetas de sedan, suv, truck, etc.) como botones seleccionables. El body type seleccionado se resalta con borde primario.

6. **AC-006**: Cada opcion de filtro muestra el conteo de vehiculos disponibles entre parentesis: "Toyota (156)", "Gasoline (612)". Los conteos se actualizan al cambiar otros filtros (via endpoint /facets).

7. **AC-007**: En desktop, los filtros se aplican en tiempo real (con debounce de 500ms). En mobile, los filtros se aplican al presionar el boton "Ver X resultados" en el bottom sheet.

8. **AC-008**: El boton "Limpiar" resetea todos los filtros a sus valores por defecto y recarga la lista. Cada seccion de filtro tiene opcion de limpiar individualmente.

9. **AC-009**: El bottom sheet mobile muestra un sticky footer con botones "Limpiar" y "Ver N resultados". El conteo de resultados se actualiza en tiempo real mientras el usuario ajusta filtros.

10. **AC-010**: Los filtros colapsables (accordion) permiten expandir/colapsar cada seccion. El estado de colapsado se persiste en localStorage.

11. **AC-011**: El filtro de ubicacion (provincia) muestra un select con todas las provincias que tienen vehiculos. En futuro, se agregara filtro por radio (km desde ubicacion del usuario).

12. **AC-012**: El filtro de extras incluye toggles para: "Solo con GPS", "Solo verificados", "Solo featured/premium".

### Definition of Done

- [ ] Filter panel desktop (sidebar) implementado
- [ ] Bottom sheet mobile implementado
- [ ] Cascading make/model select
- [ ] Dual range slider para precio
- [ ] Visual body type selector con iconos
- [ ] Facet counts actualizados dinamicamente
- [ ] Real-time filtering en desktop, apply button en mobile
- [ ] Clear all y clear individual filters
- [ ] Collapsible sections con persistencia
- [ ] Tests unitarios >= 80%

### Notas Tecnicas

- El bottom sheet debe bloquear el scroll del body cuando esta abierto
- El dual range slider puede implementarse con Angular CDK Slider o custom
- Los facet counts se obtienen del endpoint /facets que acepta los mismos filtros
- Debounce los cambios de filtro en desktop para no hacer requests en cada click
- En mobile, acumular cambios localmente y solo hacer request al "Aplicar"

### Dependencias

- MKT-FE-005: Catalog page (parent component)
- MKT-BE-005: API facets endpoint
- MKT-FE-001: UI components (select, checkbox, radio, toggle)

---

## User Story 6: [MKT-FE-007][FE-FEAT-DET] Detalle Vehiculo con Carrusel de Fotos Hero

### Descripcion

Como comprador potencial, necesito una pagina de detalle del vehiculo inmersiva y completa que me de toda la informacion necesaria para tomar una decision de compra. El elemento principal es un carrusel de fotos hero con soporte para fullscreen, zoom, y swipe en mobile.

### Microservicio

- **Nombre**: FE-FEAT-DET (Frontend Feature - Vehicle Detail)
- **Puerto**: 4200

### Contexto Tecnico

#### Componentes

```
features/
  vehicles/
    vehicle-detail/
      detail-page.component.ts                # Container page
      detail-page.component.html
      detail-page.component.spec.ts
      components/
        photo-carousel/
          photo-carousel.component.ts          # Main hero carousel
          photo-carousel.component.html
          photo-carousel.component.spec.ts
          fullscreen-gallery/
            fullscreen-gallery.component.ts    # Fullscreen overlay with zoom
            fullscreen-gallery.component.html
          thumbnail-strip/
            thumbnail-strip.component.ts       # Scrollable thumbnail row
            thumbnail-strip.component.html
        vehicle-specs/
          vehicle-specs.component.ts            # Specs grid (engine, transmission, etc.)
          vehicle-specs.component.html
        vehicle-features/
          vehicle-features.component.ts         # Features tags grid
          vehicle-features.component.html
        price-section/
          price-section.component.ts            # Price, history chart, deal rating
          price-section.component.html
        price-history-chart/
          price-history-chart.component.ts      # Line chart of price changes
          price-history-chart.component.html
        seller-card/
          seller-card.component.ts              # Seller info + contact button
          seller-card.component.html
        inquiry-form/
          inquiry-form.component.ts             # Send message to seller
          inquiry-form.component.html
        similar-vehicles/
          similar-vehicles.component.ts         # Horizontal scrollable cards
          similar-vehicles.component.html
        vehicle-location-map/
          vehicle-location-map.component.ts     # Map with vehicle location
          vehicle-location-map.component.html
        breadcrumb-bar/
          breadcrumb-bar.component.ts           # Breadcrumb navigation
          breadcrumb-bar.component.html
        share-actions/
          share-actions.component.ts            # Share, print, report buttons
          share-actions.component.html
```

#### Detail Page Layout

```html
<!-- detail-page.component.html -->
<div class="min-h-screen bg-neutral-50 dark:bg-neutral-900">
  <!-- Breadcrumb -->
  <app-breadcrumb-bar [items]="breadcrumbs()" />

  <!-- Hero: Photo Carousel -->
  <section class="relative">
    <app-photo-carousel
      [media]="vehicle()?.media || []"
      [vehicleTitle]="vehicleTitle()"
      (openFullscreen)="openGallery($event)"
    />
  </section>

  <!-- Main Content -->
  <div class="max-w-7xl mx-auto px-4 py-8">
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">

      <!-- Left Column (2/3) -->
      <div class="lg:col-span-2 space-y-8">
        <!-- Title & Quick Stats -->
        <div>
          <div class="flex items-start justify-between">
            <div>
              <h1 class="text-3xl font-display font-bold text-neutral-900 dark:text-white">
                {{ vehicle()?.year }} {{ vehicle()?.make }} {{ vehicle()?.model }}
              </h1>
              <p class="mt-1 text-lg text-neutral-500">{{ vehicle()?.trim }}</p>
            </div>
            <app-share-actions [vehicleId]="vehicle()?.id" [vehicleTitle]="vehicleTitle()" />
          </div>

          <!-- Quick stat pills -->
          <div class="mt-4 flex flex-wrap gap-2">
            <span class="px-3 py-1 bg-neutral-100 dark:bg-neutral-800 rounded-full text-sm">
              {{ vehicle()?.mileage_km | mileageFormat }}
            </span>
            <span class="px-3 py-1 bg-neutral-100 dark:bg-neutral-800 rounded-full text-sm">
              {{ vehicle()?.transmission }}
            </span>
            <span class="px-3 py-1 bg-neutral-100 dark:bg-neutral-800 rounded-full text-sm">
              {{ vehicle()?.fuel_type }}
            </span>
            <span class="px-3 py-1 bg-neutral-100 dark:bg-neutral-800 rounded-full text-sm">
              {{ vehicle()?.drivetrain }}
            </span>
            <span class="px-3 py-1 bg-neutral-100 dark:bg-neutral-800 rounded-full text-sm">
              {{ vehicle()?.condition }}
            </span>
          </div>
        </div>

        <!-- Price Section with History -->
        <app-price-section
          [currentPrice]="vehicle()?.price_usd"
          [originalPrice]="vehicle()?.original_price_usd"
          [priceHistory]="vehicle()?.price_history || []"
          [priceAnalysis]="vehicle()?.price_analysis"
          [currency]="vehicle()?.currency || 'USD'"
        />

        <!-- Specifications Grid -->
        <app-vehicle-specs [vehicle]="vehicle()" />

        <!-- Features -->
        <app-vehicle-features [features]="vehicle()?.features || []" />

        <!-- Description -->
        @if (vehicle()?.description) {
          <section>
            <h2 class="text-xl font-display font-semibold mb-4">Descripcion</h2>
            <p class="text-neutral-600 dark:text-neutral-400 whitespace-pre-line leading-relaxed">
              {{ vehicle()?.description }}
            </p>
          </section>
        }

        <!-- Location Map -->
        @if (vehicle()?.location_lat && vehicle()?.location_lng) {
          <app-vehicle-location-map
            [lat]="vehicle()!.location_lat!"
            [lng]="vehicle()!.location_lng!"
            [hasGps]="vehicle()!.has_gps_tracking"
            [province]="vehicle()?.location_province"
            [city]="vehicle()?.location_city"
          />
        }

        <!-- Price History Chart -->
        <app-price-history-chart
          [history]="vehicle()?.price_history || []"
          [currentPrice]="vehicle()?.price_usd"
        />
      </div>

      <!-- Right Column (1/3) - Sticky Sidebar -->
      <div class="lg:col-span-1">
        <div class="sticky top-20 space-y-6">
          <!-- Price Card (mobile fixed bottom, desktop sidebar) -->
          <div class="bg-white dark:bg-neutral-800 rounded-xl shadow-lg p-6">
            <div class="text-3xl font-bold text-primary-600">
              {{ vehicle()?.price_usd | currencyFormat }}
            </div>
            @if (vehicle()?.price_analysis?.price_rating) {
              <app-badge [variant]="dealBadgeVariant()">
                {{ vehicle()?.price_analysis?.price_rating | titlecase }}
              </app-badge>
            }
            <div class="mt-4 space-y-3">
              <button (click)="openInquiry()"
                      class="w-full py-3 bg-primary-600 hover:bg-primary-700 text-white rounded-lg font-medium transition-colors">
                Contactar Vendedor
              </button>
              <button (click)="toggleFavorite()"
                      class="w-full py-3 border border-neutral-300 dark:border-neutral-600 rounded-lg font-medium
                             hover:bg-neutral-50 dark:hover:bg-neutral-700 transition-colors flex items-center justify-center gap-2">
                <svg [class.fill-red-500]="isFavorited()" class="w-5 h-5" ...></svg>
                {{ isFavorited() ? 'En Favoritos' : 'Agregar a Favoritos' }}
              </button>
            </div>
          </div>

          <!-- Seller Card -->
          <app-seller-card [seller]="vehicle()?.seller" />

          <!-- Inquiry Form -->
          @if (showInquiryForm()) {
            <app-inquiry-form
              [vehicleId]="vehicle()!.id"
              [sellerName]="vehicle()?.seller?.name"
              (submitted)="onInquirySubmitted()"
              (cancelled)="closeInquiry()"
            />
          }
        </div>
      </div>
    </div>

    <!-- Similar Vehicles -->
    <section class="mt-12">
      <h2 class="text-2xl font-display font-semibold mb-6">Vehiculos Similares</h2>
      <app-similar-vehicles [vehicleId]="vehicle()?.id" />
    </section>
  </div>

  <!-- Fullscreen Gallery Overlay -->
  @if (isGalleryOpen()) {
    <app-fullscreen-gallery
      [media]="vehicle()?.media || []"
      [startIndex]="galleryStartIndex()"
      (close)="closeGallery()"
    />
  }

  <!-- Mobile: Fixed Bottom Price Bar -->
  <div class="lg:hidden fixed bottom-0 left-0 right-0 bg-white dark:bg-neutral-800 border-t
              border-neutral-200 dark:border-neutral-700 p-4 flex items-center justify-between z-30">
    <div>
      <div class="text-xl font-bold text-primary-600">{{ vehicle()?.price_usd | currencyFormat }}</div>
      <div class="text-sm text-neutral-500">{{ vehicle()?.mileage_km | mileageFormat }}</div>
    </div>
    <button (click)="openInquiry()"
            class="px-6 py-3 bg-primary-600 text-white rounded-lg font-medium">
      Contactar
    </button>
  </div>
</div>
```

### Criterios de Aceptacion

1. **AC-001**: El carrusel de fotos hero muestra la imagen principal grande (aspect ratio 16:9 en desktop, 4:3 en mobile) con navegacion prev/next (flechas) y una tira de thumbnails debajo. Soporta swipe en mobile y keyboard arrows en desktop.

2. **AC-002**: Al hacer click en la imagen o boton "Ver todas las fotos", se abre una galeria fullscreen con fondo negro. En fullscreen: zoom con pinch (mobile) y scroll wheel (desktop), swipe para cambiar foto, counter "3/12".

3. **AC-003**: En la galeria fullscreen, el zoom permite ver detalles de la imagen (hasta 3x). Pan/drag funciona cuando esta en zoom. Double-tap/double-click toggle entre zoom y fit.

4. **AC-004**: La seccion de precio muestra: precio actual (grande y prominente), precio original con tachado si hay descuento, porcentaje de descuento, badge de deal rating (Great Deal/Good Deal/Fair Price/Above Market), y dias en el mercado.

5. **AC-005**: El grafico de historial de precios muestra una linea temporal con los cambios de precio del vehiculo. Tooltips muestran la fecha y precio en cada punto. El eje Y muestra el rango de precios, el eje X las fechas.

6. **AC-006**: Las especificaciones se muestran en un grid de 2 columnas con iconos: Motor (displacement, HP, torque), Transmision, Traccion, Combustible, Kilometraje, Condicion, Color Exterior, Color Interior, VIN (parcialmente oculto), Ano.

7. **AC-007**: Las features se muestran como tags/pills en un grid flexible. Si hay mas de 8, muestra las primeras 8 con un boton "Ver todas (+N)" que expande la lista con animacion.

8. **AC-008**: El mapa de ubicacion muestra un pin en la posicion del vehiculo (Google Maps o Mapbox). Si tiene GPS tracking, muestra un indicador "Ubicacion en tiempo real". El mapa es interactivo (zoom, pan) pero no muestra la direccion exacta.

9. **AC-009**: La card del vendedor muestra: logo/avatar, nombre, tipo (dealer/private), rating con estrellas, cantidad de reviews, vehiculos activos, tiempo de respuesta promedio, y boton "Ver perfil".

10. **AC-010**: El formulario de inquiry (contactar vendedor) tiene: campo de mensaje (pre-llenado con "Hola, estoy interesado en el {year} {make} {model}..."), selector de metodo de contacto preferido (WhatsApp, llamada, email), y campo de telefono.

11. **AC-011**: La seccion de vehiculos similares muestra un carrusel horizontal de hasta 6 cards de vehiculos similares (scrollable en mobile, grid en desktop). Cada card es un mini vehicle-card con click para navegar al detalle.

12. **AC-012**: En mobile, el precio y boton "Contactar" se muestran en una barra fija en la parte inferior de la pantalla (fixed bottom bar) que se oculta al scrollar hacia abajo y aparece al scrollar hacia arriba.

13. **AC-013**: Al cargar la pagina, se registra una vista (POST /vehicles/:id/view) silenciosamente. El breadcrumb muestra: Home > Vehiculos > {Make} > {Year} {Make} {Model}.

### Definition of Done

- [ ] Photo carousel con swipe, arrows y thumbnails
- [ ] Fullscreen gallery con zoom y pinch
- [ ] Price section con deal rating y descuento
- [ ] Price history chart interactivo
- [ ] Specifications grid con iconos
- [ ] Features tags expandibles
- [ ] Location map integrado
- [ ] Seller card con info y rating
- [ ] Inquiry form funcional
- [ ] Similar vehicles carousel
- [ ] Mobile fixed bottom bar
- [ ] View registration implementado
- [ ] Breadcrumb navigation
- [ ] SEO meta tags (title, description, og:image)
- [ ] Tests unitarios >= 80%

### Notas Tecnicas

- Para el carrusel, considerar Swiper.js (excelente soporte de gestos) o implementacion custom con Angular CDK
- El zoom en fullscreen puede usar panzoom o una implementacion custom con CSS transform
- El grafico de precios puede implementarse con Chart.js (lightweight) o ngx-charts
- Para el mapa, Google Maps API o Mapbox GL JS. Considerar leaflet como alternativa open source
- El SEO requiere Angular SSR (Server-Side Rendering) para meta tags dinamicas en el head
- Las imagenes deben tener srcset para responsive (400w, 800w, 1200w, 1920w)

### Dependencias

- MKT-BE-007: API de detalle con media, price history, similar
- MKT-FE-001: UI components, layout
- MKT-BE-004: SVC-USR para favoritos
- Google Maps API key o Mapbox token

---

## User Story 7: [MKT-FE-008][FE-FEAT-CAT] Comparacion de hasta 4 Vehiculos Side-by-Side

### Descripcion

Como comprador que esta evaluando opciones, necesito poder comparar hasta 4 vehiculos lado a lado para ver las diferencias en especificaciones, precio, equipamiento y fotos. La comparacion debe resaltar las diferencias y ayudarme a tomar una decision.

### Microservicio

- **Nombre**: FE-FEAT-CAT
- **Puerto**: 4200

### Contexto Tecnico

#### Componentes

```
features/
  vehicles/
    vehicle-compare/
      compare-page.component.ts               # Main comparison page
      compare-page.component.html
      compare-page.component.spec.ts
      components/
        compare-header/
          compare-header.component.ts          # Vehicle photos + basic info header
        compare-row/
          compare-row.component.ts             # Single spec comparison row
        compare-add-slot/
          compare-add-slot.component.ts        # Empty slot to add vehicle
        compare-highlight/
          compare-highlight.component.ts       # Highlights best/worst values
      services/
        compare-state.service.ts               # Signal-based compare state (max 4)
```

#### Compare State Service

```typescript
// compare-state.service.ts
import { Injectable, signal, computed } from '@angular/core';

export interface CompareVehicle {
  id: string;
  make: string;
  model: string;
  year: number;
  trim: string | null;
  price_usd: string;
  mileage_km: number;
  fuel_type: string;
  transmission: string;
  drivetrain: string;
  body_type: string;
  condition: string;
  engine_displacement_cc: number | null;
  horsepower: number | null;
  torque_nm: number | null;
  exterior_color: string | null;
  interior_color: string | null;
  features: string[];
  primary_image_url: string | null;
  location_province: string | null;
  has_gps_tracking: boolean;
  is_verified: boolean;
  views_count: number;
  favorites_count: number;
}

@Injectable({ providedIn: 'root' })
export class CompareStateService {
  private readonly MAX_VEHICLES = 4;
  private readonly _vehicles = signal<CompareVehicle[]>([]);

  readonly vehicles = this._vehicles.asReadonly();
  readonly count = computed(() => this._vehicles().length);
  readonly isFull = computed(() => this._vehicles().length >= this.MAX_VEHICLES);
  readonly isEmpty = computed(() => this._vehicles().length === 0);
  readonly vehicleIds = computed(() => this._vehicles().map(v => v.id));

  addVehicle(vehicle: CompareVehicle): boolean {
    if (this.isFull()) return false;
    if (this.vehicleIds().includes(vehicle.id)) return false;
    this._vehicles.update(list => [...list, vehicle]);
    this.persistToStorage();
    return true;
  }

  removeVehicle(vehicleId: string): void {
    this._vehicles.update(list => list.filter(v => v.id !== vehicleId));
    this.persistToStorage();
  }

  clearAll(): void {
    this._vehicles.set([]);
    localStorage.removeItem('compare_vehicles');
  }

  isInCompare(vehicleId: string): boolean {
    return this.vehicleIds().includes(vehicleId);
  }

  private persistToStorage(): void {
    localStorage.setItem('compare_vehicles', JSON.stringify(this._vehicles()));
  }

  loadFromStorage(): void {
    const saved = localStorage.getItem('compare_vehicles');
    if (saved) {
      try {
        this._vehicles.set(JSON.parse(saved));
      } catch {
        localStorage.removeItem('compare_vehicles');
      }
    }
  }
}
```

#### Comparison Spec Rows

```typescript
// Comparison categories and specs
export const COMPARE_SECTIONS = [
  {
    title: 'General',
    specs: [
      { key: 'year', label: 'Ano', format: 'number' },
      { key: 'body_type', label: 'Tipo de Carroceria', format: 'text' },
      { key: 'condition', label: 'Condicion', format: 'text' },
      { key: 'mileage_km', label: 'Kilometraje', format: 'mileage', highlight: 'lowest' },
      { key: 'exterior_color', label: 'Color Exterior', format: 'text' },
      { key: 'interior_color', label: 'Color Interior', format: 'text' },
    ]
  },
  {
    title: 'Motor y Rendimiento',
    specs: [
      { key: 'engine_displacement_cc', label: 'Cilindrada (cc)', format: 'number' },
      { key: 'horsepower', label: 'Potencia (HP)', format: 'number', highlight: 'highest' },
      { key: 'torque_nm', label: 'Torque (Nm)', format: 'number', highlight: 'highest' },
      { key: 'fuel_type', label: 'Combustible', format: 'text' },
      { key: 'transmission', label: 'Transmision', format: 'text' },
      { key: 'drivetrain', label: 'Traccion', format: 'text' },
    ]
  },
  {
    title: 'Precio y Valor',
    specs: [
      { key: 'price_usd', label: 'Precio', format: 'currency', highlight: 'lowest' },
      { key: 'price_per_km', label: 'Precio por km', format: 'currency', computed: true, highlight: 'lowest' },
      { key: 'views_count', label: 'Vistas', format: 'number', highlight: 'highest' },
      { key: 'favorites_count', label: 'Favoritos', format: 'number', highlight: 'highest' },
    ]
  },
  {
    title: 'Ubicacion y Estado',
    specs: [
      { key: 'location_province', label: 'Provincia', format: 'text' },
      { key: 'has_gps_tracking', label: 'GPS Tracking', format: 'boolean' },
      { key: 'is_verified', label: 'Verificado', format: 'boolean' },
    ]
  }
];
```

### Criterios de Aceptacion

1. **AC-001**: El usuario puede agregar vehiculos a la comparacion desde: (a) boton "Comparar" en la vehicle card del catalogo, (b) boton "Agregar a comparacion" en la pagina de detalle. El boton muestra toggle state (agregar/quitar).

2. **AC-002**: Se pueden comparar entre 2 y 4 vehiculos. Si intenta agregar un 5to, muestra toast "Maximo 4 vehiculos para comparar. Quita uno para agregar otro."

3. **AC-003**: Un floating bar en la parte inferior muestra los vehiculos en comparacion (thumbnails + nombre) con un boton "Comparar (N)". Al hacer click, navega a /vehicles/compare.

4. **AC-004**: La pagina de comparacion muestra las fotos de cada vehiculo en la fila superior. Debajo, una tabla con las especificaciones agrupadas por categoria (General, Motor, Precio, Ubicacion).

5. **AC-005**: Los valores mejores en cada fila se resaltan en verde (ej: menor precio, menor mileage, mayor potencia). Los peores se resaltan en rojo claro. Los que son iguales no se resaltan.

6. **AC-006**: Las features de cada vehiculo se muestran como una tabla de checkmarks: cada feature que tiene un vehiculo muestra un checkmark verde, las que no tiene muestran un dash gris.

7. **AC-007**: La tabla es responsive: en mobile, se muestra en formato horizontal scrollable. Un sticky header con los nombres de los vehiculos se mantiene visible al scrollar las filas.

8. **AC-008**: Se puede quitar un vehiculo de la comparacion desde la pagina de comparacion. Se puede agregar un vehiculo faltante via un slot vacio con boton "Agregar vehiculo" que abre un search modal.

9. **AC-009**: La comparacion se persiste en localStorage, permitiendo al usuario navegar a otros paginas y volver sin perder la seleccion.

10. **AC-010**: Se incluye un campo calculado "Precio por km" (price_usd / mileage_km) para comparar el valor relativo.

11. **AC-011**: Al imprimir la pagina (Ctrl+P), se genera una version print-friendly de la comparacion con toda la informacion visible en formato tabular limpio.

12. **AC-012**: Si solo hay un vehiculo en la comparacion, la pagina muestra un mensaje "Agrega al menos un vehiculo mas para comparar" con sugerencias de vehiculos similares.

### Definition of Done

- [ ] Add/remove from compare desde catalog y detail
- [ ] Floating compare bar con thumbnails
- [ ] Compare page con tabla de especificaciones
- [ ] Highlight de mejores/peores valores
- [ ] Features comparison con checkmarks
- [ ] Responsive horizontal scroll en mobile
- [ ] Persistencia en localStorage
- [ ] Search modal para agregar vehiculo
- [ ] Print-friendly version
- [ ] Tests unitarios >= 80%

### Notas Tecnicas

- El compare state es global (providedIn: root) para compartir entre catalog, detail y compare page
- Los datos de comparacion vienen del endpoint de detalle (GET /vehicles/:id) para cada vehiculo
- Considerar hacer un batch request para obtener los detalles de todos los vehiculos en paralelo (Promise.all)
- La tabla horizontal en mobile puede usar CSS scroll-snap para alineacion limpia
- El search modal para agregar reutiliza el search-bar component del catalogo

### Dependencias

- MKT-FE-005: Catalog page (boton de comparar en cards)
- MKT-FE-007: Detail page (boton de comparar)
- MKT-BE-007: API de detalle de vehiculo

---

## User Story 8: [MKT-INT-001][WRK-SYNC] Sync scrapper_nacional a marketplace.vehicles

### Descripcion

Como sistema, necesito un worker que sincronice los 11,000+ vehiculos de la base de datos scrapper_nacional a la tabla marketplace.vehicles del marketplace. El sync debe ser incremental (solo cambios), manejar duplicados, normalizar datos, enriquecer con GPS data, indexar en Elasticsearch, y emitir eventos SQS para notificar a otros servicios.

### Microservicio

- **Nombre**: WRK-SYNC (Worker de Sincronizacion)
- **Tecnologia**: Python 3.11, SQLAlchemy 2.0, Celery / SQS consumer
- **Bases de datos**: scrapper_nacional (source, read-only), marketplace (destination, read-write)
- **Message Queue**: AWS SQS (sync-queue)
- **Patron**: ETL (Extract, Transform, Load) + Event-Driven

### Contexto Tecnico

#### Estructura de Archivos

```
wrk-sync/
  app/
    __init__.py
    cfg/
      __init__.py
      settings.py                      # DB URLs, SQS config, batch size
      source_db.py                     # Connection to scrapper_nacional
      target_db.py                     # Connection to marketplace
      elasticsearch_config.py
      sqs_config.py
    dom/
      __init__.py
      models/
        source_vehicle.py              # scrapper_nacional vehicle model
        target_vehicle.py              # marketplace vehicle model
        sync_log.py                    # Sync execution log
        sync_mapping.py                # Source ID -> Target ID mapping
        gps_data.py                    # GPS tracking data model
      services/
        normalizer.py                  # Data normalization logic
        deduplicator.py                # Duplicate detection
        enricher.py                    # GPS data, AI agent enrichment
        mapper.py                      # Source -> Target field mapping
      ports/
        source_repository.py           # Abstract source data access
        target_repository.py           # Abstract target data access
        search_indexer.py              # Abstract search indexing
        event_publisher.py             # Abstract event publishing
    app/
      __init__.py
      use_cases/
        full_sync.py                   # Full sync (initial load)
        incremental_sync.py            # Incremental sync (only changes)
        sync_single.py                 # Sync a single vehicle by source ID
        reindex_elasticsearch.py       # Full ES reindex
        cleanup_stale.py               # Remove vehicles no longer in source
    inf/
      __init__.py
      persistence/
        source_repository_impl.py      # SQLAlchemy read from scrapper_nacional
        target_repository_impl.py      # SQLAlchemy write to marketplace
        sync_log_repository.py
      search/
        elasticsearch_indexer.py       # ES bulk indexing
      messaging/
        sqs_publisher.py               # Publish sync events to SQS
      gps/
        gps_data_provider.py           # Read GPS data for vehicles
    api/
      __init__.py
      routes/
        sync_routes.py                 # Manual trigger endpoints (admin)
        health_routes.py
    tst/
      __init__.py
      unit/
        test_normalizer.py
        test_deduplicator.py
        test_mapper.py
      integration/
        test_full_sync.py
        test_incremental_sync.py
  Dockerfile
  docker-compose.yml
  requirements.txt
  .env.example
```

#### Source Data Model (scrapper_nacional)

```python
# dom/models/source_vehicle.py
# This represents the existing data in scrapper_nacional DB
# Read-only access - DO NOT modify source schema

@dataclass
class SourceVehicle:
    id: int                            # Auto-increment ID in source
    source_name: str                   # One of 18 sources (e.g., "encuentra24", "mercadolibre")
    source_url: str                    # Original listing URL
    title: str                         # Raw title from listing
    description: str                   # Raw description
    price: float                       # Price (may be in different currencies)
    currency: str                      # "USD", "PAB" (same as USD in Panama)
    make: str                          # May need normalization
    model: str                         # May need normalization
    year: int
    mileage: int                       # May be in km or miles depending on source
    mileage_unit: str                  # "km" or "mi"
    fuel_type: str                     # Raw, needs normalization
    transmission: str                  # Raw, needs normalization
    body_type: str                     # Raw, needs normalization
    color: str                         # Raw exterior color
    location: str                      # Raw location string
    images: list[str]                  # List of image URLs from source
    features_raw: str                  # Raw features text
    seller_name: str
    seller_phone: str
    seller_type: str                   # Raw
    vin: str                           # May be partial or missing
    plate: str                         # License plate (if available)
    scraped_at: datetime               # When it was scraped
    updated_at: datetime               # Last update from source
    is_active: bool                    # Still active in source?
    raw_data: dict                     # Complete raw JSON from scraping
```

#### Normalization Logic

```python
# dom/services/normalizer.py

class VehicleNormalizer:
    """Normalizes raw scraped data into clean marketplace format."""

    # Make normalization mapping
    MAKE_MAP = {
        "TOYOTA": "Toyota",
        "toyota": "Toyota",
        "HONDA": "Honda",
        "HYUNDAI": "Hyundai",
        "KIA": "Kia",
        "NISSAN": "Nissan",
        "CHEVROLET": "Chevrolet",
        "FORD": "Ford",
        "MERCEDES-BENZ": "Mercedes-Benz",
        "MERCEDES BENZ": "Mercedes-Benz",
        "MB": "Mercedes-Benz",
        "BMW": "BMW",
        "VOLKSWAGEN": "Volkswagen",
        "VW": "Volkswagen",
        "MITSUBISHI": "Mitsubishi",
        "SUZUKI": "Suzuki",
        "JEEP": "Jeep",
        "LAND ROVER": "Land Rover",
        "LANDROVER": "Land Rover",
        # ... 50+ more mappings
    }

    FUEL_MAP = {
        "gasolina": "gasoline",
        "gas": "gasoline",
        "nafta": "gasoline",
        "diesel": "diesel",
        "petroleo": "diesel",
        "gasoil": "diesel",
        "electrico": "electric",
        "hibrido": "hybrid",
        "hibrido enchufable": "plug_in_hybrid",
        "glp": "lpg",
        "gas natural": "cng",
    }

    TRANSMISSION_MAP = {
        "automatica": "automatic",
        "automatico": "automatic",
        "auto": "automatic",
        "at": "automatic",
        "manual": "manual",
        "mecanica": "manual",
        "estandar": "manual",
        "mt": "manual",
        "cvt": "cvt",
        "tiptronic": "semi_automatic",
        "secuencial": "semi_automatic",
    }

    BODY_MAP = {
        "sedan": "sedan",
        "berlina": "sedan",
        "suv": "suv",
        "camioneta": "suv",
        "pickup": "pickup",
        "pick-up": "pickup",
        "pick up": "pickup",
        "hatchback": "hatchback",
        "hatch": "hatchback",
        "coupe": "coupe",
        "convertible": "convertible",
        "cabrio": "convertible",
        "van": "van",
        "minivan": "van",
        "wagon": "wagon",
        "familiar": "wagon",
        "crossover": "crossover",
    }

    PROVINCE_MAP = {
        "panama": "Panama",
        "ciudad de panama": "Panama",
        "ptj": "Panama",
        "chiriqui": "Chiriqui",
        "david": "Chiriqui",
        "colon": "Colon",
        "cocle": "Cocle",
        "veraguas": "Veraguas",
        "herrera": "Herrera",
        "los santos": "Los Santos",
        "bocas del toro": "Bocas del Toro",
        "darien": "Darien",
    }

    FEATURE_KEYWORDS = {
        "sunroof": ["techo solar", "sunroof", "moonroof", "techo panoramico", "panoramic"],
        "leather_seats": ["cuero", "leather", "piel"],
        "backup_camera": ["camara trasera", "camara de retroceso", "backup camera", "rearview camera"],
        "bluetooth": ["bluetooth", "bt"],
        "apple_carplay": ["carplay", "apple carplay"],
        "android_auto": ["android auto"],
        "cruise_control": ["cruise control", "control crucero"],
        "adaptive_cruise_control": ["acc", "adaptive cruise", "cruise adaptativo"],
        "lane_departure_warning": ["alerta de carril", "lane departure", "ldw"],
        "blind_spot_monitor": ["punto ciego", "blind spot", "bsm"],
        "heated_seats": ["asientos calefaccionados", "heated seats", "asientos con calefaccion"],
        "navigation": ["navegacion", "gps", "navigation", "nav"],
        "keyless_entry": ["keyless", "sin llave", "smart key"],
        "push_start": ["push start", "boton de encendido", "push button start"],
        "parking_sensors": ["sensores de estacionamiento", "parking sensors", "sensores de parqueo"],
        "alloy_wheels": ["rines de aleacion", "alloy wheels", "rines deportivos"],
    }

    def normalize_make(self, raw: str) -> str:
        normalized = self.MAKE_MAP.get(raw.upper().strip(), None)
        if not normalized:
            # Title case fallback
            normalized = raw.strip().title()
        return normalized

    def normalize_fuel(self, raw: str) -> str:
        return self.FUEL_MAP.get(raw.lower().strip(), "gasoline")

    def normalize_transmission(self, raw: str) -> str:
        return self.TRANSMISSION_MAP.get(raw.lower().strip(), "automatic")

    def normalize_body_type(self, raw: str) -> str:
        return self.BODY_MAP.get(raw.lower().strip(), "sedan")

    def normalize_province(self, raw_location: str) -> tuple[str, str]:
        """Returns (province, city) from raw location string."""
        location_lower = raw_location.lower().strip()
        for key, province in self.PROVINCE_MAP.items():
            if key in location_lower:
                return province, raw_location.strip()
        return "Panama", raw_location.strip()

    def extract_features(self, raw_features: str, raw_description: str) -> list[str]:
        """Extract normalized features from raw text."""
        combined = f"{raw_features} {raw_description}".lower()
        features = []
        for feature_key, keywords in self.FEATURE_KEYWORDS.items():
            for keyword in keywords:
                if keyword in combined:
                    features.append(feature_key)
                    break
        return features

    def normalize_mileage(self, value: int, unit: str) -> int:
        """Convert to km if in miles."""
        if unit.lower() in ("mi", "miles", "millas"):
            return int(value * 1.60934)
        return value

    def normalize_price(self, price: float, currency: str) -> float:
        """Normalize to USD. PAB = USD in Panama."""
        if currency.upper() in ("PAB", "USD", "$"):
            return round(price, 2)
        # Add other currency conversions as needed
        return round(price, 2)
```

#### Sync Use Case

```python
# app/use_cases/incremental_sync.py

class IncrementalSyncUseCase:
    def __init__(self, source_repo, target_repo, normalizer, deduplicator,
                 enricher, search_indexer, event_publisher):
        self.source_repo = source_repo
        self.target_repo = target_repo
        self.normalizer = normalizer
        self.deduplicator = deduplicator
        self.enricher = enricher
        self.search_indexer = search_indexer
        self.event_publisher = event_publisher

    def execute(self, since: datetime = None, batch_size: int = 100) -> SyncResult:
        """Sync vehicles that changed since last sync."""
        if since is None:
            since = self.target_repo.get_last_sync_timestamp()

        stats = SyncResult()
        offset = 0

        while True:
            # Extract: Get changed vehicles from source
            source_vehicles = self.source_repo.find_updated_since(
                since=since, limit=batch_size, offset=offset
            )
            if not source_vehicles:
                break

            for source_vehicle in source_vehicles:
                try:
                    # Transform: Normalize data
                    normalized = self._transform(source_vehicle)

                    # Check for duplicates
                    existing = self.target_repo.find_by_external_id(
                        external_id=str(source_vehicle.id),
                        source=source_vehicle.source_name
                    )

                    if existing:
                        # Update existing
                        self._update_vehicle(existing, normalized)
                        stats.updated += 1
                    else:
                        # Deduplicate: Check if same vehicle from different source
                        duplicate = self.deduplicator.find_duplicate(normalized)
                        if duplicate:
                            # Merge with existing (keep best data)
                            self._merge_vehicle(duplicate, normalized)
                            stats.merged += 1
                        else:
                            # Create new
                            self._create_vehicle(normalized)
                            stats.created += 1

                except Exception as e:
                    stats.errors += 1
                    stats.error_details.append({
                        "source_id": source_vehicle.id,
                        "source": source_vehicle.source_name,
                        "error": str(e)
                    })

            offset += batch_size
            stats.processed += len(source_vehicles)

        # Index all changed vehicles in Elasticsearch
        changed_ids = stats.get_all_changed_ids()
        if changed_ids:
            vehicles = self.target_repo.find_by_ids(changed_ids)
            self.search_indexer.bulk_index(vehicles)

        # Publish sync completed event
        self.event_publisher.publish("sync.completed", {
            "processed": stats.processed,
            "created": stats.created,
            "updated": stats.updated,
            "merged": stats.merged,
            "errors": stats.errors,
            "timestamp": datetime.utcnow().isoformat()
        })

        return stats
```

#### SQS Event Format

```json
// Event: vehicle.created
{
  "event_type": "vehicle.created",
  "timestamp": "2026-03-23T10:00:00Z",
  "data": {
    "vehicle_id": "veh-uuid-new",
    "make": "Toyota",
    "model": "Corolla",
    "year": 2022,
    "price_usd": 18500.00,
    "source": "encuentra24",
    "external_id": "12345"
  }
}

// Event: vehicle.updated
{
  "event_type": "vehicle.updated",
  "timestamp": "2026-03-23T10:05:00Z",
  "data": {
    "vehicle_id": "veh-uuid-existing",
    "changes": {
      "price_usd": { "old": 20000.00, "new": 18500.00 },
      "mileage_km": { "old": 35000, "new": 36000 }
    }
  }
}

// Event: vehicle.price_changed
{
  "event_type": "vehicle.price_changed",
  "timestamp": "2026-03-23T10:05:00Z",
  "data": {
    "vehicle_id": "veh-uuid-existing",
    "old_price": 20000.00,
    "new_price": 18500.00,
    "change_percentage": -7.5,
    "direction": "decrease"
  }
}

// Event: sync.completed
{
  "event_type": "sync.completed",
  "timestamp": "2026-03-23T10:30:00Z",
  "data": {
    "processed": 11247,
    "created": 45,
    "updated": 312,
    "merged": 8,
    "errors": 3,
    "duration_seconds": 180
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: El full sync importa los 11,000+ vehiculos de scrapper_nacional a marketplace.vehicles en menos de 30 minutos. Procesa en batches de 100 vehiculos para evitar memory issues.

2. **AC-002**: El incremental sync detecta vehiculos nuevos o actualizados desde el ultimo sync (basado en updated_at) y solo procesa esos. Se ejecuta automaticamente cada 1 hora via scheduled task.

3. **AC-003**: La normalizacion transforma correctamente: makes (case, abreviaciones), fuel types (espanol -> ingles), transmissions, body types, provinces, y mileage (miles -> km).

4. **AC-004**: La extraccion de features analiza el texto de features_raw y description para identificar features estandarizadas (sunroof, leather_seats, backup_camera, etc.) usando keyword matching.

5. **AC-005**: La deduplicacion detecta vehiculos duplicados entre las 18 fuentes usando: VIN match (si disponible) o combinacion de (make + model + year + mileage_km +/- 5% + province). Los duplicados se mergen manteniendo los datos mas completos.

6. **AC-006**: Cuando el precio de un vehiculo cambia, se crea un registro en price_history y se emite un evento "vehicle.price_changed" a SQS para que WRK-NTF pueda notificar a usuarios con el vehiculo en favoritos.

7. **AC-007**: Los vehiculos que dejan de estar activos en la fuente (is_active=false) se marcan como "expired" en marketplace despues de 3 syncs consecutivos sin aparecer.

8. **AC-008**: El enricher agrega datos de GPS (coordenadas) a los vehiculos que tienen match en la tabla de GPS data (4,000+ vehiculos). El match se hace por plate_number o VIN.

9. **AC-009**: Despues de cada sync, los vehiculos creados y actualizados se indexan en Elasticsearch via bulk API. La indexacion no bloquea el sync.

10. **AC-010**: Las imagenes del source se descargan, redimensionan (1920px, 800px, 400px, 200px thumbnail), se convierten a WebP, y se suben a S3. Las URLs en marketplace apuntan al CDN.

11. **AC-011**: El sync genera un log detallado (sync_log) con: timestamp, duracion, vehiculos procesados, creados, actualizados, mergeados, errores. Los errores incluyen el source_id y el mensaje de error.

12. **AC-012**: Los endpoints admin (POST /internal/sync/full, POST /internal/sync/incremental) permiten ejecutar el sync manualmente. Solo accesibles por admin con autenticacion interna (API key).

13. **AC-013**: El worker consume mensajes de SQS sync-queue para syncs bajo demanda (ej: una fuente especifica publica un nuevo vehiculo, se envia un mensaje a SQS para sync inmediato de esa fuente).

### Definition of Done

- [ ] Full sync de 11,000+ vehiculos funcional y testeado
- [ ] Incremental sync con deteccion de cambios
- [ ] Normalizacion de todos los campos (make, fuel, transmission, etc.)
- [ ] Feature extraction de texto libre
- [ ] Deduplicacion cross-source funcional
- [ ] Price history tracking con eventos SQS
- [ ] GPS data enrichment
- [ ] Elasticsearch bulk indexing post-sync
- [ ] Image processing y upload a S3
- [ ] Sync logging con metricas
- [ ] Scheduled execution (cada hora)
- [ ] Admin endpoints para sync manual
- [ ] Tests >= 85% cobertura
- [ ] Documentacion de mapping de campos por fuente

### Notas Tecnicas

- Acceder a scrapper_nacional en modo READ-ONLY (nunca escribir en la fuente)
- La conexion a scrapper_nacional debe usar un usuario de DB separado con solo SELECT
- Para el image processing, usar Pillow (PIL) con quality 85 para WebP
- El bulk indexing de ES usa la API _bulk con batches de 500 documentos
- Considerar usar multiprocessing o asyncio para el procesamiento de imagenes (I/O heavy)
- Las 18 fuentes pueden tener schemas ligeramente diferentes - el mapper maneja las variaciones
- El scheduled task puede implementarse con Celery Beat o CloudWatch Events + Lambda trigger

### Dependencias

- Acceso read-only a base de datos scrapper_nacional
- MKT-BE-002: Tablas de marketplace creadas (migrations ejecutadas)
- MKT-INF-002: SQS queues, S3 bucket, Elasticsearch cluster
- GPS data table accesible (read-only)

---

## Resumen de Dependencias entre Stories

```
MKT-INT-001 (WRK-SYNC: Data Sync)
    |
    +---> MKT-BE-005 (Listado Paginado) ---+
    |                                       |
    +---> MKT-BE-006 (Busqueda ES) --------+---> MKT-FE-005 (Catalogo Grid/List)
    |                                       |         |
    +---> MKT-BE-007 (Detalle) ------+     |         +---> MKT-FE-006 (Panel Filtros)
                                     |     |
                                     v     v
                               MKT-FE-007 (Detalle Page)
                                     |
                                     v
                               MKT-FE-008 (Comparacion)
```

## Estimacion de Esfuerzo

| Story | Estimacion | Developers |
|-------|-----------|------------|
| MKT-BE-005 (Listado Paginado) | 8 points | 1 Backend Sr |
| MKT-BE-006 (Busqueda ES) | 13 points | 1 Backend Sr |
| MKT-BE-007 (Detalle) | 8 points | 1 Backend Sr |
| MKT-FE-005 (Catalogo Grid) | 13 points | 1 Frontend Sr |
| MKT-FE-006 (Panel Filtros) | 13 points | 1 Frontend Sr |
| MKT-FE-007 (Detalle Page) | 21 points | 1 Frontend Sr + 1 Frontend Jr |
| MKT-FE-008 (Comparacion) | 13 points | 1 Frontend Mid |
| MKT-INT-001 (WRK-SYNC) | 21 points | 1 Backend Sr + 1 Data Engineer |
| **Total** | **110 points** | **Sprint 2-4** |
