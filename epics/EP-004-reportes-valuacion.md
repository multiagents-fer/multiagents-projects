# [MKT-EP-004] Reportes Tecnicos, Valuacion & Evaluacion de Mercado

**Sprint**: 3-5
**Priority**: High
**Owner**: Backend & Frontend Teams
**Status**: Draft

---

## Epic Overview

This epic covers the full lifecycle of vehicle technical reporting, AI-powered market valuation, and market trend analysis. It leverages the existing 11,000+ vehicles from 18 sources in the `scrapper_nacional` database, OBD-II diagnostic data, GPS telemetry, and three AI agents (Depreciation Agent on port 5001, Marketplace Analytics Agent, and Report Builder Agent) to deliver actionable insights to buyers, sellers, and marketplace administrators.

The reports module (SVC-RPT on port 5021) is the primary backend service, with SVC-MKT (port 5019) handling market analytics. The frontend delivers two main experiences: a detailed per-vehicle technical report view and an interactive market analysis dashboard.

### Key Metrics
- Report generation time: < 5 seconds for standard, < 30 seconds for AI-enriched
- Valuation accuracy: within 5% of actual sale price (benchmarked against historical transactions)
- Dashboard load time: < 2 seconds with cached data
- PDF report generation: < 10 seconds

### Architecture Context

```
[FE Angular 18] --> [SVC-GW :8080] --> [SVC-RPT :5021] --> [PostgreSQL / Redis / Elasticsearch]
                                    --> [SVC-MKT :5019] --> [scrapper_nacional DB]
                                                        --> [AI Agents (Depreciation :5001, Analytics, Report Builder)]
```

### Dependencies
- SVC-VEH (port 5012): Vehicle catalog and detail data
- SVC-RPT (port 5021): Report generation and storage
- SVC-MKT (port 5019): Market analytics and trends
- AI Agents: Depreciation (port 5001), Marketplace Analytics, Report Builder
- Workers: WRK-SYNC (data synchronization from 18 sources)
- Infrastructure: PostgreSQL 15, Redis 7 (caching), Elasticsearch 8 (search/aggregation)
- External: OBD-II diagnostic data feed, GPS telemetry data

---

## User Stories

---

### [MKT-BE-008][SVC-RPT-API] API de Reportes Tecnicos por Vehiculo

**Description**:
Build a REST API within SVC-RPT (port 5021) that generates and serves comprehensive technical reports for any vehicle in the marketplace. The report consolidates OBD-II diagnostic data (DTC codes, sensor readings, freeze frame data), GPS-derived usage patterns, and computed health scores. Each vehicle system (engine, transmission, brakes, electrical, emissions, suspension, HVAC) receives a health score from 0 to 100, and an overall vehicle health score is calculated as a weighted average. Reports are cached in Redis with a configurable TTL and stored permanently in PostgreSQL for historical comparison.

**Microservice**: SVC-RPT (port 5021)
**Layer**: API (routes) + APP (application services) + DOM (domain models) + INF (OBD-II adapter, Redis cache, S3 for PDFs)

#### Technical Context

**Endpoints**:

```
GET    /api/v1/reports/technical/{vehicle_id}
       Query params: ?include_dtc=true&include_sensors=true&include_history=true&format=json|pdf
       Response: 200 TechnicalReportResponse | 404 VehicleNotFound | 503 DiagnosticDataUnavailable

POST   /api/v1/reports/technical/{vehicle_id}/generate
       Body: { "force_refresh": false, "include_sections": ["obd", "gps", "health"] }
       Response: 202 { "report_id": "uuid", "status": "generating", "estimated_seconds": 5 }

GET    /api/v1/reports/technical/{vehicle_id}/history
       Query params: ?page=1&per_page=10&from_date=2024-01-01&to_date=2024-12-31
       Response: 200 PaginatedReportHistory

GET    /api/v1/reports/technical/{vehicle_id}/pdf
       Response: 200 application/pdf | 202 "generating" | 404 NotFound

GET    /api/v1/reports/technical/{vehicle_id}/health-score
       Response: 200 { "overall": 85, "systems": {...}, "trend": "improving" }
```

**Data Models**:

```python
# DOM Layer - domain/models/technical_report.py
class TechnicalReport:
    id: UUID
    vehicle_id: UUID
    report_date: datetime
    overall_health_score: int  # 0-100
    systems: List[SystemHealth]
    dtc_codes: List[DTCCode]
    sensor_readings: List[SensorReading]
    gps_summary: GPSSummary
    obd_snapshot: OBDSnapshot
    created_at: datetime
    expires_at: datetime
    version: int

class SystemHealth:
    system_name: str  # engine, transmission, brakes, electrical, emissions, suspension, hvac
    health_score: int  # 0-100
    status: str  # healthy, warning, critical
    issues: List[str]
    last_checked: datetime
    weight: float  # for weighted average calculation

class DTCCode:
    code: str  # e.g., P0301
    description: str
    severity: str  # info, warning, critical
    system: str
    first_seen: datetime
    last_seen: datetime
    occurrence_count: int
    is_active: bool
    freeze_frame: Optional[dict]

class SensorReading:
    sensor_id: str
    sensor_name: str
    value: float
    unit: str
    min_normal: float
    max_normal: float
    status: str  # normal, warning, critical
    timestamp: datetime

class GPSSummary:
    total_distance_km: float
    avg_daily_km: float
    primary_usage: str  # urban, highway, mixed
    harsh_braking_events: int
    harsh_acceleration_events: int
    max_speed_recorded: float
    geo_zones: List[str]

class OBDSnapshot:
    protocol: str
    firmware_version: str
    supported_pids: List[str]
    last_connection: datetime
    connection_quality: str
```

**Marshmallow Schemas**:

```python
# API Layer - api/schemas/technical_report_schema.py
class TechnicalReportSchema(Schema):
    id = fields.UUID(dump_only=True)
    vehicle_id = fields.UUID(required=True)
    report_date = fields.DateTime(dump_only=True)
    overall_health_score = fields.Integer(dump_only=True)
    systems = fields.Nested(SystemHealthSchema, many=True)
    dtc_codes = fields.Nested(DTCCodeSchema, many=True)
    sensor_readings = fields.Nested(SensorReadingSchema, many=True)
    gps_summary = fields.Nested(GPSSummarySchema)
    generated_at = fields.DateTime(dump_only=True)
```

