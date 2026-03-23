# [MKT-EP-002] Sistema de Autenticacion, Registro & Perfiles de Usuario

**Sprint**: 2-3
**Priority**: Critical
**Epic Owner**: Tech Lead
**Estimated Points**: 76
**Teams**: Backend, Frontend

---

## Resumen del Epic

Este epic implementa todo el sistema de identidad y acceso del marketplace: autenticacion con AWS Cognito (email/password + social login), gestion de perfiles de usuario con preferencias y favoritos, y todos los flujos de frontend incluyendo registro multi-step, login/logout, recuperacion de contrasena, y dashboard de perfil. Es prerequisito para cualquier funcionalidad que requiera usuarios autenticados (compras, favoritos, chat, etc.).

## Dependencias Externas

- AWS Cognito User Pool configurado (MKT-INF-002)
- API Gateway funcional (MKT-BE-001)
- Frontend Angular base (MKT-FE-001)
- Google OAuth 2.0 credentials (Google Cloud Console)
- Facebook Login App credentials (Meta Developer Portal)
- Apple Sign In credentials (Apple Developer Portal)
- SendGrid o SES para emails transaccionales

---

## User Story 1: [MKT-BE-003][SVC-AUTH] Servicio de Autenticacion - Cognito + JWT + Social Login

### Descripcion

Como usuario del marketplace, necesito poder registrarme e iniciar sesion de forma segura usando email/password o cuentas sociales (Google, Facebook, Apple). El servicio de autenticacion actua como intermediario entre el frontend y AWS Cognito, manejando el flujo completo de auth incluyendo registro, login, logout, refresh token, verificacion de email, reset de password, y social login federation.

### Microservicio

- **Nombre**: SVC-AUTH
- **Puerto**: 5010
- **Tecnologia**: Python 3.11, Flask 3.0, boto3 (AWS SDK)
- **Base de datos**: Redis 7 (session tokens, blacklist), Cognito (user store)
- **Patron**: Hexagonal Architecture

### Contexto Tecnico

#### Endpoints

```
POST /api/v1/auth/register              # Email/password registration
POST /api/v1/auth/login                 # Email/password login
POST /api/v1/auth/logout                # Invalidate session
POST /api/v1/auth/refresh               # Refresh access token
POST /api/v1/auth/verify-email          # Confirm email with code
POST /api/v1/auth/resend-verification   # Resend verification code
POST /api/v1/auth/forgot-password       # Initiate password reset
POST /api/v1/auth/reset-password        # Complete password reset with code
POST /api/v1/auth/change-password       # Change password (authenticated)
GET  /api/v1/auth/me                    # Get current user from token
POST /api/v1/auth/social/google         # Google OAuth callback
POST /api/v1/auth/social/facebook       # Facebook OAuth callback
POST /api/v1/auth/social/apple          # Apple Sign In callback
DELETE /api/v1/auth/account             # Request account deletion
GET  /health                            # Service health check
```

#### Estructura de Archivos

```
svc-auth/
  app/
    __init__.py
    cfg/
      __init__.py
      settings.py                  # COGNITO_USER_POOL_ID, CLIENT_ID, etc.
      cognito_config.py            # Cognito client configuration
      redis_config.py              # Redis connection for token blacklist
    dom/
      __init__.py
      models/
        __init__.py
        auth_user.py               # AuthUser domain entity
        auth_token.py              # TokenPair (access + refresh + id)
        registration.py            # RegistrationRequest value object
        social_profile.py          # SocialProfile (from OAuth providers)
      ports/
        __init__.py
        auth_provider.py           # Abstract: register, login, verify, etc.
        token_store.py             # Abstract: blacklist, validate refresh
        user_sync.py               # Abstract: sync user to SVC-USR
      services/
        __init__.py
        auth_domain_service.py     # Password validation rules, email normalization
      exceptions.py                # AuthenticationFailed, UserAlreadyExists, etc.
    app/
      __init__.py
      use_cases/
        __init__.py
        register_user.py           # RegisterUserUseCase
        login_user.py              # LoginUserUseCase
        logout_user.py             # LogoutUserUseCase
        refresh_token.py           # RefreshTokenUseCase
        verify_email.py            # VerifyEmailUseCase
        forgot_password.py         # ForgotPasswordUseCase
        reset_password.py          # ResetPasswordUseCase
        change_password.py         # ChangePasswordUseCase
        social_login.py            # SocialLoginUseCase (Google, FB, Apple)
        get_current_user.py        # GetCurrentUserUseCase
        delete_account.py          # DeleteAccountUseCase
    inf/
      __init__.py
      cognito/
        __init__.py
        cognito_auth_provider.py   # Concrete Cognito adapter (boto3)
        cognito_token_verifier.py  # JWT verification with JWKS
        cognito_social_provider.py # Social federation via Cognito
      redis/
        __init__.py
        redis_token_store.py       # Token blacklist and refresh tracking
      http/
        __init__.py
        user_service_client.py     # HTTP client to SVC-USR for profile sync
      mappers/
        __init__.py
        cognito_mapper.py          # Cognito response -> domain entity mapper
    api/
      __init__.py
      routes/
        __init__.py
        auth_routes.py             # All auth endpoints
        health_routes.py
      schemas/
        __init__.py
        auth_schemas.py            # Marshmallow schemas for auth
      middleware/
        __init__.py
        auth_required.py           # Decorator for protected endpoints
        error_handler.py
    tst/
      __init__.py
      unit/
        test_auth_domain_service.py
        test_register_user.py
        test_login_user.py
        test_social_login.py
      integration/
        test_auth_routes.py
        test_cognito_adapter.py    # With mocked Cognito (moto library)
        test_token_blacklist.py
      conftest.py
  Dockerfile
  docker-compose.yml
  requirements.txt
  .env.example
```

#### Modelo de Datos

```python
# dom/models/auth_user.py
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

@dataclass
class AuthUser:
    cognito_sub: str                # Cognito user sub (UUID)
    email: str
    email_verified: bool = False
    phone_number: Optional[str] = None
    phone_verified: bool = False
    name: Optional[str] = None
    given_name: Optional[str] = None
    family_name: Optional[str] = None
    picture: Optional[str] = None
    locale: Optional[str] = None
    roles: list[str] = field(default_factory=lambda: ["buyer"])
    auth_provider: str = "email"    # "email", "google", "facebook", "apple"
    is_active: bool = True
    created_at: Optional[datetime] = None
    last_login_at: Optional[datetime] = None

# dom/models/auth_token.py
@dataclass
class TokenPair:
    access_token: str               # JWT (short-lived, 1 hour)
    refresh_token: str              # Opaque (long-lived, 30 days)
    id_token: str                   # JWT with user claims
    token_type: str = "Bearer"
    expires_in: int = 3600          # Seconds until access token expires

# dom/models/registration.py
@dataclass
class RegistrationRequest:
    email: str
    password: str
    name: str
    given_name: Optional[str] = None
    family_name: Optional[str] = None
    phone_number: Optional[str] = None
    user_type: str = "buyer"        # "buyer", "seller", "dealer"
    accepted_terms: bool = False
    accepted_privacy: bool = False
    marketing_consent: bool = False

# dom/models/social_profile.py
@dataclass
class SocialProfile:
    provider: str                   # "google", "facebook", "apple"
    provider_user_id: str
    email: str
    name: Optional[str] = None
    picture_url: Optional[str] = None
    access_token: str = ""
    id_token: Optional[str] = None  # For Apple/Google
```

#### Marshmallow Schemas

```python
# api/schemas/auth_schemas.py
from marshmallow import Schema, fields, validate, validates, ValidationError

class RegisterSchema(Schema):
    email = fields.Email(required=True)
    password = fields.String(
        required=True,
        validate=validate.Length(min=8, max=128)
    )
    name = fields.String(required=True, validate=validate.Length(min=2, max=100))
    given_name = fields.String(validate=validate.Length(max=50))
    family_name = fields.String(validate=validate.Length(max=50))
    phone_number = fields.String(validate=validate.Regexp(r'^\+[1-9]\d{6,14}$'))
    user_type = fields.String(
        load_default="buyer",
        validate=validate.OneOf(["buyer", "seller", "dealer"])
    )
    accepted_terms = fields.Boolean(required=True)
    accepted_privacy = fields.Boolean(required=True)
    marketing_consent = fields.Boolean(load_default=False)

    @validates("password")
    def validate_password(self, value):
        errors = []
        if not any(c.isupper() for c in value):
            errors.append("Must contain at least one uppercase letter")
        if not any(c.islower() for c in value):
            errors.append("Must contain at least one lowercase letter")
        if not any(c.isdigit() for c in value):
            errors.append("Must contain at least one digit")
        if not any(c in '!@#$%^&*()_+-=[]{}|;:,.<>?' for c in value):
            errors.append("Must contain at least one special character")
        if errors:
            raise ValidationError(errors)

    @validates("accepted_terms")
    def validate_terms(self, value):
        if not value:
            raise ValidationError("Terms and conditions must be accepted")

    @validates("accepted_privacy")
    def validate_privacy(self, value):
        if not value:
            raise ValidationError("Privacy policy must be accepted")

class LoginSchema(Schema):
    email = fields.Email(required=True)
    password = fields.String(required=True)
    remember_me = fields.Boolean(load_default=False)

class RefreshTokenSchema(Schema):
    refresh_token = fields.String(required=True)

class VerifyEmailSchema(Schema):
    email = fields.Email(required=True)
    code = fields.String(required=True, validate=validate.Length(equal=6))

class ForgotPasswordSchema(Schema):
    email = fields.Email(required=True)

class ResetPasswordSchema(Schema):
    email = fields.Email(required=True)
    code = fields.String(required=True, validate=validate.Length(equal=6))
    new_password = fields.String(required=True, validate=validate.Length(min=8, max=128))

class ChangePasswordSchema(Schema):
    current_password = fields.String(required=True)
    new_password = fields.String(required=True, validate=validate.Length(min=8, max=128))

class SocialLoginSchema(Schema):
    access_token = fields.String(required=False)
    id_token = fields.String(required=False)
    authorization_code = fields.String(required=False)

class TokenResponseSchema(Schema):
    access_token = fields.String()
    refresh_token = fields.String()
    id_token = fields.String()
    token_type = fields.String()
    expires_in = fields.Integer()

class AuthUserResponseSchema(Schema):
    id = fields.String()
    email = fields.Email()
    name = fields.String()
    given_name = fields.String(allow_none=True)
    family_name = fields.String(allow_none=True)
    picture = fields.String(allow_none=True)
    roles = fields.List(fields.String())
    auth_provider = fields.String()
    email_verified = fields.Boolean()
    created_at = fields.DateTime()
```

