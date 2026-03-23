#!/usr/bin/env bash
set -e

REPO="multiagents-fer/multiagents-projects"

echo "=============================================="
echo " MKT Marketplace - Part 2: Epics 6-10"
echo " Creating issues in $REPO"
echo "=============================================="

###############################################################################
# EPIC 6: [MKT-EP-006] Verificacion de Identidad (KYC)
###############################################################################

echo ""
echo ">>> Creating EPIC 6: Verificacion de Identidad (KYC)"
gh issue create --repo "$REPO" \
  --title "[MKT-EP-006] Verificacion de Identidad (KYC)" \
  --label "epic,kyc,security" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Sistema de verificacion de identidad (KYC - Know Your Customer) que se activa UNICAMENTE al momento de querer comprar un vehiculo. Incluye upload seguro de documentos oficiales, verificacion facial con liveness detection, validacion de datos contra fuentes oficiales (RENAPO, listas negras PLD/FT), y gestion completa del ciclo de vida KYC.

## Contexto Tecnico
- **Backend**: Flask 3.0 + SQLAlchemy 2.0 con servicio KYC dedicado
- **Storage**: AWS S3 con server-side encryption (SSE-S3 o SSE-KMS) para documentos sensibles
- **Queue**: SQS para procesamiento asincrono de verificaciones
- **Proveedores**: Adapter pattern para multiples proveedores de verificacion (Mati/Metamap, Jumio, Onfido)
- **OCR**: Extraccion de datos de INE/IFE, pasaporte mexicano
- **Face matching**: Comparacion biometrica selfie vs foto de documento oficial
- **Compliance**: Ley Federal para la Prevencion e Identificacion de Operaciones con Recursos de Procedencia Ilicita (LFPIORPI)

## Modelo de Datos
```python
class KYCVerification(Base):
    __tablename__ = 'kyc_verifications'
    id = Column(UUID, primary_key=True, default=uuid4)
    user_id = Column(UUID, ForeignKey('users.id'), nullable=False)
    status = Column(Enum('not_started','documents_pending','in_review','approved','rejected','expired'), default='not_started')
    risk_score = Column(Float, nullable=True)
    provider = Column(String(50))
    provider_reference_id = Column(String(255))
    rejection_reasons = Column(JSONB, nullable=True)
    approved_at = Column(DateTime, nullable=True)
    expires_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, onupdate=func.now())

class KYCDocument(Base):
    __tablename__ = 'kyc_documents'
    id = Column(UUID, primary_key=True, default=uuid4)
    verification_id = Column(UUID, ForeignKey('kyc_verifications.id'))
    document_type = Column(Enum('ine_front','ine_back','passport','selfie','proof_of_address'))
    s3_key = Column(String(500), nullable=False)
    s3_bucket = Column(String(255), nullable=False)
    file_hash = Column(String(128))
    mime_type = Column(String(50))
    file_size = Column(Integer)
    quality_score = Column(Float, nullable=True)
    ocr_data = Column(JSONB, nullable=True)
    status = Column(Enum('uploaded','processing','accepted','rejected'))
    rejection_reason = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=func.now())
```

## Stories de este Epic
- [MKT-BE-014] API de Upload de Documentos KYC
- [MKT-BE-015] Servicio de Verificacion de Identidad
- [MKT-BE-016] API de Estado y Gestion KYC
- [MKT-FE-014] Flujo de Upload de Documentos KYC
- [MKT-FE-015] Panel de Estado KYC
- [MKT-INT-003] Integracion con Proveedor de Verificacion de Identidad

## Dependencias
- [MKT-EP-001] Autenticacion (usuario logueado)
- [MKT-EP-003] Busqueda y Detalle (vehiculo seleccionado para compra)
- AWS S3 bucket configurado con encryption
- Proveedor de verificacion contratado

## Notas Tecnicas
- Los documentos NUNCA se almacenan en disco local, siempre directo a S3 con encryption
- Las URLs de documentos son presigned URLs con TTL de 15 minutos
- El KYC expira a los 6 meses y requiere re-verificacion
- Cumplimiento con LFPIORPI para PLD/FT
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-014
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-014] API de Upload de Documentos KYC"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-014] API de Upload de Documentos KYC" \
  --label "backend,kyc,api,security" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoints REST para upload seguro de documentos de verificacion de identidad. Soporta INE/IFE (frente y vuelta), pasaporte, selfie para face matching, y comprobante de domicilio. Los archivos se almacenan encriptados en S3 con validacion estricta de formato, tamano y calidad.

## Contexto Tecnico
- **Framework**: Flask 3.0 con blueprints dedicados para KYC
- **Storage**: AWS S3 con SSE-KMS encryption, presigned URLs para acceso temporal
- **Validacion**: Pillow/OpenCV para calidad de imagen, python-magic para MIME type real
- **Upload**: Multipart form-data, max 10MB por archivo
- **Ruta base**: `/api/v1/kyc/`

## Endpoints

### POST /api/v1/kyc/documents
Upload de documento oficial (INE frente/vuelta, pasaporte).
```json
// Request: multipart/form-data
{
  "document_type": "ine_front | ine_back | passport",
  "file": "<binary>"
}

// Response 201:
{
  "id": "uuid",
  "document_type": "ine_front",
  "status": "uploaded",
  "quality_score": 0.92,
  "file_size": 1245000,
  "mime_type": "image/jpeg",
  "created_at": "2026-03-23T10:00:00Z"
}
```

### POST /api/v1/kyc/selfie
Upload de selfie para face matching.
```json
// Request: multipart/form-data
{
  "file": "<binary>",
  "liveness_token": "token-from-frontend-liveness-check"
}

// Response 201:
{
  "id": "uuid",
  "document_type": "selfie",
  "status": "uploaded",
  "quality_score": 0.88,
  "face_detected": true,
  "created_at": "2026-03-23T10:00:00Z"
}
```

### POST /api/v1/kyc/proof-of-address
Upload de comprobante de domicilio.
```json
// Request: multipart/form-data
{
  "file": "<binary>",
  "document_subtype": "cfe | agua | telmex | bank_statement | predial"
}

// Response 201:
{
  "id": "uuid",
  "document_type": "proof_of_address",
  "document_subtype": "cfe",
  "status": "uploaded",
  "created_at": "2026-03-23T10:00:00Z"
}
```

### DELETE /api/v1/kyc/documents/{document_id}
Eliminar documento (solo si status != 'accepted').

## Criterios de Aceptacion
- [ ] CA-01: El endpoint POST /kyc/documents acepta multipart/form-data con campos document_type y file, retorna 201 con metadata del documento
- [ ] CA-02: Validacion de MIME type real (no solo extension) usando python-magic; solo acepta image/jpeg, image/png, application/pdf; retorna 415 para tipos no soportados
- [ ] CA-03: Validacion de tamano maximo 10MB por archivo; retorna 413 si excede el limite con mensaje "El archivo excede el tamano maximo de 10MB"
- [ ] CA-04: Validacion de calidad de imagen: resolucion minima 640x480, blur detection (Laplacian variance > 100), brightness check; retorna 422 con quality_issues array si falla
- [ ] CA-05: Los archivos se almacenan en S3 con SSE-KMS encryption, key path: `kyc/{user_id}/{verification_id}/{document_type}_{timestamp}.{ext}`, nunca en disco local
- [ ] CA-06: Se genera hash SHA-256 del archivo y se almacena en BD para deteccion de duplicados y verificacion de integridad
- [ ] CA-07: El endpoint POST /kyc/selfie valida que se detecta exactamente 1 rostro en la imagen usando face detection; retorna 422 si no detecta rostro o detecta multiples
- [ ] CA-08: El endpoint POST /kyc/selfie valida el liveness_token del frontend para prevenir fotos de fotos; retorna 401 si token invalido
- [ ] CA-09: Solo usuarios autenticados pueden subir documentos (JWT required); un usuario solo puede subir documentos para su propia verificacion KYC
- [ ] CA-10: Si ya existe un documento del mismo tipo con status 'uploaded' o 'processing', el nuevo upload reemplaza al anterior (soft delete del previo)
- [ ] CA-11: Rate limiting: maximo 10 uploads por hora por usuario para prevenir abuso; retorna 429 si se excede
- [ ] CA-12: Audit log: cada upload registra user_id, document_type, ip_address, user_agent, timestamp en tabla kyc_audit_log
- [ ] CA-13: El endpoint DELETE solo permite eliminar documentos con status 'uploaded' o 'rejected'; retorna 409 si el documento esta en 'processing' o 'accepted'

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada (OpenAPI/Swagger)
- [ ] Sin vulnerabilidades de seguridad (file upload injection, path traversal)
- [ ] Performance benchmarks cumplidos (upload < 3s para 5MB)

## Notas Tecnicas
- Usar boto3 con transfer config para multipart upload a S3 en archivos > 5MB
- Presigned URLs con TTL 15 min para lectura posterior
- Considerar thumbnail generation async via SQS para preview rapido
- El bucket S3 debe tener lifecycle policy para eliminar documentos de verificaciones expiradas

## Dependencias
- [MKT-EP-001] Autenticacion - JWT token del usuario
- AWS S3 bucket con KMS key configurado
- [MKT-EP-006] Epic padre

## Epica Padre
[MKT-EP-006] Verificacion de Identidad (KYC)
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-015
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-015] Servicio de Verificacion de Identidad"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-015] Servicio de Verificacion de Identidad" \
  --label "backend,kyc,security,ai" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar el servicio core de verificacion de identidad que procesa los documentos subidos, ejecuta OCR sobre INE/pasaporte, realiza face matching entre selfie y foto del documento, valida CURP contra RENAPO, checa listas negras PLD/FT, y genera un score de riesgo consolidado.

## Contexto Tecnico
- **Servicio**: `KYCVerificationService` en domain layer (hexagonal architecture)
- **OCR**: Adapter para proveedor (Metamap, AWS Textract como fallback)
- **Face matching**: Adapter para comparacion biometrica (confidence threshold configurable)
- **Validacion CURP**: API RENAPO via adapter
- **PLD/FT**: Validacion contra listas negras (OFAC, UIF, listas locales)
- **Queue**: SQS para procesamiento asincrono; el upload trigger SQS message

## Flujo de Verificacion
```
1. Upload completo → SQS message
2. Worker consume mensaje
3. OCR de INE/pasaporte → extrae datos
4. Face matching selfie vs foto documento
5. Validacion CURP contra RENAPO
6. Validacion listas negras PLD/FT
7. Calculo de risk score
8. Actualizacion de status → approved/rejected
9. Notificacion al usuario
```

## Modelo de Risk Score
```python
class RiskScoreCalculator:
    def calculate(self, verification: KYCVerification) -> float:
        """
        Score 0.0 (alto riesgo) a 1.0 (bajo riesgo)
        Factores:
        - ocr_confidence: peso 0.25
        - face_match_confidence: peso 0.30
        - curp_valid: peso 0.20
        - pld_clean: peso 0.25
        Threshold: >= 0.70 → approved, < 0.70 → manual_review, < 0.40 → rejected
        """
```

## Criterios de Aceptacion
- [ ] CA-01: El servicio consume mensajes SQS de documentos completados y ejecuta el pipeline de verificacion completo en orden: OCR, face match, CURP, PLD, risk score
- [ ] CA-02: OCR de INE extrae correctamente: nombre completo, CURP, clave de elector, fecha de nacimiento, direccion, vigencia; con confidence score por campo > 0.85
- [ ] CA-03: OCR de pasaporte extrae: nombre, nacionalidad, fecha nacimiento, numero de pasaporte, fecha expiracion via MRZ (Machine Readable Zone)
- [ ] CA-04: Face matching compara selfie contra foto del documento con threshold configurable (default 0.80); almacena confidence score y decision (match/no_match)
- [ ] CA-05: Validacion CURP contra RENAPO confirma que el CURP existe, los datos coinciden con el nombre del documento, y el CURP esta activo; timeout 10s con retry
- [ ] CA-06: Validacion PLD/FT checa nombre completo contra listas OFAC (SDN), UIF Mexico, y listas internas; registra resultado positivo/negativo con detalle del match
- [ ] CA-07: El risk score se calcula con los pesos definidos (OCR 0.25, face 0.30, CURP 0.20, PLD 0.25); score >= 0.70 auto-approve, < 0.40 auto-reject, entre 0.40-0.70 manual review
- [ ] CA-08: Si algun paso del pipeline falla (timeout, error de proveedor), el servicio marca el paso como 'error' y continua con los demas; el status final refleja los pasos completados
- [ ] CA-09: Los resultados de cada paso se almacenan en kyc_verification_steps con: step_name, status, result_data (JSONB), confidence_score, provider, duration_ms, created_at
- [ ] CA-10: Si el proveedor primario falla, el servicio usa el proveedor fallback automaticamente (e.g., Metamap falla → AWS Textract para OCR); registra cual proveedor se uso
- [ ] CA-11: El procesamiento completo no excede 120 segundos; si se excede, marca como timeout y envia a cola de revision manual
- [ ] CA-12: Al completar la verificacion (approved/rejected), envia notificacion al usuario via el servicio de notificaciones con el resultado y proximos pasos
- [ ] CA-13: Audit trail completo: cada paso del pipeline registra inicio, fin, resultado, proveedor usado, datos de entrada/salida (datos sensibles redactados en logs)

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) con mocks de proveedores externos
- [ ] Tests de integracion con proveedores en sandbox
- [ ] Documentacion de arquitectura del pipeline
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: pipeline completo < 120s

## Notas Tecnicas
- Cada adapter de proveedor debe implementar circuit breaker pattern (pybreaker)
- Datos de PII solo en logs nivel DEBUG, nunca en INFO/WARNING/ERROR
- El CURP tiene formato validable por regex antes de llamar a RENAPO
- Considerar cache de validaciones CURP (TTL 30 dias)

## Dependencias
- [MKT-BE-014] API de Upload de Documentos KYC
- [MKT-INT-003] Integracion con Proveedor de Verificacion
- Acceso a API RENAPO
- Listas negras PLD/FT actualizadas

## Epica Padre
[MKT-EP-006] Verificacion de Identidad (KYC)
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-016
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-016] API de Estado y Gestion KYC"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-016] API de Estado y Gestion KYC" \
  --label "backend,kyc,api" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoints para consultar el estado actual de la verificacion KYC del usuario, manejar el ciclo de vida completo (re-submission, expiracion, admin override), y proveer informacion detallada sobre razones de rechazo y pasos pendientes.

## Contexto Tecnico
- **Framework**: Flask 3.0 blueprint kyc
- **Ruta base**: `/api/v1/kyc/`
- **Admin routes**: `/api/v1/admin/kyc/`
- **Cache**: Redis para status frecuentemente consultado (TTL 60s)
- **Estados**: not_started → documents_pending → in_review → approved/rejected → expired

## Endpoints

### GET /api/v1/kyc/status
Estado actual del KYC del usuario autenticado.
```json
// Response 200:
{
  "verification_id": "uuid",
  "status": "in_review",
  "documents": [
    {"type": "ine_front", "status": "accepted", "uploaded_at": "..."},
    {"type": "ine_back", "status": "accepted", "uploaded_at": "..."},
    {"type": "selfie", "status": "processing", "uploaded_at": "..."},
    {"type": "proof_of_address", "status": "uploaded", "uploaded_at": "..."}
  ],
  "required_documents": ["ine_front", "ine_back", "selfie", "proof_of_address"],
  "completion_percentage": 75,
  "estimated_review_time_minutes": 15,
  "expires_at": "2026-09-23T10:00:00Z",
  "rejection_reasons": null,
  "created_at": "2026-03-23T10:00:00Z",
  "updated_at": "2026-03-23T10:15:00Z"
}
```

### POST /api/v1/kyc/resubmit
Re-envio de verificacion tras rechazo.
```json
// Request:
{ "documents_to_resubmit": ["ine_front", "selfie"] }
// Response 200:
{ "verification_id": "uuid-new", "status": "documents_pending", "resubmission_count": 2 }
```

### GET /api/v1/admin/kyc/verifications
Lista de verificaciones para admin (paginada, filtrable).

### PUT /api/v1/admin/kyc/verifications/{id}/override
Admin override de resultado.
```json
// Request:
{ "action": "approve | reject", "reason": "Manual verification completed", "admin_notes": "..." }
```

## Criterios de Aceptacion
- [ ] CA-01: GET /kyc/status retorna el estado completo de la verificacion del usuario autenticado, incluyendo status de cada documento individual y porcentaje de completitud
- [ ] CA-02: Si el usuario no tiene verificacion iniciada, GET /kyc/status retorna status "not_started" con lista de documentos requeridos y sus tipos
- [ ] CA-03: El campo rejection_reasons es un array de objetos {document_type, reason_code, reason_detail, suggestion} cuando status es "rejected"
- [ ] CA-04: POST /kyc/resubmit crea una nueva verificacion vinculada a la anterior, solo permite re-enviar documentos que fueron rechazados; maximo 3 re-submissions
- [ ] CA-05: La verificacion KYC expira automaticamente a los 6 meses (configurable); un job cron marca como 'expired' las verificaciones vencidas diariamente
- [ ] CA-06: GET /admin/kyc/verifications soporta filtros por status, fecha, risk_score range, nombre de usuario; paginacion limit/offset; solo accesible con rol admin
- [ ] CA-07: PUT /admin/kyc/verifications/{id}/override permite a admin aprobar o rechazar manualmente; requiere reason obligatorio; registra admin_id en audit log
- [ ] CA-08: El status se cachea en Redis con TTL 60s; el cache se invalida al cambiar el status de la verificacion o de cualquier documento
- [ ] CA-09: El endpoint retorna estimated_review_time_minutes calculado como promedio movil de las ultimas 100 verificaciones completadas del mismo tipo
- [ ] CA-10: Al consultar status, si la verificacion esta aprobada y proxima a expirar (< 30 dias), incluye campo warning: "kyc_expiring_soon" con fecha exacta
- [ ] CA-11: El historial de cambios de estado se mantiene en kyc_status_history con: old_status, new_status, changed_by (user/system/admin), reason, timestamp
- [ ] CA-12: Rate limiting en GET /kyc/status: maximo 60 requests por minuto por usuario; admin endpoints: 120 requests por minuto

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada (OpenAPI/Swagger)
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: GET /kyc/status < 100ms con cache hit

## Notas Tecnicas
- Usar Marshmallow schemas: KYCStatusSchema, KYCDocumentStatusSchema, KYCResubmitSchema
- El cron de expiracion debe correr como ECS Scheduled Task (no crontab)
- Admin override requiere 2FA adicional (verificacion por email al admin)

## Dependencias
- [MKT-BE-014] API de Upload de Documentos KYC
- [MKT-BE-015] Servicio de Verificacion de Identidad
- [MKT-EP-001] Autenticacion (roles admin)
- Redis configurado

## Epica Padre
[MKT-EP-006] Verificacion de Identidad (KYC)
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-014
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-014] Flujo de Upload de Documentos KYC"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-014] Flujo de Upload de Documentos KYC" \
  --label "frontend,kyc,angular,ux" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar el flujo completo de upload de documentos KYC en Angular 18 con captura de camara nativa, guias visuales overlay para fotografiar INE/pasaporte, preview de documentos antes de enviar, selfie con liveness detection, y progress tracking paso a paso.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Camera**: MediaDevices API (getUserMedia) para captura nativa
- **Liveness**: Web-based liveness detection (parpadeo, movimiento de cabeza)
- **Upload**: HttpClient con progress events para progress bar
- **Ruta**: `/kyc/upload` (lazy loaded module)

## Componentes
```
src/app/features/kyc/
  kyc-upload-flow/
    kyc-upload-flow.component.ts        # Stepper principal
  document-capture/
    document-capture.component.ts        # Camara + overlay guide
  selfie-capture/
    selfie-capture.component.ts          # Selfie con liveness
  document-preview/
    document-preview.component.ts        # Preview antes de enviar
  upload-progress/
    upload-progress.component.ts         # Progress bar + status
  services/
    kyc-upload.service.ts                # HTTP calls
    camera.service.ts                    # Camera API wrapper
    liveness.service.ts                  # Liveness detection logic
```

## Criterios de Aceptacion
- [ ] CA-01: El flujo de upload se presenta como stepper de 4 pasos: 1) INE Frente, 2) INE Vuelta, 3) Selfie, 4) Comprobante de domicilio; cada paso muestra icono, titulo y estado (pendiente/completo/error)
- [ ] CA-02: El componente document-capture abre la camara del dispositivo con overlay SVG guia mostrando el marco exacto donde posicionar la INE/pasaporte; incluye indicadores de alineacion
- [ ] CA-03: El usuario puede elegir entre capturar con camara o subir archivo existente (input type=file accept="image/jpeg,image/png,application/pdf"); ambos flujos convergen en preview
- [ ] CA-04: El componente document-preview muestra la imagen capturada/seleccionada en alta resolucion con opciones: "Usar esta foto" (confirmar) o "Tomar otra" (regresar a captura)
- [ ] CA-05: El componente selfie-capture implementa liveness detection basica: solicita al usuario parpadear 2 veces y girar la cabeza levemente; muestra instrucciones animadas paso a paso
- [ ] CA-06: Durante el upload, se muestra progress bar con porcentaje real (HttpClient reportProgress), tamano del archivo, y velocidad estimada de subida
- [ ] CA-07: Si la API retorna error de calidad de imagen (422), se muestra mensaje especifico con sugerencias: "La imagen esta borrosa, intente con mejor iluminacion" o "No se detecto un rostro, centre su cara en el marco"
- [ ] CA-08: El flujo es responsive: en mobile usa camara trasera para documentos y frontal para selfie; en desktop permite upload de archivo y webcam
- [ ] CA-09: Al completar los 4 pasos, se muestra pantalla de confirmacion con thumbnails de todos los documentos subidos y boton "Enviar a verificacion" que triggerea el proceso
- [ ] CA-10: Si el usuario sale del flujo y regresa, se restaura el progreso: los documentos ya subidos aparecen como completados y no se piden de nuevo
- [ ] CA-11: Los archivos se validan en frontend antes de enviar: tamano max 10MB, tipo MIME correcto, dimensiones minimas 640x480; errores se muestran inline
- [ ] CA-12: Accesibilidad WCAG 2.1 AA: todos los pasos son navegables por teclado, instrucciones tienen alt text, estados se comunican via aria-live regions

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) con Jasmine/Karma
- [ ] Tests e2e del flujo completo con Cypress/Playwright
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: captura de camara < 2s init, upload feedback inmediato

