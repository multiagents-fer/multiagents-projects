# [MKT-EP-006] Verificacion de Identidad (KYC)

**Sprint**: 5-6
**Priority**: High
**Owner**: Backend & Frontend Teams
**Status**: Draft

---

## Epic Overview

This epic implements the full Know Your Customer (KYC) identity verification flow for the Vehicle Marketplace. Mexican regulation and marketplace trust requirements demand that buyers verify their identity before completing a vehicle purchase. The flow covers: document upload (INE front/back, selfie, proof of address), OCR extraction and validation, face matching, government database verification (CURP via RENAPO), anti-money laundering (PLD/FT) blacklist screening, risk scoring, and status management with 6-month expiry.

The KYC service (SVC-KYC on port 5014) is designed with an adapter pattern to support multiple verification providers, enabling easy switching or fallback between providers without code changes. All documents are stored encrypted in S3 with strict access controls.

### Architecture Context

```
[FE Angular 18] --> [SVC-GW :8080] --> [SVC-KYC :5014] --> [PostgreSQL / Redis / S3]
                                                        --> [Verification Provider (Primary)]
                                                        --> [Verification Provider (Fallback)]
                                                        --> [RENAPO CURP API]
                                                        --> [PLD/FT Blacklist Service]
```

### KYC Status Flow

```
  NOT_STARTED --> DOCUMENTS_PENDING --> IN_REVIEW --> APPROVED
                       ^                    |
                       |                    v
                       +-------------- REJECTED (with reasons)
                                           |
                                           v (after 6 months)
                                        EXPIRED

  Status Descriptions:
  - NOT_STARTED: User has not initiated KYC
  - DOCUMENTS_PENDING: Some documents uploaded, waiting for remaining
  - IN_REVIEW: All documents uploaded, verification in progress
  - APPROVED: Identity verified, valid for 6 months
  - REJECTED: Verification failed, user can re-submit
  - EXPIRED: Approval expired after 6 months, must re-verify
```

### Security Requirements
- All documents encrypted at rest (AES-256) in S3
- Documents encrypted in transit (TLS 1.3)
- Access to documents requires admin role + audit log entry
- Documents auto-deleted 12 months after KYC approval
- PII data (CURP, name, address) encrypted in PostgreSQL using column-level encryption
- All verification attempts logged for compliance audit

---

## User Stories

---

### [MKT-BE-014][SVC-KYC-API] API de Upload de Documentos KYC

**Description**:
Build a REST API within SVC-KYC (port 5014) for uploading and managing KYC documents. The API accepts four document types: INE front, INE back, selfie, and proof of address. Each upload is validated for file format (JPEG, PNG, PDF for proof of address), file size (max 10MB), and image quality (minimum resolution, blur detection). Validated documents are stored encrypted in S3 with metadata in PostgreSQL. The upload flow supports resumable uploads for poor connectivity and provides immediate feedback on image quality.

**Microservice**: SVC-KYC (port 5014)
**Layer**: API (routes) + APP (document processing) + DOM (document domain) + INF (S3 adapter, image processing)

#### Technical Context

**Endpoints**:

```
POST   /api/v1/kyc/documents/upload
       Content-Type: multipart/form-data
       Fields: document_type (ine_front|ine_back|selfie|proof_of_address), file
       Response: 201 DocumentUploadResponse | 400 ValidationError | 413 FileTooLarge

GET    /api/v1/kyc/documents
       Response: 200 { "documents": [...], "completeness": { "ine_front": true, "ine_back": true, "selfie": false, "proof_of_address": false } }

GET    /api/v1/kyc/documents/{document_id}
       Response: 200 DocumentDetailResponse

DELETE /api/v1/kyc/documents/{document_id}
       Response: 204 No Content | 409 CannotDeleteDuringReview

POST   /api/v1/kyc/documents/{document_id}/replace
       Content-Type: multipart/form-data
       Fields: file
       Response: 200 DocumentUploadResponse

GET    /api/v1/kyc/documents/{document_id}/preview
       Query params: ?size=thumbnail|medium|original
       Response: 200 image/jpeg (signed S3 URL redirect) | 404 NotFound

POST   /api/v1/kyc/documents/validate
       Content-Type: multipart/form-data
       Fields: document_type, file
       Response: 200 { "valid": true|false, "issues": [...], "quality_score": 85 }
       (Pre-upload validation, does not store the file)
```

**Data Models**:

```python
# DOM Layer - domain/models/kyc_document.py
class KYCDocument:
    id: UUID
    user_id: UUID
    document_type: DocumentType
    file_name: str
    file_size_bytes: int
    mime_type: str
    s3_key: str  # encrypted path
    s3_bucket: str
    encryption_key_id: str  # KMS key reference
    quality_score: int  # 0-100
    quality_issues: List[str]
    upload_ip: str
    upload_user_agent: str
    status: DocumentStatus  # uploaded, validated, rejected, expired
    rejection_reason: Optional[str]
    uploaded_at: datetime
    validated_at: Optional[datetime]
    expires_at: Optional[datetime]
    version: int  # supports re-upload

class DocumentType(Enum):
    INE_FRONT = "ine_front"
    INE_BACK = "ine_back"
    SELFIE = "selfie"
    PROOF_OF_ADDRESS = "proof_of_address"

class DocumentStatus(Enum):
    UPLOADED = "uploaded"
    VALIDATED = "validated"
    REJECTED = "rejected"
    EXPIRED = "expired"

class ImageQualityResult:
    resolution_ok: bool
    resolution_width: int
    resolution_height: int
    min_resolution: str  # "640x480"
    blur_score: float  # 0-100, higher = sharper
    blur_ok: bool
    brightness_ok: bool
    brightness_value: float
    glare_detected: bool
    face_detected: bool  # for INE front and selfie
    document_edges_detected: bool  # for INE front/back
    overall_quality_score: int  # 0-100
    issues: List[str]
```

**Marshmallow Schemas**:

```python
# API Layer - api/schemas/kyc_document_schema.py
class DocumentUploadResponseSchema(Schema):
    id = fields.UUID(dump_only=True)
    document_type = fields.String()
    file_name = fields.String()
    file_size_bytes = fields.Integer()
    quality_score = fields.Integer()
    quality_issues = fields.List(fields.String())
    status = fields.String()
    uploaded_at = fields.DateTime()
    preview_url = fields.String()  # signed URL, expires in 15 minutes

class DocumentCompletenessSchema(Schema):
    ine_front = fields.Boolean()
    ine_back = fields.Boolean()
    selfie = fields.Boolean()
    proof_of_address = fields.Boolean()
    all_complete = fields.Boolean()
    missing_documents = fields.List(fields.String())
```

#### Acceptance Criteria