#### Request/Response Examples

```json
// POST /api/v1/auth/register
// Request:
{
  "email": "juan.perez@example.com",
  "password": "SecureP@ss123!",
  "name": "Juan Perez",
  "given_name": "Juan",
  "family_name": "Perez",
  "phone_number": "+50760001234",
  "user_type": "buyer",
  "accepted_terms": true,
  "accepted_privacy": true,
  "marketing_consent": false
}

// Response 201:
{
  "data": {
    "id": "cognito-sub-uuid-here",
    "email": "juan.perez@example.com",
    "name": "Juan Perez",
    "email_verified": false,
    "requires_verification": true
  },
  "message": "Registration successful. Please verify your email."
}
```

```json
// POST /api/v1/auth/verify-email
// Request:
{
  "email": "juan.perez@example.com",
  "code": "482910"
}

// Response 200:
{
  "data": {
    "email_verified": true
  },
  "message": "Email verified successfully. You can now log in."
}
```

```json
// POST /api/v1/auth/login
// Request:
{
  "email": "juan.perez@example.com",
  "password": "SecureP@ss123!",
  "remember_me": true
}

// Response 200:
{
  "data": {
    "user": {
      "id": "cognito-sub-uuid-here",
      "email": "juan.perez@example.com",
      "name": "Juan Perez",
      "given_name": "Juan",
      "family_name": "Perez",
      "picture": null,
      "roles": ["buyer"],
      "auth_provider": "email",
      "email_verified": true,
      "created_at": "2026-03-20T10:30:00Z"
    },
    "tokens": {
      "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6...",
      "refresh_token": "eyJjdHkiOiJKV1QiLCJlbmMiOi...",
      "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6...",
      "token_type": "Bearer",
      "expires_in": 3600
    }
  }
}
```

```json
// POST /api/v1/auth/refresh
// Request:
{
  "refresh_token": "eyJjdHkiOiJKV1QiLCJlbmMiOi..."
}

// Response 200:
{
  "data": {
    "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6...",
    "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6...",
    "token_type": "Bearer",
    "expires_in": 3600
  }
}
```

```json
// POST /api/v1/auth/social/google
// Request:
{
  "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6..."
}

// Response 200:
{
  "data": {
    "user": {
      "id": "cognito-sub-uuid-here",
      "email": "juan.perez@gmail.com",
      "name": "Juan Perez",
      "picture": "https://lh3.googleusercontent.com/a/photo",
      "roles": ["buyer"],
      "auth_provider": "google",
      "email_verified": true,
      "is_new_user": true,
      "created_at": "2026-03-23T10:00:00Z"
    },
    "tokens": {
      "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6...",
      "refresh_token": "eyJjdHkiOiJKV1QiLCJlbmMiOi...",
      "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6...",
      "token_type": "Bearer",
      "expires_in": 3600
    }
  }
}
```

```json
// POST /api/v1/auth/forgot-password
// Request:
{
  "email": "juan.perez@example.com"
}

// Response 200 (always 200, even if email not found - security):
{
  "message": "If the email exists, a password reset code has been sent."
}
```

```json
// POST /api/v1/auth/reset-password
// Request:
{
  "email": "juan.perez@example.com",
  "code": "391847",
  "new_password": "NewSecureP@ss456!"
}

// Response 200:
{
  "message": "Password reset successfully. You can now log in with your new password."
}
```

```json
// GET /api/v1/auth/me
// Headers: Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
// Response 200:
{
  "data": {
    "id": "cognito-sub-uuid-here",
    "email": "juan.perez@example.com",
    "name": "Juan Perez",
    "given_name": "Juan",
    "family_name": "Perez",
    "picture": null,
    "roles": ["buyer"],
    "auth_provider": "email",
    "email_verified": true,
    "created_at": "2026-03-20T10:30:00Z"
  }
}
```

```json
// Error responses follow standard format:
// POST /api/v1/auth/login (invalid credentials)
// Response 401:
{
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "Email or password is incorrect.",
    "status": 401,
    "request_id": "req_xyz789"
  }
}

// POST /api/v1/auth/register (validation error)
// Response 422:
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Request validation failed.",
    "status": 422,
    "request_id": "req_abc123",
    "details": {
      "password": [
        "Must contain at least one uppercase letter",
        "Must contain at least one special character"
      ],
      "accepted_terms": [
        "Terms and conditions must be accepted"
      ]
    }
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: POST /api/v1/auth/register crea un usuario en Cognito User Pool con email, password, y atributos personalizados (user_type, name). Retorna 201 con el cognito_sub y un indicador de que requiere verificacion de email.

2. **AC-002**: POST /api/v1/auth/verify-email acepta el email y el codigo de 6 digitos enviado por Cognito. Si el codigo es correcto, marca el email como verificado y retorna 200. Si el codigo es incorrecto o expirado (5 minutos), retorna 400 con mensaje descriptivo.

3. **AC-003**: POST /api/v1/auth/login autentica contra Cognito y retorna el trio de tokens (access, refresh, id). Si el email no esta verificado, retorna 403 con codigo EMAIL_NOT_VERIFIED. Si las credenciales son invalidas, retorna 401.

4. **AC-004**: POST /api/v1/auth/refresh acepta un refresh_token valido y retorna un nuevo access_token y id_token. Si el refresh_token esta expirado o en la blacklist, retorna 401.

5. **AC-005**: POST /api/v1/auth/logout invalida el refresh token agregandolo a la blacklist en Redis (TTL = tiempo restante del token). El access token actual sigue siendo valido hasta su expiracion natural (1 hora).

6. **AC-006**: POST /api/v1/auth/social/google acepta un id_token de Google, lo verifica, y crea o vincula un usuario en Cognito mediante federation. Si el usuario es nuevo, retorna is_new_user: true para que el frontend inicie el flujo de completar perfil.

7. **AC-007**: POST /api/v1/auth/social/facebook y /social/apple funcionan de la misma manera que Google, adaptados a cada proveedor (Facebook usa access_token, Apple usa authorization_code + id_token).

8. **AC-008**: POST /api/v1/auth/forgot-password siempre retorna 200 independientemente de si el email existe (prevencion de user enumeration). Si existe, Cognito envia el codigo de reset por email.

9. **AC-009**: POST /api/v1/auth/reset-password valida el codigo y cambia la password en Cognito. La nueva password debe cumplir la misma politica del registro (8+ chars, upper, lower, number, special).

10. **AC-010**: Todos los endpoints aplican rate limiting especifico: register (5/min por IP), login (10/min por IP, lockout 15min despues de 5 fallos), forgot-password (3/min por IP), verify-email (10/min por email).

11. **AC-011**: Al registrar un nuevo usuario exitosamente (post-verificacion), el servicio hace una llamada HTTP a SVC-USR:5011 para crear el perfil de usuario con los datos basicos (sync inicial).

12. **AC-012**: GET /api/v1/auth/me decodifica el access_token JWT sin llamar a Cognito (offline validation usando JWKS keys cacheadas) y retorna los claims del usuario.

13. **AC-013**: DELETE /api/v1/auth/account marca el usuario para eliminacion en Cognito (soft delete con 30 dias de gracia) y notifica a SVC-USR para desactivar el perfil. Retorna 202 Accepted.

### Definition of Done

- [ ] Todos los endpoints implementados y testeados
- [ ] Integracion con Cognito funcional (registro, login, verify, reset)
- [ ] Social login funcional para Google, Facebook y Apple
- [ ] Token blacklist en Redis funcional
- [ ] Rate limiting por endpoint configurado
- [ ] Sync con SVC-USR al crear usuario
- [ ] Tests unitarios >= 85% cobertura
- [ ] Tests de integracion con Cognito mock (moto library)
- [ ] Documentacion de API (Swagger/OpenAPI)
- [ ] .env.example con todas las variables

### Notas Tecnicas

- Usar la libreria `moto` para mockear Cognito en tests
- Los tokens JWT de Cognito contienen: sub, email, cognito:groups (roles), exp, iat
- El id_token contiene claims de perfil (name, picture), el access_token es para autorizacion
- Para social login, Cognito maneja la federacion - el servicio solo orquesta
- El password policy se valida tanto en frontend (UX) como en backend (seguridad)
- Cognito envia emails de verificacion y reset automaticamente (customizar templates en Cognito)

### Dependencias

- MKT-INF-002: AWS Cognito User Pool configurado
- MKT-BE-001: Gateway para routing
- MKT-BE-004: SVC-USR para sync de perfil (puede hacerse async con retry)
- Redis 7 para token blacklist

---

## User Story 2: [MKT-BE-004][SVC-USR] Servicio de Usuarios - Perfiles, Preferencias, Favoritos

### Descripcion

Como usuario registrado, necesito un perfil completo con mis datos personales, preferencias de busqueda, vehiculos favoritos, historial de busquedas, y configuraciones de notificaciones. El servicio de usuarios almacena toda la informacion de perfil que no esta en Cognito, mantiene las preferencias del usuario, y gestiona la lista de favoritos.

### Microservicio

- **Nombre**: SVC-USR
- **Puerto**: 5011
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0, Marshmallow
- **Base de datos**: PostgreSQL 15 (marketplace DB), Redis 7 (cache)
- **Patron**: Hexagonal Architecture

### Contexto Tecnico

#### Endpoints

```
# Profile
GET    /api/v1/users/me                      # Get current user profile [AUTH]
PUT    /api/v1/users/me                      # Update profile [AUTH]
PATCH  /api/v1/users/me/avatar               # Upload/change avatar [AUTH]
DELETE /api/v1/users/me/avatar               # Remove avatar [AUTH]