## Notas Tecnicas
- Usar signal() para estado del stepper y documentos subidos
- Camera permission handling: mostrar instrucciones si el usuario deniega acceso
- Considerar compresion de imagen en frontend (canvas resize) si > 5MB
- El liveness token se genera localmente y se valida en backend

## Dependencias
- [MKT-BE-014] API de Upload de Documentos KYC
- Angular 18 con standalone components
- Tailwind CSS v4

## Epica Padre
[MKT-EP-006] Verificacion de Identidad (KYC)
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-015
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-015] Panel de Estado KYC"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-015] Panel de Estado KYC" \
  --label "frontend,kyc,angular,ux" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar panel visual que muestra el estado completo de la verificacion KYC del usuario: checklist de documentos, estado de verificacion con semaforo visual, motivos de rechazo con instrucciones para corregir, tiempo estimado de revision, y opciones de re-envio.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Polling**: Polling cada 30s o WebSocket para status updates en tiempo real
- **Ruta**: `/kyc/status` (lazy loaded)

## Componentes
```
src/app/features/kyc/
  kyc-status-panel/
    kyc-status-panel.component.ts       # Panel principal
  document-checklist/
    document-checklist.component.ts      # Lista de documentos con status
  verification-status/
    verification-status.component.ts     # Semaforo de verificacion
  rejection-details/
    rejection-details.component.ts       # Detalles de rechazo
```

## Criterios de Aceptacion
- [ ] CA-01: El panel muestra checklist visual de 4 documentos requeridos (INE frente, INE vuelta, selfie, comprobante domicilio) con iconos de estado: check verde (aceptado), reloj amarillo (en revision), X rojo (rechazado), circulo gris (pendiente)
- [ ] CA-02: El estado general de verificacion se muestra como semaforo prominente: verde "Verificado", amarillo "En revision", rojo "Rechazado", gris "No iniciado"; con fecha y hora de ultimo cambio
- [ ] CA-03: Cuando status es "rejected", se muestran los motivos de rechazo por documento en cards expandibles con: motivo especifico, sugerencia de correccion, y boton "Re-enviar este documento"
- [ ] CA-04: Se muestra barra de progreso con porcentaje de completitud (0-100%) calculado: 25% por cada documento subido y aceptado
- [ ] CA-05: Tiempo estimado de verificacion se muestra como badge: "Tiempo estimado: ~15 minutos" basado en el campo estimated_review_time_minutes de la API
- [ ] CA-06: El boton "Re-enviar documento" por cada documento rechazado navega al componente de captura especifico para ese documento, pre-seleccionando el paso correcto del stepper
- [ ] CA-07: El panel hace polling cada 30 segundos al endpoint GET /kyc/status y actualiza la UI sin reload; usa signal() para reactividad; muestra indicador "Actualizando..." durante el fetch
- [ ] CA-08: Si la verificacion esta aprobada y proxima a expirar (< 30 dias), muestra banner warning amarillo: "Tu verificacion vence el {fecha}. Renueva para poder seguir comprando."
- [ ] CA-09: El panel es completamente responsive: en mobile muestra checklist vertical con cards colapsables; en desktop muestra layout de 2 columnas (checklist izq, status/detalle der)
- [ ] CA-10: Si el usuario no ha iniciado KYC y llega al panel, muestra CTA prominente: "Verifica tu identidad para poder comprar" con boton que navega al flujo de upload
- [ ] CA-11: Las transiciones entre estados se animan suavemente (Angular animations): iconos cambian con fade, barras de progreso se llenan con ease-in-out, cards de rechazo aparecen con slide-down
- [ ] CA-12: El panel incluye seccion "Preguntas frecuentes" colapsable con FAQ sobre el proceso KYC: que documentos se aceptan, cuanto tarda, que hacer si se rechaza

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del flujo completo
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: render inicial < 500ms

## Notas Tecnicas
- Usar takeUntilDestroyed() para cleanup de polling subscription
- Considerar WebSocket como upgrade futuro al polling
- El estado KYC debe persistir en un signal store para acceso desde otros componentes (e.g., boton comprar)

## Dependencias
- [MKT-BE-016] API de Estado y Gestion KYC
- [MKT-FE-014] Flujo de Upload de Documentos KYC
- Angular 18, Tailwind CSS v4

## Epica Padre
[MKT-EP-006] Verificacion de Identidad (KYC)
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-INT-003
# --------------------------------------------------------------------------
echo "  Creating [MKT-INT-003] Integracion con Proveedor de Verificacion de Identidad"
gh issue create --repo "$REPO" \
  --title "[MKT-INT-003] Integracion con Proveedor de Verificacion de Identidad" \
  --label "integration,kyc,security,third-party" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar integracion con proveedores externos de verificacion de identidad usando adapter pattern para soportar multiples proveedores (Metamap/Mati, Jumio, Onfido). Incluye webhook receptor para resultados asincronos, retry mechanism, fallback a verificacion manual, y audit log completo.

## Contexto Tecnico
- **Pattern**: Hexagonal Architecture - Port & Adapter
- **Port**: `IdentityVerificationPort` (interface en domain layer)
- **Adapters**: MetamapAdapter, JumioAdapter, ManualVerificationAdapter
- **Webhook**: Flask endpoint para recibir callbacks de proveedores
- **Retry**: Exponential backoff con jitter (1s, 2s, 4s, 8s, max 5 intentos)
- **Circuit Breaker**: pybreaker con threshold 5 failures, reset 60s

## Arquitectura
```python
# Port (domain layer)
class IdentityVerificationPort(ABC):
    @abstractmethod
    def verify_document(self, document: KYCDocument) -> VerificationResult: ...
    @abstractmethod
    def verify_face_match(self, selfie: KYCDocument, id_photo: KYCDocument) -> FaceMatchResult: ...
    @abstractmethod
    def check_watchlists(self, person: PersonData) -> WatchlistResult: ...
    @abstractmethod
    def get_verification_status(self, provider_ref: str) -> ProviderStatus: ...

# Adapter (infrastructure layer)
class MetamapAdapter(IdentityVerificationPort):
    def __init__(self, api_key: str, api_secret: str, base_url: str, timeout: int = 30): ...
```

## Criterios de Aceptacion
- [ ] CA-01: El IdentityVerificationPort define interface con metodos: verify_document, verify_face_match, check_watchlists, get_verification_status; todas las implementaciones respetan el contrato
- [ ] CA-02: MetamapAdapter implementa todos los metodos del port usando la API REST de Metamap v2; maneja autenticacion OAuth2, serializa/deserializa requests/responses al formato del proveedor
- [ ] CA-03: Webhook endpoint POST /api/v1/kyc/webhooks/{provider} recibe callbacks de proveedores; valida firma HMAC del webhook; parsea resultado y actualiza KYCVerification en BD
- [ ] CA-04: Retry mechanism con exponential backoff y jitter: reintentos en 1s, 2s, 4s, 8s, 16s (max 5 intentos); solo para errores transitorios (5xx, timeout, connection error); no retry en 4xx
- [ ] CA-05: Circuit breaker por proveedor: se abre despues de 5 failures consecutivos; estado half-open despues de 60s permite 1 request de prueba; si falla, se reabre; si exito, se cierra
- [ ] CA-06: Cuando el circuit breaker esta abierto, automaticamente se usa el proveedor fallback (JumioAdapter o ManualVerificationAdapter); se registra el failover en logs y metricas
- [ ] CA-07: ManualVerificationAdapter crea un ticket en cola de revision manual con toda la informacion del caso; un admin puede aprobar/rechazar desde el panel; timeout de 48h
- [ ] CA-08: Audit log registra cada interaccion con proveedores: request enviado (sin PII en logs), response recibido, proveedor usado, latencia, status code, retry count, circuit breaker state
- [ ] CA-09: La configuracion de proveedores es externalizada en environment variables / AWS SSM Parameter Store: API keys, URLs, timeouts, thresholds; cambios no requieren redeploy
- [ ] CA-10: Health check endpoint GET /api/v1/kyc/providers/health retorna estado de cada proveedor: connected/degraded/down, latencia promedio, uptime %, circuit breaker state
- [ ] CA-11: Datos sensibles (fotos de documentos, datos personales) se envian al proveedor sobre TLS 1.2+; se usa presigned URL de S3 en lugar de enviar el archivo raw cuando el proveedor lo soporta
- [ ] CA-12: Tests de integracion usan sandbox/test mode de cada proveedor; mock server para tests unitarios que simula respuestas exitosas, errores, y timeouts

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) con mocks
- [ ] Tests de integracion con sandbox de proveedor
- [ ] Documentacion de arquitectura y troubleshooting
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: latencia adapter < 30s (depende de proveedor)

## Notas Tecnicas
- Usar factory pattern para instanciar el adapter correcto basado en config
- Considerar strategy pattern para seleccion de proveedor basado en tipo de documento/region
- Los webhooks deben ser idempotentes (el proveedor puede enviar el mismo webhook multiples veces)
- Implementar dead letter queue en SQS para webhooks que fallan procesamiento

## Dependencias
- [MKT-BE-014] API de Upload de Documentos KYC
- [MKT-BE-015] Servicio de Verificacion de Identidad
- Contrato con al menos 1 proveedor de verificacion
- AWS SQS, SSM Parameter Store

## Epica Padre
[MKT-EP-006] Verificacion de Identidad (KYC)
ISSUE_EOF
)"

sleep 2

###############################################################################
# EPIC 7: [MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento
###############################################################################

echo ""
echo ">>> Creating EPIC 7: Cotizador de Lineas de Credito / Financiamiento"
gh issue create --repo "$REPO" \
  --title "[MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento" \
  --label "epic,financing,credit" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Cotizador en linea de lineas de credito vehicular donde multiples instituciones financieras pueden ofertar. Sistema bidireccional que envia informacion del cliente y vehiculo a las financieras, y recibe evaluaciones de credito en tiempo real. Incluye calculadora rapida sin datos personales, solicitud formal multi-financiera, y dashboard de ofertas con comparacion.

## Contexto Tecnico
- **Backend**: Flask 3.0 con servicio de financiamiento dedicado
- **Async**: SQS para fan-out de solicitudes a multiples financieras
- **Real-time**: WebSocket (Flask-SocketIO) y SSE para push de ofertas
- **Adapters**: Adapter pattern por financiera (REST, SOAP, custom protocols)
- **Circuit Breaker**: Por financiera para manejar failures independientemente
- **Amortizacion**: Calculo French (cuota fija), aleman, y americano

## Modelo de Datos
```python
class FinancingApplication(Base):
    __tablename__ = 'financing_applications'
    id = Column(UUID, primary_key=True)
    user_id = Column(UUID, ForeignKey('users.id'))
    vehicle_id = Column(UUID, ForeignKey('vehicles.id'))
    kyc_verification_id = Column(UUID, ForeignKey('kyc_verifications.id'))
    vehicle_price = Column(Numeric(12,2))
    down_payment = Column(Numeric(12,2))
    requested_term_months = Column(Integer)
    status = Column(Enum('draft','submitted','evaluating','offers_received','accepted','expired'))
    created_at = Column(DateTime, default=func.now())

class FinancingOffer(Base):
    __tablename__ = 'financing_offers'
    id = Column(UUID, primary_key=True)
    application_id = Column(UUID, ForeignKey('financing_applications.id'))
    institution_id = Column(UUID, ForeignKey('financial_institutions.id'))
    status = Column(Enum('pending','evaluating','approved','rejected','expired','error'))
    annual_rate = Column(Numeric(5,4))
    cat = Column(Numeric(5,4))
    monthly_payment = Column(Numeric(12,2))
    total_amount = Column(Numeric(12,2))
    term_months = Column(Integer)
    conditions = Column(JSONB)
    valid_until = Column(DateTime)
    received_at = Column(DateTime)

class FinancialInstitution(Base):
    __tablename__ = 'financial_institutions'
    id = Column(UUID, primary_key=True)
    name = Column(String(255))
    code = Column(String(50), unique=True)
    adapter_type = Column(String(50))  # rest, soap, custom
    api_base_url = Column(String(500))
    is_active = Column(Boolean, default=True)
    config = Column(JSONB)  # timeouts, credentials ref, etc.
```

## Stories de este Epic
- [MKT-BE-017] API de Calculadora de Credito
- [MKT-BE-018] API de Solicitud de Credito Multi-Financiera
- [MKT-BE-019] Adapter de Instituciones Financieras
- [MKT-BE-020] API de Evaluacion de Credito en Tiempo Real
- [MKT-FE-016] Cotizador Visual de Financiamiento
- [MKT-FE-017] Formulario de Solicitud de Credito
- [MKT-FE-018] Dashboard de Ofertas de Credito en Tiempo Real
- [MKT-INT-004] Integracion Bidireccional con Financieras

## Dependencias
- [MKT-EP-006] KYC (verificacion aprobada para solicitud formal)
- [MKT-EP-003] Busqueda y Detalle (datos del vehiculo)
- [MKT-EP-001] Autenticacion

## Notas Tecnicas
- La calculadora rapida NO requiere autenticacion ni KYC
- La solicitud formal SI requiere autenticacion + KYC aprobado
- Las ofertas tienen TTL configurable (default 72 horas)
- Cumplimiento con regulacion CNBV para transparencia de CAT
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-017
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-017] API de Calculadora de Credito"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-017] API de Calculadora de Credito" \
  --label "backend,financing,api" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoint de simulacion rapida de credito vehicular que NO requiere datos personales ni autenticacion. Calcula pago mensual, CAT, total a pagar, y genera tabla de amortizacion para multiples escenarios de plazo.

## Contexto Tecnico
- **Framework**: Flask 3.0 blueprint financing
- **Ruta**: `/api/v1/financing/calculate` (publica, sin auth)
- **Amortizacion**: Sistema frances (cuota fija) como default
- **CAT**: Calculo conforme a regulacion CNBV (Banco de Mexico)
- **Cache**: Redis cache por combinacion de parametros (TTL 1h)

## Endpoints

### POST /api/v1/financing/calculate
```json
// Request:
{
  "vehicle_price": 450000.00,
  "down_payment_percentage": 20,
  "term_months": [12, 24, 36, 48, 60],
  "annual_rate": 12.5,
  "insurance_included": true
}

// Response 200:
{
  "vehicle_price": 450000.00,
  "down_payment": 90000.00,
  "financed_amount": 360000.00,
  "scenarios": [
    {
      "term_months": 12,
      "monthly_payment": 32045.67,
      "annual_rate": 12.5,
      "cat": 15.2,
      "total_interest": 24548.04,
      "total_amount": 384548.04,
      "insurance_monthly": 1250.00,
      "total_monthly_with_insurance": 33295.67
    },
    { "term_months": 24, "..." : "..." },
    { "term_months": 36, "..." : "..." }
  ],
  "amortization_table": [
    {
      "month": 1,
      "payment": 32045.67,
      "principal": 28295.67,
      "interest": 3750.00,
      "balance": 331704.33,
      "insurance": 1250.00
    }
  ],
  "disclaimer": "Simulacion referencial. Tasa, CAT y condiciones sujetos a aprobacion de la institucion financiera.",
  "calculated_at": "2026-03-23T10:00:00Z"
}
```

## Criterios de Aceptacion
- [ ] CA-01: POST /financing/calculate acepta vehicle_price, down_payment_percentage (0-90), term_months (array), annual_rate; retorna 200 con escenarios de financiamiento para cada plazo solicitado
- [ ] CA-02: El calculo de pago mensual usa formula de amortizacion francesa: M = P[r(1+r)^n]/[(1+r)^n-1] donde P=monto financiado, r=tasa mensual, n=numero de pagos; precision de 2 decimales
- [ ] CA-03: El CAT (Costo Anual Total) se calcula conforme a la metodologia de Banco de Mexico incluyendo: tasa de interes, comisiones de apertura (configurable), seguro (si aplica), IVA sobre intereses
- [ ] CA-04: La tabla de amortizacion completa se retorna para el primer escenario (term_months[0]) con: mes, pago, capital, interes, saldo restante; para los demas escenarios solo el resumen
- [ ] CA-05: Validacion de inputs: vehicle_price min 50,000 max 50,000,000; down_payment_percentage 0-90; term_months entre 6-84; annual_rate 0.01-99.99; retorna 422 con detalle de validacion
- [ ] CA-06: El endpoint NO requiere autenticacion (es publico) para permitir simulaciones rapidas a usuarios no registrados; sin embargo registra analytics (vehicle_price range, plazos consultados)
- [ ] CA-07: Si insurance_included es true, agrega seguro vehicular estimado al calculo (0.5% anual del valor del vehiculo, configurable); se muestra separado y sumado al pago mensual
- [ ] CA-08: El resultado se cachea en Redis con key hash de los parametros de entrada, TTL 1 hora; parametros identicos retornan resultado cacheado en < 10ms
- [ ] CA-09: El response incluye campo disclaimer obligatorio con texto legal sobre naturaleza referencial de la simulacion, configurable desde environment variable
- [ ] CA-10: Soporta multiples monedas (MXN default, USD); el campo currency en request es opcional, default "MXN"; el calculo no hace conversion, solo formatea el response con el simbolo correcto
- [ ] CA-11: Rate limiting: 100 requests por minuto por IP para prevenir scraping; retorna 429 con Retry-After header si se excede
- [ ] CA-12: Endpoint GET /financing/calculate/config retorna configuracion publica: plazos disponibles, tasas referenciales por plazo, porcentaje minimo de enganche, monto minimo/maximo financiable

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) con escenarios de calculo verificados manualmente
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada (OpenAPI/Swagger)
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: calculo < 50ms, < 10ms con cache hit

## Notas Tecnicas
- Usar Decimal (no float) para calculos financieros para evitar errores de precision
- La formula de CAT es compleja; considerar libreria financiera o implementar segun spec de Banxico
- Tabla de amortizacion puede ser grande (84 meses); considerar paginacion o entrega parcial

## Dependencias
- Redis para cache
- Configuracion de tasas referenciales en BD o config

## Epica Padre
[MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-018
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-018] API de Solicitud de Credito Multi-Financiera"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-018] API de Solicitud de Credito Multi-Financiera" \
  --label "backend,financing,api,async" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoint de solicitud formal de credito que envia la solicitud simultaneamente a multiples instituciones financieras configuradas. Usa SQS para fan-out asincrono, agrega respuestas conforme van llegando, y maneja timeouts por financiera.

## Contexto Tecnico
- **Framework**: Flask 3.0 blueprint financing
- **Ruta**: `/api/v1/financing/apply` (requiere auth + KYC aprobado)
- **Fan-out**: SQS con una cola por financiera o cola unica con routing
- **Timeout**: Configurable por financiera (default 60s)
- **Estado**: FinancingApplication con status machine

## Endpoints

### POST /api/v1/financing/apply
```json
// Request:
{
  "vehicle_id": "uuid",
  "down_payment_amount": 90000.00,
  "preferred_term_months": 36,
  "monthly_income": 45000.00,
  "employment_type": "salaried",
  "employer_name": "Empresa SA de CV",
  "employment_duration_months": 24,
  "additional_income": 5000.00,
  "financial_institutions": ["uuid-bbva", "uuid-banorte", "uuid-hsbc"],
  "consent_credit_bureau": true,
  "consent_data_sharing": true
}

// Response 202:
{
  "application_id": "uuid",
  "status": "submitted",
  "institutions_contacted": 3,
  "estimated_response_time_seconds": 60,
  "tracking_url": "/financing/applications/uuid/status",
  "websocket_url": "/financing/evaluate/ws?application_id=uuid"
}
```

### GET /api/v1/financing/applications/{id}
Estado de la solicitud con ofertas recibidas.

### GET /api/v1/financing/applications
Historial de solicitudes del usuario.

