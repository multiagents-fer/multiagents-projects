# Coding Standards - Marketplace AgentsMX

## Reglas Obligatorias (Zero Tolerance)

Estas reglas aplican a TODOS los microservicios, frontend y backend sin excepcion.

### 1. Arquitectura Hexagonal (Ports & Adapters)

**Backend (Flask/Python):**
```
app/
  domain/           # CERO dependencias externas
    models/          # Entidades puras (Python dataclasses)
    ports/           # ABCs (interfaces)
    exceptions/      # Excepciones de dominio
    events/          # Eventos de dominio
  application/       # Orquestacion, use cases
    services/        # Logica de aplicacion
    dto/             # Data Transfer Objects
  infrastructure/    # Implementaciones concretas
    persistence/     # SQLAlchemy repos
    adapters/        # HTTP clients, S3, Redis, ES
    auth/            # Cognito adapter
    messaging/       # SQS, SNS adapters
  api/               # Capa de presentacion
    v1/              # Routes (thin controllers)
    schemas/         # Marshmallow schemas
    middleware/      # Auth, rate limit, error handling
```

**Frontend (Angular 18):**
```
src/app/
  core/
    domain/
      models/        # Interfaces TypeScript puras
      ports/         # Abstract classes (interfaces de servicio)
    application/
      state/         # Signal stores
      services/      # Orquestacion
    infrastructure/
      adapters/      # HTTP implementations de ports
      interceptors/  # JWT, error handling
      guards/        # Auth, KYC guards
  features/          # Lazy-loaded por ruta
  shared/            # Componentes reutilizables
  layout/            # Header, footer, sidebar
```

**Regla clave:** `domain/` NUNCA importa de `infrastructure/` ni de frameworks. Las dependencias van de afuera hacia adentro.

---

### 2. Limites de Tamano de Archivo

| Regla | Limite | Accion si se excede |
|-------|--------|---------------------|
| **Lineas por archivo** | Max 1,000 lineas | Dividir en modulos/clases mas pequenos |
| **Lineas por funcion/metodo** | Max 50 lineas | Extraer sub-funciones con nombres descriptivos |
| **Parametros por funcion** | Max 10 parametros | Usar objetos/dataclasses/DTOs para agrupar |

#### Ejemplos de como cumplir:

**Mal (>50 lineas, >10 params):**
```python
def create_vehicle(brand, model, year, price, kms, transmission,
                   fuel_type, color_ext, color_int, engine, doors,
                   seats, drivetrain, location_state, location_city,
                   description, features, seller_id):
    # 80 lineas de logica...
```

**Bien (<50 lineas, DTO con campos agrupados):**
```python
@dataclass
class CreateVehicleDTO:
    brand: str
    model: str
    year: int
    price: Decimal
    kms: Decimal
    transmission: str
    fuel_type: str
    color_ext: str
    color_int: str
    engine: str
    doors: int
    location: LocationDTO
    seller_id: UUID

def create_vehicle(dto: CreateVehicleDTO) -> Vehicle:
    vehicle = Vehicle.from_dto(dto)
    self._validate_vehicle(vehicle)
    return self._repository.save(vehicle)
```

**Mal (funcion larga):**
```typescript
processVehicles(data: any[]) {
  // 120 lineas haciendo todo...
}
```

**Bien (funciones cortas y descriptivas):**
```typescript
processVehicles(vehicles: VehicleDTO[]): Vehicle[] {
  const validated = this.validateVehicles(vehicles);    // max 50 lines
  const normalized = this.normalizeData(validated);      // max 50 lines
  const enriched = this.enrichWithMarketData(normalized); // max 50 lines
  return this.saveVehicles(enriched);                    // max 50 lines
}
```

---

### 3. Reglas Adicionales de Calidad

#### Python (Backend)
- Type hints obligatorios en TODOS los parametros y retornos
- No bare `except:` — siempre excepciones especificas
- Docstrings solo donde la logica NO es auto-explicativa
- `dataclass` o Pydantic para datos estructurados (no dicts sueltos)
- Tests con pytest: >80% coverage obligatorio
- Formateo: black + isort + flake8 + mypy (pre-commit hooks)