#### Acceptance Criteria

1. **AC-001**: GET `/api/v1/reports/technical/{vehicle_id}` returns a complete technical report with overall health score (0-100) and per-system health scores for all 7 systems (engine, transmission, brakes, electrical, emissions, suspension, HVAC), with response time under 500ms when cached.
2. **AC-002**: POST `/api/v1/reports/technical/{vehicle_id}/generate` triggers an asynchronous report generation job, returns a 202 with `report_id` and `estimated_seconds`, and the report is available via GET within the estimated time.
3. **AC-003**: Each DTC code in the report includes: code identifier, human-readable description, severity level (info/warning/critical), associated system, first and last seen timestamps, occurrence count, active/historical flag, and freeze frame data when available.
4. **AC-004**: Sensor readings include the raw value, unit of measurement, normal range (min/max), and a computed status (normal/warning/critical) based on manufacturer thresholds stored in the domain configuration.
5. **AC-005**: The overall health score is computed as a weighted average of all 7 system scores, where engine weight=0.25, transmission=0.20, brakes=0.20, electrical=0.10, emissions=0.10, suspension=0.10, HVAC=0.05.
6. **AC-006**: System health status follows traffic light logic: healthy (score >= 70, green), warning (score 40-69, yellow), critical (score < 40, red). Status is computed deterministically from the score.
7. **AC-007**: Reports are cached in Redis with a configurable TTL (default 24 hours). A `force_refresh=true` parameter bypasses cache and regenerates the report from live data.
8. **AC-008**: GET `/api/v1/reports/technical/{vehicle_id}/history` returns paginated historical reports with `page`, `per_page`, `from_date`, and `to_date` filters. Default pagination is page=1, per_page=10.
9. **AC-009**: GET `/api/v1/reports/technical/{vehicle_id}/pdf` returns a pre-generated PDF report. If no PDF exists, it returns 202 and triggers async PDF generation. PDF includes all report sections with charts rendered server-side.
10. **AC-010**: The API returns 404 with `{ "error": "vehicle_not_found", "message": "..." }` when the vehicle_id does not exist in SVC-VEH, and 503 with `{ "error": "diagnostic_data_unavailable" }` when OBD-II data cannot be retrieved.
11. **AC-011**: All endpoints require a valid JWT token via Authorization header. The token is validated against AWS Cognito. Unauthorized requests return 401.
12. **AC-012**: GPS summary data includes total distance, average daily kilometers, primary usage pattern classification (urban/highway/mixed), harsh driving event counts, and geographic zone history.
13. **AC-013**: Report generation handles vehicles with partial data gracefully -- if OBD-II data is unavailable, the report is generated with available data and includes a `data_completeness` field indicating which sections have data.

#### Definition of Done
- All endpoints implemented and returning correct HTTP status codes
- Marshmallow schemas validate all input/output
- Redis caching with configurable TTL operational
- PDF generation working via async worker
- Unit tests cover all domain logic (health score calculation, status classification)
- Integration tests cover all API endpoints
- API documentation in OpenAPI/Swagger format
- Load tested: 100 concurrent report requests < 2s p95

#### Technical Notes
- Use SQLAlchemy 2.0 async sessions for database queries
- OBD-II data comes from a dedicated adapter in the INF layer that connects to the vehicle telemetry database
- PDF generation uses WeasyPrint or ReportLab, triggered as a Celery task via WRK-SYNC
- Health score calculation is a pure domain function with no external dependencies -- unit testable in isolation
- Consider materialized views in PostgreSQL for pre-aggregated sensor data

#### Dependencies
- SVC-VEH (port 5012): Vehicle existence validation and basic vehicle data
- OBD-II telemetry data store (read access)
- GPS data store (read access)
- Redis 7 for caching
- S3 for PDF storage

---

### [MKT-BE-009][SVC-RPT-API] API de Valuacion de Mercado con IA

**Description**:
Build an AI-powered market valuation API within SVC-RPT that calculates the fair market price for any vehicle by analyzing 11,000+ comparable vehicles from the `scrapper_nacional` database across 18 data sources. The valuation integrates with the Depreciation Agent (port 5001) for 1-3 year depreciation projections and uses the Marketplace Analytics Agent for regional price adjustments. The system produces a confidence-scored valuation range (low/fair/high), a detailed comparables breakdown, and depreciation curves.

**Microservice**: SVC-RPT (port 5021)
**Layer**: API (routes) + APP (application services) + DOM (valuation domain logic) + INF (AI agent adapters, scrapper_nacional DB adapter)

#### Technical Context

**Endpoints**:

```
POST   /api/v1/valuations
       Body: {
         "vehicle_id": "uuid",        // existing vehicle OR
         "vehicle_spec": {             // manual spec for non-listed vehicles
           "brand": "Toyota", "model": "Corolla", "year": 2020,
           "trim": "LE", "mileage_km": 45000, "condition": "good",
           "state": "CDMX", "color": "white", "transmission": "automatic"
         },
         "include_depreciation": true,
         "depreciation_years": 3,
         "include_comparables": true
       }
       Response: 202 { "valuation_id": "uuid", "status": "processing", "estimated_seconds": 15 }

GET    /api/v1/valuations/{valuation_id}
       Response: 200 ValuationResponse | 202 StillProcessing | 404 NotFound

GET    /api/v1/valuations/{valuation_id}/comparables
       Query params: ?page=1&per_page=20&sort_by=similarity_score&order=desc
       Response: 200 PaginatedComparables

GET    /api/v1/valuations/{valuation_id}/depreciation
       Response: 200 DepreciationProjection

GET    /api/v1/valuations/vehicle/{vehicle_id}/latest
       Response: 200 ValuationResponse | 404 NoValuationFound

GET    /api/v1/valuations/market-position/{vehicle_id}
       Response: 200 { "percentile": 35, "position": "below_market", "savings_vs_avg": 12000 }
```

