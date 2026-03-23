# [MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento

**Sprint**: 5-7
**Priority**: High
**Epic Owner**: Tech Lead - SVC-FIN
**Stakeholders**: Product, Finance Partnerships, Frontend Lead, Compliance
**Estimated Effort**: 89 story points

---

## Epic Overview

This epic delivers a complete credit financing experience for vehicle purchases. Users can simulate credit scenarios with interactive calculators, submit formal credit applications that fan-out to multiple financial institutions simultaneously, and receive real-time offers via WebSocket/SSE. The system integrates bidirectionally with financial institutions (financieras) through adapters that normalize heterogeneous APIs (REST/SOAP) behind a hexagonal port interface.

### Business Goals
- Enable users to estimate monthly payments before committing to a purchase
- Aggregate credit offers from multiple financieras to maximize approval rates
- Reduce time-to-offer from days to minutes through real-time evaluation
- Provide transparency on CAT, total cost, and amortization schedules
- Comply with CNBV data standards for financial data exchange

### Architecture Context
- **Primary Service**: SVC-FIN (:5015)
- **Supporting Services**: SVC-VEH (:5012), SVC-KYC (:5014), SVC-USR (:5011), SVC-NTF (:5017)
- **Worker**: WRK-FIN (async financiera communication)
- **Message Broker**: SQS for fan-out to financieras, SNS for status updates
- **Cache**: Redis 7 for rate caching and session state
- **Database**: PostgreSQL 15 for applications, offers, amortization data

---

## User Stories

---

### US-1: [MKT-BE-017][SVC-FIN-API] Calculadora de Credito

**Description**:
Implement a credit calculator API endpoint that computes monthly payments, CAT (Costo Anual Total), total payment amount, and full amortization tables for vehicle financing. The calculator must support multiple scenario generation (12/24/36/48/60 month terms) in a single request and apply institution-specific reference rates. This is a stateless computation endpoint that does not require authentication for basic calculations but logs usage for analytics.

**Microservice**: SVC-FIN (:5015)
**Layer**: API (routes) + APP (application/use_cases) + DOM (domain/models)
**Worker**: None (synchronous computation)

#### Technical Context

**Endpoint**:
```
POST /api/v1/financing/calculate
Content-Type: application/json
Authorization: Bearer <jwt> (optional - enriches with user profile data if present)
```

**Request Schema**:
```json
{
  "vehicle_price": 450000.00,
  "down_payment_percentage": 20.0,
  "down_payment_amount": null,
  "term_months": [12, 24, 36, 48, 60],
  "reference_rate": null,
  "insurance_included": true,
  "vehicle_id": "veh_abc123",
  "institution_id": null
}
```

**Response Schema**:
```json
{
  "calculation_id": "calc_7f8a9b",
  "vehicle_price": 450000.00,
  "down_payment": 90000.00,
  "down_payment_percentage": 20.0,
  "financed_amount": 360000.00,
  "scenarios": [
    {
      "term_months": 36,
      "annual_rate": 12.5,
      "monthly_rate": 1.0417,
      "cat": 16.2,
      "monthly_payment": 12045.67,
      "total_payment": 433644.12,
      "total_interest": 73644.12,
      "insurance_monthly": 850.00,
      "total_monthly_with_insurance": 12895.67,
      "amortization_table": [
        {
          "month": 1,
          "opening_balance": 360000.00,
          "payment": 12045.67,
          "principal": 8295.67,
          "interest": 3750.00,
          "closing_balance": 351704.33
        }
      ]
    }
  ],
  "metadata": {
    "calculated_at": "2026-03-23T10:00:00Z",
    "rates_source": "banxico_reference",
    "disclaimer": "Calculo estimado. Tasa sujeta a aprobacion crediticia."
  }
}
```

**Data Model**:
```
CreditCalculation (DOM)
  - calculation_id: UUID (PK)
  - vehicle_id: UUID (FK, nullable)
  - user_id: UUID (FK, nullable)
  - vehicle_price: Decimal(12,2)
  - down_payment_percentage: Decimal(5,2)
  - down_payment_amount: Decimal(12,2)
  - financed_amount: Decimal(12,2)
  - insurance_included: Boolean
  - created_at: DateTime
  - ip_address: String(45)

CreditScenario (DOM)
  - scenario_id: UUID (PK)
  - calculation_id: UUID (FK)
  - term_months: Integer
  - annual_rate: Decimal(6,4)
  - monthly_rate: Decimal(8,6)
  - cat: Decimal(6,2)
  - monthly_payment: Decimal(12,2)
  - total_payment: Decimal(14,2)
  - total_interest: Decimal(14,2)
  - insurance_monthly: Decimal(10,2)

AmortizationEntry (DOM)
  - entry_id: UUID (PK)
  - scenario_id: UUID (FK)
  - month_number: Integer
  - opening_balance: Decimal(14,2)
  - payment: Decimal(12,2)
  - principal: Decimal(12,2)
  - interest: Decimal(12,2)
  - closing_balance: Decimal(14,2)

ReferenceRate (DOM)
  - rate_id: UUID (PK)
  - institution_id: UUID (FK, nullable)
  - rate_type: Enum(TIIE, FIXED, VARIABLE)
  - annual_rate: Decimal(6,4)
  - effective_from: Date
  - effective_to: Date
  - source: String(50)
  - fetched_at: DateTime
```

**Component Structure (SVC-FIN)**:
```
svc-fin/
  domain/
    models/credit_calculation.py
    models/credit_scenario.py
    models/amortization_entry.py
    models/reference_rate.py
    services/credit_calculator_service.py
    value_objects/money.py
    value_objects/percentage.py
  application/
    use_cases/calculate_credit_use_case.py
    dto/calculate_credit_request.py
    dto/calculate_credit_response.py
    validators/calculation_input_validator.py
  infrastructure/
    repositories/calculation_repository.py
    external/banxico_rate_client.py
    cache/rate_cache.py
  api/
    routes/financing_routes.py
    schemas/calculation_schema.py (Marshmallow)
  config/
    financing_config.py
```

#### Acceptance Criteria

1. **AC-01**: POST /api/v1/financing/calculate accepts vehicle_price (required, > 0, max 50,000,000), down_payment_percentage (0-90%), and term_months array; returns 200 with all requested scenarios computed.
2. **AC-02**: When down_payment_percentage is provided without down_payment_amount, the system computes down_payment_amount = vehicle_price * (down_payment_percentage / 100) and vice versa.
3. **AC-03**: Each scenario includes monthly_payment calculated using the standard French amortization formula: M = P * [r(1+r)^n] / [(1+r)^n - 1], where P = financed amount, r = monthly rate, n = term months.
4. **AC-04**: CAT (Costo Anual Total) is computed per CNBV Circular 21/2009 methodology including commissions, insurance, and IVA on interest; the value is expressed as annual percentage.
5. **AC-05**: Each scenario contains a full amortization_table with one entry per month showing opening_balance, payment, principal, interest, and closing_balance; the final closing_balance is 0.00 (tolerance +/- 0.01).
6. **AC-06**: When reference_rate is null and institution_id is null, the system uses the latest Banxico TIIE 28-day rate from Redis cache (TTL 24h); if cache miss, fetches from Banxico API and caches.
7. **AC-07**: When insurance_included is true, insurance_monthly is estimated as (vehicle_price * 0.04) / 12 and added to total_monthly_with_insurance but kept separate from the credit calculation itself.
8. **AC-08**: Multiple term_months values (e.g., [12, 24, 36, 48, 60]) return one scenario per term in a single response; the response is returned in < 200ms for up to 5 scenarios.
9. **AC-09**: Invalid inputs return 422 with field-level error messages: vehicle_price <= 0, down_payment_percentage > 90 or < 0, empty term_months array, term_months values not in [6,12,18,24,30,36,42,48,54,60,72,84].
10. **AC-10**: Each calculation is persisted to PostgreSQL with a unique calculation_id for analytics; if user is authenticated, user_id is associated.
11. **AC-11**: The response includes metadata.disclaimer text and metadata.rates_source indicating whether Banxico, institution-specific, or user-provided rate was used.
12. **AC-12**: All monetary values in the response use exactly 2 decimal places; rates use up to 4 decimal places.