1. **AC-001**: POST `/api/v1/kyc/documents/upload` accepts a `multipart/form-data` request with fields `document_type` (enum: ine_front, ine_back, selfie, proof_of_address) and `file` (the binary file). Returns 201 with the document metadata including quality assessment.
2. **AC-002**: File format validation: INE front/back and selfie accept JPEG and PNG only. Proof of address accepts JPEG, PNG, and PDF. Any other format returns 400 with `{ "error": "invalid_format", "accepted_formats": ["image/jpeg", "image/png"] }`.
3. **AC-003**: File size validation: Maximum 10MB per document. Files exceeding the limit return 413 with `{ "error": "file_too_large", "max_size_bytes": 10485760, "received_size_bytes": N }`.
4. **AC-004**: Image quality validation runs automatically on upload and returns a `quality_score` (0-100) with specific `quality_issues` list. Checks include: minimum resolution (640x480 for INE, 480x480 for selfie), blur detection (Laplacian variance threshold), brightness (not too dark/bright), glare detection, face detection (for INE front and selfie), and document edge detection (for INE).
5. **AC-005**: Files are stored in S3 with server-side encryption (AES-256 via AWS KMS). The S3 key follows the pattern: `kyc/{user_id}/{document_type}/{uuid}.{ext}`. The KMS key ID is stored in the document metadata for decryption.
6. **AC-006**: GET `/api/v1/kyc/documents` returns the user's uploaded documents with a `completeness` object indicating which document types have been uploaded and which are missing. `all_complete` is `true` only when all 4 document types are uploaded.
7. **AC-007**: POST `/api/v1/kyc/documents/{document_id}/replace` allows re-uploading a specific document. The old file is not deleted (retained for audit) but marked as `superseded`. The new file becomes the active version. The `version` field increments.
8. **AC-008**: DELETE `/api/v1/kyc/documents/{document_id}` soft-deletes a document. If the KYC is currently `in_review`, deletion returns 409 with `{ "error": "cannot_delete_during_review" }`. Deleted documents are retained in S3 for the compliance retention period (12 months).
9. **AC-009**: GET `/api/v1/kyc/documents/{document_id}/preview` returns a temporary signed S3 URL (expires in 15 minutes) for viewing the document. The `size` parameter controls the resolution: thumbnail (150x150), medium (600x600), original. Thumbnails and medium sizes are generated on first request and cached.
10. **AC-010**: POST `/api/v1/kyc/documents/validate` performs quality validation without storing the file. This enables the frontend to pre-validate before the final upload, providing immediate feedback to the user about image quality issues.
11. **AC-011**: Every document upload is logged in an audit table with: user_id, document_type, upload_ip, user_agent, timestamp, quality_score, and action (upload/replace/delete). The audit log is append-only.
12. **AC-012**: The upload endpoint enforces that a user can only have one active document per document type. Uploading the same type again triggers the replace flow automatically (old version archived, new version active).
13. **AC-013**: All endpoints require JWT authentication. A user can only access their own documents. Admin users (SVC-ADM) can access any user's documents, and admin access is logged separately in the audit trail.

#### Definition of Done
- All upload/download/delete/replace endpoints implemented
- S3 encrypted storage with KMS integration
- Image quality validation pipeline (resolution, blur, brightness, face, edges)
- Completeness tracking across 4 document types
- Audit logging for all document operations
- Signed URL generation for secure preview
- Unit tests for quality validation logic
- Integration tests for upload flow with mock S3
- Load test: 50 concurrent uploads handled correctly
- Security review: encryption, access controls, audit logging

#### Technical Notes
- Use `boto3` with `S3Client` for encrypted uploads. Use `ServerSideEncryption='aws:kms'` parameter.
- Image quality checks use OpenCV (`cv2`): `cv2.Laplacian(img, cv2.CV_64F).var()` for blur, `cv2.CascadeClassifier` for face detection, `cv2.Canny` for edge detection.
- Consider using `Pillow` (PIL) for image resizing and thumbnail generation.
- For large files, support chunked upload via `Content-Range` header or pre-signed S3 multipart upload URLs.
- Store the original file name but generate a UUID-based S3 key to avoid path injection.

#### Dependencies
- AWS S3: Document storage
- AWS KMS: Encryption key management
- OpenCV (cv2): Image quality validation
- Pillow: Image resizing

---

### [MKT-BE-015][SVC-KYC-APP] Servicio de Verificacion de Identidad

**Description**:
Build the core identity verification service within SVC-KYC's application layer. This service orchestrates the verification pipeline: (1) OCR extraction from INE (name, CURP, address, expiration date), (2) face matching between selfie and INE photo, (3) CURP validation against RENAPO government database, (4) PLD/FT (anti-money laundering / counter-terrorism financing) blacklist screening, and (5) risk score computation. The service produces a comprehensive verification result with per-check pass/fail status and an overall risk score.

**Microservice**: SVC-KYC (port 5014)
**Layer**: APP (application services) + DOM (verification domain) + INF (OCR adapter, face matching adapter, RENAPO adapter, PLD adapter)

#### Technical Context

**Verification Pipeline**:

```
[Documents Uploaded] --> [OCR Extraction] --> [Data Validation] --> [Face Matching]
                              |                     |                     |
                              v                     v                     v
                        INE Data:              CURP Validation       Selfie vs INE
                        - Full Name            via RENAPO API        confidence > 0.85
                        - CURP
                        - Address
                        - Birth Date
                        - Expiry Date
                        - Voter Key
                              |
                              v
                       [PLD/FT Screening] --> [Risk Score Calculation] --> [Decision]
                              |                      |
                              v                      v
                        Blacklist check         Score 0-100:
                        PEP check               - OCR quality: 20%
                        Sanctions check         - Face match: 30%
                                                - CURP valid: 20%
                                                - PLD clear: 20%
                                                - Document quality: 10%
```

**Data Models**:

```python
# DOM Layer - domain/models/verification.py
class VerificationResult:
    id: UUID
    user_id: UUID
    verification_date: datetime
    overall_status: str  # approved, rejected, manual_review
    risk_score: int  # 0-100 (higher = riskier)
    risk_level: str  # low (0-30), medium (31-60), high (61-100)
    checks: List[VerificationCheck]
    ocr_data: OCRExtractionResult
    face_match_result: FaceMatchResult
    curp_validation: CURPValidationResult
    pld_screening: PLDScreeningResult
    decision_reason: str
    manual_review_required: bool
    reviewer_id: Optional[UUID]
    reviewed_at: Optional[datetime]
    processing_time_ms: int

class VerificationCheck:
    check_type: str  # ocr, face_match, curp, pld, document_quality
    status: str  # passed, failed, warning, error
    confidence: float  # 0.0 - 1.0
    details: dict
    error_message: Optional[str]
    executed_at: datetime

class OCRExtractionResult:
    full_name: str
    first_name: str
    last_name_paternal: str
    last_name_maternal: str
    curp: str
    voter_key: str
    address_street: str
    address_colony: str
    address_municipality: str
    address_state: str
    address_zip: str
    birth_date: date
    gender: str
    expiry_date: date
    ine_section: str
    ine_issue_year: int
    extraction_confidence: float  # 0.0 - 1.0
    fields_extracted: int
    fields_total: int

class FaceMatchResult:
    match_confidence: float  # 0.0 - 1.0
    match_threshold: float  # 0.85
    is_match: bool
    liveness_score: float  # 0.0 - 1.0 (anti-spoofing)
    liveness_passed: bool
    selfie_quality: int  # 0-100
    ine_photo_quality: int  # 0-100

class CURPValidationResult:
    curp: str
    is_valid: bool
    name_matches: bool
    birth_date_matches: bool
    gender_matches: bool
    state_matches: bool
    renapo_response_code: str
    renapo_response_message: str

class PLDScreeningResult:
    screened_name: str
    screened_curp: str
    is_clear: bool
    pep_match: bool  # Politically Exposed Person
    sanctions_match: bool
    blacklist_match: bool
    matches_found: List[PLDMatch]
    screening_provider: str
    screening_date: datetime

class PLDMatch:
    list_name: str
    match_name: str
    match_score: float
    match_type: str  # exact, fuzzy, alias
    list_source: str
    list_date: date
```

**Service Interface**:

```python
# APP Layer - application/services/verification_service.py
class VerificationService:
    async def start_verification(self, user_id: UUID) -> VerificationResult:
        """Orchestrates the full verification pipeline"""
        ...

    async def run_ocr(self, ine_front_id: UUID, ine_back_id: UUID) -> OCRExtractionResult:
        """Extract data from INE images"""
        ...

    async def run_face_match(self, selfie_id: UUID, ine_front_id: UUID) -> FaceMatchResult:
        """Compare selfie with INE photo"""
        ...

    async def validate_curp(self, curp: str, ocr_data: OCRExtractionResult) -> CURPValidationResult:
        """Validate CURP against RENAPO"""
        ...

    async def screen_pld(self, name: str, curp: str) -> PLDScreeningResult:
        """Screen against PLD/FT blacklists"""
        ...

    async def calculate_risk_score(self, checks: List[VerificationCheck]) -> int:
        """Compute weighted risk score"""
        ...
```

#### Acceptance Criteria

1. **AC-001**: `start_verification(user_id)` orchestrates the full pipeline: retrieves the user's uploaded documents, runs OCR on INE front/back, performs face matching between selfie and INE, validates CURP against RENAPO, screens PLD/FT blacklists, computes risk score, and returns a comprehensive `VerificationResult`. The entire pipeline runs asynchronously.
2. **AC-002**: OCR extraction from the INE front image captures: full name (first, paternal, maternal), CURP (18 characters), voter key, address, birth date, gender, and expiry date. From the INE back: section number, issue year. Each field has an extraction confidence score. Overall extraction confidence must be > 0.7 to proceed.
3. **AC-003**: The OCR validates that the INE has not expired by comparing the `expiry_date` with the current date. Expired INE results in an automatic rejection with reason "ine_expired".
4. **AC-004**: Face matching compares the selfie with the INE front photo. The match confidence must be >= 0.85 (configurable) for a pass. The system also performs liveness detection on the selfie to prevent photo-of-photo spoofing. Liveness score must be >= 0.75 for a pass.
5. **AC-005**: CURP validation calls the RENAPO API with the extracted CURP and cross-references the returned data (name, birth date, gender, state of birth) against the OCR-extracted data. All fields must match. Name matching uses normalized comparison (remove accents, uppercase, trim spaces).
6. **AC-006**: PLD/FT screening checks the user's name and CURP against: (a) Mexican government PLD blacklist, (b) international sanctions lists (OFAC, EU, UN), (c) PEP (Politically Exposed Persons) lists. Fuzzy name matching with a threshold of 0.85 is used to catch name variations.
7. **AC-007**: The risk score is computed as a weighted sum: OCR quality (20%), face match confidence (30%), CURP validation (20%), PLD clearance (20%), document quality (10%). Score 0-30 = low risk (auto-approve), 31-60 = medium risk (auto-approve with flag), 61-100 = high risk (manual review required).
8. **AC-008**: Auto-approval: if risk score is 0-60 and all checks passed, the verification is automatically approved. If risk score is 61-100 or any critical check failed (face match, PLD), the verification is flagged for manual review by an admin.
9. **AC-009**: The verification pipeline handles partial failures gracefully. If RENAPO is unavailable, the CURP check is marked as `error` with a note, the risk score is recalculated without the CURP weight (redistributed), and the verification can still proceed if other checks pass. A re-check is scheduled for when RENAPO recovers.
10. **AC-010**: All verification data (OCR results, face match scores, CURP responses, PLD screenings) is stored in PostgreSQL with column-level encryption for PII fields (CURP, name, address). The encryption key is managed via AWS KMS.
11. **AC-011**: The verification pipeline publishes events to Redis pub/sub at each stage: `verification.started`, `verification.ocr_complete`, `verification.face_match_complete`, `verification.curp_complete`, `verification.pld_complete`, `verification.completed`. SVC-NTF subscribes for user notifications.
12. **AC-012**: Pipeline processing time is logged. Target: OCR < 5 seconds, face match < 3 seconds, CURP validation < 5 seconds, PLD screening < 5 seconds, total pipeline < 30 seconds. If any step exceeds its timeout, it is retried once before being marked as `error`.
13. **AC-013**: The service maintains a verification history per user. Re-verifications (after rejection or expiry) create a new `VerificationResult` linked to the same user. The history is queryable for compliance auditing.
14. **AC-014**: PLD screening results are cached for 24 hours per name+CURP combination. Repeated verifications within 24 hours use the cached screening result to reduce external API costs and latency.

#### Definition of Done
- Full verification pipeline implemented and orchestrated
- OCR extraction working for Mexican INE (front and back)
- Face matching with liveness detection integrated
- CURP validation via RENAPO API integrated
- PLD/FT screening integrated with at least one provider
- Risk score calculation with weighted formula
- Auto-approve / manual review routing logic
- Column-level encryption for PII data
- Events published at each pipeline stage
- Unit tests for risk score calculation, OCR validation, name matching
- Integration tests for full pipeline with mocked providers
- Security review: encryption, PII handling, audit trail

#### Technical Notes
- OCR can use Tesseract (open source) or a cloud service (AWS Textract, Google Vision). Use the adapter pattern in INF layer for provider flexibility.
- Face matching can use AWS Rekognition, Azure Face API, or an open-source model (dlib, face_recognition). Again, adapter pattern.
- RENAPO CURP validation API may have rate limits and maintenance windows. Implement caching and retry logic.
- Name normalization for comparison: `unicodedata.normalize('NFD', name).encode('ascii', 'ignore').decode('ascii').upper().strip()`
- PLD screening providers: Dow Jones Risk & Compliance, Refinitiv World-Check, or LexisNexis. Use adapter pattern.

#### Dependencies
- Document upload API (MKT-BE-014): Provides uploaded documents
- OCR Provider: AWS Textract / Tesseract / Google Vision
- Face Matching Provider: AWS Rekognition / Azure Face
- RENAPO API: CURP validation
- PLD/FT Provider: Dow Jones / Refinitiv / LexisNexis
- AWS KMS: PII encryption
- Redis 7: Event publishing, screening cache

---

### [MKT-BE-016][SVC-KYC-API] API de Estado y Gestion KYC

**Description**:
Build a REST API within SVC-KYC (port 5014) for managing KYC verification status, handling rejections and re-submissions, enforcing 6-month expiry, and providing admin override capabilities. The API serves both the user-facing status checks and the admin review workflow. Status transitions follow the defined KYC flow: not_started -> documents_pending -> in_review -> approved/rejected/expired.

**Microservice**: SVC-KYC (port 5014)
**Layer**: API (routes) + APP (status management) + DOM (KYC status domain)

#### Technical Context

**Endpoints**:

```
GET    /api/v1/kyc/status
       Response: 200 KYCStatusResponse

GET    /api/v1/kyc/status/{user_id}
       (Admin only)
       Response: 200 KYCStatusResponse | 404 UserNotFound

POST   /api/v1/kyc/submit
       Response: 200 { "status": "in_review", "estimated_review_time": "2-5 minutes" }
       | 400 { "error": "documents_incomplete", "missing": ["selfie"] }
       | 409 { "error": "already_in_review" }

GET    /api/v1/kyc/rejection-details
       Response: 200 RejectionDetailsResponse | 404 NoRejection

POST   /api/v1/kyc/resubmit
       Response: 200 { "status": "documents_pending", "resubmission_count": 2, "max_resubmissions": 3 }
       | 400 { "error": "not_rejected" } | 429 { "error": "max_resubmissions_reached" }

POST   /api/v1/kyc/admin/review/{user_id}
       (Admin only)
       Body: { "decision": "approve"|"reject", "reason": "...", "notes": "..." }
       Response: 200 KYCStatusResponse

POST   /api/v1/kyc/admin/override/{user_id}
       (Admin only, super admin)
       Body: { "action": "force_approve"|"force_expire"|"reset", "reason": "..." }
       Response: 200 KYCStatusResponse

GET    /api/v1/kyc/admin/pending-reviews
       (Admin only)
       Query params: ?page=1&per_page=20&risk_level=high&sort_by=submitted_at
       Response: 200 PaginatedPendingReviews

GET    /api/v1/kyc/history
       Response: 200 KYCHistoryResponse (all verification attempts)

GET    /api/v1/kyc/expiry-info
       Response: 200 { "approved_at": "...", "expires_at": "...", "days_remaining": 145, "renewal_eligible": true }
```