**Data Models**:

```python
# DOM Layer - domain/models/valuation.py
class Valuation:
    id: UUID
    vehicle_id: Optional[UUID]
    vehicle_spec: VehicleSpec
    valuation_date: datetime
    price_low: Decimal  # MXN
    price_fair: Decimal  # MXN
    price_high: Decimal  # MXN
    confidence_score: float  # 0.0 - 1.0
    comparable_count: int
    sources_used: List[str]
    methodology: str
    regional_adjustment: Decimal
    condition_adjustment: Decimal
    mileage_adjustment: Decimal
    depreciation_projection: Optional[DepreciationProjection]
    ai_agent_version: str
    processing_time_ms: int
    status: str  # pending, processing, completed, failed

class VehicleSpec:
    brand: str
    model: str
    year: int
    trim: Optional[str]
    mileage_km: int
    condition: str  # excellent, good, fair, poor
    state: str  # Mexican state
    city: Optional[str]
    color: Optional[str]
    transmission: str  # automatic, manual
    fuel_type: Optional[str]
    body_type: Optional[str]

class ComparableVehicle:
    source: str
    source_url: Optional[str]
    brand: str
    model: str
    year: int
    trim: str
    mileage_km: int
    price: Decimal
    state: str
    city: str
    listed_date: datetime
    similarity_score: float  # 0.0 - 1.0
    price_difference: Decimal
    adjustments_applied: List[PriceAdjustment]

class PriceAdjustment:
    factor: str  # mileage, condition, region, color, trim, age
    adjustment_amount: Decimal
    direction: str  # up, down
    explanation: str

class DepreciationProjection:
    current_value: Decimal
    projections: List[YearlyProjection]
    annual_depreciation_rate: float
    depreciation_curve_type: str  # linear, exponential, stepped
    factors: List[str]

class YearlyProjection:
    year: int
    projected_value: Decimal
    depreciation_amount: Decimal
    depreciation_percentage: float
    confidence: float
```

#### Acceptance Criteria

1. **AC-001**: POST `/api/v1/valuations` accepts either a `vehicle_id` (for listed vehicles) or a `vehicle_spec` object (for unlisted vehicles) and returns a 202 with a `valuation_id` for polling. Submitting both `vehicle_id` and `vehicle_spec` returns 400.
2. **AC-002**: The valuation result includes three price points in MXN: `price_low` (10th percentile), `price_fair` (median adjusted), and `price_high` (90th percentile), calculated from comparable vehicles in the `scrapper_nacional` database.
3. **AC-003**: The `confidence_score` (0.0 to 1.0) reflects the statistical reliability of the valuation. A score >= 0.8 requires at least 20 comparable vehicles; 0.5-0.79 requires at least 5; below 5 comparables the score is capped at 0.49 and a warning is included.
4. **AC-004**: Comparables are retrieved from the `scrapper_nacional` database and filtered by: same brand and model, year +/-3, mileage +/-30%, same country. Each comparable includes a `similarity_score` computed from year proximity, mileage proximity, trim match, regional proximity, and condition.
5. **AC-005**: Regional price adjustments are applied based on the Mexican state. Price variations between states (e.g., CDMX vs Chiapas) are computed from historical data in the 18 sources. The adjustment amount and explanation are included in the response.
6. **AC-006**: When `include_depreciation=true`, the API calls the Depreciation Agent on port 5001 via HTTP, passing the vehicle spec and receiving a depreciation curve. Communication timeout is 10 seconds with 2 retries. On failure, the valuation is returned without depreciation data and a `depreciation_status: "unavailable"` flag is set.
7. **AC-007**: Depreciation projections cover 1 to 3 years (configurable via `depreciation_years`) and include: projected value per year, annual depreciation amount, annual depreciation percentage, cumulative depreciation, and confidence per year.
8. **AC-008**: GET `/api/v1/valuations/{valuation_id}` returns 200 when the valuation is complete, 202 with `{ "status": "processing", "progress_percent": N }` when still running, and 404 when the valuation_id does not exist.
9. **AC-009**: GET `/api/v1/valuations/{valuation_id}/comparables` returns paginated comparable vehicles sorted by `similarity_score` descending by default. Each comparable includes the source name, listed price, similarity score, and itemized price adjustments applied to normalize comparison.
10. **AC-010**: GET `/api/v1/valuations/market-position/{vehicle_id}` returns the vehicle's price percentile among comparables, a human-readable position label (below_market/at_market/above_market), and the price difference versus the market average.
11. **AC-011**: Valuations are cached in Redis for 48 hours keyed by a hash of the vehicle spec. Identical requests within the TTL return the cached result immediately (200, not 202).
12. **AC-012**: Heavy valuation requests (those requiring Depreciation Agent + Analytics Agent calls) are queued via Celery/Redis and processed by WRK-FIN worker to avoid blocking the API process.
13. **AC-013**: The API logs the full valuation methodology: number of comparables considered, filters applied, adjustments made, AI agent versions used, and total processing time in milliseconds.

#### Definition of Done
- All endpoints implemented with proper status codes
- Integration with Depreciation Agent (port 5001) tested and resilient to failures
- Valuation algorithm produces consistent results across identical inputs
- Comparables pagination, sorting, and filtering working
- Redis caching with 48h TTL operational
- Unit tests for valuation domain logic (price calculation, adjustments, confidence scoring)
- Integration tests for full valuation flow including AI agent communication
- Performance: valuation completes in < 30 seconds for 95% of requests
- API documented in OpenAPI format

#### Technical Notes
- The Depreciation Agent runs on port 5001 and exposes a REST API. Use an adapter in the INF layer with circuit breaker pattern.
- Comparable vehicle search should use Elasticsearch 8 for fast filtering and aggregation across 11,000+ records.
- Consider pre-computing popular brand/model valuations nightly via WRK-SYNC to reduce real-time computation.
- Price adjustments are domain logic -- keep them in the DOM layer as pure functions for testability.
- The `scrapper_nacional` database is read-only from SVC-RPT's perspective; use a separate SQLAlchemy engine with read-only connection.

