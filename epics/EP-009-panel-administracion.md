# [MKT-EP-009] Panel de Administracion

**Sprint**: 3-8
**Priority**: Medium
**Epic Owner**: Tech Lead - SVC-ADM
**Stakeholders**: Product, Operations, Business Intelligence, Frontend Lead
**Estimated Effort**: 55 story points

---

## Epic Overview

This epic delivers a comprehensive administration panel for the Vehicle Marketplace. The panel provides real-time KPI dashboards, vehicle inventory management with bulk operations, user and role management with granular permissions, and partner (financiera + insurer) management with health monitoring. The admin panel is a critical internal tool enabling the operations team to manage the marketplace day-to-day.

### Business Goals
- Provide real-time visibility into marketplace performance (users, vehicles, revenue)
- Enable efficient inventory management with bulk upload capabilities
- Implement role-based access control for the operations team
- Monitor partner (financiera/insurer) integration health and performance
- Reduce manual operations through automation and self-service tools

### Architecture Context
- **Primary Service**: SVC-ADM (:5020)
- **Supporting Services**: SVC-USR (:5011), SVC-VEH (:5012), SVC-FIN (:5015), SVC-INS (:5016), SVC-RPT (:5021)
- **Database**: PostgreSQL 15 for admin data, roles, permissions
- **Cache**: Redis 7 for dashboard KPI caching
- **Search**: Elasticsearch 8 for vehicle/user search in admin panels
- **Storage**: S3 for bulk upload files and vehicle images

---

## User Stories

---

### US-1: [MKT-BE-024][SVC-ADM-API] Dashboard Administrativo - KPIs

**Description**:
Implement the administrative dashboard KPI API that provides aggregated metrics for the marketplace. The API returns registered user counts, active vehicle inventory, transaction volumes, revenue figures, and supports period filters (today, week, month, quarter, year, custom range) with comparison to the previous equivalent period. KPIs are cached in Redis for performance and refreshed on a configurable interval.

**Microservice**: SVC-ADM (:5020)
**Layer**: API + APP + INF
**Supporting**: SVC-RPT (:5021) for heavy aggregations

#### Technical Context

**Endpoint**:
```
GET /api/v1/admin/dashboard/kpis
Authorization: Bearer <jwt> (required, role: admin or viewer)
Query Parameters:
  - period: today|week|month|quarter|year|custom (default: month)
  - start_date: ISO date (required if period=custom)
  - end_date: ISO date (required if period=custom)
  - compare: true|false (default: true)
```

**Response Schema**:
```json
{
  "period": {
    "label": "Marzo 2026",
    "start": "2026-03-01",
    "end": "2026-03-31"
  },
  "kpis": {
    "registered_users": {
      "value": 15234,
      "previous_value": 12890,
      "change_percentage": 18.2,
      "trend": "up"
    },
    "active_vehicles": {
      "value": 11247,
      "previous_value": 10890,
      "change_percentage": 3.3,
      "trend": "up"
    },
    "new_vehicles_listed": {
      "value": 892,
      "previous_value": 756,
      "change_percentage": 18.0,
      "trend": "up"
    },
    "total_transactions": {
      "value": 234,
      "previous_value": 198,
      "change_percentage": 18.2,
      "trend": "up"
    },
    "total_revenue": {
      "value": 4567890.50,
      "currency": "MXN",
      "previous_value": 3890456.00,
      "change_percentage": 17.4,
      "trend": "up"
    },
    "financing_applications": {
      "value": 456,
      "previous_value": 389,
      "change_percentage": 17.2,
      "trend": "up"
    },
    "financing_approval_rate": {
      "value": 62.5,
      "unit": "percent",
      "previous_value": 58.3,
      "change_percentage": 7.2,
      "trend": "up"
    },
    "insurance_policies_issued": {
      "value": 178,
      "previous_value": 145,
      "change_percentage": 22.8,
      "trend": "up"
    },
    "avg_time_to_sale_days": {
      "value": 23.5,
      "previous_value": 28.1,
      "change_percentage": -16.4,
      "trend": "down"
    },
    "active_conversations": {
      "value": 1234,
      "previous_value": 1089,
      "change_percentage": 13.3,
      "trend": "up"
    }
  },
  "charts": {
    "revenue_by_day": [
      {"date": "2026-03-01", "value": 145000.00},
      {"date": "2026-03-02", "value": 178000.00}
    ],
    "users_by_day": [
      {"date": "2026-03-01", "value": 45},
      {"date": "2026-03-02", "value": 52}
    ],
    "vehicles_by_source": [
      {"source": "API Import", "count": 5400},
      {"source": "Manual Upload", "count": 3200},
      {"source": "Dealer Portal", "count": 2647}
    ],
    "transactions_by_type": [
      {"type": "vehicle_sale", "count": 156},
      {"type": "financing", "count": 45},
      {"type": "insurance", "count": 33}
    ]
  },
  "recent_activity": [
    {
      "type": "vehicle_listed",
      "description": "Toyota Camry 2024 listed by Dealer AutoMax",
      "timestamp": "2026-03-23T09:45:00Z",
      "actor": "dealer_001"
    },
    {
      "type": "transaction_completed",
      "description": "Vehicle sold: Honda CR-V 2023 - $385,000 MXN",
      "timestamp": "2026-03-23T09:30:00Z",
      "actor": "system"
    }
  ],
  "system_alerts": [
    {
      "severity": "warning",
      "message": "SVC-FIN: Banco Nacional circuit breaker OPEN",
      "timestamp": "2026-03-23T09:15:00Z",
      "source": "svc-fin"
    }
  ],
  "cached": true,
  "cache_ttl_seconds": 300,
  "generated_at": "2026-03-23T10:00:00Z"
}
```

**Data Model**:
```
DashboardSnapshot (INF)
  - snapshot_id: UUID (PK)
  - period_type: Enum(TODAY, WEEK, MONTH, QUARTER, YEAR, CUSTOM)
  - period_start: Date
  - period_end: Date
  - kpis_data: JSONB
  - charts_data: JSONB
  - generated_at: DateTime
  - generation_duration_ms: Integer

SystemAlert (DOM)
  - alert_id: UUID (PK)
  - severity: Enum(INFO, WARNING, ERROR, CRITICAL)
  - message: Text
  - source_service: String(20)
  - is_acknowledged: Boolean default false
  - acknowledged_by: UUID (FK, nullable)
  - acknowledged_at: DateTime nullable
  - created_at: DateTime
  - expires_at: DateTime

ActivityLog (DOM)
  - log_id: UUID (PK)
  - activity_type: String(50)
  - description: Text
  - actor_id: UUID (FK)
  - actor_type: Enum(USER, DEALER, ADMIN, SYSTEM)
  - entity_type: String(30)
  - entity_id: UUID
  - metadata: JSONB
  - created_at: DateTime
```

**Component Structure**:
```
svc-adm/
  domain/
    models/system_alert.py
    models/activity_log.py
    services/kpi_aggregation_service.py
    services/alert_service.py
  application/
    use_cases/get_dashboard_kpis_use_case.py
    use_cases/acknowledge_alert_use_case.py
    dto/dashboard_kpi_response.py
    dto/period_filter.py
  infrastructure/
    repositories/snapshot_repository.py
    repositories/alert_repository.py
    repositories/activity_log_repository.py
    aggregators/
      user_metrics_aggregator.py
      vehicle_metrics_aggregator.py
      transaction_metrics_aggregator.py
      financing_metrics_aggregator.py
      insurance_metrics_aggregator.py
    cache/
      dashboard_cache.py
    clients/
      report_service_client.py
      user_service_client.py
      vehicle_service_client.py
  api/
    routes/dashboard_routes.py
    schemas/dashboard_schema.py
    middleware/admin_auth_middleware.py
  config/
    dashboard_config.py
```

#### Acceptance Criteria