**Data Models**:

```python
# DOM Layer - domain/models/kyc_status.py
class KYCStatus:
    id: UUID
    user_id: UUID
    status: KYCStatusEnum
    documents_complete: bool
    verification_result_id: Optional[UUID]
    approved_at: Optional[datetime]
    expires_at: Optional[datetime]
    rejected_at: Optional[datetime]
    rejection_reasons: List[RejectionReason]
    resubmission_count: int
    max_resubmissions: int  # default 3
    admin_override: bool
    admin_override_by: Optional[UUID]
    admin_override_reason: Optional[str]
    created_at: datetime
    updated_at: datetime

class KYCStatusEnum(Enum):
    NOT_STARTED = "not_started"
    DOCUMENTS_PENDING = "documents_pending"
    IN_REVIEW = "in_review"
    APPROVED = "approved"
    REJECTED = "rejected"
    EXPIRED = "expired"

class RejectionReason:
    code: str  # e.g., "ine_blurry", "face_mismatch", "curp_invalid", "ine_expired", "pld_match"
    document_type: Optional[str]
    description: str
    fix_instruction: str  # Human-readable instruction for the user
    severity: str  # critical, fixable

class KYCHistory:
    user_id: UUID
    attempts: List[KYCAttempt]
    total_attempts: int
    current_status: KYCStatusEnum

class KYCAttempt:
    attempt_number: int
    started_at: datetime
    completed_at: Optional[datetime]
    result: str  # approved, rejected, expired
    risk_score: Optional[int]
    rejection_reasons: List[RejectionReason]
    documents_submitted: List[str]  # document types
```

**Rejection Reason Codes**:

```python
REJECTION_REASONS = {
    "ine_blurry": {
        "description": "INE image is too blurry to read",
        "fix_instruction": "Please retake your INE photo in good lighting. Hold the camera steady and ensure the text is sharp and readable.",
        "document_type": "ine_front",
        "severity": "fixable"
    },
    "ine_expired": {
        "description": "Your INE credential has expired",
        "fix_instruction": "Your INE is past its expiration date. Please upload a current, valid INE.",
        "document_type": "ine_front",
        "severity": "critical"
    },
    "face_mismatch": {
        "description": "Selfie does not match INE photo",
        "fix_instruction": "Please take a new selfie in good lighting, looking directly at the camera. Remove hats, glasses, or anything covering your face.",
        "document_type": "selfie",
        "severity": "fixable"
    },
    "curp_invalid": {
        "description": "CURP could not be validated with RENAPO",
        "fix_instruction": "The CURP extracted from your INE could not be verified. Please ensure your INE is valid and the CURP is clearly visible.",
        "document_type": "ine_front",
        "severity": "critical"
    },
    "proof_address_outdated": {
        "description": "Proof of address is older than 3 months",
        "fix_instruction": "Please upload a proof of address dated within the last 3 months (utility bill, bank statement, or government document).",
        "document_type": "proof_of_address",
        "severity": "fixable"
    },
    "selfie_liveness_failed": {
        "description": "Liveness check failed on selfie",
        "fix_instruction": "Please take a live selfie (not a photo of a photo). Look directly at the camera in good lighting.",
        "document_type": "selfie",
        "severity": "fixable"
    },
    "pld_match": {
        "description": "Identity flagged in compliance screening",
        "fix_instruction": "Your identity requires additional review. Our team will contact you within 24 hours.",
        "document_type": null,
        "severity": "critical"
    }
}
```

#### Acceptance Criteria

1. **AC-001**: GET `/api/v1/kyc/status` returns the authenticated user's current KYC status including: status enum, document completeness, approval/rejection dates, days until expiry (if approved), resubmission count, and whether manual review is pending.
2. **AC-002**: POST `/api/v1/kyc/submit` initiates the verification process. Preconditions: all 4 documents must be uploaded (returns 400 with missing list if not), status must be `documents_pending` (returns 409 if already `in_review`). On success, status transitions to `in_review` and the verification pipeline (MKT-BE-015) is triggered asynchronously.
3. **AC-003**: When verification completes (approved or rejected), the status is updated automatically. If approved, `approved_at` and `expires_at` (approved_at + 6 months) are set. If rejected, `rejected_at` and `rejection_reasons` are set with specific, actionable rejection codes.
4. **AC-004**: GET `/api/v1/kyc/rejection-details` returns the list of rejection reasons for the most recent rejected verification. Each reason includes: `code`, `description`, `fix_instruction` (user-friendly text), associated `document_type`, and `severity` (critical = cannot fix by re-upload, fixable = can fix by re-uploading).
5. **AC-005**: POST `/api/v1/kyc/resubmit` resets the status from `rejected` to `documents_pending`, allowing the user to replace rejected documents and resubmit. Maximum 3 resubmissions allowed. Exceeding returns 429 with `{ "error": "max_resubmissions_reached", "contact": "support@marketplace.com" }`.
6. **AC-006**: KYC approval expires after 6 months. WRK-NTF checks daily for approaching expirations and sends reminders at 30 days, 7 days, and 1 day before expiry. On the expiry date, status transitions to `expired`. The user must re-verify to continue purchases.
7. **AC-007**: POST `/api/v1/kyc/admin/review/{user_id}` (admin only) allows an admin to approve or reject a verification that requires manual review. The admin provides a `decision` (approve/reject), `reason`, and optional `notes`. The action is logged in the audit trail with the admin's user ID.
8. **AC-008**: POST `/api/v1/kyc/admin/override/{user_id}` (super admin only) allows force-approving, force-expiring, or resetting a user's KYC status. This is for exceptional cases (e.g., provider errors, known customers). The override is flagged in the record and requires a reason. All overrides are logged.
9. **AC-009**: GET `/api/v1/kyc/admin/pending-reviews` (admin only) returns a paginated list of verifications requiring manual review, sorted by submission date (oldest first by default). Filterable by `risk_level` (high, medium). Each entry includes: user name, submission date, risk score, risk level, and verification check summaries.
10. **AC-010**: GET `/api/v1/kyc/history` returns the authenticated user's complete KYC history: all verification attempts with their dates, results, risk scores, and rejection reasons. This provides transparency for the user and supports compliance requirements.
11. **AC-011**: GET `/api/v1/kyc/expiry-info` returns expiry details for approved users: approval date, expiry date, days remaining, and whether the user is eligible for early renewal (available 30 days before expiry).
12. **AC-012**: All status transitions trigger notifications via SVC-NTF: `in_review` -> "Your identity is being verified", `approved` -> "Your identity has been verified!", `rejected` -> "Identity verification needs attention" (with fix instructions), `expired` -> "Your identity verification has expired".
13. **AC-013**: The KYC status is queryable by other services (SVC-PUR) via an internal endpoint `GET /internal/v1/kyc/status/{user_id}` that returns a simplified response: `{ "status": "approved", "valid_until": "...", "is_valid": true }`. This endpoint uses service-to-service authentication (API key), not JWT.