# Preferences
GET    /api/v1/users/me/preferences          # Get user preferences [AUTH]
PUT    /api/v1/users/me/preferences          # Update preferences [AUTH]

# Favorites
GET    /api/v1/users/me/favorites            # List favorite vehicles [AUTH]
POST   /api/v1/users/me/favorites            # Add vehicle to favorites [AUTH]
DELETE /api/v1/users/me/favorites/:vehicleId # Remove from favorites [AUTH]
GET    /api/v1/users/me/favorites/check      # Check if vehicles are favorited [AUTH]

# Search History
GET    /api/v1/users/me/searches             # Recent search history [AUTH]
DELETE /api/v1/users/me/searches             # Clear search history [AUTH]
POST   /api/v1/users/me/searches             # Save a search [AUTH]

# Notifications Settings
GET    /api/v1/users/me/notifications/settings    # Get notification prefs [AUTH]
PUT    /api/v1/users/me/notifications/settings    # Update notification prefs [AUTH]

# Admin endpoints
GET    /api/v1/users/:id                     # Get user by ID [ADMIN]
GET    /api/v1/users                         # List users [ADMIN]
PUT    /api/v1/users/:id/status              # Activate/deactivate user [ADMIN]
PUT    /api/v1/users/:id/roles               # Update user roles [ADMIN]

# Internal (service-to-service)
POST   /internal/users                       # Create user profile (from SVC-AUTH)
GET    /internal/users/:id/exists            # Check if user exists

# Health
GET    /health                               # Service health
```

#### Estructura de Archivos

```
svc-user/
  app/
    __init__.py
    cfg/
      __init__.py
      settings.py
      database.py
      redis_config.py
    dom/
      __init__.py
      models/
        __init__.py
        user_profile.py            # UserProfile domain entity
        user_preferences.py        # UserPreferences value object
        favorite.py                # Favorite domain entity
        saved_search.py            # SavedSearch domain entity
        notification_settings.py   # NotificationSettings value object
        value_objects.py           # UserStatus, UserType, etc.
      ports/
        __init__.py
        user_repository.py         # Abstract user repository
        favorite_repository.py     # Abstract favorites repository
        search_history_repository.py
        cache_port.py
        storage_port.py            # Abstract file storage (S3)
      services/
        __init__.py
        user_domain_service.py     # Profile validation, completeness score
      exceptions.py
    app/
      __init__.py
      use_cases/
        __init__.py
        get_profile.py
        update_profile.py
        upload_avatar.py
        get_preferences.py
        update_preferences.py
        list_favorites.py
        add_favorite.py
        remove_favorite.py
        check_favorites.py
        get_search_history.py
        save_search.py
        clear_search_history.py
        get_notification_settings.py
        update_notification_settings.py
        create_user_internal.py    # Called by SVC-AUTH
        admin_list_users.py
        admin_update_user_status.py
      dto/
        __init__.py
        user_dto.py
        preferences_dto.py
    inf/
      __init__.py
      persistence/
        __init__.py
        sqlalchemy_models.py
        user_repository_impl.py
        favorite_repository_impl.py
        search_history_repository_impl.py
      cache/
        redis_cache_impl.py
      storage/
        s3_storage_impl.py         # Avatar upload to S3
      mappers/
        user_mapper.py
    api/
      __init__.py
      routes/
        __init__.py
        user_routes.py
        favorite_routes.py
        preference_routes.py
        search_history_routes.py
        notification_settings_routes.py
        admin_routes.py
        internal_routes.py
        health_routes.py
      schemas/
        __init__.py
        user_schemas.py
        favorite_schemas.py
        preference_schemas.py
        search_history_schemas.py
        notification_schemas.py
      middleware/
        __init__.py
        auth_required.py
        admin_required.py
        error_handler.py
    tst/
      __init__.py
      unit/
        test_user_domain_service.py
        test_update_profile.py
        test_favorites.py
        test_preferences.py
      integration/
        test_user_routes.py
        test_favorite_routes.py
        test_user_repository.py
      conftest.py
      factories.py
  migrations/
    versions/
      001_create_user_profiles_table.py
      002_create_favorites_table.py
      003_create_saved_searches_table.py
      004_create_notification_settings_table.py
  Dockerfile
  docker-compose.yml
  requirements.txt
  .env.example
```

#### Modelo de Datos

```python
# dom/models/user_profile.py
from dataclasses import dataclass, field
from datetime import datetime, date
from typing import Optional
from .value_objects import UserStatus, UserType

@dataclass
class UserProfile:
    id: str                            # Same as cognito_sub from SVC-AUTH
    email: str
    name: str
    given_name: Optional[str] = None
    family_name: Optional[str] = None
    phone_number: Optional[str] = None
    avatar_url: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None       # "male", "female", "other", "prefer_not_to_say"
    address_line_1: Optional[str] = None
    address_line_2: Optional[str] = None
    city: Optional[str] = None
    province: Optional[str] = None
    postal_code: Optional[str] = None
    country: str = "PA"                # ISO 3166-1 alpha-2
    bio: Optional[str] = None          # Short description (for sellers/dealers)
    company_name: Optional[str] = None # For dealers
    user_type: UserType = UserType.BUYER
    status: UserStatus = UserStatus.ACTIVE
    auth_provider: str = "email"
    profile_completeness: int = 0      # 0-100 percentage
    total_favorites: int = 0
    total_searches: int = 0
    total_inquiries: int = 0
    last_active_at: Optional[datetime] = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

# dom/models/user_preferences.py
@dataclass
class UserPreferences:
    user_id: str
    preferred_makes: list[str] = field(default_factory=list)     # ["Toyota", "Honda"]
    preferred_body_types: list[str] = field(default_factory=list) # ["sedan", "suv"]
    preferred_fuel_types: list[str] = field(default_factory=list) # ["gasoline", "hybrid"]
    budget_min: Optional[float] = None
    budget_max: Optional[float] = None
    preferred_year_min: Optional[int] = None
    preferred_year_max: Optional[int] = None
    preferred_provinces: list[str] = field(default_factory=list)
    preferred_transmission: Optional[str] = None
    preferred_condition: Optional[str] = None    # "new", "used", "any"
    max_mileage_km: Optional[int] = None
    currency: str = "USD"
    language: str = "es"
    distance_unit: str = "km"
    theme: str = "system"                        # "light", "dark", "system"
    updated_at: datetime = field(default_factory=datetime.utcnow)

# dom/models/favorite.py
@dataclass
class Favorite:
    id: str                            # UUID
    user_id: str
    vehicle_id: str
    vehicle_snapshot: dict             # Denormalized vehicle data at time of favoriting
    notes: Optional[str] = None        # Personal notes about this vehicle
    created_at: datetime = field(default_factory=datetime.utcnow)

# dom/models/saved_search.py
@dataclass
class SavedSearch:
    id: str                            # UUID
    user_id: str
    name: Optional[str] = None         # "My SUV search"
    filters: dict = field(default_factory=dict)  # Search parameters
    results_count: int = 0             # Number of results at save time
    alert_enabled: bool = False        # Notify when new matches found
    last_executed_at: Optional[datetime] = None
    created_at: datetime = field(default_factory=datetime.utcnow)