1. **AC-01**: GET /api/v1/admin/dashboard/kpis requires valid JWT with role "admin" or "viewer"; unauthorized users receive 403; unauthenticated users receive 401.
2. **AC-02**: The period parameter supports: today, week (Mon-Sun), month (1st-last), quarter (Q1-Q4), year (Jan-Dec), custom (start_date + end_date required); invalid period values return 422.
3. **AC-03**: When compare=true, each KPI includes previous_value (same duration, immediately preceding period), change_percentage (calculated as ((current - previous) / previous) * 100), and trend (up/down/stable where stable = change < 1%).
4. **AC-04**: KPIs include: registered_users (total from SVC-USR), active_vehicles (published status from SVC-VEH), new_vehicles_listed (created in period), total_transactions (completed in period), total_revenue (sum of transaction amounts), financing_applications (submitted in period), financing_approval_rate (approved/total * 100), insurance_policies_issued (in period), avg_time_to_sale_days, active_conversations (from SVC-CHT).
5. **AC-05**: Charts data includes: revenue_by_day (daily revenue for the period), users_by_day (new registrations per day), vehicles_by_source (grouped by import source), transactions_by_type (grouped by sale/financing/insurance).
6. **AC-06**: Recent activity returns the 20 most recent significant events across all services: vehicle listings, transactions, user registrations, partner status changes; each entry includes type, description, timestamp, and actor.
7. **AC-07**: System alerts are collected from all microservices: circuit breaker state changes, high error rates, service health degradations, expiring certificates; alerts include severity (info/warning/error/critical), message, source, and timestamp.
8. **AC-08**: KPI responses are cached in Redis with key `adm:dashboard:{period}:{start}:{end}` and TTL 300 seconds (5 minutes); the response indicates cached=true and remaining TTL; force-refresh is available via header `Cache-Control: no-cache`.
9. **AC-09**: For custom date ranges, the maximum range is 365 days; ranges exceeding this return 422 with message "Maximum date range is 365 days".
10. **AC-10**: Heavy aggregations (revenue, transaction counts) are delegated to SVC-RPT which uses read replicas; SVC-ADM orchestrates calls to SVC-RPT, SVC-USR, SVC-VEH in parallel and assembles the response.
11. **AC-11**: Dashboard generation for a month period completes in < 3 seconds (uncached) and < 200ms (cached); generation_duration_ms is included in the response for monitoring.
12. **AC-12**: A snapshot of KPIs is persisted daily (midnight UTC) in DashboardSnapshot for historical trend analysis; snapshots are retained for 2 years.

#### Definition of Done
- Endpoint implemented with Redis caching
- Parallel service aggregation with timeout handling
- Period calculation with comparison logic tested
- Unit tests >= 95% coverage on aggregation logic
- Integration tests with mock service clients
- Performance test: < 3s uncached response
- Code reviewed and merged to develop

#### Technical Notes
- Use `asyncio.gather` for parallel calls to SVC-USR, SVC-VEH, SVC-RPT, SVC-FIN, SVC-INS
- Dashboard cache invalidation: on significant events (new transaction, batch import) publish to Redis channel `adm:cache:invalidate`
- Consider materialized views in PostgreSQL for frequently aggregated metrics
- System alerts should be collected via a dedicated Redis pub/sub channel that all services publish to

#### Dependencies
- SVC-USR for user metrics
- SVC-VEH for vehicle metrics
- SVC-RPT for transaction and revenue aggregations
- SVC-FIN for financing metrics
- SVC-INS for insurance metrics
- SVC-CHT for conversation metrics
- Redis 7 for caching

---

### US-2: [MKT-BE-025][SVC-ADM-API] Gestion de Inventario

**Description**:
Implement vehicle inventory management API endpoints for the admin panel. This includes full CRUD operations on vehicles, bulk CSV/Excel upload for batch vehicle imports, image management (upload, reorder, set primary), publish/unpublish controls, and pricing management including promotional offers. The API supports the 11,000+ vehicle inventory from 18 sources and integrates with Elasticsearch for fast search and filtering.

**Microservice**: SVC-ADM (:5020) + SVC-VEH (:5012)
**Layer**: API + APP + INF

#### Technical Context

**Endpoints**:
```
GET    /api/v1/admin/vehicles                    # List with search/filter/pagination
GET    /api/v1/admin/vehicles/{id}               # Get vehicle detail
POST   /api/v1/admin/vehicles                    # Create vehicle
PUT    /api/v1/admin/vehicles/{id}               # Update vehicle
DELETE /api/v1/admin/vehicles/{id}               # Soft delete vehicle
PATCH  /api/v1/admin/vehicles/{id}/status        # Publish/unpublish
PATCH  /api/v1/admin/vehicles/{id}/pricing       # Update price/offers
POST   /api/v1/admin/vehicles/{id}/images        # Upload images
PUT    /api/v1/admin/vehicles/{id}/images/reorder # Reorder images
DELETE /api/v1/admin/vehicles/{id}/images/{imgId} # Delete image
POST   /api/v1/admin/vehicles/bulk-upload         # CSV/Excel upload
GET    /api/v1/admin/vehicles/bulk-upload/{jobId}  # Check upload status
POST   /api/v1/admin/vehicles/bulk-action         # Bulk publish/unpublish/delete
```

**List Endpoint Query Parameters**:
```
GET /api/v1/admin/vehicles?
  search=toyota camry&
  status=published,draft&
  brand=Toyota&
  year_min=2020&year_max=2025&
  price_min=200000&price_max=500000&
  source=api_import,manual&
  sort=created_at:desc&
  page=1&
  per_page=25
```

**List Response Schema**:
```json
{
  "data": [
    {
      "vehicle_id": "veh_abc123",
      "title": "Toyota Camry 2024 SE",
      "brand": "Toyota",
      "model": "Camry",
      "year": 2024,
      "version": "SE",
      "price": 450000.00,
      "original_price": 480000.00,
      "has_offer": true,
      "offer_percentage": 6.25,
      "status": "published",
      "source": "api_import",
      "images_count": 8,
      "primary_image_url": "https://cdn.example.com/vehicles/veh_abc123/1.jpg",
      "views_count": 234,
      "inquiries_count": 12,
      "days_listed": 15,
      "created_at": "2026-03-08T10:00:00Z",
      "updated_at": "2026-03-23T09:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total": 11247,
    "total_pages": 450
  },
  "filters_applied": {
    "search": "toyota camry",
    "status": ["published", "draft"]
  }
}
```

**Bulk Upload Request**:
```
POST /api/v1/admin/vehicles/bulk-upload
Content-Type: multipart/form-data

file: vehicles.csv (or .xlsx)
source: "manual_upload"
publish_immediately: false
```

**Bulk Upload Response**:
```json
{
  "job_id": "job_abc123",
  "status": "processing",
  "file_name": "vehicles.csv",
  "total_rows": 250,
  "check_status_url": "/api/v1/admin/vehicles/bulk-upload/job_abc123"
}
```

**Bulk Upload Status**:
```json
{
  "job_id": "job_abc123",
  "status": "completed",
  "total_rows": 250,
  "processed": 250,
  "success": 237,
  "errors": 13,
  "error_details": [
    {
      "row": 15,
      "field": "year",
      "error": "Invalid year: 2030",
      "original_value": "2030"
    }
  ],
  "created_vehicles": 237,
  "started_at": "2026-03-23T10:00:00Z",
  "completed_at": "2026-03-23T10:02:30Z"
}
```