#### TypeScript (Frontend)
- `strict: true` en tsconfig.json
- No `any` — usar tipos especificos siempre
- Standalone components obligatorio (no NgModules)
- Signals para state management (no BehaviorSubject para estado nuevo)
- OnPush change detection strategy por defecto
- Tests: >80% coverage con Jasmine/Karma

#### General
- Nombres descriptivos: `calculateMonthlyPayment()` no `calc()`
- Un archivo = una responsabilidad (Single Responsibility)
- DRY pero sin abstracciones prematuras (3 repeticiones = extraer)
- Constantes con nombre, no magic numbers: `MAX_FAVORITES = 100` no `100`
- Logs estructurados (JSON) con correlation ID en cada request
- Variables de entorno para config, NUNCA hardcoded

---

### 4. Validacion Automatica

Estas reglas se validan en CI/CD:

```yaml
# .github/workflows/quality-gates.yml
- name: Check file length
  run: |
    find . -name "*.py" -o -name "*.ts" | while read f; do
      lines=$(wc -l < "$f")
      if [ "$lines" -gt 1000 ]; then
        echo "ERROR: $f tiene $lines lineas (max 1000)"
        exit 1
      fi
    done

- name: Check function length
  run: |
    # flake8 con max-function-length
    flake8 --max-function-length=50

- name: Check parameters
  run: |
    # pylint con max-args
    pylint --max-args=10
```

---

---

## Clean Code - Principios Obligatorios

Basado en "Clean Code" (Robert C. Martin), "The Pragmatic Programmer", y OWASP Top 10.

### 5. SOLID Principles

#### S - Single Responsibility (SRP)
- Cada clase/modulo tiene UNA sola razon para cambiar
- Un archivo = una responsabilidad
- Si describes una clase con "y" (ej: "valida y guarda y notifica"), viola SRP

```python
# MAL: hace todo
class VehicleService:
    def create_vehicle(self): ...
    def send_email(self): ...
    def generate_pdf(self): ...
    def calculate_tax(self): ...

# BIEN: responsabilidad unica
class VehicleService:       # solo logica de vehiculos
class NotificationService:  # solo notificaciones
class ReportService:        # solo reportes
class TaxCalculator:        # solo calculos fiscales
```

#### O - Open/Closed (OCP)
- Abierto para extension, cerrado para modificacion
- Usar strategy pattern, ports/adapters para extensibilidad
- Nuevas financieras/aseguradoras = nuevo adapter, NO modificar service

```python
# MAL: modificar service por cada financiera nueva
class FinancingService:
    def evaluate(self, institution):
        if institution == "bancomer":
            # logica bancomer
        elif institution == "banamex":
            # logica banamex
        # agregar elif por cada nueva...

# BIEN: adapter por financiera
class FinancingService:
    def evaluate(self, adapter: FinancialInstitutionPort):
        return adapter.evaluate(self.application)
```

#### L - Liskov Substitution (LSP)
- Las subclases deben ser sustituibles por su clase base
- Si un adapter implementa un port, debe cumplir el contrato completo

#### I - Interface Segregation (ISP)
- Interfaces pequenas y especificas, no interfaces "gordas"
- Mejor 3 ports de 3 metodos que 1 port de 9 metodos

```python
# MAL: interface gorda
class VehiclePort(ABC):
    def find_by_id(self): ...
    def search(self): ...
    def create(self): ...
    def update(self): ...
    def delete(self): ...
    def generate_report(self): ...
    def calculate_valuation(self): ...

# BIEN: interfaces segregadas
class VehicleReadPort(ABC):
    def find_by_id(self): ...
    def search(self): ...

class VehicleWritePort(ABC):
    def create(self): ...
    def update(self): ...
    def delete(self): ...

class VehicleAnalyticsPort(ABC):
    def generate_report(self): ...
    def calculate_valuation(self): ...
```