## Criterios de Aceptacion
- [ ] CA-01: POST /financing/apply valida que el usuario tiene KYC aprobado y vigente; retorna 403 con mensaje "Verificacion de identidad requerida" y link al flujo KYC si no esta aprobado
- [ ] CA-02: La solicitud se persiste en BD con status 'submitted' y retorna 202 inmediatamente; el procesamiento asincrono envia la solicitud a cada financiera seleccionada via SQS
- [ ] CA-03: El fan-out envia un mensaje SQS por cada financiera seleccionada con: datos del solicitante (de perfil + KYC), datos del vehiculo (del inventario), parametros de credito solicitados
- [ ] CA-04: Si financial_institutions no se especifica o esta vacio, se envian a TODAS las financieras activas en el sistema; si se especifica, solo a las seleccionadas
- [ ] CA-05: Cada financiera tiene su propio timeout configurable (financial_institutions.config.timeout_seconds); si no responde a tiempo, su status se marca como 'timeout' sin afectar a las demas
- [ ] CA-06: GET /financing/applications/{id} retorna la solicitud con array de ofertas recibidas hasta el momento, status por financiera, y conteo de pendientes/respondidas
- [ ] CA-07: Los campos consent_credit_bureau y consent_data_sharing son obligatorios y deben ser true; se almacena timestamp del consentimiento y IP del usuario para compliance legal
- [ ] CA-08: Validacion de inputs: vehicle_id debe existir y estar activo en inventario; down_payment minimo 10% del precio del vehiculo; monthly_income > 0; employment_type en enum valido
- [ ] CA-09: Un usuario no puede tener mas de 3 solicitudes activas (status submitted o evaluating) simultaneamente; retorna 409 si excede el limite
- [ ] CA-10: GET /financing/applications retorna historial paginado de solicitudes del usuario con: id, vehiculo (marca/modelo/ano), status, numero de ofertas, fecha, mejor oferta (si hay)
- [ ] CA-11: Los datos sensibles del solicitante (income, employer) se encriptan at-rest en la BD usando column-level encryption con KMS key dedicada
- [ ] CA-12: Al recibir todas las respuestas (o timeout de todas las pendientes), el status de la application cambia a 'offers_received' y se envia notificacion push al usuario

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion con SQS local (localstack)
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: submit < 500ms, fan-out SQS < 2s para 10 financieras

## Notas Tecnicas
- Usar SQS FIFO para garantizar orden y deduplicacion por application_id + institution_id
- Considerar DLQ para mensajes que fallan procesamiento
- Los datos del vehiculo se snapshot al momento de la solicitud (no reference) para evitar inconsistencias si el vehiculo cambia

## Dependencias
- [MKT-BE-017] API de Calculadora de Credito
- [MKT-BE-016] API de Estado y Gestion KYC (verificacion aprobada)
- [MKT-BE-019] Adapter de Instituciones Financieras
- AWS SQS

## Epica Padre
[MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-019
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-019] Adapter de Instituciones Financieras"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-019] Adapter de Instituciones Financieras" \
  --label "backend,financing,integration,adapter" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar adapter pattern para comunicacion con multiples instituciones financieras. Cada financiera tiene su propia API (REST, SOAP, o custom), formato de datos, y protocolo de autenticacion. Los adapters normalizan las interfaces para que el servicio de financiamiento trabaje con un contrato unico.

## Contexto Tecnico
- **Pattern**: Hexagonal Architecture - Port & Adapter
- **Port**: `FinancialInstitutionPort` en domain layer
- **Adapters**: Un adapter por financiera en infrastructure layer
- **Factory**: `FinancialInstitutionAdapterFactory` para instanciar el adapter correcto
- **Circuit Breaker**: pybreaker por adapter
- **Health Check**: Ping periodico a cada financiera

## Arquitectura
```python
# Port (domain layer)
class FinancialInstitutionPort(ABC):
    @abstractmethod
    def submit_application(self, application: CreditApplication) -> SubmissionResult: ...
    @abstractmethod
    def get_evaluation_status(self, reference_id: str) -> EvaluationStatus: ...
    @abstractmethod
    def get_offer_details(self, offer_id: str) -> OfferDetails: ...
    @abstractmethod
    def accept_offer(self, offer_id: str, acceptance: OfferAcceptance) -> AcceptanceResult: ...
    @abstractmethod
    def health_check(self) -> HealthStatus: ...

# Adapter example
class BBVAAdapter(FinancialInstitutionPort):
    """BBVA Mexico REST API adapter"""
    def __init__(self, config: BBVAConfig): ...
    def submit_application(self, application: CreditApplication) -> SubmissionResult:
        # Map CreditApplication -> BBVA-specific request format
        # POST to BBVA API
        # Map BBVA response -> SubmissionResult
        ...

class BanorteSOAPAdapter(FinancialInstitutionPort):
    """Banorte SOAP API adapter using zeep"""
    ...

# Factory
class AdapterFactory:
    _registry: dict[str, Type[FinancialInstitutionPort]] = {}
    @classmethod
    def create(cls, institution: FinancialInstitution) -> FinancialInstitutionPort: ...
```

## Criterios de Aceptacion
- [ ] CA-01: FinancialInstitutionPort define interface con metodos: submit_application, get_evaluation_status, get_offer_details, accept_offer, health_check; todos retornan domain objects estandarizados
- [ ] CA-02: Al menos 3 adapters implementados: uno REST (e.g., BBVAAdapter), uno SOAP (e.g., BanorteSOAPAdapter usando zeep), uno mock (MockFinancialAdapter para testing y desarrollo)
- [ ] CA-03: Cada adapter mapea el CreditApplication del dominio al formato especifico de la financiera (field mapping, transformaciones, validaciones adicionales) y viceversa para responses
- [ ] CA-04: AdapterFactory registra adapters y crea instancias basado en financial_institution.adapter_type; retorna error claro si el adapter_type no esta registrado
- [ ] CA-05: Circuit breaker por adapter con configuracion: failure_threshold=5, recovery_timeout=60s, expected_exceptions=[ConnectionError, Timeout]; estado se expone via health_check
- [ ] CA-06: Cada adapter tiene timeout configurable (institution.config.timeout_seconds); request que excede timeout lanza TimeoutError que es capturado y registrado
- [ ] CA-07: Health check por financiera ejecuta un ping/status ligero cada 5 minutos (ECS scheduled task); resultado se almacena en Redis con TTL 10min; GET /financing/institutions/health expone el estado
- [ ] CA-08: Manejo de errores estandarizado: cada adapter captura excepciones especificas del proveedor y las mapea a excepciones del dominio (InstitutionUnavailable, ApplicationRejected, InvalidData, RateLimited)
- [ ] CA-09: Logging estructurado por adapter: request_id, institution_code, method, duration_ms, status_code, error_type (sin datos PII); metricas emitidas a CloudWatch
- [ ] CA-10: Los credentials de cada financiera se almacenan en AWS SSM Parameter Store (SecureString) y se cargan al inicializar el adapter; nunca en codigo o environment variables planas
- [ ] CA-11: Cada adapter soporta modo sandbox (institution.config.sandbox=true) que apunta a endpoints de prueba del proveedor; el modo se configura por environment
- [ ] CA-12: Tests unitarios por adapter con mocking de HTTP/SOAP calls; tests de integracion con sandbox de al menos 1 proveedor real; contract tests para validar que los adapters cumplen el port

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) por adapter
- [ ] Tests de contrato (port compliance)
- [ ] Documentacion de como agregar un nuevo adapter
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: submit_application < 5s (excl. tiempo de proveedor)

## Notas Tecnicas
- Para SOAP adapters usar zeep con transport configurado (timeout, ssl)
- Considerar retry dentro del adapter para errores transitorios del proveedor (separado del retry de SQS)
- El adapter debe ser stateless para permitir multiples instancias en ECS

## Dependencias
- [MKT-BE-018] API de Solicitud de Credito Multi-Financiera
- AWS SSM Parameter Store
- Documentacion de API de financieras partners

## Epica Padre
[MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-020
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-020] API de Evaluacion de Credito en Tiempo Real"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-020] API de Evaluacion de Credito en Tiempo Real" \
  --label "backend,financing,websocket,real-time" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar canales de comunicacion en tiempo real (WebSocket y Server-Sent Events) para push de ofertas de credito conforme van llegando de cada financiera. El frontend se suscribe y recibe actualizaciones live del estado de evaluacion por financiera y las ofertas aprobadas.

## Contexto Tecnico
- **WebSocket**: Flask-SocketIO con Redis como message broker (adapter)
- **SSE**: Flask endpoint con streaming response como alternativa
- **Trigger**: Worker SQS que procesa respuestas de financieras emite evento a Redis pub/sub
- **Room**: Cada application_id tiene su propio room/channel

## Endpoints

### WebSocket /financing/evaluate/ws
```javascript
// Client connect:
socket.emit('subscribe', { application_id: 'uuid', token: 'jwt' });

// Server events:
socket.on('offer_received', {
  application_id: 'uuid',
  institution: { id: 'uuid', name: 'BBVA', logo_url: '...' },
  offer: {
    id: 'uuid',
    status: 'approved',
    annual_rate: 11.5,
    cat: 14.2,
    monthly_payment: 12500.00,
    term_months: 36,
    total_amount: 450000.00,
    conditions: ['Seguro obligatorio', 'Cuenta BBVA'],
    valid_until: '2026-03-26T10:00:00Z'
  }
});

socket.on('institution_status', {
  application_id: 'uuid',
  institution_id: 'uuid',
  status: 'evaluating' | 'approved' | 'rejected' | 'timeout' | 'error',
  message: 'Evaluando solicitud...'
});

socket.on('evaluation_complete', {
  application_id: 'uuid',
  total_offers: 3,
  best_offer_id: 'uuid',
  all_responded: true
});
```

### GET /financing/evaluate/stream?application_id=uuid
SSE endpoint como alternativa a WebSocket.
```
event: offer_received
data: {"institution": "BBVA", "offer": {...}}

event: institution_status
data: {"institution_id": "uuid", "status": "evaluating"}
```

## Criterios de Aceptacion
- [ ] CA-01: WebSocket endpoint /financing/evaluate/ws acepta conexion con JWT token valido; valida que el application_id pertenece al usuario autenticado; rechaza con error 4001 si no autorizado
- [ ] CA-02: Al suscribirse, el servidor envia inmediatamente el estado actual: ofertas ya recibidas y status por financiera, para que el cliente no pierda eventos que llegaron antes de conectar
- [ ] CA-03: Evento 'offer_received' se emite en tiempo real (< 2s latencia) cuando un worker SQS procesa una respuesta aprobada de una financiera; incluye datos completos de la oferta
- [ ] CA-04: Evento 'institution_status' se emite cuando cambia el status de evaluacion de una financiera: pending → evaluating → approved/rejected/timeout/error; incluye mensaje descriptivo
- [ ] CA-05: Evento 'evaluation_complete' se emite cuando todas las financieras han respondido o han hecho timeout; incluye conteo total de ofertas y referencia a la mejor oferta (menor CAT)
- [ ] CA-06: SSE endpoint GET /financing/evaluate/stream funciona como alternativa para clientes que no soportan WebSocket; mismos eventos, formato SSE estandar con event/data/id
- [ ] CA-07: La comparacion automatica de ofertas selecciona "mejor oferta" por menor CAT (Costo Anual Total); en empate, menor pago mensual; el campo best_offer_id se actualiza en BD
- [ ] CA-08: WebSocket usa Redis pub/sub como broker para soportar multiples instancias de servidor (horizontal scaling en ECS); cada worker publica a Redis, SocketIO distribuye a clients
- [ ] CA-09: Heartbeat cada 30s en WebSocket para detectar conexiones muertas; auto-reconnect en cliente con backoff; SSE incluye retry: 5000 para auto-reconnect del browser
- [ ] CA-10: Timeout global configurable por aplicacion (default 120s); si se alcanza, se emite evaluation_complete con las ofertas recibidas hasta ese momento y flag timeout: true
- [ ] CA-11: Maximo 5 conexiones WebSocket simultaneas por usuario para prevenir abuso; la conexion mas antigua se cierra si se excede el limite
- [ ] CA-12: Metricas emitidas a CloudWatch: conexiones activas, mensajes enviados por segundo, latencia promedio de entrega, ofertas por financiera

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) con mock de WebSocket
- [ ] Tests de integracion con multiple clients concurrentes
- [ ] Documentacion de protocolo WebSocket y SSE
- [ ] Sin vulnerabilidades de seguridad (auth en WS, no info leaks)
- [ ] Performance: latencia < 2s desde respuesta de financiera hasta push a cliente

## Notas Tecnicas
- Flask-SocketIO con async_mode='eventlet' o 'gevent' para concurrencia
- Redis adapter para multi-instance: socketio = SocketIO(message_queue='redis://...')
- Para SSE, usar generator function con yield y Connection: keep-alive
- Considerar sticky sessions en ALB para WebSocket, o usar Redis adapter

## Dependencias
- [MKT-BE-018] API de Solicitud de Credito Multi-Financiera
- [MKT-BE-019] Adapter de Instituciones Financieras
- Redis para pub/sub
- Flask-SocketIO

## Epica Padre
[MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-016
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-016] Cotizador Visual de Financiamiento"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-016] Cotizador Visual de Financiamiento" \
  --label "frontend,financing,angular,ux" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar cotizador visual interactivo de financiamiento vehicular con sliders para enganche y plazo, actualizacion en tiempo real del pago mensual, grafica de amortizacion, y comparacion de escenarios side-by-side.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Graficas**: Chart.js con ng2-charts wrapper
- **Ruta**: `/vehiculos/:id/financiamiento` (accesible sin auth)
- **API**: POST /financing/calculate

## Componentes
```
src/app/features/financing/
  calculator/
    financing-calculator.component.ts    # Componente principal
  sliders/
    down-payment-slider.component.ts     # Slider enganche
    term-slider.component.ts             # Slider plazo
  results/
    payment-summary.component.ts         # Resumen de pago
    amortization-chart.component.ts      # Grafica amortizacion
    scenario-comparison.component.ts     # Comparacion escenarios
  services/
    financing-calculator.service.ts      # HTTP + cache local
```

## Criterios de Aceptacion
- [ ] CA-01: Slider de enganche permite seleccionar desde 0% hasta 90% del valor del vehiculo en incrementos de 5%; muestra monto en pesos debajo del slider actualizado en tiempo real
- [ ] CA-02: Slider de plazo permite seleccionar 12, 24, 36, 48, 60 meses con marcadores visuales en cada opcion; el valor seleccionado se destaca visualmente
- [ ] CA-03: Al mover cualquier slider, el pago mensual estimado se actualiza en tiempo real (debounce 300ms) con animacion de conteo numerico (count-up animation)
- [ ] CA-04: La grafica de amortizacion (Chart.js) muestra stacked area chart con: capital (azul), interes (rojo), saldo restante (linea); tooltip con detalle por mes al hacer hover
- [ ] CA-05: Comparacion de escenarios muestra cards side-by-side para 3 plazos seleccionados con: pago mensual, total de intereses, total a pagar, CAT; el mas economico tiene badge "Menor costo total"
- [ ] CA-06: El cotizador se precarga con datos del vehiculo actual (precio) tomados del detalle del vehiculo; el usuario no necesita ingresar el precio manualmente
- [ ] CA-07: El componente es completamente responsive: en mobile los sliders son full-width, las cards de escenarios se apilan verticalmente, la grafica se adapta al ancho de pantalla
- [ ] CA-08: CTA prominente "Solicitar credito formal" al final del cotizador; si el usuario no esta logueado, navega a login con redirect back; si esta logueado pero sin KYC, navega a KYC
- [ ] CA-09: Los calculos se realizan primero en frontend (formula local para respuesta instantanea) y se validan contra el backend (POST /financing/calculate); si difieren > 1%, se usa el valor del backend
- [ ] CA-10: El disclaimer legal "Simulacion referencial..." se muestra debajo de los resultados en texto pequeno; el texto se obtiene del backend (configurable)
- [ ] CA-11: Loading skeleton se muestra mientras se espera respuesta del backend; error state con retry button si la API falla; resultados anteriores se mantienen visibles durante loading
- [ ] CA-12: La tasa de interes referencial se muestra como informativa con tooltip explicando que la tasa final depende de la evaluacion de cada financiera

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del flujo de cotizacion
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: actualizacion de UI < 100ms al mover slider

## Notas Tecnicas
- Usar signal() para estado reactivo de sliders y resultados
- Debounce HTTP calls con rxjs debounceTime(300) o similar en signals
- Chart.js responsive config para graficas adaptables
- Considerar Web Worker para calculo local de amortizacion en tablas grandes

## Dependencias
- [MKT-BE-017] API de Calculadora de Credito
- [MKT-EP-003] Detalle de Vehiculo (precio)
- Angular 18, Tailwind CSS v4, Chart.js

## Epica Padre
[MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-017
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-017] Formulario de Solicitud de Credito"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-017] Formulario de Solicitud de Credito" \
  --label "frontend,financing,angular,forms" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar formulario multi-step para solicitud formal de credito vehicular. Incluye pasos para datos personales, datos laborales, referencias personales, seleccion de financieras, consentimientos legales, y resumen de confirmacion.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Forms**: Angular Reactive Forms con validacion por step
- **Styling**: Tailwind CSS v4
- **Ruta**: `/financiamiento/solicitud/:vehicleId` (requiere auth + KYC)
- **API**: POST /financing/apply

## Componentes
```
src/app/features/financing/
  application-form/
    credit-application-form.component.ts   # Stepper principal
  steps/
    personal-data-step.component.ts         # Datos personales
    employment-step.component.ts            # Datos laborales
    references-step.component.ts            # Referencias personales
    institution-selection-step.component.ts # Seleccion financieras
    consent-step.component.ts               # Consentimientos legales
    review-step.component.ts                # Resumen y confirmacion
```

## Criterios de Aceptacion
- [ ] CA-01: El formulario tiene 6 pasos con stepper visual: 1) Datos personales, 2) Datos laborales, 3) Referencias, 4) Financieras, 5) Consentimiento, 6) Resumen; navegacion prev/next con validacion por paso
- [ ] CA-02: Paso 1 - Datos personales se pre-llena desde el perfil del usuario y KYC: nombre, CURP, RFC, fecha nacimiento, telefono, email, estado civil, dependientes economicos; campos editables con validacion
- [ ] CA-03: Paso 2 - Datos laborales: tipo de empleo (asalariado/independiente/pensionado), nombre empresa, puesto, antiguedad, ingreso mensual neto, ingreso adicional, telefono empresa; validacion por tipo de empleo
- [ ] CA-04: Paso 3 - Referencias personales: minimo 2 referencias con nombre, parentesco, telefono, email; boton "Agregar referencia" para mas; validacion que no repita telefono/email del solicitante
- [ ] CA-05: Paso 4 - Seleccion de financieras: muestra lista de financieras activas con logo, nombre, tasa referencial, y checkbox de seleccion; minimo 1 seleccionada; opcion "Enviar a todas"
- [ ] CA-06: Paso 5 - Consentimiento: checkbox para consulta de buro de credito con texto legal completo (expandible), checkbox de aviso de privacidad con link a PDF, checkbox de terminos y condiciones; todos obligatorios
- [ ] CA-07: Paso 6 - Resumen: muestra todos los datos agrupados por seccion con opcion de editar cada seccion (navega al paso correspondiente); boton "Enviar solicitud" deshabilitado hasta confirmar veracidad
- [ ] CA-08: Los datos del formulario se persisten en localStorage/sessionStorage entre pasos para no perder progreso si el usuario navega fuera; se limpian al enviar exitosamente o abandonar
- [ ] CA-09: Validacion en tiempo real por campo: indicadores visuales de error/exito, mensajes de error descriptivos en espanol, validacion al perder foco (blur) y al intentar avanzar de paso
- [ ] CA-10: Al enviar la solicitud (POST /financing/apply), muestra loading overlay con animacion; en exito navega al dashboard de ofertas; en error muestra mensaje y permite reintentar
- [ ] CA-11: El formulario es responsive: en mobile cada paso es full-screen con navegacion bottom-fixed; en desktop layout 2 columnas (formulario izq, resumen vehiculo der)
- [ ] CA-12: Si el usuario no tiene KYC aprobado al acceder al formulario, muestra modal informativo con boton que navega al flujo KYC y retorna automaticamente al formulario al completar

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) con tests de validacion por paso
- [ ] Tests e2e del flujo completo
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: transicion entre pasos < 200ms

## Notas Tecnicas
- Usar FormGroup anidados por paso para validacion independiente
- Signal para estado del stepper (currentStep, completedSteps, formData)
- Los datos del vehiculo se muestran como sidebar persistente (desktop) o header colapsable (mobile)
- Formateo de moneda con Angular CurrencyPipe o custom pipe para MXN

## Dependencias
- [MKT-BE-018] API de Solicitud de Credito Multi-Financiera
- [MKT-FE-015] Panel de Estado KYC (verificacion previa)
- [MKT-EP-001] Autenticacion
- Angular 18, Tailwind CSS v4

## Epica Padre
[MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-018
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-018] Dashboard de Ofertas de Credito en Tiempo Real"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-018] Dashboard de Ofertas de Credito en Tiempo Real" \
  --label "frontend,financing,angular,real-time,websocket" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar dashboard que muestra las ofertas de credito conforme llegan en tiempo real de cada financiera. Cards animados con detalles de oferta, comparacion automatica, badge de mejor oferta, timer de evaluacion, y boton para aceptar oferta y continuar al purchase flow.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4 con animaciones
- **Real-time**: WebSocket (socket.io-client) con fallback a SSE (EventSource)
- **Ruta**: `/financiamiento/ofertas/:applicationId` (requiere auth)