**Data Model**:
```
BulkUploadJob (DOM)
  - job_id: UUID (PK)
  - admin_user_id: UUID (FK)
  - file_name: String(255)
  - file_s3_key: String(255)
  - file_format: Enum(CSV, XLSX)
  - source_label: String(50)
  - publish_immediately: Boolean
  - status: Enum(PENDING, PROCESSING, COMPLETED, FAILED)
  - total_rows: Integer
  - processed_rows: Integer
  - success_count: Integer
  - error_count: Integer
  - error_details: JSONB
  - started_at: DateTime
  - completed_at: DateTime
  - created_at: DateTime

VehicleImage (DOM - in SVC-VEH)
  - image_id: UUID (PK)
  - vehicle_id: UUID (FK)
  - s3_key: String(255)
  - cdn_url: String(255)
  - sort_order: Integer
  - is_primary: Boolean default false
  - width: Integer
  - height: Integer
  - file_size_bytes: Integer
  - content_type: String(50)
  - uploaded_by: UUID (FK)
  - created_at: DateTime

VehiclePricing (DOM - in SVC-VEH)
  - pricing_id: UUID (PK)
  - vehicle_id: UUID (FK)
  - original_price: Decimal(14,2)
  - current_price: Decimal(14,2)
  - offer_percentage: Decimal(5,2) nullable
  - offer_start_date: Date nullable
  - offer_end_date: Date nullable
  - price_history: JSONB
  - updated_by: UUID (FK)
  - updated_at: DateTime
```

**Component Structure**:
```
svc-adm/
  domain/
    models/bulk_upload_job.py
    services/inventory_management_service.py
    services/bulk_upload_service.py
    services/image_management_service.py
    services/pricing_service.py
  application/
    use_cases/list_vehicles_use_case.py
    use_cases/create_vehicle_use_case.py
    use_cases/update_vehicle_use_case.py
    use_cases/bulk_upload_use_case.py
    use_cases/manage_images_use_case.py
    use_cases/update_pricing_use_case.py
    use_cases/bulk_action_use_case.py
    dto/vehicle_admin_dto.py
    dto/bulk_upload_dto.py
    validators/vehicle_validator.py
    validators/csv_validator.py
  infrastructure/
    repositories/bulk_upload_repository.py
    clients/vehicle_service_client.py
    search/elasticsearch_vehicle_search.py
    storage/s3_image_storage.py
    parsers/csv_parser.py
    parsers/excel_parser.py
  api/
    routes/inventory_routes.py
    routes/image_routes.py
    routes/bulk_upload_routes.py
    schemas/vehicle_admin_schema.py
    schemas/bulk_upload_schema.py
```

#### Acceptance Criteria

1. **AC-01**: GET /api/v1/admin/vehicles supports full-text search via Elasticsearch (search param queries brand, model, version, VIN); results are paginated with page + per_page (default 25, max 100).
2. **AC-02**: Filters: status (published/draft/archived, multi-select), brand (exact match), year_min/year_max (range), price_min/price_max (range), source (multi-select from 18 known sources); multiple filters combine with AND logic.
3. **AC-03**: Sort options: created_at, updated_at, price, year, views_count, days_listed; direction: asc or desc; default sort is created_at:desc.
4. **AC-04**: POST /api/v1/admin/vehicles creates a new vehicle via SVC-VEH; required fields: brand, model, year, version, price; optional: VIN, description, mileage, transmission, fuel_type, color, features; returns 201 with the created vehicle.
5. **AC-05**: PUT /api/v1/admin/vehicles/{id} updates any vehicle field; validation rules: price > 0, year within last 30 years, mileage >= 0; partial updates via PATCH semantics (only sent fields are updated); returns 200.
6. **AC-06**: PATCH /api/v1/admin/vehicles/{id}/status accepts {status: "published"|"draft"|"archived"}; publishing validates that the vehicle has at least 1 image and all required fields; if validation fails, return 422 with missing requirements.
7. **AC-07**: PATCH /api/v1/admin/vehicles/{id}/pricing accepts {current_price, offer_percentage, offer_start_date, offer_end_date}; when offer_percentage is set, current_price = original_price * (1 - offer_percentage/100); price_history is appended with old price and timestamp.
8. **AC-08**: POST /api/v1/admin/vehicles/{id}/images accepts multipart/form-data with up to 20 images; each image is validated (JPEG/PNG/WebP, max 10MB, min 800x600px); images are resized to standard sizes (thumb 200x150, medium 800x600, large 1600x1200) and uploaded to S3 via CDN.
9. **AC-09**: PUT /api/v1/admin/vehicles/{id}/images/reorder accepts {image_ids: [ordered array]}; updates sort_order for each image; the first image in the array becomes is_primary=true.
10. **AC-10**: POST /api/v1/admin/vehicles/bulk-upload accepts CSV or XLSX file (max 50MB, max 5000 rows); the file is uploaded to S3 and processing starts asynchronously; response returns job_id immediately with 202 Accepted.
11. **AC-11**: Bulk upload processing validates each row against vehicle schema; valid rows create vehicles via SVC-VEH; invalid rows are collected in error_details with row number, field, error message, and original value; processing status is updated in real-time and queryable via GET /bulk-upload/{jobId}.
12. **AC-12**: POST /api/v1/admin/vehicles/bulk-action accepts {action: "publish"|"unpublish"|"archive"|"delete", vehicle_ids: [...]}; max 500 vehicles per action; actions are processed in parallel; response includes success_count and error_count with details.
13. **AC-13**: All inventory operations are logged in ActivityLog with admin user_id, action type, vehicle_id, and before/after state for audit trail.

#### Definition of Done
- All CRUD endpoints implemented with validation
- Elasticsearch integration for search and filtering
- Bulk upload with CSV/XLSX parsing and async processing
- Image upload with resizing and S3 storage
- Unit tests >= 95% coverage
- Integration tests with Elasticsearch and S3 (localstack)
- Performance test: list endpoint < 500ms for 11,000 vehicles with filters
- Code reviewed and merged to develop

#### Technical Notes
- Use `openpyxl` for XLSX parsing and `csv` stdlib for CSV
- Image resizing via `Pillow` in a background worker to avoid blocking the API
- Elasticsearch index should be kept in sync with PostgreSQL via change data capture or explicit sync
- Bulk upload should use database batch insert (SQLAlchemy `bulk_save_objects`) for performance
- Consider S3 multipart upload for large files

#### Dependencies
- SVC-VEH for vehicle CRUD operations
- Elasticsearch 8 for search
- AWS S3 for images and bulk upload files
- Redis for bulk upload job status updates

---

### US-3: [MKT-BE-026][SVC-ADM-API] Gestion de Usuarios y Roles

**Description**:
Implement user and role management API for the admin panel. This includes CRUD operations on users with role assignment (admin, editor, viewer, dealer), granular permission management, audit logging of all administrative actions, and ability to suspend/activate user accounts. The system integrates with AWS Cognito for authentication and manages role-based authorization internally.

**Microservice**: SVC-ADM (:5020) + SVC-USR (:5011)
**Layer**: API + APP + DOM + INF

#### Technical Context

**Endpoints**:
```
GET    /api/v1/admin/users                      # List users with search/filter
GET    /api/v1/admin/users/{id}                 # Get user detail
POST   /api/v1/admin/users                      # Create admin/dealer user
PUT    /api/v1/admin/users/{id}                 # Update user
PATCH  /api/v1/admin/users/{id}/status          # Suspend/activate
PATCH  /api/v1/admin/users/{id}/role            # Change role
GET    /api/v1/admin/roles                      # List available roles
GET    /api/v1/admin/roles/{role}/permissions   # Get role permissions
PUT    /api/v1/admin/roles/{role}/permissions   # Update role permissions
GET    /api/v1/admin/audit-log                  # Query audit log
```

**User List Response**:
```json
{
  "data": [
    {
      "user_id": "usr_abc123",
      "email": "admin@marketplace.com",
      "full_name": "Carlos Rodriguez",
      "role": "admin",
      "status": "active",
      "last_login_at": "2026-03-23T08:00:00Z",
      "created_at": "2025-01-15T10:00:00Z",
      "vehicles_count": 0,
      "transactions_count": 0
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total": 1234
  }
}
```