#### Definition of Done
- Endpoint implemented with Marshmallow request/response validation
- Unit tests for amortization formula with known financial examples (>= 95% coverage)
- Integration test with PostgreSQL for persistence
- Performance test: < 200ms for 5-scenario calculation
- API documentation in OpenAPI 3.0 spec
- Code reviewed and merged to develop

#### Technical Notes
- Use Python `decimal.Decimal` with ROUND_HALF_UP for all financial calculations to avoid floating-point errors
- Amortization formula must handle edge cases: 0% rate (simple division), 100% down payment (no financing needed)
- Cache Banxico rates in Redis with key `rates:banxico:tiie_28d` and TTL 86400s
- Consider pre-computing common scenarios for popular vehicle price ranges

#### Dependencies
- SVC-VEH for vehicle_price validation when vehicle_id is provided
- Banxico API for reference rates (external dependency, cache required)
- Redis 7 for rate caching

---

### US-2: [MKT-BE-018][SVC-FIN-API] Solicitud de Credito Multi-Financiera

**Description**:
Implement the credit application endpoint that receives applicant data, vehicle data, and KYC information, then fans out the application to N financial institutions simultaneously via SQS. The endpoint creates the application record, validates KYC completeness, dispatches messages to each selected financiera queue, and returns a tracking ID. Response aggregation happens asynchronously via WRK-FIN and results are pushed via WebSocket (see US-4).

**Microservice**: SVC-FIN (:5015) + WRK-FIN
**Layer**: API + APP + DOM + INF
**Worker**: WRK-FIN (fan-out dispatch and response aggregation)

#### Technical Context

**Endpoint**:
```
POST /api/v1/financing/apply
Content-Type: application/json
Authorization: Bearer <jwt> (required)
```

**Request Schema**:
```json
{
  "vehicle_id": "veh_abc123",
  "applicant": {
    "full_name": "Juan Perez Lopez",
    "curp": "PELJ850101HDFRPN09",
    "rfc": "PELJ850101AB3",
    "date_of_birth": "1985-01-01",
    "nationality": "mexicana",
    "marital_status": "casado",
    "dependents": 2,
    "education_level": "licenciatura",
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
  "employment": {
    "type": "asalariado",
    "company_name": "Empresa SA de CV",
    "position": "Gerente",
    "monthly_income": 45000.00,
    "seniority_months": 36,
    "employer_phone": "+5215598765432",
    "employer_address": "Polanco, CDMX"
  },
  "references": [
    {
      "name": "Maria Garcia",
      "relationship": "familiar",
      "phone": "+5215511111111"
    },
    {
      "name": "Pedro Sanchez",
      "relationship": "laboral",
      "phone": "+5215522222222"
    }
  ],
  "financing": {
    "down_payment_percentage": 20.0,
    "requested_term_months": 36,
    "target_institutions": ["inst_001", "inst_002", "inst_003"]
  },
  "consents": {
    "bureau_check": true,
    "data_sharing": true,
    "privacy_notice": true,
    "terms_accepted": true
  }
}
```

**Response Schema**:
```json
{
  "application_id": "app_x9y8z7",
  "status": "submitted",
  "submitted_at": "2026-03-23T10:05:00Z",
  "institutions_count": 3,
  "institutions": [
    {
      "institution_id": "inst_001",
      "institution_name": "Banco Nacional",
      "status": "queued",
      "estimated_response_minutes": 15
    },
    {
      "institution_id": "inst_002",
      "institution_name": "Financiera del Sur",
      "status": "queued",
      "estimated_response_minutes": 30
    },
    {
      "institution_id": "inst_003",
      "institution_name": "Credito Facil",
      "status": "queued",
      "estimated_response_minutes": 10
    }
  ],
  "tracking_url": "/financing/applications/app_x9y8z7/status",
  "websocket_url": "wss://api.marketplace.com/financing/evaluate/ws?app=app_x9y8z7"
}
```

**Data Model**:
```
CreditApplication (DOM)
  - application_id: UUID (PK)
  - user_id: UUID (FK)
  - vehicle_id: UUID (FK)
  - status: Enum(DRAFT, SUBMITTED, EVALUATING, COMPLETED, EXPIRED, CANCELLED)
  - applicant_data: JSONB (encrypted)
  - employment_data: JSONB (encrypted)
  - references_data: JSONB (encrypted)
  - down_payment_percentage: Decimal(5,2)
  - requested_term_months: Integer
  - bureau_consent: Boolean
  - data_sharing_consent: Boolean
  - privacy_consent: Boolean
  - submitted_at: DateTime
  - completed_at: DateTime
  - expires_at: DateTime
  - created_at: DateTime
  - updated_at: DateTime

InstitutionApplication (DOM)
  - inst_app_id: UUID (PK)
  - application_id: UUID (FK)
  - institution_id: UUID (FK)
  - status: Enum(QUEUED, SENT, EVALUATING, APPROVED, REJECTED, TIMEOUT, ERROR)
  - sent_at: DateTime
  - response_at: DateTime
  - timeout_at: DateTime
  - external_reference: String(100)
  - request_payload_hash: String(64)
  - response_payload: JSONB (encrypted)
  - error_message: Text
  - retry_count: Integer default 0
  - created_at: DateTime
  - updated_at: DateTime
```

**Component Structure**:
```
svc-fin/
  domain/
    models/credit_application.py
    models/institution_application.py
    events/application_submitted_event.py
    events/institution_response_event.py
    services/application_service.py
  application/
    use_cases/submit_application_use_case.py
    use_cases/check_application_status_use_case.py
    dto/submit_application_request.py
    dto/submit_application_response.py
    validators/application_validator.py
    validators/kyc_completeness_validator.py
  infrastructure/
    repositories/application_repository.py
    messaging/sqs_publisher.py
    messaging/application_fan_out.py
    encryption/field_encryption.py
  api/
    routes/application_routes.py
    schemas/application_schema.py
```

#### Acceptance Criteria

1. **AC-01**: POST /api/v1/financing/apply requires a valid JWT; unauthenticated requests return 401.
2. **AC-02**: The request body is validated: all applicant fields required, CURP format (18 chars alphanumeric), RFC format (12-13 chars), phone E.164, email RFC 5322, zip_code 5 digits; invalid fields return 422 with per-field errors.
3. **AC-03**: At least 2 references are required; each must have name, relationship, and phone; the system rejects if fewer than 2 are provided.
4. **AC-04**: All consent fields (bureau_check, data_sharing, privacy_notice, terms_accepted) must be true; if any is false, return 422 with message indicating which consent is missing.
5. **AC-05**: The system validates that the vehicle_id exists and is in "published" status by calling SVC-VEH; if the vehicle is not available, return 409 with message "Vehicle is not available for financing".
6. **AC-06**: The system validates KYC completeness by calling SVC-KYC for the user; if KYC level is below "basic", return 422 with instructions to complete KYC first.
7. **AC-07**: target_institutions is optional; if omitted, the system selects all active financieras; if provided, validates each institution_id exists and is active; inactive or unknown IDs return 422.
8. **AC-08**: Upon successful validation, one SQS message per selected financiera is published to queue `fin-application-{institution_id}` containing encrypted applicant data, vehicle data, and application reference; messages include a deduplication_id based on application_id + institution_id.
9. **AC-09**: Each InstitutionApplication record is created with status QUEUED and timeout_at = now + institution.max_response_minutes (configurable per institution, default 60 min).
10. **AC-10**: The response returns 201 with application_id, list of institutions with their initial status, and WebSocket URL for real-time tracking.
11. **AC-11**: Sensitive applicant data (CURP, RFC, income, employer details) is encrypted at rest using AES-256-GCM before storage in JSONB columns; encryption key is managed via AWS KMS.
12. **AC-12**: A user cannot submit more than 3 active applications simultaneously; if limit reached, return 429 with message "Maximum active applications reached".
13. **AC-13**: The application record has an expires_at timestamp set to submitted_at + 72 hours; expired applications are automatically marked as EXPIRED by WRK-FIN.

