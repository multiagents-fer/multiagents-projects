# [MKT-EP-008] Marketplace de Seguros

**Sprint**: 6-8
**Priority**: High
**Epic Owner**: Tech Lead - SVC-INS
**Stakeholders**: Product, Insurance Partnerships, Frontend Lead, Compliance
**Estimated Effort**: 68 story points

---

## Epic Overview

This epic delivers a complete insurance marketplace where users can quote, compare, and purchase vehicle insurance from multiple providers in a single flow. The system fans out quote requests to N insurance providers simultaneously, aggregates responses with standardized coverage comparisons, and enables end-to-end policy contracting including payment and digital policy issuance. The architecture mirrors the financing epic's adapter pattern, with provider-specific adapters behind a hexagonal port interface.

### Business Goals
- Enable users to compare insurance quotes from multiple providers in one place
- Reduce insurance shopping time from hours to minutes
- Increase vehicle purchase conversion by bundling insurance in the checkout flow
- Generate commission revenue from insurance policy sales
- Provide transparency on coverage details, deductibles, and exclusions

### Architecture Context
- **Primary Service**: SVC-INS (:5016)
- **Supporting Services**: SVC-VEH (:5012), SVC-USR (:5011), SVC-PUR (:5013), SVC-NTF (:5017)
- **Worker**: WRK-INS (async provider communication)
- **Message Broker**: SQS for fan-out to providers
- **Cache**: Redis 7 for quote caching (24h TTL)
- **Database**: PostgreSQL 15 for quotes, policies, provider data

---

## User Stories

---

### US-1: [MKT-BE-021][SVC-INS-API] Cotizacion de Seguros Multi-Aseguradora

**Description**:
Implement an insurance quoting endpoint that receives vehicle and driver information along with the desired coverage type, then fans out quote requests to N active insurance providers simultaneously. The endpoint aggregates returned quotes into a standardized format, caches results for 24 hours, and returns a comparison-ready response. The fan-out uses SQS for async dispatch and Redis for response aggregation with a configurable timeout per provider.

**Microservice**: SVC-INS (:5016)
**Layer**: API + APP + DOM + INF
**Worker**: WRK-INS (fan-out execution)

#### Technical Context

**Endpoint**:
```
POST /api/v1/insurance/quote
Content-Type: application/json
Authorization: Bearer <jwt> (required)
```

**Request Schema**:
```json
{
  "vehicle": {
    "vehicle_id": "veh_abc123",
    "brand": "Toyota",
    "model": "Camry",
    "year": 2024,
    "version": "SE",
    "vin": "1HGCG5655WA041389",
    "license_plate": "ABC-123-D",
    "current_value": 450000.00,
    "usage": "particular",
    "zip_code": "06600"
  },
  "driver": {
    "full_name": "Juan Perez Lopez",
    "date_of_birth": "1985-01-01",
    "gender": "M",
    "zip_code": "06600",
    "license_number": "CDMX-123456",
    "license_type": "automovilista",
    "years_driving": 10,
    "claims_last_3_years": 0
  },
  "coverage_types": ["basica", "amplia", "premium"],
  "payment_frequency": "mensual",
  "start_date": "2026-04-01",
  "target_providers": null
}
```

**Response Schema**:
```json
{
  "quote_request_id": "qr_abc123",
  "status": "completed",
  "vehicle_summary": {
    "description": "Toyota Camry 2024 SE",
    "insured_value": 450000.00
  },
  "quotes": [
    {
      "quote_id": "qt_001",
      "provider_id": "prov_001",
      "provider_name": "Seguros Atlas",
      "provider_logo_url": "/assets/providers/atlas.png",
      "provider_rating": 4.2,
      "coverage_type": "amplia",
      "coverage_label": "Cobertura Amplia",
      "annual_premium": 18500.00,
      "monthly_premium": 1625.00,
      "deductible_percentage": 5,
      "deductible_amount": 22500.00,
      "coverages": [
        {
          "name": "Danos materiales",
          "description": "Cubre danos al vehiculo asegurado",
          "sum_insured": 450000.00,
          "deductible": "5%",
          "included": true
        },
        {
          "name": "Robo total",
          "description": "Cubre perdida total por robo",
          "sum_insured": 450000.00,
          "deductible": "10%",
          "included": true
        },
        {
          "name": "Responsabilidad civil",
          "description": "Danos a terceros en bienes y personas",
          "sum_insured": 3000000.00,
          "deductible": "N/A",
          "included": true
        },
        {
          "name": "Gastos medicos ocupantes",
          "description": "Gastos medicos por accidente",
          "sum_insured": 200000.00,
          "deductible": "N/A",
          "included": true
        },
        {
          "name": "Asistencia vial",
          "description": "Grua, paso de corriente, cambio de llanta",
          "sum_insured": null,
          "deductible": "N/A",
          "included": true
        },
        {
          "name": "Auto sustituto",
          "description": "Vehiculo de reemplazo durante reparacion",
          "sum_insured": null,
          "deductible": "N/A",
          "included": false
        }
      ],
      "exclusions": [
        "Uso comercial o de carga",
        "Conduccion en estado de ebriedad",
        "Siniestros en carreras o competencias"
      ],
      "valid_until": "2026-04-07T23:59:59Z",
      "quote_reference": "SA-2026-Q-00456"
    }
  ],
  "providers_summary": {
    "total_requested": 5,
    "responded": 4,
    "timeout": 1,
    "best_price_quote_id": "qt_001",
    "best_coverage_quote_id": "qt_003"
  },
  "cached": false,
  "cache_expires_at": "2026-03-24T10:00:00Z"
}
```

**Data Model**:
```
QuoteRequest (DOM)
  - quote_request_id: UUID (PK)
  - user_id: UUID (FK)
  - vehicle_id: UUID (FK, nullable)
  - vehicle_data: JSONB
  - driver_data: JSONB
  - coverage_types: ARRAY[String]
  - payment_frequency: Enum(MENSUAL, TRIMESTRAL, SEMESTRAL, ANUAL)
  - start_date: Date
  - status: Enum(PENDING, IN_PROGRESS, COMPLETED, EXPIRED)
  - providers_requested: Integer
  - providers_responded: Integer
  - created_at: DateTime
  - completed_at: DateTime
  - expires_at: DateTime

InsuranceQuote (DOM)
  - quote_id: UUID (PK)
  - quote_request_id: UUID (FK)
  - provider_id: UUID (FK)
  - coverage_type: Enum(BASICA, AMPLIA, PREMIUM)
  - annual_premium: Decimal(12,2)
  - monthly_premium: Decimal(12,2)
  - deductible_percentage: Decimal(5,2)
  - deductible_amount: Decimal(12,2)
  - coverages: JSONB
  - exclusions: JSONB
  - valid_until: DateTime
  - provider_reference: String(100)
  - is_best_price: Boolean default false
  - is_best_coverage: Boolean default false
  - status: Enum(ACTIVE, SELECTED, EXPIRED, REPLACED)
  - created_at: DateTime

InsuranceCoverage (DOM - value object)
  - name: String(100)
  - description: Text
  - sum_insured: Decimal(14,2) nullable
  - deductible: String(20)
  - included: Boolean
```