#### Definition of Done
- All user-facing and admin endpoints implemented
- Status transitions following the defined KYC flow
- Rejection reasons with actionable fix instructions
- 6-month expiry enforcement via WRK-NTF
- Admin review and override workflows
- Resubmission flow with 3-attempt limit
- Internal service endpoint for SVC-PUR integration
- Notifications triggered on all status changes
- Unit tests for status transitions, expiry calculation, resubmission limits
- Integration tests for admin workflows
- API documented in OpenAPI format

#### Technical Notes
- KYC status should be a singleton per user (one active KYC record at a time). Historical records are linked via `user_id`.
- The internal endpoint (`/internal/v1/`) should validate an `X-Service-Key` header, not JWT. This avoids coupling user auth to service-to-service calls.
- Expiry calculation: `expires_at = approved_at + timedelta(days=183)` (approximately 6 months).
- Admin override should require a second factor (confirmation code) in a future iteration.
- Consider using PostgreSQL `LISTEN/NOTIFY` for real-time status updates instead of polling.

#### Dependencies
- Verification Service (MKT-BE-015): Pipeline execution
- SVC-NTF (port 5017): Status change notifications
- SVC-PUR (port 5013): Internal status check consumer
- SVC-ADM (port 5020): Admin authentication and authorization
- WRK-NTF: Expiry checking and notification worker

---

### [MKT-FE-014][FE-FEAT-PRF] Flujo de Upload de Documentos KYC

**Description**:
Build an Angular 18 standalone component that guides the user through uploading their KYC documents. The flow provides: camera capture with overlay guides (frame for INE, oval for selfie), photo preview with quality assessment before final upload, a selfie step with liveness detection prompts, per-document progress bars, and clear step-by-step instructions. The component handles poor connectivity with retry logic and provides immediate feedback on image quality issues.

**Frontend Module**: FE-FEAT-PRF (Profile Feature)
**Framework**: Angular 18 (standalone components, signals)
**Styling**: Tailwind CSS v4

#### Technical Context

**Component Structure**:

```
src/app/features/profile/
  components/
    kyc-upload/
      kyc-upload-page.component.ts             # Page with step navigation
      kyc-upload-page.component.html
      document-stepper/
        document-stepper.component.ts           # Step indicator (1-4)
      camera-capture/
        camera-capture.component.ts             # Camera with overlay guides
        camera-capture.component.html
        ine-overlay.component.ts                # ID card frame overlay
        selfie-overlay.component.ts             # Oval face guide overlay
      document-preview/
        document-preview.component.ts           # Preview with quality check
        quality-indicator.component.ts           # Quality score visualization
      file-upload/
        file-upload.component.ts                # Drag-drop + file select fallback
        upload-progress.component.ts             # Progress bar per document
      step-instructions/
        step-instructions.component.ts           # Instructions panel per step
  services/
    kyc-upload.service.ts                       # Upload HTTP calls
    camera.service.ts                           # Camera access management
    image-quality.service.ts                    # Client-side quality checks
  store/
    kyc-upload.store.ts
```

**Signal Store**:

```typescript
// kyc-upload.store.ts
export class KYCUploadStore {
  currentStep = signal<number>(1);  // 1=INE Front, 2=INE Back, 3=Selfie, 4=Proof of Address
  documents = signal<Map<DocumentType, UploadedDocument>>(new Map());
  capturedImage = signal<CapturedImage | null>(null);
  qualityResult = signal<QualityResult | null>(null);
  uploading = signal<boolean>(false);
  uploadProgress = signal<number>(0);
  error = signal<string | null>(null);

  // Computed
  stepConfig = computed(() => STEP_CONFIGS[this.currentStep()]);
  allDocumentsUploaded = computed(() => this.documents().size === 4);
  canSubmit = computed(() =>
    this.allDocumentsUploaded() && !this.uploading()
  );
  documentStatus = computed(() => ({
    ine_front: this.documents().has('ine_front'),
    ine_back: this.documents().has('ine_back'),
    selfie: this.documents().has('selfie'),
    proof_of_address: this.documents().has('proof_of_address'),
  }));
}
```

**Step Configuration**:

```typescript
const STEP_CONFIGS: Record<number, StepConfig> = {
  1: {
    documentType: 'ine_front',
    title: 'INE - Front Side',
    instructions: [
      'Place your INE on a flat, well-lit surface',
      'Align the card within the frame',
      'Make sure all text is clearly visible',
      'Avoid shadows and reflections'
    ],
    captureMode: 'camera',
    overlayType: 'id-card',
    acceptedFormats: ['image/jpeg', 'image/png'],
    maxSizeBytes: 10485760
  },
  2: {
    documentType: 'ine_back',
    title: 'INE - Back Side',
    instructions: [
      'Flip your INE to the back side',
      'Align the card within the frame',
      'Ensure the barcode is visible'
    ],
    captureMode: 'camera',
    overlayType: 'id-card',
    acceptedFormats: ['image/jpeg', 'image/png'],
    maxSizeBytes: 10485760
  },
  3: {
    documentType: 'selfie',
    title: 'Selfie - Face Verification',
    instructions: [
      'Position your face within the oval guide',
      'Look directly at the camera',
      'Remove hats, sunglasses, or face coverings',
      'Ensure even lighting on your face',
      'Follow the on-screen prompts for liveness check'
    ],
    captureMode: 'selfie',
    overlayType: 'oval-face',
    acceptedFormats: ['image/jpeg', 'image/png'],
    maxSizeBytes: 10485760
  },
  4: {
    documentType: 'proof_of_address',
    title: 'Proof of Address',
    instructions: [
      'Upload a recent utility bill, bank statement, or government document',
      'Document must be dated within the last 3 months',
      'Your name and address must be clearly visible',
      'You can upload a photo or PDF'
    ],
    captureMode: 'file',  // file upload, not camera
    overlayType: null,
    acceptedFormats: ['image/jpeg', 'image/png', 'application/pdf'],
    maxSizeBytes: 10485760
  }
};
```

#### Acceptance Criteria