#### Definition of Done
- Endpoint implemented with full validation
- SQS fan-out tested with localstack in integration tests
- Encryption/decryption of sensitive fields verified
- Unit tests >= 95% coverage on validators and use case
- Integration tests for full flow: submit -> queue -> persist
- Load test: 50 concurrent applications without data loss
- Code reviewed and merged to develop

#### Technical Notes
- Use SQS FIFO queues with message deduplication to prevent duplicate submissions
- Applicant data must be encrypted before SQS dispatch (SQS messages may be logged)
- Consider idempotency key in request headers for retry safety
- WRK-FIN polls institution-specific response queues and updates InstitutionApplication status

#### Dependencies
- SVC-VEH for vehicle validation
- SVC-KYC for KYC level check
- SVC-USR for user profile enrichment
- AWS SQS for message fan-out
- AWS KMS for encryption key management
- WRK-FIN for async processing

---

### US-3: [MKT-BE-019][SVC-FIN-INF] Adapter de Instituciones Financieras

**Description**:
Implement a hexagonal architecture port/adapter pattern for financial institution integrations. Define the `FinancialInstitutionPort` interface that all institution adapters must implement. Each adapter handles the specifics of communicating with a particular financiera (REST or SOAP), mapping requests/responses to the internal domain model, handling errors, performing health checks, and implementing circuit breaker patterns to prevent cascade failures.

**Microservice**: SVC-FIN (:5015)
**Layer**: DOM (port interface) + INF (adapters)
**Worker**: WRK-FIN (uses adapters for communication)

#### Technical Context

**Port Interface**:
```python
# svc-fin/domain/ports/financial_institution_port.py
from abc import ABC, abstractmethod
from domain.models.credit_application import CreditApplication
from domain.models.credit_offer import CreditOffer
from domain.value_objects.health_status import HealthStatus

class FinancialInstitutionPort(ABC):
    @abstractmethod
    async def submit_application(self, application: CreditApplication) -> str:
        """Submit application, return external reference ID."""
        pass

    @abstractmethod
    async def check_status(self, external_reference: str) -> InstitutionStatus:
        """Check application status at the institution."""
        pass

    @abstractmethod
    async def get_offer(self, external_reference: str) -> CreditOffer:
        """Retrieve approved credit offer details."""
        pass

    @abstractmethod
    async def cancel_application(self, external_reference: str) -> bool:
        """Cancel a pending application."""
        pass

    @abstractmethod
    async def health_check(self) -> HealthStatus:
        """Check institution API availability."""
        pass

    @abstractmethod
    def get_institution_id(self) -> str:
        pass

    @abstractmethod
    def get_supported_terms(self) -> list[int]:
        pass

    @abstractmethod
    def get_max_response_minutes(self) -> int:
        pass
```

**REST Adapter Example**:
```python
# svc-fin/infrastructure/adapters/banco_nacional_adapter.py
class BancoNacionalAdapter(FinancialInstitutionPort):
    def __init__(self, config: InstitutionConfig, http_client: HttpClient):
        self.config = config
        self.client = http_client
        self.circuit_breaker = CircuitBreaker(
            failure_threshold=5,
            recovery_timeout=60,
            expected_exception=InstitutionUnavailableError
        )

    @circuit_breaker
    async def submit_application(self, application: CreditApplication) -> str:
        payload = self._map_to_banco_nacional_format(application)
        response = await self.client.post(
            f"{self.config.base_url}/api/solicitudes",
            json=payload,
            headers=self._auth_headers(),
            timeout=30
        )
        return response["folio"]
```

**SOAP Adapter Example**:
```python
# svc-fin/infrastructure/adapters/financiera_sur_adapter.py
class FinancieraSurAdapter(FinancialInstitutionPort):
    def __init__(self, config: InstitutionConfig, soap_client: SoapClient):
        self.config = config
        self.soap = soap_client
        self.circuit_breaker = CircuitBreaker(
            failure_threshold=3,
            recovery_timeout=120,
            expected_exception=InstitutionUnavailableError
        )

    @circuit_breaker
    async def submit_application(self, application: CreditApplication) -> str:
        xml_body = self._map_to_financiera_sur_xml(application)
        response = await self.soap.call(
            wsdl=self.config.wsdl_url,
            operation="EnviarSolicitud",
            body=xml_body,
            timeout=45
        )
        return response.find(".//NumeroReferencia").text
```

**Data Model**:
```
FinancialInstitution (DOM)
  - institution_id: UUID (PK)
  - code: String(20) UNIQUE
  - name: String(100)
  - type: Enum(BANK, SOFOM, SOFIPO, CREDIT_UNION)
  - api_type: Enum(REST, SOAP, SFTP)
  - base_url: String(255)
  - wsdl_url: String(255) nullable
  - auth_type: Enum(API_KEY, OAUTH2, CERTIFICATE, BASIC)
  - credentials: JSONB (encrypted)
  - supported_terms: ARRAY[Integer]
  - min_amount: Decimal(12,2)
  - max_amount: Decimal(12,2)
  - max_response_minutes: Integer default 60
  - is_active: Boolean default true
  - is_sandbox: Boolean default false
  - health_status: Enum(HEALTHY, DEGRADED, DOWN)
  - last_health_check: DateTime
  - circuit_breaker_state: Enum(CLOSED, OPEN, HALF_OPEN)
  - created_at: DateTime
  - updated_at: DateTime

InstitutionMetrics (DOM)
  - metric_id: UUID (PK)
  - institution_id: UUID (FK)
  - date: Date
  - applications_sent: Integer
  - applications_approved: Integer
  - applications_rejected: Integer
  - applications_timeout: Integer
  - avg_response_seconds: Float
  - error_count: Integer
  - availability_percentage: Decimal(5,2)
```

**Component Structure**:
```
svc-fin/
  domain/
    ports/
      financial_institution_port.py
    models/
      financial_institution.py
      institution_metrics.py
      credit_offer.py
    value_objects/
      health_status.py
      institution_status.py
  infrastructure/
    adapters/
      base_institution_adapter.py
      banco_nacional_adapter.py
      financiera_sur_adapter.py
      credito_facil_adapter.py
      adapter_factory.py
    circuit_breaker/
      circuit_breaker.py
      circuit_breaker_state.py
    http/
      http_client.py
      soap_client.py
      retry_policy.py
    health/
      institution_health_checker.py
    mapping/
      cnbv_data_mapper.py
```

#### Acceptance Criteria

1. **AC-01**: A `FinancialInstitutionPort` abstract base class is defined with methods: submit_application, check_status, get_offer, cancel_application, health_check, get_institution_id, get_supported_terms, get_max_response_minutes.
2. **AC-02**: An `AdapterFactory` creates the correct adapter instance based on FinancialInstitution.api_type and institution_id; unknown institution_id raises `InstitutionNotFoundError`.
3. **AC-03**: Each REST adapter maps internal CreditApplication fields to the institution-specific JSON format using a dedicated mapper class; no domain model leaks into the external payload.
4. **AC-04**: Each SOAP adapter generates valid XML from CreditApplication using a dedicated XML mapper; the SOAP envelope includes proper namespace declarations.
5. **AC-05**: Circuit breaker per adapter transitions from CLOSED to OPEN after N consecutive failures (configurable per institution, default 5); OPEN state rejects calls immediately with `InstitutionUnavailableError` for recovery_timeout seconds; after timeout transitions to HALF_OPEN allowing 1 probe request.
6. **AC-06**: Health check endpoint GET /api/v1/financing/institutions/health returns status of all active institutions; each shows: institution_id, name, health_status (HEALTHY/DEGRADED/DOWN), last_check timestamp, circuit_breaker_state.
7. **AC-07**: Health checks run automatically every 5 minutes via a scheduled task; results update FinancialInstitution.health_status and last_health_check in the database.
8. **AC-08**: Each adapter implements retry with exponential backoff (1s, 2s, 4s) for transient errors (HTTP 429, 502, 503, 504, connection timeout); non-transient errors (4xx except 429) are not retried.
9. **AC-09**: Request and response payloads are logged (with sensitive fields masked) to an audit table for debugging; log entries include institution_id, direction (request/response), timestamp, duration_ms, status_code.
10. **AC-10**: Credentials for each institution are stored encrypted in PostgreSQL and decrypted at runtime via AWS KMS; credentials are never logged or included in error messages.
11. **AC-11**: Each adapter has a sandbox mode toggled by FinancialInstitution.is_sandbox; sandbox mode hits staging endpoints and uses test credentials without affecting production.
12. **AC-12**: Metrics (applications_sent, approved, rejected, timeout, avg_response_seconds, error_count) are tracked per institution per day and persisted in InstitutionMetrics table.