**Component Structure**:
```
svc-ins/
  domain/
    models/quote_request.py
    models/insurance_quote.py
    models/insurance_coverage.py
    services/quote_aggregation_service.py
    services/quote_comparison_service.py
    value_objects/coverage_type.py
    value_objects/payment_frequency.py
  application/
    use_cases/request_quotes_use_case.py
    use_cases/get_quotes_use_case.py
    dto/quote_request_dto.py
    dto/quote_response_dto.py
    validators/quote_request_validator.py
  infrastructure/
    repositories/quote_request_repository.py
    repositories/insurance_quote_repository.py
    messaging/sqs_quote_publisher.py
    cache/quote_cache.py
  api/
    routes/quote_routes.py
    schemas/quote_schema.py (Marshmallow)
  config/
    insurance_config.py
```

#### Acceptance Criteria

1. **AC-01**: POST /api/v1/insurance/quote requires valid JWT; returns 401 for unauthenticated requests.
2. **AC-02**: Request validation: vehicle.year must be within last 20 years, current_value > 0 and < 10,000,000, driver.date_of_birth must indicate age >= 18, coverage_types must be non-empty and contain valid values (basica, amplia, premium); invalid inputs return 422 with per-field errors.
3. **AC-03**: When vehicle_id is provided, the system calls SVC-VEH to enrich vehicle data (brand, model, year, version); if the vehicle is not found, return 404.
4. **AC-04**: The system identifies all active insurance providers and publishes one SQS message per provider per coverage_type requested to queue `ins-quote-{provider_id}`; if target_providers is specified, only those providers are used.
5. **AC-05**: The endpoint returns immediately with status "in_progress" and the quote_request_id; the client polls GET /api/v1/insurance/quote/{quote_request_id} to retrieve quotes as they arrive, or connects to a WebSocket for real-time updates.
6. **AC-06**: As provider responses arrive via WRK-INS, InsuranceQuote records are created with standardized coverage mappings; the QuoteRequest.providers_responded count is incremented.
7. **AC-07**: When all providers have responded or the global timeout (120 seconds) is reached, QuoteRequest.status is set to COMPLETED; remaining providers are marked as timeout.
8. **AC-08**: Quote responses are cached in Redis with key `ins:quote:{quote_request_id}` and TTL 86400 (24 hours); subsequent identical requests (same vehicle + driver + coverage within 24h) return cached results with cached=true.
9. **AC-09**: The response includes providers_summary with total_requested, responded, timeout counts, and identifies best_price_quote_id (lowest annual_premium) and best_coverage_quote_id (most coverages included).
10. **AC-10**: Each quote includes a detailed coverages array with standardized coverage names, descriptions, sum_insured, deductible, and included boolean; provider-specific coverage names are mapped to the standard taxonomy.
11. **AC-11**: Each quote includes an exclusions array listing what is NOT covered; this is extracted from provider responses or populated from provider configuration defaults.
12. **AC-12**: Quotes are sorted by annual_premium ascending within each coverage_type by default; the API supports sort query parameter with values: price_asc, price_desc, rating_desc, coverage_desc.

#### Definition of Done
- Endpoint implemented with Marshmallow validation
- SQS fan-out tested with localstack
- Redis caching with 24h TTL verified
- Quote aggregation and comparison logic unit tested
- Integration tests for full flow (>= 95% coverage)
- API documented in OpenAPI 3.0 spec
- Code reviewed and merged to develop

#### Technical Notes
- Use SQS standard queues (not FIFO) for quote requests since ordering doesn't matter
- Cache key should include a hash of vehicle+driver+coverage to detect identical requests
- Coverage standardization mapping should be configurable (not hardcoded) per provider
- Consider returning partial results after 30 seconds with a "still loading" indicator

#### Dependencies
- SVC-VEH for vehicle data enrichment
- AWS SQS for provider fan-out
- Redis 7 for quote caching
- WRK-INS for async provider communication
- US-2 (InsuranceProviderPort and adapters)

---

### US-2: [MKT-BE-022][SVC-INS-INF] Adapter de Aseguradoras

**Description**:
Implement a hexagonal architecture port/adapter pattern for insurance provider integrations, mirroring the financial institution adapter pattern from EP-007. Define the `InsuranceProviderPort` interface that all provider adapters must implement. Each adapter handles communication with a specific insurer, mapping between the internal domain model and provider-specific API formats, handling errors, implementing rate limiting, and circuit breaker patterns.

**Microservice**: SVC-INS (:5016)
**Layer**: DOM (port interface) + INF (adapters)
**Worker**: WRK-INS (uses adapters)

#### Technical Context

**Port Interface**:
```python
# svc-ins/domain/ports/insurance_provider_port.py
from abc import ABC, abstractmethod

class InsuranceProviderPort(ABC):
    @abstractmethod
    async def request_quote(self, vehicle: VehicleData, driver: DriverData,
                            coverage: CoverageType) -> ProviderQuoteResponse:
        """Request an insurance quote from this provider."""
        pass

    @abstractmethod
    async def confirm_policy(self, quote_reference: str,
                             insured_data: InsuredData) -> PolicyConfirmation:
        """Confirm and issue a policy based on an accepted quote."""
        pass

    @abstractmethod
    async def get_policy_status(self, policy_reference: str) -> PolicyStatus:
        """Check the status of an issued policy."""
        pass

    @abstractmethod
    async def cancel_policy(self, policy_reference: str,
                            reason: str) -> CancellationResult:
        """Request policy cancellation."""
        pass

    @abstractmethod
    async def health_check(self) -> HealthStatus:
        """Check provider API availability."""
        pass

    @abstractmethod
    def get_provider_id(self) -> str:
        pass

    @abstractmethod
    def get_supported_coverages(self) -> list[CoverageType]:
        pass

    @abstractmethod
    def get_rate_limit(self) -> RateLimit:
        """Returns max requests per second/minute for this provider."""
        pass
```

**Adapter Example**:
```python
# svc-ins/infrastructure/adapters/seguros_atlas_adapter.py
class SegurosAtlasAdapter(InsuranceProviderPort):
    def __init__(self, config: ProviderConfig, http_client: HttpClient):
        self.config = config
        self.client = http_client
        self.circuit_breaker = CircuitBreaker(
            failure_threshold=5,
            recovery_timeout=60
        )
        self.rate_limiter = TokenBucketRateLimiter(
            max_tokens=10,
            refill_rate=2  # 2 requests per second
        )

    @circuit_breaker
    @rate_limiter
    async def request_quote(self, vehicle, driver, coverage):
        payload = self._map_to_atlas_format(vehicle, driver, coverage)
        response = await self.client.post(
            f"{self.config.base_url}/api/v2/cotizaciones",
            json=payload,
            headers=self._auth_headers(),
            timeout=30
        )
        return self._map_from_atlas_response(response)

    def _map_to_atlas_format(self, vehicle, driver, coverage):
        return {
            "vehiculo": {
                "marca": vehicle.brand,
                "modelo": vehicle.model,
                "anio": vehicle.year,
                "version": vehicle.version,
                "valor": float(vehicle.current_value),
                "uso": self._map_usage(vehicle.usage)
            },
            "conductor": {
                "nombre": driver.full_name,
                "fechaNacimiento": driver.date_of_birth.isoformat(),
                "sexo": driver.gender,
                "codigoPostal": driver.zip_code,
                "aniosManejando": driver.years_driving,
                "siniestros3Anios": driver.claims_last_3_years
            },
            "tipoCoberturaRequerido": self._map_coverage_type(coverage)
        }
```