## Componentes
```
src/app/features/financing/
  offers-dashboard/
    offers-dashboard.component.ts          # Dashboard principal
  offer-card/
    offer-card.component.ts                # Card individual de oferta
  offer-comparison/
    offer-comparison.component.ts          # Tabla comparativa
  evaluation-timer/
    evaluation-timer.component.ts          # Timer de evaluacion
  services/
    financing-websocket.service.ts         # WebSocket client
    financing-sse.service.ts               # SSE fallback client
```

## Criterios de Aceptacion
- [ ] CA-01: Al cargar la pagina, se conecta al WebSocket /financing/evaluate/ws con el application_id; si WebSocket falla, cae automaticamente a SSE /financing/evaluate/stream
- [ ] CA-02: Las ofertas llegan como cards animados (slide-in desde la derecha con fade-in); cada card muestra: logo financiera, tasa anual, CAT, pago mensual, plazo, total a pagar
- [ ] CA-03: La oferta con menor CAT recibe badge animado "Mejor oferta" (estrella dorada con pulse animation); si llega una mejor, el badge migra con animacion suave
- [ ] CA-04: Estado por financiera se muestra como lista lateral: icono spinner (evaluando), check verde (aprobado), X rojo (rechazado), reloj naranja (timeout); actualiza en tiempo real
- [ ] CA-05: Timer de evaluacion muestra tiempo transcurrido desde envio de solicitud en formato MM:SS; cambia a verde cuando evaluation_complete; indica "Esperando N financieras..."
- [ ] CA-06: El detalle expandible por oferta muestra: tabla de amortizacion resumida (primeros 3 y ultimos 3 meses), condiciones especiales, documentos requeridos adicionales, vigencia de oferta
- [ ] CA-07: Boton "Aceptar oferta" en cada card; al click muestra modal de confirmacion con resumen de la oferta y consecuencias (compromiso con la financiera); confirmar navega al siguiente paso del purchase flow
- [ ] CA-08: Tabla comparativa side-by-side de todas las ofertas recibidas con filas: tasa, CAT, pago mensual, plazo, total, comision apertura, seguro incluido; se actualiza conforme llegan ofertas
- [ ] CA-09: Si no se reciben ofertas (todas rechazadas o timeout), muestra pantalla de "Sin ofertas disponibles" con sugerencias: ajustar enganche, intentar con otro vehiculo, contactar asesor
- [ ] CA-10: El dashboard es responsive: en mobile muestra ofertas como cards verticales scrollables; la comparacion se convierte en tabs (una financiera por tab); timer es sticky en top
- [ ] CA-11: Al desconectarse el WebSocket, muestra banner "Reconectando..." con retry automatico (backoff: 1s, 2s, 4s, 8s, max 30s); al reconectar, solicita estado actual para sincronizar
- [ ] CA-12: Sonido/vibracion sutil (configurable) al recibir nueva oferta para captar atencion del usuario; respeta preferencias de notificacion del sistema operativo

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e con mock WebSocket
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: render de nueva oferta < 300ms desde evento WS

## Notas Tecnicas
- Usar socket.io-client para WebSocket; EventSource nativo para SSE
- Signals para estado reactivo de ofertas, status por financiera, y timer
- Angular animations (@angular/animations) para card transitions
- Considerar Virtual Scroll si hay muchas ofertas (unlikely pero defensive)

## Dependencias
- [MKT-BE-020] API de Evaluacion de Credito en Tiempo Real
- [MKT-FE-017] Formulario de Solicitud de Credito
- Angular 18, Tailwind CSS v4, socket.io-client

## Epica Padre
[MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-INT-004
# --------------------------------------------------------------------------
echo "  Creating [MKT-INT-004] Integracion Bidireccional con Financieras"
gh issue create --repo "$REPO" \
  --title "[MKT-INT-004] Integracion Bidireccional con Financieras" \
  --label "integration,financing,third-party,webhook" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar integracion bidireccional completa con instituciones financieras: API client para enviar solicitudes de credito, webhook endpoint para recibir decisiones de evaluacion, mapeo de datos estandar compatible con CNBV, encriptacion de datos sensibles, reconciliacion de estados, y sandbox mode para testing.

## Contexto Tecnico
- **Outbound**: API client (httpx/requests) con retry y circuit breaker
- **Inbound**: Webhook endpoint Flask para recibir decisiones
- **Data format**: JSON estandar compatible con CNBV; mapeo a formatos propietarios por adapter
- **Security**: TLS 1.2+, payload encryption con AES-256, webhook signature verification
- **Reconciliation**: Job periodico que verifica consistencia de estados

## Arquitectura de Integracion
```
[Marketplace] → POST /api/financiera/solicitud → [Financiera]
                                                      ↓
[Marketplace] ← POST /webhooks/financing/{code} ← [Financiera]

[Marketplace] → GET /api/financiera/status/{ref} → [Financiera]  (polling fallback)
```

## Criterios de Aceptacion
- [ ] CA-01: Webhook endpoint POST /api/v1/webhooks/financing/{institution_code} recibe decisiones de financieras; valida HMAC-SHA256 signature en header X-Webhook-Signature usando secret por financiera
- [ ] CA-02: El webhook parsea el payload, lo mapea al formato estandar FinancingOffer, actualiza el status de la oferta en BD, y emite evento a Redis pub/sub para WebSocket push al usuario
- [ ] CA-03: API client por financiera envía solicitud con datos del solicitante mapeados al formato de la financiera; incluye datos del vehiculo, monto solicitado, plazo, y referencia KYC
- [ ] CA-04: Mapeo de datos estandar CNBV: RFC, CURP, nombre completo, direccion (formato SEPOMEX), ingresos, historial crediticio; transformacion bidireccional (estandar ↔ propietario por financiera)
- [ ] CA-05: Datos sensibles en transito se encriptan con AES-256-GCM usando key compartida por financiera (key exchange previo); campos encriptados: ingreso, RFC, numero de cuenta
- [ ] CA-06: Sandbox mode por financiera: cuando institution.config.sandbox=true, las requests van a URLs de sandbox, se usan credentials de prueba, y los responses se loggean completamente para debugging
- [ ] CA-07: Reconciliacion periodica (cada 30 min via ECS scheduled task): para ofertas en status 'evaluating' > 30 min, polling GET al endpoint de status de la financiera para sincronizar estado
- [ ] CA-08: Idempotencia en webhook: webhook_id o reference_id se usa como idempotency key; si ya se proceso, retorna 200 sin reprocesar; se almacena en Redis set con TTL 7 dias
- [ ] CA-09: Dead letter queue en SQS para webhooks que fallan procesamiento; alerta a Slack/email si DLQ crece > 10 mensajes; dashboard de webhooks fallidos en admin panel
- [ ] CA-10: Rate limiting outbound: respeta los rate limits de cada financiera (config por financiera); implementa token bucket algorithm con Redis para controlar velocidad de envio
- [ ] CA-11: Metricas por financiera emitidas a CloudWatch: solicitudes enviadas, ofertas recibidas, aprobaciones, rechazos, timeouts, latencia promedio, error rate; alarmas si error rate > 10%
- [ ] CA-12: Documentacion de integracion generada automaticamente: endpoint URLs, formatos de request/response, codigos de error, flujo de autenticacion; actualizada con cada cambio de adapter

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion con sandbox de al menos 1 financiera
- [ ] Documentacion de integracion completa
- [ ] Sin vulnerabilidades de seguridad (audit de crypto)
- [ ] Performance: webhook processing < 2s

## Notas Tecnicas
- Usar httpx con async para outbound calls en batch
- Webhook secret rotation: soportar 2 secrets activos simultaneamente para rotacion sin downtime
- El webhook endpoint debe retornar 200 rapido y procesar async (SQS) para no hacer timeout al proveedor
- Considerar API gateway (Kong/AWS API GW) delante de webhooks para rate limiting y auth

## Dependencias
- [MKT-BE-019] Adapter de Instituciones Financieras
- [MKT-BE-020] API de Evaluacion en Tiempo Real (Redis pub/sub)
- AWS SQS, Redis, CloudWatch
- Contratos firmados con financieras partners

## Epica Padre
[MKT-EP-007] Cotizador de Lineas de Credito / Financiamiento
ISSUE_EOF
)"

sleep 2

###############################################################################
# EPIC 8: [MKT-EP-008] Marketplace de Seguros
###############################################################################

echo ""
echo ">>> Creating EPIC 8: Marketplace de Seguros"
gh issue create --repo "$REPO" \
  --title "[MKT-EP-008] Marketplace de Seguros" \
  --label "epic,insurance,marketplace" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Plataforma donde multiples aseguradoras pueden ofertar seguros vehiculares. Incluye cotizacion instantanea a multiples aseguradoras, comparacion detallada de coberturas, y contratacion en linea con emision de poliza digital.

## Contexto Tecnico
- **Backend**: Flask 3.0 con servicio de seguros dedicado
- **Async**: SQS para fan-out de cotizaciones
- **Adapters**: Adapter pattern por aseguradora (similar a financieras)
- **Cache**: Redis para cotizaciones (TTL 24h)
- **Coberturas**: Basica (RC), Amplia, Premium (todo riesgo)
- **Compliance**: AMIS (Asociacion Mexicana de Instituciones de Seguros) estandar

## Modelo de Datos
```python
class InsuranceQuoteRequest(Base):
    __tablename__ = 'insurance_quote_requests'
    id = Column(UUID, primary_key=True)
    user_id = Column(UUID, ForeignKey('users.id'), nullable=True)
    vehicle_data = Column(JSONB)  # marca, modelo, ano, version, valor
    driver_data = Column(JSONB)   # edad, genero, CP, historial
    coverage_type = Column(Enum('basic','standard','premium'))
    status = Column(Enum('pending','quoting','completed','expired'))
    created_at = Column(DateTime, default=func.now())

class InsuranceQuote(Base):
    __tablename__ = 'insurance_quotes'
    id = Column(UUID, primary_key=True)
    request_id = Column(UUID, ForeignKey('insurance_quote_requests.id'))
    provider_id = Column(UUID, ForeignKey('insurance_providers.id'))
    annual_premium = Column(Numeric(12,2))
    monthly_premium = Column(Numeric(12,2))
    deductible_percentage = Column(Numeric(4,2))
    coverages = Column(JSONB)  # lista de coberturas incluidas
    conditions = Column(JSONB)
    valid_until = Column(DateTime)
    status = Column(Enum('quoted','selected','contracted','expired'))

class InsuranceProvider(Base):
    __tablename__ = 'insurance_providers'
    id = Column(UUID, primary_key=True)
    name = Column(String(255))
    code = Column(String(50), unique=True)
    logo_url = Column(String(500))
    rating = Column(Numeric(2,1))
    is_active = Column(Boolean, default=True)
    config = Column(JSONB)
```

## Stories de este Epic
- [MKT-BE-021] API de Cotizacion de Seguros Multi-Aseguradora
- [MKT-BE-022] Adapter de Aseguradoras
- [MKT-BE-023] API de Contratacion de Seguros
- [MKT-FE-019] Cotizador Visual de Seguros
- [MKT-FE-020] Comparador de Ofertas de Seguros
- [MKT-FE-021] Flujo de Contratacion de Seguro
- [MKT-INT-005] Integracion Bidireccional con Aseguradoras

## Dependencias
- [MKT-EP-003] Busqueda y Detalle (datos del vehiculo)
- [MKT-EP-001] Autenticacion (para contratacion)
- [MKT-EP-006] KYC (para contratacion)

## Notas Tecnicas
- Cotizacion rapida NO requiere auth (como la calculadora de credito)
- Contratacion SI requiere auth + KYC
- Las coberturas se estandarizan al formato AMIS para comparacion justa
- Cache de cotizaciones 24h reduce llamadas a aseguradoras
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-021
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-021] API de Cotizacion de Seguros Multi-Aseguradora"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-021] API de Cotizacion de Seguros Multi-Aseguradora" \
  --label "backend,insurance,api,async" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoint de cotizacion instantanea de seguros vehiculares que envia la solicitud a multiples aseguradoras simultaneamente, agrega las cotizaciones, y las retorna. Soporta cache de cotizaciones con TTL 24h para evitar llamadas repetidas.

## Contexto Tecnico
- **Framework**: Flask 3.0 blueprint insurance
- **Ruta**: `/api/v1/insurance/quote` (publica, sin auth para cotizacion rapida)
- **Fan-out**: SQS o asyncio gather para cotizaciones paralelas
- **Cache**: Redis con key compuesta (vehiculo+conductor+cobertura) y TTL 24h
- **Timeout**: 30s global, configurable por aseguradora

## Endpoints

### POST /api/v1/insurance/quote
```json
// Request:
{
  "vehicle": {
    "brand": "Toyota",
    "model": "Corolla",
    "year": 2024,
    "version": "SE CVT",
    "value": 420000.00,
    "vin": "optional",
    "license_plate": "optional"
  },
  "driver": {
    "age": 35,
    "gender": "M",
    "zip_code": "06600",
    "driving_experience_years": 10,
    "claims_last_3_years": 0
  },
  "coverage_type": "standard",
  "providers": ["qualitas", "gnp", "axa"]
}

// Response 200:
{
  "request_id": "uuid",
  "quotes": [
    {
      "provider": { "id": "uuid", "name": "Qualitas", "code": "qualitas", "logo_url": "...", "rating": 4.2 },
      "annual_premium": 18500.00,
      "monthly_premium": 1625.00,
      "deductible": { "damage": "5%", "theft": "10%" },
      "coverages": [
        { "name": "Responsabilidad Civil", "limit": "3,000,000 MXN", "included": true },
        { "name": "Danos Materiales", "limit": "Valor comercial", "included": true },
        { "name": "Robo Total", "limit": "Valor comercial", "included": true },
        { "name": "Gastos Medicos", "limit": "500,000 MXN", "included": true },
        { "name": "Asistencia Vial", "included": true },
        { "name": "Auto Sustituto", "days": 15, "included": false }
      ],
      "valid_until": "2026-03-24T10:00:00Z"
    }
  ],
  "total_providers_contacted": 3,
  "total_quotes_received": 3,
  "cached": false,
  "created_at": "2026-03-23T10:00:00Z"
}
```

## Criterios de Aceptacion
- [ ] CA-01: POST /insurance/quote acepta datos del vehiculo (marca, modelo, ano, valor obligatorios), datos del conductor (edad, genero, CP obligatorios), y tipo de cobertura; retorna 200 con array de cotizaciones
- [ ] CA-02: Fan-out a todas las aseguradoras activas si providers no se especifica; solo a las seleccionadas si se indica; cada cotizacion se solicita en paralelo con timeout individual de 30s
- [ ] CA-03: Cache en Redis con key hash de (marca+modelo+ano+valor+edad+genero+CP+cobertura), TTL 24h; si existe cache valido, retorna inmediatamente con cached:true sin contactar aseguradoras
- [ ] CA-04: Cada cotizacion incluye: prima anual, prima mensual, deducibles por tipo, lista detallada de coberturas con limites y si estan incluidas o son adicionales
- [ ] CA-05: Las cotizaciones se almacenan en BD (insurance_quotes) vinculadas al request para historial y para contratacion posterior sin re-cotizar
- [ ] CA-06: Si una aseguradora no responde a tiempo o retorna error, las demas cotizaciones se retornan normalmente; la aseguradora fallida aparece con status "error" o "timeout" en el response
- [ ] CA-07: Validacion de inputs: edad conductor 18-99, year vehiculo 2005-actual+1, valor vehiculo 50,000-50,000,000; coverage_type en enum valido; retorna 422 con detalle
- [ ] CA-08: El endpoint NO requiere autenticacion para cotizacion rapida; si el usuario esta autenticado (JWT opcional), vincula la cotizacion a su perfil para historial
- [ ] CA-09: Rate limiting: 20 requests por minuto por IP (sin auth), 60 por minuto por usuario (con auth); retorna 429 si excede
- [ ] CA-10: El response incluye total_providers_contacted y total_quotes_received para transparencia; si no hay cotizaciones, retorna 200 con quotes vacío y mensaje explicativo
- [ ] CA-11: Las coberturas se normalizan al estandar AMIS para comparacion justa entre aseguradoras: mismos nombres de cobertura, mismos formatos de limite, misma estructura
- [ ] CA-12: Metricas por aseguradora: tiempo de respuesta, tasa de exito, rango de precios; emitidas a CloudWatch para monitoring y para seleccionar aseguradoras mas confiables

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) con mocks de aseguradoras
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada (OpenAPI/Swagger)
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: cotizacion completa < 30s (depende de aseguradoras)

## Notas Tecnicas
- Usar asyncio.gather() con return_exceptions=True para paralelizar cotizaciones
- El cache key debe ser determinista: ordenar campos antes de hashear
- Considerar background refresh del cache para cotizaciones populares

## Dependencias
- [MKT-BE-022] Adapter de Aseguradoras
- Redis para cache
- SQS para procesamiento async (si se necesita)

## Epica Padre
[MKT-EP-008] Marketplace de Seguros
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-022
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-022] Adapter de Aseguradoras"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-022] Adapter de Aseguradoras" \
  --label "backend,insurance,integration,adapter" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar adapter pattern para comunicacion con multiples aseguradoras. Cada aseguradora tiene su propia API, formato de cotizacion, y catalogo de coberturas. Los adapters normalizan todo a una interface comun para que el servicio de seguros trabaje con un contrato unico.

## Contexto Tecnico
- **Pattern**: Hexagonal Architecture - Port & Adapter
- **Port**: `InsuranceProviderPort` en domain layer
- **Adapters**: Un adapter por aseguradora en infrastructure layer
- **Coberturas**: Estandarizacion AMIS para comparacion
- **Circuit Breaker**: pybreaker por adapter
- **Rate Limiting**: Token bucket por aseguradora

## Arquitectura
```python
# Port (domain layer)
class InsuranceProviderPort(ABC):
    @abstractmethod
    def get_quote(self, vehicle: VehicleData, driver: DriverData, coverage: CoverageType) -> InsuranceQuoteResult: ...
    @abstractmethod
    def get_coverage_catalog(self) -> list[CoverageDefinition]: ...
    @abstractmethod
    def submit_application(self, quote_id: str, applicant: ApplicantData) -> ApplicationResult: ...
    @abstractmethod
    def get_policy_status(self, application_ref: str) -> PolicyStatus: ...
    @abstractmethod
    def health_check(self) -> HealthStatus: ...

# Coverage standardization
class CoverageMapper:
    """Maps provider-specific coverage names to AMIS standard"""
    AMIS_STANDARD = {
        'rc': 'Responsabilidad Civil',
        'dm': 'Danos Materiales',
        'rt': 'Robo Total',
        'gm': 'Gastos Medicos Ocupantes',
        'av': 'Asistencia Vial',
        'al': 'Asistencia Legal',
    }
```

## Criterios de Aceptacion
- [ ] CA-01: InsuranceProviderPort define interface con metodos: get_quote, get_coverage_catalog, submit_application, get_policy_status, health_check; todas las implementaciones respetan el contrato
- [ ] CA-02: Al menos 3 adapters implementados: QualitasAdapter (REST), GNPAdapter (SOAP/REST), MockInsuranceAdapter (para testing); cada uno mapea request/response al formato del proveedor
- [ ] CA-03: Cada adapter normaliza las coberturas del proveedor al estandar AMIS usando CoverageMapper; coberturas desconocidas se incluyen como "adicional" con nombre original
- [ ] CA-04: Los tipos de cobertura (basic, standard, premium) se mapean a los paquetes equivalentes de cada aseguradora; si no hay equivalente exacto, se selecciona el mas cercano superior
- [ ] CA-05: Circuit breaker por adapter: threshold 5 failures, recovery 60s; cuando abierto, get_quote retorna InsuranceProviderUnavailable sin intentar la llamada
- [ ] CA-06: Rate limiting por aseguradora usando token bucket en Redis: respeta limites contractuales (e.g., Qualitas: 100 req/min, GNP: 50 req/min); configurable por proveedor
- [ ] CA-07: Cada adapter valida datos minimos requeridos por la aseguradora antes de enviar (e.g., GNP requiere VIN para cotizacion premium); retorna ValidationError con campos faltantes
- [ ] CA-08: Factory pattern: InsuranceAdapterFactory.create(provider_code) retorna el adapter configurado; lazy initialization con cache de instancias
- [ ] CA-09: Credentials por aseguradora en AWS SSM Parameter Store; cada adapter lee sus credentials al inicializarse; soporta rotacion sin restart
- [ ] CA-10: Health check por aseguradora cada 5 minutos: latencia, disponibilidad, ultimo error; resultado en Redis y expuesto via GET /insurance/providers/health
- [ ] CA-11: Sandbox mode por aseguradora (config.sandbox=true): requests a URLs de prueba, datos mock, full logging habilitado; util para onboarding de nuevas aseguradoras
- [ ] CA-12: Documentacion auto-generada por adapter: coberturas soportadas, campos requeridos, mapeo de errores, limites de rate; accesible desde admin panel

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) por adapter
- [ ] Tests de contrato (port compliance)
- [ ] Documentacion de como agregar nueva aseguradora
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: get_quote adapter processing < 2s (excl. proveedor)

## Notas Tecnicas
- Para SOAP adapters usar zeep con strict=False para tolerancia a WSDL imperfectos
- Considerar cache de coverage_catalog por aseguradora (cambia poco, TTL 7 dias)
- Los adapters deben ser thread-safe para uso en asyncio gather