**Role Permissions Response**:
```json
{
  "role": "editor",
  "description": "Can manage vehicles and view reports",
  "permissions": [
    {
      "resource": "vehicles",
      "actions": ["create", "read", "update"],
      "restrictions": {
        "delete": false,
        "bulk_delete": false,
        "publish": true
      }
    },
    {
      "resource": "users",
      "actions": ["read"],
      "restrictions": {
        "create": false,
        "update_role": false,
        "suspend": false
      }
    },
    {
      "resource": "dashboard",
      "actions": ["read"],
      "restrictions": {}
    },
    {
      "resource": "partners",
      "actions": ["read"],
      "restrictions": {
        "create": false,
        "update_credentials": false
      }
    },
    {
      "resource": "reports",
      "actions": ["read"],
      "restrictions": {
        "export": true,
        "delete": false
      }
    }
  ]
}
```

**Audit Log Response**:
```json
{
  "data": [
    {
      "log_id": "aud_001",
      "timestamp": "2026-03-23T09:45:00Z",
      "actor_id": "usr_admin01",
      "actor_name": "Carlos Rodriguez",
      "actor_role": "admin",
      "action": "user.role_changed",
      "resource_type": "user",
      "resource_id": "usr_abc123",
      "details": {
        "field": "role",
        "old_value": "viewer",
        "new_value": "editor",
        "reason": "Promoted to content manager"
      },
      "ip_address": "192.168.1.100",
      "user_agent": "Mozilla/5.0..."
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 50,
    "total": 5678
  }
}
```

**Data Model**:
```
AdminRole (DOM)
  - role_id: UUID (PK)
  - name: String(20) UNIQUE (admin, editor, viewer, dealer)
  - description: String(200)
  - is_system_role: Boolean default true
  - created_at: DateTime
  - updated_at: DateTime

RolePermission (DOM)
  - permission_id: UUID (PK)
  - role_id: UUID (FK)
  - resource: String(50)
  - action: String(20)
  - is_allowed: Boolean default true
  - restrictions: JSONB
  - created_at: DateTime

UserRole (DOM - in SVC-USR)
  - user_role_id: UUID (PK)
  - user_id: UUID (FK)
  - role_id: UUID (FK)
  - assigned_by: UUID (FK)
  - assigned_at: DateTime
  - is_active: Boolean default true

AuditLog (DOM)
  - log_id: UUID (PK)
  - actor_id: UUID (FK)
  - action: String(100)
  - resource_type: String(50)
  - resource_id: UUID
  - details: JSONB
  - ip_address: String(45)
  - user_agent: String(500)
  - created_at: DateTime (indexed, partitioned monthly)
```

**Component Structure**:
```
svc-adm/
  domain/
    models/admin_role.py
    models/role_permission.py
    models/audit_log.py
    services/role_service.py
    services/permission_service.py
    services/audit_service.py
  application/
    use_cases/list_users_use_case.py
    use_cases/create_admin_user_use_case.py
    use_cases/update_user_role_use_case.py
    use_cases/suspend_user_use_case.py
    use_cases/get_audit_log_use_case.py
    dto/user_admin_dto.py
    dto/role_dto.py
    validators/user_admin_validator.py
  infrastructure/
    repositories/role_repository.py
    repositories/permission_repository.py
    repositories/audit_log_repository.py
    clients/user_service_client.py
    clients/cognito_client.py
    middleware/permission_middleware.py
  api/
    routes/user_management_routes.py
    routes/role_routes.py
    routes/audit_log_routes.py
    schemas/user_management_schema.py
    decorators/require_permission.py
```

#### Acceptance Criteria

1. **AC-01**: GET /api/v1/admin/users requires JWT with role "admin"; editors and viewers receive 403 for this endpoint; supports search (by name, email), filter by role, filter by status (active/suspended), pagination.
2. **AC-02**: POST /api/v1/admin/users creates a new admin/dealer user: creates Cognito account, sets temporary password, assigns role internally, sends welcome email via SVC-NTF; required fields: email (unique), full_name, role; returns 201.
3. **AC-03**: PATCH /api/v1/admin/users/{id}/role changes user role; only "admin" role can change roles; changing to "admin" requires super_admin flag; the role change is recorded in AuditLog with old_value and new_value.
4. **AC-04**: PATCH /api/v1/admin/users/{id}/status accepts {status: "active"|"suspended", reason: "string"}; suspending a user disables their Cognito account (preventing login) and records the reason; reactivating re-enables the Cognito account.
5. **AC-05**: An admin cannot suspend or change their own role (self-modification protection); attempting returns 422 with message "Cannot modify your own account".
6. **AC-06**: Four predefined roles exist: (a) admin - full access to all resources, (b) editor - CRUD on vehicles, read on users/reports/partners, (c) viewer - read-only on all resources, (d) dealer - CRUD on own vehicles only, read on own transactions.
7. **AC-07**: PUT /api/v1/admin/roles/{role}/permissions allows admin to customize permissions for non-system roles; each permission is a (resource, action, is_allowed) tuple; system roles (admin) cannot be modified.
8. **AC-08**: All admin actions are logged in AuditLog with: actor_id, action (e.g., "user.created", "vehicle.published", "role.permission_changed"), resource_type, resource_id, details (JSONB with before/after values), ip_address, user_agent.
9. **AC-09**: GET /api/v1/admin/audit-log supports filters: actor_id, action (prefix match, e.g., "user.*"), resource_type, date range (start_date, end_date); sorted by timestamp descending; paginated.
10. **AC-10**: The permission middleware (`@require_permission(resource, action)`) decorator checks the authenticated user's role permissions before executing any endpoint; unauthorized access returns 403 with message "Insufficient permissions: {resource}.{action} required".
11. **AC-11**: Audit log entries are immutable; there is no update or delete endpoint for audit logs; the table is partitioned by month for query performance.
12. **AC-12**: User deletion is soft-delete only (status = "deleted"); the user's Cognito account is disabled but not deleted; all associated data is retained for audit purposes; hard deletion requires a separate compliance process.

#### Definition of Done
- All user management endpoints implemented
- Role and permission system with middleware decorator
- Cognito integration for account management
- Comprehensive audit logging
- Unit tests >= 95% coverage
- Integration tests with Cognito (localstack or moto)
- Permission middleware tested for all role combinations
- Code reviewed and merged to develop

#### Technical Notes
- Use PostgreSQL table partitioning (by month) for AuditLog for query performance
- Permission checks should be cached in Redis (TTL 5 min) to avoid database lookups on every request
- Cognito user pool operations use boto3 `cognito-idp` client
- Consider implementing ABAC (Attribute-Based Access Control) for dealer-specific resource restrictions
- Audit log should use a separate database connection pool to avoid impacting main operations

#### Dependencies
- AWS Cognito for user account management
- SVC-USR for user profile data
- SVC-NTF for welcome emails and notifications
- Redis for permission caching

---

### US-4: [MKT-BE-027][SVC-ADM-API] Gestion de Partners - Financieras y Aseguradoras

**Description**:
Implement partner management API for financial institutions (financieras) and insurance providers (aseguradoras). The admin can perform CRUD operations on partners, configure API endpoints and credentials, toggle active/inactive status, and view performance metrics per partner. This is the admin-facing management layer for the institutions configured in EP-007 and EP-008.

**Microservice**: SVC-ADM (:5020)
**Layer**: API + APP + INF
**Supporting**: SVC-FIN (:5015), SVC-INS (:5016)

#### Technical Context

**Endpoints**:
```
GET    /api/v1/admin/partners                       # List all partners
GET    /api/v1/admin/partners/{id}                  # Get partner detail
POST   /api/v1/admin/partners                       # Create partner
PUT    /api/v1/admin/partners/{id}                  # Update partner
PATCH  /api/v1/admin/partners/{id}/status           # Toggle active/inactive
PUT    /api/v1/admin/partners/{id}/credentials      # Update API credentials
GET    /api/v1/admin/partners/{id}/metrics          # Get performance metrics
GET    /api/v1/admin/partners/{id}/logs             # Get integration logs
GET    /api/v1/admin/partners/health                # Health status overview
POST   /api/v1/admin/partners/{id}/test-connection  # Test API connectivity
```