#### Dependencies
- `scrapper_nacional` database (read access to 11,000+ vehicles from 18 sources)
- Depreciation Agent (port 5001)
- Marketplace Analytics Agent
- SVC-VEH (port 5012): Vehicle data for listed vehicles
- Redis 7: Caching and Celery broker
- Elasticsearch 8: Comparable vehicle search
- WRK-FIN: Async valuation processing

---

### [MKT-BE-010][SVC-MKT-API] API de Analisis y Tendencias de Mercado

**Description**:
Build a market analysis and trends API within SVC-MKT (port 5019) that provides aggregated market intelligence derived from 18 data sources and 11,000+ vehicle listings. The API delivers brand/model price trends over time, a composite price index, demand analysis (listing velocity, days-on-market, price-to-sale ratio), source-by-source comparison, and geographic demand heat map data. This powers the frontend market analysis dashboard and feeds the Marketplace Analytics Agent.

**Microservice**: SVC-MKT (port 5019)
**Layer**: API (routes) + APP (application services) + DOM (analytics domain) + INF (Elasticsearch adapter, scrapper_nacional adapter)

#### Technical Context

**Endpoints**:

```
GET    /api/v1/market/trends
       Query params: ?brand=Toyota&model=Corolla&year_from=2018&year_to=2024
                     &state=CDMX&period=monthly&months=12
       Response: 200 MarketTrendsResponse

GET    /api/v1/market/price-index
       Query params: ?segment=sedan&period=monthly&months=24
       Response: 200 PriceIndexResponse

GET    /api/v1/market/demand
       Query params: ?brand=Toyota&model=&state=&period=monthly
       Response: 200 DemandAnalysisResponse

GET    /api/v1/market/sources/comparison
       Query params: ?brand=Toyota&model=Corolla&year=2020
       Response: 200 SourceComparisonResponse

GET    /api/v1/market/heatmap
       Query params: ?brand=&model=&year_from=&year_to=&metric=avg_price|listing_count|demand_score
       Response: 200 HeatmapResponse

GET    /api/v1/market/top-selling
       Query params: ?period=last_30_days&limit=20&state=
       Response: 200 TopSellingResponse

GET    /api/v1/market/summary
       Response: 200 MarketSummaryResponse (high-level KPIs for dashboard header)
```

**Data Models**:

```python
# DOM Layer - domain/models/market_analytics.py
class MarketTrend:
    brand: str
    model: str
    period: str  # monthly, weekly
    data_points: List[TrendDataPoint]
    avg_price_change_percent: float
    total_listings_analyzed: int
    date_range: DateRange

class TrendDataPoint:
    date: date
    avg_price: Decimal
    median_price: Decimal
    min_price: Decimal
    max_price: Decimal
    listing_count: int
    price_change_percent: float
    volume_change_percent: float

class PriceIndex:
    segment: str
    base_date: date
    base_value: float  # 100.0
    data_points: List[IndexDataPoint]

class IndexDataPoint:
    date: date
    index_value: float
    change_from_base: float
    change_from_previous: float

class DemandAnalysis:
    brand: str
    model: Optional[str]
    avg_days_on_market: float
    listing_velocity: float  # new listings per day
    price_to_sale_ratio: float
    demand_score: float  # 0-100
    supply_demand_indicator: str  # oversupply, balanced, undersupply
    trending_direction: str  # up, stable, down

class SourceComparison:
    brand: str
    model: str
    year: int
    sources: List[SourceStats]

class SourceStats:
    source_name: str
    listing_count: int
    avg_price: Decimal
    median_price: Decimal
    min_price: Decimal
    max_price: Decimal
    price_std_dev: Decimal
    freshness_score: float  # based on listing age
    data_quality_score: float

class HeatmapCell:
    state: str
    state_code: str
    latitude: float
    longitude: float
    metric_value: float
    listing_count: int
    rank: int

class TopSellingVehicle:
    brand: str
    model: str
    year_range: str
    avg_price: Decimal
    total_listings: int
    avg_days_on_market: float
    demand_score: float
    price_trend: str  # rising, stable, falling
    rank: int
```

#### Acceptance Criteria

1. **AC-001**: GET `/api/v1/market/trends` returns time-series price trend data for the specified brand/model combination with data points at the specified period granularity (weekly or monthly). Each data point includes average, median, min, max prices, listing count, and period-over-period change percentages.
2. **AC-002**: Trend data is filterable by brand, model, year range, state, and time period. Omitting optional filters returns aggregated data across all values for that dimension.
3. **AC-003**: GET `/api/v1/market/price-index` returns a composite price index (base = 100) for a vehicle segment (sedan, SUV, pickup, hatchback, luxury, commercial) over the specified period. The index is computed from the median price of all listings in that segment, normalized to the earliest data point.
4. **AC-004**: GET `/api/v1/market/demand` returns demand analysis metrics: average days on market, listing velocity (new listings per day), price-to-sale ratio, a computed demand score (0-100), supply/demand indicator (oversupply/balanced/undersupply), and trending direction.
5. **AC-005**: GET `/api/v1/market/sources/comparison` returns a side-by-side comparison of all 18 data sources for a specific brand/model/year, including listing count, price statistics (avg, median, min, max, std dev), data freshness score, and data quality score per source.
6. **AC-006**: GET `/api/v1/market/heatmap` returns geographic data for all 32 Mexican states with the requested metric (avg_price, listing_count, or demand_score). Each cell includes state name, state code, coordinates for map rendering, metric value, and rank.
7. **AC-007**: GET `/api/v1/market/top-selling` returns the top N (default 20, max 100) most in-demand brand/model combinations for the specified period, ranked by demand score. Includes average price, total listings, average days on market, and price trend direction.
8. **AC-008**: GET `/api/v1/market/summary` returns high-level KPIs: total active listings, total sources active, average market price, month-over-month price change, most searched brand, most searched model, and market health indicator.
9. **AC-009**: All aggregation queries execute against Elasticsearch 8 indices. Query response time is under 1 second for any single endpoint with standard filters. Results are cached in Redis with a 1-hour TTL.
10. **AC-010**: The `scrapper_nacional` data is synchronized to Elasticsearch via WRK-SYNC worker. The sync runs every 6 hours and the API response includes a `data_freshness` field with the last sync timestamp.
11. **AC-011**: Source comparison includes a `data_quality_score` per source computed from: listing completeness (has price, year, mileage, photos), data freshness (average listing age), and consistency (price outlier ratio).
12. **AC-012**: All endpoints support CORS and require valid JWT authentication. Rate limiting is applied: 100 requests per minute for authenticated users, 10 for unauthenticated (public summary only).
13. **AC-013**: Responses include a `metadata` object with `total_records_analyzed`, `data_freshness`, `cache_hit` boolean, and `query_time_ms`.