**Data Model**:
```
InsuranceProvider (DOM)
  - provider_id: UUID (PK)
  - code: String(20) UNIQUE
  - name: String(100)
  - logo_url: String(255)
  - api_type: Enum(REST, SOAP, SFTP)
  - base_url: String(255)
  - auth_type: Enum(API_KEY, OAUTH2, CERTIFICATE)
  - credentials: JSONB (encrypted)
  - supported_coverages: ARRAY[String]
  - rate_limit_per_second: Integer
  - rate_limit_per_minute: Integer
  - avg_response_seconds: Float
  - rating: Decimal(3,1)
  - is_active: Boolean default true
  - is_sandbox: Boolean default false
  - health_status: Enum(HEALTHY, DEGRADED, DOWN)
  - last_health_check: DateTime
  - circuit_breaker_state: Enum(CLOSED, OPEN, HALF_OPEN)
  - created_at: DateTime
  - updated_at: DateTime

ProviderCoverageMapping (INF)
  - mapping_id: UUID (PK)
  - provider_id: UUID (FK)
  - internal_coverage_name: String(100)
  - provider_coverage_name: String(100)
  - provider_coverage_code: String(20)
  - default_sum_insured: Decimal(14,2)
  - default_deductible: String(20)

ProviderMetrics (DOM)
  - metric_id: UUID (PK)
  - provider_id: UUID (FK)
  - date: Date
  - quotes_requested: Integer
  - quotes_returned: Integer
  - quotes_timeout: Integer
  - policies_issued: Integer
  - avg_response_ms: Float
  - error_count: Integer
  - availability_pct: Decimal(5,2)
```

**Component Structure**:
```
svc-ins/
  domain/
    ports/
      insurance_provider_port.py
    models/
      insurance_provider.py
      provider_metrics.py
    value_objects/
      coverage_type.py
      health_status.py
      rate_limit.py
  infrastructure/
    adapters/
      base_provider_adapter.py
      seguros_atlas_adapter.py
      qualitas_adapter.py
      gnp_adapter.py
      axa_adapter.py
      adapter_factory.py
    circuit_breaker/
      circuit_breaker.py
    rate_limiter/
      token_bucket_rate_limiter.py
    http/
      http_client.py
    mapping/
      coverage_mapper.py
      amis_data_mapper.py
    health/
      provider_health_checker.py
```

#### Acceptance Criteria

1. **AC-01**: An `InsuranceProviderPort` abstract base class is defined with methods: request_quote, confirm_policy, get_policy_status, cancel_policy, health_check, get_provider_id, get_supported_coverages, get_rate_limit.
2. **AC-02**: An `AdapterFactory` returns the correct adapter instance based on provider_id; unknown provider raises `ProviderNotFoundError`; factory caches adapter instances (singleton per provider).
3. **AC-03**: Each adapter maps internal VehicleData and DriverData to the provider-specific format using a dedicated mapper; domain models never leak into external payloads.
4. **AC-04**: Provider responses are mapped back to standardized InsuranceCoverage objects using ProviderCoverageMapping configuration; unknown provider-specific coverage names are logged and mapped to "other" with the original name preserved.
5. **AC-05**: Circuit breaker per adapter: CLOSED -> OPEN after 5 consecutive failures; OPEN rejects for 60s; then HALF_OPEN allows 1 probe request; state shared via Redis across instances.
6. **AC-06**: Rate limiter per adapter implements token bucket algorithm respecting provider-specific limits (e.g., Qualitas: 5 req/s, Atlas: 10 req/s); exceeded rate returns 429 to the caller with retry-after header.
7. **AC-07**: Health check per provider runs every 5 minutes; updates health_status (HEALTHY if < 1% error rate, DEGRADED if 1-10%, DOWN if > 10% or circuit open); results visible via GET /api/v1/insurance/providers/health.
8. **AC-08**: Each adapter supports 3 coverage types: basica (liability only), amplia (liability + theft + damage), premium (amplia + medical + legal + roadside + substitute vehicle); providers that don't support all 3 types return quotes only for supported types.
9. **AC-09**: Request/response payloads are logged (sensitive fields masked: name, license, DOB) to an audit table with provider_id, direction, timestamp, duration_ms, status_code.
10. **AC-10**: Provider credentials are stored encrypted via AWS KMS and decrypted at runtime; credentials are never logged or included in error messages.
11. **AC-11**: Each adapter has a sandbox mode; when enabled, requests hit the provider's staging/sandbox endpoint with test credentials; sandbox responses include realistic sample data.
12. **AC-12**: Metrics per provider per day (quotes_requested, returned, timeout, policies_issued, avg_response_ms, error_count, availability_pct) are tracked and persisted in ProviderMetrics.

#### Definition of Done
- Port interface defined with docstrings
- At least 3 concrete adapters implemented (REST-based)
- Circuit breaker and rate limiter tested
- Coverage mapping configuration for each provider
- Unit tests >= 95% coverage
- Integration tests with mock HTTP servers
- Code reviewed and merged to develop

#### Technical Notes
- Use `httpx` for async HTTP calls
- AMIS (Asociacion Mexicana de Instituciones de Seguros) data format for standardized fields
- Coverage mapping should be database-driven (not hardcoded) for easy maintenance
- Some providers use vehicle catalog codes (amis_code) instead of brand/model text

#### Dependencies
- AWS KMS for credential management
- Redis for circuit breaker state and rate limiter
- AMIS vehicle catalog for provider-specific vehicle codes

---

### US-3: [MKT-BE-023][SVC-INS-API] Contratacion de Seguros

**Description**:
Implement the insurance policy contracting endpoint that takes a selected quote, additional insured data, and payment information to initiate policy issuance. The flow includes: validating the quote is still active, collecting additional insured details, processing payment, confirming the policy with the provider, and generating a digital policy document for the user.

**Microservice**: SVC-INS (:5016)
**Layer**: API + APP + DOM + INF

#### Technical Context

**Endpoint**:
```
POST /api/v1/insurance/apply
Content-Type: application/json
Authorization: Bearer <jwt> (required)
```

**Request Schema**:
```json
{
  "quote_id": "qt_001",
  "insured": {
    "full_name": "Juan Perez Lopez",
    "curp": "PELJ850101HDFRPN09",
    "rfc": "PELJ850101AB3",
    "date_of_birth": "1985-01-01",
    "email": "juan@example.com",
    "phone": "+5215512345678",
    "address": {
      "street": "Av. Reforma 222",
      "colony": "Juarez",
      "municipality": "Cuauhtemoc",
      "state": "CDMX",
      "zip_code": "06600"
    }
  },
  "beneficiary": {
    "full_name": "Maria Perez Garcia",
    "relationship": "conyuge",
    "phone": "+5215598765432"
  },
  "payment": {
    "method": "credit_card",
    "frequency": "mensual",
    "card_token": "tok_abc123"
  },
  "additional_driver": null
}
```