**Partner List Response**:
```json
{
  "data": [
    {
      "partner_id": "part_001",
      "type": "financiera",
      "code": "banco_nacional",
      "name": "Banco Nacional",
      "logo_url": "/assets/partners/banco-nacional.png",
      "api_type": "REST",
      "is_active": true,
      "is_sandbox": false,
      "health_status": "healthy",
      "circuit_breaker_state": "closed",
      "last_health_check": "2026-03-23T09:55:00Z",
      "metrics_summary": {
        "requests_today": 45,
        "success_rate": 97.8,
        "avg_response_ms": 1250
      },
      "created_at": "2025-06-01T10:00:00Z"
    },
    {
      "partner_id": "part_002",
      "type": "aseguradora",
      "code": "seguros_atlas",
      "name": "Seguros Atlas",
      "logo_url": "/assets/partners/seguros-atlas.png",
      "api_type": "REST",
      "is_active": true,
      "is_sandbox": false,
      "health_status": "degraded",
      "circuit_breaker_state": "half_open",
      "last_health_check": "2026-03-23T09:55:00Z",
      "metrics_summary": {
        "requests_today": 28,
        "success_rate": 85.7,
        "avg_response_ms": 3400
      },
      "created_at": "2025-07-15T10:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total": 12
  }
}
```

**Partner Detail Response**:
```json
{
  "partner_id": "part_001",
  "type": "financiera",
  "code": "banco_nacional",
  "name": "Banco Nacional",
  "logo_url": "/assets/partners/banco-nacional.png",
  "api_type": "REST",
  "base_url": "https://api.banconacional.com/v2",
  "auth_type": "OAUTH2",
  "credentials_configured": true,
  "credentials_last_updated": "2026-02-15T10:00:00Z",
  "supported_terms": [12, 24, 36, 48, 60],
  "min_amount": 50000.00,
  "max_amount": 5000000.00,
  "max_response_minutes": 30,
  "is_active": true,
  "is_sandbox": false,
  "health_status": "healthy",
  "circuit_breaker_state": "closed",
  "webhook_url": "https://api.marketplace.com/webhooks/financing/banco_nacional/decision",
  "webhook_secret_configured": true,
  "contact": {
    "name": "Pedro Martinez",
    "email": "pedro.martinez@banconacional.com",
    "phone": "+5215512345678"
  },
  "notes": "Integration completed 2025-06-15. Contact for rate changes.",
  "created_at": "2025-06-01T10:00:00Z",
  "updated_at": "2026-03-20T14:00:00Z"
}
```

**Metrics Response**:
```json
{
  "partner_id": "part_001",
  "period": "last_30_days",
  "metrics": {
    "total_requests": 1250,
    "successful_requests": 1220,
    "failed_requests": 18,
    "timeout_requests": 12,
    "success_rate": 97.6,
    "avg_response_ms": 1340,
    "p95_response_ms": 3200,
    "p99_response_ms": 5800,
    "applications_sent": 89,
    "applications_approved": 56,
    "applications_rejected": 28,
    "applications_timeout": 5,
    "approval_rate": 62.9,
    "revenue_generated": 245000.00,
    "daily_breakdown": [
      {
        "date": "2026-03-22",
        "requests": 42,
        "success_rate": 100.0,
        "avg_response_ms": 1100,
        "applications": 3,
        "approved": 2
      }
    ]
  }
}
```

**Data Model**:
```
Partner (DOM)
  - partner_id: UUID (PK)
  - type: Enum(FINANCIERA, ASEGURADORA)
  - code: String(30) UNIQUE
  - name: String(100)
  - logo_url: String(255)
  - api_type: Enum(REST, SOAP, SFTP)
  - base_url: String(255)
  - auth_type: Enum(API_KEY, OAUTH2, CERTIFICATE, BASIC)
  - credentials_ref: String(255) (AWS Secrets Manager ARN)
  - configuration: JSONB (type-specific: terms, amounts, coverages, etc.)
  - webhook_url: String(255)
  - webhook_secret_ref: String(255)
  - is_active: Boolean default false
  - is_sandbox: Boolean default true
  - health_status: Enum(HEALTHY, DEGRADED, DOWN, UNKNOWN)
  - circuit_breaker_state: Enum(CLOSED, OPEN, HALF_OPEN)
  - contact_name: String(100)
  - contact_email: String(100)
  - contact_phone: String(20)
  - notes: Text
  - created_at: DateTime
  - updated_at: DateTime

PartnerIntegrationLog (INF)
  - log_id: UUID (PK)
  - partner_id: UUID (FK)
  - direction: Enum(OUTBOUND, INBOUND)
  - operation: String(50)
  - request_summary: Text
  - response_status: Integer
  - response_summary: Text
  - duration_ms: Integer
  - is_error: Boolean
  - error_message: Text
  - created_at: DateTime
```

**Component Structure**:
```
svc-adm/
  domain/
    models/partner.py
    models/partner_integration_log.py
    services/partner_management_service.py
    services/partner_health_service.py
  application/
    use_cases/list_partners_use_case.py
    use_cases/create_partner_use_case.py
    use_cases/update_partner_use_case.py
    use_cases/toggle_partner_status_use_case.py
    use_cases/update_credentials_use_case.py
    use_cases/get_partner_metrics_use_case.py
    use_cases/test_connection_use_case.py
    dto/partner_dto.py
    dto/partner_metrics_dto.py
    validators/partner_validator.py
  infrastructure/
    repositories/partner_repository.py
    repositories/integration_log_repository.py
    clients/fin_service_client.py
    clients/ins_service_client.py
    secrets/secrets_manager_client.py
  api/
    routes/partner_routes.py
    schemas/partner_schema.py
```

#### Acceptance Criteria

1. **AC-01**: GET /api/v1/admin/partners requires JWT with role "admin" or "editor" (read-only for editors); supports filter by type (financiera/aseguradora), is_active, health_status; pagination with page + per_page.
2. **AC-02**: POST /api/v1/admin/partners requires "admin" role; creates a new partner with initial status is_active=false, is_sandbox=true; required fields: type, code (unique), name, api_type, base_url, auth_type; returns 201.
3. **AC-03**: PUT /api/v1/admin/partners/{id}/credentials accepts credentials (API keys, OAuth client_id/secret, certificate PEM) and stores them in AWS Secrets Manager; the partner record stores only the Secrets Manager ARN, never the raw credentials; returns 200 with credentials_configured=true.
4. **AC-04**: PATCH /api/v1/admin/partners/{id}/status toggles is_active; activating a partner requires: credentials_configured=true, at least one successful test-connection, and is_sandbox=false (must graduate from sandbox first); failing any check returns 422 with the specific requirement not met.
5. **AC-05**: POST /api/v1/admin/partners/{id}/test-connection triggers a health_check call via the appropriate adapter (SVC-FIN or SVC-INS based on partner type); returns the result with: connectivity (ok/failed), response_time_ms, ssl_valid, auth_valid, api_version_compatible; the test result is logged.
6. **AC-06**: GET /api/v1/admin/partners/{id}/metrics returns aggregated performance metrics for the last 30 days (default): total_requests, success_rate, avg/p95/p99 response times, and for financieras: applications/approvals/rejections, for aseguradoras: quotes/policies/claims; supports period parameter.
7. **AC-07**: GET /api/v1/admin/partners/{id}/logs returns integration logs for the partner: timestamp, direction, operation, status, duration, error message if any; supports date range filter and pagination; sensitive data in logs is masked.
8. **AC-08**: GET /api/v1/admin/partners/health returns a summary of all active partners' health status grouped by type; includes: total count, healthy count, degraded count, down count, and a list of partners with non-healthy status.
9. **AC-09**: When a partner's health_status changes (e.g., HEALTHY -> DEGRADED or DEGRADED -> DOWN), a SystemAlert is created and the operations team is notified via SVC-NTF.
10. **AC-10**: Partner configuration includes type-specific fields: financieras have supported_terms, min/max_amount, max_response_minutes; aseguradoras have supported_coverages, rate_limit_per_second; these are stored in the configuration JSONB field.
11. **AC-11**: Deleting a partner is soft-delete (is_active=false + deleted_at timestamp); the partner's data is retained for audit and historical metrics; only admin role can delete.
12. **AC-12**: All partner management operations (create, update, status change, credential update) are recorded in AuditLog; credential operations log the action but never the credential values.