#### Definition of Done
- Port interface defined with complete docstrings
- At least 2 concrete adapters implemented (1 REST, 1 SOAP)
- Circuit breaker tested with failure injection
- Health check scheduler running
- Adapter factory tested with all registered institutions
- Unit tests >= 95% coverage on adapters and circuit breaker
- Integration tests with mock HTTP/SOAP servers
- Code reviewed and merged to develop

#### Technical Notes
- Use `httpx` for async HTTP calls in REST adapters
- Use `zeep` for SOAP client with async transport
- Circuit breaker state can be stored in Redis for cross-instance consistency
- CNBV data mapping should follow the standard "Expediente Unico" format
- Consider rate limiting per institution (some have low TPS limits)

#### Dependencies
- AWS KMS for credential decryption
- Redis for circuit breaker state sharing across instances
- Each institution's API documentation (external)
- CNBV data standards documentation

---

### US-4: [MKT-BE-020][SVC-FIN-API] Evaluacion de Credito en Tiempo Real

**Description**:
Implement a WebSocket endpoint and SSE alternative that pushes credit evaluation updates to the client in real time. As financial institutions process an application and respond (via WRK-FIN), the system broadcasts status changes and offers to the connected client. The UI can display offers appearing in real-time with per-institution status tracking (pending/evaluating/approved/rejected) and automatic comparison of approved offers.

**Microservice**: SVC-FIN (:5015)
**Layer**: API (WebSocket + SSE routes) + APP (event handlers) + INF (Redis Pub/Sub)

#### Technical Context

**WebSocket Endpoint**:
```
WSS /api/v1/financing/evaluate/ws?application_id=app_x9y8z7
Authorization: Bearer <jwt> (via query param or first message)
```

**SSE Endpoint (fallback)**:
```
GET /api/v1/financing/evaluate/sse?application_id=app_x9y8z7
Authorization: Bearer <jwt>
Accept: text/event-stream
```

**WebSocket Message Types (Server -> Client)**:

Status Update:
```json
{
  "type": "status_update",
  "application_id": "app_x9y8z7",
  "institution_id": "inst_001",
  "institution_name": "Banco Nacional",
  "previous_status": "queued",
  "new_status": "evaluating",
  "timestamp": "2026-03-23T10:06:00Z",
  "message": "Su solicitud esta siendo evaluada"
}
```

Offer Received:
```json
{
  "type": "offer_received",
  "application_id": "app_x9y8z7",
  "institution_id": "inst_001",
  "institution_name": "Banco Nacional",
  "offer": {
    "offer_id": "off_abc123",
    "status": "approved",
    "annual_rate": 11.9,
    "cat": 15.8,
    "term_months": 36,
    "monthly_payment": 11890.50,
    "total_payment": 428058.00,
    "down_payment_required": 20.0,
    "commission_percentage": 2.5,
    "commission_amount": 9000.00,
    "valid_until": "2026-03-30T23:59:59Z",
    "conditions": [
      "Seguro de auto obligatorio con Banco Nacional",
      "Domiciliacion de pago"
    ]
  },
  "timestamp": "2026-03-23T10:12:00Z",
  "is_best_offer": true,
  "comparison_rank": 1
}
```

Rejection:
```json
{
  "type": "rejection",
  "application_id": "app_x9y8z7",
  "institution_id": "inst_002",
  "institution_name": "Financiera del Sur",
  "reason_code": "INSUFFICIENT_INCOME",
  "reason_message": "El ingreso mensual no cumple el minimo requerido",
  "timestamp": "2026-03-23T10:08:00Z"
}
```

Evaluation Complete:
```json
{
  "type": "evaluation_complete",
  "application_id": "app_x9y8z7",
  "summary": {
    "total_institutions": 3,
    "approved": 1,
    "rejected": 1,
    "timeout": 1,
    "best_offer_id": "off_abc123",
    "best_offer_institution": "Banco Nacional"
  },
  "timestamp": "2026-03-23T10:15:00Z"
}
```

**WebSocket Message Types (Client -> Server)**:
```json
{
  "type": "accept_offer",
  "offer_id": "off_abc123"
}
```
```json
{
  "type": "ping"
}
```

**Data Model**:
```
CreditOffer (DOM)
  - offer_id: UUID (PK)
  - application_id: UUID (FK)
  - institution_id: UUID (FK)
  - inst_app_id: UUID (FK)
  - status: Enum(RECEIVED, ACCEPTED, DECLINED, EXPIRED)
  - annual_rate: Decimal(6,4)
  - cat: Decimal(6,2)
  - term_months: Integer
  - monthly_payment: Decimal(12,2)
  - total_payment: Decimal(14,2)
  - down_payment_required: Decimal(5,2)
  - commission_percentage: Decimal(5,2)
  - commission_amount: Decimal(12,2)
  - conditions: JSONB
  - valid_until: DateTime
  - comparison_rank: Integer
  - is_best_offer: Boolean
  - accepted_at: DateTime nullable
  - created_at: DateTime
  - updated_at: DateTime

EvaluationEvent (DOM)
  - event_id: UUID (PK)
  - application_id: UUID (FK)
  - institution_id: UUID (FK)
  - event_type: Enum(STATUS_UPDATE, OFFER_RECEIVED, REJECTION, TIMEOUT, COMPLETE)
  - payload: JSONB
  - created_at: DateTime
```

**Component Structure**:
```
svc-fin/
  api/
    websocket/
      evaluation_ws_handler.py
      ws_connection_manager.py
    sse/
      evaluation_sse_handler.py
    routes/
      evaluation_routes.py
  application/
    use_cases/accept_offer_use_case.py
    event_handlers/institution_response_handler.py
    event_handlers/offer_ranking_service.py
  infrastructure/
    pubsub/
      redis_pubsub.py
      evaluation_channel.py
    repositories/
      offer_repository.py
      evaluation_event_repository.py
```

#### Acceptance Criteria

1. **AC-01**: WebSocket connection at /api/v1/financing/evaluate/ws requires valid JWT and application_id; connection is rejected with 4001 code if JWT is invalid, 4003 if user does not own the application.
2. **AC-02**: SSE endpoint at /api/v1/financing/evaluate/sse provides the same events as WebSocket for clients that cannot maintain WebSocket connections; events use standard SSE format with `event:` and `data:` fields.
3. **AC-03**: When WRK-FIN updates an InstitutionApplication status, a Redis Pub/Sub message is published to channel `fin:eval:{application_id}`; the WebSocket handler subscribes to this channel and forwards messages to the connected client.
4. **AC-04**: Status transitions are emitted in order: queued -> sent -> evaluating -> approved/rejected/timeout; each transition generates a status_update message with previous and new status.
5. **AC-05**: When an institution approves, the offer_received message includes all financial details (rate, CAT, term, monthly_payment, total, commission, conditions); the offer is ranked against existing offers by total_payment ascending.
6. **AC-06**: The `is_best_offer` flag is dynamically recalculated as new offers arrive; if a new offer has lower total_payment, it becomes the best offer and a status_update is sent for the previous best offer to update its is_best_offer to false.
7. **AC-07**: When an institution rejects, the rejection message includes a reason_code and human-readable reason_message; reason codes follow a standard enum (INSUFFICIENT_INCOME, POOR_CREDIT_HISTORY, MISSING_DOCUMENTATION, POLICY_RESTRICTION, OTHER).
8. **AC-08**: When all institutions have responded (or timed out), an evaluation_complete message is sent with a summary of results; if at least one offer exists, the best_offer_id is included.
9. **AC-09**: Client can send accept_offer message via WebSocket; the server validates the offer exists, belongs to the application, is not expired, and marks it as ACCEPTED while declining all other offers for the same application.
10. **AC-10**: WebSocket connections are kept alive with server-side ping every 30 seconds; client timeout is 90 seconds without pong; disconnected clients can reconnect and receive any missed events from the EvaluationEvent table (replay from last received event_id).
11. **AC-11**: A maximum of 2 concurrent WebSocket connections per application are allowed (e.g., user on phone + desktop); additional connections receive 4029 error code.
12. **AC-12**: An evaluation timer is tracked server-side; if not all institutions have responded within the application's max timeout (max of all institution timeouts), remaining institutions are marked as TIMEOUT and evaluation_complete is sent.