# dom/models/notification_settings.py
@dataclass
class NotificationSettings:
    user_id: str
    email_new_matches: bool = True     # New vehicles matching preferences
    email_price_drops: bool = True     # Price drops on favorited vehicles
    email_saved_search_alerts: bool = True
    email_messages: bool = True        # Chat messages
    email_promotions: bool = False     # Marketing emails
    email_weekly_digest: bool = True
    push_new_matches: bool = True
    push_price_drops: bool = True
    push_messages: bool = True
    push_promotions: bool = False
    sms_messages: bool = False
    sms_transaction_updates: bool = True
    quiet_hours_start: Optional[str] = None  # "22:00"
    quiet_hours_end: Optional[str] = None    # "08:00"
    updated_at: datetime = field(default_factory=datetime.utcnow)
```

#### SQLAlchemy Models

```python
# inf/persistence/sqlalchemy_models.py
from sqlalchemy import (
    Column, String, Integer, Boolean, DateTime, Date,
    Text, Float, Numeric, JSON, Index, ForeignKey, UniqueConstraint
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import uuid
from app.cfg.database import Base

class UserProfileModel(Base):
    __tablename__ = "user_profiles"

    id = Column(UUID(as_uuid=True), primary_key=True)  # = cognito_sub
    email = Column(String(255), nullable=False, unique=True, index=True)
    name = Column(String(100), nullable=False)
    given_name = Column(String(50), nullable=True)
    family_name = Column(String(50), nullable=True)
    phone_number = Column(String(20), nullable=True)
    avatar_url = Column(String(500), nullable=True)
    date_of_birth = Column(Date, nullable=True)
    gender = Column(String(30), nullable=True)
    address_line_1 = Column(String(255), nullable=True)
    address_line_2 = Column(String(255), nullable=True)
    city = Column(String(100), nullable=True)
    province = Column(String(100), nullable=True)
    postal_code = Column(String(20), nullable=True)
    country = Column(String(2), nullable=False, default="PA")
    bio = Column(Text, nullable=True)
    company_name = Column(String(200), nullable=True)
    user_type = Column(String(20), nullable=False, default="buyer", index=True)
    status = Column(String(20), nullable=False, default="active", index=True)
    auth_provider = Column(String(20), nullable=False, default="email")
    profile_completeness = Column(Integer, nullable=False, default=0)
    total_favorites = Column(Integer, default=0)
    total_searches = Column(Integer, default=0)
    total_inquiries = Column(Integer, default=0)
    last_active_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, server_default="now()")
    updated_at = Column(DateTime, nullable=False, server_default="now()", onupdate="now()")

    preferences = relationship("UserPreferencesModel", back_populates="user", uselist=False)
    favorites = relationship("FavoriteModel", back_populates="user")
    notification_settings = relationship("NotificationSettingsModel", back_populates="user", uselist=False)

class UserPreferencesModel(Base):
    __tablename__ = "user_preferences"

    user_id = Column(UUID(as_uuid=True), ForeignKey("user_profiles.id"), primary_key=True)
    preferred_makes = Column(JSON, default=[])
    preferred_body_types = Column(JSON, default=[])
    preferred_fuel_types = Column(JSON, default=[])
    budget_min = Column(Numeric(12, 2), nullable=True)
    budget_max = Column(Numeric(12, 2), nullable=True)
    preferred_year_min = Column(Integer, nullable=True)
    preferred_year_max = Column(Integer, nullable=True)
    preferred_provinces = Column(JSON, default=[])
    preferred_transmission = Column(String(30), nullable=True)
    preferred_condition = Column(String(30), nullable=True)
    max_mileage_km = Column(Integer, nullable=True)
    currency = Column(String(3), default="USD")
    language = Column(String(5), default="es")
    distance_unit = Column(String(5), default="km")
    theme = Column(String(10), default="system")
    updated_at = Column(DateTime, nullable=False, server_default="now()", onupdate="now()")

    user = relationship("UserProfileModel", back_populates="preferences")

class FavoriteModel(Base):
    __tablename__ = "favorites"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("user_profiles.id"), nullable=False, index=True)
    vehicle_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    vehicle_snapshot = Column(JSON, nullable=False)
    notes = Column(Text, nullable=True)
    created_at = Column(DateTime, nullable=False, server_default="now()")

    user = relationship("UserProfileModel", back_populates="favorites")

    __table_args__ = (
        UniqueConstraint("user_id", "vehicle_id", name="uq_user_vehicle_favorite"),
        Index("idx_favorites_user_created", "user_id", "created_at"),
    )

class SavedSearchModel(Base):
    __tablename__ = "saved_searches"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("user_profiles.id"), nullable=False, index=True)
    name = Column(String(100), nullable=True)
    filters = Column(JSON, nullable=False, default={})
    results_count = Column(Integer, default=0)
    alert_enabled = Column(Boolean, default=False)
    last_executed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, server_default="now()")

class NotificationSettingsModel(Base):
    __tablename__ = "notification_settings"

    user_id = Column(UUID(as_uuid=True), ForeignKey("user_profiles.id"), primary_key=True)
    email_new_matches = Column(Boolean, default=True)
    email_price_drops = Column(Boolean, default=True)
    email_saved_search_alerts = Column(Boolean, default=True)
    email_messages = Column(Boolean, default=True)
    email_promotions = Column(Boolean, default=False)
    email_weekly_digest = Column(Boolean, default=True)
    push_new_matches = Column(Boolean, default=True)
    push_price_drops = Column(Boolean, default=True)
    push_messages = Column(Boolean, default=True)
    push_promotions = Column(Boolean, default=False)
    sms_messages = Column(Boolean, default=False)
    sms_transaction_updates = Column(Boolean, default=True)
    quiet_hours_start = Column(String(5), nullable=True)
    quiet_hours_end = Column(String(5), nullable=True)
    updated_at = Column(DateTime, nullable=False, server_default="now()", onupdate="now()")

    user = relationship("UserProfileModel", back_populates="notification_settings")
```

#### Request/Response Examples

```json
// GET /api/v1/users/me
// Headers: X-User-ID: cognito-sub-uuid (set by gateway)
// Response 200:
{
  "data": {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "email": "juan.perez@example.com",
    "name": "Juan Perez",
    "given_name": "Juan",
    "family_name": "Perez",
    "phone_number": "+50760001234",
    "avatar_url": "https://cdn.marketplace.com/avatars/a1b2c3d4/photo.webp",
    "date_of_birth": null,
    "city": "Ciudad de Panama",
    "province": "Panama",
    "country": "PA",
    "bio": null,
    "user_type": "buyer",
    "status": "active",
    "auth_provider": "email",
    "profile_completeness": 65,
    "total_favorites": 12,
    "total_searches": 45,
    "total_inquiries": 3,
    "last_active_at": "2026-03-23T09:30:00Z",
    "created_at": "2026-03-20T10:30:00Z",
    "updated_at": "2026-03-22T14:00:00Z"
  }
}
```

```json
// PUT /api/v1/users/me
// Request:
{
  "given_name": "Juan Carlos",
  "family_name": "Perez Rodriguez",
  "phone_number": "+50760001234",
  "city": "Ciudad de Panama",
  "province": "Panama",
  "bio": "Car enthusiast looking for my next SUV."
}

// Response 200:
{
  "data": {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "name": "Juan Carlos Perez Rodriguez",
    "profile_completeness": 80,
    "updated_at": "2026-03-23T10:00:00Z"
  },
  "message": "Profile updated successfully."
}
```

```json
// GET /api/v1/users/me/favorites?cursor=eyJpZCI...&limit=10
// Response 200:
{
  "data": [
    {
      "id": "fav-uuid-1",
      "vehicle_id": "veh-uuid-1",
      "vehicle_snapshot": {
        "make": "Toyota",
        "model": "RAV4",
        "year": 2023,
        "price_usd": "32500.00",
        "mileage_km": 15000,
        "primary_image_url": "https://cdn.marketplace.com/vehicles/veh-uuid-1/main.webp",
        "status": "active"
      },
      "notes": "Great price, check in person",
      "created_at": "2026-03-22T16:00:00Z"
    }
  ],
  "pagination": {
    "next_cursor": "eyJpZCI6ImZhdi...",
    "has_next": true,
    "limit": 10,
    "total_count": 12
  }
}
```

```json
// POST /api/v1/users/me/favorites
// Request:
{
  "vehicle_id": "veh-uuid-2",
  "notes": "Nice color, affordable"
}