#### D - Dependency Inversion (DIP)
- Depender de abstracciones (ports), no de implementaciones (adapters)
- Application layer inyecta adapters via constructor
- NUNCA instanciar un adapter dentro de un service

```python
# MAL: depende de implementacion
class VehicleService:
    def __init__(self):
        self.repo = SQLAlchemyVehicleRepo()  # acoplamiento directo

# BIEN: depende de abstraccion
class VehicleService:
    def __init__(self, repo: VehicleRepositoryPort):
        self._repo = repo  # inyectado, puede ser cualquier implementacion
```

---

### 6. Clean Code Rules

#### Nombres
- Variables/funciones: descriptivas, no abreviadas
  - `calculate_monthly_payment()` NO `calc_mp()`
  - `vehicle_count` NO `vc` o `cnt`
  - `is_eligible_for_financing` NO `flag` o `check`
- Clases: sustantivos en singular (`Vehicle`, `User`, `PurchaseIntent`)
- Funciones: verbos (`create_vehicle`, `calculate_price`, `validate_kyc`)
- Booleanos: prefijo is/has/can/should (`is_active`, `has_kyc`, `can_purchase`)
- Constantes: UPPER_SNAKE_CASE (`MAX_FAVORITES = 100`, `KYC_EXPIRY_DAYS = 180`)
- No nombres genericos: evitar `data`, `info`, `temp`, `aux`, `result`, `item`

#### Funciones
- Hacen UNA sola cosa (Single Level of Abstraction)
- Max 50 lineas (regla del proyecto)
- Max 10 parametros (usar DTO si mas)
- Sin side effects ocultos (el nombre debe reflejar todo lo que hace)
- Return early: validaciones al inicio, happy path sin anidar

```python
# MAL: anidado, largo, side effects
def process_purchase(user, vehicle, financing, insurance, payment):
    if user:
        if user.is_active:
            if vehicle:
                if vehicle.status == "active":
                    if financing:
                        # 30 lineas de logica...
                    else:
                        # 20 lineas de logica...
                else:
                    raise Error("vehiculo no disponible")
            else:
                raise Error("vehiculo requerido")
        else:
            raise Error("usuario inactivo")
    else:
        raise Error("usuario requerido")

# BIEN: return early, funciones cortas
def process_purchase(dto: PurchaseDTO) -> PurchaseIntent:
    self._validate_preconditions(dto)
    intent = PurchaseIntent.create(dto.user_id, dto.vehicle_id)
    intent = self._apply_financing(intent, dto.financing)
    intent = self._apply_insurance(intent, dto.insurance)
    return self._repository.save(intent)

def _validate_preconditions(self, dto: PurchaseDTO) -> None:
    if not dto.user_id:
        raise UserRequiredError()
    if not self._user_repo.is_active(dto.user_id):
        raise InactiveUserError()
    if not self._vehicle_repo.is_available(dto.vehicle_id):
        raise VehicleNotAvailableError()
```

#### Comentarios
- El codigo debe ser auto-explicativo; comentarios son un "olor"
- PROHIBIDO: comentarios obvios (`# incrementa el contador`, `# retorna el resultado`)
- PERMITIDO: explicar POR QUE (no QUE): `# BANXICO requiere CAT con formula especifica`
- PERMITIDO: TODOs con ticket: `# TODO [MKT-BE-017]: implementar calculo real de CAT`
- PROHIBIDO: codigo comentado (usar git para historial)
- Docstrings: solo en funciones publicas de la API y solo si el nombre no es suficiente

#### Error Handling
- Excepciones especificas de dominio, NUNCA genericas

```python
# MAL
except Exception as e:
    return {"error": str(e)}

# BIEN
except VehicleNotFoundError:
    raise  # propagar al error handler global
except InsufficientFundsError as e:
    logger.warning("insufficient_funds", user_id=user_id, amount=e.amount)
    raise
```

- Error handler global en API layer que mapea excepciones a HTTP status codes
- Nunca tragarse excepciones silenciosamente
- Logging de errores con contexto (user_id, request_id, datos relevantes)