#### Definition of Done
- All 7 endpoints implemented and returning correct data
- Elasticsearch indices created and populated via WRK-SYNC
- Redis caching operational with 1-hour TTL
- Aggregation queries optimized (all < 1 second p95)
- Unit tests for demand score calculation, index computation, quality scoring
- Integration tests for all endpoints with realistic data
- API documented in OpenAPI format
- Data freshness monitoring in place

#### Technical Notes
- Use Elasticsearch aggregation framework (terms, date_histogram, percentiles, geo_bounds) for all analytics queries.
- Pre-compute daily/weekly/monthly aggregations via scheduled WRK-SYNC tasks to avoid expensive real-time aggregations.
- The heatmap endpoint returns data structured for integration with Leaflet or Mapbox on the frontend.
- Price index calculation uses the Laspeyres method with the first month as the base period.
- Consider using Elasticsearch transforms for materialized aggregations.

#### Dependencies
- `scrapper_nacional` database (18 sources, 11,000+ vehicles)
- Elasticsearch 8 (primary query engine for aggregations)
- Redis 7 (caching)
- WRK-SYNC (data synchronization and pre-aggregation)
- Marketplace Analytics Agent (optional enrichment)

---

### [MKT-FE-009][FE-FEAT-DET] Vista de Reporte Tecnico del Vehiculo

**Description**:
Build an Angular 18 standalone component that displays a comprehensive technical report for a vehicle. The view features a traffic-light health summary per vehicle system (7 systems), a scrollable list of active and historical DTC codes with severity badges, interactive sensor reading charts (line charts for time-series, gauge charts for current values), and a one-click PDF download button. The component uses signals-based state management and is styled with Tailwind CSS v4.

**Frontend Module**: FE-FEAT-DET (Vehicle Detail Feature)
**Framework**: Angular 18 (standalone components, signals)
**Styling**: Tailwind CSS v4

#### Technical Context

**Component Structure**:

```
src/app/features/vehicle-detail/
  components/
    technical-report/
      technical-report-page.component.ts      # Page-level smart component
      technical-report-page.component.html
      health-summary/
        health-summary.component.ts            # Traffic light grid for 7 systems
        health-summary.component.html
        system-health-card.component.ts        # Individual system card
      dtc-codes/
        dtc-codes-list.component.ts            # Filterable DTC list
        dtc-codes-list.component.html
        dtc-code-item.component.ts             # Single DTC row with severity badge
      sensor-charts/
        sensor-charts-panel.component.ts       # Chart container with selector
        sensor-line-chart.component.ts         # Time-series line chart
        sensor-gauge-chart.component.ts        # Current value gauge
      gps-summary/
        gps-summary.component.ts               # Usage pattern summary
      report-actions/
        report-actions.component.ts            # PDF download, share, refresh buttons
  services/
    technical-report.service.ts                # HTTP calls to SVC-RPT
  models/
    technical-report.model.ts                  # TypeScript interfaces
  store/
    technical-report.store.ts                  # Signal-based state
```

**Signal Store**:

```typescript
// technical-report.store.ts
export class TechnicalReportStore {
  // State signals
  report = signal<TechnicalReport | null>(null);
  loading = signal<boolean>(false);
  error = signal<string | null>(null);
  selectedSystem = signal<string | null>(null);
  selectedSensorId = signal<string | null>(null);
  pdfGenerating = signal<boolean>(false);

  // Computed signals
  overallHealth = computed(() => this.report()?.overall_health_score ?? 0);
  systemsSorted = computed(() =>
    (this.report()?.systems ?? []).sort((a, b) => a.health_score - b.health_score)
  );
  activeDtcCodes = computed(() =>
    (this.report()?.dtc_codes ?? []).filter(d => d.is_active)
  );
  criticalCount = computed(() =>
    this.activeDtcCodes().filter(d => d.severity === 'critical').length
  );
}
```

**Routes**:

```typescript
// Route: /vehicles/:vehicleId/technical-report
{
  path: 'vehicles/:vehicleId/technical-report',
  loadComponent: () => import('./features/vehicle-detail/components/technical-report/technical-report-page.component')
    .then(m => m.TechnicalReportPageComponent),
  canActivate: [authGuard]
}
```

#### Acceptance Criteria