1. **AC-001**: The upload page displays a 4-step indicator showing: (1) INE Front, (2) INE Back, (3) Selfie, (4) Proof of Address. Each step shows its status (pending/active/completed) with appropriate icons. Completed steps have a green checkmark.
2. **AC-002**: Steps 1 and 2 (INE) open the device camera with a semi-transparent overlay showing a card-shaped frame. The user aligns their INE within the frame. A "Capture" button takes the photo. On desktop, a file upload fallback is provided.
3. **AC-003**: Step 3 (Selfie) opens the front-facing camera with an oval overlay guiding face positioning. The component displays liveness detection prompts: "Blink your eyes", "Turn your head slowly to the left", "Smile". Each prompt must be completed to prevent photo-of-photo spoofing.
4. **AC-004**: After each capture, a preview screen displays the image with quality assessment results. The quality check runs client-side first (basic checks: resolution, brightness) and then server-side via the `/validate` endpoint. Results show: "Image quality: Good/Fair/Poor" with specific issues listed (e.g., "Image is slightly blurry").
5. **AC-005**: The quality indicator displays a score (0-100) with color coding: green (80-100, "Good"), yellow (50-79, "Fair - consider retaking"), red (0-49, "Poor - please retake"). For "Fair" and "Poor", specific fix suggestions are shown with a "Retake" button.
6. **AC-006**: The preview screen has three buttons: "Retake" (return to camera), "Upload" (proceed with this image), and "Choose from Gallery" (alternative file selection). "Upload" is disabled if quality score is below 30 (too poor to proceed).
7. **AC-007**: During upload, a progress bar shows the upload percentage (0-100%). For large files or slow connections, the progress updates smoothly. If the upload fails, a retry button is shown with the error message. Up to 3 automatic retries with exponential backoff (1s, 2s, 4s) are attempted before showing the manual retry button.
8. **AC-008**: Step 4 (Proof of Address) provides a drag-and-drop zone and a file selection button. It accepts JPEG, PNG, and PDF files. For PDF files, a thumbnail preview of the first page is generated. The drag-and-drop zone shows visual feedback (highlighted border) when a file is dragged over it.
9. **AC-009**: Each step displays clear, numbered instructions in a panel beside (desktop) or above (mobile) the capture area. Instructions are specific to the document type and include visual examples (illustration of correctly positioned INE, properly lit selfie, acceptable proof of address).
10. **AC-010**: The user can navigate between steps to re-upload any document, even after it has been uploaded. Returning to a completed step shows the current uploaded document with an option to "Replace". Replacing a document calls the `/replace` endpoint.
11. **AC-011**: After all 4 documents are uploaded, a summary screen shows all documents with their preview thumbnails and quality scores. A "Submit for Verification" button triggers the `/submit` endpoint. The button is disabled until all 4 documents are uploaded.
12. **AC-012**: Camera permissions are requested with a clear explanation dialog before accessing the camera. If the user denies camera access, a fallback file upload mode is provided with an explanation of how to enable camera access in browser settings.
13. **AC-013**: The upload flow works offline-tolerant: if connectivity is lost during upload, the captured image is retained in memory and the upload is retried when connectivity is restored. A "No internet connection" banner is shown.
14. **AC-014**: The component is fully responsive. On mobile, the camera fills the viewport with the overlay. On desktop, the camera preview is centered with instructions beside it. All touch and click interactions work on both platforms.

#### Definition of Done
- All 4 document upload steps implemented
- Camera capture with overlay guides (ID card frame, oval face guide)
- Liveness detection prompts in selfie step
- Client-side and server-side quality validation
- Progress bar with retry logic
- Drag-and-drop for proof of address
- Summary screen with submit action
- Camera permission handling with fallback
- Unit tests for quality validation, step navigation, upload logic
- Manual QA on iOS Safari, Android Chrome, desktop Chrome/Firefox
- Accessibility: screen reader announces step changes, keyboard navigation for all controls

#### Technical Notes
- Camera access uses `navigator.mediaDevices.getUserMedia()`. Wrap in a service that handles permission requests and device enumeration.
- The INE overlay is an SVG with a transparent cut-out in the shape of a credit card (85.6mm x 53.98mm aspect ratio = 1.586:1).
- The selfie oval overlay uses CSS `clip-path: ellipse()` or an SVG mask.
- Client-side quality checks: use `OffscreenCanvas` or `<canvas>` to analyze the captured image. Check resolution via `naturalWidth`/`naturalHeight`. Approximate blur detection by computing the variance of pixel intensity gradients.
- Liveness detection on the frontend is basic (prompt-based). The real liveness check happens server-side in the verification service.
- Use Angular's `@defer` to lazy-load the camera module since it requires significant JavaScript for canvas operations.

#### Dependencies
- SVC-KYC API (MKT-BE-014): Upload, validate, replace endpoints
- Browser APIs: `MediaDevices`, `Canvas`, `File API`
- Angular CDK: a11y for screen reader support

---

### [MKT-FE-015][FE-FEAT-PRF] Panel de Estado KYC

**Description**:
Build an Angular 18 standalone component that displays the user's current KYC verification status as a comprehensive dashboard panel. The panel shows a document checklist with traffic-light status per document, rejection reasons with specific fix instructions, re-upload capability per document, and verification history. It integrates with the KYC upload flow for document re-submission.

**Frontend Module**: FE-FEAT-PRF (Profile Feature)
**Framework**: Angular 18 (standalone components, signals)
**Styling**: Tailwind CSS v4

#### Technical Context

**Component Structure**:

```
src/app/features/profile/
  components/
    kyc-status/
      kyc-status-panel.component.ts             # Main panel component
      kyc-status-panel.component.html
      kyc-status-badge.component.ts             # Compact badge for use in other pages
      document-checklist/
        document-checklist.component.ts          # 4-document checklist
        document-checklist-item.component.ts     # Single document with status
      rejection-details/
        rejection-details.component.ts           # Rejection reasons panel
        rejection-fix-card.component.ts          # Per-reason fix instruction card
      kyc-expiry/
        kyc-expiry-indicator.component.ts        # Expiry countdown + renewal
      kyc-history/
        kyc-history-timeline.component.ts        # Past verification attempts
  services/
    kyc-status.service.ts
  store/
    kyc-status.store.ts
```

**Signal Store**:

```typescript
// kyc-status.store.ts
@Injectable({ providedIn: 'root' })
export class KYCStatusStore {
  status = signal<KYCStatus | null>(null);
  documents = signal<KYCDocument[]>([]);
  rejectionDetails = signal<RejectionReason[]>([]);
  expiryInfo = signal<ExpiryInfo | null>(null);
  history = signal<KYCAttempt[]>([]);
  loading = signal<boolean>(false);

  // Computed
  statusColor = computed(() => {
    switch (this.status()?.status) {
      case 'approved': return 'green';
      case 'in_review': return 'blue';
      case 'documents_pending': return 'yellow';
      case 'rejected': return 'red';
      case 'expired': return 'gray';
      default: return 'gray';
    }
  });
  isVerified = computed(() => this.status()?.status === 'approved');
  needsAction = computed(() =>
    ['documents_pending', 'rejected', 'expired'].includes(this.status()?.status ?? '')
  );
  daysUntilExpiry = computed(() => this.expiryInfo()?.days_remaining ?? null);
  documentCompleteness = computed(() => {
    const docs = this.documents();
    return {
      ine_front: docs.some(d => d.document_type === 'ine_front' && d.status !== 'rejected'),
      ine_back: docs.some(d => d.document_type === 'ine_back' && d.status !== 'rejected'),
      selfie: docs.some(d => d.document_type === 'selfie' && d.status !== 'rejected'),
      proof_of_address: docs.some(d => d.document_type === 'proof_of_address' && d.status !== 'rejected'),
    };
  });
}
```

#### Acceptance Criteria