#### Definition of Done
- All CRUD endpoints implemented
- Secrets Manager integration for credential storage
- Health status aggregation working
- Metrics endpoint with daily breakdown
- Unit tests >= 95% coverage
- Integration tests with mock SVC-FIN and SVC-INS
- Code reviewed and merged to develop

#### Technical Notes
- Credentials should never appear in API responses, logs, or error messages
- Test-connection should have a timeout of 10 seconds to prevent hanging
- Consider caching partner list in Redis (TTL 1 min) as it's queried frequently by other services
- Health status aggregation should pull from SVC-FIN and SVC-INS directly, not maintain a separate copy
- Partner type determines which service to delegate to for test-connection and metrics

#### Dependencies
- SVC-FIN for financiera health checks and metrics
- SVC-INS for aseguradora health checks and metrics
- AWS Secrets Manager for credential storage
- SVC-NTF for health alerts

---

### US-5: [MKT-FE-022][FE-FEAT-ADM] Dashboard Admin Principal

**Description**:
Build the main admin dashboard page in Angular 18 featuring KPI summary cards with trend indicators, trend charts using Chart.js, a recent activity table, system alerts with severity indicators, and period filter controls. The dashboard serves as the landing page for admin users and provides at-a-glance marketplace health.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-ADM (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/admin/
  dashboard/
    admin-dashboard.component.ts
    admin-dashboard.component.html
    admin-dashboard.component.spec.ts
  kpi-card/
    kpi-card.component.ts
    kpi-card.component.html
  trend-chart/
    trend-chart.component.ts
    trend-chart.component.html
  activity-table/
    activity-table.component.ts
    activity-table.component.html
  alert-banner/
    alert-banner.component.ts
    alert-banner.component.html
  period-filter/
    period-filter.component.ts
    period-filter.component.html
  services/
    admin-dashboard.service.ts
  state/
    dashboard.store.ts
```

**Dashboard Store**:
```typescript
@Injectable({ providedIn: 'root' })
export class DashboardStore {
  readonly period = signal<string>('month');
  readonly startDate = signal<string | null>(null);
  readonly endDate = signal<string | null>(null);
  readonly kpis = signal<DashboardKpis | null>(null);
  readonly charts = signal<DashboardCharts | null>(null);
  readonly recentActivity = signal<ActivityEntry[]>([]);
  readonly systemAlerts = signal<SystemAlert[]>([]);
  readonly isLoading = signal<boolean>(false);
  readonly lastRefreshed = signal<Date | null>(null);
  readonly autoRefreshEnabled = signal<boolean>(true);

  readonly criticalAlerts = computed(() =>
    this.systemAlerts().filter(a => a.severity === 'critical' || a.severity === 'error')
  );
}
```

**KPI Card Layout**:
```html
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-5 gap-4">
  @for (kpi of kpiCards(); track kpi.key) {
    <div class="bg-white rounded-xl shadow-sm p-6 hover:shadow-md transition-shadow">
      <div class="flex justify-between items-start">
        <div>
          <p class="text-sm text-gray-500 font-medium">{{ kpi.label }}</p>
          <p class="text-2xl font-bold mt-1">
            {{ kpi.formattedValue }}
          </p>
        </div>
        <div class="p-2 rounded-lg" [class]="kpi.iconBgClass">
          <span class="text-xl">{{ kpi.icon }}</span>
        </div>
      </div>
      <div class="mt-4 flex items-center gap-1 text-sm">
        @if (kpi.trend === 'up') {
          <span class="text-green-600">^ {{ kpi.changePercentage }}%</span>
          <span class="text-gray-400">vs periodo anterior</span>
        } @else if (kpi.trend === 'down') {
          <span class="text-red-600">v {{ kpi.changePercentage }}%</span>
          <span class="text-gray-400">vs periodo anterior</span>
        } @else {
          <span class="text-gray-500">= Sin cambio</span>
        }
      </div>
    </div>
  }
</div>
```

#### Acceptance Criteria

1. **AC-01**: The dashboard is the default landing page for authenticated admin users (role: admin, editor, viewer); non-admin users are redirected to the public marketplace.
2. **AC-02**: A period filter control at the top allows selecting: Today, This Week, This Month (default), This Quarter, This Year, Custom Range (date pickers); changing the period triggers a new API call to refresh all KPIs and charts.
3. **AC-03**: KPI cards display the following metrics in a responsive grid: Registered Users, Active Vehicles, New Listings, Transactions, Revenue (formatted as MXN currency), Financing Applications, Approval Rate (%), Insurance Policies, Avg Days to Sale; each card shows the value, trend indicator (up/down arrow with percentage), and comparison to previous period.
4. **AC-04**: Trend indicators use color coding: green for positive trends (more users, revenue, etc.), red for negative trends; for "Avg Days to Sale", the polarity is inverted (decrease = green, increase = red).
5. **AC-05**: Two Chart.js line charts display: (a) Revenue over time (daily points for the selected period), (b) New Users over time; charts include tooltips on hover, legend, and responsive sizing; data comes from the charts section of the API response.
6. **AC-06**: Two additional charts display: (a) Vehicles by Source (pie/doughnut chart showing distribution of the 18 sources), (b) Transactions by Type (horizontal bar chart: sales, financing, insurance).
7. **AC-07**: A recent activity table shows the 20 most recent events: timestamp, type (with color-coded badge), description, actor; the table auto-refreshes every 60 seconds when autoRefresh is enabled; a "View all" link navigates to the full audit log.
8. **AC-08**: System alerts appear in a banner above the KPI cards when critical/error alerts exist; each alert shows severity icon (color-coded), message, source service, and timestamp; an "Acknowledge" button dismisses the alert (calls API); warning-level alerts appear in a collapsible section below the banner.
9. **AC-09**: A manual refresh button and auto-refresh toggle (default: on, interval: 60s) are available in the header; the last refreshed timestamp is displayed; refreshing shows a subtle loading overlay without full-page skeleton.
10. **AC-10**: The dashboard is fully responsive: on mobile (< 640px) KPI cards stack in single column, charts stack vertically and resize; on tablet (768px-1024px) KPI cards in 2-column grid; on desktop (>= 1280px) KPI cards in 4-5 column grid with charts side by side.
11. **AC-11**: Loading state: initial load shows skeleton placeholders for KPI cards and charts; subsequent refreshes show a subtle shimmer overlay on existing content without layout shift.
12. **AC-12**: Error handling: if the API call fails, existing cached data remains visible with a "Could not refresh data" notification and a retry button; if no cached data exists, a full-page error state with retry is shown.

#### Definition of Done
- Dashboard component implemented with all KPI cards, charts, activity table, alerts
- Chart.js integration with responsive charts
- Auto-refresh mechanism with toggle
- Fully responsive Tailwind CSS layout
- Unit tests >= 90% coverage
- E2E test: change period filter -> verify KPI update -> acknowledge alert
- Performance: < 2s full render (including API + charts)
- Code reviewed and merged to develop

#### Technical Notes
- Use ng2-charts for Chart.js integration in Angular
- Auto-refresh should pause when the browser tab is not visible (Page Visibility API)
- Consider using `@defer` for charts below the fold to improve initial render time
- KPI card trend calculation happens on the backend; frontend just displays the result
- Dashboard data can be preloaded via Angular route resolver

#### Dependencies
- US-1 (Dashboard KPI API)
- Chart.js / ng2-charts library
- Admin layout/shell component with sidebar navigation
- Auth guard for admin routes

---

### US-6: [MKT-FE-023][FE-FEAT-ADM] Panel de Gestion de Inventario

**Description**:
Build the vehicle inventory management panel for the admin frontend. Features a searchable table with advanced filters, pagination, inline price/status editing, bulk action capabilities (publish, unpublish, archive, delete), a vehicle detail view with edit form, and drag-and-drop image upload with reordering. This is the primary tool for the operations team to manage the 11,000+ vehicle catalog.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-ADM (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/admin/
  inventory/
    inventory-list.component.ts
    inventory-list.component.html
    inventory-list.component.spec.ts
  inventory-filters/
    inventory-filters.component.ts
    inventory-filters.component.html
  vehicle-detail-admin/
    vehicle-detail-admin.component.ts
    vehicle-detail-admin.component.html
  vehicle-form/
    vehicle-form.component.ts
    vehicle-form.component.html
  image-manager/
    image-manager.component.ts
    image-manager.component.html
  bulk-upload/
    bulk-upload.component.ts
    bulk-upload.component.html
  bulk-actions/
    bulk-actions-bar.component.ts
    bulk-actions-bar.component.html
  pricing-editor/
    pricing-editor.component.ts
    pricing-editor.component.html
  services/
    inventory-admin.service.ts
  state/
    inventory.store.ts
```

**Inventory Store**:
```typescript
@Injectable({ providedIn: 'root' })
export class InventoryStore {
  readonly vehicles = signal<AdminVehicle[]>([]);
  readonly pagination = signal<Pagination>({ page: 1, perPage: 25, total: 0 });
  readonly searchQuery = signal<string>('');
  readonly filters = signal<InventoryFilters>({
    status: [],
    brand: null,
    yearMin: null,
    yearMax: null,
    priceMin: null,
    priceMax: null,
    source: []
  });
  readonly sortColumn = signal<string>('created_at');
  readonly sortDirection = signal<'asc' | 'desc'>('desc');
  readonly selectedVehicleIds = signal<Set<string>>(new Set());
  readonly isLoading = signal<boolean>(false);
  readonly bulkUploadJob = signal<BulkUploadJob | null>(null);

  readonly selectedCount = computed(() => this.selectedVehicleIds().size);
  readonly hasSelection = computed(() => this.selectedCount() > 0);
  readonly allSelected = computed(() =>
    this.vehicles().length > 0 &&
    this.selectedCount() === this.vehicles().length
  );
}
```

#### Acceptance Criteria

1. **AC-01**: The inventory panel displays vehicles in a data table with columns: checkbox (for selection), image thumbnail, title (brand model year version), price, status (badge: green=published, gray=draft, red=archived), source, views, days listed, actions (edit/view/delete icons); columns are sortable by clicking headers.
2. **AC-02**: A search bar at the top performs full-text search (brand, model, version, VIN) with debounce (300ms); results update without full page reload; search term is highlighted in results.
3. **AC-03**: Filter panel (collapsible sidebar or dropdown) provides: status multi-select checkboxes, brand dropdown (searchable), year range slider (min/max), price range slider (min/max), source multi-select; active filters show as removable chips above the table; a "Clear all filters" button resets all.
4. **AC-04**: Pagination shows: total vehicle count, current page, page size selector (10/25/50/100), page navigation (first, previous, page numbers, next, last); changing page size resets to page 1.
5. **AC-05**: Inline editing: clicking a vehicle's price cell opens an inline input for quick price editing; pressing Enter saves (PATCH /pricing), Escape cancels; clicking a status badge opens a dropdown for quick status change (PATCH /status); changes are saved immediately with a subtle success toast.
6. **AC-06**: Checkbox selection enables bulk actions: selecting one or more vehicles reveals a sticky bottom action bar with buttons: "Publish" (count), "Unpublish" (count), "Archive" (count), "Delete" (count); a "Select all on page" checkbox in the header selects all visible vehicles; bulk actions show a confirmation dialog with the count.
7. **AC-07**: Vehicle detail/edit view opens in a slide-over panel (or full page): displays all vehicle fields in editable form; fields grouped by section (basic info, specifications, pricing, description); save button validates and calls PUT endpoint; cancel returns to list.
8. **AC-08**: Image manager within the detail view: displays current images in a grid; supports drag-and-drop reorder (new order saved via PUT /images/reorder); drag-and-drop upload zone for new images (max 20 per vehicle, JPEG/PNG/WebP, max 10MB each); delete button per image with confirmation; the first image has a "Primary" badge.
9. **AC-09**: Bulk CSV/XLSX upload: an "Import" button opens a modal with: drag-and-drop file zone, template download link (CSV and XLSX), source label input, "publish immediately" toggle; after upload, a progress indicator shows: "Processing row X of Y", success count, error count; completed jobs show an error report with downloadable error details.
10. **AC-10**: The panel is responsive: on desktop, the full table with all columns is visible; on tablet, less important columns (views, days_listed, source) are hidden; on mobile, the table transforms into a card list with key info (image, title, price, status) and expandable details.
11. **AC-11**: Empty states: when no vehicles match filters/search, show "No vehicles found" with suggestion to adjust filters; when the inventory is completely empty, show an onboarding message with "Add your first vehicle" CTA.
12. **AC-12**: Performance: the table renders 25 rows in < 200ms; scrolling is smooth; filter changes show loading indicator within 100ms; virtual scrolling is used if page size exceeds 50.

#### Definition of Done
- Inventory table with search, filters, sort, pagination
- Inline editing for price and status
- Bulk selection and actions with confirmation
- Vehicle detail/edit slide-over panel
- Drag-and-drop image management
- Bulk CSV/XLSX upload with progress
- Fully responsive layout
- Unit tests >= 90% coverage
- E2E test: search, filter, inline edit, bulk action, image upload
- Code reviewed and merged to develop

#### Technical Notes
- Use Angular CDK DragDrop for image reordering
- Debounce search input to avoid excessive API calls
- Consider using Angular CDK Virtual Scroll for large page sizes
- Bulk upload file processing should poll the job status endpoint every 2 seconds
- Image thumbnails should use CDN URLs with resize parameters for fast loading

#### Dependencies
- US-2 (Inventory management API)
- Angular CDK (DragDrop, Virtual Scroll)
- Admin layout component with navigation
- Shared table/pagination components

---

### US-7: [MKT-FE-024][FE-FEAT-ADM] Panel de Gestion de Partners

**Description**:
Build the partner management panel for the admin frontend, covering both financieras and aseguradoras. The panel displays a unified list of all partners with type indicators, provides add/edit forms for partner configuration, shows real-time health status with color-coded indicators (green/yellow/red), displays performance metrics with charts, and provides access to integration logs for debugging.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-ADM (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/admin/
  partners/
    partner-list.component.ts
    partner-list.component.html
    partner-list.component.spec.ts
  partner-form/
    partner-form.component.ts
    partner-form.component.html
  partner-detail/
    partner-detail.component.ts
    partner-detail.component.html
  health-indicator/
    health-indicator.component.ts
    health-indicator.component.html
  partner-metrics/
    partner-metrics.component.ts
    partner-metrics.component.html
  integration-logs/
    integration-logs.component.ts
    integration-logs.component.html
  services/
    partner-admin.service.ts
  state/
    partner.store.ts
```

**Partner Store**:
```typescript
@Injectable({ providedIn: 'root' })
export class PartnerStore {
  readonly partners = signal<Partner[]>([]);
  readonly selectedPartner = signal<Partner | null>(null);
  readonly partnerMetrics = signal<PartnerMetrics | null>(null);
  readonly integrationLogs = signal<IntegrationLog[]>([]);
  readonly filterType = signal<'all' | 'financiera' | 'aseguradora'>('all');
  readonly filterHealth = signal<'all' | 'healthy' | 'degraded' | 'down'>('all');
  readonly isLoading = signal<boolean>(false);
  readonly healthOverview = signal<HealthOverview | null>(null);

  readonly filteredPartners = computed(() => {
    let list = this.partners();
    if (this.filterType() !== 'all') {
      list = list.filter(p => p.type === this.filterType());
    }
    if (this.filterHealth() !== 'all') {
      list = list.filter(p => p.healthStatus === this.filterHealth());
    }
    return list;
  });

  readonly healthySummary = computed(() => ({
    healthy: this.partners().filter(p => p.healthStatus === 'healthy').length,
    degraded: this.partners().filter(p => p.healthStatus === 'degraded').length,
    down: this.partners().filter(p => p.healthStatus === 'down').length,
    total: this.partners().length
  }));
}
```

**Health Indicator Component**:
```html
<!-- Green/Yellow/Red health dot with label -->
<div class="flex items-center gap-2">
  <span class="relative flex h-3 w-3">
    @if (status() === 'healthy') {
      <span class="animate-ping absolute inline-flex h-full w-full rounded-full
                   bg-green-400 opacity-75"></span>
      <span class="relative inline-flex rounded-full h-3 w-3
                   bg-green-500"></span>
    } @else if (status() === 'degraded') {
      <span class="animate-pulse absolute inline-flex h-full w-full
                   rounded-full bg-yellow-400 opacity-75"></span>
      <span class="relative inline-flex rounded-full h-3 w-3
                   bg-yellow-500"></span>
    } @else {
      <span class="relative inline-flex rounded-full h-3 w-3
                   bg-red-500"></span>
    }
  </span>
  <span class="text-sm capitalize">{{ status() }}</span>
</div>
```

#### Acceptance Criteria

1. **AC-01**: The partner list displays all partners (financieras + aseguradoras) in a table or card grid with: logo, name, type badge (blue for financiera, purple for aseguradora), health status indicator (green/yellow/red dot), active/inactive toggle, circuit breaker state, requests today, success rate; sortable by name, type, health status.
2. **AC-02**: A health overview bar at the top shows: total partners count, healthy (green) count, degraded (yellow) count, down (red) count; clicking a status filters the list to show only partners with that status.
3. **AC-03**: Filter tabs allow switching between: All, Financieras, Aseguradoras; each tab shows a count badge; an additional filter for health status (All, Healthy, Degraded, Down) refines the list.
4. **AC-04**: An "Add Partner" button opens a form (modal or slide-over) with fields: type (financiera/aseguradora radio), code (auto-generated slug from name, editable), name, API type (REST/SOAP dropdown), base URL, auth type (API_KEY/OAUTH2/Certificate dropdown), contact name/email/phone, notes; required fields validated; save calls POST endpoint.
5. **AC-05**: Clicking a partner row opens the partner detail view with tabs: (a) Configuration - editable fields for endpoints, auth type, type-specific settings (terms/amounts for financieras, coverages for aseguradoras), (b) Credentials - credential update form (fields depend on auth_type: API key input, OAuth client_id + secret, certificate PEM upload), (c) Metrics, (d) Integration Logs.
6. **AC-06**: Health indicators update in real-time: the partner list polls GET /admin/partners/health every 30 seconds; status transitions are highlighted with a brief animation (e.g., border flash); if a partner transitions to DOWN, a toast notification appears.
7. **AC-07**: Metrics tab shows Chart.js visualizations: (a) Line chart of success rate over last 30 days, (b) Bar chart of avg response time by day, (c) For financieras: approval rate trend, for aseguradoras: quote-to-policy conversion trend; KPI summary cards above charts show: total requests, success rate, avg response time, specific metrics per type.
8. **AC-08**: Integration logs tab shows a scrollable, filtered log table: timestamp, direction (inbound/outbound with arrow icon), operation, status (color-coded badge), duration_ms, error message (if any); filters for date range, direction, and error-only toggle; clicking a log entry expands to show request/response summary (masked sensitive data).
9. **AC-09**: A "Test Connection" button on each partner's detail view triggers the test-connection API; a modal shows the test progress and results: connectivity status, response time, SSL validity, auth validity, API version compatibility; each check is displayed as a checklist item with pass/fail indicators.
10. **AC-10**: The active/inactive toggle on each partner row calls PATCH /status; toggling inactive to active validates prerequisites (credentials configured, successful test connection); if prerequisites not met, a tooltip/popover explains what's missing.
11. **AC-11**: The panel is responsive: on desktop, full table view with all columns; on tablet, card grid (2 columns) with key info; on mobile, single column cards with expandable details.
12. **AC-12**: Error states: if partner list fails to load, show retry button; if metrics fail, show "Metrics unavailable" placeholder with retry; individual partner operations (save, test, toggle) show inline error messages.

#### Definition of Done
- Partner list with health indicators and filters
- Add/edit partner form with type-specific fields
- Metrics visualization with Chart.js
- Integration logs with filtering and expandable detail
- Test connection modal
- Real-time health status updates (polling)
- Fully responsive
- Unit tests >= 90% coverage
- E2E test: add partner -> configure -> test connection -> activate
- Code reviewed and merged to develop

#### Technical Notes
- Health status polling should use Angular's `interval` + `switchMap` with auto-pause on tab hidden
- Credential forms should use `<input type="password">` and never show stored credentials
- Certificate PEM upload should validate the file format before upload
- Consider using Angular Material bottom sheet for partner detail on mobile
- Log entries should implement virtual scrolling for partners with many log entries

#### Dependencies
- US-4 (Partner management API)
- Chart.js / ng2-charts for metrics charts
- Admin layout with navigation
- Shared form components

---

## Cross-Cutting Concerns

### Security
- All admin endpoints require JWT with admin/editor/viewer role
- Permission middleware enforces granular resource-level access
- Audit logging for all write operations
- Credentials never exposed in API responses or logs
- CORS restricted to admin domain only

### Observability
- Admin action metrics: operations per admin, response times, error rates
- Dashboard render time tracking
- Bulk upload job monitoring
- Partner health status change alerts

### Performance
- Dashboard KPIs cached in Redis (5 min TTL)
- Elasticsearch for fast vehicle search across 11,000+ vehicles
- Pagination and lazy loading for large data sets
- CDN for vehicle image thumbnails

### Audit & Compliance
- All admin actions logged with actor, timestamp, before/after state
- Audit log immutable and partitioned monthly
- 2-year retention for audit logs
- Separation of duties: role-based access prevents unauthorized changes

---

## Epic Dependencies Graph

```
EP-009 Dependencies:
  SVC-USR (EP-002) --> User data and Cognito integration
  SVC-VEH (EP-003) --> Vehicle CRUD and search
  SVC-FIN (EP-007) --> Financiera metrics and health
  SVC-INS (EP-008) --> Aseguradora metrics and health
  SVC-RPT (EP-011) --> Heavy aggregations for KPIs
  SVC-NTF (EP-010) --> Admin notifications and alerts
  Elasticsearch 8 --> Vehicle search
  AWS Cognito --> User account management
  AWS Secrets Manager --> Partner credential storage
```

## Release Plan

| Sprint | Stories | Focus |
|--------|---------|-------|
| Sprint 3 | US-1, US-5 | Dashboard API + Frontend Dashboard |
| Sprint 4 | US-2, US-6 | Inventory API + Frontend Inventory |
| Sprint 5 | US-3 | Users & Roles API |
| Sprint 6 | US-4, US-7 | Partners API + Frontend Partners |
| Sprint 7-8 | Polish, audit logging, bulk operations | Refinement and testing |