1. **AC-001**: The technical report page loads and displays the overall health score as a large circular gauge (0-100) with color coding: green (70-100), yellow (40-69), red (0-39). The score animates from 0 to the actual value on page load.
2. **AC-002**: A grid of 7 system health cards is displayed, each showing: system name, health score, traffic light indicator (green/yellow/red circle), issue count, and last checked date. Cards are sorted by health score ascending (worst first).
3. **AC-003**: Clicking a system health card expands it to show detailed issues for that system, related DTC codes filtered to that system, and relevant sensor readings. Only one system card can be expanded at a time.
4. **AC-004**: The DTC codes section displays a filterable, sortable table with columns: code, description, severity (with colored badge), system, first seen, last seen, occurrences, status (active/historical). Default sort is by severity (critical first), then by last seen date descending.
5. **AC-005**: DTC codes are filterable by: severity (multi-select checkboxes), system (dropdown), status (active/historical toggle), and free-text search on code or description.
6. **AC-006**: The sensor charts panel shows a dropdown to select a sensor, and renders a time-series line chart (using Chart.js or ngx-charts) with the sensor's readings over time. The normal range is displayed as a shaded band on the chart. Readings outside the normal range are highlighted in red.
7. **AC-007**: Current sensor values are displayed as gauge charts showing the value relative to the normal range. Gauges use green/yellow/red segments corresponding to normal/warning/critical zones.
8. **AC-008**: A "Download PDF" button triggers PDF generation via the API. While generating, the button shows a spinner and "Generating..." text. On completion, the PDF auto-downloads. On failure, a toast notification with the error is shown.
9. **AC-009**: The GPS summary section displays: total distance driven, average daily distance, usage pattern (urban/highway/mixed with icon), harsh driving event counts, and max speed recorded. All values use appropriate units (km, km/h).
10. **AC-010**: The page shows a loading skeleton while the report is being fetched. If the report is still generating (202 response), a progress indicator with estimated time is shown, and the page polls every 3 seconds until the report is ready.
11. **AC-011**: The page is fully responsive: on mobile (< 768px), system cards stack vertically, charts resize to full width, and the DTC table becomes a card-based list. On desktop, the layout uses a 2-column grid.
12. **AC-012**: All component state is managed via Angular signals. No RxJS Subjects or BehaviorSubjects are used for local component state. HTTP calls use the HttpClient observable converted to signals via `toSignal()` or explicit signal updates in the service.
13. **AC-013**: The report page includes a "Refresh Report" button that calls the generate endpoint with `force_refresh=true` and reloads the data. A confirmation dialog is shown before refreshing.

#### Definition of Done
- All components implemented as Angular 18 standalone components
- Signal-based state management with no unnecessary RxJS subscriptions
- Tailwind CSS v4 styling with responsive breakpoints
- Chart library integrated (Chart.js or ngx-charts)
- PDF download flow working end-to-end
- Component unit tests for all smart components
- Visual regression tests for health cards and charts
- Accessible: ARIA labels, keyboard navigation, color-blind friendly indicators

#### Technical Notes
- Use Angular's new `@if`, `@for`, `@switch` template syntax (not `*ngIf`, `*ngFor`).
- Charts should lazy-load the chart library to reduce initial bundle size.
- PDF download should use `HttpClient` with `responseType: 'blob'` and create a download link dynamically.
- Consider using `@defer` blocks for the sensor charts section since it is below the fold.
- Tailwind CSS v4 classes should use the design system's color palette for traffic light colors.

#### Dependencies
- SVC-RPT API (MKT-BE-008): All technical report endpoints
- Chart library: Chart.js 4.x with ng2-charts or ngx-charts
- Angular CDK: Overlay for expansion panels, a11y utilities

---

### [MKT-FE-010][FE-FEAT-MKT] Dashboard de Analisis de Mercado

**Description**:
Build a full-featured market analysis dashboard as an Angular 18 standalone page featuring interactive charts (line charts for trends, bar charts for comparisons, pie charts for market share), a source comparison table, a geographic heat map of Mexico with demand/price overlays, and a top-selling vehicles leaderboard. The dashboard consumes all SVC-MKT endpoints and provides filtering controls for brand, model, year range, state, and time period.

**Frontend Module**: FE-FEAT-MKT (Market Feature)
**Framework**: Angular 18 (standalone components, signals)
**Styling**: Tailwind CSS v4

#### Technical Context

**Component Structure**:

```
src/app/features/market/
  components/
    market-dashboard/
      market-dashboard-page.component.ts       # Page-level smart component
      market-dashboard-page.component.html
      market-filters/
        market-filters.component.ts             # Global filter bar
      market-summary/
        market-summary-kpi.component.ts         # KPI cards row
      price-trends/
        price-trends-chart.component.ts         # Line chart with multi-series
      price-index/
        price-index-chart.component.ts          # Index line chart
      demand-analysis/
        demand-analysis-panel.component.ts      # Demand metrics cards
      source-comparison/
        source-comparison-table.component.ts    # Sortable table of 18 sources
      heatmap/
        mexico-heatmap.component.ts             # Interactive Mexico map
      top-selling/
        top-selling-list.component.ts           # Ranked list with mini charts
  services/
    market-analytics.service.ts
  models/
    market-analytics.model.ts
  store/
    market-dashboard.store.ts
```

**Signal Store**:

```typescript
// market-dashboard.store.ts
export class MarketDashboardStore {
  // Filter state
  filters = signal<MarketFilters>({
    brand: null, model: null, yearFrom: null, yearTo: null,
    state: null, period: 'monthly', months: 12, segment: null
  });

  // Data signals
  summary = signal<MarketSummary | null>(null);
  trends = signal<MarketTrend | null>(null);
  priceIndex = signal<PriceIndex | null>(null);
  demand = signal<DemandAnalysis | null>(null);
  sourceComparison = signal<SourceComparison | null>(null);
  heatmapData = signal<HeatmapCell[]>([]);
  topSelling = signal<TopSellingVehicle[]>([]);

  // Loading states
  summaryLoading = signal<boolean>(false);
  trendsLoading = signal<boolean>(false);
  // ... one loading signal per data source

  // Computed
  hasActiveFilters = computed(() => {
    const f = this.filters();
    return !!(f.brand || f.model || f.state || f.segment);
  });
}
```

#### Acceptance Criteria