## Dependencias
- Documentacion API de aseguradoras partners
- AWS SSM Parameter Store
- Redis para rate limiting y health status

## Epica Padre
[MKT-EP-008] Marketplace de Seguros
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-023
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-023] API de Contratacion de Seguros"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-023] API de Contratacion de Seguros" \
  --label "backend,insurance,api,payment" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoints para contratacion de seguros vehiculares: solicitud basada en cotizacion previa, generacion de poliza draft, integracion con flujo de pago, confirmacion, y emision de poliza digital descargable.

## Contexto Tecnico
- **Framework**: Flask 3.0 blueprint insurance
- **Ruta**: `/api/v1/insurance/apply` (requiere auth + KYC)
- **Pago**: Integracion con pasarela de pago (Stripe/Conekta)
- **Poliza**: Generacion de PDF con datos de poliza
- **Storage**: S3 para polizas emitidas

## Endpoints

### POST /api/v1/insurance/apply
```json
// Request:
{
  "quote_id": "uuid",
  "applicant": {
    "full_name": "Juan Perez Garcia",
    "rfc": "PEGJ880101XXX",
    "address": { "street": "...", "city": "...", "state": "...", "zip": "06600" },
    "phone": "+5215512345678",
    "email": "juan@example.com",
    "beneficiary": { "name": "...", "relationship": "esposa", "percentage": 100 }
  },
  "payment_method": "monthly",
  "start_date": "2026-04-01"
}

// Response 201:
{
  "application_id": "uuid",
  "status": "pending_payment",
  "policy_draft": { "number": "POL-2026-XXXXX", "start_date": "...", "end_date": "..." },
  "payment": { "amount": 1625.00, "currency": "MXN", "payment_url": "https://..." }
}
```

### POST /api/v1/insurance/applications/{id}/confirm
Confirmar pago y emitir poliza.

### GET /api/v1/insurance/policies/{id}/download
Descargar poliza PDF.

### GET /api/v1/insurance/policies
Mis polizas activas.

## Criterios de Aceptacion
- [ ] CA-01: POST /insurance/apply valida que el quote_id existe, no esta expirado (valid_until), y pertenece al usuario (o fue anonimo y se vincula ahora); retorna 409 si la cotizacion expiro
- [ ] CA-02: La solicitud requiere autenticacion y KYC aprobado; retorna 403 con mensaje descriptivo y links a login/KYC si no cumple los requisitos
- [ ] CA-03: Se envia la solicitud a la aseguradora via el adapter correspondiente con datos del asegurado, vehiculo, y cobertura seleccionada; la aseguradora retorna draft de poliza
- [ ] CA-04: El response incluye payment_url para redirigir al usuario a la pasarela de pago; soporta metodos: tarjeta credito/debito, transferencia SPEI, OXXO pay
- [ ] CA-05: POST /insurance/applications/{id}/confirm se llama despues del pago exitoso (webhook de pasarela o callback); confirma con la aseguradora y emite la poliza definitiva
- [ ] CA-06: La poliza emitida se genera como PDF con: numero de poliza, datos del asegurado, datos del vehiculo, coberturas detalladas, vigencia, deducibles, condiciones; se almacena en S3
- [ ] CA-07: GET /insurance/policies/{id}/download retorna presigned URL de S3 para descarga directa del PDF; URL con TTL de 1 hora; solo accesible por el titular de la poliza
- [ ] CA-08: GET /insurance/policies retorna lista paginada de polizas del usuario: activas, vencidas, canceladas; con datos resumidos (aseguradora, vehiculo, vigencia, proxima renovacion)
- [ ] CA-09: Al emitir poliza exitosamente, envia notificacion multicanal al usuario: email con PDF adjunto, push notification, in-app notification con link a descarga
- [ ] CA-10: Payment webhook maneja estados: successful (emitir poliza), failed (notificar usuario), pending (esperar); idempotente por payment_reference
- [ ] CA-11: Si la aseguradora rechaza la solicitud despues del pago, se inicia reembolso automatico y se notifica al usuario con motivo de rechazo
- [ ] CA-12: Audit trail completo: solicitud creada, pago iniciado, pago confirmado, poliza emitida, poliza descargada; con timestamps y actor (user/system)

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion con mock de pasarela y aseguradora
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: emision de poliza < 10s

## Notas Tecnicas
- Usar WeasyPrint o reportlab para generacion de PDF de poliza
- El PDF debe incluir QR code con URL de verificacion de poliza
- Considerar tabla insurance_applications separada de insurance_policies para lifecycle management
- El webhook de pago debe retornar 200 rapido y procesar async

## Dependencias
- [MKT-BE-021] API de Cotizacion (cotizacion previa)
- [MKT-BE-022] Adapter de Aseguradoras
- [MKT-EP-006] KYC aprobado
- Pasarela de pago (Stripe/Conekta)
- AWS S3 para polizas PDF

## Epica Padre
[MKT-EP-008] Marketplace de Seguros
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-019
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-019] Cotizador Visual de Seguros"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-019] Cotizador Visual de Seguros" \
  --label "frontend,insurance,angular,ux" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar formulario rapido de cotizacion de seguros con datos del vehiculo y conductor, seleccion visual de tipo de cobertura con cards explicativos, loading state animado mientras llegan cotizaciones, y coberturas populares pre-seleccionadas.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Ruta**: `/seguros/cotizar` o `/vehiculos/:id/seguro` (sin auth para cotizacion)
- **API**: POST /insurance/quote

## Componentes
```
src/app/features/insurance/
  quote-form/
    insurance-quote-form.component.ts     # Formulario principal
  vehicle-form/
    vehicle-data-form.component.ts         # Datos del vehiculo
  driver-form/
    driver-data-form.component.ts          # Datos del conductor
  coverage-selector/
    coverage-selector.component.ts         # Selector tipo cobertura
  quote-loading/
    quote-loading.component.ts             # Loading state
  services/
    insurance-quote.service.ts             # HTTP calls
```

## Criterios de Aceptacion
- [ ] CA-01: Formulario de 3 secciones en single page: 1) Datos del vehiculo, 2) Datos del conductor, 3) Tipo de cobertura; boton "Cotizar" al final que envia todo junto
- [ ] CA-02: Datos del vehiculo: selects cascading marca → modelo → ano → version (cargados de la API de catalogo del inventario); si viene de detalle de vehiculo, se pre-llena automaticamente
- [ ] CA-03: Datos del conductor: edad (input numerico), genero (select), codigo postal (input con validacion 5 digitos), experiencia conduciendo (select anos), siniestros ultimos 3 anos (select 0-5)
- [ ] CA-04: Selector de cobertura tipo card con 3 opciones: Basica (icono escudo basico, "Lo minimo legal", lista de coberturas), Amplia (icono escudo+, "Lo mas popular", badge "Recomendado"), Premium (icono escudo gold, "Proteccion total")
- [ ] CA-05: La cobertura "Amplia/Standard" viene pre-seleccionada por default con badge "Mas popular" destacado visualmente; al cambiar la seleccion se anima la transicion
- [ ] CA-06: Loading state mientras se espera respuesta: animacion de cards esqueleto (skeleton) con branding de aseguradoras apareciendo uno a uno, progress text "Contactando aseguradoras..."
- [ ] CA-07: Validacion en tiempo real: todos los campos obligatorios marcados con *, errores al perder foco, boton "Cotizar" deshabilitado hasta que el formulario sea valido
- [ ] CA-08: Si el usuario viene desde la pagina de detalle de un vehiculo, se pre-llenan los datos del vehiculo y se oculta esa seccion (expandible si quiere modificar); focus en datos del conductor
- [ ] CA-09: Responsive: en mobile cada seccion es colapsable (accordion), inputs full-width, coverage cards se apilan verticalmente; en desktop layout 2 columnas
- [ ] CA-10: Al recibir cotizaciones exitosamente, navega automaticamente al comparador de ofertas (/seguros/comparar/:requestId) con las cotizaciones cargadas
- [ ] CA-11: Si todas las aseguradoras fallan o no hay cotizaciones, muestra mensaje "No pudimos obtener cotizaciones. Intente ajustando los datos del vehiculo o contacte a un asesor" con CTA
- [ ] CA-12: Cada seccion del formulario muestra tooltip de ayuda: "Por que pedimos esto?" que explica por que cada dato es necesario para la cotizacion

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del flujo de cotizacion
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: formulario interactivo en < 1s, cotizacion < 30s

## Notas Tecnicas
- Usar signal() para estado del formulario y cotizaciones
- Cascading selects de vehiculo: cargar marcas al init, modelos on marca change, etc.
- Considerar autocompletado de CP para pre-llenar estado/ciudad
- Las coberturas detalladas por tipo se pueden cargar de endpoint /insurance/coverages/catalog

## Dependencias
- [MKT-BE-021] API de Cotizacion de Seguros
- [MKT-EP-003] Catalogo de vehiculos (marcas/modelos)
- Angular 18, Tailwind CSS v4

## Epica Padre
[MKT-EP-008] Marketplace de Seguros
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-020
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-020] Comparador de Ofertas de Seguros"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-020] Comparador de Ofertas de Seguros" \
  --label "frontend,insurance,angular,ux" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar tabla comparativa detallada de ofertas de seguros de multiples aseguradoras. Muestra coberturas incluidas/excluidas con checkmarks, precios, rating, deducibles, badge de mejor relacion precio-cobertura, y opciones de filtrado/ordenamiento.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Ruta**: `/seguros/comparar/:requestId` (sin auth, datos de cotizacion previa)

## Componentes
```
src/app/features/insurance/
  quote-comparison/
    quote-comparison.component.ts          # Tabla comparativa principal
  comparison-table/
    comparison-table.component.ts          # Tabla de coberturas
  quote-detail-card/
    quote-detail-card.component.ts         # Card detalle de oferta
  filters/
    quote-filters.component.ts             # Filtros y ordenamiento
  services/
    insurance-comparison.service.ts        # Logica de comparacion
```

## Criterios de Aceptacion
- [ ] CA-01: Tabla comparativa horizontal con columnas por aseguradora y filas por cobertura; cada celda muestra check verde (incluida), X gris (no incluida), o icono "+" azul (disponible como extra)
- [ ] CA-02: Header de cada columna muestra: logo aseguradora, nombre, rating (estrellas 1-5), precio mensual prominente, precio anual debajo; columna sticky en scroll horizontal mobile
- [ ] CA-03: Las filas de cobertura agrupadas por categoria: Responsabilidad Civil, Danos al Vehiculo, Robo, Personas, Asistencia; cada grupo colapsable con header de seccion
- [ ] CA-04: Badge "Mejor relacion precio-cobertura" automatico en la oferta que tiene mejor score (coberturas_incluidas / precio_mensual); se calcula en frontend con formula configurable
- [ ] CA-05: Fila de deducible por cobertura principal: muestra porcentaje o monto fijo; se destaca visualmente si es significativamente diferente entre aseguradoras (e.g., > 5% diferencia)
- [ ] CA-06: Filtrar cotizaciones por: rango de precio (slider), tipo de cobertura minimo (checkboxes), rating minimo (estrellas); ordenar por: precio asc/desc, rating, coberturas incluidas
- [ ] CA-07: Click en una oferta expande detalle: condiciones especiales, exclusiones, proceso de reclamacion, telefono de emergencia, numero de talleres afiliados
- [ ] CA-08: Boton "Contratar" en cada columna; si usuario no esta logueado, redirige a login con redirect back; si logueado sin KYC, muestra modal de KYC requerido
- [ ] CA-09: Responsive: en mobile la tabla se convierte en cards swipeables (una aseguradora por card) con boton "Comparar lado a lado" que abre modal con 2-3 seleccionadas
- [ ] CA-10: Si solo hay 1 cotizacion, muestra formato de card detallada en vez de tabla comparativa; incluye mensaje "Solo una aseguradora respondio. Puede intentar con otros tipos de cobertura."
- [ ] CA-11: Tooltips en cada cobertura explicando que cubre, ejemplos practicos (e.g., "Danos materiales: cubre reparacion de tu vehiculo si chocas contra otro auto o un poste")
- [ ] CA-12: Boton "Compartir comparacion" genera link unico con TTL 7 dias que cualquier persona puede ver (util para consultar con pareja/familia antes de decidir)

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del flujo de comparacion
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: render tabla < 500ms para 5 aseguradoras

## Notas Tecnicas
- Usar CSS grid para tabla comparativa con columns template
- Considerar virtual scroll para filas si hay muchas coberturas
- El score "mejor relacion" debe ser transparente (mostrar como se calcula al hacer hover)

## Dependencias
- [MKT-BE-021] API de Cotizacion (datos de cotizacion)
- [MKT-FE-019] Cotizador Visual (navega aqui despues de cotizar)
- Angular 18, Tailwind CSS v4

## Epica Padre
[MKT-EP-008] Marketplace de Seguros
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-021
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-021] Flujo de Contratacion de Seguro"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-021] Flujo de Contratacion de Seguro" \
  --label "frontend,insurance,angular,payment" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar flujo de contratacion de seguro vehicular: resumen de cobertura seleccionada, formulario de datos adicionales del asegurado, seleccion de metodo de pago, confirmacion, y descarga de poliza emitida.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Pago**: Integracion con componente de pasarela (Stripe Elements o Conekta Tokenizer)
- **Ruta**: `/seguros/contratar/:quoteId` (requiere auth + KYC)

## Componentes
```
src/app/features/insurance/
  contract-flow/
    insurance-contract-flow.component.ts   # Stepper principal
  coverage-summary/
    coverage-summary.component.ts          # Resumen cobertura
  applicant-form/
    applicant-form.component.ts            # Datos del asegurado
  payment-selection/
    payment-selection.component.ts         # Metodo de pago
  confirmation/
    insurance-confirmation.component.ts    # Confirmacion y poliza
```

## Criterios de Aceptacion
- [ ] CA-01: Stepper de 4 pasos: 1) Resumen de cobertura, 2) Datos del asegurado, 3) Pago, 4) Confirmacion; navegacion secuencial con validacion por paso
- [ ] CA-02: Paso 1 muestra resumen completo de la cobertura seleccionada: aseguradora (logo+nombre), todas las coberturas con limites, deducibles, prima mensual/anual, vigencia; boton "Continuar"
- [ ] CA-03: Paso 2 pre-llena datos del usuario desde perfil/KYC: nombre, RFC, direccion, telefono, email; campos adicionales: beneficiario (nombre, parentesco, porcentaje), inicio de vigencia (date picker, min=hoy)
- [ ] CA-04: Paso 3 muestra opciones de pago: tarjeta credito/debito (formulario Stripe/Conekta embebido), transferencia SPEI (muestra CLABE + referencia), OXXO (genera referencia con codigo de barras)
- [ ] CA-05: Paso 3 muestra resumen de cobro: prima (mensual o anual segun seleccion), desglose IVA, total a pagar hoy; seleccion de frecuencia de pago (mensual, trimestral, semestral, anual)
- [ ] CA-06: Paso 4 (Confirmacion) se muestra despues del pago exitoso: numero de poliza, datos principales, boton prominente "Descargar poliza PDF", opciones "Enviar a mi email" y "Compartir por WhatsApp"
- [ ] CA-07: Si el pago falla, muestra mensaje de error con opciones: reintentar con mismo metodo, cambiar metodo de pago, contactar soporte; no pierde el progreso del formulario
- [ ] CA-08: Si el pago es por SPEI/OXXO (asincrono), muestra pantalla de espera con referencia de pago, instrucciones, y mensaje "Te notificaremos cuando se confirme el pago"
- [ ] CA-09: Responsive: en mobile cada paso es full-screen; el resumen de cobertura se muestra como drawer inferior colapsable persistente; formularios de pago se adaptan al ancho
- [ ] CA-10: Validacion de datos del asegurado: RFC formato valido (regex), beneficiario porcentaje suma 100%, fecha inicio vigencia entre hoy y hoy+30 dias
- [ ] CA-11: Al confirmar poliza, muestra confetti animation (sutil) y mensaje de felicitacion; CTA secundario "Ver mis polizas" que navega al historial de polizas del usuario
- [ ] CA-12: El flujo completo se puede abandonar y retomar: los datos se guardan en sessionStorage; si la cotizacion expira durante el flujo, se muestra aviso y opcion de re-cotizar

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del flujo completo con mock de pago
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad (PCI compliance en formulario de pago)
- [ ] Performance: transicion entre pasos < 200ms

## Notas Tecnicas
- NUNCA manejar datos de tarjeta directamente; usar tokenizer de la pasarela (Stripe Elements / Conekta)
- El componente de pago debe estar en iframe/shadow DOM de la pasarela para PCI compliance
- Considerar Web Share API para boton "Compartir por WhatsApp" en mobile

## Dependencias
- [MKT-BE-023] API de Contratacion de Seguros
- [MKT-FE-020] Comparador (seleccion de oferta)
- [MKT-EP-006] KYC aprobado
- Stripe Elements / Conekta Tokenizer SDK

## Epica Padre
[MKT-EP-008] Marketplace de Seguros
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-INT-005
# --------------------------------------------------------------------------
echo "  Creating [MKT-INT-005] Integracion Bidireccional con Aseguradoras"
gh issue create --repo "$REPO" \
  --title "[MKT-INT-005] Integracion Bidireccional con Aseguradoras" \
  --label "integration,insurance,third-party,webhook" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar integracion bidireccional con aseguradoras: API client para cotizaciones y solicitudes, webhook para actualizaciones de poliza, estandar de datos AMIS, certificados SSL client/server, y ambientes sandbox por aseguradora.

## Contexto Tecnico
- **Outbound**: API client (httpx) para cotizaciones y contrataciones
- **Inbound**: Webhook endpoint para actualizaciones de poliza (emision, cancelacion, renovacion)
- **Data standard**: AMIS (Asociacion Mexicana de Instituciones de Seguros) compatible
- **Security**: Mutual TLS (mTLS) con certificados por aseguradora
- **Sandbox**: Ambiente de prueba por aseguradora

## Criterios de Aceptacion
- [ ] CA-01: API client por aseguradora implementa metodos: get_quote, submit_application, get_policy, cancel_policy; cada uno mapea datos del dominio al formato de la aseguradora y viceversa
- [ ] CA-02: Webhook endpoint POST /api/v1/webhooks/insurance/{provider_code} recibe actualizaciones de poliza; valida autenticidad (HMAC o mTLS), parsea, y actualiza estado en BD
- [ ] CA-03: Datos de cotizacion/contratacion se estructuran segun estandar AMIS: catalogo de marcas/modelos (AMIS key), tipos de cobertura estandar, formato de poliza, codigos de rechazo
- [ ] CA-04: Mutual TLS configurado por aseguradora: certificado cliente almacenado en AWS Secrets Manager, certificado servidor de aseguradora en trust store; rotacion de certificados soportada
- [ ] CA-05: Sandbox mode por aseguradora: config.sandbox=true redirige a URLs de test, usa credenciales de sandbox, logging verbose habilitado, datos de prueba estandar
- [ ] CA-06: Webhook maneja eventos: policy_issued (poliza emitida), policy_cancelled (cancelacion), policy_renewed (renovacion), claim_update (actualizacion de siniestro); cada evento actualiza BD
- [ ] CA-07: Idempotencia en webhooks: event_id como idempotency key en Redis set (TTL 30 dias); re-procesamiento seguro si se recibe duplicado
- [ ] CA-08: Reconciliacion diaria: job que compara polizas activas en BD vs estado en aseguradora; reporta discrepancias via alerta; corrige automaticamente si la diferencia es un status update perdido
- [ ] CA-09: Rate limiting outbound: respeta limites de cada aseguradora; implementa backpressure si se acerca al limite; metricas de uso vs limite en CloudWatch
- [ ] CA-10: Datos personales encriptados en transito: campos sensibles (RFC, CURP, domicilio) encriptados con key compartida por aseguradora; solo se desencriptan en el adapter antes de enviar via TLS
- [ ] CA-11: Error handling estandarizado: cada adapter mapea errores de la aseguradora a codigos de error del dominio (InsuranceError enum); retries automaticos para errores transitorios
- [ ] CA-12: Metricas por aseguradora: cotizaciones enviadas/recibidas, contrataciones exitosas/fallidas, latencia promedio, disponibilidad; dashboard en admin panel y alarmas en CloudWatch

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion con sandbox de al menos 1 aseguradora
- [ ] Documentacion de integracion y troubleshooting
- [ ] Sin vulnerabilidades de seguridad (audit de TLS y crypto)
- [ ] Performance: cotizacion outbound < 15s, webhook processing < 2s

## Notas Tecnicas
- Usar httpx con verify=custom_ca_bundle para mTLS
- Certificados mTLS en AWS Secrets Manager con rotation lambda
- AMIS publica catalogos actualizados periodicamente; importar y cachear
- Considerar API gateway delante de webhooks para centralized auth y rate limiting

## Dependencias
- [MKT-BE-022] Adapter de Aseguradoras
- [MKT-BE-023] API de Contratacion
- AWS Secrets Manager, CloudWatch
- Contratos firmados con aseguradoras

## Epica Padre
[MKT-EP-008] Marketplace de Seguros
ISSUE_EOF
)"

sleep 2

###############################################################################
# EPIC 9: [MKT-EP-009] Panel de Administracion
###############################################################################