// Response 201:
{
  "data": {
    "id": "fav-uuid-new",
    "vehicle_id": "veh-uuid-2",
    "created_at": "2026-03-23T10:05:00Z"
  },
  "message": "Vehicle added to favorites."
}
```

```json
// GET /api/v1/users/me/favorites/check?vehicle_ids=veh-uuid-1,veh-uuid-2,veh-uuid-3
// Response 200:
{
  "data": {
    "veh-uuid-1": true,
    "veh-uuid-2": true,
    "veh-uuid-3": false
  }
}
```

```json
// GET /api/v1/users/me/preferences
// Response 200:
{
  "data": {
    "preferred_makes": ["Toyota", "Honda", "Hyundai"],
    "preferred_body_types": ["suv", "sedan"],
    "preferred_fuel_types": ["gasoline", "hybrid"],
    "budget_min": 15000.00,
    "budget_max": 40000.00,
    "preferred_year_min": 2020,
    "preferred_year_max": null,
    "preferred_provinces": ["Panama", "Chiriqui"],
    "preferred_transmission": "automatic",
    "preferred_condition": "used",
    "max_mileage_km": 80000,
    "currency": "USD",
    "language": "es",
    "distance_unit": "km",
    "theme": "dark"
  }
}
```

```json
// POST /api/v1/users/me/searches
// Request:
{
  "name": "SUVs bajo 30k",
  "filters": {
    "body_type": "suv",
    "price_max": 30000,
    "condition": "used",
    "year_min": 2020,
    "transmission": "automatic"
  },
  "alert_enabled": true
}

// Response 201:
{
  "data": {
    "id": "search-uuid-1",
    "name": "SUVs bajo 30k",
    "filters": { "body_type": "suv", "price_max": 30000, "condition": "used", "year_min": 2020, "transmission": "automatic" },
    "results_count": 245,
    "alert_enabled": true,
    "created_at": "2026-03-23T10:10:00Z"
  },
  "message": "Search saved. You will be notified when new matches are found."
}
```

### Criterios de Aceptacion

1. **AC-001**: POST /internal/users crea un perfil de usuario basico cuando SVC-AUTH notifica un nuevo registro. Los campos requeridos son: id (cognito_sub), email, name, auth_provider. Las preferencias y notification_settings se crean con valores por defecto.

2. **AC-002**: GET /api/v1/users/me retorna el perfil completo del usuario identificado por el header X-User-ID (propagado por el gateway). Si el perfil no existe, retorna 404.

3. **AC-003**: PUT /api/v1/users/me actualiza solo los campos enviados (partial update). El campo profile_completeness se recalcula automaticamente segun los campos completados (nombre=10%, telefono=10%, avatar=15%, direccion=15%, DOB=10%, etc.).

4. **AC-004**: PATCH /api/v1/users/me/avatar acepta un archivo de imagen (JPG, PNG, WebP, max 5MB), lo redimensiona a 256x256 y 64x64 (thumbnail), lo sube a S3, y actualiza avatar_url en el perfil.

5. **AC-005**: GET /api/v1/users/me/favorites retorna la lista paginada de vehiculos favoritos con cursor-based pagination. El vehicle_snapshot contiene datos denormalizados del vehiculo al momento de agregar a favoritos.

6. **AC-006**: POST /api/v1/users/me/favorites agrega un vehiculo a favoritos. Si ya existe, retorna 409 Conflict. Incrementa total_favorites y favorites_count en el vehiculo (via SVC-VEH o async).

7. **AC-007**: DELETE /api/v1/users/me/favorites/:vehicleId elimina el favorito. Decrementa total_favorites. Si no existe, retorna 404.

8. **AC-008**: GET /api/v1/users/me/favorites/check acepta un query param vehicle_ids (comma-separated, max 20) y retorna un mapa de vehicle_id -> boolean indicando cuales estan en favoritos del usuario. Util para el catalogo.

9. **AC-009**: PUT /api/v1/users/me/preferences actualiza las preferencias de busqueda del usuario. Estas preferencias se usan para: (a) pre-llenar filtros en el catalogo, (b) calcular vehiculos recomendados, (c) alertas de nuevos vehiculos.

10. **AC-010**: POST /api/v1/users/me/searches guarda una busqueda con sus filtros. Si alert_enabled=true, el sistema notificara (via SVC-NTF) cuando haya vehiculos nuevos que coincidan con los filtros.

11. **AC-011**: GET /api/v1/users/me/notifications/settings retorna todas las preferencias de notificacion. PUT actualiza solo los campos enviados. Las quiet_hours se validan (formato HH:MM, start < end).

12. **AC-012**: Los endpoints admin (GET /api/v1/users, GET /api/v1/users/:id) solo son accesibles por usuarios con rol "admin" (validado via X-User-Roles header). El listado admin soporta filtros por user_type, status, y fecha de registro.

13. **AC-013**: El perfil de usuario se cachea en Redis (TTL 10 min). El cache se invalida en PUT /api/v1/users/me. El endpoint de check favorites usa Redis para respuestas rapidas.

### Definition of Done

- [ ] Todos los endpoints implementados y testeados
- [ ] CRUD completo de perfiles con partial updates
- [ ] Upload de avatar con resize y S3 storage
- [ ] Favoritos con denormalizacion y check batch
- [ ] Busquedas guardadas con alertas
- [ ] Preferencias de notificacion completas
- [ ] Endpoints admin con role validation
- [ ] Profile completeness calculado automaticamente
- [ ] Redis cache implementado para perfiles y favoritos
- [ ] Tests >= 85% cobertura
- [ ] Migraciones Alembic funcionales

### Notas Tecnicas

- El campo vehicle_snapshot en favorites es una desnormalizacion intencional para mostrar el favorito aunque el vehiculo cambie o se elimine
- El profile_completeness se calcula con pesos: name (10), phone (10), avatar (15), DOB (10), address completa (20), bio (10), preferencias (15), verificacion (10)
- Para el check de favoritos en batch, usar un SET en Redis per-user con vehicle_ids
- Las saved_searches con alert_enabled son consumidas por WRK-NTF periodicamente
- Limitar a 50 favoritos y 20 saved searches por usuario free, ilimitado para premium

### Dependencias

- MKT-BE-001: Gateway para routing
- MKT-BE-003: SVC-AUTH para creacion inicial de perfil
- MKT-BE-002: SVC-VEH para snapshot de vehiculo al agregar favorito
- AWS S3 para almacenamiento de avatares
- Redis 7 para cache

---

## User Story 3: [MKT-FE-002][FE-FEAT-AUTH] Flujo de Registro Multi-Step

### Descripcion

Como visitante del marketplace, necesito un flujo de registro guiado, moderno y amigable que me permita crear mi cuenta paso a paso. El registro debe ser multi-step (3 pasos): datos basicos, verificacion de email, y completar perfil. Debe soportar tambien registro rapido con Google, Facebook o Apple en un solo click.

### Microservicio

- **Nombre**: FE-FEAT-AUTH (Frontend Feature - Authentication)
- **Puerto**: 4200
- **Tecnologia**: Angular 18, Tailwind CSS v4, Standalone Components, Signals

### Contexto Tecnico

#### Componentes

```
features/
  auth/
    register/
      register-page.component.ts          # Container component (manages steps)
      register-page.component.html
      register-page.component.spec.ts
      steps/
        step-credentials/
          step-credentials.component.ts    # Step 1: Email, Password, Name
          step-credentials.component.html
          step-credentials.component.spec.ts
        step-verification/
          step-verification.component.ts   # Step 2: Email verification code
          step-verification.component.html
          step-verification.component.spec.ts
        step-profile/
          step-profile.component.ts        # Step 3: Optional profile info
          step-profile.component.html
          step-profile.component.spec.ts
      components/
        social-login-buttons/
          social-login-buttons.component.ts   # Google, Facebook, Apple buttons
          social-login-buttons.component.html
        password-strength-meter/
          password-strength-meter.component.ts # Visual password strength
          password-strength-meter.component.html
        step-indicator/
          step-indicator.component.ts      # Progress bar (Step 1 of 3)
          step-indicator.component.html
        terms-checkbox/
          terms-checkbox.component.ts      # Terms & privacy with links
          terms-checkbox.component.html
    services/
      auth.service.ts                      # HTTP calls to SVC-AUTH
      social-auth.service.ts               # OAuth flow management
      registration-state.service.ts        # Signal-based state for multi-step
    auth.routes.ts
```

#### Registration State Service

```typescript
// features/auth/services/registration-state.service.ts
import { Injectable, signal, computed } from '@angular/core';

export interface RegistrationState {
  currentStep: number;              // 1, 2, or 3
  email: string;
  password: string;
  name: string;
  givenName: string;
  familyName: string;
  phoneNumber: string;
  userType: 'buyer' | 'seller' | 'dealer';
  acceptedTerms: boolean;
  acceptedPrivacy: boolean;
  marketingConsent: boolean;
  verificationCode: string;
  isEmailVerified: boolean;
  // Step 3 (optional profile)
  city: string;
  province: string;
  preferredMakes: string[];
  budgetMin: number | null;
  budgetMax: number | null;
}

@Injectable()
export class RegistrationStateService {
  private readonly _state = signal<RegistrationState>({
    currentStep: 1,
    email: '',
    password: '',
    name: '',
    givenName: '',
    familyName: '',
    phoneNumber: '',
    userType: 'buyer',
    acceptedTerms: false,
    acceptedPrivacy: false,
    marketingConsent: false,
    verificationCode: '',
    isEmailVerified: false,
    city: '',
    province: '',
    preferredMakes: [],
    budgetMin: null,
    budgetMax: null,
  });

  readonly state = this._state.asReadonly();
  readonly currentStep = computed(() => this._state().currentStep);
  readonly canProceedStep1 = computed(() => {
    const s = this._state();
    return s.email && s.password && s.name && s.acceptedTerms && s.acceptedPrivacy;
  });
  readonly canProceedStep2 = computed(() => this._state().isEmailVerified);
  readonly progressPercentage = computed(() => (this._state().currentStep / 3) * 100);

