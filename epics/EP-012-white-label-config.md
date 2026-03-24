# [MKT-EP-012] Configuracion White Label (Branding, Dominio, Features)

**Sprint**: 10-11
**Priority**: Priority 2
**Epic Owner**: Tech Lead
**Estimated Points**: 95
**Teams**: Backend, Frontend, Infrastructure

---

## Resumen del Epic

Este epic cubre el sistema completo de configuracion White Label: el motor de temas dinamico que aplica branding personalizado por tenant (logos, colores, tipografia, favicon), la configuracion de dominios custom con verificacion DNS y provisionamiento SSL, los feature toggles que habilitan/deshabilitan modulos por tenant, y el panel de administracion super admin para gestionar estas configuraciones. El nuevo servicio SVC-WHL (svc-whitelabel:5024) se encarga del rendering y theming, mientras que SVC-TNT almacena la configuracion.

## Dependencias Externas

- EP-011 completado (arquitectura multi-tenant, SVC-TNT funcional)
- AWS S3 para almacenar logos y assets de tenants
- Google Fonts API o fonts auto-hospedados para tipografias custom
- AWS ACM para certificados SSL de dominios custom
- Angular 18 con Tailwind CSS v4 (frontend base de EP-001)

---

## User Story 1: [MKT-BE-036][SVC-WHL-API] API de Configuracion White Label

### Descripcion

Como servicio White Label, necesito una API que exponga la configuracion completa de un tenant (branding, features, dominio) resuelta automaticamente desde el dominio del request. Esta API alimenta al frontend Angular para aplicar el tema correcto, y genera CSS dinamico con las variables custom del tenant. La configuracion se cachea agresivamente en Redis para minimizar latencia, ya que se consulta en cada carga de pagina.

### Microservicio

- **Nombre**: SVC-WHL
- **Puerto**: 5024
- **Tecnologia**: Python 3.11, Flask 3.0, SQLAlchemy 2.0, Marshmallow 3.x
- **Base de datos**: PostgreSQL 15 (lee de tenant_configs), Redis 7 (cache)
- **Patron**: Hexagonal Architecture (Ports & Adapters)

### Contexto Tecnico

#### Endpoints

```
# Public endpoints (no auth required, resolved from domain)
GET  /api/v1/whitelabel/config           -> Full tenant config for current domain
GET  /api/v1/whitelabel/theme.css        -> Dynamic CSS variables for current tenant
GET  /api/v1/whitelabel/manifest.json    -> PWA manifest with tenant branding
GET  /api/v1/whitelabel/branding         -> Branding assets only (logo, favicon, colors)

# Admin endpoints (super admin or tenant admin)
PUT  /api/v1/admin/tenants/:id/branding  -> Update branding configuration
PUT  /api/v1/admin/tenants/:id/features  -> Toggle features on/off
PUT  /api/v1/admin/tenants/:id/domain    -> Configure custom domain
GET  /api/v1/admin/tenants/:id/domain/verify -> Check DNS verification status
POST /api/v1/admin/tenants/:id/branding/preview -> Generate preview URL

# Health
GET  /health                              -> Service health + cache status
```

#### Estructura de Archivos

```
svc-whitelabel/
  app/
    __init__.py
    cfg/
      __init__.py
      settings.py                  # Configuracion por entorno
      database.py                  # SQLAlchemy (read-only, tenant_configs)
      redis_config.py              # Redis connection pool
      default_theme.py             # Default AgentsMX theme values
    dom/
      __init__.py
      models/
        __init__.py
        theme.py                   # Theme domain entity
        branding.py                # Branding domain entity
        feature_flags.py           # FeatureFlags domain entity
        domain_config.py           # DomainConfig domain entity
        value_objects.py           # FontFamily, ColorHex, CSSUnit, etc.
      ports/
        __init__.py
        theme_repository.py        # ABC: ThemeRepository
        branding_store.py          # ABC: BrandingStore (S3 for assets)
        theme_cache.py             # ABC: ThemeCachePort
        ssl_provisioner.py         # ABC: SSLProvisionerPort
      services/
        __init__.py
        theme_generator.py         # Genera CSS variables desde config
        feature_flag_svc.py        # Evalua feature flags
        domain_validator.py        # Valida DNS records
    app/
      __init__.py
      use_cases/
        __init__.py
        get_tenant_config.py       # Resuelve y retorna config completa
        update_branding.py         # Actualiza branding
        toggle_features.py         # Habilita/deshabilita features
        setup_custom_domain.py     # Configura dominio custom
        verify_domain_dns.py       # Verifica DNS records
        generate_theme_css.py      # Genera CSS dinamico
        generate_manifest.py       # Genera PWA manifest
    inf/
      __init__.py
      persistence/
        __init__.py
        theme_repo_impl.py         # Lee de tenant_configs table
      cache/
        __init__.py
        theme_cache_redis.py       # Redis cache implementation
      storage/
        __init__.py
        s3_branding_store.py       # S3 para logos/favicons
      ssl/
        __init__.py
        acm_ssl_provisioner.py     # AWS ACM certificate provisioning
      dns/
        __init__.py
        dns_resolver.py            # DNS verification via dnspython
    api/
      __init__.py
      routes/
        __init__.py
        whitelabel_routes.py       # Public config/theme endpoints
        branding_routes.py         # Admin branding endpoints
        domain_routes.py           # Admin domain endpoints
        health_routes.py           # GET /health
      schemas/
        __init__.py
        config_schema.py           # Response schemas
        branding_schema.py         # Branding update schemas
        features_schema.py         # Feature toggle schemas
        domain_schema.py           # Domain config schemas
      middleware/
        __init__.py
        cache_headers.py           # Set Cache-Control headers
        error_handler.py           # Standard error handling
    tst/
      __init__.py
      unit/
        test_theme_generator.py
        test_feature_flag_svc.py
        test_domain_validator.py
      integration/
        test_get_tenant_config.py
        test_theme_cache.py
      conftest.py
  Dockerfile
  docker-compose.yml
  requirements.txt
  pyproject.toml
  .env.example
```

#### Request/Response - Get Tenant Config

```json
// GET /api/v1/whitelabel/config
// (tenant resolved from Host header by gateway middleware)
// Response 200
{
  "data": {
    "tenant": {
      "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "name": "Mi Autos Puebla",
      "slug": "mi-autos-puebla",
      "plan": "pro"
    },
    "branding": {
      "logo_url": "https://cdn.agentsmx.com/tenants/f47ac10b/logo.svg",
      "logo_dark_url": "https://cdn.agentsmx.com/tenants/f47ac10b/logo-dark.svg",
      "favicon_url": "https://cdn.agentsmx.com/tenants/f47ac10b/favicon.ico",
      "primary_color": "#E11D48",
      "secondary_color": "#BE123C",
      "accent_color": "#FB923C",
      "background_color": "#FFFFFF",
      "text_color": "#1F2937",
      "font_family": "Poppins",
      "heading_font_family": "Montserrat",
      "border_radius": "12px",
      "header_style": "centered",
      "footer_style": "full"
    },
    "features": {
      "financing": true,
      "insurance": true,
      "kyc_verification": false,
      "chat": true,
      "analytics": true,
      "reports": true,
      "seo_tools": true,
      "notifications_email": true,
      "notifications_sms": true,
      "notifications_push": false,
      "vehicle_comparison": true,
      "price_history": true,
      "favorites": true,
      "share_social": true
    },
    "domain": {
      "subdomain_url": "https://miautos.agentsmx.com",
      "custom_domain_url": "https://www.miautos.com",
      "is_custom_domain_active": true
    },
    "meta": {
      "title": "Mi Autos Puebla - Los Mejores Autos",
      "description": "Encuentra tu auto ideal en Mi Autos Puebla.",
      "google_analytics_id": "G-XXXXXXXXXX",
      "facebook_pixel_id": null
    },
    "ui": {
      "show_powered_by_badge": false,
      "powered_by_text": "Powered by AgentsMX",
      "powered_by_url": "https://agentsmx.com"
    }
  },
  "cache": {
    "ttl_seconds": 300,
    "generated_at": "2026-03-24T10:00:00Z"
  }
}
```

#### Request/Response - Dynamic Theme CSS

```css
/* GET /api/v1/whitelabel/theme.css */
/* Content-Type: text/css */
/* Cache-Control: public, max-age=300 */

:root {
  /* Brand Colors */
  --color-primary: #E11D48;
  --color-primary-hover: #BE123C;
  --color-primary-light: #FEE2E2;
  --color-secondary: #BE123C;
  --color-secondary-hover: #9F1239;
  --color-accent: #FB923C;
  --color-accent-hover: #EA580C;
  --color-background: #FFFFFF;
  --color-surface: #F9FAFB;
  --color-text: #1F2937;
  --color-text-secondary: #6B7280;
  --color-text-inverse: #FFFFFF;
  --color-border: #E5E7EB;
  --color-error: #EF4444;
  --color-success: #10B981;
  --color-warning: #F59E0B;

  /* Typography */
  --font-family-body: 'Poppins', sans-serif;
  --font-family-heading: 'Montserrat', sans-serif;
  --font-size-xs: 0.75rem;
  --font-size-sm: 0.875rem;
  --font-size-base: 1rem;
  --font-size-lg: 1.125rem;
  --font-size-xl: 1.25rem;
  --font-size-2xl: 1.5rem;
  --font-size-3xl: 1.875rem;

  /* Spacing & Layout */
  --border-radius-sm: 6px;
  --border-radius-md: 12px;
  --border-radius-lg: 16px;
  --border-radius-full: 9999px;
  --shadow-sm: 0 1px 2px rgba(0,0,0,0.05);
  --shadow-md: 0 4px 6px rgba(0,0,0,0.07);
  --shadow-lg: 0 10px 15px rgba(0,0,0,0.1);

  /* Tenant-specific */
  --logo-height: 40px;
  --header-height: 64px;
}

/* Auto-generated Tailwind overrides */
.bg-primary { background-color: var(--color-primary) !important; }
.text-primary { color: var(--color-primary) !important; }
.border-primary { border-color: var(--color-primary) !important; }
.hover\:bg-primary:hover { background-color: var(--color-primary-hover) !important; }
.bg-secondary { background-color: var(--color-secondary) !important; }
.text-secondary { color: var(--color-secondary) !important; }
.bg-accent { background-color: var(--color-accent) !important; }
.text-accent { color: var(--color-accent) !important; }
.font-body { font-family: var(--font-family-body) !important; }
.font-heading { font-family: var(--font-family-heading) !important; }
.rounded-theme { border-radius: var(--border-radius-md) !important; }
```