**Response Schema**:
```json
{
  "application_id": "ins_app_001",
  "status": "policy_issued",
  "policy": {
    "policy_id": "pol_001",
    "policy_number": "SA-POL-2026-00789",
    "provider_name": "Seguros Atlas",
    "coverage_type": "amplia",
    "insured_vehicle": "Toyota Camry 2024 SE",
    "insured_value": 450000.00,
    "annual_premium": 18500.00,
    "payment_frequency": "mensual",
    "monthly_premium": 1625.00,
    "effective_from": "2026-04-01",
    "effective_to": "2027-03-31",
    "deductible_percentage": 5,
    "policy_document_url": "/api/v1/insurance/policies/pol_001/document",
    "digital_card_url": "/api/v1/insurance/policies/pol_001/card"
  },
  "payment": {
    "transaction_id": "txn_abc123",
    "amount": 1625.00,
    "status": "approved",
    "next_payment_date": "2026-05-01"
  },
  "created_at": "2026-03-23T10:30:00Z"
}
```

**Data Model**:
```
InsuranceApplication (DOM)
  - application_id: UUID (PK)
  - user_id: UUID (FK)
  - quote_id: UUID (FK)
  - quote_request_id: UUID (FK)
  - provider_id: UUID (FK)
  - status: Enum(PENDING, PAYMENT_PROCESSING, CONFIRMING_WITH_PROVIDER,
                 POLICY_ISSUED, PAYMENT_FAILED, PROVIDER_REJECTED, CANCELLED)
  - insured_data: JSONB (encrypted)
  - beneficiary_data: JSONB
  - payment_method: Enum(CREDIT_CARD, DEBIT_CARD, BANK_TRANSFER, OXXO)
  - payment_frequency: Enum(MENSUAL, TRIMESTRAL, SEMESTRAL, ANUAL)
  - created_at: DateTime
  - updated_at: DateTime

InsurancePolicy (DOM)
  - policy_id: UUID (PK)
  - application_id: UUID (FK)
  - provider_id: UUID (FK)
  - policy_number: String(50) UNIQUE
  - provider_policy_reference: String(100)
  - coverage_type: Enum(BASICA, AMPLIA, PREMIUM)
  - insured_value: Decimal(14,2)
  - annual_premium: Decimal(12,2)
  - deductible_percentage: Decimal(5,2)
  - effective_from: Date
  - effective_to: Date
  - status: Enum(ACTIVE, CANCELLED, EXPIRED, SUSPENDED)
  - coverages: JSONB
  - document_s3_key: String(255)
  - card_s3_key: String(255)
  - created_at: DateTime
  - updated_at: DateTime

InsurancePayment (DOM)
  - payment_id: UUID (PK)
  - policy_id: UUID (FK)
  - transaction_id: String(100)
  - amount: Decimal(12,2)
  - currency: String(3) default 'MXN'
  - status: Enum(PENDING, APPROVED, DECLINED, REFUNDED)
  - payment_method: String(20)
  - payment_date: DateTime
  - next_payment_date: Date
  - gateway_response: JSONB
  - created_at: DateTime
```

**Component Structure**:
```
svc-ins/
  domain/
    models/insurance_application.py
    models/insurance_policy.py
    models/insurance_payment.py
    services/policy_issuance_service.py
    services/payment_service.py
    events/policy_issued_event.py
  application/
    use_cases/apply_insurance_use_case.py
    use_cases/get_policy_use_case.py
    use_cases/download_policy_document_use_case.py
    dto/apply_insurance_request.py
    dto/apply_insurance_response.py
    validators/application_validator.py
  infrastructure/
    repositories/application_repository.py
    repositories/policy_repository.py
    repositories/payment_repository.py
    payment_gateway/
      payment_gateway_port.py
      stripe_payment_adapter.py
      conekta_payment_adapter.py
    document/
      policy_document_generator.py
      digital_card_generator.py
      s3_document_storage.py
  api/
    routes/application_routes.py
    routes/policy_routes.py
    schemas/application_schema.py
```

#### Acceptance Criteria

1. **AC-01**: POST /api/v1/insurance/apply requires valid JWT; unauthenticated requests return 401.
2. **AC-02**: The system validates that quote_id exists, belongs to the authenticated user's quote_request, and is not expired (valid_until > now); expired quotes return 410 Gone with message "Quote has expired, please request a new quote".
3. **AC-03**: Insured data validation: CURP format validated (18 chars), RFC format validated (12-13 chars), phone E.164 format, email RFC 5322, address with all required fields; invalid fields return 422.
4. **AC-04**: Payment is processed first: the system charges the first period amount (monthly/quarterly/semi-annual/annual based on frequency) via the payment gateway (Stripe/Conekta); if payment fails, return 402 with gateway error message and do not proceed to policy issuance.
5. **AC-05**: After successful payment, the system calls the provider's confirm_policy adapter method with insured data and quote reference; if the provider confirms, an InsurancePolicy record is created with status ACTIVE.
6. **AC-06**: If the provider rejects the policy (e.g., additional underwriting check fails), the payment is refunded automatically, status is set to PROVIDER_REJECTED, and the user is notified via SVC-NTF.
7. **AC-07**: Upon successful policy issuance, a PDF policy document is generated with: policy number, insured details, vehicle details, coverage summary, premium breakdown, terms and conditions; the PDF is stored in S3 and accessible via policy_document_url.
8. **AC-08**: A digital insurance card is generated (PNG/PDF) with: policy number, insured name, vehicle plate/VIN, coverage type, effective dates, provider logo, QR code linking to policy verification; stored in S3 and accessible via digital_card_url.
9. **AC-09**: A confirmation notification is sent via SVC-NTF to the user's email (with policy PDF attached) and in-app notification; if WhatsApp is enabled in preferences, a WhatsApp message with digital card is also sent.
10. **AC-10**: The response returns 201 with application_id, policy details, and payment transaction details; all dates and amounts are clearly presented.
11. **AC-11**: A user cannot apply for the same quote twice; duplicate quote_id submissions return 409 Conflict.
12. **AC-12**: Insured personal data (CURP, RFC, address) is encrypted at rest using AES-256-GCM before storage; encryption keys managed via AWS KMS.
13. **AC-13**: The entire operation (payment + provider confirmation + policy creation + document generation) is wrapped in a saga pattern; if any step fails after payment, the payment is refunded and the user is informed of the specific failure.

#### Definition of Done
- Endpoint implemented with full validation and saga pattern
- Payment gateway integration tested with sandbox
- Policy document PDF generation verified
- Digital card generation verified
- Notification integration with SVC-NTF tested
- Unit tests >= 95% coverage
- Integration test: full flow from apply to policy download
- Code reviewed and merged to develop