1. **AC-001**: The KYC status panel displays the current status prominently at the top with a colored badge: green "Verified" for approved, blue "In Review" for in_review, yellow "Action Required" for documents_pending, red "Rejected" for rejected, gray "Expired" for expired, gray "Not Started" for not_started.
2. **AC-002**: Below the status badge, a brief explanation text is shown based on the status. For approved: "Your identity is verified. Valid until [date]." For rejected: "Please fix the issues below and resubmit." For in_review: "We are reviewing your documents. This usually takes 2-5 minutes." For expired: "Your verification has expired. Please re-verify to continue purchases."
3. **AC-003**: The document checklist shows all 4 document types as a vertical list. Each item displays: document type name, traffic light indicator (green=uploaded and valid, yellow=uploaded but has issues, red=rejected, gray=not uploaded), upload date, and a thumbnail preview (or placeholder icon for gray/not uploaded).
4. **AC-004**: Each document item in the checklist has a "Re-upload" button (visible for rejected or uploaded documents) that navigates to the KYC upload flow at the specific step for that document type. After re-upload, the user returns to this panel.
5. **AC-005**: When status is `rejected`, a rejection details section is displayed prominently below the checklist. Each rejection reason is shown as a card with: reason description (human-readable), the affected document type (with icon), severity (fixable or critical), and specific fix instructions in a highlighted callout box.
6. **AC-006**: Fix instruction cards for "fixable" rejections include a direct "Fix Now" button that navigates to the appropriate upload step. "Critical" rejections (e.g., expired INE, PLD match) show a different visual treatment (red border) and instruct the user to contact support.
7. **AC-007**: When status is `approved`, an expiry indicator is displayed showing: approval date, expiry date, days remaining, and a visual progress bar (full green to empty red as expiry approaches). When 30 days or fewer remain, a "Renew Now" button appears to start the re-verification flow.
8. **AC-008**: A `kyc-status-badge` compact component can be embedded in other pages (e.g., profile header, purchase wizard). It shows only the status icon and text (e.g., green checkmark + "Verified"). Clicking it navigates to the full KYC status panel.
9. **AC-009**: The KYC history section shows a timeline of all past verification attempts. Each entry displays: attempt number, date, result (approved/rejected/expired), risk score (if available), and rejection reasons (if applicable). The most recent attempt is at the top.
10. **AC-010**: When status is `in_review`, the panel polls the status endpoint every 10 seconds. When the status changes (approved or rejected), the panel updates immediately with an animation, and a toast notification is shown. Polling stops when a terminal status is reached.
11. **AC-011**: The "Submit for Verification" action is available from the status panel when all 4 documents are uploaded and status is `documents_pending`. Clicking it calls the `/submit` endpoint and transitions the UI to the `in_review` state.
12. **AC-012**: The panel displays the resubmission counter when applicable: "Attempt 2 of 3" for rejected status. When max resubmissions are reached (3), the panel shows a message directing the user to contact support, with no re-upload buttons.
13. **AC-013**: The panel is responsive. On mobile, document thumbnails are smaller, rejection cards stack vertically, and the history timeline is simplified. The status badge and action buttons remain prominent at the top.
14. **AC-014**: All status information is accessible. Status colors are paired with text labels (not color-only). Traffic lights in the checklist have `aria-label` descriptions. The panel structure uses proper heading hierarchy for screen readers.

#### Definition of Done
- KYC status panel displaying all states correctly
- Document checklist with traffic light indicators
- Rejection details with fix instructions and action buttons
- Expiry indicator with renewal flow
- Compact badge component for embedding in other pages
- History timeline showing past attempts
- Polling for in_review status updates
- Re-upload navigation to specific document step
- Unit tests for status display logic, polling, completeness calculation
- Visual QA for all 6 status states
- Responsive layout tested on mobile/tablet/desktop
- Accessibility audit passed

#### Technical Notes
- The `KYCStatusStore` is `providedIn: 'root'` so status is available across the application (for the badge component).
- Polling should use `setInterval` wrapped in an `effect()` that starts/stops based on the `in_review` status.
- Document thumbnails use the signed URL from the `/preview?size=thumbnail` endpoint. Cache the URLs in the signal store to avoid repeated API calls.
- Navigation to the upload flow should pass the specific `step` as a query parameter: `/kyc/upload?step=3` (for selfie re-upload).
- The compact badge component should be lightweight and not trigger API calls on its own. It reads from the global `KYCStatusStore` which is loaded on app initialization.

#### Dependencies
- SVC-KYC API (MKT-BE-016): Status, rejection details, submit, expiry endpoints
- SVC-KYC API (MKT-BE-014): Document preview endpoint
- KYC Upload Flow (MKT-FE-014): Navigation target for re-uploads
- Angular CDK: a11y module

---

### [MKT-INT-003][SVC-KYC] Integracion con Proveedor de Verificacion de Identidad

**Description**:
Build the provider integration layer within SVC-KYC (port 5014) using the adapter pattern to support multiple identity verification providers. The integration includes a primary provider and a fallback provider, webhook reception for asynchronous verification results, retry with exponential backoff for transient failures, graceful degradation to manual review when both providers are unavailable, and a complete audit trail of all provider interactions.

**Microservice**: SVC-KYC (port 5014)
**Layer**: INF (provider adapters) + APP (orchestration) + CFG (provider configuration)

#### Technical Context

**Adapter Pattern**:

```python
# INF Layer - infrastructure/adapters/verification_provider.py
from abc import ABC, abstractmethod

class VerificationProviderAdapter(ABC):
    """
    Abstract adapter for identity verification providers.
    Implementations: MatiAdapter, OnyxAdapter, ManualAdapter (fallback)
    """

    @abstractmethod
    async def submit_verification(self, request: VerificationRequest) -> SubmissionResult:
        """Submit documents for verification. Returns a provider reference ID."""
        ...

    @abstractmethod
    async def get_verification_status(self, provider_ref: str) -> ProviderStatus:
        """Poll provider for verification status."""
        ...

    @abstractmethod
    async def handle_webhook(self, payload: dict, signature: str) -> WebhookResult:
        """Process incoming webhook from provider."""
        ...

    @abstractmethod
    async def health_check(self) -> ProviderHealth:
        """Check provider API availability."""
        ...

class MatiAdapter(VerificationProviderAdapter):
    """
    Adapter for Mati (Metamap) - primary provider for Mexican ID verification.
    Supports: INE OCR, face matching, liveness, CURP validation, PLD screening.
    """
    base_url: str = "https://api.getmati.com/v2"
    api_key: str  # from environment
    webhook_secret: str  # for signature validation
    timeout_seconds: int = 30
    max_retries: int = 3

class OnyxAdapter(VerificationProviderAdapter):
    """
    Adapter for fallback provider.
    Supports: Document OCR, face matching, basic identity verification.
    """
    base_url: str  # from environment
    api_key: str  # from environment
    timeout_seconds: int = 30
    max_retries: int = 3

class ManualReviewAdapter(VerificationProviderAdapter):
    """
    Fallback adapter when all automated providers are unavailable.
    Creates a manual review task for admin team.
    """
    pass
```

**Webhook Handler**:

```python
# API Layer - api/routes/webhooks.py
@router.post("/api/v1/kyc/webhooks/{provider}")
async def handle_provider_webhook(provider: str, request: Request):
    """
    Receives async verification results from providers.
    Validates webhook signature, processes result, updates KYC status.
    """
    pass
```

**Provider Configuration**:

```python
# CFG Layer - config/verification_providers.py
VERIFICATION_PROVIDERS = {
    "primary": {
        "adapter": "MatiAdapter",
        "base_url": "https://api.getmati.com/v2",
        "api_key_env": "MATI_API_KEY",
        "webhook_secret_env": "MATI_WEBHOOK_SECRET",
        "timeout": 30,
        "retries": 3,
        "backoff_base": 2,  # exponential backoff: 2^attempt seconds
        "capabilities": ["ocr", "face_match", "liveness", "curp", "pld"]
    },
    "fallback": {
        "adapter": "OnyxAdapter",
        "base_url_env": "ONYX_BASE_URL",
        "api_key_env": "ONYX_API_KEY",
        "webhook_secret_env": "ONYX_WEBHOOK_SECRET",
        "timeout": 30,
        "retries": 3,
        "backoff_base": 2,
        "capabilities": ["ocr", "face_match", "liveness"]
    },
    "manual": {
        "adapter": "ManualReviewAdapter",
        "capabilities": ["all"],
        "sla_hours": 24
    }
}

PROVIDER_SELECTION_STRATEGY = "primary_with_fallback"
# Options: "primary_only", "primary_with_fallback", "round_robin", "cost_optimized"
```