echo ""
echo ">>> Creating EPIC 9: Panel de Administracion"
gh issue create --repo "$REPO" \
  --title "[MKT-EP-009] Panel de Administracion" \
  --label "epic,admin,dashboard" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Dashboard administrativo completo para gestionar el marketplace vehicular: KPIs principales, gestion de inventario, administracion de usuarios y roles, configuracion de partners (financieras y aseguradoras), analytics, y herramientas operativas.

## Contexto Tecnico
- **Backend**: Flask 3.0 con blueprints admin (role-based access)
- **Frontend**: Angular 18 modulo admin (lazy loaded, guard por rol)
- **Graficas**: Chart.js para dashboards
- **Roles**: admin (super), editor, viewer, dealer
- **Audit**: Registro completo de acciones administrativas
- **Data**: 11,000+ vehiculos de 18 fuentes, 7 AI agents

## Modelo de Datos Adicional
```python
class AdminAuditLog(Base):
    __tablename__ = 'admin_audit_logs'
    id = Column(UUID, primary_key=True)
    admin_id = Column(UUID, ForeignKey('users.id'))
    action = Column(String(100))  # e.g., 'vehicle.update', 'user.suspend'
    resource_type = Column(String(50))
    resource_id = Column(UUID)
    old_values = Column(JSONB, nullable=True)
    new_values = Column(JSONB, nullable=True)
    ip_address = Column(String(45))
    user_agent = Column(String(500))
    created_at = Column(DateTime, default=func.now())

class Role(Base):
    __tablename__ = 'roles'
    id = Column(UUID, primary_key=True)
    name = Column(String(50), unique=True)
    permissions = Column(JSONB)  # {'vehicles': ['read','write','delete'], ...}
```

## Stories de este Epic
- [MKT-BE-024] API de Dashboard Administrativo
- [MKT-BE-025] API de Gestion de Inventario
- [MKT-BE-026] API de Gestion de Usuarios y Roles
- [MKT-BE-027] API de Gestion de Partners (Financieras y Aseguradoras)
- [MKT-FE-022] Dashboard Administrativo Principal
- [MKT-FE-023] Panel de Gestion de Inventario
- [MKT-FE-024] Panel de Gestion de Partners

## Dependencias
- [MKT-EP-001] Autenticacion (roles y permisos)
- [MKT-EP-002] Inventario (datos de vehiculos)
- [MKT-EP-007] Financiamiento (datos de partners financieros)
- [MKT-EP-008] Seguros (datos de partners aseguradoras)

## Notas Tecnicas
- Todos los endpoints admin requieren rol admin o permisos especificos
- Audit log es obligatorio para todas las acciones de escritura
- El panel admin es un modulo separado con lazy loading para no afectar performance del marketplace publico
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-024
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-024] API de Dashboard Administrativo"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-024] API de Dashboard Administrativo" \
  --label "backend,admin,dashboard,api" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoint de dashboard administrativo que retorna KPIs principales del marketplace: usuarios registrados, vehiculos activos, transacciones, revenue, con filtros por periodo y comparacion con periodo anterior.

## Contexto Tecnico
- **Framework**: Flask 3.0 blueprint admin
- **Ruta**: `/api/v1/admin/dashboard` (requiere rol admin/viewer)
- **Cache**: Redis para KPIs con TTL 5 min (datos se actualizan frecuentemente)
- **Queries**: SQLAlchemy con optimizacion para agregaciones pesadas
- **Comparacion**: Periodo actual vs periodo anterior (MoM, WoW, YoY)

## Endpoints

### GET /api/v1/admin/dashboard
```json
// Query params: ?period=last_30_days&source=all&location=all
// Response 200:
{
  "period": { "start": "2026-02-21", "end": "2026-03-23", "label": "Ultimos 30 dias" },
  "kpis": {
    "registered_users": { "value": 15420, "change": 8.5, "change_label": "vs periodo anterior" },
    "active_vehicles": { "value": 11234, "change": -2.1, "change_label": "vs periodo anterior" },
    "total_transactions": { "value": 342, "change": 15.3, "change_label": "vs periodo anterior" },
    "revenue": { "value": 4250000.00, "currency": "MXN", "change": 22.7, "change_label": "vs periodo anterior" },
    "kyc_completed": { "value": 1205, "change": 12.0 },
    "financing_applications": { "value": 567, "change": 18.2 },
    "insurance_policies": { "value": 234, "change": 25.1 },
    "average_vehicle_price": { "value": 385000.00, "change": 3.2 }
  },
  "trends": {
    "users_daily": [{"date": "2026-02-21", "value": 45}, ...],
    "transactions_daily": [{"date": "2026-02-21", "value": 8}, ...],
    "revenue_daily": [{"date": "2026-02-21", "value": 125000}, ...]
  },
  "recent_activity": [
    {"type": "transaction", "description": "Venta Toyota Corolla 2024", "amount": 420000, "timestamp": "..."},
    {"type": "user", "description": "Nuevo usuario registrado", "timestamp": "..."}
  ],
  "alerts": [
    {"severity": "warning", "message": "5 vehiculos con precios desactualizados (>30 dias)"},
    {"severity": "info", "message": "3 nuevas financieras pendientes de activacion"}
  ]
}
```

## Criterios de Aceptacion
- [ ] CA-01: GET /admin/dashboard retorna KPIs principales: usuarios registrados, vehiculos activos, transacciones, revenue, KYC completados, solicitudes de financiamiento, polizas de seguro, precio promedio vehiculo
- [ ] CA-02: Cada KPI incluye valor actual y porcentaje de cambio vs periodo anterior equivalente (e.g., ultimos 30 dias vs 30 dias previos); cambio positivo en verde, negativo en rojo
- [ ] CA-03: Filtro por periodo: today, last_7_days, last_30_days, last_90_days, current_month, current_year, custom (start_date, end_date); default last_30_days
- [ ] CA-04: Filtro por fuente de vehiculos (18 fuentes disponibles): all o array de source_ids; filtra KPIs de vehiculos y transacciones por fuente
- [ ] CA-05: Filtro por ubicacion (estado/ciudad): filtra por ubicacion del vehiculo o del usuario segun el KPI; acepta state_code o city_id
- [ ] CA-06: Trends retorna series temporales diarias para graficas: usuarios, transacciones, revenue; granularidad diaria para periodos < 90 dias, semanal para >= 90 dias
- [ ] CA-07: Recent activity retorna ultimas 20 acciones relevantes: transacciones, usuarios nuevos, vehiculos publicados, KYC completados; paginable con cursor
- [ ] CA-08: Alerts retorna alertas del sistema con severidad (critical, warning, info): vehiculos desactualizados, partners inactivos, errores de integracion, KYC pendientes de revision manual
- [ ] CA-09: Cache en Redis con TTL 5 min por combinacion de filtros; cache se invalida al crear transaccion, registrar usuario, o cambiar status de vehiculo (eventos)
- [ ] CA-10: Solo accesible con roles admin o viewer (viewer read-only); retorna 403 si el usuario no tiene el rol requerido; el rol se obtiene del JWT
- [ ] CA-11: Performance: response time < 500ms con cache hit, < 3s sin cache para queries de agregacion sobre 11,000+ vehiculos y tablas relacionadas
- [ ] CA-12: Endpoint adicional GET /admin/dashboard/export?format=csv|xlsx exporta KPIs y trends del periodo seleccionado en formato tabular

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance benchmarks cumplidos (< 3s sin cache)

## Notas Tecnicas
- Usar materialized views o pre-computed aggregations para KPIs pesados
- Considerar CQRS: las queries del dashboard leen de read replicas o tablas pre-agregadas
- Los trends se pueden pre-calcular en batch nightly y solo calcular el dia actual en real-time

## Dependencias
- [MKT-EP-001] Autenticacion con roles
- Todas las tablas del marketplace (users, vehicles, transactions, kyc, financing, insurance)
- Redis para cache

## Epica Padre
[MKT-EP-009] Panel de Administracion
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-025
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-025] API de Gestion de Inventario"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-025] API de Gestion de Inventario" \
  --label "backend,admin,inventory,api" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoints CRUD completos para gestion administrativa de inventario vehicular: creacion manual, edicion, bulk upload via CSV/Excel, gestion de imagenes, publicar/despublicar, y gestion de precios y ofertas.

## Contexto Tecnico
- **Framework**: Flask 3.0 blueprint admin
- **Ruta**: `/api/v1/admin/vehicles` (requiere rol admin/editor)
- **Bulk**: pandas para parsing CSV/Excel, SQS para procesamiento async
- **Imagenes**: S3 + CloudFront, thumbnail generation
- **Sync**: Los 7 AI agents tambien escriben al inventario; este CRUD es el canal manual

## Endpoints

### GET /api/v1/admin/vehicles
Lista paginada con filtros avanzados.

### POST /api/v1/admin/vehicles
Crear vehiculo manualmente.

### PUT /api/v1/admin/vehicles/{id}
Actualizar vehiculo.

### DELETE /api/v1/admin/vehicles/{id}
Soft delete.

### POST /api/v1/admin/vehicles/bulk-upload
Upload CSV/Excel para creacion masiva.

### PUT /api/v1/admin/vehicles/{id}/status
Publicar/despublicar.

### POST /api/v1/admin/vehicles/{id}/images
Upload de imagenes.

### PUT /api/v1/admin/vehicles/{id}/pricing
Actualizar precio y ofertas.

## Criterios de Aceptacion
- [ ] CA-01: GET /admin/vehicles retorna lista paginada (limit/offset) con filtros: status (draft/published/sold/archived), source (manual/agent-name), price range, brand, model, year, location; busqueda por texto libre
- [ ] CA-02: POST /admin/vehicles crea vehiculo con validacion completa: marca (del catalogo), modelo, ano (2005-actual+1), precio (> 0), ubicacion, al menos 1 imagen; retorna 201 con el vehiculo creado
- [ ] CA-03: PUT /admin/vehicles/{id} actualiza cualquier campo; cambios se registran en audit log con old_values y new_values; retorna 200 con vehiculo actualizado
- [ ] CA-04: DELETE /admin/vehicles/{id} es soft delete (status='archived'); solo admin puede hard delete; el vehiculo archivado no aparece en busquedas publicas pero si en admin
- [ ] CA-05: POST /admin/vehicles/bulk-upload acepta CSV o Excel (xlsx); valida formato, headers esperados, datos de cada fila; procesa async via SQS; retorna 202 con job_id para tracking
- [ ] CA-06: El bulk upload reporta progreso: GET /admin/vehicles/bulk-upload/{job_id} retorna total_rows, processed, succeeded, failed, errors (array con row number y motivo)
- [ ] CA-07: PUT /admin/vehicles/{id}/status cambia entre draft, published, unpublished; publicar valida datos completos minimos (titulo, precio, 1+ imagen, ubicacion); despublicar es instantaneo
- [ ] CA-08: POST /admin/vehicles/{id}/images acepta hasta 20 imagenes por vehiculo; multipart upload a S3; genera thumbnails (150x150, 400x300, 800x600) async; retorna URLs de cada tamaño
- [ ] CA-09: PUT /admin/vehicles/{id}/pricing actualiza precio, precio anterior (para mostrar descuento), oferta especial (porcentaje off, fecha inicio, fecha fin); calcula y valida descuento
- [ ] CA-10: Todos los endpoints de escritura registran accion en admin_audit_log con: admin_id, action, resource_type='vehicle', resource_id, old/new values, IP, user_agent
- [ ] CA-11: Bulk actions endpoint PUT /admin/vehicles/bulk-action acepta array de vehicle_ids y accion (publish, unpublish, archive, update_price); procesa y retorna resultados por vehiculo
- [ ] CA-12: El listado admin incluye campos extras no visibles en marketplace publico: source (origen del dato), agent (que AI agent lo creo), sync_status, last_synced_at, internal_notes

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: listado < 500ms, bulk upload < 5min para 1000 vehiculos

## Notas Tecnicas
- Usar Marshmallow con partial=True para updates parciales
- Bulk upload: usar pandas.read_csv/read_excel con dtype validation
- Image processing: Pillow para thumbnails, considerar Lambda para async processing
- Elasticsearch re-indexing se triggerea al publicar/despublicar/editar vehiculo

## Dependencias
- [MKT-EP-002] Inventario de Vehiculos (modelo existente)
- [MKT-EP-001] Autenticacion con roles
- AWS S3, CloudFront, SQS

## Epica Padre
[MKT-EP-009] Panel de Administracion
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-026
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-026] API de Gestion de Usuarios y Roles"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-026] API de Gestion de Usuarios y Roles" \
  --label "backend,admin,users,security,api" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoints para administracion de usuarios con roles y permisos granulares. CRUD de usuarios, asignacion de roles (admin, editor, viewer, dealer), gestion de permisos por recurso, audit log de acciones administrativas, y suspension/activacion de cuentas.

## Contexto Tecnico
- **Framework**: Flask 3.0 blueprint admin
- **Ruta**: `/api/v1/admin/users` (requiere rol admin)
- **Auth**: AWS Cognito para gestion de cuentas, BD local para roles/permisos
- **RBAC**: Role-Based Access Control con permisos granulares por recurso

## Endpoints

### GET /api/v1/admin/users
Lista paginada de usuarios con filtros.

### GET /api/v1/admin/users/{id}
Detalle de usuario con roles, permisos, actividad reciente.

### PUT /api/v1/admin/users/{id}/roles
Asignar/revocar roles.

### PUT /api/v1/admin/users/{id}/status
Suspender/activar cuenta.

### GET /api/v1/admin/audit-log
Historial de acciones administrativas.

### GET /api/v1/admin/roles
Lista de roles con permisos.

### POST /api/v1/admin/roles
Crear rol personalizado.

## Criterios de Aceptacion
- [ ] CA-01: GET /admin/users retorna lista paginada con filtros: role, status (active/suspended/pending), registration_date range, KYC status, busqueda por nombre/email; sortable por cualquier campo
- [ ] CA-02: GET /admin/users/{id} retorna perfil completo: datos personales, roles asignados, permisos efectivos (union de permisos de todos sus roles), KYC status, actividad reciente (ultimas 20 acciones)
- [ ] CA-03: PUT /admin/users/{id}/roles permite asignar/revocar roles; request: {add_roles: ["editor"], remove_roles: ["viewer"]}; valida que no se quede sin el rol minimo; audit log obligatorio
- [ ] CA-04: Los permisos son granulares por recurso: vehicles (read/write/delete/publish), users (read/write/suspend), financing (read/manage), insurance (read/manage), analytics (read/export)
- [ ] CA-05: PUT /admin/users/{id}/status permite suspender o activar cuenta; suspender deshabilita login en Cognito, invalida sesiones activas, y notifica al usuario por email con motivo
- [ ] CA-06: Un admin no puede suspender su propia cuenta ni revocar su propio rol admin; requiere otro admin para estas acciones; minimo 1 admin activo siempre
- [ ] CA-07: GET /admin/audit-log retorna historial paginado de acciones administrativas con filtros: admin_id, action_type, resource_type, date_range; ordenado por fecha desc
- [ ] CA-08: Cada accion de escritura en cualquier endpoint admin registra automaticamente en audit_log: admin_id, action, resource_type, resource_id, old/new values, IP, timestamp
- [ ] CA-09: POST /admin/roles permite crear roles personalizados con permisos especificos; nombre unico; los roles predefinidos (admin, editor, viewer, dealer) no se pueden eliminar
- [ ] CA-10: El dealer role tiene permisos especiales: solo ve vehiculos de su dealership, puede editar precios de sus vehiculos, ve metricas solo de su inventario
- [ ] CA-11: Export de usuarios: GET /admin/users/export?format=csv retorna lista de usuarios filtrada en CSV; excluye datos sensibles (password, tokens); solo admin puede exportar
- [ ] CA-12: Rate limiting en endpoints admin: 120 requests/min por admin; acciones sensibles (suspend, role change) requieren confirmacion via 2FA (codigo al email del admin)

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) incluyendo tests de autorizacion
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad (RBAC bypass tests)
- [ ] Performance: listado < 500ms

## Notas Tecnicas
- Usar decorator @require_permission('resource.action') en endpoints para validacion declarativa
- Los roles se cachean en Redis por user_id (TTL 5 min) para evitar queries en cada request
- La sincronizacion con Cognito (disable/enable user) es async; si falla, marcar en BD y reintentar

## Dependencias
- [MKT-EP-001] Autenticacion (Cognito)
- AWS Cognito Admin API
- Redis para cache de roles

## Epica Padre
[MKT-EP-009] Panel de Administracion
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-027
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-027] API de Gestion de Partners (Financieras y Aseguradoras)"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-027] API de Gestion de Partners (Financieras y Aseguradoras)" \
  --label "backend,admin,partners,api" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar endpoints CRUD para administracion de instituciones financieras y aseguradoras partners. Configuracion de endpoints/credentials/timeouts, toggle activo/inactivo, y metricas de performance por partner.

## Contexto Tecnico
- **Framework**: Flask 3.0 blueprint admin
- **Ruta**: `/api/v1/admin/partners` (requiere rol admin)
- **Config**: Endpoints, credentials ref (SSM), timeouts, rate limits
- **Metricas**: Agregacion de datos de integracion por partner

## Endpoints

### GET /api/v1/admin/partners/financial-institutions
### POST /api/v1/admin/partners/financial-institutions
### PUT /api/v1/admin/partners/financial-institutions/{id}
### DELETE /api/v1/admin/partners/financial-institutions/{id}

### GET /api/v1/admin/partners/insurance-providers
### POST /api/v1/admin/partners/insurance-providers
### PUT /api/v1/admin/partners/insurance-providers/{id}
### DELETE /api/v1/admin/partners/insurance-providers/{id}

### GET /api/v1/admin/partners/{type}/{id}/metrics
### GET /api/v1/admin/partners/{type}/{id}/logs

## Criterios de Aceptacion
- [ ] CA-01: CRUD completo para financial_institutions: nombre, codigo (unico), tipo adapter (rest/soap/custom), API base URL, is_active, config JSONB; validacion de campos obligatorios
- [ ] CA-02: CRUD completo para insurance_providers: nombre, codigo (unico), logo_url, rating, tipo adapter, API base URL, is_active, config JSONB; validacion de campos obligatorios
- [ ] CA-03: El campo config de cada partner incluye: timeout_seconds, max_retries, rate_limit_rpm, sandbox_url, credentials_ssm_path (referencia a SSM, nunca el secret en claro)
- [ ] CA-04: Toggle activo/inactivo: PUT /{id} con is_active=false deshabilita inmediatamente al partner; las solicitudes en curso se completan pero no se envian nuevas; el cambio se refleja en < 1 min
- [ ] CA-05: GET /partners/{type}/{id}/metrics retorna metricas de los ultimos 30 dias: total solicitudes, aprobaciones, rechazos, timeouts, error rate, latencia promedio, latencia p95
- [ ] CA-06: GET /partners/{type}/{id}/logs retorna ultimos 100 logs de integracion: timestamp, method, status_code, latency_ms, error_message; filtrable por status y date range
- [ ] CA-07: Al crear un partner, se ejecuta health check automatico para validar conectividad; si falla, se crea pero con status warning y se notifica al admin
- [ ] CA-08: Validacion de URL: API base URL debe ser HTTPS; se valida formato URL y opcionalmente se hace DNS resolution; sandbox URL puede ser HTTP para desarrollo local
- [ ] CA-09: Soft delete: DELETE marca como deleted_at sin eliminar registros; las solicitudes historicas mantienen referencia al partner; se puede restaurar con PUT /{id}/restore
- [ ] CA-10: El listado retorna health_status en tiempo real por partner (de Redis cache): healthy (green), degraded (yellow), down (red); basado en ultimo health check
- [ ] CA-11: Audit log en todas las operaciones CRUD: quien creo/edito/desactivo el partner, que cambio, cuando; especialmente critico para cambios de credentials o URLs
- [ ] CA-12: Bulk test endpoint POST /admin/partners/test-all ejecuta health check a todos los partners activos y retorna reporte consolidado; util para diagnostico rapido

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion pasando
- [ ] Documentacion API actualizada
- [ ] Sin vulnerabilidades de seguridad (credentials nunca expuestas)
- [ ] Performance: listado < 300ms, metricas < 1s

## Notas Tecnicas
- Credentials NUNCA se retornan en GET responses; solo se muestra credentials_ssm_path y flag has_credentials: true/false
- Metricas se agregan de la tabla de logs de integracion; considerar pre-agregacion diaria para performance
- El health check periódico (cada 5 min) se ejecuta como ECS scheduled task separado

## Dependencias
- [MKT-EP-007] Financiamiento (financial_institutions table)
- [MKT-EP-008] Seguros (insurance_providers table)
- [MKT-EP-001] Autenticacion con rol admin
- AWS SSM Parameter Store

## Epica Padre
[MKT-EP-009] Panel de Administracion
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-022
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-022] Dashboard Administrativo Principal"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-022] Dashboard Administrativo Principal" \
  --label "frontend,admin,dashboard,angular" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar dashboard administrativo principal con KPI cards, graficas de tendencias, tabla de actividad reciente, alertas del sistema, y filtros de periodo. Es la landing page del modulo admin.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Graficas**: Chart.js con ng2-charts
- **Ruta**: `/admin/dashboard` (lazy loaded, guard por rol admin/viewer)
- **API**: GET /admin/dashboard