#### CSS Generation Logic

```python
# dom/services/theme_generator.py
from dataclasses import dataclass
from typing import Optional

@dataclass
class ThemeVariables:
    primary_color: str
    secondary_color: str
    accent_color: str
    background_color: str
    text_color: str
    font_family: str
    heading_font_family: str
    border_radius: str

class ThemeGenerator:
    def generate_css(self, theme: ThemeVariables) -> str:
        """Generate CSS custom properties from theme config."""
        primary_hover = self._darken_color(theme.primary_color, 10)
        primary_light = self._lighten_color(theme.primary_color, 90)
        secondary_hover = self._darken_color(theme.secondary_color, 10)
        accent_hover = self._darken_color(theme.accent_color, 10)

        return CSS_TEMPLATE.format(
            primary=theme.primary_color,
            primary_hover=primary_hover,
            primary_light=primary_light,
            secondary=theme.secondary_color,
            secondary_hover=secondary_hover,
            accent=theme.accent_color,
            accent_hover=accent_hover,
            background=theme.background_color,
            text=theme.text_color,
            font_body=theme.font_family,
            font_heading=theme.heading_font_family,
            border_radius=theme.border_radius,
        )

    def _darken_color(self, hex_color: str, percent: int) -> str:
        """Darken a hex color by a percentage."""
        ...

    def _lighten_color(self, hex_color: str, percent: int) -> str:
        """Lighten a hex color by a percentage."""
        ...
```

### Criterios de Aceptacion

1. **AC-001**: GET /api/v1/whitelabel/config retorna la configuracion completa del tenant actual (resuelto por el gateway) incluyendo branding (logo, colores, fonts), features (flags booleanos), domain (URLs), meta (title, description, analytics), y ui (powered_by badge). El response time es menor a 50ms con cache hit.

2. **AC-002**: GET /api/v1/whitelabel/theme.css retorna un archivo CSS valido con variables custom properties (:root) generadas dinamicamente desde la configuracion del tenant. Incluye --color-primary, --color-secondary, --color-accent, --color-background, --color-text, --font-family-body, --font-family-heading, --border-radius-md. Content-Type es text/css.

3. **AC-003**: La configuracion se cachea en Redis con key "whitelabel:config:{tenant_id}" y TTL de 5 minutos. El CSS se cachea con key "whitelabel:css:{tenant_id}" y TTL de 5 minutos. Cache miss resulta en query a DB, cache hit sirve directamente desde Redis. Se envian headers Cache-Control: public, max-age=300.

4. **AC-004**: Si el tenant no tiene configuracion custom (tenant_config con branding vacio), se retornan los defaults de AgentsMX: primary_color=#2563EB, font_family=Inter, border_radius=8px, todas las features habilitadas. El sistema nunca retorna una configuracion vacia o incompleta.

5. **AC-005**: PUT /api/v1/admin/tenants/:id/branding permite actualizar logo_url, logo_dark_url, favicon_url, primary_color, secondary_color, accent_color, background_color, text_color, font_family, heading_font_family, border_radius, header_style, footer_style. Cada campo es opcional (patch semantics). Invalida el cache de Redis inmediatamente tras la actualizacion.

6. **AC-006**: PUT /api/v1/admin/tenants/:id/features permite habilitar/deshabilitar features individuales. Solo se envian los features a cambiar (patch). La validacion verifica que features premium (analytics, reports, seo_tools, notifications_sms) solo se habiliten si el plan del tenant lo permite (Pro o Enterprise).