---

### 7. Principios de Diseno

#### DRY (Don't Repeat Yourself)
- Si copias codigo 3 veces, extraer a funcion/componente compartido
- Pero NO abstraer prematuramente: 2 repeticiones NO justifican abstraer
- Preferir composicion sobre herencia

#### KISS (Keep It Simple, Stupid)
- La solucion mas simple que funciona es la mejor
- No optimizar prematuramente (profile first)
- No agregar features "por si acaso" (YAGNI)

#### YAGNI (You Aren't Gonna Need It)
- NO implementar funcionalidad especulativa
- NO agregar configurabilidad innecesaria
- NO crear abstracciones para un solo uso
- Si no esta en los criterios de aceptacion, NO lo hagas

#### Law of Demeter (Principle of Least Knowledge)
- Un objeto solo habla con sus amigos directos
- `user.get_address().get_city().get_name()` es MALO (train wreck)
- `user.get_city_name()` es BUENO

#### Composition Over Inheritance
- Preferir inyeccion de dependencias y composicion
- Herencia max 2 niveles de profundidad
- Usar mixins/protocols en vez de herencia multiple

---

### 8. Seguridad (OWASP Top 10)

#### A01 - Broken Access Control
- Verificar permisos en CADA endpoint, no solo en el frontend
- Role-based access control (RBAC) en API layer
- Nunca confiar en datos del cliente (re-validar en backend)

#### A02 - Cryptographic Failures
- Passwords: NUNCA en texto plano (Cognito maneja hashing)
- Datos sensibles (KYC docs, income) encriptados en DB (column-level)
- TLS 1.3 obligatorio para todas las comunicaciones
- Secrets en AWS Secrets Manager, NUNCA en codigo ni env files commiteados

#### A03 - Injection
- SQLAlchemy ORM previene SQL injection (NUNCA raw SQL con string formatting)
- Marshmallow valida y sanitiza inputs
- No eval(), no exec(), no f-strings con user input en queries

#### A04 - Insecure Design
- Threat modeling antes de implementar features de seguridad (KYC, pagos)
- Rate limiting en todos los endpoints publicos
- CAPTCHA en registro y login tras multiples intentos

#### A05 - Security Misconfiguration
- No exponer stack traces en produccion (error handler global)
- Headers de seguridad: CSP, X-Frame-Options, HSTS, X-Content-Type-Options
- CORS restrictivo: solo origenes permitidos
- Debug mode OFF en produccion

#### A06 - Vulnerable Components
- Dependencias actualizadas; Snyk/Trivy en CI
- No usar librerias abandonadas (sin updates en 1+ ano)
- Lock files (poetry.lock, package-lock.json) commiteados

#### A07 - Authentication Failures
- JWT con expiracion corta (15 min access, 7d refresh)
- Refresh token rotation
- Rate limiting en auth endpoints (5/min login)
- Account lockout tras 10 intentos fallidos

#### A08 - Data Integrity Failures
- Validar TODOS los inputs en backend (no confiar en validacion frontend)
- HMAC para webhooks de financieras y aseguradoras
- Checksums para archivos subidos (KYC documents)

#### A09 - Logging & Monitoring Failures
- Log TODOS los eventos de seguridad: login, failed login, role change, KYC actions
- Structured logging (JSON) con request_id para correlacion
- Alertas en: >10 failed logins/min, >5% error rate, DLQ messages
- No logear datos sensibles: passwords, tokens, numeros de tarjeta, fotos KYC

#### A10 - Server-Side Request Forgery (SSRF)
- Validar URLs externas antes de hacer requests
- Whitelist de dominios permitidos para adapter calls
- No permitir redirects arbitrarios

---

### 9. Testing Standards

#### Piramide de Tests
```
        /  E2E  \         5% — Playwright/Cypress
       / Integracion \    25% — pytest + TestClient
      /   Unitarios    \  70% — pytest + Jasmine
```

