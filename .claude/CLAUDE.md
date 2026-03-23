# Marketplace AgentsMX - Reglas de Desarrollo

ESTAS REGLAS SON OBLIGATORIAS. Cualquier IA o desarrollador DEBE cumplirlas sin excepcion.
Violar estas reglas invalida automaticamente cualquier PR o codigo generado.

## Reglas de Tamano (HARD LIMITS)

1. **Max 1,000 lineas por archivo** — dividir en modulos si se excede
2. **Max 50 lineas por funcion/metodo** — extraer sub-funciones descriptivas
3. **Max 10 parametros por funcion** — usar DTOs/dataclasses para agrupar
4. **Max 400 lineas cambiadas por PR** — dividir en PRs mas pequenos
5. **Max 3 niveles de anidacion** — usar return early y guard clauses

## Arquitectura Hexagonal (OBLIGATORIA en frontend Y backend)

```
domain/       → CERO dependencias externas, CERO imports de infrastructure/
application/  → Solo depende de domain/ports (abstracciones)
infrastructure/ → Implementa ports con tecnologias concretas
api/          → Thin controllers, solo mapea HTTP a application services
```

- Ports son ABCs (Python) o abstract classes (TypeScript)
- Adapters implementan ports en infrastructure/
- Application layer usa dependency injection (NUNCA instanciar adapters directamente)
- Domain models son puros: dataclasses (Python) o interfaces (TypeScript)

## SOLID Principles

- **S** - Single Responsibility: una clase = una razon para cambiar
- **O** - Open/Closed: extender con nuevos adapters, no modificar services
- **L** - Liskov Substitution: adapters intercambiables sin romper el sistema
- **I** - Interface Segregation: ports pequenos y especificos (3-5 metodos max)
- **D** - Dependency Inversion: depender de ports, no de implementaciones

## Clean Code Rules

- Nombres descriptivos: `calculate_monthly_payment()` NO `calc()`
- Booleanos con prefijo: `is_active`, `has_kyc`, `can_purchase`
- Constantes UPPER_SNAKE: `MAX_FAVORITES = 100`, NO magic numbers
- Return early: validaciones al inicio, no anidar
- Sin side effects ocultos en funciones
- Sin codigo comentado (usar git)
- Comentarios solo para explicar POR QUE, nunca QUE
- DRY: extraer tras 3 repeticiones (no antes)
- YAGNI: no implementar features especulativas
- KISS: la solucion mas simple que funciona

## Python (Backend)

- Type hints obligatorios en TODOS los parametros y retornos
- No bare `except:` — excepciones especificas siempre
- `dataclass` o Pydantic para datos estructurados (no dicts)
- pytest: >80% coverage, nombres descriptivos, patron AAA
- Formateo: black + isort + flake8 + mypy (pre-commit hooks)
- SQLAlchemy 2.0 style: select() no query()
- Structured logging: structlog JSON con request_id

## TypeScript (Frontend - Angular 18)

- `strict: true` en tsconfig.json
- No `any` — tipos especificos siempre
- Standalone components (no NgModules)
- Signals para state management
- OnPush change detection por defecto
- Lazy loading por feature module
- Tests: >80% coverage con Jasmine/Karma

## Seguridad (OWASP Top 10)

- Validar TODOS los inputs en backend (Marshmallow schemas)
- NUNCA SQL raw con string formatting (usar ORM)
- NUNCA secrets en codigo ni .env commiteados
- JWT con expiracion corta (15 min access, 7d refresh)
- Rate limiting en endpoints publicos
- CORS restrictivo: solo origenes permitidos
- Headers: CSP, X-Frame-Options, HSTS
- Datos sensibles encriptados en DB (KYC docs, income)
- TLS 1.3 obligatorio
- No exponer stack traces en produccion

## Testing

- Piramide: 70% unitarios, 25% integracion, 5% E2E
- Minimo 80% coverage global, 100% en domain layer
- Tests unitarios: sin infraestructura, mocks solo para ports
- Tests integracion: DB real (PostgreSQL Docker), TestClient
- Nombres: `test_vehicle_with_negative_price_raises_validation_error`
- CI falla si coverage baja del minimo

## Git

- Conventional Commits: feat:, fix:, refactor:, test:, docs:, chore:
- Branch: feature/MKT-XX-NNN-descripcion
- PR: titulo con codigo de story, descripcion con que/por que/como probar
- NUNCA commitear: .env, credentials, node_modules, __pycache__

## Nomenclatura de Microservicios

Ver README.md para tabla completa (SVC-GW, SVC-AUTH, SVC-VEH, etc.)

## Referencia Completa

- **CODING_STANDARDS.md** — Reglas completas con ejemplos de codigo
- **ARCHITECTURE.md** — Schema DB, 60+ endpoints, diagramas
- **README.md** — Nomenclatura microservicios, epicas, tech stack
- **epics/** — User stories con criterios de aceptacion
- **mockups/** — Mockups HTML por seccion