**Request/Response Models**:

```python
# INF Layer - infrastructure/adapters/models.py
class VerificationRequest:
    user_id: UUID
    kyc_id: UUID
    documents: List[DocumentReference]
    checks_requested: List[str]  # ["ocr", "face_match", "liveness", "curp", "pld"]
    callback_url: str  # webhook URL for async results
    priority: str  # normal, high
    metadata: dict

class DocumentReference:
    document_type: str
    s3_key: str
    presigned_url: str  # temporary URL for provider to download the document
    mime_type: str

class SubmissionResult:
    provider_name: str
    provider_ref: str  # provider's reference ID
    status: str  # submitted, queued, error
    estimated_completion_seconds: int
    submission_time_ms: int

class ProviderStatus:
    provider_ref: str
    status: str  # pending, processing, completed, failed
    checks_completed: List[CheckResult]
    overall_result: Optional[str]  # approved, rejected, manual_review
    error_message: Optional[str]

class CheckResult:
    check_type: str
    status: str  # passed, failed, error
    confidence: float
    details: dict
    provider_specific_data: dict

class WebhookResult:
    provider_name: str
    provider_ref: str
    kyc_id: UUID
    event_type: str  # verification_completed, verification_failed, check_completed
    result: ProviderStatus
    received_at: datetime
    signature_valid: bool

class ProviderHealth:
    provider_name: str
    is_available: bool
    response_time_ms: int
    last_successful_call: datetime
    error_rate_percent: float  # last 100 calls
    degraded: bool
```

**Audit Log**:

```python
# INF Layer - infrastructure/audit/provider_audit.py
class ProviderAuditEntry:
    id: UUID
    kyc_id: UUID
    user_id: UUID
    provider_name: str
    action: str  # submit, poll, webhook_received, retry, fallback, manual_escalation
    request_payload: dict  # sanitized (no raw images)
    response_payload: dict
    response_status: int
    response_time_ms: int
    retry_attempt: int
    error_message: Optional[str]
    timestamp: datetime
```

#### Acceptance Criteria

1. **AC-001**: The `VerificationProviderAdapter` abstract class defines the interface that all providers implement: `submit_verification()`, `get_verification_status()`, `handle_webhook()`, and `health_check()`. Concrete implementations exist for at least two providers (primary and fallback) plus the manual review fallback.
2. **AC-002**: `submit_verification()` on the primary adapter (Mati/Metamap) sends the user's documents to the provider via their API. Documents are shared via pre-signed S3 URLs (15-minute expiry). The submission includes the callback webhook URL for asynchronous result delivery. Returns a `SubmissionResult` with the provider's reference ID.
3. **AC-003**: The webhook endpoint `POST /api/v1/kyc/webhooks/{provider}` receives asynchronous results from the verification provider. The handler: (a) validates the webhook signature using HMAC-SHA256 with the provider's webhook secret, (b) parses the payload into a `WebhookResult`, (c) maps provider-specific results to the standardized `VerificationCheck` domain models, (d) updates the KYC status, (e) returns 200 to acknowledge receipt.
4. **AC-004**: Invalid webhook signatures result in a 401 response and a security alert logged to the audit trail. The invalid payload is stored for forensic analysis but does not affect the KYC status.
5. **AC-005**: When the primary provider fails (timeout, 5xx error, or rate limit), the system retries up to 3 times with exponential backoff (2s, 4s, 8s). If all retries fail, the system automatically submits to the fallback provider. The fallback switch is logged in the audit trail with reason.
6. **AC-006**: When both primary and fallback providers are unavailable, the system falls back to the `ManualReviewAdapter` which creates a manual review task visible in the admin pending reviews queue. The user is notified that verification is in progress with a longer estimated time (up to 24 hours).
7. **AC-007**: Provider selection strategy is configurable: `primary_with_fallback` (default), `primary_only` (no fallback), `round_robin` (alternate between providers for load distribution), `cost_optimized` (choose cheapest available provider). The strategy is set via environment variable.
8. **AC-008**: Each provider adapter normalizes the provider-specific response into standardized domain models. For example, Mati's `documentData.fullName` maps to `OCRExtractionResult.full_name`, and Mati's `faceMatch.score` maps to `FaceMatchResult.match_confidence`. This normalization is tested with provider-specific fixture data.
9. **AC-009**: The health check endpoint `GET /api/v1/kyc/providers/health` (admin only) returns the status of all configured providers: availability, average response time, error rate (last 100 calls), last successful call timestamp, and degradation status.
10. **AC-010**: All provider interactions are logged in the audit trail: submissions (without raw image data), responses, webhooks received, retries attempted, fallback switches, and manual escalations. Each entry includes the KYC ID, provider name, action, response time, and timestamp.
11. **AC-011**: Pre-signed S3 URLs generated for the provider have a configurable TTL (default 15 minutes) and are logged in the audit trail. URLs are single-use when possible (depends on provider support). If a URL expires before the provider downloads the document, the submission is retried with a fresh URL.
12. **AC-012**: The adapter handles provider-specific rate limits gracefully. When a 429 (Too Many Requests) response is received, the adapter backs off for the duration specified in the `Retry-After` header and queues the request for later processing. The user is not notified of rate-limit delays unless the total wait exceeds 5 minutes.
13. **AC-013**: Provider configuration (API keys, URLs, timeouts, retry counts) is loaded from environment variables at service startup. Changing a provider's configuration requires only an environment variable change and service restart, no code deployment.
14. **AC-014**: Integration tests use recorded provider responses (VCR-style cassettes via `vcrpy` or `respx`) to simulate: successful verification, rejected verification, webhook delivery, timeout with retry, fallback to secondary provider, and fallback to manual review. Tests run without actual provider API calls.

#### Definition of Done
- Adapter pattern implemented with abstract base class and 3 concrete adapters
- Primary provider (Mati/Metamap) adapter fully integrated
- Fallback provider adapter integrated
- Manual review fallback creating admin tasks
- Webhook endpoint receiving and validating provider callbacks
- Provider response normalization to domain models
- Retry with exponential backoff working
- Automatic fallback on provider failure
- Audit trail logging all provider interactions
- Health check endpoint for monitoring
- Integration tests with recorded responses for all scenarios
- Provider-specific normalization tested with fixture data
- Configuration externalized via environment variables
- Security review: webhook signature validation, pre-signed URL management

#### Technical Notes
- Use `httpx.AsyncClient` with connection pooling for provider API calls.
- Webhook signature validation: `hmac.compare_digest(hmac.new(secret, payload, 'sha256').hexdigest(), received_signature)`.
- VCR-style testing: use `respx` (for `httpx`) or `responses` (for `requests`) to record and replay provider API interactions.
- Pre-signed URLs: use `boto3.client('s3').generate_presigned_url('get_object', ExpiresIn=900)`.
- Consider using Celery for async provider submission to avoid blocking the webhook handler. The submission task publishes a "verification_submitted" event to Redis pub/sub.
- Provider-specific data that does not map to the domain model should be stored in a `raw_provider_response` JSON column for debugging purposes.

#### Dependencies
- Primary Verification Provider API (Mati/Metamap or equivalent)
- Fallback Verification Provider API
- AWS S3: Pre-signed URL generation for document sharing
- Redis 7: Event publishing, rate limit tracking
- SVC-ADM (port 5020): Manual review task queue
- `httpx`: Async HTTP client for provider calls
- `vcrpy` or `respx`: Test recording for integration tests