## Componentes
```
src/app/features/admin/
  dashboard/
    admin-dashboard.component.ts          # Layout principal
  kpi-cards/
    kpi-card.component.ts                  # Card individual de KPI
  trend-charts/
    trend-chart.component.ts               # Grafica de tendencia
  activity-table/
    recent-activity.component.ts           # Tabla actividad reciente
  alerts/
    system-alerts.component.ts             # Panel de alertas
  filters/
    period-filter.component.ts             # Filtro de periodo
```

## Criterios de Aceptacion
- [ ] CA-01: Layout de dashboard con grid: 4 KPI cards arriba, 2 graficas de tendencia al centro, tabla de actividad reciente abajo izquierda, alertas abajo derecha
- [ ] CA-02: KPI cards muestran: valor principal grande, label descriptivo, porcentaje de cambio con flecha arriba (verde) o abajo (rojo), icono representativo; datos de GET /admin/dashboard
- [ ] CA-03: Las 4 KPI cards principales: Usuarios Registrados, Vehiculos Activos, Transacciones, Revenue (con formato moneda MXN); adicionales colapsables: KYC, Financiamiento, Seguros
- [ ] CA-04: Graficas de tendencia (Chart.js line chart): usuarios por dia y revenue por dia; tooltip con valor exacto al hover; responsive al tamaño del contenedor
- [ ] CA-05: Filtro de periodo como dropdown en header: Hoy, Ultimos 7 dias, Ultimos 30 dias, Este mes, Este ano, Personalizado (date range picker); al cambiar, recarga todo el dashboard
- [ ] CA-06: Tabla de actividad reciente muestra ultimas 20 acciones: tipo (icono), descripcion, monto (si aplica), fecha/hora relativa ("hace 5 min"); paginable; click navega al recurso
- [ ] CA-07: Panel de alertas muestra alertas del sistema con severidad visual: rojo (critical), amarillo (warning), azul (info); click en alerta navega a la seccion relevante del admin
- [ ] CA-08: Auto-refresh cada 5 minutos (configurable); indicador de ultima actualizacion en header; boton manual "Actualizar" con animacion de loading
- [ ] CA-09: Responsive: en mobile las KPI cards se apilan 2x2, las graficas ocupan full-width vertical, la tabla y alertas se apilan; en tablet 2 columnas; en desktop 4 columnas
- [ ] CA-10: Loading state con skeleton placeholders para cada seccion; si la API falla, muestra mensaje de error por seccion sin romper el resto del dashboard
- [ ] CA-11: Las graficas soportan toggle para mostrar/ocultar datasets (e.g., mostrar solo transacciones, ocultar revenue); legend interactivo de Chart.js
- [ ] CA-12: Export button en header permite descargar KPIs y trends como CSV o Excel; llama a GET /admin/dashboard/export

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del dashboard completo
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: render completo < 2s, refresh < 1s con cache

## Notas Tecnicas
- Usar signal() para estado de KPIs, trends, actividad, alertas
- Chart.js con responsive: true y maintainAspectRatio: false para graficas adaptables
- Considerar ResizeObserver para ajustar graficas cuando cambia el layout
- El admin module es lazy loaded: loadChildren en app routes

## Dependencias
- [MKT-BE-024] API de Dashboard Administrativo
- Angular 18, Tailwind CSS v4, Chart.js / ng2-charts
- Auth guard con rol admin/viewer

## Epica Padre
[MKT-EP-009] Panel de Administracion
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-023
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-023] Panel de Gestion de Inventario"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-023] Panel de Gestion de Inventario" \
  --label "frontend,admin,inventory,angular" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar panel de gestion de inventario vehicular con tabla avanzada (busqueda, filtros, paginacion), inline editing para precio y estado, bulk actions, vista de detalle con edicion completa, y upload de imagenes drag & drop.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Tabla**: Custom data table o Angular CDK table
- **Drag & Drop**: Angular CDK drag-drop para imagenes
- **Ruta**: `/admin/inventario` (lazy loaded, guard admin/editor)
- **API**: /admin/vehicles endpoints

## Componentes
```
src/app/features/admin/
  inventory/
    inventory-list.component.ts            # Tabla principal
    inventory-detail.component.ts          # Vista detalle/edicion
    inventory-filters.component.ts         # Panel de filtros
  bulk-upload/
    bulk-upload.component.ts               # Upload CSV/Excel
  image-manager/
    image-manager.component.ts             # Drag & drop imagenes
  bulk-actions/
    bulk-actions-bar.component.ts          # Barra de acciones masivas
```

## Criterios de Aceptacion
- [ ] CA-01: Tabla de vehiculos con columnas: checkbox (seleccion), imagen thumbnail, titulo, marca/modelo/ano, precio, status (badge color), fuente, fecha publicacion, acciones (editar/ver/archivar)
- [ ] CA-02: Busqueda global por texto libre (titulo, marca, modelo, VIN) con debounce 300ms; busqueda se ejecuta server-side via query param
- [ ] CA-03: Filtros avanzados en panel lateral colapsable: status (multiselect), marca (multiselect con busqueda), rango de precio (slider), rango de ano, fuente (multiselect), ubicacion
- [ ] CA-04: Paginacion server-side con selector de items por pagina (10, 25, 50, 100); muestra "Mostrando X-Y de Z vehiculos"; navegacion primera/anterior/siguiente/ultima pagina
- [ ] CA-05: Inline editing: doble click en celda de precio abre input inline; Enter confirma (PUT /admin/vehicles/{id}/pricing), Escape cancela; feedback visual de guardado exitoso/error
- [ ] CA-06: Inline editing de status: click en badge de status abre dropdown con opciones (draft, published, unpublished); seleccion ejecuta PUT inmediato con feedback
- [ ] CA-07: Seleccion multiple con checkbox: al seleccionar 1+ vehiculos, aparece barra flotante de bulk actions: "Publicar (N)", "Despublicar (N)", "Archivar (N)"; con confirmacion modal
- [ ] CA-08: Vista de detalle abre en drawer lateral (desktop) o pagina completa (mobile): formulario editable con todos los campos del vehiculo, seccion de imagenes, historial de cambios
- [ ] CA-09: Image manager en detalle: drag & drop para reordenar imagenes, drag & drop o click para upload nuevas, boton eliminar por imagen, preview en lightbox; max 20 imagenes
- [ ] CA-10: Boton "Bulk Upload" abre modal con: zona drag & drop para CSV/Excel, template descargable, preview de primeras 5 filas, boton confirmar; muestra progreso de procesamiento
- [ ] CA-11: Indicador visual de fuente de datos: badge "Manual" (azul), "AI Agent: nombre" (morado), "Sync: fuente" (verde); filtrable por fuente en la tabla
- [ ] CA-12: Exportar tabla actual (con filtros aplicados) como CSV con boton "Exportar"; incluye todos los campos visibles

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del CRUD completo
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: tabla render < 500ms para 100 rows, inline edit < 200ms feedback

## Notas Tecnicas
- Usar Angular CDK Table con custom data source para paginacion/sort server-side
- Image upload con progress tracking (HttpClient reportProgress)
- Considerar virtual scroll para tablas muy grandes (> 100 rows en pantalla)
- Inline edit: usar ContentEditable o custom input overlay para UX fluida

## Dependencias
- [MKT-BE-025] API de Gestion de Inventario
- Angular 18, Tailwind CSS v4, Angular CDK

## Epica Padre
[MKT-EP-009] Panel de Administracion
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-024
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-024] Panel de Gestion de Partners"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-024] Panel de Gestion de Partners" \
  --label "frontend,admin,partners,angular" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar panel de administracion de partners (instituciones financieras y aseguradoras): lista con health status, formulario de alta/edicion, metricas de performance, y logs de integracion.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Ruta**: `/admin/partners` (lazy loaded, guard admin)
- **API**: /admin/partners endpoints

## Componentes
```
src/app/features/admin/
  partners/
    partners-list.component.ts             # Lista de partners
    partner-form.component.ts              # Formulario alta/edicion
    partner-metrics.component.ts           # Metricas del partner
    partner-logs.component.ts              # Logs de integracion
    health-indicator.component.ts          # Indicador de salud
```

## Criterios de Aceptacion
- [ ] CA-01: Dos tabs principales: "Instituciones Financieras" y "Aseguradoras"; cada tab muestra lista de partners con: logo, nombre, tipo adapter, health status, is_active toggle, acciones
- [ ] CA-02: Health status por partner como semaforo: circulo verde (healthy), amarillo (degraded), rojo (down); tooltip con ultimo check, latencia, y error message si aplica
- [ ] CA-03: Toggle activo/inactivo inline: switch que ejecuta PUT inmediato; con confirmacion modal si se desactiva ("Este partner tiene N solicitudes activas. Confirmar desactivacion?")
- [ ] CA-04: Formulario de alta/edicion en drawer lateral: nombre, codigo, tipo adapter (select), API base URL, sandbox URL, timeout (input numerico), max retries, rate limit RPM, notas internas
- [ ] CA-05: El campo de credentials muestra solo "Configurado" / "No configurado" con boton "Actualizar credenciales" que abre modal seguro; nunca muestra el secret en claro
- [ ] CA-06: Metricas por partner en vista detalle: graficas de ultimos 30 dias - solicitudes por dia, tasa de aprobacion, latencia promedio, error rate; comparacion con promedio de todos los partners
- [ ] CA-07: Logs de integracion por partner: tabla con timestamp, metodo (submit/status/quote), status code, latencia, error; filtrable por status (success/error) y fecha; paginacion
- [ ] CA-08: Boton "Test Connection" por partner ejecuta health check on-demand y muestra resultado inmediato: conectividad, latencia, version API, certificados validos
- [ ] CA-09: Boton "Test All" ejecuta health check a todos los partners activos simultaneamente; muestra reporte consolidado en modal con tabla de resultados
- [ ] CA-10: Responsive: en mobile la lista de partners se muestra como cards, el formulario como pagina completa, las metricas se simplifican a KPI numbers sin graficas
- [ ] CA-11: Al crear nuevo partner, wizard de 3 pasos: 1) Datos basicos, 2) Configuracion tecnica (URL, timeout, etc), 3) Test de conexion; no permite guardar si test falla (con opcion de override)
- [ ] CA-12: Indicador visual de tipo de partner: badge "REST" (azul), "SOAP" (naranja), "Custom" (morado); junto al nombre en la lista

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del CRUD de partners
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: lista con health status < 1s

## Notas Tecnicas
- Health status se obtiene de Redis (pre-calculado cada 5 min); no se calcula on-demand para la lista
- Las graficas de metricas usan Chart.js con datasets por metrica
- El formulario de credentials debe usar input type=password y nunca log the value

## Dependencias
- [MKT-BE-027] API de Gestion de Partners
- Angular 18, Tailwind CSS v4, Chart.js

## Epica Padre
[MKT-EP-009] Panel de Administracion
ISSUE_EOF
)"

sleep 2

###############################################################################
# EPIC 10: [MKT-EP-010] Notificaciones, Comunicacion & SEO
###############################################################################

echo ""
echo ">>> Creating EPIC 10: Notificaciones, Comunicacion & SEO"
gh issue create --repo "$REPO" \
  --title "[MKT-EP-010] Notificaciones, Comunicacion & SEO" \
  --label "epic,notifications,chat,seo" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Sistema de notificaciones multicanal (in-app, email, push, WhatsApp, SMS), chat en tiempo real entre compradores y vendedores, y optimizacion SEO completa para posicionamiento organico del marketplace.

## Contexto Tecnico
- **Notificaciones**: In-app (WebSocket), Email (AWS SES), Push (FCM), WhatsApp Business API, SMS (SNS)
- **Chat**: WebSocket bidireccional (Flask-SocketIO)
- **SEO**: Angular Universal (SSR), sitemap dinamico, structured data, Core Web Vitals
- **Queue**: SQS para envio asincrono de notificaciones
- **Templates**: Jinja2/HTML para emails, handlebars para WhatsApp

## Modelo de Datos
```python
class Notification(Base):
    __tablename__ = 'notifications'
    id = Column(UUID, primary_key=True)
    user_id = Column(UUID, ForeignKey('users.id'))
    type = Column(String(50))  # kyc_approved, offer_received, chat_message, etc.
    title = Column(String(255))
    body = Column(Text)
    data = Column(JSONB)  # payload adicional (links, IDs, etc.)
    channels_sent = Column(ARRAY(String))  # ['in_app', 'email', 'push']
    read_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=func.now())

class ChatConversation(Base):
    __tablename__ = 'chat_conversations'
    id = Column(UUID, primary_key=True)
    type = Column(Enum('buyer_seller', 'buyer_support'))
    participant_ids = Column(ARRAY(UUID))
    vehicle_id = Column(UUID, nullable=True)
    status = Column(Enum('active', 'archived', 'blocked'))
    last_message_at = Column(DateTime)
    created_at = Column(DateTime, default=func.now())

class ChatMessage(Base):
    __tablename__ = 'chat_messages'
    id = Column(UUID, primary_key=True)
    conversation_id = Column(UUID, ForeignKey('chat_conversations.id'))
    sender_id = Column(UUID, ForeignKey('users.id'))
    content = Column(Text)
    message_type = Column(Enum('text', 'image', 'file', 'system'))
    attachment_url = Column(String(500), nullable=True)
    read_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=func.now())
```

## Stories de este Epic
- [MKT-BE-028] Servicio de Notificaciones Multicanal
- [MKT-BE-029] API de Chat en Tiempo Real
- [MKT-FE-025] Centro de Notificaciones
- [MKT-FE-026] Chat Widget Integrado
- [MKT-BE-030] SEO Backend - Sitemap & Metadata
- [MKT-FE-027] SEO Frontend - SSR & Performance

## Dependencias
- [MKT-EP-001] Autenticacion (usuarios)
- [MKT-EP-003] Busqueda y Detalle (vehiculos para SEO)
- AWS SES, SQS, SNS, FCM
- WhatsApp Business API

## Notas Tecnicas
- Las notificaciones respetan preferencias del usuario (opt-in/opt-out por canal)
- El chat tiene moderacion basica: deteccion de spam, bloqueo de usuarios
- SSR es critico para SEO en paginas de detalle de vehiculo (11,000+ paginas indexables)
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-028
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-028] Servicio de Notificaciones Multicanal"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-028] Servicio de Notificaciones Multicanal" \
  --label "backend,notifications,email,push,whatsapp" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar servicio de notificaciones multicanal que soporta in-app (WebSocket), email (AWS SES con templates HTML), push notifications (Firebase Cloud Messaging), WhatsApp Business API, y SMS (SNS) como fallback. Incluye preferencias de canal por usuario y cola SQS para envio asincrono.

## Contexto Tecnico
- **Servicio**: `NotificationService` en domain layer
- **Canales**: In-app (WebSocket/SocketIO), Email (SES), Push (FCM), WhatsApp (Business API), SMS (SNS)
- **Queue**: SQS para envio asincrono (desacoplar del request)
- **Templates**: Jinja2 para email HTML, MessageTemplate model para WhatsApp
- **Preferencias**: User notification preferences table

## Arquitectura
```python
# Port
class NotificationPort(ABC):
    @abstractmethod
    def send(self, notification: Notification, channel: str) -> SendResult: ...

# Adapters
class InAppNotificationAdapter(NotificationPort): ...   # WebSocket emit
class EmailNotificationAdapter(NotificationPort): ...    # SES send_email
class PushNotificationAdapter(NotificationPort): ...     # FCM send
class WhatsAppNotificationAdapter(NotificationPort): ... # WhatsApp Business API
class SMSNotificationAdapter(NotificationPort): ...      # SNS publish

# Orchestrator
class NotificationOrchestrator:
    def notify(self, user_id: UUID, notification_type: str, data: dict):
        """
        1. Load user preferences
        2. Select channels based on preferences + notification type
        3. Render templates per channel
        4. Enqueue to SQS per channel
        """
```

## Endpoints
### GET /api/v1/notifications
Lista de notificaciones del usuario (in-app).

### PUT /api/v1/notifications/{id}/read
Marcar como leida.

### PUT /api/v1/notifications/read-all
Marcar todas como leidas.

### GET /api/v1/notifications/preferences
Preferencias de notificacion del usuario.

### PUT /api/v1/notifications/preferences
Actualizar preferencias.

## Criterios de Aceptacion
- [ ] CA-01: NotificationOrchestrator.notify() recibe user_id, notification_type, y data; consulta preferencias del usuario y envia por los canales habilitados; si no hay preferencias, usa defaults (in_app + email)
- [ ] CA-02: In-app: emite evento WebSocket 'notification' al usuario conectado con title, body, type, data; si el usuario no esta conectado, la notificacion se almacena y se entrega al conectarse
- [ ] CA-03: Email: renderiza template Jinja2 HTML responsive con branding del marketplace; envia via SES con from configurable; templates por tipo: kyc_approved, offer_received, payment_confirmed, etc.
- [ ] CA-04: Push: envia a todos los dispositivos registrados del usuario via FCM; soporta data message (procesable por app) y notification message (visible por OS); device tokens en tabla user_devices
- [ ] CA-05: WhatsApp: envia mensajes via WhatsApp Business API usando templates pre-aprobados por Meta; soporta templates con variables (nombre, vehiculo, monto); requiere opt-in previo del usuario
- [ ] CA-06: SMS via SNS como fallback: solo para notificaciones criticas (pago confirmado, poliza emitida) si otros canales fallan; formato texto plano max 160 chars; requiere opt-in
- [ ] CA-07: El envio es asincrono via SQS: NotificationOrchestrator encola un mensaje por canal habilitado; workers dedicados procesan cada cola; retry automatico (3 intentos con backoff)
- [ ] CA-08: GET /notifications retorna lista paginada de notificaciones in-app del usuario: title, body, type, data, read_at, created_at; filtrable por read/unread; ordenadas por fecha desc
- [ ] CA-09: PUT /notifications/preferences acepta configuracion por tipo de notificacion: {kyc: {email: true, push: true, whatsapp: false}, financing: {email: true, push: true}, ...}
- [ ] CA-10: Cada notificacion almacena channels_sent (array de canales por los que se envio) y delivery_status por canal (sent, delivered, failed, bounced) para tracking
- [ ] CA-11: Unsubscribe link en emails que permite deshabilitar canal email para ese tipo de notificacion con 1 click (token firmado en URL, no requiere login)
- [ ] CA-12: Metricas emitidas a CloudWatch: notificaciones enviadas por canal por tipo, delivery rate, bounce rate (email), open rate (email), click rate (email)
- [ ] CA-13: Rate limiting por usuario: max 50 notificaciones/dia por canal para prevenir spam; notificaciones batch se agrupan en digest si exceden el limite

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage) con mocks de SES, FCM, WhatsApp
- [ ] Tests de integracion con SES sandbox
- [ ] Documentacion de tipos de notificacion y templates
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: enqueue < 100ms, delivery in-app < 2s, email < 30s

## Notas Tecnicas
- Usar SQS con message groups por canal para procesamiento independiente
- Email templates con MJML para responsive HTML que se convierte a HTML compatible con clientes de correo
- FCM tokens deben limpiarse cuando la app reporta InvalidRegistration
- WhatsApp templates requieren aprobacion previa de Meta (24-48h)

## Dependencias
- [MKT-EP-001] Autenticacion (user_id)
- AWS SES, SQS, SNS
- Firebase Cloud Messaging
- WhatsApp Business API (Meta)

## Epica Padre
[MKT-EP-010] Notificaciones, Comunicacion & SEO
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-029
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-029] API de Chat en Tiempo Real"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-029] API de Chat en Tiempo Real" \
  --label "backend,chat,websocket,real-time" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar sistema de chat en tiempo real via WebSocket para comunicacion entre compradores y vendedores, y entre compradores y soporte. Incluye historial de conversaciones, envio de attachments, y moderacion basica.