1. **AC-001**: The dashboard page loads with a sticky filter bar at the top containing: brand dropdown (auto-complete), model dropdown (dependent on brand selection), year range (two number inputs or slider), state dropdown (32 Mexican states), period selector (weekly/monthly), and a "Clear Filters" button.
2. **AC-002**: Below the filter bar, a row of 6 KPI summary cards displays: total active listings, average market price (MXN formatted), month-over-month price change (with green up / red down arrow), most searched brand, most searched model, and market health indicator (bull/bear/neutral icon). Data comes from the `/market/summary` endpoint.
3. **AC-003**: The price trends section shows a multi-series line chart. When no model is selected, it shows the top 5 brands by listing count. When a brand is selected, it shows the top 5 models for that brand. Each series is a different color. Hovering shows a tooltip with the exact values. The X-axis is time, Y-axis is price in MXN.
4. **AC-004**: The price index section shows a line chart with the composite price index (base = 100) for the selected segment. A horizontal reference line at 100 marks the base. The chart includes a shaded confidence band. Index values above 100 indicate price appreciation, below 100 indicate depreciation.
5. **AC-005**: The demand analysis panel shows 4 metric cards: average days on market (with trend arrow), listing velocity (new/day), supply/demand indicator (with icon: oversupply=red, balanced=yellow, undersupply=green), and demand score (0-100 with gauge). Clicking any card shows a detailed breakdown modal.
6. **AC-006**: The source comparison section displays a sortable table with all 18 data sources as rows. Columns: source name, listing count, average price, median price, price range (min-max), data freshness (relative time), data quality score (with star rating). Clicking a column header sorts the table.
7. **AC-007**: The heatmap displays an interactive SVG map of Mexico with states colored by the selected metric (average price, listing count, or demand score). A metric toggle allows switching between the three views. Hovering a state shows a tooltip with the state name and exact metric value. Clicking a state sets the state filter for the entire dashboard.
8. **AC-008**: The top-selling section shows a ranked list of the top 20 brand/model combinations. Each row includes: rank number, brand logo (if available), brand/model name, year range, average price, total listings, demand score bar, and a mini sparkline chart showing the 30-day price trend. The list updates when dashboard filters change.
9. **AC-009**: When any filter changes, all dashboard sections that depend on that filter reload their data independently. Each section shows its own loading skeleton. Sections that do not depend on the changed filter (e.g., summary KPIs do not depend on brand filter for total listings) are not unnecessarily reloaded.
10. **AC-010**: All charts are interactive: line charts support zoom (drag to select range), bar charts support click-to-filter, and all charts support export as PNG via a small button in the chart's top-right corner.
11. **AC-011**: The dashboard is responsive. On mobile: KPI cards stack in 2 columns, charts take full width, the source table becomes horizontally scrollable, the heatmap is replaced with a sortable state list, and top-selling shows as cards instead of a table.
12. **AC-012**: Dashboard data is cached client-side. Navigating away and returning within 5 minutes does not trigger new API calls. A "Refresh Data" button forces a reload of all sections. Each section shows a `data_freshness` timestamp from the API response metadata.
13. **AC-013**: The filter state is synchronized with the URL query parameters using Angular Router. Sharing a URL with filters pre-populates the dashboard with those filters. Browser back/forward navigation updates the filters and data accordingly.
14. **AC-014**: Each chart includes an accessible data table alternative that can be toggled via a "View as Table" button, ensuring the dashboard meets WCAG 2.1 AA accessibility standards.

#### Definition of Done
- All dashboard sections implemented as standalone components
- Signal-based state with independent loading states per section
- Filter bar functional with URL synchronization
- Charts interactive (zoom, hover, export)
- Heatmap rendering with all 32 Mexican states
- Responsive layout tested on mobile, tablet, desktop
- Component unit tests for filter logic and data transformations
- E2E tests for filter-apply-reload flow
- Performance: initial dashboard load < 3 seconds, filter change < 1.5 seconds

#### Technical Notes
- Use `effect()` to watch filter signal changes and trigger API calls.
- The Mexico SVG map can use a TopoJSON/GeoJSON of Mexico states rendered with D3.js or a lightweight Angular wrapper.
- Consider using Angular CDK virtual scrolling for the source comparison table if data grows.
- Chart exports use the chart library's built-in `toBase64Image()` or `canvas.toBlob()`.
- URL synchronization: use `Router.navigate` with `queryParamsHandling: 'merge'` on filter changes.

#### Dependencies
- SVC-MKT API (MKT-BE-010): All market analytics endpoints
- Chart library: Chart.js 4.x with ng2-charts or ngx-charts
- Map library: D3.js for SVG heatmap or Leaflet for interactive map
- Angular CDK: a11y, overlay, scrolling

---

### [MKT-INT-002][SVC-RPT] Integracion con AI Agents

**Description**:
Build the integration layer within SVC-RPT (port 5021) that communicates with three AI agents: Depreciation Agent (port 5001), Marketplace Analytics Agent, and Report Builder Agent. The integration uses an adapter pattern in the INF layer, with each agent having its own adapter class implementing a common interface. Heavy valuation requests are dispatched to an async Celery queue (via Redis 7) and processed by workers. The integration includes circuit breaker, retry with exponential backoff, timeout management, and fallback strategies.

**Microservice**: SVC-RPT (port 5021)
**Layer**: INF (adapters) + APP (orchestration services) + CFG (agent configuration)

#### Technical Context

**Agent Adapters**:

```python
# INF Layer - infrastructure/adapters/ai_agent_adapter.py
from abc import ABC, abstractmethod

class AIAgentAdapter(ABC):
    @abstractmethod
    async def health_check(self) -> AgentHealthStatus: ...

    @abstractmethod
    async def invoke(self, request: AgentRequest) -> AgentResponse: ...

    @abstractmethod
    def get_agent_info(self) -> AgentInfo: ...

class DepreciationAgentAdapter(AIAgentAdapter):
    """Connects to Depreciation Agent on port 5001"""
    base_url: str = "http://localhost:5001"
    timeout_seconds: int = 10
    max_retries: int = 2
    circuit_breaker_threshold: int = 5
    circuit_breaker_timeout: int = 60

class MarketplaceAnalyticsAgentAdapter(AIAgentAdapter):
    """Connects to Marketplace Analytics Agent"""
    # Similar configuration

class ReportBuilderAgentAdapter(AIAgentAdapter):
    """Connects to Report Builder Agent for PDF/report generation"""
    # Similar configuration
```

**Celery Tasks**:

```python
# INF Layer - infrastructure/tasks/valuation_tasks.py
@celery_app.task(bind=True, max_retries=3, default_retry_delay=30)
def process_valuation(self, valuation_id: str, vehicle_spec: dict, options: dict):
    """
    Async task for heavy valuations that require multiple AI agent calls.
    Executed by WRK-FIN worker.
    """
    pass

@celery_app.task(bind=True, max_retries=2, default_retry_delay=10)
def generate_report_pdf(self, report_id: str, report_type: str):
    """
    Async task for PDF report generation via Report Builder Agent.
    Executed by WRK-SYNC worker.
    """
    pass
```

**Configuration**:

```python
# CFG Layer - config/agents.py
AI_AGENTS_CONFIG = {
    "depreciation": {
        "base_url": "http://localhost:5001",
        "timeout": 10,
        "retries": 2,
        "circuit_breaker": {"threshold": 5, "timeout": 60},
        "fallback": "cached_depreciation"
    },
    "marketplace_analytics": {
        "base_url": "http://localhost:5002",
        "timeout": 15,
        "retries": 2,
        "circuit_breaker": {"threshold": 5, "timeout": 60},
        "fallback": "statistical_fallback"
    },
    "report_builder": {
        "base_url": "http://localhost:5003",
        "timeout": 30,
        "retries": 1,
        "circuit_breaker": {"threshold": 3, "timeout": 120},
        "fallback": "basic_pdf_generation"
    }
}
```

#### Acceptance Criteria

1. **AC-001**: Each AI agent (Depreciation, Marketplace Analytics, Report Builder) has a dedicated adapter class in the INF layer that implements the `AIAgentAdapter` abstract base class with `health_check()`, `invoke()`, and `get_agent_info()` methods.
2. **AC-002**: The Depreciation Agent adapter calls `POST http://localhost:5001/api/v1/depreciation` with vehicle spec and returns a `DepreciationProjection` domain object. Connection timeout is 10 seconds, read timeout is 10 seconds. On timeout, it retries up to 2 times with exponential backoff (1s, 2s).
3. **AC-003**: A circuit breaker is implemented per agent. After 5 consecutive failures (configurable), the circuit opens and all subsequent calls immediately return the fallback result for 60 seconds (configurable). After the timeout, the circuit enters half-open state and allows one test request.
4. **AC-004**: When the Depreciation Agent circuit is open, the system falls back to a cached depreciation result (most recent successful result for the same brand/model/year) stored in Redis. If no cache exists, the valuation is returned with `depreciation_available: false` and an explanation.
5. **AC-005**: When the Marketplace Analytics Agent circuit is open, the system falls back to a statistical model that computes trends from raw `scrapper_nacional` data using simple moving averages. The response includes `source: "statistical_fallback"` to indicate reduced accuracy.
6. **AC-006**: When the Report Builder Agent circuit is open, the system falls back to basic PDF generation using a local template engine (WeasyPrint/ReportLab) without AI-enhanced formatting. The PDF includes a note that it was generated without AI enhancement.
7. **AC-007**: Heavy valuation requests (those requiring Depreciation + Analytics agents) are dispatched as Celery tasks to the `valuation_queue` and processed by WRK-FIN workers. The API returns 202 immediately with a task ID for polling.
8. **AC-008**: PDF generation requests are dispatched as Celery tasks to the `report_queue` and processed by WRK-SYNC workers. Task priority is configurable: user-initiated PDFs are high priority, batch/scheduled PDFs are low priority.
9. **AC-009**: Each agent call is logged with: agent name, request payload (sanitized), response status, response time in milliseconds, retry count, circuit breaker state, and whether a fallback was used. Logs are structured JSON for ingestion by monitoring tools.
10. **AC-010**: A health check endpoint `GET /api/v1/agents/health` returns the status of all three AI agents: each agent's `status` (healthy/degraded/down), `last_successful_call` timestamp, `circuit_breaker_state` (closed/open/half_open), `avg_response_time_ms`, and `success_rate_percent` (last 100 calls).
11. **AC-011**: Agent configuration (URLs, timeouts, retry counts, circuit breaker thresholds) is loaded from environment variables with defaults from the CFG layer. Changing configuration does not require a code deployment -- environment variable changes take effect on service restart.
12. **AC-012**: All agent communication uses `httpx.AsyncClient` with connection pooling. A shared client pool is created at service startup and reused across requests to avoid connection overhead.
13. **AC-013**: Celery tasks implement idempotency: re-submitting the same valuation request (same vehicle spec hash) within 1 hour does not create a duplicate task. The existing result or in-progress task ID is returned instead.
14. **AC-014**: Integration tests mock the AI agents using `respx` or `httpx.MockTransport` and verify: successful flow, timeout handling, retry behavior, circuit breaker transitions, fallback activation, and Celery task dispatch.

#### Definition of Done
- All three agent adapters implemented with the common interface
- Circuit breaker working with configurable thresholds
- Fallback strategies implemented and tested for all three agents
- Celery tasks for valuation and PDF generation dispatched and processed
- Health check endpoint reporting accurate agent status
- Structured logging for all agent interactions
- Unit tests for circuit breaker state transitions and fallback logic
- Integration tests with mocked agents for all scenarios
- Configuration externalized via environment variables
- Documentation of agent API contracts

#### Technical Notes
- Use `httpx` (not `requests`) for async HTTP communication with the AI agents.
- Circuit breaker can be implemented with `pybreaker` library or a custom implementation in the DOM layer.
- Celery tasks should use `task_id` derived from the request hash to enable idempotency checks via `AsyncResult`.
- Consider using `tenacity` library for retry with exponential backoff instead of hand-rolling retry logic.
- Agent health metrics should be stored in Redis with a sliding window (last 100 calls) for the health check endpoint.

#### Dependencies
- Depreciation Agent (port 5001): Must be running and accessible from SVC-RPT
- Marketplace Analytics Agent: Must be running and accessible
- Report Builder Agent: Must be running and accessible
- Redis 7: Celery broker, result backend, circuit breaker state, cached fallbacks
- WRK-FIN: Worker for valuation tasks
- WRK-SYNC: Worker for report generation tasks
- `httpx`: Async HTTP client
- `celery`: Task queue
- `pybreaker` or custom: Circuit breaker implementation