  updateState(partial: Partial<RegistrationState>): void {
    this._state.update(current => ({ ...current, ...partial }));
  }

  nextStep(): void {
    this._state.update(s => ({ ...s, currentStep: Math.min(s.currentStep + 1, 3) }));
  }

  prevStep(): void {
    this._state.update(s => ({ ...s, currentStep: Math.max(s.currentStep - 1, 1) }));
  }

  reset(): void {
    this._state.set({ /* initial state */ } as RegistrationState);
  }
}
```

#### Auth Service

```typescript
// features/auth/services/auth.service.ts
import { Injectable, inject } from '@angular/core';
import { ApiService } from '../../../core/services/api.service';
import { Observable } from 'rxjs';

export interface RegisterRequest {
  email: string;
  password: string;
  name: string;
  given_name?: string;
  family_name?: string;
  phone_number?: string;
  user_type: string;
  accepted_terms: boolean;
  accepted_privacy: boolean;
  marketing_consent: boolean;
}

export interface LoginResponse {
  user: {
    id: string;
    email: string;
    name: string;
    picture: string | null;
    roles: string[];
    auth_provider: string;
    email_verified: boolean;
  };
  tokens: {
    access_token: string;
    refresh_token: string;
    id_token: string;
    token_type: string;
    expires_in: number;
  };
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly api = inject(ApiService);

  register(data: RegisterRequest): Observable<{ data: { id: string; email: string; requires_verification: boolean } }> {
    return this.api.post('/auth/register', data);
  }

  verifyEmail(email: string, code: string): Observable<{ data: { email_verified: boolean } }> {
    return this.api.post('/auth/verify-email', { email, code });
  }

  resendVerification(email: string): Observable<{ message: string }> {
    return this.api.post('/auth/resend-verification', { email });
  }

  login(email: string, password: string, rememberMe: boolean = false): Observable<{ data: LoginResponse }> {
    return this.api.post('/auth/login', { email, password, remember_me: rememberMe });
  }

  socialLogin(provider: string, token: string): Observable<{ data: LoginResponse }> {
    return this.api.post(`/auth/social/${provider}`, { id_token: token });
  }

  refreshToken(refreshToken: string): Observable<{ data: { access_token: string } }> {
    return this.api.post('/auth/refresh', { refresh_token: refreshToken });
  }

  forgotPassword(email: string): Observable<{ message: string }> {
    return this.api.post('/auth/forgot-password', { email });
  }

  resetPassword(email: string, code: string, newPassword: string): Observable<{ message: string }> {
    return this.api.post('/auth/reset-password', { email, code, new_password: newPassword });
  }

  logout(): Observable<void> {
    return this.api.post('/auth/logout', {});
  }