## Contexto Tecnico
- **WebSocket**: Flask-SocketIO con Redis adapter para multi-instance
- **Storage**: PostgreSQL para mensajes, S3 para attachments
- **Moderacion**: Filtro de spam basico, bloqueo de usuarios
- **Ruta**: WebSocket /chat/ws, REST /api/v1/chat/*

## Endpoints REST

### GET /api/v1/chat/conversations
Lista de conversaciones del usuario.

### POST /api/v1/chat/conversations
Iniciar nueva conversacion.

### GET /api/v1/chat/conversations/{id}/messages
Historial de mensajes (paginado).

### POST /api/v1/chat/conversations/{id}/messages
Enviar mensaje (fallback REST si WS no disponible).

### POST /api/v1/chat/conversations/{id}/attachments
Upload de archivo adjunto.

## WebSocket Events
```javascript
// Client → Server
socket.emit('join_conversation', { conversation_id: 'uuid' });
socket.emit('send_message', { conversation_id: 'uuid', content: 'Hola', type: 'text' });
socket.emit('typing', { conversation_id: 'uuid', is_typing: true });

// Server → Client
socket.on('new_message', { message_id, sender_id, content, type, created_at });
socket.on('typing_indicator', { conversation_id, user_id, is_typing });
socket.on('message_read', { conversation_id, message_id, read_by, read_at });
```

## Criterios de Aceptacion
- [ ] CA-01: POST /chat/conversations inicia conversacion entre buyer y seller con referencia al vehiculo; valida que el vehiculo existe y esta publicado; no permite conversacion duplicada (mismos participantes + vehiculo)
- [ ] CA-02: WebSocket emit 'send_message' envia mensaje de texto en tiempo real a todos los participantes de la conversacion; el mensaje se persiste en BD y se confirma con message_id al sender
- [ ] CA-03: Typing indicator: 'typing' event se emite a otros participantes en < 500ms; auto-cancel despues de 5 segundos sin nuevo typing event; no se persiste en BD
- [ ] CA-04: GET /chat/conversations retorna lista de conversaciones del usuario ordenadas por last_message_at desc: participante, vehiculo (thumbnail+titulo), ultimo mensaje (preview 100 chars), unread count
- [ ] CA-05: GET /chat/conversations/{id}/messages retorna historial paginado (cursor-based, 50 por pagina) con: content, sender_id, message_type, attachment_url, read_at, created_at
- [ ] CA-06: POST /chat/conversations/{id}/attachments acepta imagenes (jpg, png, max 5MB) y PDFs (max 10MB); upload a S3; retorna URL y crea mensaje tipo 'image' o 'file' automaticamente
- [ ] CA-07: Read receipts: cuando un usuario lee mensajes, emite 'message_read' a otros participantes; actualiza read_at en BD; el unread count se calcula basado en mensajes con read_at=null
- [ ] CA-08: Chat buyer ↔ support: tipo especial de conversacion sin vehiculo; auto-assign al agente de soporte con menor carga; soporte puede transferir conversacion a otro agente
- [ ] CA-09: Moderacion basica: filtro de palabras prohibidas (configurable), deteccion de spam (> 10 mensajes/minuto del mismo usuario bloquea temporalmente), boton de reporte por mensaje
- [ ] CA-10: Si el destinatario no esta conectado via WebSocket, se envia notificacion push/email via NotificationService con preview del mensaje y link a la conversacion
- [ ] CA-11: Historial se mantiene permanentemente (no se elimina); solo admin puede eliminar mensajes; usuario puede archivar conversacion (no visible pero datos intactos)
- [ ] CA-12: WebSocket usa Redis adapter para funcionar con multiples instancias ECS; cada instancia suscribe a Redis pub/sub por conversation_id

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests de integracion con WebSocket client
- [ ] Documentacion de protocolo WebSocket
- [ ] Sin vulnerabilidades de seguridad (XSS en mensajes, file upload validation)
- [ ] Performance: message delivery < 500ms, historial load < 300ms

## Notas Tecnicas
- Sanitizar contenido de mensajes para prevenir XSS (bleach library)
- Usar cursor-based pagination para mensajes (created_at + id) para performance con millones de mensajes
- Considerar compresion de imagenes antes de almacenar en S3
- Flask-SocketIO rooms para conversaciones: room = conversation_id

## Dependencias
- [MKT-EP-001] Autenticacion
- [MKT-BE-028] Servicio de Notificaciones (notificar offline users)
- Redis, S3, Flask-SocketIO

## Epica Padre
[MKT-EP-010] Notificaciones, Comunicacion & SEO
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-025
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-025] Centro de Notificaciones"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-025] Centro de Notificaciones" \
  --label "frontend,notifications,angular,ux" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar centro de notificaciones completo: bell icon con badge en navbar, dropdown de notificaciones recientes, pagina completa de notificaciones con filtros, mark as read/unread, y configuracion de preferencias por canal y tipo.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Real-time**: WebSocket para recibir notificaciones live
- **Rutas**: dropdown en navbar (global), `/notificaciones` (pagina completa), `/notificaciones/preferencias`

## Componentes
```
src/app/features/notifications/
  notification-bell/
    notification-bell.component.ts         # Bell icon + badge en navbar
  notification-dropdown/
    notification-dropdown.component.ts     # Dropdown recientes
  notification-list/
    notification-list.component.ts         # Pagina completa
  notification-item/
    notification-item.component.ts         # Item individual
  notification-preferences/
    notification-preferences.component.ts  # Config preferencias
  services/
    notification.service.ts                # HTTP + WebSocket
```

## Criterios de Aceptacion
- [ ] CA-01: Bell icon en navbar con badge numerico rojo que muestra conteo de notificaciones no leidas; badge desaparece cuando todas estan leidas; se actualiza en tiempo real via WebSocket
- [ ] CA-02: Click en bell abre dropdown con ultimas 10 notificaciones: icono por tipo, titulo en bold, preview de body (max 80 chars), tiempo relativo ("hace 5 min"); items no leidos con fondo destacado
- [ ] CA-03: Cada notificacion en dropdown es clickeable: navega a la pantalla relevante (e.g., oferta de credito → dashboard de ofertas, KYC aprobado → panel KYC) y marca como leida
- [ ] CA-04: Link "Ver todas" en footer del dropdown navega a /notificaciones con lista completa paginada, scroll infinito, con todas las notificaciones
- [ ] CA-05: Pagina completa de notificaciones con filtros: tipo (dropdown multiselect), estado (todas/leidas/no leidas), rango de fecha; boton "Marcar todas como leidas"
- [ ] CA-06: Swipe left en mobile (o icono) para marcar como leida/no leida individual; batch select con checkboxes para marcar multiples
- [ ] CA-07: Pagina de preferencias (/notificaciones/preferencias): matriz tipo × canal (email, push, WhatsApp, SMS); toggle por cada celda; seccion de opt-out global por canal
- [ ] CA-08: WebSocket listener en notification.service escucha evento 'notification'; al recibir, actualiza badge count y agrega al tope del dropdown si esta abierto; suena/vibra si preferencia activa
- [ ] CA-09: Empty state cuando no hay notificaciones: ilustracion + "No tienes notificaciones" con sugerencia de activar canales adicionales en preferencias
- [ ] CA-10: Las notificaciones se agrupan por dia en la pagina completa: headers "Hoy", "Ayer", "Esta semana", fecha especifica para anteriores
- [ ] CA-11: Animacion sutil al recibir nueva notificacion: el bell hace shake animation, badge incrementa con bounce; dropdown muestra nueva notificacion con slide-in desde arriba
- [ ] CA-12: Responsive: dropdown se convierte en bottom sheet en mobile; pagina completa usa layout single column; preferencias se muestran como accordion por tipo de notificacion

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del flujo completo
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad
- [ ] Performance: dropdown open < 200ms, real-time update < 1s

## Notas Tecnicas
- Usar signal() para unread count y lista de notificaciones
- El notification.service es un singleton que mantiene WebSocket connection durante toda la sesion
- Considerar Service Worker para push notifications cuando la app no esta en primer plano
- El badge count se puede obtener de GET /notifications/unread-count (lightweight endpoint)

## Dependencias
- [MKT-BE-028] Servicio de Notificaciones Multicanal
- Angular 18, Tailwind CSS v4
- WebSocket client (socket.io-client)

## Epica Padre
[MKT-EP-010] Notificaciones, Comunicacion & SEO
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-026
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-026] Chat Widget Integrado"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-026] Chat Widget Integrado" \
  --label "frontend,chat,angular,websocket,ux" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar widget de chat integrado en el marketplace: floating button persistente, drawer con lista de conversaciones, mensajeria en tiempo real con typing indicator, y envio de imagenes/archivos.

## Contexto Tecnico
- **Framework**: Angular 18 standalone components con signals
- **Styling**: Tailwind CSS v4
- **Real-time**: WebSocket (socket.io-client) para mensajeria
- **UI**: Floating action button + drawer lateral/bottom sheet

## Componentes
```
src/app/features/chat/
  chat-button/
    chat-button.component.ts               # Floating button
  chat-drawer/
    chat-drawer.component.ts               # Drawer principal
  conversation-list/
    conversation-list.component.ts         # Lista de conversaciones
  chat-window/
    chat-window.component.ts               # Ventana de chat activa
  message-bubble/
    message-bubble.component.ts            # Burbuja de mensaje
  chat-input/
    chat-input.component.ts                # Input de mensaje + attachments
  services/
    chat.service.ts                        # WebSocket + HTTP
```

## Criterios de Aceptacion
- [ ] CA-01: Floating action button (FAB) en esquina inferior derecha con icono de chat; badge con numero de conversaciones con mensajes no leidos; visible en todas las paginas del marketplace (excepto admin)
- [ ] CA-02: Click en FAB abre drawer desde la derecha (desktop, 400px width) o bottom sheet (mobile, 90vh height) con lista de conversaciones activas
- [ ] CA-03: Lista de conversaciones muestra: avatar del otro participante, nombre, thumbnail del vehiculo (si aplica), preview ultimo mensaje, hora, badge unread count por conversacion
- [ ] CA-04: Click en conversacion abre chat window dentro del drawer: header con nombre + vehiculo, area de mensajes scrollable, input de texto en footer; boton back para volver a lista
- [ ] CA-05: Los mensajes se muestran como burbujas: propios a la derecha (azul), del otro a la izquierda (gris); con hora debajo, status de lectura (check simple enviado, doble check leido)
- [ ] CA-06: Typing indicator: cuando el otro usuario esta escribiendo, muestra animacion de 3 puntos ("...") debajo del ultimo mensaje; desaparece al dejar de escribir (timeout 5s)
- [ ] CA-07: Input de mensaje con: textarea auto-expandible (max 5 lineas), boton enviar (icono flecha), boton adjuntar (icono clip) que abre selector de archivo (imagenes + PDF)
- [ ] CA-08: Las imagenes adjuntas se muestran como thumbnails en las burbujas; click abre lightbox full-screen; los PDFs se muestran con icono + nombre del archivo, click descarga
- [ ] CA-09: Desde la pagina de detalle de vehiculo, boton "Contactar vendedor" abre el chat drawer con conversacion nueva (o existente) pre-vinculada al vehiculo; primer mensaje puede ser pre-populado
- [ ] CA-10: Auto-scroll al ultimo mensaje al abrir conversacion y al recibir nuevo mensaje; si el usuario scrolleo hacia arriba, no auto-scroll (muestra badge "Nuevo mensaje" para bajar)
- [ ] CA-11: El chat mantiene conexion WebSocket persistente mientras el drawer esta abierto; desconecta al cerrar; reconecta automaticamente si pierde conexion con indicador visual
- [ ] CA-12: Responsive: en mobile el drawer es full-screen; el chat window tiene safe-area padding para notch/home indicator; el teclado virtual no oculta el input (scroll-into-view)

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Tests e2e del flujo de chat
- [ ] Documentacion de componentes
- [ ] Sin vulnerabilidades de seguridad (XSS in messages)
- [ ] Performance: message send < 500ms round-trip, drawer open < 300ms

## Notas Tecnicas
- Usar signal() para conversations, active conversation, messages, unread counts
- Sanitizar mensajes con DomSanitizer para prevenir XSS
- Considerar virtual scroll para conversaciones con muchos mensajes
- El chat service es singleton; mantiene estado de todas las conversaciones en signals

## Dependencias
- [MKT-BE-029] API de Chat en Tiempo Real
- Angular 18, Tailwind CSS v4, socket.io-client

## Epica Padre
[MKT-EP-010] Notificaciones, Comunicacion & SEO
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-BE-030
# --------------------------------------------------------------------------
echo "  Creating [MKT-BE-030] SEO Backend - Sitemap & Metadata"
gh issue create --repo "$REPO" \
  --title "[MKT-BE-030] SEO Backend - Sitemap & Metadata" \
  --label "backend,seo,sitemap,metadata" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar infraestructura SEO backend: generacion de sitemap.xml dinamico con 11,000+ vehiculos, meta tags por vehiculo (Open Graph, Twitter Cards), structured data Schema.org Vehicle, y canonical URLs para todas las paginas indexables.

## Contexto Tecnico
- **Framework**: Flask 3.0 endpoints dedicados para SEO
- **Sitemap**: XML sitemap con sitemap index (multiples archivos si > 50,000 URLs)
- **Structured Data**: JSON-LD Schema.org Vehicle, BreadcrumbList, Organization
- **Cache**: CloudFront para sitemap, Redis para metadata pre-computed
- **Vehiculos**: 11,000+ activos de 18 fuentes

## Endpoints

### GET /sitemap.xml
Sitemap index.

### GET /sitemap-vehicles-{page}.xml
Sitemap de vehiculos paginado (max 50,000 URLs por archivo).

### GET /sitemap-pages.xml
Sitemap de paginas estaticas.

### GET /api/v1/seo/vehicle/{id}/metadata
Metadata pre-computada para un vehiculo.

### GET /api/v1/seo/vehicle/{id}/structured-data
JSON-LD structured data.

## Criterios de Aceptacion
- [ ] CA-01: GET /sitemap.xml retorna sitemap index XML valido (segun sitemaps.org protocol) con referencias a sub-sitemaps: sitemap-vehicles-1.xml, sitemap-vehicles-2.xml, sitemap-pages.xml
- [ ] CA-02: Cada sitemap de vehiculos contiene max 50,000 URLs con: loc (URL canonica), lastmod (ultima actualizacion del vehiculo), changefreq (weekly), priority (0.8 para vehiculos activos)
- [ ] CA-03: El sitemap se regenera automaticamente cada 6 horas via ECS scheduled task; se almacena en S3 y se sirve via CloudFront con cache TTL 6h; header Last-Modified correcto
- [ ] CA-04: GET /api/v1/seo/vehicle/{id}/metadata retorna: title optimizado ("{Marca} {Modelo} {Ano} - {Precio} | Marketplace"), description (150-160 chars con highlights), og:image (foto principal)
- [ ] CA-05: Open Graph tags por vehiculo: og:title, og:description, og:image (1200x630 optimizada), og:url (canonical), og:type=product, og:price:amount, og:price:currency=MXN
- [ ] CA-06: Twitter Cards: twitter:card=summary_large_image, twitter:title, twitter:description, twitter:image; optimizados para previews en Twitter/X
- [ ] CA-07: GET /api/v1/seo/vehicle/{id}/structured-data retorna JSON-LD Schema.org Vehicle: @type Vehicle, name, description, brand, model, modelDate, mileageFromOdometer, offers (price, priceCurrency, availability)
- [ ] CA-08: BreadcrumbList structured data para navegacion: Home > Vehiculos > {Marca} > {Modelo} > {Ano} {Version}; cada nivel con URL valida
- [ ] CA-09: Canonical URLs: cada vehiculo tiene URL canonica unica: /vehiculos/{slug} donde slug = "{marca}-{modelo}-{ano}-{id_corto}"; redirects 301 de URLs alternativas a la canonica
- [ ] CA-10: Metadata pre-computada en Redis (TTL 1h) por vehiculo; se invalida al editar vehiculo; el title/description se genera automaticamente pero es overrideable por admin
- [ ] CA-11: robots.txt dinamico: permite indexacion de vehiculos, paginas de busqueda con filtros canonicos, bloquea admin panel, APIs, paginas de checkout; header X-Robots-Tag para paginas dinamicas
- [ ] CA-12: Endpoint GET /api/v1/seo/health retorna metricas: total URLs en sitemap, ultima generacion, vehiculos sin metadata, errores de generacion; util para monitoring

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Validacion de sitemap con Google Search Console
- [ ] Validacion de structured data con Google Rich Results Test
- [ ] Documentacion de endpoints y formato
- [ ] Performance: sitemap generation < 5min para 11,000 vehiculos, metadata API < 50ms

## Notas Tecnicas
- Usar lxml para generacion eficiente de XML sitemap
- Los slugs deben ser URL-safe: lowercase, sin acentos, guiones en lugar de espacios
- Considerar sitemap de imagenes (image:image) para Google Images indexing
- El sitemap submit se puede automatizar via Google Search Console API

## Dependencias
- [MKT-EP-002] Inventario de Vehiculos (datos de vehiculos)
- AWS S3, CloudFront, Redis
- Google Search Console (verificacion de sitio)

## Epica Padre
[MKT-EP-010] Notificaciones, Comunicacion & SEO
ISSUE_EOF
)"

sleep 2

# --------------------------------------------------------------------------
# MKT-FE-027
# --------------------------------------------------------------------------
echo "  Creating [MKT-FE-027] SEO Frontend - SSR & Performance"
gh issue create --repo "$REPO" \
  --title "[MKT-FE-027] SEO Frontend - SSR & Performance" \
  --label "frontend,seo,ssr,performance,angular" \
  --body "$(cat <<'ISSUE_EOF'
## Descripcion
Implementar optimizaciones SEO del frontend: Angular Universal (SSR) para renderizado server-side de paginas de vehiculos, lazy loading de imagenes, optimizacion de Core Web Vitals (LCP, FID, CLS), y configuracion PWA.

## Contexto Tecnico
- **SSR**: Angular Universal con Express.js server
- **Performance**: Lazy loading, image optimization, code splitting
- **Core Web Vitals**: LCP < 2.5s, FID < 100ms, CLS < 0.1
- **PWA**: Service Worker, manifest.json, offline support basico
- **Deploy**: SSR server en ECS Fargate, static assets en CloudFront

## Configuracion
```
# Angular SSR setup
ng add @angular/ssr

# Key files
src/app/app.config.server.ts     # Server config
src/main.server.ts                # Server entry point
server.ts                         # Express server
```

## Criterios de Aceptacion
- [ ] CA-01: Angular Universal SSR configurado para renderizar server-side las paginas criticas: home (/), busqueda (/vehiculos), detalle de vehiculo (/vehiculos/:slug), paginas de seguro/financiamiento
- [ ] CA-02: El HTML renderizado por SSR incluye meta tags completos (title, description, OG, Twitter Cards) usando datos del API /seo/vehicle/{id}/metadata; los bots de Google reciben HTML completo
- [ ] CA-03: JSON-LD structured data se inyecta en el HTML SSR como <script type="application/ld+json"> en el <head>; datos de /seo/vehicle/{id}/structured-data
- [ ] CA-04: Lazy loading de imagenes con loading="lazy" attribute nativo en todas las imagenes below-the-fold; la imagen principal del vehiculo (above-fold) tiene loading="eager" y fetchpriority="high"
- [ ] CA-05: Image optimization: uso de format WebP con fallback JPEG via <picture> element; srcset con multiples resoluciones (400w, 800w, 1200w); sizes attribute acorde al layout
- [ ] CA-06: Code splitting automatico por route (Angular lazy loading); el bundle principal < 200KB gzipped; cada feature module se carga on-demand
- [ ] CA-07: Core Web Vitals targets: LCP (Largest Contentful Paint) < 2.5s en mobile 4G, FID (First Input Delay) < 100ms, CLS (Cumulative Layout Shift) < 0.1; medido con Lighthouse CI
- [ ] CA-08: PWA manifest.json configurado con: name, short_name, icons (multiple sizes), theme_color, background_color, start_url, display: standalone; installable en mobile
- [ ] CA-09: Service Worker con estrategia cache-first para assets estaticos (CSS, JS, imagenes) y network-first para API calls; offline muestra pagina "Sin conexion" con ultimo contenido cacheado
- [ ] CA-10: Preconnect/prefetch para dominios criticos: <link rel="preconnect" href="cdn.cloudfront.net">, <link rel="dns-prefetch" href="api.marketplace.com">; fonts con font-display: swap
- [ ] CA-11: Transfer State: datos obtenidos en SSR se transfieren al cliente via TransferState para evitar doble fetch; implementado para detalle de vehiculo y resultados de busqueda
- [ ] CA-12: Lighthouse CI en pipeline de CI/CD: score minimo 90 en Performance, 90 en SEO, 90 en Accessibility, 90 en Best Practices; build falla si no cumple thresholds

## Definicion de Hecho (DoD)
- [ ] Codigo revisado en PR
- [ ] Tests unitarios (>80% coverage)
- [ ] Lighthouse CI pasando con scores >= 90
- [ ] Google Rich Results Test validando structured data
- [ ] Documentacion de configuracion SSR y deployment
- [ ] Performance: TTFB < 800ms, FCP < 1.8s, LCP < 2.5s

## Notas Tecnicas
- SSR Express server debe manejar gracefully: timeouts (max 5s render), memory limits, concurrent requests
- Usar Angular provideClientHydration() para hydration eficiente post-SSR
- CloudFront debe cachear respuestas SSR con cache key basado en URL (no cookies/headers)
- Considerar ISR (Incremental Static Regeneration) para paginas de vehiculos si SSR es costoso

## Dependencias
- [MKT-BE-030] SEO Backend (metadata y structured data)
- [MKT-EP-003] Busqueda y Detalle (paginas a renderizar)
- Angular Universal (@angular/ssr)
- AWS ECS Fargate (SSR server), CloudFront

## Epica Padre
[MKT-EP-010] Notificaciones, Comunicacion & SEO
ISSUE_EOF
)"

echo ""
echo "=============================================="
echo " DONE! All issues for Epics 6-10 created."
echo "=============================================="
echo ""
echo "Summary:"
echo "  Epic 6 (KYC): 6 issues (BE-014..016, FE-014..015, INT-003)"
echo "  Epic 7 (Financing): 8 issues (BE-017..020, FE-016..018, INT-004)"
echo "  Epic 8 (Insurance): 7 issues (BE-021..023, FE-019..021, INT-005)"
echo "  Epic 9 (Admin): 7 issues (BE-024..027, FE-022..024)"
echo "  Epic 10 (Notifications/Chat/SEO): 6 issues (BE-028..030, FE-025..027)"
echo "  + 5 Epic issues"
echo "  Total: 39 issues"