7. **AC-007**: Los colores se validan como hex valido (^#[0-9A-Fa-f]{6}$). Las fonts se validan contra una whitelist de fonts disponibles (Inter, Poppins, Montserrat, Roboto, Open Sans, Lato, Nunito, Raleway, Playfair Display, Merriweather). El border_radius se valida como valor CSS valido (^[0-9]+(px|rem|em)$).

8. **AC-008**: GET /api/v1/whitelabel/manifest.json retorna un manifest PWA valido con name, short_name, theme_color, background_color, icons del tenant. Esto permite que el white label se instale como PWA con el branding del tenant.

9. **AC-009**: POST /api/v1/admin/tenants/:id/branding/preview genera una URL temporal (TTL 1 hora) que muestra el white label con el branding propuesto sin afectar la version en vivo. Usa query param ?preview_token=xxx para cargar config de preview en vez de la produccion.

10. **AC-010**: El theme.css genera automaticamente variantes de color: hover states (10% darker), light states (90% lighter), border states (20% opacity) para cada color primario, secundario y accent. Esto se calcula server-side para evitar calculo en el cliente.

11. **AC-011**: Los logos se suben a S3 con prefijo tenant-specific (s3://marketplace-assets/tenants/{tenant_id}/branding/) y se sirven via CloudFront CDN. Se aceptan formatos: SVG (preferido), PNG, JPEG. Tamano maximo: 2MB. Dimensiones recomendadas: logo 200x50px, favicon 32x32px.

12. **AC-012**: La API soporta Content-Negotiation: GET /api/v1/whitelabel/config con Accept: application/json retorna JSON, con Accept: text/css retorna solo el CSS. Esto simplifica la integracion para clientes que solo necesitan el CSS.

13. **AC-013**: Todos los endpoints publicos (/whitelabel/*) no requieren autenticacion JWT. Los endpoints admin (/admin/tenants/:id/*) requieren JWT con rol super_admin o tenant_admin (este ultimo solo puede modificar su propio tenant). Tenant admin modifica un tenant diferente recibe 403.

### Definition of Done

- [ ] SVC-WHL creado con estructura hexagonal completa
- [ ] Endpoints publicos de config y theme funcionales
- [ ] Endpoints admin de branding y features funcionales
- [ ] CSS generation probado con multiples configuraciones
- [ ] Cache Redis con invalidacion correcta
- [ ] Upload de logos a S3 funcional
- [ ] Tests unitarios para theme generator y feature flags
- [ ] Tests de integracion con Redis y PostgreSQL
- [ ] Cobertura >= 85%
- [ ] Dockerfile y docker-compose funcionales
- [ ] Code review aprobado

### Notas Tecnicas

- El CSS generado debe ser minificado en produccion para reducir tamano de transferencia
- Considerar pre-generar el CSS en el momento de guardar branding (no en cada request)
- Google Fonts se cargan via <link> en el HTML head, no embebidos en el CSS
- Para fonts auto-hospedados, subir los .woff2 a S3/CloudFront junto con los logos
- El manifest.json debe tener iconos en multiples tamanos: 72, 96, 128, 144, 152, 192, 384, 512

### Dependencias

- EP-011 Stories MKT-BE-031 y MKT-BE-032 completadas (SVC-TNT con modelo y API)
- EP-011 Story MKT-BE-033 completada (tenant resolution middleware)
- AWS S3 bucket para assets de tenants
- CloudFront distribution configurada (EP-011 MKT-INF-004)
- Redis 7 para cache

---

## User Story 2: [MKT-FE-028][FE-CORE] Motor de Temas Dinamico (Theme Engine)

### Descripcion

Como aplicacion Angular, necesito un motor de temas dinamico que al inicializar la app, consulte la configuracion del tenant actual via /whitelabel/config, aplique las CSS variables, cargue los assets del tenant (logo, favicon), configure los feature flags, y mantenga el tema actualizado durante toda la sesion. Este motor debe funcionar como un servicio Angular standalone que se inyecta en el APP_INITIALIZER para garantizar que el tema este listo antes de renderizar cualquier componente.

### Microservicio

- **Nombre**: Frontend Angular 18
- **Puerto**: 4200 (dev)
- **Tecnologia**: Angular 18, TypeScript 5.4, Tailwind CSS v4, Standalone Components, Signals
- **Patron**: Hexagonal Architecture (Frontend)

### Contexto Tecnico

#### Estructura de Archivos

```
src/app/
  core/
    whitelabel/
      domain/
        models/
          tenant-config.model.ts        # Interfaces para tenant config
          branding.model.ts             # Interface para branding
          feature-flags.model.ts        # Interface para feature flags
          theme-variables.model.ts      # Interface para CSS variables
        ports/
          whitelabel-config.port.ts     # Abstract class: WhitelabelConfigPort
      application/
        services/
          theme-engine.service.ts       # Orquesta aplicacion de tema
          feature-flag.service.ts       # Evalua feature flags
        use-cases/
          initialize-theme.use-case.ts  # APP_INITIALIZER entry point
      infrastructure/
        adapters/
          whitelabel-api.adapter.ts     # HTTP calls to /whitelabel/*
          whitelabel-cache.adapter.ts   # LocalStorage/SessionStorage cache
        interceptors/
          tenant-header.interceptor.ts  # Add X-Tenant-ID to requests
        guards/
          feature-flag.guard.ts         # Route guard based on features
        directives/
          if-feature.directive.ts       # *ifFeature="financing"
        pipes/
          tenant-asset.pipe.ts          # Transform asset URLs per tenant
      whitelabel.provider.ts            # DI configuration
```

#### Domain Models

```typescript
// domain/models/tenant-config.model.ts
export interface TenantConfig {
  tenant: TenantInfo;
  branding: BrandingConfig;
  features: FeatureFlags;
  domain: DomainInfo;
  meta: MetaConfig;
  ui: UIConfig;
}

export interface TenantInfo {
  id: string;
  name: string;
  slug: string;
  plan: 'free' | 'basic' | 'pro' | 'enterprise';
}

export interface BrandingConfig {
  logo_url: string | null;
  logo_dark_url: string | null;
  favicon_url: string | null;
  primary_color: string;
  secondary_color: string;
  accent_color: string;
  background_color: string;
  text_color: string;
  font_family: string;
  heading_font_family: string;
  border_radius: string;
  header_style: 'default' | 'minimal' | 'centered';
  footer_style: 'default' | 'minimal' | 'full';
}

export interface FeatureFlags {
  financing: boolean;
  insurance: boolean;
  kyc_verification: boolean;
  chat: boolean;
  analytics: boolean;
  reports: boolean;
  seo_tools: boolean;
  notifications_email: boolean;
  notifications_sms: boolean;
  notifications_push: boolean;
  vehicle_comparison: boolean;
  price_history: boolean;
  favorites: boolean;
  share_social: boolean;
}

export interface DomainInfo {
  subdomain_url: string;
  custom_domain_url: string | null;
  is_custom_domain_active: boolean;
}

export interface MetaConfig {
  title: string | null;
  description: string | null;
  google_analytics_id: string | null;
  facebook_pixel_id: string | null;
}

export interface UIConfig {
  show_powered_by_badge: boolean;
  powered_by_text: string;
  powered_by_url: string;
}
```

#### Port Definition

```typescript
// domain/ports/whitelabel-config.port.ts
import { Observable } from 'rxjs';
import { TenantConfig } from '../models/tenant-config.model';

export abstract class WhitelabelConfigPort {
  abstract getConfig(): Observable<TenantConfig>;
  abstract getThemeCSS(): Observable<string>;
  abstract getManifest(): Observable<Record<string, unknown>>;
}
```

#### Theme Engine Service

```typescript
// application/services/theme-engine.service.ts
import { Injectable, signal, computed, inject } from '@angular/core';
import { DOCUMENT } from '@angular/common';
import { Title, Meta } from '@angular/platform-browser';
import { TenantConfig, BrandingConfig } from '../../domain/models/tenant-config.model';

@Injectable({ providedIn: 'root' })
export class ThemeEngineService {
  private readonly document = inject(DOCUMENT);
  private readonly titleService = inject(Title);
  private readonly metaService = inject(Meta);

  // Signals for reactive theme state
  private readonly _config = signal<TenantConfig | null>(null);
  private readonly _isLoaded = signal<boolean>(false);

  readonly config = this._config.asReadonly();
  readonly isLoaded = this._isLoaded.asReadonly();
  readonly tenantName = computed(() => this._config()?.tenant.name ?? 'AgentsMX');
  readonly logoUrl = computed(() => this._config()?.branding.logo_url ?? '/assets/logo-default.svg');
  readonly features = computed(() => this._config()?.features);

  applyTheme(config: TenantConfig): void {
    this._config.set(config);
    this._applyBranding(config.branding);
    this._applyMeta(config.meta, config.tenant.name);
    this._applyFavicon(config.branding.favicon_url);
    this._loadFonts(config.branding.font_family, config.branding.heading_font_family);
    this._isLoaded.set(true);
  }

  private _applyBranding(branding: BrandingConfig): void {
    const root = this.document.documentElement;
    root.style.setProperty('--color-primary', branding.primary_color);
    root.style.setProperty('--color-secondary', branding.secondary_color);
    root.style.setProperty('--color-accent', branding.accent_color);
    root.style.setProperty('--color-background', branding.background_color);
    root.style.setProperty('--color-text', branding.text_color);
    root.style.setProperty('--font-family-body', branding.font_family);
    root.style.setProperty('--font-family-heading', branding.heading_font_family);
    root.style.setProperty('--border-radius-md', branding.border_radius);
  }

  private _applyMeta(meta: MetaConfig, tenantName: string): void {
    this.titleService.setTitle(meta.title ?? tenantName);
    if (meta.description) {
      this.metaService.updateTag({ name: 'description', content: meta.description });
    }
  }

  private _applyFavicon(faviconUrl: string | null): void {
    if (!faviconUrl) return;
    const link = this.document.querySelector("link[rel*='icon']") as HTMLLinkElement
      ?? this.document.createElement('link');
    link.type = 'image/x-icon';
    link.rel = 'shortcut icon';
    link.href = faviconUrl;
    this.document.head.appendChild(link);
  }

  private _loadFonts(bodyFont: string, headingFont: string): void {
    const fonts = new Set([bodyFont, headingFont]);
    fonts.forEach(font => {
      if (font === 'Inter') return; // Already loaded by default
      const link = this.document.createElement('link');
      link.rel = 'stylesheet';
      link.href = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(font)}:wght@300;400;500;600;700&display=swap`;
      this.document.head.appendChild(link);
    });
  }
}
```

#### Feature Flag Service

```typescript
// application/services/feature-flag.service.ts
import { Injectable, computed, inject } from '@angular/core';
import { ThemeEngineService } from './theme-engine.service';
import { FeatureFlags } from '../../domain/models/tenant-config.model';

@Injectable({ providedIn: 'root' })
export class FeatureFlagService {
  private readonly themeEngine = inject(ThemeEngineService);

  private readonly _features = computed(() =>
    this.themeEngine.config()?.features ?? this._defaults()
  );

  isEnabled(feature: keyof FeatureFlags): boolean {
    return this._features()?.[feature] ?? false;
  }

  readonly isFinancingEnabled = computed(() => this._features()?.financing ?? false);
  readonly isInsuranceEnabled = computed(() => this._features()?.insurance ?? false);
  readonly isChatEnabled = computed(() => this._features()?.chat ?? false);
  readonly isKycEnabled = computed(() => this._features()?.kyc_verification ?? false);
  readonly isAnalyticsEnabled = computed(() => this._features()?.analytics ?? false);

  private _defaults(): FeatureFlags {
    return {
      financing: true, insurance: true, kyc_verification: true,
      chat: true, analytics: false, reports: false, seo_tools: false,
      notifications_email: true, notifications_sms: false,
      notifications_push: false, vehicle_comparison: true,
      price_history: true, favorites: true, share_social: true,
    };
  }
}
```

#### APP_INITIALIZER

```typescript
// application/use-cases/initialize-theme.use-case.ts
import { inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ThemeEngineService } from '../services/theme-engine.service';
import { WhitelabelConfigPort } from '../../domain/ports/whitelabel-config.port';

export function initializeThemeFactory(): () => Promise<void> {
  const configPort = inject(WhitelabelConfigPort);
  const themeEngine = inject(ThemeEngineService);

  return async () => {
    try {
      const config = await firstValueFrom(configPort.getConfig());
      themeEngine.applyTheme(config);
    } catch (error) {
      console.warn('Failed to load tenant config, using defaults', error);
      themeEngine.applyTheme(DEFAULT_AGENTSMX_CONFIG);
    }
  };
}

// In app.config.ts:
// providers: [
//   { provide: APP_INITIALIZER, useFactory: initializeThemeFactory, multi: true },
//   { provide: WhitelabelConfigPort, useClass: WhitelabelApiAdapter },
// ]
```

#### Structural Directive for Feature Flags

```typescript
// infrastructure/directives/if-feature.directive.ts
import { Directive, Input, TemplateRef, ViewContainerRef, inject, OnInit } from '@angular/core';
import { FeatureFlagService } from '../../application/services/feature-flag.service';
import { FeatureFlags } from '../../domain/models/tenant-config.model';

@Directive({ selector: '[ifFeature]', standalone: true })
export class IfFeatureDirective implements OnInit {
  @Input({ required: true }) ifFeature!: keyof FeatureFlags;

  private readonly featureFlags = inject(FeatureFlagService);
  private readonly templateRef = inject(TemplateRef);
  private readonly viewContainer = inject(ViewContainerRef);

  ngOnInit(): void {
    if (this.featureFlags.isEnabled(this.ifFeature)) {
      this.viewContainer.createEmbeddedView(this.templateRef);
    } else {
      this.viewContainer.clear();
    }
  }
}

// Usage in template:
// <app-financing-card *ifFeature="'financing'" />
// <app-insurance-card *ifFeature="'insurance'" />
// <app-chat-widget *ifFeature="'chat'" />
```

### Criterios de Aceptacion

1. **AC-001**: El ThemeEngineService se ejecuta como APP_INITIALIZER antes de que cualquier componente se renderice. La app no muestra contenido hasta que el tema este aplicado (evita flash of unstyled content). Si la API falla, se aplican los defaults de AgentsMX en menos de 3 segundos.

2. **AC-002**: Las CSS variables se aplican correctamente al documentElement (:root) incluyendo: --color-primary, --color-secondary, --color-accent, --color-background, --color-text, --font-family-body, --font-family-heading, --border-radius-md. Se verifica que todos los componentes que usan estas variables reflejan los colores del tenant.

3. **AC-003**: El logo del tenant se carga en el header y reemplaza el logo default de AgentsMX. Si logo_url es null, se muestra el logo default. Si logo_dark_url existe y el sistema detecta dark mode, se usa el logo dark. El logo se carga via <img> con alt="[tenant_name]".

4. **AC-004**: El favicon se actualiza dinamicamente al favicon del tenant. Si favicon_url es null, se mantiene el favicon default. Se verifica que el browser tab muestra el favicon correcto del tenant.

5. **AC-005**: Las Google Fonts se cargan dinamicamente via <link> inyectado en el <head>. Solo se cargan las fonts que el tenant necesita (si font_family y heading_font_family son iguales, solo una carga). Se cargan los pesos 300, 400, 500, 600, 700. Display: swap para evitar FOIT.

6. **AC-006**: La directiva *ifFeature muestra u oculta secciones del UI segun los feature flags del tenant. Si financing es false, toda la seccion de financiamiento desaparece del catalogo y detalle de vehiculo. Si chat es false, el widget de chat no se renderiza. Se verifica con al menos 5 features diferentes.

7. **AC-007**: El FeatureFlagService expone signals computados (isFinancingEnabled, isInsuranceEnabled, etc.) que se actualizan reactivamente si la configuracion cambia. Los componentes que dependen de estos signals se re-renderizan automaticamente.

8. **AC-008**: El route guard FeatureFlagGuard previene la navegacion a rutas de features deshabilitados. Si un usuario intenta navegar a /financing y financing es false, se redirige a /home con un mensaje. Las rutas protegidas: /financing, /insurance, /kyc, /chat, /analytics, /reports.

9. **AC-009**: El meta title y meta description se actualizan con los valores del tenant config. Si google_analytics_id esta configurado, se inyecta el script de GA4 dinamicamente. Si facebook_pixel_id esta configurado, se inyecta el pixel de Facebook.

10. **AC-010**: La configuracion se cachea en sessionStorage con key "wl_config_{tenant_slug}" y TTL de 5 minutos. En la siguiente navegacion dentro del TTL, la config se lee de sessionStorage sin hacer API call. El cache se invalida si el usuario cambia de tenant.

11. **AC-011**: El interceptor TenantHeaderInterceptor agrega el header X-Tenant-ID a todos los requests HTTP salientes del frontend. El tenant_id se obtiene del ThemeEngineService.config(). Requests a dominios externos (Google Fonts, analytics) no incluyen el header.

12. **AC-012**: El pipe TenantAssetPipe transforma URLs de assets al formato CDN del tenant: {{ 'logo.svg' | tenantAsset }} se resuelve a "https://cdn.agentsmx.com/tenants/{tenant_id}/logo.svg". Simplifica el uso de assets tenant-specific en templates.

13. **AC-013**: En modo desarrollo, se puede forzar un tenant_id via query param ?_tenant=miautos para probar diferentes temas sin cambiar de dominio. Esta funcionalidad solo esta habilitada cuando isDevMode() retorna true.

### Definition of Done

- [ ] ThemeEngineService implementado y funcional como APP_INITIALIZER
- [ ] CSS variables aplicadas correctamente (verificado visualmente en 3 tenants diferentes)
- [ ] Feature flags funcionales con directiva *ifFeature
- [ ] Route guards para features deshabilitados
- [ ] Google Fonts cargando dinamicamente
- [ ] Favicon y meta tags actualizandose por tenant
- [ ] Cache en sessionStorage funcional
- [ ] Tests unitarios para ThemeEngine, FeatureFlags, directivas
- [ ] Tests con configuracion default (fallback)
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- APP_INITIALIZER retorna Promise; si se rechaza, la app no arranca. Siempre hacer catch con fallback a defaults
- Usar signals de Angular 18 en vez de BehaviorSubject para estado reactivo
- Las CSS variables deben usar !important solo en las clases utility de Tailwind override, no en las variables :root
- Considerar Server-Side Rendering (SSR) en el futuro: el tema debe poder aplicarse en el servidor
- El interceptor no debe agregar X-Tenant-ID a requests de assets (CloudFront), solo a API calls

### Dependencias

- Story MKT-BE-036 completada (API de config white label)
- Angular 18 con Tailwind CSS v4 configurado (EP-001)
- Standalone components (no NgModules)
- Signals API de Angular 18

---

## User Story 3: [MKT-FE-029][FE-LAYOUT] Layout Adaptable por Tenant

### Descripcion

Como frontend Angular, necesito que el layout principal de la aplicacion (header, footer, sidebar) se adapte dinamicamente al branding y configuracion del tenant. El header muestra el logo del tenant con su nombre, navegacion personalizada segun features habilitados, y colores del tema. El footer muestra informacion de contacto del tenant, links a redes sociales, y opcionalmente el badge "Powered by AgentsMX". El sidebar solo muestra las secciones habilitadas por los feature flags del tenant.

### Microservicio

- **Nombre**: Frontend Angular 18
- **Puerto**: 4200 (dev)
- **Tecnologia**: Angular 18, TypeScript 5.4, Tailwind CSS v4, Standalone Components, Signals
- **Patron**: Hexagonal Architecture (Frontend) - Presentation Layer

### Contexto Tecnico

#### Estructura de Archivos

```
src/app/
  shared/
    layout/
      header/
        header.component.ts            # Standalone, OnPush
        header.component.html
        header.component.spec.ts
      footer/
        footer.component.ts
        footer.component.html
        footer.component.spec.ts
      sidebar/
        sidebar.component.ts
        sidebar.component.html
        sidebar.component.spec.ts
      main-layout/
        main-layout.component.ts       # Shell layout with header/sidebar/footer
        main-layout.component.html
        main-layout.component.spec.ts
      powered-by-badge/
        powered-by-badge.component.ts
        powered-by-badge.component.html
        powered-by-badge.component.spec.ts
```

#### Header Component

```typescript
// shared/layout/header/header.component.ts
import { Component, inject, computed, ChangeDetectionStrategy } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { ThemeEngineService } from '../../../core/whitelabel/application/services/theme-engine.service';
import { FeatureFlagService } from '../../../core/whitelabel/application/services/feature-flag.service';
import { IfFeatureDirective } from '../../../core/whitelabel/infrastructure/directives/if-feature.directive';

interface NavItem {
  label: string;
  route: string;
  feature?: keyof FeatureFlags;
  icon: string;
}

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, IfFeatureDirective],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './header.component.html',
})
export class HeaderComponent {
  private readonly themeEngine = inject(ThemeEngineService);
  private readonly featureFlags = inject(FeatureFlagService);

  readonly logoUrl = this.themeEngine.logoUrl;
  readonly tenantName = this.themeEngine.tenantName;
  readonly headerStyle = computed(() =>
    this.themeEngine.config()?.branding.header_style ?? 'default'
  );

  readonly navItems = computed<NavItem[]>(() => {
    const items: NavItem[] = [
      { label: 'Catalogo', route: '/vehicles', icon: 'car' },
    ];
    if (this.featureFlags.isFinancingEnabled()) {
      items.push({ label: 'Financiamiento', route: '/financing', icon: 'credit-card' });
    }
    if (this.featureFlags.isInsuranceEnabled()) {
      items.push({ label: 'Seguros', route: '/insurance', icon: 'shield' });
    }
    return items;
  });

  readonly isMobileMenuOpen = signal(false);

  toggleMobileMenu(): void {
    this.isMobileMenuOpen.update(v => !v);
  }
}
```

#### Header Template

```html
<!-- header.component.html -->
<header class="sticky top-0 z-50 bg-white shadow-sm border-b border-gray-100"
        [class.header-centered]="headerStyle() === 'centered'"
        [class.header-minimal]="headerStyle() === 'minimal'">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
    <div class="flex items-center justify-between"
         [style.height.px]="64">

      <!-- Logo -->
      <a routerLink="/" class="flex items-center gap-3">
        <img [src]="logoUrl()"
             [alt]="tenantName()"
             class="h-10 w-auto object-contain"
             loading="eager" />
        @if (headerStyle() !== 'minimal') {
          <span class="text-lg font-heading font-semibold text-gray-900">
            {{ tenantName() }}
          </span>
        }
      </a>

      <!-- Desktop Navigation -->
      <nav class="hidden md:flex items-center gap-6">
        @for (item of navItems(); track item.route) {
          <a [routerLink]="item.route"
             routerLinkActive="text-primary border-b-2 border-primary"
             class="text-sm font-medium text-gray-700 hover:text-primary
                    transition-colors py-5">
            {{ item.label }}
          </a>
        }
      </nav>

      <!-- Auth & Mobile Menu -->
      <div class="flex items-center gap-4">
        <a routerLink="/auth/login"
           class="hidden sm:inline-flex items-center px-4 py-2 rounded-theme
                  bg-primary text-white text-sm font-medium hover:bg-primary-hover
                  transition-colors">
          Iniciar Sesion
        </a>
        <button (click)="toggleMobileMenu()"
                class="md:hidden p-2 rounded-lg hover:bg-gray-100">
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                  d="M4 6h16M4 12h16M4 18h16"/>
          </svg>
        </button>
      </div>
    </div>
  </div>

  <!-- Mobile Menu -->
  @if (isMobileMenuOpen()) {
    <div class="md:hidden border-t border-gray-100 bg-white">
      <div class="px-4 py-3 space-y-2">
        @for (item of navItems(); track item.route) {
          <a [routerLink]="item.route"
             (click)="toggleMobileMenu()"
             class="block px-3 py-2 rounded-lg text-sm font-medium text-gray-700
                    hover:bg-gray-50 hover:text-primary">
            {{ item.label }}
          </a>
        }
      </div>
    </div>
  }
</header>
```

#### Footer Component

```typescript
// shared/layout/footer/footer.component.ts
@Component({
  selector: 'app-footer',
  standalone: true,
  imports: [RouterLink, IfFeatureDirective, PoweredByBadgeComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './footer.component.html',
})
export class FooterComponent {
  private readonly themeEngine = inject(ThemeEngineService);

  readonly tenantName = this.themeEngine.tenantName;
  readonly footerStyle = computed(() =>
    this.themeEngine.config()?.branding.footer_style ?? 'default'
  );
  readonly showPoweredBy = computed(() =>
    this.themeEngine.config()?.ui.show_powered_by_badge ?? true
  );
  readonly currentYear = new Date().getFullYear();
}
```

### Criterios de Aceptacion

1. **AC-001**: El header muestra el logo del tenant actual cargado desde logo_url. El logo tiene alt text con el nombre del tenant, height de 40px, y carga con loading="eager". Si logo_url es null, se muestra un placeholder con las iniciales del tenant en un circulo con el color primario.

2. **AC-002**: El header adapta su estilo segun header_style de la config: "default" muestra logo izquierda + nav derecha, "centered" muestra logo centrado con nav debajo, "minimal" muestra solo logo sin texto del tenant name. Los tres estilos se implementan con clases CSS condicionales.

3. **AC-003**: La navegacion principal se genera dinamicamente basandose en los feature flags. Solo se muestran los links a secciones habilitadas: Catalogo (siempre visible), Financiamiento (si financing=true), Seguros (si insurance=true). Un tenant con financing=false no ve el link de financiamiento.

4. **AC-004**: El menu mobile (hamburger) se muestra en pantallas < 768px (md breakpoint de Tailwind). Al hacer click, se despliega un panel con los mismos links filtrados por features. El menu se cierra al navegar a una ruta.

5. **AC-005**: El footer muestra informacion de contacto del tenant (email, telefono), links utiles (Catalogo, FAQ, Terminos, Privacidad), y redes sociales del tenant. Cuando footer_style es "minimal", solo muestra copyright y powered by. Cuando es "full", muestra todo en 4 columnas.

6. **AC-006**: El componente PoweredByBadge muestra "Powered by AgentsMX" con link a agentsmx.com. Se muestra solo si show_powered_by_badge es true en la config del tenant. Tenants con plan Pro o Enterprise pueden ocultarlo. El badge tiene estilo discreto (texto gris pequeno).

7. **AC-007**: Todos los colores del layout usan CSS variables: botones usan bg-primary y hover:bg-primary-hover, texto de links activos usa text-primary, bordes usan border-primary. Se verifica visualmente que cambiar los colores del tenant cambia toda la apariencia del layout.

8. **AC-008**: Las fonts del layout usan las variables: titulos usan font-heading (var(--font-family-heading)), body text usa font-body (var(--font-family-body)). Se verifica que las fonts personalizadas del tenant se aplican correctamente en header y footer.

9. **AC-009**: El border-radius de botones, cards y inputs usa var(--border-radius-md) via la clase rounded-theme. Un tenant con border_radius="16px" tiene esquinas mas redondeadas que uno con "4px". Se verifica en botones del header, cards del catalogo, e inputs de busqueda.

10. **AC-010**: El layout es responsive: header colapsa a hamburger menu en mobile, footer cambia a stack vertical en mobile, sidebar se oculta y se accede via drawer en mobile. Se verifica en breakpoints: 320px (mobile), 768px (tablet), 1024px (desktop), 1280px (wide).

11. **AC-011**: Todos los componentes de layout usan ChangeDetectionStrategy.OnPush y dependen de signals para reactividad. No hay subscripciones manuales a observables en los componentes de layout. Se verifica que no hay memory leaks con la herramienta de profiling de Angular.

12. **AC-012**: Los tests unitarios de cada componente de layout verifican: (a) rendering con config default, (b) rendering con config personalizado (colores, logo, features), (c) navegacion filtrada por features, (d) responsive behavior, (e) powered by badge visibility.

### Definition of Done

- [ ] HeaderComponent implementado con estilos dinamicos (default/centered/minimal)
- [ ] FooterComponent implementado con estilos dinamicos (default/minimal/full)
- [ ] SidebarComponent con filtraje por feature flags
- [ ] PoweredByBadge configurable por plan
- [ ] Responsive design verificado en 4 breakpoints
- [ ] CSS variables aplicadas en todos los elementos de layout
- [ ] OnPush + signals en todos los componentes
- [ ] Tests unitarios con cobertura >= 85%
- [ ] Visual QA con 3 configuraciones de tenant diferentes
- [ ] Code review aprobado

### Notas Tecnicas

- Usar @for de Angular 18 (no *ngFor) para iteracion en templates
- Usar @if de Angular 18 (no *ngIf) para condicionales en templates
- Tailwind CSS v4 con JIT mode para generar solo las clases usadas
- Las clases CSS dinamicas (bg-primary, etc.) se definen en theme.css, no como clases Tailwind puras
- El header sticky (top-0 z-50) no debe interferir con modals o dropdowns (z-index management)

### Dependencias

- Story MKT-FE-028 completada (ThemeEngine y FeatureFlags services)
- Tailwind CSS v4 configurado con custom theme
- Router de Angular 18 configurado con lazy loading

---

## User Story 4: [MKT-BE-037][SVC-WHL-INF] Custom Domain Setup & SSL

### Descripcion

Como sistema de configuracion de dominios, necesito un flujo completo para que un tenant pueda configurar su dominio custom (ej: www.miautos.com) en su white label. El flujo incluye: (1) el tenant ingresa su dominio deseado, (2) el sistema genera instrucciones DNS con un token de verificacion CNAME, (3) un background job verifica periodicamente si el registro DNS fue configurado, (4) tras verificacion exitosa, se provisiona automaticamente un certificado SSL via AWS ACM, (5) el certificado se adjunta al ALB listener, (6) el dominio queda activo y funcional con HTTPS.

### Microservicio

- **Nombre**: SVC-WHL
- **Puerto**: 5024
- **Tecnologia**: Python 3.11, Flask 3.0, dnspython, boto3 (AWS SDK)
- **Base de datos**: PostgreSQL 15 (custom_domain_mappings), Redis 7
- **Patron**: Hexagonal Architecture - Infrastructure Layer

### Contexto Tecnico

#### Endpoints

```
# Custom Domain Management (Tenant Admin or Super Admin)
PUT  /api/v1/admin/tenants/:id/domain            -> Initiate custom domain setup
GET  /api/v1/admin/tenants/:id/domain             -> Get domain status & DNS instructions
GET  /api/v1/admin/tenants/:id/domain/verify      -> Trigger manual DNS verification
DELETE /api/v1/admin/tenants/:id/domain            -> Remove custom domain

# Internal (called by background job)
POST /internal/domain/verify-pending               -> Verify all pending domains
POST /internal/domain/provision-ssl/:domain_id     -> Provision SSL for verified domain
```

#### Request/Response - Setup Custom Domain

```json
// PUT /api/v1/admin/tenants/:id/domain
// Request
{
  "custom_domain": "www.miautos.com"
}

// Response 200
{
  "data": {
    "domain": "www.miautos.com",
    "status": "pending_dns_verification",
    "dns_instructions": {
      "type": "CNAME",
      "host": "_acme-challenge.www.miautos.com",
      "value": "dcv-token-a1b2c3d4e5f6.custom.agentsmx.com",
      "ttl": 300,
      "instruction_text": "Agrega el siguiente registro CNAME en tu proveedor de DNS (GoDaddy, Namecheap, Cloudflare, etc.):"
    },
    "additional_cname": {
      "type": "CNAME",
      "host": "www.miautos.com",
      "value": "custom.agentsmx.com",
      "ttl": 300,
      "instruction_text": "Agrega este registro CNAME para apuntar tu dominio a nuestros servidores:"
    },
    "verification_deadline": "2026-03-27T10:00:00Z",
    "created_at": "2026-03-24T10:00:00Z"
  }
}
```

#### Request/Response - Domain Status

```json
// GET /api/v1/admin/tenants/:id/domain
// Response 200
{
  "data": {
    "domain": "www.miautos.com",
    "status": "ssl_provisioning",
    "dns_verified": true,
    "dns_verified_at": "2026-03-24T11:30:00Z",
    "ssl_provisioned": false,
    "ssl_certificate_arn": "arn:aws:acm:us-east-1:123456789:certificate/abc-123",
    "ssl_status": "PENDING_VALIDATION",
    "steps": [
      { "step": 1, "name": "DNS Verification Token", "status": "completed", "completed_at": "2026-03-24T11:30:00Z" },
      { "step": 2, "name": "DNS CNAME Record", "status": "completed", "completed_at": "2026-03-24T11:30:00Z" },
      { "step": 3, "name": "SSL Certificate", "status": "in_progress", "started_at": "2026-03-24T11:31:00Z" },
      { "step": 4, "name": "Load Balancer Configuration", "status": "pending" },
      { "step": 5, "name": "Domain Active", "status": "pending" }
    ],
    "estimated_completion": "2026-03-24T12:00:00Z"
  }
}
```

#### Domain Verification Logic

```python
# dom/services/domain_validator.py
import dns.resolver
from dataclasses import dataclass

@dataclass
class DNSVerificationResult:
    domain: str
    is_cname_valid: bool
    is_verification_valid: bool
    cname_target: str | None
    verification_target: str | None
    error: str | None

class DomainValidator:
    VERIFICATION_PREFIX = "_acme-challenge"
    EXPECTED_CNAME_TARGET = "custom.agentsmx.com"

    def verify_domain(self, domain: str,
                      verification_token: str) -> DNSVerificationResult:
        """Verify both CNAME and verification token DNS records."""
        cname_valid = self._check_cname(domain)
        verification_valid = self._check_verification_token(
            domain, verification_token
        )
        return DNSVerificationResult(
            domain=domain,
            is_cname_valid=cname_valid,
            is_verification_valid=verification_valid,
            cname_target=self._resolve_cname(domain),
            verification_target=self._resolve_cname(
                f"{self.VERIFICATION_PREFIX}.{domain}"
            ),
            error=None
        )

    def _check_cname(self, domain: str) -> bool:
        """Verify domain has CNAME pointing to custom.agentsmx.com."""
        try:
            answers = dns.resolver.resolve(domain, 'CNAME')
            for rdata in answers:
                target = str(rdata.target).rstrip('.')
                if target == self.EXPECTED_CNAME_TARGET:
                    return True
            return False
        except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer,
                dns.resolver.NoNameservers):
            return False

    def _check_verification_token(self, domain: str,
                                   token: str) -> bool:
        """Verify _acme-challenge.domain has correct token."""
        try:
            fqdn = f"{self.VERIFICATION_PREFIX}.{domain}"
            answers = dns.resolver.resolve(fqdn, 'CNAME')
            for rdata in answers:
                target = str(rdata.target).rstrip('.')
                if token in target:
                    return True
            return False
        except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer,
                dns.resolver.NoNameservers):
            return False

    def _resolve_cname(self, domain: str) -> str | None:
        """Resolve CNAME record for a domain."""
        try:
            answers = dns.resolver.resolve(domain, 'CNAME')
            return str(list(answers)[0].target).rstrip('.')
        except Exception:
            return None
```

#### Background Job - Domain Verification Worker

```python
# inf/jobs/domain_verification_worker.py
import schedule
import time
from datetime import datetime, timedelta

class DomainVerificationWorker:
    POLL_INTERVAL_MINUTES = 5
    MAX_VERIFICATION_HOURS = 72

    def __init__(self, domain_validator: DomainValidator,
                 domain_repo: CustomDomainRepository,
                 ssl_provisioner: SSLProvisionerPort,
                 notification_svc: NotificationPort):
        self._validator = domain_validator
        self._repo = domain_repo
        self._ssl = ssl_provisioner
        self._notifications = notification_svc

    def run_verification_cycle(self) -> None:
        """Check all pending domains and advance their state."""
        pending_domains = self._repo.find_by_status("pending_dns_verification")

        for domain_record in pending_domains:
            if self._is_expired(domain_record):
                self._mark_expired(domain_record)
                continue

            result = self._validator.verify_domain(
                domain_record.domain,
                domain_record.dns_verification_token
            )

            if result.is_cname_valid and result.is_verification_valid:
                self._advance_to_ssl(domain_record)

    def _advance_to_ssl(self, domain_record) -> None:
        """DNS verified, provision SSL certificate."""
        domain_record.is_verified = True
        domain_record.verified_at = datetime.utcnow()
        domain_record.status = "ssl_provisioning"
        self._repo.save(domain_record)

        cert_arn = self._ssl.request_certificate(domain_record.domain)
        domain_record.ssl_certificate_arn = cert_arn
        self._repo.save(domain_record)

    def _is_expired(self, domain_record) -> bool:
        deadline = domain_record.created_at + timedelta(
            hours=self.MAX_VERIFICATION_HOURS
        )
        return datetime.utcnow() > deadline

    def _mark_expired(self, domain_record) -> None:
        domain_record.status = "verification_expired"
        self._repo.save(domain_record)
        self._notifications.send_domain_verification_expired(
            domain_record.tenant_id, domain_record.domain
        )
```

#### SSL Provisioner Port and Implementation

```python
# dom/ports/ssl_provisioner.py
from abc import ABC, abstractmethod

class SSLProvisionerPort(ABC):
    @abstractmethod
    def request_certificate(self, domain: str) -> str:
        """Request SSL certificate. Returns certificate ARN."""
        ...

    @abstractmethod
    def check_certificate_status(self, certificate_arn: str) -> str:
        """Check status: PENDING_VALIDATION, ISSUED, FAILED."""
        ...

    @abstractmethod
    def attach_to_load_balancer(self, certificate_arn: str,
                                 listener_arn: str) -> bool:
        """Attach issued certificate to ALB listener."""
        ...

# inf/ssl/acm_ssl_provisioner.py
import boto3

class ACMSSLProvisioner(SSLProvisionerPort):
    def __init__(self, region: str = "us-east-1"):
        self._acm = boto3.client("acm", region_name=region)
        self._elbv2 = boto3.client("elbv2", region_name=region)

    def request_certificate(self, domain: str) -> str:
        response = self._acm.request_certificate(
            DomainName=domain,
            ValidationMethod="DNS",
            Tags=[{"Key": "tenant-domain", "Value": domain}]
        )
        return response["CertificateArn"]

    def check_certificate_status(self, certificate_arn: str) -> str:
        response = self._acm.describe_certificate(
            CertificateArn=certificate_arn
        )
        return response["Certificate"]["Status"]

    def attach_to_load_balancer(self, certificate_arn: str,
                                 listener_arn: str) -> bool:
        self._elbv2.add_listener_certificates(
            ListenerArn=listener_arn,
            Certificates=[{"CertificateArn": certificate_arn}]
        )
        return True
```

### Criterios de Aceptacion

1. **AC-001**: PUT /api/v1/admin/tenants/:id/domain acepta un dominio custom, valida su formato (dominio DNS valido, no es *.agentsmx.com), genera un token de verificacion unico (UUID-based), y retorna instrucciones DNS con dos registros CNAME a configurar: el verification token y el domain pointing.

2. **AC-002**: El dominio custom se valida con regex para formato DNS valido, se rechaza si ya esta en uso por otro tenant (409 Conflict), se rechaza si es un subdominio de agentsmx.com (422), y se rechaza si el tenant ya tiene un dominio custom activo (debe eliminarlo primero).

3. **AC-003**: Las instrucciones DNS retornadas son claras y especificas: incluyen el tipo de registro (CNAME), el host exacto a configurar, el valor exacto, el TTL recomendado (300), y texto explicativo en espanol que el tenant puede seguir en cualquier proveedor DNS (GoDaddy, Namecheap, Cloudflare).

4. **AC-004**: El background job de verificacion DNS ejecuta cada 5 minutos, consulta todos los dominios con status "pending_dns_verification", y para cada uno verifica via dnspython que ambos registros CNAME existen y apuntan correctamente. Si ambos son validos, avanza el estado a "ssl_provisioning".

5. **AC-005**: Si la verificacion DNS no se completa en 72 horas, el dominio se marca como "verification_expired" y se notifica al tenant via email con instrucciones para reintentar. El polling se detiene para ese dominio. El tenant puede reiniciar el proceso con un nuevo PUT.

6. **AC-006**: Tras verificacion DNS exitosa, el sistema solicita automaticamente un certificado SSL via AWS ACM con ValidationMethod="DNS". El ACM certificate ARN se almacena en la tabla custom_domain_mappings. Un segundo background job verifica cada 5 minutos si el certificado fue emitido (status ISSUED).

7. **AC-007**: Cuando el certificado SSL es emitido (status ISSUED), el sistema lo adjunta automaticamente al ALB listener via add_listener_certificates (SNI). Luego actualiza custom_domain_mappings con ssl_provisioned=true y status="active". El dominio esta listo para recibir trafico HTTPS.

8. **AC-008**: GET /api/v1/admin/tenants/:id/domain retorna el estado actual del dominio con un tracker de pasos visual: (1) DNS Verification Token, (2) DNS CNAME Record, (3) SSL Certificate, (4) Load Balancer Configuration, (5) Domain Active. Cada paso tiene status (pending/in_progress/completed/failed) y timestamps.

9. **AC-009**: GET /api/v1/admin/tenants/:id/domain/verify permite al tenant triggear manualmente una verificacion DNS sin esperar al job periodico. Retorna inmediatamente el resultado de la verificacion. Tiene rate limit de 1 verificacion manual por minuto para evitar abuso.

10. **AC-010**: DELETE /api/v1/admin/tenants/:id/domain elimina el dominio custom: remueve el certificado del ALB listener, marca el domain mapping como deleted, invalida el cache de resolucion, y notifica al tenant. El tenant vuelve a ser accesible solo via subdomain.agentsmx.com.

11. **AC-011**: Errores comunes se detectan y comunican claramente: "CNAME record not found" (el tenant no agrego el registro), "CNAME points to wrong target" (apunta a otro servidor), "Domain already verified by another tenant" (conflicto), "SSL certificate failed" (problema con ACM). Cada error incluye sugerencia de resolucion.

12. **AC-012**: Los tests de integracion mockean dnspython y boto3 para simular: DNS resolucion exitosa, DNS no encontrado, DNS apuntando a target incorrecto, ACM certificate request, ACM certificate issued, ACM certificate failed, ALB listener attachment. Cobertura >= 85% en el flujo completo.

13. **AC-013**: Solo tenants con plan Pro o Enterprise pueden configurar dominios custom. Si un tenant con plan Free o Basic intenta configurar un dominio, recibe 403 con mensaje "Custom domains are available on Pro and Enterprise plans."

### Definition of Done

- [ ] Flujo completo de setup de dominio funcional (PUT -> verify -> SSL -> active)
- [ ] Background jobs de verificacion DNS y SSL implementados
- [ ] Integracion con AWS ACM y ALB via boto3
- [ ] DNS verification via dnspython funcional
- [ ] Status tracking con pasos visuales
- [ ] Error handling con mensajes claros en espanol
- [ ] Tests de integracion con mocks de AWS y DNS
- [ ] Rate limiting en verificacion manual
- [ ] Validacion de plan (solo Pro/Enterprise)
- [ ] Cobertura >= 85%
- [ ] Code review aprobado

### Notas Tecnicas

- AWS ACM DNS validation puede tardar 5-30 minutos despues de que el CNAME esta correcto
- El ALB tiene limite de 25 certificados adicionales por listener; monitorear este limite
- dnspython resuelve DNS directamente, no usa /etc/hosts; en testing usar mocks
- El background job puede correr como ECS Scheduled Task o como thread en el servicio
- Considerar usar SQS para desacoplar la verificacion: evento "domain.dns_verified" -> "provision_ssl"

### Dependencias

- Story MKT-BE-031 completada (tabla custom_domain_mappings)
- Story MKT-INF-004 completada (ALB con SNI configurado)
- AWS ACM con permisos para RequestCertificate y DescribeCertificate
- AWS ELBv2 con permisos para AddListenerCertificates
- dnspython library instalada

---

## User Story 5: [MKT-FE-030][FE-FEAT-ADM] Panel de Configuracion White Label (Super Admin)

### Descripcion

Como super administrador de AgentsMX, necesito un panel de configuracion completo para gestionar los white labels de los tenants. Este panel incluye: (1) un editor de branding con color pickers, upload de logo, selector de fonts, y preview en vivo, (2) feature toggles con checkboxes para cada modulo, (3) un wizard de configuracion de dominio con instrucciones DNS paso a paso y status tracker, (4) configuracion de plan y billing. Todo integrado en la seccion de administracion existente.

### Microservicio

- **Nombre**: Frontend Angular 18 - Admin Module
- **Puerto**: 4200 (dev)
- **Tecnologia**: Angular 18, TypeScript 5.4, Tailwind CSS v4, Standalone Components, Signals
- **Patron**: Hexagonal Architecture (Frontend) - Feature Module

### Contexto Tecnico

#### Estructura de Archivos

```
src/app/
  features/
    admin/
      tenants/
        domain/
          models/
            tenant-admin.model.ts      # Tenant admin interfaces
            branding-form.model.ts     # Branding form model
            domain-setup.model.ts      # Domain setup model
          ports/
            tenant-admin.port.ts       # Abstract class
        application/
          services/
            tenant-admin.service.ts    # Orchestration
            branding-preview.service.ts # Live preview logic
          use-cases/
            update-branding.use-case.ts
            toggle-features.use-case.ts
            setup-domain.use-case.ts
        infrastructure/
          adapters/
            tenant-admin-api.adapter.ts
        presentation/
          pages/
            tenant-list/
              tenant-list.page.ts
              tenant-list.page.html
              tenant-list.page.spec.ts
            tenant-detail/
              tenant-detail.page.ts
              tenant-detail.page.html
              tenant-detail.page.spec.ts
            tenant-branding/
              tenant-branding.page.ts
              tenant-branding.page.html
              tenant-branding.page.spec.ts
            tenant-features/
              tenant-features.page.ts
              tenant-features.page.html
              tenant-features.page.spec.ts
            tenant-domain/
              tenant-domain.page.ts
              tenant-domain.page.html
              tenant-domain.page.spec.ts
          components/
            color-picker/
              color-picker.component.ts
              color-picker.component.html
              color-picker.component.spec.ts
            logo-uploader/
              logo-uploader.component.ts
              logo-uploader.component.html
              logo-uploader.component.spec.ts
            font-selector/
              font-selector.component.ts
              font-selector.component.html
              font-selector.component.spec.ts
            branding-preview/
              branding-preview.component.ts
              branding-preview.component.html
              branding-preview.component.spec.ts
            feature-toggle/
              feature-toggle.component.ts
              feature-toggle.component.html
              feature-toggle.component.spec.ts
            domain-wizard/
              domain-wizard.component.ts
              domain-wizard.component.html
              domain-wizard.component.spec.ts
            dns-instruction/
              dns-instruction.component.ts
              dns-instruction.component.html
              dns-instruction.component.spec.ts
          routes.ts                     # Lazy-loaded routes
```

#### Color Picker Component

```typescript
// presentation/components/color-picker/color-picker.component.ts
import { Component, input, output, signal, ChangeDetectionStrategy } from '@angular/core';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-color-picker',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="flex items-center gap-3">
      <label [for]="id()" class="text-sm font-medium text-gray-700 w-40">
        {{ label() }}
      </label>
      <div class="flex items-center gap-2">
        <input
          type="color"
          [id]="id()"
          [ngModel]="color()"
          (ngModelChange)="onColorChange($event)"
          class="w-10 h-10 rounded-lg border border-gray-200 cursor-pointer" />
        <input
          type="text"
          [ngModel]="color()"
          (ngModelChange)="onColorChange($event)"
          pattern="^#[0-9A-Fa-f]{6}$"
          class="w-24 px-2 py-1 text-sm border border-gray-300 rounded-lg
                 font-mono uppercase" />
        <div
          class="w-10 h-10 rounded-lg border border-gray-200"
          [style.background-color]="color()">
        </div>
      </div>
    </div>
  `,
})
export class ColorPickerComponent {
  readonly label = input.required<string>();
  readonly id = input.required<string>();
  readonly color = input.required<string>();
  readonly colorChange = output<string>();

  onColorChange(value: string): void {
    if (/^#[0-9A-Fa-f]{6}$/.test(value)) {
      this.colorChange.emit(value);
    }
  }
}
```

#### Branding Preview Component

```typescript
// presentation/components/branding-preview/branding-preview.component.ts
@Component({
  selector: 'app-branding-preview',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="border border-gray-200 rounded-xl overflow-hidden shadow-lg">
      <div class="text-xs font-medium text-gray-500 bg-gray-50 px-4 py-2
                  border-b flex items-center gap-2">
        <span class="w-3 h-3 rounded-full bg-red-400"></span>
        <span class="w-3 h-3 rounded-full bg-yellow-400"></span>
        <span class="w-3 h-3 rounded-full bg-green-400"></span>
        <span class="ml-2">{{ previewUrl() }}</span>
      </div>
      <div class="bg-white" [style]="previewStyles()">
        <!-- Preview Header -->
        <div class="px-4 py-3 border-b flex items-center justify-between"
             [style.border-color]="branding().primary_color + '20'">
          @if (branding().logo_url) {
            <img [src]="branding().logo_url" class="h-8" alt="Preview logo" />
          } @else {
            <div class="h-8 w-24 rounded"
                 [style.background-color]="branding().primary_color">
            </div>
          }
          <div class="flex gap-3">
            <span class="text-sm" [style.color]="branding().text_color">Catalogo</span>
            <span class="text-sm" [style.color]="branding().primary_color">Financiamiento</span>
          </div>
          <button class="px-3 py-1 text-white text-sm"
                  [style.background-color]="branding().primary_color"
                  [style.border-radius]="branding().border_radius">
            Iniciar Sesion
          </button>
        </div>
        <!-- Preview Content -->
        <div class="p-4 grid grid-cols-3 gap-3">
          @for (i of [1,2,3]; track i) {
            <div class="border rounded-lg p-3"
                 [style.border-radius]="branding().border_radius"
                 [style.border-color]="branding().primary_color + '30'">
              <div class="h-16 bg-gray-100 rounded mb-2"
                   [style.border-radius]="branding().border_radius">
              </div>
              <div class="h-3 w-3/4 rounded"
                   [style.background-color]="branding().text_color + '30'">
              </div>
              <div class="h-3 w-1/2 rounded mt-1"
                   [style.background-color]="branding().accent_color + '50'">
              </div>
            </div>
          }
        </div>
      </div>
    </div>
  `,
})
export class BrandingPreviewComponent {
  readonly branding = input.required<BrandingConfig>();
  readonly tenantSlug = input<string>('preview');

  readonly previewUrl = computed(() =>
    `https://${this.tenantSlug()}.agentsmx.com`
  );

  readonly previewStyles = computed(() => {
    const b = this.branding();
    return `
      --color-primary: ${b.primary_color};
      --font-family-body: ${b.font_family}, sans-serif;
      --font-family-heading: ${b.heading_font_family}, sans-serif;
      font-family: ${b.font_family}, sans-serif;
      background-color: ${b.background_color};
      color: ${b.text_color};
    `;
  });
}
```

#### Feature Toggle Component

```typescript
// presentation/components/feature-toggle/feature-toggle.component.ts
@Component({
  selector: 'app-feature-toggle',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="flex items-center justify-between py-3 px-4 rounded-lg
                hover:bg-gray-50 transition-colors">
      <div class="flex-1">
        <div class="flex items-center gap-2">
          <span class="text-sm font-medium text-gray-900">{{ label() }}</span>
          @if (isPremium()) {
            <span class="px-2 py-0.5 text-xs font-medium rounded-full
                         bg-amber-100 text-amber-800">
              PRO
            </span>
          }
        </div>
        <p class="text-xs text-gray-500 mt-0.5">{{ description() }}</p>
      </div>
      <label class="relative inline-flex items-center cursor-pointer">
        <input type="checkbox"
               [ngModel]="enabled()"
               (ngModelChange)="onToggle($event)"
               [disabled]="isLocked()"
               class="sr-only peer" />
        <div class="w-11 h-6 bg-gray-200 rounded-full peer
                    peer-checked:bg-primary peer-focus:ring-2 peer-focus:ring-primary/20
                    after:content-[''] after:absolute after:top-[2px] after:left-[2px]
                    after:bg-white after:rounded-full after:h-5 after:w-5
                    after:transition-all peer-checked:after:translate-x-full
                    peer-disabled:opacity-50 peer-disabled:cursor-not-allowed">
        </div>
      </label>
    </div>
  `,
})
export class FeatureToggleComponent {
  readonly label = input.required<string>();
  readonly description = input<string>('');
  readonly enabled = input.required<boolean>();
  readonly isPremium = input<boolean>(false);
  readonly isLocked = input<boolean>(false);
  readonly enabledChange = output<boolean>();

  onToggle(value: boolean): void {
    this.enabledChange.emit(value);
  }
}
```

#### Domain Wizard Component

```typescript
// presentation/components/domain-wizard/domain-wizard.component.ts
@Component({
  selector: 'app-domain-wizard',
  standalone: true,
  imports: [FormsModule, DnsInstructionComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './domain-wizard.component.html',
})
export class DomainWizardComponent {
  readonly tenantId = input.required<string>();
  readonly currentDomain = input<DomainSetupStatus | null>(null);

  private readonly tenantAdmin = inject(TenantAdminService);

  readonly domainInput = signal('');
  readonly isSubmitting = signal(false);
  readonly error = signal<string | null>(null);

  readonly currentStep = computed(() => {
    const domain = this.currentDomain();
    if (!domain) return 0;
    if (domain.status === 'pending_dns_verification') return 1;
    if (domain.status === 'ssl_provisioning') return 3;
    if (domain.status === 'active') return 5;
    return 0;
  });

  readonly steps = [
    { name: 'Ingresar Dominio', icon: 'globe' },
    { name: 'Verificacion DNS', icon: 'dns' },
    { name: 'Registro CNAME', icon: 'link' },
    { name: 'Certificado SSL', icon: 'lock' },
    { name: 'Configuracion ALB', icon: 'server' },
    { name: 'Dominio Activo', icon: 'check-circle' },
  ];

  async submitDomain(): Promise<void> {
    this.isSubmitting.set(true);
    this.error.set(null);
    try {
      await this.tenantAdmin.setupCustomDomain(
        this.tenantId(), this.domainInput()
      );
    } catch (err: unknown) {
      this.error.set(
        err instanceof Error ? err.message : 'Error configurando dominio'
      );
    } finally {
      this.isSubmitting.set(false);
    }
  }

  async verifyDomain(): Promise<void> {
    await this.tenantAdmin.verifyDomain(this.tenantId());
  }

  async removeDomain(): Promise<void> {
    if (confirm('Estas seguro de eliminar el dominio custom?')) {
      await this.tenantAdmin.removeDomain(this.tenantId());
    }
  }
}
```

### Criterios de Aceptacion

1. **AC-001**: La pagina Tenant List muestra todos los tenants en una tabla con columnas: nombre, slug, plan, status (badge coloreado), vehiculos (usado/limite), dominio, fecha de creacion. Soporta busqueda por nombre, filtrado por status y plan, paginacion de 20 items, y ordenamiento por columna.

2. **AC-002**: La pagina Tenant Detail muestra tabs: Info General, Branding, Features, Dominio, Billing, Metricas. Cada tab carga su contenido via lazy component. La info general muestra KPIs principales: vehiculos activos, usuarios, transacciones del mes, revenue del mes.

3. **AC-003**: El editor de Branding incluye: (a) color pickers para primary, secondary, accent, background, text (6 colores), (b) upload de logo con preview (arrastrar o click, formatos SVG/PNG/JPEG, max 2MB), (c) upload de favicon (32x32), (d) selector de font-family (dropdown con preview de cada font), (e) selector de header_style y footer_style (radio buttons con previews).

4. **AC-004**: El componente BrandingPreview muestra un mini-preview del white label en tiempo real que se actualiza instantaneamente conforme el admin cambia colores, logo, o fonts. El preview simula un header con logo y nav, y un grid de 3 cards de vehiculos con los colores del tema.

5. **AC-005**: El boton "Guardar Branding" envia SOLO los campos modificados (patch) a PUT /admin/tenants/:id/branding. Muestra un spinner durante el guardado, toast de exito "Branding actualizado correctamente", y toast de error si falla. El cache del tenant se invalida automaticamente.

6. **AC-006**: El panel de Features muestra cada feature como un toggle switch con: nombre, descripcion corta, badge "PRO" si es premium, y estado enabled/disabled. Features premium (analytics, reports, seo_tools, notifications_sms) muestran el toggle deshabilitado (grayed out) si el plan del tenant no los incluye.

7. **AC-007**: El Domain Wizard muestra un flujo de 5 pasos con stepper visual: (1) Ingresar dominio, (2) Verificacion DNS, (3) Registro CNAME, (4) Certificado SSL, (5) Dominio Activo. Cada paso muestra su status (pending/in_progress/completed) con iconos y timestamps.

8. **AC-008**: En el paso "Verificacion DNS", se muestran instrucciones claras con los registros DNS a configurar en formato copiable (click to copy): tipo CNAME, host, value, TTL. Incluye screenshots/instrucciones para los 3 proveedores DNS mas comunes (GoDaddy, Namecheap, Cloudflare).

9. **AC-009**: El boton "Verificar DNS" permite al admin triggear una verificacion manual. Muestra un spinner durante la verificacion y el resultado: "DNS verificado correctamente" (verde) o "DNS no encontrado - asegurate de haber configurado los registros" (rojo con instrucciones).

10. **AC-010**: Toda la seccion de tenants es accesible solo para usuarios con rol super_admin. Si un usuario sin este rol intenta navegar a /admin/tenants, se redirige a /admin/dashboard con mensaje de permisos insuficientes. Las rutas tienen guard canActivate que verifica el rol.

11. **AC-011**: Todos los componentes del panel usan standalone components con OnPush change detection y signals. No hay subscripciones manuales a observables. Los formularios usan reactive forms o ngModel segun complejidad. La paginacion y filtrado son reactivos (debounce de 300ms en busqueda).

12. **AC-012**: Los tests unitarios verifican: (a) color picker emite colores hex validos, (b) logo uploader valida formato y tamano, (c) feature toggles respetan restricciones de plan, (d) domain wizard navega entre pasos correctamente, (e) branding preview refleja cambios en tiempo real.

13. **AC-013**: El panel tiene validaciones en el frontend: colores deben ser hex valido (#XXXXXX), logo max 2MB, favicon max 500KB, dominio formato valido, subdomain no reservado. Errores de validacion se muestran inline debajo de cada campo con texto rojo.

14. **AC-014**: Existe un boton "Vista Previa Completa" que abre una nueva ventana/tab con la URL del white label del tenant incluyendo un query param ?preview=true que carga el branding pendiente de guardar (no el activo). Esto permite al admin ver como se vera antes de publicar.

### Definition of Done

- [ ] Pagina Tenant List con busqueda, filtrado, paginacion
- [ ] Pagina Tenant Detail con tabs
- [ ] Editor de branding con color pickers, logo upload, font selector
- [ ] Live preview funcional y reactivo
- [ ] Feature toggles con restricciones de plan
- [ ] Domain wizard con 5 pasos y DNS verification
- [ ] Guards de acceso para super_admin
- [ ] Validaciones de frontend completas
- [ ] Tests unitarios con cobertura >= 85%
- [ ] Responsive design verificado
- [ ] Code review aprobado

### Notas Tecnicas

- Usar Angular CDK Drag&Drop si se requiere reordenar elementos en el futuro
- Los color pickers nativos de HTML5 (<input type="color">) varian por browser; considerar libreria (ngx-color) para consistencia
- Logo upload usa FileReader API para preview local antes de subir a S3
- El preview en vivo usa CSS variables aplicadas a un contenedor scoped, no al :root global (para no afectar el admin)
- Debounce en busqueda y color changes para evitar muchas API calls

### Dependencias

- Stories MKT-BE-036 y MKT-BE-037 completadas (API de white label y domain setup)
- EP-009 completado (panel de administracion base)
- Angular 18 con standalone components y signals
- AWS S3 para upload de logos (presigned URLs)