  getMe(): Observable<{ data: any }> {
    return this.api.get('/auth/me');
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: La pagina de registro muestra un step indicator con 3 pasos: "Crear Cuenta", "Verificar Email", "Completar Perfil". El paso actual esta resaltado y los pasos completados muestran un checkmark.

2. **AC-002**: Step 1 (Credenciales) tiene campos: nombre completo, email, password, confirmar password, tipo de usuario (buyer/seller), checkboxes de terminos y privacidad. Todos con validacion en tiempo real.

3. **AC-003**: El campo de password muestra un password strength meter visual con 4 niveles (weak, fair, good, strong) basado en: longitud, mayusculas, minusculas, numeros, caracteres especiales. Los colores son rojo, naranja, amarillo, verde.

4. **AC-004**: La validacion del email verifica formato y muestra error inline. La validacion del password muestra los requisitos como checklist que se van marcando en verde mientras el usuario escribe.

5. **AC-005**: Los botones de social login (Google, Facebook, Apple) estan disponibles en Step 1 con el texto "Continuar con Google/Facebook/Apple". Al hacer social login exitoso, salta directamente a Step 3.

6. **AC-006**: Al completar Step 1 y hacer click en "Crear Cuenta", se llama POST /api/v1/auth/register. Si hay error (email ya existe), se muestra inline sin perder los datos del formulario. Si es exitoso, avanza a Step 2.

7. **AC-007**: Step 2 (Verificacion) muestra 6 inputs numericos individuales para el codigo de verificacion (OTP-style). Auto-avanza el focus al siguiente input al escribir un digito. Soporta paste del codigo completo.

8. **AC-008**: Step 2 tiene un timer de 60 segundos para reenviar el codigo. El boton "Reenviar codigo" esta deshabilitado hasta que el timer llega a 0. Maximo 3 reenvios.

9. **AC-009**: Al ingresar el codigo correcto, llama POST /api/v1/auth/verify-email y avanza a Step 3. Si el codigo es incorrecto, muestra error con animacion shake.

10. **AC-010**: Step 3 (Perfil) es opcional y muestra campos: telefono, ciudad, provincia, marcas preferidas (multi-select), rango de presupuesto (dual range slider). Tiene botones "Completar despues" y "Guardar y continuar".

11. **AC-011**: Al completar Step 3 (o skip), se hace login automatico del usuario y se redirige al home o a la pagina de la que venia (return URL). El estado de autenticacion se actualiza globalmente.

12. **AC-012**: Todo el flujo es responsive: en mobile los steps se muestran full-width con navegacion swipe. En desktop, el formulario esta centrado con max-width 480px y una imagen/ilustracion al costado.

13. **AC-013**: Si el usuario cierra la pagina en Step 2, al regresar al registro con el mismo email se detecta que ya esta registrado pero no verificado y se envia directo a Step 2.

### Definition of Done

- [ ] Los 3 steps del registro implementados y funcionales
- [ ] Social login con Google, Facebook y Apple funcionando
- [ ] Password strength meter visual implementado
- [ ] OTP input con auto-focus y paste implementado
- [ ] Timer de reenvio de codigo funcional
- [ ] Validaciones en tiempo real para todos los campos
- [ ] Responsive design verificado en mobile y desktop
- [ ] Tests unitarios para components y services (>= 80%)
- [ ] Transiciones animadas entre steps
- [ ] Error handling para todos los edge cases

### Notas Tecnicas

- Usar Angular reactive forms con validadores custom
- El state del registro multi-step se maneja con signals (RegistrationStateService)
- Para social login de Google, usar @abacritt/angularx-social-login o la API de Google directa
- El OTP input debe manejar keyboard events: backspace (retroceder), paste (distribuir digitos)
- Implementar debounce de 300ms en la validacion del email para evitar requests excesivos
- Guardar el return URL en sessionStorage para redirect post-registro

### Dependencias

- MKT-FE-001: Angular app base con design system
- MKT-BE-003: SVC-AUTH endpoints funcionales
- Google/Facebook/Apple OAuth credentials configuradas

---

## User Story 4: [MKT-FE-003][FE-FEAT-AUTH] Login, Logout y Recuperacion de Contrasena

### Descripcion

Como usuario registrado, necesito poder iniciar sesion con email/password o cuentas sociales, cerrar sesion de forma segura, y recuperar mi contrasena si la olvido. Los flujos deben ser rapidos, intuitivos y seguros.

### Microservicio

- **Nombre**: FE-FEAT-AUTH (Frontend Feature - Authentication)
- **Puerto**: 4200
- **Tecnologia**: Angular 18, Tailwind CSS v4, Standalone Components

### Contexto Tecnico

#### Componentes

```
features/
  auth/
    login/
      login-page.component.ts             # Login form page
      login-page.component.html
      login-page.component.spec.ts
    forgot-password/
      forgot-password-page.component.ts    # Step 1: Enter email
      forgot-password-page.component.html
      forgot-password-page.component.spec.ts
    reset-password/
      reset-password-page.component.ts     # Step 2: Code + new password
      reset-password-page.component.html
      reset-password-page.component.spec.ts
    auth.routes.ts
```

#### Auth Routes

```typescript
// features/auth/auth.routes.ts
import { Routes } from '@angular/router';
import { guestGuard } from '../../core/guards/guest.guard';

export const AUTH_ROUTES: Routes = [
  {
    path: 'login',
    loadComponent: () => import('./login/login-page.component')
      .then(m => m.LoginPageComponent),
    canActivate: [guestGuard],
    title: 'Iniciar Sesion - Vehicle Marketplace'
  },
  {
    path: 'register',
    loadComponent: () => import('./register/register-page.component')
      .then(m => m.RegisterPageComponent),
    canActivate: [guestGuard],
    title: 'Crear Cuenta - Vehicle Marketplace'
  },
  {
    path: 'forgot-password',
    loadComponent: () => import('./forgot-password/forgot-password-page.component')
      .then(m => m.ForgotPasswordPageComponent),
    canActivate: [guestGuard],
    title: 'Recuperar Contrasena - Vehicle Marketplace'
  },
  {
    path: 'reset-password',
    loadComponent: () => import('./reset-password/reset-password-page.component')
      .then(m => m.ResetPasswordPageComponent),
    canActivate: [guestGuard],
    title: 'Nueva Contrasena - Vehicle Marketplace'
  }
];
```

#### Login Page Component

```typescript
// features/auth/login/login-page.component.ts
import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { Router, RouterLink, ActivatedRoute } from '@angular/router';
import { AuthService } from '../services/auth.service';
import { AuthStateService } from '../../../core/services/auth-state.service';
import { ButtonComponent } from '../../../shared/components/ui/button/button.component';
import { InputComponent } from '../../../shared/components/ui/input/input.component';
import { SocialLoginButtonsComponent } from '../register/components/social-login-buttons/social-login-buttons.component';

@Component({
  selector: 'app-login-page',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    RouterLink,
    ButtonComponent,
    InputComponent,
    SocialLoginButtonsComponent,
  ],
  templateUrl: './login-page.component.html'
})
export class LoginPageComponent {
  private readonly fb = inject(FormBuilder);
  private readonly authService = inject(AuthService);
  private readonly authState = inject(AuthStateService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  readonly isLoading = signal(false);
  readonly errorMessage = signal<string | null>(null);

  readonly form = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required]],
    rememberMe: [false],
  });

  onSubmit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    this.isLoading.set(true);
    this.errorMessage.set(null);

    const { email, password, rememberMe } = this.form.getRawValue();
    this.authService.login(email, password, rememberMe).subscribe({
      next: (res) => {
        this.authState.setUser({
          id: res.data.user.id,
          email: res.data.user.email,
          name: res.data.user.name,
          avatar_url: res.data.user.picture,
          roles: res.data.user.roles,
          token: res.data.tokens.access_token,
        });
        // Store tokens
        const storage = rememberMe ? localStorage : sessionStorage;
        storage.setItem('access_token', res.data.tokens.access_token);
        storage.setItem('refresh_token', res.data.tokens.refresh_token);

        // Redirect to return URL or home
        const returnUrl = this.route.snapshot.queryParams['returnUrl'] || '/';
        this.router.navigateByUrl(returnUrl);
      },
      error: (err) => {
        this.isLoading.set(false);
        if (err.status === 401) {
          this.errorMessage.set('Correo electronico o contrasena incorrectos.');
        } else if (err.status === 403 && err.error?.error?.code === 'EMAIL_NOT_VERIFIED') {
          this.errorMessage.set('Tu correo no ha sido verificado. Revisa tu bandeja de entrada.');
        } else {
          this.errorMessage.set('Ocurrio un error. Intenta de nuevo.');
        }
      }
    });
  }

  onSocialLogin(provider: string, token: string): void {
    this.isLoading.set(true);
    this.authService.socialLogin(provider, token).subscribe({
      next: (res) => {
        // Same flow as email login
        this.authState.setUser({
          id: res.data.user.id,
          email: res.data.user.email,
          name: res.data.user.name,
          avatar_url: res.data.user.picture,
          roles: res.data.user.roles,
          token: res.data.tokens.access_token,
        });
        localStorage.setItem('access_token', res.data.tokens.access_token);
        localStorage.setItem('refresh_token', res.data.tokens.refresh_token);
        const returnUrl = this.route.snapshot.queryParams['returnUrl'] || '/';
        this.router.navigateByUrl(returnUrl);
      },
      error: () => {
        this.isLoading.set(false);
        this.errorMessage.set('Error al iniciar sesion con proveedor externo.');
      }
    });
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: La pagina de login muestra: campo email, campo password (con toggle show/hide), checkbox "Recordarme", boton "Iniciar Sesion", links a "Registrarse" y "Olvidaste tu contrasena?", y botones de social login.

2. **AC-002**: El login con email/password llama POST /api/v1/auth/login. Si exitoso, almacena tokens (localStorage si "Recordarme", sessionStorage si no), actualiza AuthStateService, y redirige a returnUrl o home.

3. **AC-003**: Si el login falla por credenciales invalidas (401), muestra "Correo electronico o contrasena incorrectos" sin especificar cual esta mal (seguridad). Si falla por email no verificado (403), muestra mensaje con link para reenviar codigo.

4. **AC-004**: El social login (Google, Facebook, Apple) inicia el flujo OAuth, obtiene el token del proveedor, y llama POST /api/v1/auth/social/{provider}. El UX es identico al del login normal post-autenticacion.

5. **AC-005**: El logout limpia tokens de storage, llama POST /api/v1/auth/logout, limpia el AuthStateService, y redirige a la pagina de login. El header de navegacion se actualiza inmediatamente (signals reactivos).

6. **AC-006**: La pagina "Olvidaste tu contrasena" tiene un campo de email. Al enviar, llama POST /api/v1/auth/forgot-password y muestra mensaje de confirmacion: "Si el correo existe, recibiras un codigo de recuperacion."

7. **AC-007**: La pagina "Reset Password" tiene: campo email (pre-llenado si viene de forgot-password), 6 inputs para el codigo (OTP-style), campo nueva contrasena con strength meter, campo confirmar contrasena. Al enviar, llama POST /api/v1/auth/reset-password.

8. **AC-008**: Despues de un reset de password exitoso, muestra un mensaje de exito con boton "Ir a iniciar sesion" que navega a /auth/login con el email pre-llenado.

9. **AC-009**: El auth interceptor agrega automaticamente el header Authorization: Bearer {token} a todas las requests HTTP (excepto auth endpoints). Si recibe 401, intenta refresh token automaticamente y reintenta la request original.

10. **AC-010**: Si el refresh token falla (token expirado o invalido), se hace logout automatico y se redirige a /auth/login con un toast "Tu sesion ha expirado. Por favor inicia sesion de nuevo."

11. **AC-011**: El guard de guest (guestGuard) redirige a /dashboard si el usuario ya esta autenticado. El guard de auth (authGuard) redirige a /auth/login?returnUrl={current_url} si no esta autenticado.

12. **AC-012**: Al cargar la aplicacion (APP_INITIALIZER o similar), se verifica si hay un access_token en storage. Si existe y es valido, se llama GET /api/v1/auth/me para restaurar la sesion. Si es invalido, se intenta refresh.

### Definition of Done

- [ ] Login page funcional con email/password y social login
- [ ] Logout funcional con limpieza completa de estado
- [ ] Forgot password flow completo
- [ ] Reset password flow completo
- [ ] Auth interceptor con auto-refresh implementado
- [ ] Guards (auth, guest) funcionando correctamente
- [ ] Session restoration al cargar la app
- [ ] Error handling para todos los escenarios
- [ ] Responsive design en mobile y desktop
- [ ] Tests unitarios >= 80% cobertura

### Notas Tecnicas

- El token refresh debe ser transparente para el usuario (no percibe interrupciones)
- Usar queue de requests pendientes mientras se refresca el token (evitar multiples refresh)
- El "Recordarme" determina el storage (localStorage = persistente, sessionStorage = tab only)
- Considerar rate limiting visual en login: despues de 3 intentos fallidos, mostrar captcha
- Los passwords nunca se almacenan en el frontend, solo tokens

### Dependencias

- MKT-FE-001: Angular app base, UI components
- MKT-BE-003: SVC-AUTH endpoints
- MKT-FE-002: Social login buttons (shared component)

---

## User Story 5: [MKT-FE-004][FE-FEAT-PRF] Dashboard de Perfil de Usuario

### Descripcion

Como usuario autenticado, necesito un dashboard de perfil completo donde pueda ver y editar mis datos personales, cambiar mi foto de perfil, gestionar mis preferencias de busqueda, ver mis vehiculos favoritos, revisar mi historial de busquedas, y configurar mis preferencias de notificaciones.

### Microservicio

- **Nombre**: FE-FEAT-PRF (Frontend Feature - Profile)
- **Puerto**: 4200
- **Tecnologia**: Angular 18, Tailwind CSS v4, Standalone Components, Signals

### Contexto Tecnico

#### Componentes

```
features/
  profile/
    dashboard/
      dashboard-page.component.ts          # Main dashboard with sidebar nav
      dashboard-page.component.html
    personal-info/
      personal-info-page.component.ts      # Edit personal information
      personal-info-page.component.html
      personal-info-page.component.spec.ts
      components/
        avatar-upload/
          avatar-upload.component.ts        # Drag & drop avatar with crop
          avatar-upload.component.html
        profile-completeness/
          profile-completeness.component.ts # Visual progress ring
          profile-completeness.component.html
    preferences/
      preferences-page.component.ts        # Search preferences
      preferences-page.component.html
      preferences-page.component.spec.ts
      components/
        budget-range-slider/
          budget-range-slider.component.ts  # Dual thumb range slider
          budget-range-slider.component.html
        make-selector/
          make-selector.component.ts        # Multi-select with logos
          make-selector.component.html
    favorites/
      favorites-page.component.ts          # Favorited vehicles grid
      favorites-page.component.html
      favorites-page.component.spec.ts
    saved-searches/
      saved-searches-page.component.ts     # Saved searches list
      saved-searches-page.component.html
      saved-searches-page.component.spec.ts
    notifications/
      notifications-settings-page.component.ts  # Notification preferences
      notifications-settings-page.component.html
      notifications-settings-page.component.spec.ts
    security/
      security-page.component.ts           # Change password, linked accounts
      security-page.component.html
      security-page.component.spec.ts
    services/
      profile.service.ts                   # HTTP calls to SVC-USR
      profile-state.service.ts             # Signal-based profile state
    profile.routes.ts
```

#### Profile Routes

```typescript
// features/profile/profile.routes.ts
import { Routes } from '@angular/router';

export const PROFILE_ROUTES: Routes = [
  {
    path: '',
    loadComponent: () => import('./dashboard/dashboard-page.component')
      .then(m => m.DashboardPageComponent),
    title: 'Mi Perfil - Vehicle Marketplace'
  },
  {
    path: 'personal-info',
    loadComponent: () => import('./personal-info/personal-info-page.component')
      .then(m => m.PersonalInfoPageComponent),
    title: 'Informacion Personal - Vehicle Marketplace'
  },
  {
    path: 'preferences',
    loadComponent: () => import('./preferences/preferences-page.component')
      .then(m => m.PreferencesPageComponent),
    title: 'Preferencias - Vehicle Marketplace'
  },
  {
    path: 'favorites',
    loadComponent: () => import('./favorites/favorites-page.component')
      .then(m => m.FavoritesPageComponent),
    title: 'Favoritos - Vehicle Marketplace'
  },
  {
    path: 'saved-searches',
    loadComponent: () => import('./saved-searches/saved-searches-page.component')
      .then(m => m.SavedSearchesPageComponent),
    title: 'Busquedas Guardadas - Vehicle Marketplace'
  },
  {
    path: 'notifications',
    loadComponent: () => import('./notifications/notifications-settings-page.component')
      .then(m => m.NotificationsSettingsPageComponent),
    title: 'Notificaciones - Vehicle Marketplace'
  },
  {
    path: 'security',
    loadComponent: () => import('./security/security-page.component')
      .then(m => m.SecurityPageComponent),
    title: 'Seguridad - Vehicle Marketplace'
  }
];
```

#### Profile State Service

```typescript
// features/profile/services/profile-state.service.ts
import { Injectable, signal, computed, inject } from '@angular/core';
import { ProfileService } from './profile.service';
import { toSignal } from '@angular/core/rxjs-interop';

export interface UserProfile {
  id: string;
  email: string;
  name: string;
  given_name: string | null;
  family_name: string | null;
  phone_number: string | null;
  avatar_url: string | null;
  date_of_birth: string | null;
  city: string | null;
  province: string | null;
  country: string;
  bio: string | null;
  company_name: string | null;
  user_type: string;
  profile_completeness: number;
  total_favorites: number;
  total_searches: number;
  total_inquiries: number;
  created_at: string;
}

@Injectable({ providedIn: 'root' })
export class ProfileStateService {
  private readonly _profile = signal<UserProfile | null>(null);
  private readonly _loading = signal(true);

  readonly profile = this._profile.asReadonly();
  readonly loading = this._loading.asReadonly();
  readonly completeness = computed(() => this._profile()?.profile_completeness ?? 0);
  readonly displayName = computed(() => {
    const p = this._profile();
    if (!p) return '';
    if (p.given_name && p.family_name) return `${p.given_name} ${p.family_name}`;
    return p.name;
  });
  readonly memberSince = computed(() => {
    const p = this._profile();
    if (!p) return '';
    return new Date(p.created_at).toLocaleDateString('es', { month: 'long', year: 'numeric' });
  });

  setProfile(profile: UserProfile): void {
    this._profile.set(profile);
    this._loading.set(false);
  }

  updateProfile(partial: Partial<UserProfile>): void {
    const current = this._profile();
    if (current) {
      this._profile.set({ ...current, ...partial });
    }
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: El dashboard muestra una sidebar de navegacion con secciones: Resumen, Informacion Personal, Preferencias, Favoritos, Busquedas Guardadas, Notificaciones, Seguridad. En mobile, la sidebar se convierte en un menu horizontal scrollable.

2. **AC-002**: La pagina de resumen (dashboard home) muestra: avatar con nombre, profile completeness ring (porcentaje visual circular), stats (favoritos, busquedas, consultas), actividad reciente, y tips para completar el perfil.

3. **AC-003**: El componente avatar-upload permite drag & drop o click para seleccionar imagen. Muestra preview con crop circular antes de subir. Llama PATCH /api/v1/users/me/avatar. Acepta JPG, PNG, WebP hasta 5MB.

4. **AC-004**: La pagina de informacion personal muestra un formulario con: nombre, apellido, telefono, fecha de nacimiento (date picker), genero (select), direccion (calle, ciudad, provincia, codigo postal), bio. Al guardar, llama PUT /api/v1/users/me.

5. **AC-005**: El profile completeness ring se actualiza en tiempo real cuando el usuario completa campos. Muestra un tooltip con los campos faltantes y su peso porcentual. Si llega a 100%, muestra una animacion de celebracion.

6. **AC-006**: La pagina de preferencias tiene: multi-select de marcas preferidas (con logos), selector de body types (visual con iconos), rango de presupuesto (dual range slider con inputs numericos), rango de anos, provincias, transmision, condicion, kilometraje maximo.

7. **AC-007**: La pagina de favoritos muestra los vehiculos favoritos en grid (2 columnas desktop, 1 mobile). Cada card muestra: foto, make/model/year, precio, mileage, status badge. Permite eliminar favoritos con confirmacion y agregar notas.

8. **AC-008**: Si un vehiculo favorito cambio de precio desde que fue agregado, la card muestra un badge "Precio bajo!" (verde) o "Precio subio" (rojo) comparando con el snapshot original.

9. **AC-009**: La pagina de busquedas guardadas lista las saved searches con: nombre, filtros aplicados (como tags), cantidad de resultados, toggle de alertas, fecha de creacion. Permite ejecutar la busqueda (navega al catalogo con filtros) o eliminar.

10. **AC-010**: La pagina de notificaciones muestra toggles agrupados por categoria: Email (nuevos matches, bajas de precio, alertas de busquedas, mensajes, promociones, digest semanal), Push (matches, precios, mensajes), SMS (mensajes, transacciones). Incluye quiet hours con time pickers.

11. **AC-011**: La pagina de seguridad permite: cambiar contrasena (current + new + confirm), ver cuentas sociales vinculadas (con opcion de desvincular), y solicitar eliminacion de cuenta (con modal de confirmacion que requiere escribir "ELIMINAR").

12. **AC-012**: Todos los formularios del dashboard muestran toast notifications de exito o error al guardar. Los cambios no guardados se detectan y al intentar navegar fuera se muestra un dialog "Tienes cambios sin guardar".

13. **AC-013**: El dashboard carga los datos del perfil con skeleton loading. Si algun endpoint falla, muestra un estado de error con boton de reintento, sin bloquear las otras secciones.

### Definition of Done

- [ ] Dashboard con sidebar navigation implementado
- [ ] Informacion personal editable con avatar upload
- [ ] Profile completeness ring funcional
- [ ] Preferencias de busqueda con dual range slider
- [ ] Favoritos grid con deteccion de cambios de precio
- [ ] Busquedas guardadas con toggle de alertas
- [ ] Notificaciones settings con toggles por categoria
- [ ] Seguridad con cambio de contrasena
- [ ] Unsaved changes detection implementado
- [ ] Responsive design verificado
- [ ] Skeleton loading para todas las secciones
- [ ] Tests unitarios >= 80% cobertura

### Notas Tecnicas

- Usar DashboardLayoutComponent (sidebar + content) definido en MKT-FE-001
- El profile state es global (providedIn: root) para compartir entre componentes
- El avatar upload usa FormData y multipart/form-data
- Para el crop de avatar, considerar usar ngx-image-cropper
- El dual range slider puede implementarse con noUiSlider o custom con Angular CDK
- El unsaved changes guard usa canDeactivate
- Las preferencias se usan para personalizar el feed del home en futuras iteraciones

### Dependencias

- MKT-FE-001: Angular app base, layout components, UI components
- MKT-FE-003: Auth state y session management
- MKT-BE-004: SVC-USR endpoints
- MKT-BE-003: SVC-AUTH para cambio de contrasena

---

## Resumen de Dependencias entre Stories

```
MKT-BE-003 (SVC-AUTH)
    |
    +--> MKT-BE-004 (SVC-USR) --- sync usuario al registrar
    |        |
    |        v
    |    MKT-FE-004 (Dashboard Perfil) --- consume SVC-USR
    |
    +--> MKT-FE-002 (Registro Multi-Step) --- consume SVC-AUTH
    |
    +--> MKT-FE-003 (Login/Logout) --- consume SVC-AUTH
         |
         +--> MKT-FE-004 (Dashboard Perfil) --- requiere auth state
```

## Estimacion de Esfuerzo

| Story | Estimacion | Developers |
|-------|-----------|------------|
| MKT-BE-003 (SVC-AUTH) | 13 points | 1 Backend Sr |
| MKT-BE-004 (SVC-USR) | 13 points | 1 Backend Sr |
| MKT-FE-002 (Registro) | 13 points | 1 Frontend Sr |
| MKT-FE-003 (Login/Logout) | 8 points | 1 Frontend Mid |
| MKT-FE-004 (Dashboard) | 21 points | 1 Frontend Sr + 1 Frontend Jr |
| **Total** | **68 points** | **Sprint 2-3** |