#### Tests Unitarios
- Testear logica de dominio sin infraestructura
- Mocks solo para ports (interfaces), NUNCA para logica de dominio
- Patron AAA: Arrange, Act, Assert
- Un assert por test (preferible)
- Nombres descriptivos: `test_vehicle_with_negative_price_raises_validation_error`

```python
# BIEN: test descriptivo, un assert
def test_calculate_monthly_payment_with_zero_down_payment():
    result = calculate_monthly_payment(
        price=Decimal("300000"),
        down_payment_pct=Decimal("0"),
        term_months=48,
        annual_rate=Decimal("12.5")
    )
    assert result == Decimal("7916.67")

# MAL: test generico, multiples asserts
def test_calculator():
    r1 = calc(300000, 0, 48, 12.5)
    r2 = calc(300000, 20, 48, 12.5)
    assert r1 > 0
    assert r2 > 0
    assert r1 > r2
```

#### Tests de Integracion
- Testear con DB real (PostgreSQL en Docker)
- Testear endpoints con TestClient (Flask/FastAPI)
- Fixtures para setup/teardown de datos
- Transacciones rollback entre tests

#### Coverage
- Minimo 80% global
- 100% en domain layer (logica de negocio critica)
- 90% en application layer
- 70% en infrastructure layer
- CI falla si coverage baja del minimo

---

### 10. Git & Code Review

#### Commits
- Conventional Commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`
- Mensaje descriptivo: `feat(SVC-VEH): add cursor-based pagination to vehicle listing API`
- Un commit = un cambio logico (no mega-commits)
- NUNCA commitear: .env, credentials, node_modules, __pycache__, .pyc

#### Pull Requests
- Titulo con codigo de story: `[MKT-BE-005] Add vehicle listing API with pagination`
- Descripcion con: que cambia, por que, como probar, screenshots si UI
- Max 400 lineas cambiadas por PR (dividir si es mas)
- Al menos 1 approval requerido
- CI debe pasar (build + tests + lint + security)

#### Branch Strategy
- `main` — produccion (protegido, solo merge via PR)
- `develop` — integracion (deploy a dev automatico)
- `feature/MKT-BE-005-vehicle-listing` — features
- `fix/MKT-BE-005-pagination-bug` — bug fixes
- `release/v1.0.0` — release candidates

---

### 11. Resumen Rapido para IA/Desarrolladores

```
CHECKLIST ANTES DE ESCRIBIR CODIGO:

ARQUITECTURA:
[ ] Arquitectura hexagonal? (domain sin deps externas)
[ ] SOLID principles respetados?
[ ] Dependency injection (no instanciar adapters en services)?

TAMANO:
[ ] Archivo < 1,000 lineas?
[ ] Funcion < 50 lineas?
[ ] Funcion < 10 parametros? (usar DTO si mas)
[ ] PR < 400 lineas cambiadas?

CALIDAD:
[ ] Nombres descriptivos (no abreviaciones)?
[ ] Type hints / strict types (no any)?
[ ] Return early (no anidar >3 niveles)?
[ ] Sin codigo comentado?
[ ] Sin magic numbers (usar constantes)?
[ ] Sin side effects ocultos?

SEGURIDAD:
[ ] Inputs validados en backend (Marshmallow/schemas)?
[ ] Sin SQL raw con string formatting?
[ ] Sin secrets hardcoded?
[ ] Permisos verificados en endpoint?
[ ] Datos sensibles encriptados?
[ ] Headers de seguridad configurados?

TESTING:
[ ] Tests unitarios (>80% coverage)?
[ ] Tests de integracion para endpoints?
[ ] Nombres de test descriptivos?
[ ] Mocks solo para ports/interfaces?

OPERACIONES:
[ ] Logs estructurados (JSON) con request_id?
[ ] Error handling con excepciones especificas?
[ ] Health check endpoint?
[ ] Variables de entorno para config?
[ ] Docker image construye correctamente?

GIT:
[ ] Conventional commit message?
[ ] Branch con nombre de story (feature/MKT-XX-NNN)?
[ ] PR con descripcion y screenshots?
```