#### Definition of Done
- WebSocket handler implemented with Flask-SocketIO or equivalent
- SSE endpoint implemented as fallback
- Redis Pub/Sub integration tested
- Event replay on reconnection verified
- Unit tests >= 95% coverage
- Integration test: full flow from application submit to offer acceptance
- WebSocket load test: 100 concurrent connections
- Code reviewed and merged to develop

#### Technical Notes
- Use Redis Pub/Sub for cross-instance event broadcasting (multiple SVC-FIN instances)
- Store all events in EvaluationEvent table for replay and audit
- Consider using Flask-SocketIO with Redis message queue adapter for horizontal scaling
- SSE connections should include `Cache-Control: no-cache` and `Connection: keep-alive` headers
- Offer ranking algorithm: primary sort by total_payment ASC, secondary by CAT ASC

#### Dependencies
- Redis 7 for Pub/Sub
- WRK-FIN for institution response processing
- US-2 (CreditApplication must exist)
- US-3 (Adapters for institution communication)

---

### US-5: [MKT-FE-016][FE-FEAT-FIN] Cotizador Visual de Financiamiento

**Description**:
Build an interactive financing calculator component for the Angular 18 frontend using standalone components and signals-based state. The calculator features sliders for down payment percentage and loan term, with real-time monthly payment updates as users adjust parameters. It displays an amortization chart, allows side-by-side scenario comparison, and includes a CTA button to initiate a formal credit application.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-FIN (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/financing/
  calculator/
    financing-calculator.component.ts
    financing-calculator.component.html
    financing-calculator.component.spec.ts
  calculator-slider/
    calculator-slider.component.ts
    calculator-slider.component.html
  amortization-chart/
    amortization-chart.component.ts
    amortization-chart.component.html
  scenario-comparison/
    scenario-comparison.component.ts
    scenario-comparison.component.html
  services/
    financing-calculator.service.ts
    financing-calculator.service.spec.ts
  models/
    calculation.model.ts
    scenario.model.ts
    amortization-entry.model.ts
  state/
    calculator.store.ts
```

**API Integration**:
```typescript
// financing-calculator.service.ts
@Injectable({ providedIn: 'root' })
export class FinancingCalculatorService {
  private readonly apiUrl = `${environment.apiGateway}/api/v1/financing`;

  calculate(request: CalculateRequest): Observable<CalculationResponse> {
    return this.http.post<CalculationResponse>(
      `${this.apiUrl}/calculate`,
      request
    );
  }
}
```

**Signals-Based State**:
```typescript
// calculator.store.ts
@Injectable({ providedIn: 'root' })
export class CalculatorStore {
  // Input signals
  readonly vehiclePrice = signal<number>(0);
  readonly downPaymentPercentage = signal<number>(20);
  readonly selectedTerms = signal<number[]>([12, 24, 36, 48, 60]);
  readonly insuranceIncluded = signal<boolean>(true);

  // Computed signals
  readonly downPaymentAmount = computed(() =>
    this.vehiclePrice() * (this.downPaymentPercentage() / 100)
  );
  readonly financedAmount = computed(() =>
    this.vehiclePrice() - this.downPaymentAmount()
  );

  // Async state
  readonly scenarios = signal<Scenario[]>([]);
  readonly isLoading = signal<boolean>(false);
  readonly error = signal<string | null>(null);
  readonly selectedScenario = signal<Scenario | null>(null);
}
```

**Tailwind CSS Classes (v4)**:
```html
<!-- Slider container -->
<div class="flex flex-col gap-4 p-6 bg-white rounded-2xl shadow-lg">
  <input type="range" class="w-full accent-blue-600 h-2 rounded-lg" />
  <div class="flex justify-between text-sm text-gray-500">
    <span>10%</span>
    <span class="text-2xl font-bold text-blue-700">
      {{ downPaymentPercentage() }}%
    </span>
    <span>90%</span>
  </div>
</div>

<!-- Scenario card -->
<div class="p-4 border-2 rounded-xl transition-all duration-300
            hover:border-blue-500 hover:shadow-md cursor-pointer"
     [class.border-blue-600]="isSelected()"
     [class.bg-blue-50]="isSelected()">
</div>
```

#### Acceptance Criteria

1. **AC-01**: The calculator component receives vehicle_price as an input (from vehicle detail page or manual entry); if no vehicle is selected, user can type a price manually in a formatted input field (comma-separated thousands).
2. **AC-02**: A horizontal slider controls down_payment_percentage from 10% to 90% in 5% increments; the down payment amount in pesos updates in real time as the slider moves; both the slider and a numeric input are synchronized bidirectionally.
3. **AC-03**: A term selector allows choosing multiple terms (12, 24, 36, 48, 60 months) via toggle buttons; at least one term must be selected; the API is called with all selected terms to generate scenarios.
4. **AC-04**: When any input changes (price, down payment, terms), the system debounces for 500ms then calls POST /financing/calculate; a loading skeleton is shown during the API call; previous results remain visible until new results arrive.
5. **AC-05**: Each scenario is displayed as a card showing: term label (e.g., "36 meses"), monthly_payment (large, prominent), annual_rate, CAT, total_payment, total_interest; cards are arranged in a horizontal scrollable row on mobile and a grid on desktop.
6. **AC-06**: Clicking a scenario card selects it and displays its full amortization table in a chart (line chart showing principal vs. interest over time using Chart.js or ng2-charts) and an expandable data table below.
7. **AC-07**: A "Compare scenarios" toggle enables side-by-side comparison of 2-3 selected scenarios in a table format: rows for each metric (rate, CAT, monthly payment, total payment, total interest), columns for each scenario, with the best value in each row highlighted in green.
8. **AC-08**: An insurance toggle (on by default) shows/hides insurance_monthly in the monthly payment display; when enabled, total_monthly_with_insurance is shown with a breakdown tooltip.
9. **AC-09**: A prominent CTA button "Solicitar credito formal" appears below the calculator; clicking it navigates to the credit application form (US-6) pre-populated with the selected scenario's parameters.
10. **AC-10**: The component is fully responsive: on mobile (< 640px) sliders stack vertically, scenario cards scroll horizontally, and the amortization chart resizes; on desktop (>= 1024px) sliders are side-by-side and cards display in a 3-column grid.
11. **AC-11**: All monetary values are formatted as Mexican pesos (e.g., "$12,045.67 MXN") using a shared currency pipe; percentages show 1-2 decimal places.
12. **AC-12**: Error states are handled gracefully: API timeout shows "No se pudo calcular, intente de nuevo" with a retry button; network error shows offline banner; invalid server response shows generic error message.
13. **AC-13**: The calculator state persists in the CalculatorStore signal; navigating away and returning restores the last inputs and results without a new API call (until inputs change).

#### Definition of Done
- Standalone component implemented with signals-based state
- Tailwind CSS v4 styling, fully responsive
- Chart.js amortization chart working
- Unit tests for component logic and service (>= 90% coverage)
- E2E test: adjust slider -> verify payment update -> select scenario -> view chart
- Lighthouse performance score >= 90
- Code reviewed and merged to develop

#### Technical Notes
- Use Angular 18 standalone components (no NgModule)
- Signals for all reactive state (no RxJS BehaviorSubjects for component state)
- Debounce API calls using rxjs `debounceTime` in the service layer
- Chart.js via ng2-charts for amortization visualization
- Consider using `@defer` for lazy-loading the amortization chart section

#### Dependencies
- US-1 (Calculator API endpoint)
- Shared currency formatting pipe
- Chart.js / ng2-charts library
- Vehicle detail page for vehicle_price input

---

### US-6: [MKT-FE-017][FE-FEAT-FIN] Formulario de Solicitud de Credito

**Description**:
Build a multi-step credit application form in Angular 18 with standalone components. The form collects personal data, employment information, and references across multiple steps with validation. It includes financiera selection, bureau consent checkbox, privacy documentation links, and a summary review before submission. The form integrates with the credit application API (US-2).

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-FIN (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/financing/
  application-form/
    credit-application-form.component.ts
    credit-application-form.component.html
    steps/
      personal-data-step.component.ts
      employment-step.component.ts
      references-step.component.ts
      institution-selection-step.component.ts
      consent-step.component.ts
      summary-step.component.ts
    services/
      credit-application.service.ts
    models/
      credit-application.model.ts
    state/
      application-form.store.ts
    validators/
      curp.validator.ts
      rfc.validator.ts
      phone.validator.ts
```

**Form State with Signals**:
```typescript
// application-form.store.ts
@Injectable({ providedIn: 'root' })
export class ApplicationFormStore {
  readonly currentStep = signal<number>(1);
  readonly totalSteps = signal<number>(6);
  readonly personalData = signal<PersonalData | null>(null);
  readonly employmentData = signal<EmploymentData | null>(null);
  readonly references = signal<Reference[]>([]);
  readonly selectedInstitutions = signal<string[]>([]);
  readonly consents = signal<Consents>({
    bureauCheck: false,
    dataSharing: false,
    privacyNotice: false,
    termsAccepted: false
  });
  readonly isSubmitting = signal<boolean>(false);
  readonly submitResult = signal<SubmitResult | null>(null);

  readonly progress = computed(() =>
    (this.currentStep() / this.totalSteps()) * 100
  );
  readonly canSubmit = computed(() =>
    this.consents().bureauCheck &&
    this.consents().dataSharing &&
    this.consents().privacyNotice &&
    this.consents().termsAccepted
  );
}
```

**Step Navigation**:
```html
<!-- Progress bar -->
<div class="w-full bg-gray-200 rounded-full h-2 mb-8">
  <div class="bg-blue-600 h-2 rounded-full transition-all duration-500"
       [style.width.%]="store.progress()">
  </div>
</div>

<!-- Step indicator -->
<div class="flex justify-between mb-8">
  @for (step of steps; track step.number) {
    <div class="flex flex-col items-center gap-1">
      <div class="w-10 h-10 rounded-full flex items-center justify-center
                  text-sm font-medium transition-colors"
           [class]="step.number <= store.currentStep()
             ? 'bg-blue-600 text-white'
             : 'bg-gray-200 text-gray-500'">
        {{ step.number }}
      </div>
      <span class="text-xs text-gray-500 hidden sm:block">{{ step.label }}</span>
    </div>
  }
</div>
```

#### Acceptance Criteria

1. **AC-01**: The form has 6 steps displayed in order: (1) Personal Data, (2) Employment, (3) References, (4) Institution Selection, (5) Consents & Privacy, (6) Summary & Submit; a progress bar and step indicator show current progress.
2. **AC-02**: Step 1 (Personal Data) collects: full_name (required, min 5 chars), CURP (required, validated with regex ^[A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z0-9]\d$), RFC (required, 12-13 chars with validation), date_of_birth (required, age 18-75), nationality, marital_status (dropdown), dependents (0-20), education_level (dropdown), email (required, RFC 5322), phone (required, E.164 +52...), full address with street, colony, municipality, state (dropdown of 32 states), zip_code (5 digits).
3. **AC-03**: Step 2 (Employment) collects: employment_type (asalariado/independiente/empresario/jubilado), company_name (required if asalariado), position, monthly_income (required, > 0, formatted as currency), seniority_months (required, > 0), employer_phone (validated), employer_address.
4. **AC-04**: Step 3 (References) requires exactly 2 references, each with: name (required), relationship (dropdown: familiar/laboral/personal), phone (required, validated); an "Add reference" button allows adding up to 5 total; a "Remove" button appears for references beyond the required 2.
5. **AC-05**: Step 4 (Institution Selection) displays available active financieras as selectable cards with: institution logo, name, typical rate range, typical response time; user can select 1 to all; a "Select all" checkbox is available; at least 1 must be selected.
6. **AC-06**: Step 5 (Consents) displays 4 mandatory checkboxes: (a) "Autorizo la consulta a mi historial crediticio (Buro de Credito)" with link to full bureau authorization text, (b) "Autorizo compartir mis datos con las financieras seleccionadas" with link, (c) "He leido y acepto el Aviso de Privacidad" with link to full privacy notice, (d) "Acepto los Terminos y Condiciones" with link; all 4 must be checked to proceed.
7. **AC-07**: Step 6 (Summary) displays a read-only summary of all entered data organized by section with "Edit" links that navigate back to the corresponding step; financial parameters (vehicle, down payment, term) from the calculator are also shown.
8. **AC-08**: Navigation: "Next" button validates the current step before advancing; "Back" button navigates to previous step preserving data; direct step navigation (clicking step indicator) only allows visiting completed or current steps.
9. **AC-09**: On submit, the form calls POST /financing/apply with all collected data; during submission a loading overlay with spinner and "Enviando solicitud..." message appears; the submit button is disabled to prevent double-submission.
10. **AC-10**: On successful submission (201), the user is redirected to the real-time evaluation dashboard (US-7) with the application_id; on error (422), field-level errors are mapped back to their respective steps and the first step with errors is activated.
11. **AC-11**: Form data persists in ApplicationFormStore signals and survives navigation within the form (step changes); if the user leaves the financing section entirely, a browser `beforeunload` confirmation dialog warns about unsaved data.
12. **AC-12**: All form inputs follow accessibility standards: labels associated with inputs via `for` attribute, error messages announced with `aria-live="polite"`, keyboard navigation between steps with Tab/Shift+Tab, focus management on step change.
13. **AC-13**: The form is responsive: on mobile, form fields stack vertically with full-width inputs; on desktop, fields are arranged in 2-column grid where appropriate (e.g., name + CURP, email + phone).

#### Definition of Done
- All 6 step components implemented as standalone Angular components
- Reactive Forms with custom validators (CURP, RFC, phone)
- Signals-based form store with persistence
- Tailwind CSS v4 responsive styling
- Unit tests for each step component and validators (>= 90% coverage)
- E2E test: complete form flow from step 1 to submission
- Accessibility audit passed (axe-core, 0 critical violations)
- Code reviewed and merged to develop

#### Technical Notes
- Use Angular Reactive Forms with custom validators for CURP, RFC patterns
- Form data stored in signals, not in URL params (sensitive data)
- Consider using Angular CDK Stepper for step management
- Lazy-load institution logos with `loading="lazy"` attribute
- Privacy and consent documents should open in new tabs, not navigate away

#### Dependencies
- US-2 (Credit application API)
- US-5 (Calculator provides pre-populated financing parameters)
- SVC-FIN GET /financing/institutions endpoint for active financiera list
- Privacy notice and terms documents (content team)

---

### US-7: [MKT-FE-018][FE-FEAT-FIN] Dashboard de Ofertas de Credito Real-Time

**Description**:
Build a real-time credit offers dashboard that displays incoming offers from financial institutions as they arrive. The dashboard connects via WebSocket (or SSE fallback) to receive live updates, showing animated cards for each offer, a comparison view, a "Best offer" badge, expandable detail sections, and an "Accept offer" button. An evaluation timer shows elapsed time since submission.

**Microservice**: Frontend (Angular 18)
**Layer**: FE-FEAT-FIN (Feature Module)

#### Technical Context

**Component Structure**:
```
src/app/features/financing/
  evaluation-dashboard/
    evaluation-dashboard.component.ts
    evaluation-dashboard.component.html
  offer-card/
    offer-card.component.ts
    offer-card.component.html
  offer-comparison/
    offer-comparison.component.ts
    offer-comparison.component.html
  institution-status/
    institution-status.component.ts
    institution-status.component.html
  evaluation-timer/
    evaluation-timer.component.ts
  services/
    evaluation-websocket.service.ts
    evaluation-sse.service.ts
  state/
    evaluation.store.ts
  animations/
    offer-card.animations.ts
```

**WebSocket Service**:
```typescript
// evaluation-websocket.service.ts
@Injectable({ providedIn: 'root' })
export class EvaluationWebSocketService {
  private socket: WebSocket | null = null;
  readonly messages$ = new Subject<EvaluationMessage>();
  readonly connectionState = signal<'connecting' | 'connected' | 'disconnected'>('disconnected');

  connect(applicationId: string, token: string): void {
    const url = `${environment.wsUrl}/api/v1/financing/evaluate/ws?application_id=${applicationId}`;
    this.socket = new WebSocket(url);
    this.connectionState.set('connecting');

    this.socket.onopen = () => this.connectionState.set('connected');
    this.socket.onmessage = (event) => {
      const message = JSON.parse(event.data) as EvaluationMessage;
      this.messages$.next(message);
    };
    this.socket.onclose = () => {
      this.connectionState.set('disconnected');
      this.reconnect(applicationId, token);
    };
  }
}
```

**Evaluation Store**:
```typescript
// evaluation.store.ts
@Injectable({ providedIn: 'root' })
export class EvaluationStore {
  readonly applicationId = signal<string>('');
  readonly institutions = signal<InstitutionStatus[]>([]);
  readonly offers = signal<CreditOffer[]>([]);
  readonly bestOffer = computed(() =>
    this.offers().find(o => o.isBestOffer) ?? null
  );
  readonly isComplete = signal<boolean>(false);
  readonly summary = signal<EvaluationSummary | null>(null);
  readonly elapsedSeconds = signal<number>(0);
  readonly connectionState = signal<string>('disconnected');

  readonly approvedCount = computed(() =>
    this.offers().filter(o => o.status === 'approved').length
  );
  readonly rejectedCount = computed(() =>
    this.institutions().filter(i => i.status === 'rejected').length
  );
  readonly pendingCount = computed(() =>
    this.institutions().filter(i =>
      ['queued', 'sent', 'evaluating'].includes(i.status)
    ).length
  );
}
```

**Card Animation**:
```typescript
// offer-card.animations.ts
export const offerCardAnimation = trigger('offerAppear', [
  transition(':enter', [
    style({ opacity: 0, transform: 'translateY(30px) scale(0.95)' }),
    animate('400ms cubic-bezier(0.35, 0, 0.25, 1)',
      style({ opacity: 1, transform: 'translateY(0) scale(1)' })
    )
  ])
]);
```

#### Acceptance Criteria

1. **AC-01**: On page load, the component reads application_id from the route parameter and connects to WebSocket endpoint; a "Connecting..." indicator is shown during connection; once connected, the indicator changes to "Connected" (green dot).
2. **AC-02**: A status bar at the top shows all institutions with their current status using colored badges: gray (queued), blue (sent), yellow/animated (evaluating), green (approved), red (rejected), orange (timeout); status updates animate smoothly.
3. **AC-03**: When a `status_update` message arrives, the corresponding institution badge updates with a brief highlight animation (pulse); the status label transitions smoothly.
4. **AC-04**: When an `offer_received` message arrives, a new offer card appears with a slide-up + fade-in animation (400ms ease-out); the card displays: institution name + logo, annual_rate, CAT, term_months, monthly_payment (large and prominent), total_payment, commission, and conditions list.
5. **AC-05**: The offer card with the lowest total_payment displays a "Mejor oferta" badge (gold/star icon) in the top-right corner; if a better offer arrives later, the badge animates from the old card to the new one.
6. **AC-06**: Each offer card has an "Expand" button that reveals additional details: full conditions list, commission breakdown, validity date, and a detailed amortization preview (first 6 months).
7. **AC-07**: Each approved offer card has an "Aceptar oferta" button; clicking it shows a confirmation dialog ("Confirma que desea aceptar la oferta de [Institution Name]?"); on confirm, sends accept_offer message via WebSocket and disables all other accept buttons.
8. **AC-08**: A comparison mode toggle switches the view from individual cards to a comparison table: columns = institutions, rows = rate/CAT/monthly_payment/total_payment/commission/conditions; the best value per row is highlighted in green; offers can be sorted by any column.
9. **AC-09**: An evaluation timer displays elapsed time since submission in MM:SS format, updating every second; the timer pauses when evaluation_complete is received; estimated remaining time per pending institution is shown based on their max_response_minutes.
10. **AC-10**: When `evaluation_complete` message arrives, a summary banner appears at the top: "Evaluacion completada: X aprobadas, Y rechazadas, Z sin respuesta"; if offers exist, the banner highlights the best offer with a "Review best offer" CTA.
11. **AC-11**: If WebSocket disconnects, the service automatically attempts reconnection with exponential backoff (1s, 2s, 4s, 8s, max 30s); during disconnection, a yellow "Reconnecting..." banner is shown; on reconnect, missed events are replayed from the server.
12. **AC-12**: If WebSocket is not supported by the browser, the component falls back to SSE; the user experience is identical regardless of transport mechanism.
13. **AC-13**: The dashboard is responsive: on mobile, offer cards stack vertically with swipe navigation; on tablet, 2-column grid; on desktop, 3-column grid with comparison table visible alongside.

#### Definition of Done
- Dashboard component implemented with WebSocket + SSE fallback
- Angular animations for card appearances and status transitions
- Signals-based store with computed properties for aggregations
- Comparison table with sorting and highlighting
- Unit tests >= 90% coverage
- E2E test: simulate WebSocket messages -> verify card appearance + animation
- Tested on Chrome, Firefox, Safari, Edge
- Code reviewed and merged to develop

#### Technical Notes
- WebSocket reconnection should request event replay from last received event_id
- Use Angular `@defer` for the comparison table (loaded on user toggle)
- Consider using Intersection Observer for lazy rendering of off-screen offer cards
- Timer should use `requestAnimationFrame` or `setInterval(1000)` with cleanup in `ngOnDestroy`
- Test with mock WebSocket server (jest-websocket-mock or similar)

#### Dependencies
- US-4 (WebSocket/SSE backend)
- US-2 (Application must be submitted first)
- US-6 (Form navigates to this dashboard on success)

---

### US-8: [MKT-INT-004][WRK-FIN] Integracion Bidireccional con Financieras

**Description**:
Implement the WRK-FIN worker that handles bidirectional communication with financial institutions. This includes: a webhook endpoint to receive asynchronous decisions from financieras, an API client that submits applications using the adapter pattern (US-3), CNBV-compatible data formatting, encryption of sensitive data in transit and at rest, state reconciliation between internal records and institution responses, and sandbox mode for each institution.

**Microservice**: WRK-FIN (Worker)
**Layer**: INF (infrastructure) + APP (application)

#### Technical Context

**Worker Architecture**:
```
wrk-fin/
  consumers/
    application_consumer.py       # SQS consumer for outbound applications
    response_consumer.py          # SQS consumer for institution responses
    timeout_consumer.py           # Scheduled check for timed-out applications
  webhooks/
    webhook_routes.py             # Flask routes for institution callbacks
    webhook_validator.py          # Signature/auth validation per institution
    webhook_payload_mapper.py     # Map institution-specific to internal format
  processors/
    application_processor.py      # Orchestrates sending to institution
    response_processor.py         # Processes institution decisions
    reconciliation_processor.py   # Reconciles state mismatches
  encryption/
    payload_encryptor.py          # AES-256-GCM encryption/decryption
    key_manager.py                # AWS KMS key management
  cnbv/
    cnbv_formatter.py             # CNBV Expediente Unico format
    cnbv_validator.py             # Validate CNBV compliance
  state/
    state_machine.py              # Application state transitions
    state_reconciler.py           # Detect and fix state mismatches
  sandbox/
    sandbox_simulator.py          # Simulates financiera responses
    sandbox_config.py             # Per-institution sandbox settings
  config/
    worker_config.py
    queue_config.py
```

**Webhook Endpoint**:
```
POST /webhooks/financing/{institution_code}/decision
Content-Type: application/json
X-Institution-Signature: <hmac_sha256>
```

**Webhook Payload (Institution -> WRK-FIN)**:
```json
{
  "reference_id": "app_x9y8z7_inst001",
  "institution_reference": "BN-2026-00123",
  "decision": "approved",
  "offer": {
    "annual_rate": 11.9,
    "term_months": 36,
    "monthly_payment": 11890.50,
    "total_amount": 428058.00,
    "cat": 15.8,
    "commission_pct": 2.5,
    "insurance_required": true,
    "conditions": ["Seguro con aseguradora asociada", "Domiciliacion"],
    "valid_until": "2026-03-30T23:59:59Z"
  },
  "timestamp": "2026-03-23T10:12:00Z",
  "signature": "abc123..."
}
```

**State Machine**:
```
QUEUED -> SENT -> EVALUATING -> APPROVED (with offer)
                             -> REJECTED (with reason)
                             -> TIMEOUT
                             -> ERROR (retryable)
```

**Data Model**:
```
WebhookLog (INF)
  - log_id: UUID (PK)
  - institution_id: UUID (FK)
  - direction: Enum(INBOUND, OUTBOUND)
  - endpoint: String(255)
  - method: String(10)
  - headers: JSONB
  - payload: JSONB (encrypted)
  - response_status: Integer
  - response_body: JSONB
  - processing_status: Enum(RECEIVED, PROCESSED, FAILED, IGNORED)
  - error_message: Text
  - duration_ms: Integer
  - created_at: DateTime

StateReconciliation (INF)
  - reconciliation_id: UUID (PK)
  - application_id: UUID (FK)
  - institution_id: UUID (FK)
  - internal_status: String(20)
  - external_status: String(20)
  - mismatch_type: Enum(STATUS_MISMATCH, MISSING_RESPONSE, STALE_STATE)
  - resolution: Enum(AUTO_FIXED, MANUAL_REVIEW, IGNORED)
  - resolved_at: DateTime
  - created_at: DateTime
```

#### Acceptance Criteria

1. **AC-01**: WRK-FIN SQS consumer polls queue `fin-application-outbound` and processes messages sequentially with at-least-once delivery; each message contains an application_id and institution_id; the consumer uses the AdapterFactory (US-3) to get the correct adapter and calls submit_application.
2. **AC-02**: After successful submission to an institution, InstitutionApplication.status is updated to SENT and external_reference is stored; a Redis Pub/Sub message is published to `fin:eval:{application_id}` with type=status_update.
3. **AC-03**: Webhook endpoint POST /webhooks/financing/{institution_code}/decision validates the institution signature using HMAC-SHA256 with the institution's webhook_secret; invalid signatures return 401 and are logged.
4. **AC-04**: Valid webhook payloads are mapped from institution-specific format to internal CreditOffer domain model; the mapper handles each institution's unique field names and data formats.
5. **AC-05**: When a webhook delivers an "approved" decision, a CreditOffer record is created, InstitutionApplication.status is set to APPROVED, and an offer_received event is published to Redis Pub/Sub; when "rejected", status is set to REJECTED with reason_code and reason_message.
6. **AC-06**: All outbound application data is formatted according to CNBV "Expediente Unico" standard before sending to institutions; the formatter converts internal models to the standard XML/JSON schema including required fields: CURP, RFC, credit amount, term, income documentation.
7. **AC-07**: Sensitive data (CURP, RFC, income, bank account numbers) is encrypted using AES-256-GCM before transmission; encryption keys are rotated via AWS KMS; the encryption key ID is stored alongside the ciphertext for future decryption.
8. **AC-08**: A timeout checker runs every 5 minutes; it queries InstitutionApplication records where status IN (QUEUED, SENT, EVALUATING) AND now > timeout_at; these records are marked as TIMEOUT and a timeout event is published.
9. **AC-09**: State reconciliation runs daily; it compares InstitutionApplication status with the latest known status from each institution (via check_status adapter method); mismatches are logged in StateReconciliation table; auto-fixable mismatches (e.g., institution approved but internal shows evaluating) are resolved automatically.
10. **AC-10**: Sandbox mode per institution: when FinancialInstitution.is_sandbox is true, the worker uses SandboxSimulator instead of the real adapter; the simulator returns configurable responses (approve/reject/timeout) with realistic delays (2-30 seconds).
11. **AC-11**: Failed submissions are retried up to 3 times with exponential backoff (10s, 30s, 90s); after all retries exhausted, status is set to ERROR with error_message and an alert notification is sent to SVC-NTF for operations team.
12. **AC-12**: All webhook requests and outbound API calls are logged in WebhookLog with full payload (encrypted), headers, status code, and duration_ms; logs are retained for 90 days for audit compliance.
13. **AC-13**: The worker handles graceful shutdown: on SIGTERM, it stops polling for new messages, waits for in-flight processing to complete (max 30 seconds), then exits; no messages are lost during shutdown.

#### Definition of Done
- SQS consumer implemented for outbound and response queues
- Webhook endpoint with signature validation
- CNBV formatter with standard compliance tests
- Encryption/decryption of sensitive payloads
- State machine with valid transitions enforced
- Sandbox simulator with configurable responses
- Reconciliation job implemented and scheduled
- Unit tests >= 95% coverage
- Integration tests with localstack (SQS, KMS)
- Load test: 100 concurrent applications processed without errors
- Code reviewed and merged to develop

#### Technical Notes
- Use boto3 for SQS with long polling (wait_time_seconds=20)
- Webhook endpoint should return 200 immediately and process async to avoid institution timeouts
- CNBV standard may require specific XML namespaces; validate with XSD schema
- Consider dead-letter queues for messages that fail all retries
- Sandbox simulator should support configurable latency distribution for realistic testing

#### Dependencies
- US-3 (FinancialInstitutionPort and adapters)
- US-4 (Redis Pub/Sub for real-time events)
- AWS SQS, KMS
- SVC-NTF for operations alerts
- CNBV Expediente Unico specification document

---

## Cross-Cutting Concerns

### Security
- All sensitive financial data encrypted at rest (AES-256-GCM) and in transit (TLS 1.3)
- CURP, RFC, income data never stored in plain text
- JWT required for all endpoints except calculator (optional)
- Webhook signatures validated per institution
- Rate limiting: 10 calculations/min unauthenticated, 100/min authenticated

### Observability
- Structured logging with correlation_id across SVC-FIN and WRK-FIN
- Metrics: calculation_count, application_count, offer_count, approval_rate, avg_response_time per institution
- Alerts: circuit breaker state changes, high error rates, timeout rate > 50%
- Distributed tracing with OpenTelemetry across service boundaries

### Performance
- Calculator endpoint: < 200ms p95
- Application submission: < 2s p95
- WebSocket event delivery: < 500ms from institution response to client
- Redis cache for reference rates and institution configs

### Compliance
- CNBV data standards for financial data exchange
- Buro de Credito consent tracking and audit trail
- LFPDPPP (privacy law) compliance for personal data handling
- 90-day retention for all financial transaction logs

---

## Epic Dependencies Graph

```
EP-007 Dependencies:
  SVC-VEH (EP-003) --> Vehicle data for applications
  SVC-KYC (EP-005) --> KYC validation for applicants
  SVC-USR (EP-002) --> User profile and authentication
  SVC-NTF (EP-010) --> Notifications for application status
  SVC-ADM (EP-009) --> Partner management for financieras
```

## Release Plan

| Sprint | Stories | Focus |
|--------|---------|-------|
| Sprint 5 | US-1, US-3, US-5 | Calculator API + Adapters + Frontend Calculator |
| Sprint 6 | US-2, US-4, US-6 | Application API + Real-time + Application Form |
| Sprint 7 | US-7, US-8 | Dashboard + Worker Integration |