#### Technical Notes
- Use saga pattern (not distributed transaction) for the multi-step process
- Payment gateway abstraction allows switching between Stripe and Conekta
- PDF generation via `reportlab` or `weasyprint` for policy documents
- Digital card via `Pillow` for image generation
- S3 pre-signed URLs for secure document download (1h expiry)

#### Dependencies
- US-1 (Quotes must exist)
- Payment gateway (Stripe/Conekta) for payment processing
- AWS S3 for document storage
- AWS KMS for encryption
- SVC-NTF for notifications
- SVC-PUR for linking insurance to vehicle purchase

---

### US-4: [MKT-FE-019][FE-FEAT-INS] Cotizador Visual de Seguros

**Description**:
Build an interactive insurance quoting form in Angular 18 that collects vehicle and driver information via a streamlined quick-form experience, displays coverage type options as selectable cards with icons and descriptions, shows loading states while quotes arrive from providers, and pre-selects popular coverage options. The component is designed for quick engagement with minimal required inputs.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-INS (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/insurance/
  quote-form/
    insurance-quote-form.component.ts
    insurance-quote-form.component.html
    insurance-quote-form.component.spec.ts
  coverage-card/
    coverage-type-card.component.ts
    coverage-type-card.component.html
  quote-loading/
    quote-loading.component.ts
    quote-loading.component.html
  services/
    insurance-quote.service.ts
  models/
    quote-request.model.ts
    coverage-type.model.ts
  state/
    insurance-quote.store.ts
```

**Signals-Based State**:
```typescript
// insurance-quote.store.ts
@Injectable({ providedIn: 'root' })
export class InsuranceQuoteStore {
  readonly vehicleData = signal<VehicleFormData | null>(null);
  readonly driverData = signal<DriverFormData | null>(null);
  readonly selectedCoverages = signal<CoverageType[]>(['amplia']);
  readonly paymentFrequency = signal<PaymentFrequency>('mensual');
  readonly isLoading = signal<boolean>(false);
  readonly quoteRequestId = signal<string | null>(null);
  readonly loadingProgress = signal<number>(0);
  readonly providersTotal = signal<number>(0);
  readonly providersResponded = signal<number>(0);

  readonly progressPercentage = computed(() =>
    this.providersTotal() > 0
      ? (this.providersResponded() / this.providersTotal()) * 100
      : 0
  );
}
```

**Coverage Card Layout**:
```html
<!-- Coverage type cards -->
<div class="grid grid-cols-1 md:grid-cols-3 gap-4">
  @for (coverage of coverageTypes; track coverage.id) {
    <button
      class="relative p-6 rounded-2xl border-2 transition-all duration-300
             text-left hover:shadow-lg"
      [class]="coverage.id === selectedCoverage()
        ? 'border-blue-600 bg-blue-50 shadow-md'
        : 'border-gray-200 bg-white hover:border-blue-300'"
      (click)="selectCoverage(coverage.id)">

      @if (coverage.popular) {
        <span class="absolute -top-3 left-4 px-3 py-1 bg-orange-500
                     text-white text-xs font-bold rounded-full">
          Mas popular
        </span>
      }

      <div class="text-3xl mb-3">{{ coverage.icon }}</div>
      <h3 class="text-lg font-semibold mb-2">{{ coverage.label }}</h3>
      <p class="text-sm text-gray-500 mb-4">{{ coverage.description }}</p>

      <ul class="space-y-2">
        @for (feature of coverage.features; track feature) {
          <li class="flex items-center gap-2 text-sm">
            <span class="text-green-500">OK</span>
            <span>{{ feature }}</span>
          </li>
        }
      </ul>
    </button>
  }
</div>
```

#### Acceptance Criteria

1. **AC-01**: The quote form is divided into 2 sections: (1) Vehicle + Driver data (compact form), (2) Coverage selection cards; if the user arrives from a vehicle detail page, vehicle data is pre-populated and section 1 is collapsed showing only a summary.
2. **AC-02**: Vehicle section collects: brand (searchable dropdown), model (filtered by brand), year (filtered by model), version (filtered by year + model), license_plate (optional), usage (particular/commercial dropdown); if vehicle_id is available, all fields auto-fill from SVC-VEH data.
3. **AC-03**: Driver section collects: date_of_birth (date picker, age 18-85), gender (M/F radio), zip_code (5 digits, auto-fills state), years_driving (numeric, 0-70), claims_last_3_years (numeric, 0-10, default 0).
4. **AC-04**: Three coverage type cards are displayed: (a) Basica - shield icon, "Responsabilidad Civil", features: RC obligatoria, defensa legal; (b) Amplia - car icon, "Cobertura Amplia", features: RC + robo total + danos materiales + asistencia vial, badge "Mas popular"; (c) Premium - star icon, "Cobertura Premium", features: Amplia + gastos medicos + auto sustituto + cobertura en USA/Canada.
5. **AC-05**: "Amplia" coverage is pre-selected by default with visual emphasis; multiple coverages can be selected simultaneously to compare quotes across coverage levels.
6. **AC-06**: A "Cotizar" button submits the form; validation runs on all required fields; errors appear inline below each field in red text; the button is disabled while loading.
7. **AC-07**: On submit, a loading state is displayed with: animated provider logos appearing one by one, a progress bar showing "X of Y aseguradoras respondieron", estimated time remaining, and a skeleton preview of where quote cards will appear.
8. **AC-08**: Payment frequency selector (mensual/trimestral/semestral/anual) is available and defaults to "mensual"; changing it recalculates displayed premiums without a new API call (simple division from annual premium).
9. **AC-09**: When quotes arrive, the loading state transitions smoothly to the quote results (comparison view - US-5); the transition uses a cross-fade animation.
10. **AC-10**: Form data persists in InsuranceQuoteStore signals; navigating away and returning restores the form state without re-fetching.
11. **AC-11**: The form is responsive: on mobile, all fields stack vertically and coverage cards scroll horizontally; on desktop, vehicle and driver fields are in a 2-column grid and coverage cards are in a 3-column grid.
12. **AC-12**: Brand/model/year dropdowns are populated from SVC-VEH catalog endpoint and cached locally for 1 hour; typing in the brand field filters options with fuzzy matching.

#### Definition of Done
- Standalone component with signals-based state
- Tailwind CSS v4 responsive design
- Coverage card selection with animations
- Loading state with progress indicator
- Unit tests >= 90% coverage
- E2E test: fill form -> submit -> verify loading state
- Code reviewed and merged to develop

#### Technical Notes
- Use Angular 18 standalone components
- Searchable dropdowns via Angular CDK Combobox or custom implementation
- Vehicle catalog can be large; use virtual scrolling for dropdown lists
- Loading animation can use CSS keyframes for provider logo reveal
- Pre-select coverage from URL query param if coming from marketing landing page

#### Dependencies
- US-1 (Quote API)
- SVC-VEH catalog endpoint for brand/model/year/version
- Shared form components (inputs, dropdowns, date picker)

---

### US-5: [MKT-FE-020][FE-FEAT-INS] Comparador de Ofertas de Seguros

**Description**:
Build an insurance quote comparison component that displays quotes from multiple providers in a feature-rich comparison table. The table shows providers as rows and coverage features as columns, with included/excluded indicators, monthly and annual pricing, provider ratings, deductible amounts, and highlight badges for "Best value" and "Best coverage". Users can sort, filter, and select a quote to proceed to contracting.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-INS (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/insurance/
  comparison/
    insurance-comparison.component.ts
    insurance-comparison.component.html
    insurance-comparison.component.spec.ts
  comparison-row/
    comparison-row.component.ts
    comparison-row.component.html
  coverage-detail-modal/
    coverage-detail-modal.component.ts
    coverage-detail-modal.component.html
  services/
    comparison.service.ts
  state/
    comparison.store.ts
```

**Comparison Table Layout**:
```html
<div class="overflow-x-auto">
  <table class="w-full border-collapse">
    <thead>
      <tr class="bg-gray-50">
        <th class="sticky left-0 bg-gray-50 p-4 text-left min-w-[200px]">
          Aseguradora
        </th>
        @for (coverage of coverageColumns; track coverage) {
          <th class="p-4 text-center min-w-[150px] cursor-pointer
                     hover:bg-gray-100"
              (click)="sortBy(coverage)">
            {{ coverage.label }}
            @if (sortColumn() === coverage.id) {
              <span>{{ sortDirection() === 'asc' ? ' ^' : ' v' }}</span>
            }
          </th>
        }
      </tr>
    </thead>
    <tbody>
      @for (quote of sortedQuotes(); track quote.quote_id) {
        <tr class="border-b hover:bg-blue-50 transition-colors"
            [class.ring-2]="quote.is_best_price"
            [class.ring-green-400]="quote.is_best_price">
          <!-- Provider info -->
          <td class="sticky left-0 bg-white p-4">
            <div class="flex items-center gap-3">
              <img [src]="quote.provider_logo_url" class="w-10 h-10 rounded"
                   [alt]="quote.provider_name" />
              <div>
                <p class="font-semibold">{{ quote.provider_name }}</p>
                <div class="flex items-center gap-1 text-sm text-yellow-500">
                  <span>*</span>
                  <span>{{ quote.provider_rating }}</span>
                </div>
              </div>
              @if (quote.is_best_price) {
                <span class="ml-2 px-2 py-1 bg-green-100 text-green-800
                             text-xs font-bold rounded-full">
                  Mejor precio
                </span>
              }
            </div>
          </td>
          <!-- Coverage columns -->
          @for (coverage of coverageColumns; track coverage) {
            <td class="p-4 text-center">
              @if (isCoverageIncluded(quote, coverage)) {
                <span class="text-green-600 font-bold">Si</span>
              } @else {
                <span class="text-gray-300">No</span>
              }
            </td>
          }
        </tr>
      }
    </tbody>
  </table>
</div>
```

**Store**:
```typescript
@Injectable({ providedIn: 'root' })
export class ComparisonStore {
  readonly quotes = signal<InsuranceQuote[]>([]);
  readonly sortColumn = signal<string>('monthly_premium');
  readonly sortDirection = signal<'asc' | 'desc'>('asc');
  readonly filterCoverage = signal<CoverageType | null>(null);
  readonly selectedQuoteId = signal<string | null>(null);

  readonly sortedQuotes = computed(() => {
    let filtered = this.quotes();
    if (this.filterCoverage()) {
      filtered = filtered.filter(q => q.coverage_type === this.filterCoverage());
    }
    return [...filtered].sort((a, b) => {
      const val = a[this.sortColumn()] - b[this.sortColumn()];
      return this.sortDirection() === 'asc' ? val : -val;
    });
  });

  readonly bestPriceQuote = computed(() =>
    [...this.quotes()].sort((a, b) => a.annual_premium - b.annual_premium)[0] ?? null
  );
  readonly bestCoverageQuote = computed(() =>
    [...this.quotes()].sort((a, b) =>
      b.coverages.filter(c => c.included).length -
      a.coverages.filter(c => c.included).length
    )[0] ?? null
  );
}
```

#### Acceptance Criteria

1. **AC-01**: The comparison table displays all received quotes as rows; columns show standardized coverage features: Responsabilidad Civil, Danos Materiales, Robo Total, Gastos Medicos, Asistencia Vial, Defensa Legal, Auto Sustituto; plus pricing columns: monthly premium, annual premium, deductible %.
2. **AC-02**: Each coverage cell shows a green checkmark (included) or gray dash (excluded); hovering over an included coverage shows a tooltip with sum_insured amount and deductible details.
3. **AC-03**: Provider column (sticky left) shows: logo, name, star rating (1-5), and badge indicators ("Best price" in green, "Best coverage" in blue).
4. **AC-04**: Monthly and annual prices are displayed in both columns; the user can toggle between showing monthly or annual as the primary price; the primary price is displayed in large bold text.
5. **AC-05**: Clicking any column header sorts the table: clicking price sorts by premium (ascending first click, descending second), clicking a coverage column sorts by whether that coverage is included (included first), clicking provider sorts alphabetically.
6. **AC-06**: A coverage type filter (tabs or toggle) at the top allows filtering quotes by: All, Basica, Amplia, Premium; the active filter tab has a count badge showing number of quotes.
7. **AC-07**: Each row has an "Expand" button that reveals a detail section below the row showing: full list of coverages with descriptions, all exclusions, commission details, and terms/conditions summary.
8. **AC-08**: Each row has a "Seleccionar" button; clicking it highlights the row and stores the selected quote_id; a sticky bottom bar appears showing the selected quote summary and a "Continuar a contratacion" CTA button.
9. **AC-09**: A "Best value" algorithm badge appears on the quote with the best ratio of (included coverages count) / (annual_premium); this is separate from "Best price" (cheapest) and "Best coverage" (most inclusions).
10. **AC-10**: On mobile (< 768px), the table transforms into a card-based layout: each provider is a card showing key metrics, with an expand button for full coverage details; cards are swipeable horizontally.
11. **AC-11**: The table handles edge cases: no quotes returned (empty state with "No se encontraron cotizaciones" message and retry button), single quote (comparison note hidden), all same price (no "Best price" badge).
12. **AC-12**: An "Export comparison" button generates a PDF summary of all quotes for offline review; the PDF includes all providers, coverages, prices, and the date of the comparison.

#### Definition of Done
- Comparison table component with sorting, filtering, and badges
- Mobile card-based alternative layout
- Tooltip coverage details
- Sticky selection bar with CTA
- Unit tests >= 90% coverage
- E2E test: sort by price, filter by coverage, select quote, verify CTA
- Cross-browser tested (Chrome, Firefox, Safari)
- Code reviewed and merged to develop

#### Technical Notes
- Use CSS `position: sticky` for the left provider column and bottom selection bar
- Table should use virtual scrolling if more than 20 quotes (unlikely but safe)
- PDF export via `jsPDF` or server-side generation endpoint
- Consider precomputing "best value" on the backend for consistency

#### Dependencies
- US-1 (Quotes data)
- US-4 (Quote form navigates to comparison on completion)
- Shared UI components (badges, tooltips, modals)

---

### US-6: [MKT-FE-021][FE-FEAT-INS] Flujo de Contratacion de Seguro

**Description**:
Build the insurance contracting flow as a multi-step component in Angular 18. The flow includes: coverage summary review, additional insured data collection, payment method selection and processing, and confirmation with policy document download. This is the final step after selecting a quote from the comparison view.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-INS (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/insurance/
  contracting/
    insurance-contracting.component.ts
    insurance-contracting.component.html
  contracting-steps/
    coverage-summary-step.component.ts
    insured-data-step.component.ts
    payment-step.component.ts
    confirmation-step.component.ts
  services/
    insurance-contracting.service.ts
  state/
    contracting.store.ts
```

**Contracting Store**:
```typescript
@Injectable({ providedIn: 'root' })
export class ContractingStore {
  readonly selectedQuote = signal<InsuranceQuote | null>(null);
  readonly currentStep = signal<number>(1);
  readonly insuredData = signal<InsuredData | null>(null);
  readonly beneficiaryData = signal<BeneficiaryData | null>(null);
  readonly paymentMethod = signal<PaymentMethod | null>(null);
  readonly isProcessing = signal<boolean>(false);
  readonly policy = signal<InsurancePolicy | null>(null);
  readonly error = signal<string | null>(null);

  readonly totalSteps = signal<number>(4);
  readonly progress = computed(() =>
    (this.currentStep() / this.totalSteps()) * 100
  );
}
```

#### Acceptance Criteria

1. **AC-01**: The contracting flow has 4 steps: (1) Coverage Summary, (2) Insured Data, (3) Payment, (4) Confirmation; a progress bar and step indicator track current position.
2. **AC-02**: Step 1 (Coverage Summary) displays the selected quote details in a read-only format: provider name + logo, coverage type, all included coverages with sums insured, all exclusions, premium breakdown (annual, payment frequency, per-period amount), deductible, effective dates; an "Edit selection" link returns to the comparison view.
3. **AC-03**: Step 2 (Insured Data) collects: full_name, CURP (validated), RFC (validated), date_of_birth, email, phone, full address; if user profile already has this data (from SVC-USR), fields are pre-populated; a beneficiary section collects: name, relationship (dropdown), phone.
4. **AC-04**: Step 3 (Payment) shows payment method options: credit card (Visa/MC/Amex), debit card, bank transfer (SPEI), OXXO; for card payments, a secure card form is embedded (Stripe Elements or Conekta tokenizer); for SPEI, CLABE and reference number are displayed; for OXXO, a payment reference barcode is generated.
5. **AC-05**: On "Pay" button click in Step 3, the system calls POST /insurance/apply; during processing, a loading overlay shows "Procesando pago..." then "Confirmando poliza con aseguradora..."; the button is disabled to prevent double submission.
6. **AC-06**: Step 4 (Confirmation) displays: success message with confetti animation, policy number, coverage summary, next payment date, two download buttons (policy PDF document, digital insurance card), and share buttons (email, WhatsApp).
7. **AC-07**: If payment fails, Step 3 shows an inline error message with the specific reason (e.g., "Tarjeta declinada - fondos insuficientes") and allows retrying with a different payment method without losing entered data.
8. **AC-08**: If provider confirmation fails after payment, a special error state shows "Pago procesado, confirmacion pendiente" with a reference number and support contact; the payment is NOT refunded automatically from the frontend (backend saga handles this).
9. **AC-09**: The policy PDF download triggers a GET to /insurance/policies/{id}/document with JWT auth; the digital card download triggers GET /insurance/policies/{id}/card; both open in a new tab or download depending on device.
10. **AC-10**: The flow is responsive: on mobile, all steps stack vertically; payment card form adapts to mobile keyboard; confirmation page is scroll-friendly with large tap targets.
11. **AC-11**: Navigation: "Back" button works on all steps; browser back button is intercepted with a confirmation dialog on steps 2-3 (to prevent accidental data loss); after successful policy issuance (step 4), back navigation is disabled.
12. **AC-12**: An inactivity timeout of 15 minutes on the payment step triggers a warning modal ("Su sesion esta por expirar") with "Continue" and "Cancel" options; if no action in 2 more minutes, the flow is cancelled and the user returns to the comparison view.

#### Definition of Done
- 4-step contracting flow implemented with standalone components
- Payment gateway integration (Stripe Elements / Conekta) working in sandbox
- Policy document download verified
- Error handling for payment and provider failures
- Unit tests >= 90% coverage
- E2E test: complete contracting flow from coverage summary to policy download
- Code reviewed and merged to develop

#### Technical Notes
- Stripe Elements or Conekta widget must be loaded dynamically (not in initial bundle)
- Card tokenization happens client-side; only the token is sent to the backend
- Consider using `@defer` for the payment widget to reduce initial load
- Confirmation step should trigger analytics event for conversion tracking
- Digital card can be added to Apple Wallet / Google Pay if supported

#### Dependencies
- US-3 (Insurance application API)
- US-5 (Comparison view provides selected quote)
- Payment gateway SDK (Stripe.js / Conekta.js)
- Shared step/progress components

---

### US-7: [MKT-INT-005][WRK-INS] Integracion Bidireccional con Aseguradoras

**Description**:
Implement the WRK-INS worker that handles bidirectional communication with insurance providers. This includes: processing outbound quote requests from SQS, receiving webhook callbacks for policy status updates, mapping data to AMIS (Asociacion Mexicana de Instituciones de Seguros) standards, managing TLS certificates for provider authentication, encrypting sensitive data in transit, and maintaining sandbox environments per provider for testing.

**Microservice**: WRK-INS (Worker)
**Layer**: INF + APP

#### Technical Context

**Worker Architecture**:
```
wrk-ins/
  consumers/
    quote_consumer.py          # SQS consumer for outbound quotes
    policy_consumer.py         # SQS consumer for policy confirmations
    expiry_consumer.py         # Scheduled check for expired quotes
  webhooks/
    webhook_routes.py          # Flask routes for provider callbacks
    webhook_validator.py       # Signature/cert validation per provider
    webhook_mapper.py          # Map provider events to internal format
  processors/
    quote_processor.py         # Orchestrates quote request to provider
    policy_processor.py        # Orchestrates policy confirmation
    renewal_processor.py       # Handles policy renewal reminders
  amis/
    amis_formatter.py          # AMIS standard data formatting
    amis_vehicle_catalog.py    # AMIS vehicle code lookups
    amis_validator.py          # Validate AMIS compliance
  certificates/
    cert_manager.py            # TLS client cert management
    cert_store.py              # Secure cert storage (AWS Secrets Manager)
  encryption/
    payload_encryptor.py       # Encrypt sensitive fields
  sandbox/
    sandbox_simulator.py       # Simulate provider responses
    sandbox_config.py          # Per-provider sandbox settings
  config/
    worker_config.py
```

**Webhook Endpoint**:
```
POST /webhooks/insurance/{provider_code}/event
Content-Type: application/json
X-Provider-Certificate: <client_cert_fingerprint>
```

**Webhook Event Types**:
```json
{
  "event_type": "policy_issued",
  "provider_reference": "SA-POL-2026-00789",
  "our_reference": "ins_app_001",
  "policy_data": {
    "policy_number": "SA-POL-2026-00789",
    "effective_from": "2026-04-01",
    "effective_to": "2027-03-31",
    "document_url": "https://provider.com/docs/SA-POL-2026-00789.pdf"
  },
  "timestamp": "2026-03-23T10:35:00Z"
}
```

**Data Model**:
```
ProviderWebhookLog (INF)
  - log_id: UUID (PK)
  - provider_id: UUID (FK)
  - event_type: String(50)
  - direction: Enum(INBOUND, OUTBOUND)
  - endpoint: String(255)
  - headers: JSONB
  - payload: JSONB (encrypted)
  - response_status: Integer
  - processing_status: Enum(RECEIVED, PROCESSED, FAILED, IGNORED)
  - error_message: Text
  - duration_ms: Integer
  - created_at: DateTime

ProviderCertificate (INF)
  - cert_id: UUID (PK)
  - provider_id: UUID (FK)
  - cert_type: Enum(CLIENT_CERT, CA_CERT, WEBHOOK_SIGNING)
  - secrets_manager_arn: String(255)
  - fingerprint: String(64)
  - issued_at: DateTime
  - expires_at: DateTime
  - is_active: Boolean default true
  - created_at: DateTime
```

#### Acceptance Criteria

1. **AC-01**: WRK-INS SQS consumer polls queue `ins-quote-outbound` and processes quote request messages; each message contains vehicle data, driver data, coverage type, and provider_id; the consumer uses AdapterFactory (US-2) to get the correct provider adapter.
2. **AC-02**: After successful quote submission to a provider, the response is mapped to a standardized InsuranceQuote record using coverage mappings from ProviderCoverageMapping; the quote is persisted and a Redis Pub/Sub message notifies the frontend.
3. **AC-03**: Webhook endpoint POST /webhooks/insurance/{provider_code}/event validates the provider's identity via client certificate fingerprint or HMAC signature; invalid credentials return 401 and are logged.
4. **AC-04**: Webhook events are processed based on event_type: "policy_issued" creates/updates InsurancePolicy, "policy_cancelled" updates status, "policy_renewed" creates renewal record, "claim_reported" is logged for the admin dashboard.
5. **AC-05**: All outbound data is formatted according to AMIS standards: vehicle identification uses AMIS catalog codes (marca, tipo, modelo year), personal data follows AMIS person schema, coverage types map to AMIS coverage catalog codes.
6. **AC-06**: The AMIS vehicle catalog is maintained locally (seeded from AMIS annual release) with mapping: (brand, model, year, version) -> amis_clave; lookup failures are logged and fall back to free-text vehicle description.
7. **AC-07**: TLS client certificates for mutual authentication are stored in AWS Secrets Manager; the cert_manager loads and caches certificates at worker startup; expiring certificates (< 30 days) trigger alerts via SVC-NTF to the operations team.
8. **AC-08**: Sensitive data (driver name, CURP, license, address) in outbound requests is encrypted with provider-specific public keys where required; encryption uses the provider's preferred algorithm (RSA-OAEP or AES-256-GCM).
9. **AC-09**: Quote expiry checker runs every hour; it marks quotes where valid_until < now as EXPIRED and publishes expiry events.
10. **AC-10**: Sandbox mode per provider: when is_sandbox is true, the SandboxSimulator generates realistic quote responses with configurable parameters (price range, response time, coverage variations, approval/rejection ratios).
11. **AC-11**: Failed quote requests are retried up to 3 times with exponential backoff (5s, 15s, 45s); after exhaustion, the quote is marked as ERROR with provider_id and error details; dead-letter queue captures permanently failed messages.
12. **AC-12**: All webhook and API interactions are logged in ProviderWebhookLog with encrypted payloads; logs retained for 90 days for compliance.
13. **AC-13**: Graceful shutdown: on SIGTERM, stop polling for new messages, wait up to 30 seconds for in-flight processing, then exit cleanly; no message loss during deployment.

#### Definition of Done
- SQS consumers for quotes and policies implemented
- Webhook endpoint with certificate validation
- AMIS formatter with vehicle catalog integration
- Certificate management with expiry alerts
- Sandbox simulator with configurable responses
- Unit tests >= 95% coverage
- Integration tests with localstack (SQS, Secrets Manager)
- Code reviewed and merged to develop

#### Technical Notes
- Use mTLS (mutual TLS) for providers that require client certificate authentication
- AMIS vehicle catalog is typically a large Excel/CSV; import as a PostgreSQL table with indexes on brand+model+year
- Some providers require XML (SOAP) while others use REST/JSON; adapters abstract this
- Consider using Celery with SQS broker as alternative to raw boto3 consumer
- Dead-letter queue analysis should be part of weekly ops review

#### Dependencies
- US-2 (Provider adapters)
- US-1 (Quote requests from SVC-INS)
- US-3 (Policy confirmation flow)
- AWS SQS, Secrets Manager
- AMIS vehicle catalog data
- SVC-NTF for certificate expiry alerts

---

## Cross-Cutting Concerns

### Security
- All personal data encrypted at rest (AES-256-GCM) and in transit (TLS 1.3)
- mTLS with provider certificates where required
- CURP, RFC never stored in plain text
- Payment card data handled by PCI-compliant payment gateway (never touches our servers)
- Rate limiting: 5 quote requests/min per user

### Observability
- Structured logging with correlation_id across SVC-INS and WRK-INS
- Metrics: quotes_requested, quotes_returned, policies_issued, conversion_rate per provider
- Alerts: circuit breaker state changes, high error rates, certificate expiry warnings
- Distributed tracing with OpenTelemetry

### Performance
- Quote aggregation: < 120s total, first results visible within 10s
- Policy issuance: < 30s end-to-end (payment + confirmation)
- Redis cache for quotes reduces repeat requests by ~40%

### Compliance
- AMIS data standards for insurance data exchange
- CNSF (Comision Nacional de Seguros y Fianzas) compliance
- LFPDPPP (privacy law) for personal data
- PCI DSS compliance via tokenized payments

---

## Epic Dependencies Graph

```
EP-008 Dependencies:
  SVC-VEH (EP-003) --> Vehicle data and catalog
  SVC-USR (EP-002) --> User profile for pre-population
  SVC-PUR (EP-004) --> Link insurance to vehicle purchase
  SVC-NTF (EP-010) --> Notifications for quotes and policies
  SVC-ADM (EP-009) --> Provider management
  EP-007 (Financing) --> Insurance often bundled with financing
```

## Release Plan

| Sprint | Stories | Focus |
|--------|---------|-------|
| Sprint 6 | US-1, US-2, US-4 | Quote API + Adapters + Frontend Form |
| Sprint 7 | US-3, US-5, US-6, US-7 | Contracting + Comparison + Worker |
| Sprint 8 | Polish, E2E testing, Provider onboarding | Production readiness |
