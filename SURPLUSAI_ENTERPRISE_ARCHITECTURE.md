# SurplusAI Enterprise Architecture

## Production-Grade SaaS Platform for Surplus Funds Intelligence

**Classification**: INTERNAL -- EXECUTIVE ARCHITECTURE
**Version**: 1.0.0
**Date**: 2026-05-24
**Domain**: surplusai.io
**Host**: wheeler-aiops-01 (5.78.140.118) -- 30 GB RAM, 16 vCPUs, 338 GB SSD
**PM2 Ecosystem**: Wheeler Autonomous Operations (20+ services)

---

## Table of Contents

1. Multi-Tenant Data Isolation Architecture
2. Enterprise Authentication & RBAC
3. County Adapter Framework (All 50 States, 3,000+ Counties)
4. AI Docket Parsing Pipeline
5. Lead Scoring ML Engine
6. Attorney Routing Algorithm
7. Document Automation Pipeline
8. Billing & Subscription Architecture
9. API Gateway Design
10. Enterprise SLA Framework
11. Capacity Planning (200,000 Cases/Month)
12. Security Architecture
13. Implementation Roadmap & Phase Gates
A. Appendix: Complete Schema DDL
B. Appendix: Service Port Map

---

## 1. Multi-Tenant Data Isolation Architecture

### 1.1 Isolation Strategy Decision

SurplusAI employs a **hybrid isolation model** with two tiers:

| Tier | Isolation Model | Use Case | Tenant Count |
|------|----------------|----------|-------------|
| Standard (Pro) | Schema-per-tenant within shared database | Small-to-medium law firms, solo practitioners | Up to 500 |
| Enterprise (White-Label) | Database-per-tenant on dedicated or shared cluster | Large firms, enterprise deployments | Up to 50 |

**Decision Rationale:**
- Schema-per-tenant balances isolation with operational efficiency. A single PostgreSQL instance (frgops-standby :5433) can host 500+ tenant schemas without degradation.
- Database-per-tenant for white-label clients provides full data isolation required for compliance (HIPAA-adjacent, state bar ethics rules) and enables per-tenant backup/restore SLAs.
- Row-level security (RLS) is used *within* schemas for soft multi-tenancy of reference data (e.g., county adapters, document templates).

### 1.2 Schema-Per-Tenant Architecture

Each tenant gets a dedicated PostgreSQL schema within the shared `surplusai` database on frgops-standby (:5433):

```
surplusai database (frgops-standby:5433)
  |
  +-- public                          # Reference data (adapters, templates, plans)
  +-- tenant_{org_id}_001             # Tenant schema 1
  +-- tenant_{org_id}_002             # Tenant schema 2
  +-- tenant_{org_id}_003             # Tenant schema 3
  ...
```

**Schema creation at tenant provisioning:**

```sql
-- Called during tenant onboarding
CREATE SCHEMA IF NOT EXISTS tenant_{org_id};

-- Set search path to tenant schema for all tenant queries
ALTER ROLE surplusai_user SET search_path TO tenant_{org_id}, public;

-- Create tenant-local tables (each schema has full copy of tenant-scoped tables)
CREATE TABLE tenant_{org_id}.cases (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_number     VARCHAR(128) NOT NULL,
    property_address VARCHAR(512),
    surplus_amount  NUMERIC(12,2),
    sale_date       DATE,
    sale_type       VARCHAR(32),
    court_name      VARCHAR(256),
    county          VARCHAR(128),
    state           CHAR(2),
    raw_data        JSONB,
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(case_number, state, county)
);

CREATE TABLE tenant_{org_id}.leads (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id         UUID REFERENCES tenant_{org_id}.cases(id),
    score           NUMERIC(5,2),
    score_breakdown JSONB,
    status          VARCHAR(32) DEFAULT 'new',
    assigned_to     UUID,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE tenant_{org_id}.attorney_assignments ( ... );
CREATE TABLE tenant_{org_id}.documents ( ... );
CREATE TABLE tenant_{org_id}.calendar_events ( ... );
CREATE TABLE tenant_{org_id}.notifications ( ... );
CREATE TABLE tenant_{org_id}.audit_log ( ... );
```

**Shared reference tables (public schema):**

```sql
-- Public schema holds reference data shared across all tenants
CREATE TABLE public.organizations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(256) NOT NULL,
    slug            VARCHAR(64) UNIQUE NOT NULL,
    tier            VARCHAR(32) NOT NULL DEFAULT 'pro',
    schema_name     VARCHAR(64) NOT NULL UNIQUE,
    is_active       BOOLEAN DEFAULT TRUE,
    settings        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.organization_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id),
    user_id         UUID REFERENCES public.users(id),
    role            VARCHAR(32) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organization_id, user_id)
);

CREATE TABLE public.county_adapters (
    county_code     VARCHAR(32) PRIMARY KEY,
    county_name     VARCHAR(128) NOT NULL,
    state_code      CHAR(2) NOT NULL,
    base_url        VARCHAR(512),
    auth_type       VARCHAR(32) DEFAULT 'none',
    auth_config     JSONB,
    enabled         BOOLEAN DEFAULT TRUE,
    poll_interval_minutes INTEGER DEFAULT 60,
    rate_limit_rps  NUMERIC(4,1) DEFAULT 1.0,
    last_run_at     TIMESTAMPTZ,
    last_error      TEXT,
    cases_collected_total INTEGER DEFAULT 0
);

CREATE TABLE public.document_templates (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    county_code     VARCHAR(32) REFERENCES public.county_adapters(county_code),
    document_type   VARCHAR(64) NOT NULL,
    template_body   TEXT NOT NULL,
    fields_required JSONB,
    fields_optional JSONB,
    version         INTEGER DEFAULT 1
);

CREATE TABLE public.billing_plans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_code       VARCHAR(32) UNIQUE NOT NULL,
    name            VARCHAR(128) NOT NULL,
    price_cents     INTEGER NOT NULL,
    features        JSONB NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE
);

CREATE TABLE public.billing_subscriptions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id),
    plan_id         UUID REFERENCES public.billing_plans(id),
    status          VARCHAR(32) DEFAULT 'active',
    current_period_start DATE NOT NULL,
    current_period_end   DATE NOT NULL,
    stripe_subscription_id VARCHAR(128),
    trial_end       DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 1.3 Database-Per-Tenant Architecture (White-Label Tier)

For Enterprise/White-Label tenants, each organization receives a dedicated database:

```sql
-- Provisioning script for white-label tenant
CREATE DATABASE surplusai_tenant_{org_id}
    WITH OWNER = surplusai_admin
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8';

-- Create dedicated role with limited privileges
CREATE ROLE surplusai_tenant_{org_id}_user WITH LOGIN PASSWORD '<random-hex>';
GRANT CONNECT ON DATABASE surplusai_tenant_{org_id} TO surplusai_tenant_{org_id}_user;
GRANT USAGE, CREATE ON SCHEMA public TO surplusai_tenant_{org_id}_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO surplusai_tenant_{org_id}_user;

-- Apply standard SurplusAI schema
\c surplusai_tenant_{org_id}
\i /opt/apps/surplusai-portal/migrations/base_schema.sql
```

White-label databases can reside on:
- **Tier 1**: Same frgops-standby instance (:5433) -- up to 20 dedicated databases
- **Tier 2**: Dedicated PostgreSQL container on AIOPS -- up to 50 databases
- **Tier 3**: Separate COREDB PostgreSQL cluster (future) -- unlimited scale

### 1.4 Connection Pooling

All tenant database connections route through PgBouncer (or application-level pool) to prevent connection exhaustion:

```
surplusai-portal-api (:8103)
  |
  +-- PgBouncer (127.0.0.1:6432) or SQLAlchemy pool
  |     |
  |     +-- surplusai database (schema-per-tenant: shared pool, 50 connections)
  |     +-- surplusai_tenant_xxx (db-per-tenant: dedicated pool, 10 connections each)
  |
  Pool settings:
  - min_size: 2 (warm connections per tenant)
  - max_size: 10 (per tenant, burst)
  - max_overflow: 5 (emergency connections)
  - pool_timeout: 5s
  - pool_recycle: 3600s
```

### 1.5 Tenant-Aware Middleware

The FastAPI application resolves the active tenant from JWT claims and sets the database search path:

```python
# middleware/tenant.py
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

class TenantMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Extract org_id from validated JWT
        org_id = request.state.user.get("organization_id")
        
        # Look up tenant schema
        async with db.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT schema_name FROM public.organizations WHERE id = $1",
                org_id
            )
            schema_name = row["schema_name"]
        
        # Set schema search path for this request
        request.state.tenant_schema = schema_name
        request.state.tenant_id = org_id
        
        # Execute within tenant context
        async with db.acquire() as conn:
            await conn.execute(f"SET search_path TO {schema_name}, public")
            response = await call_next(request)
        
        return response
```

For database-per-tenant, the middleware selects the correct database connection string from a registry:

```python
class DatabasePerTenantMiddleware(BaseHTTPMiddleware):
    TENANT_DB_URLS = {
        "org_abc": "postgresql://user:pass@127.0.0.1:5433/surplusai_tenant_abc",
        "org_def": "postgresql://user:pass@127.0.0.1:5433/surplusai_tenant_def",
    }
    
    async def dispatch(self, request: Request, call_next):
        org_id = request.state.user.get("organization_id")
        db_url = self.TENANT_DB_URLS.get(org_id)
        if not db_url:
            raise HTTPException(500, "Tenant database not configured")
        
        # Create per-request engine session (or use cached async engine)
        async with create_async_engine(db_url).connect() as conn:
            request.state.db = conn
            response = await call_next(request)
        
        return response
```

---

## 2. Enterprise Authentication & RBAC

### 2.1 Authentication Architecture

SurplusAI supports three authentication methods, configurable per organization:

| Method | Protocol | Use Case | Implementation |
|--------|----------|----------|---------------|
| Native (email + password) | bcrypt + JWT | SMB / solo practitioners | FastAPI built-in auth |
| SAML 2.0 | SAML Web SSO | Enterprise SSO (Okta, Azure AD, OneLogin) | `python3-saml` + metadata exchange |
| OIDC | OpenID Connect | Modern identity providers (Google Workspace, Auth0, Keycloak) | `authlib` library |

### 2.2 Native Authentication Flow

```
POST /api/v1/auth/login
  Body: { email, password }
  Response: { access_token, refresh_token, expires_in }
  
POST /api/v1/auth/register
  Body: { email, password, organization_name, tier }
  Response: { organization_id, user_id, access_token }
  Notes: Creates organization + tenant schema on registration (Phase 1: admin-provisioned only)

POST /api/v1/auth/refresh
  Body: { refresh_token }
  Response: { access_token, expires_in }

POST /api/v1/auth/magic-link
  Body: { email }
  Response: { message: "Check email for login link" }
  Notes: Passwordless login for attorney portal
```

### 2.3 SAML 2.0 Integration

```
Configuration (set by admin):
  POST /api/v1/admin/saml/config
    Body: {
      idp_metadata_url: "https://your-org.okta.com/app/.../sso/saml/metadata",
      idp_entity_id: "http://www.okta.com/...",
      attr_mapping: {
        email: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        first_name: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
        last_name: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname",
        groups: "http://schemas.xmlsoap.org/claims/Group"
      }
    }
    
Login flow:
  1. User clicks "Sign in with SSO" on SurplusAI login page
  2. User enters organization domain (e.g., "lawfirm.com")
  3. SurplusAI redirects to IdP SAML endpoint with AuthnRequest
  4. IdP authenticates user, POSTs SAMLResponse to SurplusAI ACS URL
  5. SurplusAI validates assertion, extracts attributes, maps to organization user
  6. JWT issued, user redirected to dashboard
```

### 2.4 OIDC Integration

```python
# Example: Google Workspace OIDC config
OIDC_PROVIDERS = {
    "google": {
        "authorization_endpoint": "https://accounts.google.com/o/oauth2/v2/auth",
        "token_endpoint": "https://oauth2.googleapis.com/token",
        "userinfo_endpoint": "https://openidconnect.googleapis.com/v1/userinfo",
        "jwks_uri": "https://www.googleapis.com/oauth2/v3/certs",
        "scopes": ["openid", "email", "profile"],
        "client_id": "...",  # Per-organization
        "client_secret": "...",  # Per-organization
    }
}

# Login flow:
GET /api/v1/auth/oidc/{provider}/authorize
  -> Redirects to provider's authorization URL with state parameter
  
GET /api/v1/auth/oidc/{provider}/callback
  -> Exchanges code for tokens, validates ID token
  -> Creates/links user account
  -> Issues JWT
```

### 2.5 JWT Token Design

```json
{
  "sub": "user_uuid",
  "email": "attorney@lawfirm.com",
  "organization_id": "org_uuid",
  "organization_slug": "lawfirm-pllc",
  "role": "attorney",
  "tenant_schema": "tenant_org_001",
  "permissions": [
    "cases:read",
    "cases:write",
    "leads:read",
    "documents:sign"
  ],
  "iss": "surplusai.io",
  "aud": "surplusai-portal-api",
  "iat": 1716500000,
  "exp": 1716586400
}
```

**Token lifecycle:**
- Access token: 15 minutes (short-lived, reduced blast radius)
- Refresh token: 7 days (configurable per organization)
- SAML session: IdP-controlled (typically 8 hours)

### 2.6 RBAC Role Model

Four roles with strictly defined permission boundaries:

#### Superadmin (Platform Operator)

```yaml
role: superadmin
scope: Global platform administration
permissions:
  - organizations:read,create,update,delete,suspend
  - users:read,create,update,delete
  - billing:read,update,refund
  - adapters:read,create,update,delete,enable,disable
  - cases:* (cross-tenant, read-only without explicit override)
  - leads:* (cross-tenant, read-only without explicit override)
  - system:read (metrics, logs, health)
  - audit:read (cross-tenant)
  - templates:read,create,update,delete
```

#### Attorney Admin (Organization Administrator)

```yaml
role: attorney_admin
scope: Own organization only
permissions:
  - organization:read,update_settings
  - users:read,create,update,deactivate (within org)
  - billing:read (own subscription only)
  - cases:read,create,update,delete,export
  - leads:read,update_score,assign,reassign
  - documents:read,create,send,delete
  - templates:read,create,update (org-scoped)
  - attorneys:read,create,update,deactivate (org members)
  - audit:read (org-scoped)
  - reports:read,create,export
  - webhooks:read,create,update,delete
  - calendar:read,create,update,delete
```

#### Attorney (Case Worker)

```yaml
role: attorney
scope: Own assigned cases and profile
permissions:
  - cases:read (assigned only)
  - leads:read (assigned only)
  - documents:read,create,send,sign (assigned cases only)
  - profile:read,update
  - calendar:read (own deadlines)
  - communications:read,send (on assigned cases)
  - attorneys:read (directory only)
```

#### Viewer (Read-Only)

```yaml
role: viewer
scope: Read access within organization
permissions:
  - cases:read
  - leads:read
  - documents:read
  - reports:read
  - attorneys:read
  - calendar:read
  - NO: create, update, delete, write operations
```

### 2.7 Permission Enforcement

Enforcement happens at three layers:

**Layer 1: API Gateway (Traefik middleware)**
- Validates JWT signature and expiry
- Rejects requests without valid token
- Rate limits by organization

**Layer 2: FastAPI middleware**
```python
from fastapi import Depends, HTTPException, Security
from fastapi.security import HTTPBearer

security = HTTPBearer()

async def require_role(required_role: str):
    async def role_checker(token: HTTPAuthorizationCredentials = Security(security)):
        payload = decode_jwt(token.credentials)
        user_role = payload.get("role")
        role_hierarchy = ["viewer", "attorney", "attorney_admin", "superadmin"]
        if role_hierarchy.index(user_role) < role_hierarchy.index(required_role):
            raise HTTPException(403, "Insufficient permissions")
        return payload
    return role_checker

# Usage:
@app.get("/api/v1/leads")
async def list_leads(user=Depends(require_role("viewer"))):
    ...
```

**Layer 3: Row-level security (PostgreSQL RLS)**
```sql
-- Enable RLS on tenant tables
ALTER TABLE tenant_org_001.cases ENABLE ROW LEVEL SECURITY;

-- Attorney can only see their assigned cases
CREATE POLICY attorney_case_access ON tenant_org_001.cases
    FOR ALL
    USING (
        current_user_role() = 'attorney' 
        AND assigned_to = current_user_id()
    );

-- Attorney admin can see all cases in org
CREATE POLICY admin_case_access ON tenant_org_001.cases
    FOR ALL
    USING (current_user_role() IN ('attorney_admin', 'superadmin'));
```

---

## 3. County Adapter Framework (All 50 States, 3,000+ Counties)

### 3.1 Architecture Overview

The county adapter framework is the data ingestion backbone. Each of the 3,000+ U.S. counties represents a potential data source with unique website structure, document format, and access patterns. The framework provides a standardized interface with county-specific implementations.

```
/opt/apps/surplusai-scraper-agent-svc/src/adapters/
  |
  +-- interface.ts              # ICountyAdapter interface (contract)
  +-- registry.ts               # Adapter registry with DB-backed config
  +-- base-adapter.ts           # Shared: rate limiting, retry, logging, metrics
  +-- states/
  |     +-- california/
  |     |     +-- los-angeles.adapter.ts
  |     |     +-- san-diego.adapter.ts
  |     |     +-- orange.adapter.ts
  |     |     +-- ...
  |     +-- texas/
  |     |     +-- harris.adapter.ts
  |     |     +-- dallas.adapter.ts
  |     |     +-- tarrant.adapter.ts
  |     |     +-- ...
  |     +-- illinois/
  |     |     +-- cook.adapter.ts
  |     |     +-- ...
  |     +-- [state]/
  |           +-- [county].adapter.ts
  +-- templates/
        +-- standard-portal.adapter.ts   # Generic web portal adapter
        +-- pdf-only.adapter.ts          # PDF document source only
        +-- api-json.adapter.ts          # REST API data source
        +-- csv-upload.adapter.ts        # CSV/bulk data source
```

### 3.2 Adapter Interface (Production-Grade)

```typescript
/**
 * County adapter interface for surplus fund data collection.
 * Every county gets an implementation of this contract.
 */
interface ICountyAdapter {
  // Identity
  countyCode: string;           // "los-angeles-ca"
  countyName: string;           // "Los Angeles"
  stateCode: string;            // "CA"
  fipsCode: string;             // "06037" — FIPS county code for cross-reference

  // Required: fetch new/updated cases from this county's data source
  fetchCases(): Promise<RawCase[]>;

  // Optional: authenticate to the county data portal
  authenticate?(credentials: AuthCredentials): Promise<AuthToken>;

  // Optional: county-specific document parsing
  parseDocument?(buffer: Buffer, mimeType: string): Promise<ParsedDocument>;

  // Optional: handle captcha or bot detection
  handleChallenge?(challenge: ChallengePayload): Promise<ChallengeSolution>;

  // Rate limiting configuration
  rateLimit: {
    requestsPerSecond: number;
    burstSize: number;
    backoffMinutes: number;
    maxRetries: number;
  };

  // Health check: verify the data source is reachable
  healthCheck(): Promise<AdapterHealth>;
}

interface RawCase {
  externalId: string;           // County's own case ID
  caseNumber: string;
  propertyAddress?: string;
  surplusAmount?: number;
  saleDate?: string;            // ISO 8601
  saleType?: 'trustee' | 'foreclosure' | 'tax' | 'sheriff';
  claimantNames: string[];
  claimantAddresses: string[];
  attorneyName?: string;
  attorneyBarNumber?: string;
  courtName?: string;
  documentUrls: string[];
  rawHtml?: string;             // For LLM extraction fallback
  collectedAt: string;          // ISO 8601
}

interface AdapterHealth {
  status: 'healthy' | 'degraded' | 'down';
  lastSuccessfulRun?: string;
  lastError?: string;
  responseTimeMs?: number;
  casesAvailable?: number;
}
```

### 3.3 Adapter Template System

To achieve 3,000+ county coverage, adapters are generated from templates covering ~90% of counties:

```typescript
// templates/standard-portal.adapter.ts
// Covers: counties with standard web portal + PDF documents (~60% of counties)

class StandardPortalAdapter implements ICountyAdapter {
  constructor(
    public readonly countyCode: string,
    public readonly countyName: string,
    public readonly stateCode: string,
    public readonly fipsCode: string,
    private readonly config: PortalAdapterConfig
  ) {}

  public readonly rateLimit = {
    requestsPerSecond: 1.0,
    burstSize: 2,
    backoffMinutes: 30,
    maxRetries: 3,
  };

  async fetchCases(): Promise<RawCase[]> {
    // Step 1: Fetch search results page
    const searchUrl = this.config.searchUrlPattern
      .replace('{county}', this.countyName)
      .replace('{state}', this.stateCode);
    
    const html = await this.fetchWithRetry(searchUrl);
    
    // Step 2: Parse search results (district court, superior court, etc.)
    const caseLinks = this.parseCaseLinks(html);
    
    // Step 3: Fetch each case detail page
    const cases: RawCase[] = [];
    for (const link of caseLinks) {
      const detailHtml = await this.fetchWithRetry(link.url);
      const parsed = this.parseCaseDetail(detailHtml, link);
      
      // Step 4: Download associated documents
      parsed.documentUrls = this.extractDocumentUrls(detailHtml);
      
      cases.push(parsed);
    }
    
    return cases;
  }

  private async fetchWithRetry(url: string): Promise<string> {
    // Implements: exponential backoff + jitter
    // Token bucket rate limiting
    // User-agent rotation
    // See base-adapter.ts for shared implementation
    return this.baseAdapter.fetchWithRetry(url);
  }
}
```

### 3.4 Adapter Configuration (Database-Backed)

Adapters are configured via the `county_adapters` table and managed through the admin console:

```sql
-- Full adapter config schema
CREATE TABLE public.county_adapters (
    county_code             VARCHAR(32) PRIMARY KEY,
    county_name             VARCHAR(128) NOT NULL,
    state_code              CHAR(2) NOT NULL,
    fips_code               VARCHAR(5),
    adapter_class           VARCHAR(128) NOT NULL,  -- e.g., "StandardPortalAdapter"
    template_type           VARCHAR(64),              -- Which generator template to use
    
    -- Data source configuration
    base_url                VARCHAR(512),
    search_url_pattern      VARCHAR(512),
    detail_url_pattern      VARCHAR(512),
    document_url_pattern    VARCHAR(512),
    
    -- Authentication
    auth_type               VARCHAR(32) DEFAULT 'none',  -- none, api_key, basic, oauth2, session
    auth_config             JSONB,                       -- Encrypted credentials
    auth_refresh_required   BOOLEAN DEFAULT FALSE,
    
    -- Scheduling
    enabled                 BOOLEAN DEFAULT FALSE,
    poll_interval_minutes   INTEGER DEFAULT 1440,        -- Default: daily
    active_hours_start      TIME DEFAULT '06:00',
    active_hours_end        TIME DEFAULT '22:00',
    timezone                VARCHAR(64) DEFAULT 'America/New_York',
    
    -- Rate limiting
    rate_limit_rps          NUMERIC(4,1) DEFAULT 1.0,
    rate_limit_burst        INTEGER DEFAULT 2,
    backoff_minutes         INTEGER DEFAULT 30,
    max_retries             INTEGER DEFAULT 3,
    
    -- Adaptive scrape (automatic interval adjustment)
    adaptive_polling        BOOLEAN DEFAULT FALSE,
    min_poll_interval       INTEGER DEFAULT 60,
    target_cases_per_run    INTEGER DEFAULT 50,
    last_cases_count        INTEGER DEFAULT 0,
    
    -- Health tracking
    health_status           VARCHAR(32) DEFAULT 'unknown',
    last_run_at             TIMESTAMPTZ,
    last_success_at         TIMESTAMPTZ,
    last_error              TEXT,
    consecutive_errors      INTEGER DEFAULT 0,
    error_threshold         INTEGER DEFAULT 5,           -- Auto-disable at threshold
    
    -- Statistics
    total_runs              INTEGER DEFAULT 0,
    successful_runs         INTEGER DEFAULT 0,
    failed_runs             INTEGER DEFAULT 0,
    cases_collected_total   INTEGER DEFAULT 0,
    cases_collected_today   INTEGER DEFAULT 0,
    avg_response_time_ms    INTEGER,
    
    -- Configuration versioning
    config_version          INTEGER DEFAULT 1,
    config_updated_at       TIMESTAMPTZ,
    config_updated_by       UUID REFERENCES public.users(id),
    
    -- Metadata
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for geographic queries
CREATE INDEX idx_adapters_state ON public.county_adapters(state_code);
CREATE INDEX idx_adapters_health ON public.county_adapters(health_status) WHERE enabled = TRUE;
CREATE INDEX idx_adapters_next_run ON public.county_adapters(last_run_at) WHERE enabled = TRUE;
```

### 3.5 County Classification by Complexity

Counties are classified into tiers based on data source characteristics:

| Tier | Description | % of Counties | Adapter Type | Est. Dev Time | Example |
|------|-------------|--------------|--------------|---------------|---------|
| 1 | REST API + JSON/XML data | 8% (240) | `ApiJsonAdapter` | 0.5 days | Maricopa, AZ; Dallas, TX |
| 2 | Structured web portal + PDF | 25% (750) | `StandardPortalAdapter` | 1 day | Los Angeles, CA; Cook, IL |
| 3 | Unstructured web portal | 30% (900) | `PortalScraperAdapter` | 1.5 days | Miami-Dade, FL; Philadelphia, PA |
| 4 | PDF-only or scanned images | 20% (600) | `PdfOnlyAdapter` | 2 days | Rural counties with limited IT |
| 5 | No online data / phone-only | 12% (360) | `ManualEntryAdapter` | N/A | Remote rural counties |
| 6 | Subscription/paid data | 5% (150) | `PaidApiAdapter` | 1 day | Various (LexisNexis sourced) |

**Coverage strategy:**
- Phase 1: Top 50 counties by case volume (Tier 1-2, ~70% of national case volume)
- Phase 2: Next 200 counties (Tiers 1-3, ~90% of volume)
- Phase 3: Remaining counties via template generation (Tiers 1-4, ~98% of volume)
- Phase 4: Long tail (Tiers 5-6, manual/paid sources)

### 3.6 Scraper Queue and Scheduling

The scraper uses the existing polling loop with Temporal Server (:7233) for durable execution:

```
Temporal Workflow: SurplusScrapeOrchestrator
  |
  +-- Activity: LoadEnabledAdapters
  |     Reads enabled county_adapters where poll_interval_minutes elapsed
  |
  +-- Activity: PartitionByRateLimit
  |     Groups adapters by rate limit tier for parallel execution
  |
  +-- For each partition (parallel fan-out):
  |     +-- Activity: ExecuteAdapter(county_code)
  |     |     Runs ICountyAdapter.fetchCases()
  |     |     Records metrics, handles errors
  |     |
  |     +-- Activity: QueueParsing(cases)
  |     |     Adds new cases to parser queue
  |     |
  |     +-- Activity: DetectChanges
  |     |     Compares with previous run, alerts on significant changes
  |
  +-- Activity: UpdateMetrics
        Push to Prometheus: total_cases, errors, latency
```

**Scaling:**
- Temporal supports parallel adapter execution bounded by rate limits
- Target: 50 concurrent adapters (limited by target site tolerance, not infrastructure)
- At 50 concurrent adapters, all 3,000+ counties can be scraped within 60 minutes

### 3.7 Adaptive Polling

Instead of fixed intervals, adapters automatically adjust polling frequency:

```sql
-- Adaptive polling logic (pseudocode)
poll_interval_minutes = CASE
    WHEN consecutive_errors > 3 THEN 1440  -- Once/day during errors
    WHEN avg_cases_per_run < 5 THEN 4320    -- Low volume: every 3 days
    WHEN avg_cases_per_run < 20 THEN 1440   -- Medium volume: daily
    WHEN avg_cases_per_run < 50 THEN 720    -- High volume: every 12 hours
    ELSE 360                                 -- Very high volume: every 6 hours
END;
```

---

## 4. AI Docket Parsing Pipeline

### 4.1 Pipeline Architecture

The docket parsing pipeline transforms raw county court documents into structured, validated case data. It runs as a separate service on port 8104 with five stages:

```
                        ┌──────────────────────────────────────┐
                        │     Parser Service (:8104)           │
                        │                                      │
Raw documents ─────────>│ Stage 1: Ingest & Classify           │──> Queue for review
  (PDF, HTML, images)   │   - MIME detection                   │     (confidence < 0.6)
                        │   - Text extraction (PDF/HTML/OCR)   │
                        │   - Language detection               │
                        │                                      │
                        │ Stage 2: LLM Extraction              │──> Confidence 0.6-0.85
                        │   - LiteLLM (:4049) /v1/chat/complet │     (flag for spot-check)
                        │   - DeepSeek V4 (deepseek-chat)      │
                        │   - Structured JSON output            │
                        │   - Few-shot examples per county      │
                        │                                      │
                        │ Stage 3: Validation                  │──> Auto-accepted
                        │   - Schema enforcement               │     (confidence > 0.85)
                        │   - Cross-field consistency          │
                        │   - Regex pattern matching            │
                        │   - Surplus amount sanity check       │
                        │                                      │
                        │ Stage 4: Confidence Scoring           │
                        │   - Per-field confidence              │
                        │   - Geometric mean aggregation        │
                        │   - Threshold routing                 │
                        │                                      │
                        │ Stage 5: Persistence                  │
                        │   - Write to tenant schema            │
                        │   - Index in Neo4j (:7687)           │
                        │   - Cache extraction result           │
                        └──────────────────────────────────────┘
```

### 4.2 Stage 1: Document Classification

```python
# services/classifier.py

class DocumentClassifier:
    """Classifies incoming documents by type and format."""
    
    MIME_TYPE_MAP = {
        'application/pdf': 'pdf',
        'text/html': 'html',
        'text/plain': 'text',
        'image/jpeg': 'image',
        'image/png': 'image',
        'image/tiff': 'image',
    }
    
    async def classify(self, buffer: bytes, content_type: str) -> DocumentType:
        """Determine document type and extraction strategy."""
        mime_type = content_type or self._detect_mime(buffer)
        format_type = self.MIME_TYPE_MAP.get(mime_type, 'unknown')
        
        if format_type == 'pdf':
            # Check if PDF is text-based or scanned
            pdf_info = await self._analyze_pdf(buffer)
            if pdf_info.has_text:
                return DocumentType('pdf_text', extractor='pypdf')
            else:
                return DocumentType('pdf_scanned', extractor='ocr')
                
        elif format_type == 'html':
            return DocumentType('html', extractor='html2text')
            
        elif format_type == 'image':
            return DocumentType('image', extractor='ocr')
            
        else:
            return DocumentType('unknown', extractor='raw_text')
    
    async def extract_text(self, buffer: bytes, doc_type: DocumentType) -> str:
        """Extract raw text based on document type."""
        if doc_type.extractor == 'pypdf':
            return await self._extract_pdf_text(buffer)
        elif doc_type.extractor == 'ocr':
            return await self._ocr_extract(buffer)  # Tesseract/PaddleOCR
        elif doc_type.extractor == 'html2text':
            return html2text.html2text(buffer.decode('utf-8'))
        else:
            return buffer.decode('utf-8', errors='replace')
```

### 4.3 Stage 2: LLM Extraction

```python
# services/llm_extractor.py

class LLMExtractor:
    """Extract structured case data using DeepSeek V4 via LiteLLM."""
    
    LITELLM_URL = "http://127.0.0.1:4049/v1"
    MODEL = "deepseek-chat"
    
    def __init__(self):
        self.client = openai.AsyncOpenAI(
            base_url=self.LITELLM_URL,
            api_key="sk-litellm-proxy",  # LiteLLM validates internally
        )
    
    async def extract(self, text: str, county_code: str, state_code: str) -> ExtractionResult:
        """Send document text to LLM and parse structured output."""
        
        prompt = self._build_prompt(text, county_code, state_code)
        
        response = await self.client.chat.completions.create(
            model=self.MODEL,
            messages=[
                {"role": "system", "content": prompt.system},
                {"role": "user", "content": prompt.user}
            ],
            response_format={"type": "json_object"},
            temperature=0.1,  # Low temperature for deterministic extraction
            max_tokens=4096,
        )
        
        raw = json.loads(response.choices[0].message.content)
        validated = self._validate_schema(raw)
        
        return ExtractionResult(
            raw=validated,
            usage=response.usage,
            latency_ms=response.response_ms,
        )
    
    def _build_prompt(self, text: str, county_code: str, state_code: str) -> Prompt:
        """Build extraction prompt with county-specific few-shot examples."""
        
        examples = self._get_few_shot_examples(county_code, state_code)
        
        return Prompt(
            system=f"""You are a legal document extraction specialist. Extract surplus fund 
case information from court documents into structured JSON.

County-specific rules for {county_code}, {state_code}:
{self._get_county_rules(county_code)}

Extraction confidence guidelines:
- Set confidence=1.0 for values directly found in the text
- Set confidence=0.8 for values clearly derivable from context
- Set confidence=0.5 for values that require inference
- Set confidence=0.0 for values not found in the text

Examples:
{json.dumps(examples, indent=2)}

Respond ONLY with valid JSON matching the required schema.""",
            user=f"Extract case information from this document:\n\n{text[:32000]}"
        )
```

### 4.4 Stage 3: Field-Level Validation

```python
# services/validator.py

class FieldValidator:
    """Cross-field validation rules for extracted case data."""
    
    VALIDATION_RULES = {
        "case_number": [
            Rule("not_empty", lambda v: bool(v)),
            Rule("no_hallucination", lambda v: len(v) > 3 and len(v) < 64),
            Rule("county_format", lambda v, ctx: self._validate_case_format(v, ctx.county_code)),
        ],
        "surplus_amount": [
            Rule("positive_number", lambda v: v > 0),
            Rule("reasonable_range", lambda v: v < 50_000_000),  # Max $50M
            Rule("min_relevant", lambda v: v >= 100),            # Min $100
        ],
        "sale_date": [
            Rule("valid_date", lambda v: self._is_valid_date(v)),
            Rule("not_future", lambda v: datetime.fromisoformat(v) <= datetime.now()),
            Rule("not_too_old", lambda v: datetime.fromisoformat(v) > datetime.now() - timedelta(days=365*5)),
        ],
        "claimant_names": [
            Rule("not_empty_list", lambda v: len(v) > 0),
            Rule("no_placeholders", lambda v: not any(n.startswith("[") for n in v)),
        ],
        "state": [
            Rule("valid_us_state", lambda v: v in US_STATES),
        ],
    }
    
    async def validate(self, extraction: dict, context: ValidationContext) -> ValidationResult:
        """Run all validation rules and compute field-level confidence adjustments."""
        field_results = {}
        all_passed = True
        
        for field, value in extraction.items():
            if field not in self.VALIDATION_RULES:
                continue
            
            field_ok = True
            for rule in self.VALIDATION_RULES[field]:
                try:
                    if rule.requires_context:
                        passed = rule.check(value, context)
                    else:
                        passed = rule.check(value)
                    
                    if not passed:
                        field_ok = False
                        all_passed = False
                except Exception:
                    field_ok = False
                    all_passed = False
            
            field_results[field] = {
                "valid": field_ok,
                "value": value,
            }
        
        return ValidationResult(
            passed=all_passed,
            field_results=field_results,
            overall_confidence=self._compute_overall_confidence(field_results, extraction),
        )
```

### 4.5 Stage 4: Confidence Scoring Engine

```python
# services/confidence.py

class ConfidenceScorer:
    """Compute per-field and overall confidence scores."""
    
    def compute_per_field(self, extraction: dict, validation: ValidationResult) -> dict:
        """Compute confidence for each extracted field."""
        confidences = {}
        
        for field, value in extraction.items():
            base_confidence = extraction.get(f"_confidence_{field}", 0.8)
            
            # Adjust based on validation
            if field in validation.field_results:
                if not validation.field_results[field]["valid"]:
                    base_confidence *= 0.5
            
            # Adjust based on extraction source
            source = extraction.get(f"_source_{field}", "llm")
            if source == "regex":
                base_confidence = min(1.0, base_confidence + 0.15)
            elif source == "ocr":
                base_confidence *= 0.85
            elif source == "html_structured":
                base_confidence = min(1.0, base_confidence + 0.1)
            
            # Numeric field heuristics
            if isinstance(value, (int, float)) and field in ["surplus_amount", "original_judgment"]:
                if value == round(value, -3):  # Round number is suspicious
                    base_confidence *= 0.9
            
            confidences[field] = round(min(1.0, max(0.0, base_confidence)), 2)
        
        return confidences
    
    def compute_overall(self, per_field: dict, required_fields: list[str]) -> float:
        """Geometric mean of required field confidences."""
        required_confidences = [
            per_field.get(f, 0.0) for f in required_fields
        ]
        
        if not required_confidences:
            return 0.0
        
        # Geometric mean (penalizes low confidence more than arithmetic)
        product = 1.0
        for c in required_confidences:
            product *= max(c, 0.01)  # Avoid zero product
        
        return round(product ** (1.0 / len(required_confidences)), 4)
```

### 4.6 Threshold Routing

```python
THRESHOLD_CONFIG = {
    "auto_accept": {
        "min_confidence": 0.85,
        "action": "persist_and_notify",
        "description": "No human review needed",
    },
    "spot_check": {
        "min_confidence": 0.60,
        "action": "persist_and_flag",
        "description": "Auto-accepted, flagged for random audit",
        "audit_rate": 0.10,  # 10% sampled for review
    },
    "human_review": {
        "min_confidence": 0.0,
        "action": "queue_for_review",
        "description": "Requires human review before persistence",
    },
}
```

### 4.7 Training Data Pipeline

Every extraction (whether auto-accepted or human-reviewed) becomes a training example:

```sql
CREATE TABLE public.training_examples (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    raw_document_hash   VARCHAR(64) NOT NULL,       -- SHA-256 for dedup
    raw_document_text   TEXT,                         -- Truncated to 32K chars
    county_code         VARCHAR(32) NOT NULL,
    state_code          CHAR(2) NOT NULL,
    llm_extraction      JSONB NOT NULL,              -- What LLM returned
    human_corrected     JSONB,                        -- Human corrections (nullable)
    reviewer_id         UUID REFERENCES public.users(id),
    reviewed_at         TIMESTAMPTZ,
    confidence_scores   JSONB,                       -- Per-field confidence
    extraction_latency_ms INTEGER,                    -- LLM response time
    used_in_training    BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(raw_document_hash)
);

CREATE INDEX idx_training_county ON public.training_examples(county_code);
CREATE INDEX idx_training_used ON public.training_examples(used_in_training) WHERE used_in_training = FALSE;
```

**Target: 5,000+ examples before fine-tuning a dedicated extraction model.**

---

## 5. Lead Scoring ML Engine

### 5.1 Architecture

The scoring service runs on port 8105 and provides both rule-based and ML-based lead scoring:

```
scoring-service (:8105)
  |
  +-- /api/v1/score          # Score a single lead (real-time)
  +-- /api/v1/score-batch    # Score batch of leads (async)
  +-- /api/v1/models         # List/deploy scoring models
  +-- /api/v1/features       # Feature engineering pipeline
  +-- /api/v1/train          # Trigger model retraining
```

### 5.2 Composite Score Formula

```python
# engine/composite_score.py

class CompositeScorer:
    """
    LeadScore = w1 * SurplusScore + w2 * FindabilityScore 
               + w3 * CompetitionScore + w4 * UrgencyScore
               + w5 * HistoricalScore + w6 * SeasonalityScore
    """
    
    WEIGHT_DEFAULTS = {
        "surplus_weight": 0.30,
        "findability_weight": 0.25,
        "competition_weight": 0.15,
        "urgency_weight": 0.10,
        "historical_weight": 0.12,
        "seasonality_weight": 0.08,
    }
    
    def __init__(self, weights: dict = None):
        self.weights = weights or self.WEIGHT_DEFAULTS
    
    async def score(self, lead: Lead, context: ScoringContext) -> LeadScore:
        """Compute composite lead score 0-100."""
        
        surplus_score = self._compute_surplus_score(lead.surplus_amount, context)
        findability_score = self._compute_findability_score(lead.claimant, context)
        competition_score = self._compute_competition_score(lead, context)
        urgency_score = self._compute_urgency_score(lead.sale_date)
        historical_score = self._compute_historical_score(lead, context)
        seasonality_score = self._compute_seasonality_score(lead.sale_date)
        
        composite = (
            self.weights["surplus_weight"] * surplus_score +
            self.weights["findability_weight"] * findability_score +
            self.weights["competition_weight"] * competition_score +
            self.weights["urgency_weight"] * urgency_score +
            self.weights["historical_weight"] * historical_score +
            self.weights["seasonality_weight"] * seasonality_score
        )
        
        breakdown = {
            "surplus_score": surplus_score,
            "findability_score": findability_score,
            "competition_score": competition_score,
            "urgency_score": urgency_score,
            "historical_score": historical_score,
            "seasonality_score": seasonality_score,
            "weights_applied": self.weights,
        }
        
        return LeadScore(
            composite=round(min(100, max(0, composite)), 2),
            breakdown=breakdown,
            tier=self._assign_tier(composite),
        )
    
    def _compute_surplus_score(self, amount: float, ctx: ScoringContext) -> float:
        """Surplus amount score with logarithmic scaling."""
        if not amount or amount <= 0:
            return 0
        
        # Log scale: $1K=20, $10K=60, $50K=85, $100K=95, $500K=100
        import math
        score = min(100, 20 * math.log10(max(1, amount / 1000)) * 10)
        
        # Adjust by county percentile if available
        if ctx.county_stats and ctx.county_stats.percentile_90:
            if amount > ctx.county_stats.percentile_90:
                score *= 1.1
        
        return min(100, score)
    
    def _compute_findability_score(self, claimant: Claimant, ctx: ScoringContext) -> float:
        """Score based on how findable the claimant is."""
        score = 0
        
        # Phone available: 30 points
        if claimant.phone:
            score += 30
        
        # Email available: 25 points
        if claimant.email:
            score += 25
        
        # Physical address: 20 points
        if claimant.address:
            score += 20
        
        # Social media presence: 15 points (if enriched)
        if claimant.social_profiles and len(claimant.social_profiles) > 0:
            score += min(15, len(claimant.social_profiles) * 5)
        
        # Bankruptcy flag: -20 penalty
        if claimant.bankruptcy_flag:
            score -= 20
        
        # Deceased claimant: 0 (unfindable)
        if claimant.is_deceased:
            score = 0
        
        return max(0, min(100, score))
    
    def _compute_competition_score(self, lead: Lead, ctx: ScoringContext) -> float:
        """Lower competition = higher score."""
        active_attorneys = ctx.active_attorneys_on_case or 0
        # Base 100, minus 20 per competing attorney
        score = 100 - (active_attorneys * 20)
        return max(0, score)
    
    def _compute_urgency_score(self, sale_date: Optional[date]) -> float:
        """Decay score over time since sale."""
        if not sale_date:
            return 50  # Unknown date = moderate urgency
        
        days_since = (date.today() - sale_date).days
        
        if days_since < 0:
            return 100  # Future sale = maximum urgency
        elif days_since <= 7:
            return 90   # Within a week
        elif days_since <= 30:
            return max(0, 100 - (days_since * 2))  # Decay 2 pts/day
        elif days_since <= 90:
            return max(0, 60 - (days_since * 0.5))  # Slow decay
        else:
            return max(10, 100 - (days_since * 0.2))  # Floor at 10
    
    def _compute_historical_score(self, lead: Lead, ctx: ScoringContext) -> float:
        """Score based on historical conversion patterns."""
        if not ctx.historical_stats:
            return 50  # Neutral if no history
        
        county_conversion = ctx.historical_stats.get(lead.county, {}).get("conversion_rate", 0.5)
        case_type_conversion = ctx.historical_stats.get(lead.sale_type, {}).get("conversion_rate", 0.5)
        
        return (county_conversion * 60 + case_type_conversion * 40)
    
    def _compute_seasonality_score(self, sale_date: Optional[date]) -> float:
        """Adjust score based on seasonal patterns."""
        if not sale_date:
            return 50
        
        month = sale_date.month
        # Q4 (Oct-Dec) typically has higher abandonment = more opportunity
        if month in [10, 11, 12]:
            return 70
        # Q1 (Jan-Mar) moderate
        elif month in [1, 2, 3]:
            return 60
        else:
            return 40
    
    def _assign_tier(self, score: float) -> str:
        if score >= 85:
            return "HOT"
        elif score >= 70:
            return "WARM"
        elif score >= 50:
            return "LUKEWARM"
        else:
            return "COLD"
```

### 5.3 ML Model (XGBoost)

Phase 2 enhancement replaces the rule-based scorer with a gradient-boosted model:

```python
# ml/model.py

import xgboost as xgb
import joblib
from typing import Optional

class XGBoostScorer:
    """
    ML-enhanced lead scorer using XGBoost.
    Trained on historical FRGCRM outcomes.
    """
    
    FEATURE_ENGINEERING = {
        "numerical": [
            "surplus_amount_log",
            "days_since_sale",
            "claimant_age_estimated",
            "claimant_distance_to_attorney_km",
            "property_value_estimated",
            "num_claimants",
            "num_documents",
            "county_monthly_volume",
            "county_avg_surplus",
            "attorney_density_in_county",
            "days_until_statute_of_limitations",
        ],
        "categorical": [
            "county",
            "state",
            "sale_type",
            "property_type",
            "day_of_week_sale",
            "month_of_sale",
            "quarter",
        ],
        "boolean": [
            "claimant_has_phone",
            "claimant_has_email",
            "claimant_has_address",
            "claimant_bankruptcy_history",
            "attorney_already_assigned",
            "is_commercial_property",
        ],
    }
    
    def __init__(self, model_path: Optional[str] = None):
        self.model = None
        if model_path:
            self.model = joblib.load(model_path)
    
    def engineer_features(self, lead: Lead, context: ScoringContext) -> np.ndarray:
        """Transform raw lead data into feature vector."""
        import numpy as np
        import pandas as pd
        
        features = {}
        
        # Numerical features
        features["surplus_amount_log"] = np.log1p(lead.surplus_amount or 0)
        
        if lead.sale_date:
            features["days_since_sale"] = (date.today() - lead.sale_date).days
        else:
            features["days_since_sale"] = -1
        
        features["claimant_distance_to_attorney_km"] = (
            context.distance_km or -1
        )
        
        features["num_claimants"] = len(lead.claimants or [])
        
        # Categorical features (one-hot encoded in production)
        features["county"] = lead.county
        features["state"] = lead.state
        features["sale_type"] = lead.sale_type or "unknown"
        
        # Boolean features
        features["claimant_has_phone"] = 1 if lead.claimant_phone else 0
        features["claimant_has_email"] = 1 if lead.claimant_email else 0
        
        return pd.DataFrame([features])
    
    async def predict(self, lead: Lead, context: ScoringContext) -> MLScore:
        """Predict conversion probability (0.0-1.0)."""
        if not self.model:
            raise RuntimeError("Model not loaded. Train or load first.")
        
        features = self.engineer_features(lead, context)
        proba = self.model.predict_proba(features)[0, 1]
        
        return MLScore(
            conversion_probability=round(proba, 4),
            confidence=self._estimate_confidence(features),
            feature_importance=self.model.feature_importances_.tolist(),
        )
    
    def _estimate_confidence(self, features: pd.DataFrame) -> float:
        """Estimate prediction confidence based on feature completeness."""
        # More complete data = higher confidence
        null_ratio = features.isnull().sum().sum() / features.size
        return max(0.5, 1.0 - null_ratio)
```

### 5.4 Feature Engineering Pipeline

```python
# features/pipeline.py

class FeaturePipeline:
    """Daily feature engineering pipeline for model training."""
    
    def __init__(self, db_url: str):
        self.engine = create_engine(db_url)
    
    def build_training_set(self, start_date: date, end_date: date) -> pd.DataFrame:
        """Build complete training dataset from FRGCRM and SurplusAI data."""
        
        query = """
        SELECT 
            c.*,
            l.score as lead_score,
            l.status as lead_status,
            l.created_at as lead_created_at,
            o.converted_to_revenue,
            o.revenue_amount,
            o.closed_at,
            cm.phone as claimant_phone,
            cm.email as claimant_email,
            cm.address as claimant_address,
            cm.bankruptcy_flag,
            cm.social_profiles,
            a.name as attorney_name,
            a.years_experience,
            a.success_rate,
            ct.county_name,
            ct.state_code,
            ct.population,
            ct.median_home_value,
            DATE_PART('day', o.closed_at - c.sale_date) as days_to_close,
            EXISTS(
                SELECT 1 FROM surplus_attorney_assignments aa 
                WHERE aa.case_id = c.id AND aa.status = 'active'
            ) as has_active_attorney
        FROM surplus_cases c
        LEFT JOIN surplus_leads l ON l.case_id = c.id
        LEFT JOIN frgcrm.outcomes o ON o.case_number = c.case_number
        LEFT JOIN frgcrm.claimants cm ON cm.case_id = c.id
        LEFT JOIN surplus_attorney_assignments aa ON aa.case_id = c.id
        LEFT JOIN surplus_attorneys a ON a.id = aa.attorney_id
        LEFT JOIN surplus_counties ct ON ct.county_code = c.county
        WHERE c.sale_date BETWEEN $1 AND $2
        AND o.converted_to_revenue IS NOT NULL
        """
        
        df = pd.read_sql(query, self.engine, params=[start_date, end_date])
        
        # Feature engineering
        df = self._add_temporal_features(df)
        df = self._add_aggregate_features(df)
        df = self._add_cross_county_features(df)
        
        return df
    
    def _add_temporal_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Add time-based features."""
        df['sale_day_of_week'] = df['sale_date'].dt.dayofweek
        df['sale_month'] = df['sale_date'].dt.month
        df['sale_quarter'] = df['sale_date'].dt.quarter
        df['sale_is_q4'] = (df['sale_month'] >= 10).astype(int)
        df['days_since_sale'] = (pd.Timestamp.now() - df['sale_date']).dt.days
        return df
    
    def _add_aggregate_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Add county-level aggregate features."""
        county_stats = df.groupby('county_name').agg({
            'surplus_amount': ['mean', 'median', 'std', 'count'],
            'converted_to_revenue': 'mean',
        }).round(2)
        county_stats.columns = [
            'county_avg_surplus', 'county_median_surplus', 
            'county_std_surplus', 'county_case_count',
            'county_conversion_rate'
        ]
        df = df.merge(county_stats, on='county_name', how='left')
        return df
```

### 5.5 Training Pipeline

```python
# ml/train.py

class ModelTrainer:
    """Orchestrates model training with hyperparameter optimization."""
    
    async def train(self, config: TrainingConfig) -> TrainingResult:
        """Full training pipeline."""
        # 1. Build training set
        df = FeaturePipeline(self.db_url).build_training_set(
            config.train_start, config.train_end
        )
        
        # 2. Split features/target
        X = df[config.feature_columns]
        y = df['converted_to_revenue']
        
        # 3. Train/validate split (stratified by county)
        X_train, X_val, y_train, y_val = train_test_split(
            X, y, test_size=0.2, stratify=df['county'], random_state=42
        )
        
        # 4. Hyperparameter optimization (Optuna)
        study = optuna.create_study(direction='maximize')
        study.optimize(
            lambda trial: self._objective(trial, X_train, y_train, X_val, y_val),
            n_trials=100
        )
        
        # 5. Train final model
        best_params = study.best_params
        model = xgb.XGBClassifier(**best_params)
        model.fit(X_train, y_train)
        
        # 6. Evaluate
        y_pred = model.predict_proba(X_val)[:, 1]
        auc = roc_auc_score(y_val, y_pred)
        
        # 7. Serialize
        model_path = f"/opt/models/surplusai/v{config.model_version}.joblib"
        joblib.dump(model, model_path)
        
        # 8. Store metadata
        await self._store_model_metadata(config, auc, best_params, model_path)
        
        return TrainingResult(
            model_version=config.model_version,
            auc=round(auc, 4),
            best_params=best_params,
            model_path=model_path,
            feature_count=len(config.feature_columns),
            training_examples=len(df),
        )
```

---

## 6. Attorney Routing Algorithm

### 6.1 Architecture

The routing engine matches scored leads to the best available attorney. It exists as an extension of the existing attorney_matcher.py engine in the portal:

```
Lead (> threshold) ──> Routing Engine
                           |
                           +-- Step 1: Pre-filter (jurisdiction, capacity, conflict check)
                           +-- Step 2: Score candidates (weighted dimensions)
                           +-- Step 3: Rank and select
                           +-- Step 4: Offer (notify, wait, escalate)
```

### 6.2 Configurable Weight System

All routing weights are configurable per organization and stored in the database:

```sql
CREATE TABLE public.routing_configs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID REFERENCES public.organizations(id) NOT NULL,
    name                VARCHAR(128) DEFAULT 'default',
    is_active           BOOLEAN DEFAULT TRUE,
    
    -- Dimension weights (must sum to 100)
    weights             JSONB NOT NULL DEFAULT '{
        "jurisdiction_match": 25,
        "expertise_match": 20,
        "performance_history": 20,
        "capacity_score": 15,
        "location_preference": 10,
        "recency_preference": 10
    }',
    
    -- Thresholds
    min_score_for_offer     NUMERIC(5,2) DEFAULT 60.00,
    offer_timeout_hours     INTEGER DEFAULT 48,
    max_candidates_returned INTEGER DEFAULT 5,
    
    -- Fallback strategy
    fallback_strategy        VARCHAR(32) DEFAULT 'next_best',
        -- next_best | round_robin | admin_notify
    
    -- Advanced options
    enforce_load_balancing  BOOLEAN DEFAULT TRUE,
    max_cases_per_attorney  INTEGER DEFAULT 10,
    prefer_in_county        BOOLEAN DEFAULT TRUE,
    
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organization_id, name)
);
```

### 6.3 Routing Algorithm

```python
# engine/routing_engine.py

class AttorneyRoutingEngine:
    """
    Weighted multi-dimensional attorney routing engine.
    Scores and ranks attorneys for each incoming lead.
    """
    
    DIMENSION_WEIGHTS = {
        "jurisdiction_match": 0.25,    # Licensed in correct state, county experience
        "expertise_match": 0.20,       # Practice area alignment
        "performance_history": 0.20,   # Historical win rate, recovery amount
        "capacity_score": 0.15,        # Available bandwidth
        "location_preference": 0.10,   # Physical proximity to county
        "recency_preference": 0.10,    # Fair distribution of assignments
    }
    
    async def route(self, lead: Lead, org_id: UUID) -> RoutingResult:
        """Route a lead to the best attorney."""
        
        # Step 1: Load organization routing config
        config = await self._load_routing_config(org_id)
        weights = config.get("weights", self.DIMENSION_WEIGHTS)
        
        # Step 2: Pre-filter candidates
        candidates = await self._prefilter_candidates(lead, config)
        
        if not candidates:
            return RoutingResult(
                status="no_candidates",
                message="No eligible attorneys found for this lead",
            )
        
        # Step 3: Score each candidate
        scored = []
        for attorney in candidates:
            score = await self._score_attorney(attorney, lead, weights)
            scored.append(score)
        
        # Step 4: Rank by composite score
        scored.sort(key=lambda x: x.composite_score, reverse=True)
        
        # Step 5: Select top candidate(s)
        top_candidate = scored[0]
        
        if top_candidate.composite_score < config.get("min_score_for_offer", 60):
            return RoutingResult(
                status="below_threshold",
                message=f"Best candidate score {top_candidate.composite_score} below threshold",
                candidates=scored[:config.get("max_candidates_returned", 5)],
            )
        
        # Step 6: Create assignment
        assignment = await self._create_assignment(
            lead=lead,
            attorney=top_candidate.attorney,
            score=top_candidate,
            method="ai_routed",
            config=config,
        )
        
        return RoutingResult(
            status="assigned",
            assignment_id=assignment.id,
            attorney=top_candidate.attorney,
            score=top_candidate,
            candidates=scored[:3],  # Top 3 for transparency
        )
    
    async def _prefilter_candidates(self, lead: Lead, config: dict) -> list[Attorney]:
        """Apply hard filters before scoring."""
        
        query = """
        SELECT a.*, al.state, al.bar_number, aa.status as availability_status,
               aa.max_active_cases, aa.current_active_cases,
               COALESCE(ps.composite_score, 0) as performance_score
        FROM marketplace.attorneys a
        JOIN marketplace.attorney_bar_licenses al ON al.attorney_id = a.id
        LEFT JOIN marketplace.attorney_availability aa ON aa.attorney_id = a.id
        LEFT JOIN marketplace.performance_scores ps ON ps.attorney_id = a.id
            AND ps.score_date = CURRENT_DATE
            AND ps.period_type = 'rolling_90'
        WHERE a.onboarding_status = 'active'
          AND al.state = $1                                    -- Licensed in case state
          AND al.verification_status = 'verified'              -- License verified
          AND (aa.status IS NULL OR aa.status = 'accepting')   -- Accepting cases
          AND (aa.current_active_cases < aa.max_active_cases)  -- Under capacity
          AND a.id NOT IN (                                    -- No conflict of interest
              SELECT attorney_id FROM marketplace.conflict_of_interest
              WHERE claimant_name ILIKE $2
                 OR property_address ILIKE $3
          )
        ORDER BY ps.composite_score DESC
        LIMIT 20
        """
        
        rows = await self.db.fetch(query, 
            lead.state, 
            f"%{lead.claimant_name}%",
            f"%{lead.property_address}%",
        )
        
        return [Attorney(**row) for row in rows]
    
    async def _score_attorney(self, attorney: Attorney, lead: Lead, weights: dict) -> AttorneyScore:
        """Compute multi-dimensional score for one attorney."""
        
        dimensions = {}
        
        # Dimension 1: Jurisdiction Match (0-100)
        jur_score = 100
        if attorney.primary_state != lead.state:
            jur_score -= 30  # Out-of-state penalty
        if lead.county not in attorney.counties_practiced:
            jur_score -= 15  # Never worked this county
        
        # Bonus for county experience
        county_cases = await self._county_case_history(attorney.id, lead.county)
        jur_score += min(10, county_cases * 2)  # Up to 10 bonus points
        
        dimensions["jurisdiction_match"] = min(100, jur_score)
        
        # Dimension 2: Expertise Match (0-100)
        expertise = attorney.practice_areas or []
        if lead.sale_type in expertise:
            dimensions["expertise_match"] = 100
        elif "surplus_funds_collection" in expertise:
            dimensions["expertise_match"] = 80  # General surplus = good
        else:
            dimensions["expertise_match"] = 40
        
        # Dimension 3: Performance History (0-100)
        perf = attorney.performance_score or 50
        dimensions["performance_history"] = perf
        
        # Dimension 4: Capacity Score (0-100)
        capacity_pct = (attorney.current_active_cases / max(attorney.max_active_cases, 1)) * 100
        dimensions["capacity_score"] = max(0, 100 - capacity_pct)
        
        # Dimension 5: Location Preference (0-100)
        if lead.county == attorney.home_county:
            dimensions["location_preference"] = 100
        elif lead.state == attorney.home_state:
            dimensions["location_preference"] = 70
        else:
            dimensions["location_preference"] = 40
        
        # Dimension 6: Recency Preference (0-100)
        hours_since_last = await self._hours_since_last_assignment(attorney.id)
        dimensions["recency_preference"] = min(100, hours_since_last / 24 * 10)
        
        # Composite: weighted sum
        composite = sum(
            dimensions[dim] * weights.get(dim, 0) * 100 
            for dim in dimensions
        )
        
        return AttorneyScore(
            attorney=attorney,
            composite_score=round(composite, 2),
            dimensions=dimensions,
        )
```

---

## 7. Document Automation Pipeline

### 7.1 Architecture

Document automation spans three services: the portal template engine, Docuseal (:3010) for e-signatures, and InsForge (:7130) for secure storage.

```
Template DB ──> Jinja2 Rendering ──> PDF Generation ──> Docuseal (:3010)
                     │                                        │
                     │                                   E-signature workflow
                     │                                        │
                     │                                   Webhook callback
                     │                                        │
                     └──────────> InsForge (:7130) <──────────┘
                                      │
                                 Secure storage
                                 (encrypted at rest)
```

### 7.2 Template Engine

```python
# services/document_automation.py

class DocumentAutomationService:
    """Generate, sign, and store legal documents."""
    
    async def generate_document(
        self, 
        template_id: UUID, 
        case_data: dict, 
        tenant_schema: str
    ) -> GeneratedDocument:
        """Fill a county-specific template with case data and generate PDF."""
        
        # 1. Load template
        template = await self._load_template(template_id, tenant_schema)
        
        # 2. Validate required fields are present
        missing = [
            f for f in template.fields_required 
            if f not in case_data or case_data[f] is None
        ]
        if missing:
            raise ValidationError(f"Missing required fields: {missing}")
        
        # 3. Render with Jinja2
        jinja_template = Template(template.template_body)
        rendered_html = jinja_template.render(**case_data)
        
        # 4. Convert to PDF (WeasyPrint)
        pdf_bytes = self._html_to_pdf(rendered_html)
        
        # 5. Generate filename
        filename = f"{case_data['case_number']}_{template.document_type}_{datetime.now():%Y%m%d}.pdf"
        
        # 6. Store temporarily (for Docuseal submission)
        temp_url = await self._store_temp(pdf_bytes, filename)
        
        return GeneratedDocument(
            filename=filename,
            pdf_bytes=pdf_bytes,
            temp_url=temp_url,
            page_count=self._count_pages(pdf_bytes),
        )
    
    async def send_for_signature(
        self,
        document: GeneratedDocument,
        signers: list[Signer],
        case_assignment_id: UUID,
    ) -> SignatureRequest:
        """Send document to Docuseal for e-signature."""
        
        # POST to Docuseal API
        async with httpx.AsyncClient() as client:
            response = await client.post(
                "http://127.0.0.1:3010/api/submissions",
                json={
                    "template_id": None,  # Using PDF, not template
                    "send_email": True,
                    "submitters": [
                        {
                            "name": signer.name,
                            "email": signer.email,
                            "role": signer.role,  # "claimant" or "attorney"
                        }
                        for signer in signers
                    ],
                    "files": [
                        {
                            "name": document.filename,
                            "url": document.temp_url,
                        }
                    ],
                    "metadata": {
                        "case_assignment_id": str(case_assignment_id),
                        "system": "surplusai",
                    }
                },
                headers={
                    "X-Auth-Token": self.docuseal_api_key,
                }
            )
            result = response.json()
        
        return SignatureRequest(
            submission_id=result["id"],
            status="sent",
            signing_urls={s.role: s.signing_url for s in result["submitters"]},
        )
    
    async def handle_docuseal_webhook(self, payload: dict) -> None:
        """Process Docuseal completion webhook."""
        
        submission_id = payload["submission_id"]
        status = payload["status"]  # "completed", "declined", "expired"
        
        if status == "completed":
            # Download signed PDF
            signed_pdf = await self._download_signed_pdf(submission_id)
            
            # Store in InsForge
            storage_result = await self._store_in_insforge(
                pdf_bytes=signed_pdf,
                case_assignment_id=payload["metadata"]["case_assignment_id"],
                document_type="signed_agreement",
            )
            
            # Update case_documents table
            await self._update_document_status(
                submission_id=submission_id,
                status="signed",
                storage_url=storage_result.url,
            )
            
            # Update case assignment status
            await self._advance_case_stage(
                case_assignment_id=payload["metadata"]["case_assignment_id"],
                new_stage="documents_signed",
            )
    
    async def _store_in_insforge(
        self, 
        pdf_bytes: bytes, 
        case_assignment_id: UUID,
        document_type: str,
    ) -> StorageResult:
        """Store signed document in InsForge (:7130)."""
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                "http://localhost:7130/api/storage",
                files={"file": ("document.pdf", pdf_bytes, "application/pdf")},
                data={
                    "case_id": str(case_assignment_id),
                    "document_type": document_type,
                    "encrypt": "true",
                },
                headers={
                    "Authorization": f"Bearer {self.insforge_api_key}",
                }
            )
            return StorageResult(url=response.json()["url"])
```

### 7.3 Document Types

| Document Type | Template Required | Signers | Storage in InsForge | Trigger Event |
|--------------|-------------------|---------|---------------------|---------------|
| Representation Agreement | Yes (per county) | Claimant + Attorney | Encrypted | Case assignment accepted |
| Retention Agreement | Yes (per county) | Claimant + Attorney | Encrypted | Assignment active |
| Demand Letter | Yes (standard) | Attorney only | Encrypted | Case preparation |
| Court Filing | Generated ad-hoc | Attorney only | Encrypted | Filing deadline |
| Settlement Authorization | Yes (standard) | Claimant | Encrypted | Settlement offer |
| Release of Claims | Yes (standard) | Claimant | Encrypted | Recovery completed |
| Pro Hac Vice Motion | Yes (per state) | Attorney only | Encrypted | Multi-state case |
| Revenue Sharing Agreement | Yes (standard) | Attorney + Admin | Encrypted | Attorney onboarding |

### 7.4 Filing Calendar & Deadline Tracking

```sql
CREATE TABLE tenant_{org_id}.calendar_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id             UUID NOT NULL REFERENCES tenant_{org_id}.cases(id),
    event_type          VARCHAR(64) NOT NULL,
        -- filing_deadline | hearing_date | response_due | status_check | statute_of_limitations
    title               VARCHAR(256) NOT NULL,
    description         TEXT,
    due_date            TIMESTAMPTZ NOT NULL,
    reminder_schedule   INTEGER[] DEFAULT '{14, 7, 3, 1}',  -- Days before to remind
    reminders_sent      INTEGER[] DEFAULT '{}',
    completed_at        TIMESTAMPTZ,
    assigned_attorney_id UUID,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Notification worker: checks every 30 minutes for upcoming deadlines
-- Python pseudocode:
async def deadline_notification_worker():
    while True:
        upcoming = await db.fetch("""
            SELECT ce.*, c.case_number, c.county, c.state, 
                   u.email, u.phone
            FROM calendar_events ce
            JOIN cases c ON c.id = ce.case_id
            LEFT JOIN users u ON u.id = ce.assigned_attorney_id
            WHERE ce.completed_at IS NULL
              AND ce.due_date BETWEEN NOW() AND NOW() + INTERVAL '14 days'
              AND NOT (ce.reminders_sent @> ARRAY[EXTRACT(DAY FROM ce.due_date - NOW())::INT])
        """)
        
        for event in upcoming:
            days_remaining = (event.due_date - datetime.now()).days
            if days_remaining in event.reminder_schedule:
                await send_notification(
                    user=event.user,
                    channel="email",
                    subject=f"Deadline approaching: {event.title}",
                    body=f"Case {event.case_number} - {event.title} due in {days_remaining} days",
                )
                # Update reminders_sent array
                await db.execute("""
                    UPDATE calendar_events 
                    SET reminders_sent = reminders_sent || ARRAY[$1]
                    WHERE id = $2
                """, days_remaining, event.id)
        
        await asyncio.sleep(1800)  # Check every 30 minutes
```

---

## 8. Billing & Subscription Architecture

### 8.1 Tiered Pricing Model

SurplusAI uses Stripe for payment processing with a tiered subscription model:

| Tier | Price | Monthly Case Limit | County Limit | Users | Document Gen | API Calls |
|------|-------|-------------------|-------------|-------|-------------|-----------|
| Basic (Freemium) | $0 | 50 | 1 | 1 | 5 | 100 |
| Pro | $997/mo | 500 | 5 | 5 | 50 | 1,000 |
| Enterprise | $2,997/mo | 5,000 | 50 | 25 | 500 | 10,000 |
| White-Label | $4,997/mo | Unlimited | Unlimited | Unlimited | Unlimited | 100,000 |

### 8.2 Stripe Integration Architecture

```
surplusai-portal-api (:8103)
  |
  +-- Stripe SDK (server-side)
  |     |
  |     +-- Products & Prices (configured in Stripe Dashboard)
  |     +-- Checkout Sessions (annual/monthly)
  |     +-- Webhooks (async event processing)
  |     +-- Customer Portal (self-service)
  |
  Stripe events:
  - customer.subscription.created
  - customer.subscription.updated
  - customer.subscription.deleted
  - invoice.paid
  - invoice.payment_failed
  - checkout.session.completed
```

### 8.3 Subscription Lifecycle

```
Signup
  |
  v
Trial (14 days, all Pro features)
  |
  +-- Subscribe -> Active (Stripe Checkout)
  |     |
  |     +-- Invoice paid -> Remains active
  |     +-- Invoice failed -> Grace period (5 days)
  |     |     |
  |     |     +-- Payment retry (3 attempts, 72h) -> Active
  |     |     +-- All failed -> Past Due -> Suspended
  |     |
  |     +-- Upgrade -> Prorated -> New plan active
  |     +-- Downgrade -> End of period -> New plan
  |     +-- Cancel -> End of period -> Expired
  |
  +-- No subscribe -> Trial ends -> Limited (Basic tier)
```

### 8.4 Entitlement Enforcement

Feature gating is enforced at the API layer via FastAPI middleware:

```python
# middleware/entitlement.py

class EntitlementMiddleware(BaseHTTPMiddleware):
    """Enforce plan limits per API request."""
    
    PLAN_LIMITS = {
        "basic": {
            "monthly_cases": 50,
            "county_adapters": 1,
            "users": 1,
            "documents_per_month": 5,
            "api_calls_per_month": 100,
            "white_label": False,
            "saml_sso": False,
            "custom_adapter": False,
        },
        "pro": {
            "monthly_cases": 500,
            "county_adapters": 5,
            "users": 5,
            "documents_per_month": 50,
            "api_calls_per_month": 1000,
            "white_label": False,
            "saml_sso": False,
            "custom_adapter": False,
        },
        "enterprise": {
            "monthly_cases": 5000,
            "county_adapters": 50,
            "users": 25,
            "documents_per_month": 500,
            "api_calls_per_month": 10000,
            "white_label": False,
            "saml_sso": True,
            "custom_adapter": True,
        },
        "white_label": {
            "monthly_cases": 1000000,  # Effectively unlimited
            "county_adapters": 9999,
            "users": 9999,
            "documents_per_month": 99999,
            "api_calls_per_month": 100000,
            "white_label": True,
            "saml_sso": True,
            "custom_adapter": True,
        },
    }
    
    async def dispatch(self, request: Request, call_next):
        # Extract org_id from JWT
        org_id = request.state.user.get("organization_id")
        
        # Get subscription + plan
        subscription = await self._get_subscription(org_id)
        plan = self.PLAN_LIMITS.get(subscription.plan_code, self.PLAN_LIMITS["basic"])
        
        # Check usage limits
        endpoint = request.url.path
        method = request.method
        
        if method in ("POST", "PUT") and "cases" in endpoint:
            await self._check_case_limit(org_id, plan)
        
        if "adapters" in endpoint and method in ("POST", "PUT"):
            await self._check_adapter_limit(org_id, plan)
        
        if "documents" in endpoint and method == "POST":
            await self._check_document_limit(org_id, plan)
        
        if "users" in endpoint and method == "POST":
            await self._check_user_limit(org_id, plan)
        
        # Check feature access
        if "saml" in endpoint or "oidc" in endpoint:
            if not plan["saml_sso"]:
                raise HTTPException(402, "SSO requires Enterprise plan. Please upgrade.")
        
        if "white-label" in endpoint or "custom-domain" in endpoint:
            if not plan["white_label"]:
                raise HTTPException(402, "White-label requires Enterprise plan. Please upgrade.")
        
        # Attach plan to request state for downstream use
        request.state.plan = plan
        
        return await call_next(request)
```

### 8.5 Usage Metering

```sql
CREATE TABLE public.usage_records (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID REFERENCES public.organizations(id) NOT NULL,
    metric              VARCHAR(64) NOT NULL,
        -- cases_scraped | cases_parsed | leads_scored | documents_generated | api_calls
    quantity            INTEGER NOT NULL DEFAULT 1,
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Monthly rollup for billing
CREATE MATERIALIZED VIEW public.usage_monthly AS
SELECT 
    organization_id,
    metric,
    DATE_TRUNC('month', recorded_at) AS month,
    SUM(quantity) AS total
FROM public.usage_records
GROUP BY organization_id, metric, DATE_TRUNC('month', recorded_at);

-- Check usage against plan limits:
SELECT COALESCE(SUM(quantity), 0) as monthly_cases
FROM public.usage_records
WHERE organization_id = $1
  AND metric = 'cases_scraped'
  AND recorded_at >= DATE_TRUNC('month', NOW());
```

### 8.6 Admin Billing Dashboard Metrics

| Metric | Query | Target |
|--------|-------|--------|
| Monthly Recurring Revenue (MRR) | `SELECT SUM(price_cents) FROM subscriptions JOIN plans WHERE status='active'` | Track |
| Active Subscriptions | `SELECT COUNT(*) FROM subscriptions WHERE status='active'` | Track |
| Churn Rate | Monthly canceled / monthly active at start | <5% |
| Trials Converted | Trials started -> converted to paid in 14 days | >20% |
| ARPU | MRR / active subscriptions | Track by tier |
| Usage vs. Plan | Usage records vs. plan limits | <80% (room to grow) |

---

## 9. API Gateway Design

### 9.1 Gateway Architecture

All SurplusAI API traffic routes through a layered gateway:

```
surplusai.io
  |
Cloudflare (Edge)
  - DNS resolution
  - DDoS protection (L3/L4/L7)
  - WAF rules (SQL injection, XSS, bot detection)
  - TLS termination
  - Geo-blocking (optional per tenant)
  - Caching (static assets, API responses with TTL)
  - Rate limiting (edge-level: 1000 req/s per IP)
  |
Traefik (L7 Router on AIOPS)
  - Path-based routing to services
  - API rate limiting (organization-level)
  - Basic auth for admin endpoints
  - Request logging
  - Circuit breaking
  |
surplusai-portal-api (:8103) — FastAPI
  - JWT validation
  - RBAC enforcement
  - Entitlement checks
  - Request validation
  - Rate limiting (user-level)
```

### 9.2 Rate Limiting Strategy

Four tiers of rate limiting, enforced at different layers:

| Layer | Scope | Limit | Enforced By | Response |
|-------|-------|-------|-------------|----------|
| Edge | Per IP | 1,000 req/s | Cloudflare WAF | 429 + Retry-After |
| Organization | Per API key | 100 req/s | Traefik middleware | 429 + Retry-After |
| User | Per JWT | 30 req/s | FastAPI middleware | 429 + Retry-After |
| Endpoint | Per route | Varies | FastAPI decorator | 429 + Retry-After |

```python
# middleware/rate_limit.py

from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

# Organization-level rate limiter (Redis-backed)
limiter = Limiter(
    key_func=lambda: request.state.user.get("organization_id", "anonymous"),
    storage_uri="redis://127.0.0.1:6379/0",
    strategy="fixed-window",
)

@app.get("/api/v1/cases")
@limiter.limit("30/second")
async def list_cases(request: Request):
    ...

# Query-level rate limit (prevent expensive queries)
@app.get("/api/v1/leads/search")
@limiter.limit("5/minute")
async def search_leads(request: Request):
    ...

# Admin endpoints: stricter limits
@app.post("/api/v1/admin/adapters")
@limiter.limit("10/minute")
async def create_adapter(request: Request):
    ...
```

### 9.3 API Request Quotas

Usage-based quotas supplement rate limits:

```python
# middleware/quota.py

class QuotaMiddleware:
    """Track and enforce monthly API call quotas per plan."""
    
    async def check_quota(self, request: Request):
        org_id = request.state.user.get("organization_id")
        plan = request.state.plan
        
        # Count API calls this month
        monthly_calls = await db.fetchval("""
            SELECT COALESCE(SUM(quantity), 0)
            FROM usage_records
            WHERE organization_id = $1
              AND metric = 'api_calls'
              AND recorded_at >= DATE_TRUNC('month', NOW())
        """, org_id)
        
        limit = plan["api_calls_per_month"]
        
        if monthly_calls >= limit:
            raise HTTPException(
                status_code=429,
                detail={
                    "error": "monthly_quota_exceeded",
                    "message": f"Monthly API call limit of {limit} exceeded. Upgrade your plan.",
                    "limit": limit,
                    "usage": monthly_calls,
                    "reset_date": next_month_start().isoformat(),
                }
            )
        
        # Record this call
        await db.execute("""
            INSERT INTO usage_records (organization_id, metric, quantity)
            VALUES ($1, 'api_calls', 1)
        """, org_id)
```

### 9.4 API Versioning

```
/api/v1/...   # Current stable version
/api/v2/...   # Future version (when needed)
/api/...      # Redirects to latest stable

Version strategy:
- V1: current (immutable, no breaking changes after GA)
- V2: planned for Month 9+ (advanced filtering, streaming, webhooks v2)
- Deprecation: 6-month notice, sunset header in responses
```

### 9.5 API Documentation

All endpoints documented via OpenAPI 3.0 (auto-generated by FastAPI) at `/docs` and `/redoc`:

```python
# FastAPI auto-generates OpenAPI spec
from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi

app = FastAPI(
    title="SurplusAI Enterprise API",
    description="Enterprise surplus funds intelligence platform. Requires authentication.",
    version="1.0.0",
    docs_url="/api/v1/docs",
    redoc_url="/api/v1/redoc",
    openapi_url="/api/v1/openapi.json",
)
```

---

## 10. Enterprise SLA Framework

### 10.1 Service Level Objectives

| Metric | Target | Measurement | Window |
|--------|--------|-------------|--------|
| API Uptime | 99.5% | Prometheus UP metric | Monthly rolling |
| API Response Time (p95) | <500ms | Prometheus histogram | 5-minute buckets |
| API Response Time (p99) | <2s | Prometheus histogram | 5-minute buckets |
| Scraper Freshness | <24h from source | last_success_at | Per adapter |
| Parser Throughput | <5 min per document | request duration | Per document |
| Lead Scoring Latency | <2s per score | request duration | Per request |
| Document Generation | <30s per document | request duration | Per document |
| Search Query Latency | <3s | request duration | p95 |

### 10.2 Incident Response Tiers

| Severity | Definition | Response Time | Update Frequency | Escalation Path |
|----------|-----------|--------------|-----------------|-----------------|
| P0 (Critical) | Platform down, all tenants affected | 15 min | Every 30 min | Superadmin -> Wheeler Brain OS |
| P1 (High) | Feature degradation, major tenant affected | 1 hour | Every 2 hours | Attorney admin -> Engineer |
| P2 (Medium) | Feature degradation, single tenant | 4 hours | Daily | Support -> Engineer |
| P3 (Low) | Cosmetic, documentation, non-functional | 24 hours | Weekly | Self-service |

### 10.3 SLA Credits

If SLOs are not met, tenants receive service credits:

| Monthly Uptime | Credit |
|---------------|--------|
| 99.0% - 99.49% | 10% credit |
| 98.0% - 98.99% | 25% credit |
| < 98.0% | 50% credit |
| < 95.0% | 100% credit (month free) |

**Measurement**: Uptime measured by Prometheus blackbox-exporter probing `/api/v1/health` every 30 seconds from two independent locations.

### 10.4 Health Check Endpoint

All SurplusAI services implement a standardized health check:

```python
# routes/health.py

@app.get("/api/v1/health")
async def health_check():
    """Health check endpoint for load balancers and monitoring."""
    
    checks = {
        "status": "healthy",
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat(),
        "checks": {},
    }
    
    # Database connectivity
    try:
        await db.execute("SELECT 1")
        checks["checks"]["database"] = {"status": "healthy", "latency_ms": 0}
    except Exception as e:
        checks["checks"]["database"] = {"status": "degraded", "error": str(e)}
        checks["status"] = "degraded"
    
    # LiteLLM connectivity
    try:
        async with httpx.AsyncClient() as client:
            r = await client.get("http://127.0.0.1:4049/v1/models", timeout=2)
            checks["checks"]["litellm"] = {"status": "healthy" if r.status_code == 200 else "degraded"}
    except Exception as e:
        checks["checks"]["litellm"] = {"status": "degraded", "error": str(e)}
        checks["status"] = "degraded"
    
    # Neo4j connectivity
    try:
        async with Neo4jConnection("bolt://127.0.0.1:7687") as conn:
            await conn.run("RETURN 1")
        checks["checks"]["neo4j"] = {"status": "healthy"}
    except Exception as e:
        checks["checks"]["neo4j"] = {"status": "degraded", "error": str(e)}
        checks["status"] = "degraded"
    
    # Docuseal connectivity
    try:
        async with httpx.AsyncClient() as client:
            r = await client.get("http://127.0.0.1:3010/health", timeout=2)
            checks["checks"]["docuseal"] = {"status": "healthy" if r.status_code == 200 else "degraded"}
    except Exception as e:
        checks["checks"]["docuseal"] = {"status": "degraded", "error": str(e)}
    
    # Queue depth
    queue_depth = await self._get_parse_queue_depth()
    if queue_depth > 1000:
        checks["checks"]["parse_queue"] = {"status": "warning", "depth": queue_depth}
    else:
        checks["checks"]["parse_queue"] = {"status": "healthy", "depth": queue_depth}
    
    http_status = 200 if checks["status"] == "healthy" else 503
    return JSONResponse(content=checks, status_code=http_status)
```

### 10.5 Monitoring & Alerting

| Alert | Condition | Severity | Notification |
|-------|-----------|----------|-------------|
| API Down | Health check fails 3 consecutive times | P0 | PagerDuty + SMS + Slack |
| Response Time Degraded | p95 > 1s for 5 minutes | P1 | Slack + Email |
| Database Connection Failure | Connection pool exhausted | P0 | PagerDuty + SMS |
| Scraper Adapter Failure | >50% of adapters failing | P1 | Slack + Email |
| Parse Queue Backup | Queue depth > 1000 | P2 | Slack |
| SSL Certificate Expiry | < 7 days remaining | P1 | Slack + Email |
| Disk Space | < 10% free | P2 | Slack |
| Memory Pressure | > 85% used | P2 | Slack |

---

## 11. Capacity Planning (200,000 Cases/Month)

### 11.1 Current Infrastructure Headroom

**AIOPS Node (5.78.140.118) -- 30 GB RAM, 16 vCPUs, 338 GB SSD:**

| Resource | Current Usage | Available | Headroom |
|----------|--------------|-----------|----------|
| CPU | ~20% aggregate (3.2 vCPUs) | 12.8 vCPUs | 80% |
| RAM | ~15 GB (all services) | 15 GB | 50% |
| Disk | 61 GB used | 277 GB | 82% |

**frgops-standby PostgreSQL (:5433):**
- Current: 122 case records, ~2 MB
- Target: 200,000 cases/month = ~2M cases/year = ~80 GB/year at scale
- Note: Document blobs stored separately in InsForge/object storage, not Postgres

### 11.2 Projected Growth

| Metric | Month 1 | Month 3 | Month 6 | Month 12 |
|--------|---------|---------|---------|----------|
| Cases scraped | 5,000 | 25,000 | 75,000 | 200,000 |
| Documents parsed | 5,000 | 25,000 | 75,000 | 200,000 |
| Leads scored | 3,000 | 15,000 | 45,000 | 120,000 |
| Lead storage (DB) | 500 MB | 2.5 GB | 7.5 GB | 20 GB |
| Document storage (InsForge) | 5 GB | 25 GB | 75 GB | 200 GB |
| LLM API calls | 5,000/mo | 25,000/mo | 75,000/mo | 200,000/mo |
| Database connections (peak) | 50 | 75 | 100 | 150 |
| API requests/month | 10,000 | 100,000 | 300,000 | 1,000,000 |
| API requests/second (peak) | 5 | 25 | 75 | 200 |

### 11.3 Scaling Plan by Threshold

**Threshold 1: 25,000 cases/month (Month 3)**
- [ ] Separate SurplusAI database from shared frgcrm on frgops-standby
- [ ] Add dedicated `surplusai` database on same PostgreSQL instance
- [ ] Increase PgBouncer pool from 50 to 100 connections
- [ ] Monitor: DB CPU, IOPS, connection count

**Threshold 2: 75,000 cases/month (Month 6)**
- [ ] Deploy dedicated PostgreSQL 16 container for SurplusAI only
- [ ] Add read replica for reporting queries (Superset)
- [ ] Migrate document storage from local disk to S3-compatible (MinIO on COREDB)
- [ ] Scale parser-service to 2 PM2 instances
- [ ] Scale scoring-service to 2 PM2 instances
- [ ] Add Redis cluster for cache (currently single instance)
- [ ] Monitor: all metrics below 70% utilization

**Threshold 3: 200,000 cases/month (Month 12)**
- [ ] Database: connection pooling with PgBouncer, read replicas (2), partitioning by month
- [ ] Application: horizontal scale to 4-6 PM2 instances per service behind Traefik load balancer
- [ ] Cache: Redis cluster with 3 shards
- [ ] Object storage: MinIO distributed mode on COREDB
- [ ] Queue: Adapter execution distributed via Temporal with 10+ concurrent workers
- [ ] Neo4j: migrate from single instance to causal cluster (3 cores, 2 read replicas)
- [ ] Consider: Dedicated search (Elasticsearch/Meilisearch) for full-text case search

### 11.4 Database Partitioning Strategy

At 200,000 cases/month, the database requires partitioning:

```sql
-- Partition by month for cases table
CREATE TABLE tenant_{org_id}.cases (
    id              UUID NOT NULL,
    case_number     VARCHAR(128) NOT NULL,
    sale_date       DATE NOT NULL,
    -- ... other columns
    PRIMARY KEY (id, sale_date)
) PARTITION BY RANGE (sale_date);

-- Monthly partitions
CREATE TABLE tenant_{org_id}.cases_2026_01 PARTITION OF tenant_{org_id}.cases
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE tenant_{org_id}.cases_2026_02 PARTITION OF tenant_{org_id}.cases
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
-- ... automated partition creation via pg_partman

-- Partition by month for audit_log
CREATE TABLE tenant_{org_id}.audit_log (
    id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- ... other columns
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE tenant_{org_id}.audit_log_2026_01 PARTITION OF tenant_{org_id}.audit_log
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
```

### 11.5 LLM Cost Projection

At scale (200,000 documents/month):

| Model | Cost per 1K tokens (input) | Cost per 1K tokens (output) | Avg input tokens | Avg output tokens | Monthly Cost |
|-------|---------------------------|----------------------------|------------------|-------------------|-------------|
| DeepSeek V4 (current) | $0.0002 | $0.001 | 8,000 (doc text) | 500 (JSON) | ~$135/mo |
| Fine-tuned model (Phase 3) | $0.0005 | $0.002 | 4,000 (shorter prompts) | 300 (more concise) | ~$110/mo |

**Mitigations:**
- Prompt caching for repeated county instructions (LiteLLM supports)
- Batch processing during off-peak hours (Temporal scheduled workflows)
- Fine-tuned model reduces token count by 50% with county-specific knowledge
- Cache identical document extractions (same document hash from different sources)

---

## 12. Security Architecture

### 12.1 Zero-Trust Architecture

SurplusAI inherits and extends the Wheeler ecosystem zero-trust model:

```
Layer 1: Network (Enforced: Stage 2 hardening, QA 100/100)
  - All services bind to 127.0.0.1 (no public ports)
  - UFW default-deny incoming
  - Tailscale mesh for inter-node communication
  - Cloudflare WAF at edge (DDoS, bot, SQL injection, XSS)

Layer 2: Container/Process
  - Zero :latest Docker tags (all pinned)
  - PM2 env -i pattern for clean process state
  - Secrets in .env files with chmod 600
  - HEALTHCHECK on all containers

Layer 3: Application
  - JWT authentication (RS256 signed)
  - RBAC enforcement at middleware level
  - Rate limiting and quota enforcement
  - Input validation (Pydantic models in FastAPI)
  - SQL injection prevention (parameterized queries)

Layer 4: Data
  - Tenant isolation (schema-per-tenant / database-per-tenant)
  - PII isolation (separate encrypted columns, limited access)
  - Audit logging (all data access recorded)
  - Encryption at rest (LUKS on host, encrypted columns for PII)
```

### 12.2 PII Isolation Architecture

Personally Identifiable Information (claimant names, addresses, SSNs, attorney bar numbers) is isolated with column-level encryption:

```python
# security/pii_encryption.py

from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2

class PIIEncryption:
    """
    Column-level encryption for PII fields.
    Each tenant has a unique encryption key derived from a master key + tenant ID.
    """
    
    MASTER_KEY_ENV = "SURPLUSAI_PII_MASTER_KEY"
    
    @classmethod
    def get_tenant_key(cls, tenant_id: str) -> bytes:
        """Derive tenant-specific encryption key."""
        master_key = os.environ[cls.MASTER_KEY_ENV].encode()
        kdf = PBKDF2(
            algorithm=hashes.SHA256(),
            length=32,
            salt=tenant_id.encode(),
            iterations=100000,
        )
        return base64.urlsafe_b64encode(kdf.derive(master_key))
    
    @classmethod
    def encrypt_field(cls, plaintext: str, tenant_id: str) -> str:
        """Encrypt a PII field for storage."""
        if not plaintext:
            return None
        key = cls.get_tenant_key(tenant_id)
        f = Fernet(key)
        return f.encrypt(plaintext.encode()).decode()
    
    @classmethod
    def decrypt_field(cls, ciphertext: str, tenant_id: str) -> str:
        """Decrypt a PII field for display."""
        if not ciphertext:
            return None
        key = cls.get_tenant_key(tenant_id)
        f = Fernet(key)
        return f.decrypt(ciphertext.encode()).decode()
```

**PII database schema:**

```sql
-- PII fields stored encrypted in a separate, access-controlled table
CREATE TABLE tenant_{org_id}.claimant_pii (
    id                  UUID PRIMARY KEY,
    case_id             UUID NOT NULL REFERENCES tenant_{org_id}.cases(id),
    full_name_enc       TEXT NOT NULL,              -- Fernet encrypted
    ssn_hash            VARCHAR(128),               -- SHA-256 hash (for dedup, not reversible)
    ssn_enc             TEXT,                       -- Fernet encrypted (for reporting)
    phone_enc           TEXT,                       -- Fernet encrypted
    email_enc           TEXT,                       -- Fernet encrypted
    address_enc         TEXT,                       -- Fernet encrypted
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    accessed_at         TIMESTAMPTZ,                -- Track last PII access
    accessed_by         UUID,                       -- Who accessed PII last
    UNIQUE(case_id)
);

-- Access logging for PII (immutable)
CREATE TABLE tenant_{org_id}.pii_access_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL,
    action              VARCHAR(32) NOT NULL,        -- read | decrypt | export
    resource_type       VARCHAR(64) NOT NULL,        -- claimant | attorney
    resource_id         UUID NOT NULL,
    fields_accessed     TEXT[],                      -- Which PII fields were accessed
    ip_address          INET,
    user_agent          TEXT,
    accessed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 12.3 Audit Logging

Every data mutation is logged to the audit log with before/after values:

```sql
CREATE TABLE public.audit_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID REFERENCES public.organizations(id),
    actor_id            UUID,                        -- Who performed the action
    actor_type          VARCHAR(32),                 -- user | system | webhook | admin
    action              VARCHAR(64) NOT NULL,        -- create | update | delete | read | export
    resource_type       VARCHAR(64) NOT NULL,        -- case | lead | assignment | document | user
    resource_id         UUID NOT NULL,
    changes             JSONB,                       -- {field: {old: value, new: value}}
    metadata            JSONB,                       -- request_id, ip_address, user_agent
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Create monthly partitions (automated via pg_partman)
CREATE TABLE public.audit_log_2026_06 PARTITION OF public.audit_log
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- Critical indexes
CREATE INDEX idx_audit_org ON public.audit_log(organization_id, created_at DESC);
CREATE INDEX idx_audit_resource ON public.audit_log(resource_type, resource_id);
CREATE INDEX idx_audit_actor ON public.audit_log(actor_id, created_at DESC);
```

### 12.4 Data Retention

| Data Type | Retention | Deletion Policy |
|-----------|-----------|----------------|
| Case records | 7 years (or per agreement) | Soft-delete, then hard-delete after retention |
| PII data | 7 years (or per agreement) | Encrypted at rest, purged with case |
| Audit logs | 3 years | Partition drop after retention |
| Usage records | 13 months (billing audit) | Aggregated, then dropped |
| Training examples | Perpetual (de-identified) | PII stripped before storage |
| Session tokens | 7 days (refresh) | TTL-based expiry |
| Raw documents | 90 days after case closed | Purged after retention period |

### 12.5 API Security Headers

```python
# middleware/security_headers.py

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Apply security headers to all responses."""
    
    HEADERS = {
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "X-XSS-Protection": "1; mode=block",
        "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
        "Content-Security-Policy": (
            "default-src 'self'; "
            "script-src 'self'; "
            "style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data:; "
            "connect-src 'self' https://surplusai.io wss://surplusai.io; "
            "frame-ancestors 'none'"
        ),
        "Referrer-Policy": "strict-origin-when-cross-origin",
        "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
        "Cache-Control": "no-store, no-cache, must-revalidate",
    }
```

---

## 13. Implementation Roadmap & Phase Gates

### 13.1 Phase Gate Model

Each phase has defined exit criteria. No phase starts until the previous phase's gates are met.

### Phase 1: Foundation (Weeks 1-2)

**Objective**: Multi-tenant infrastructure, auth, and data pipeline basics.

**Deliverables:**
- [ ] Multi-tenant schema provisioning (schema-per-tenant + tenant middleware)
- [ ] RBAC implementation (4 roles with middleware enforcement)
- [ ] Native auth (email/password + JWT)
- [ ] County adapter framework: interface, base adapter, registry
- [ ] Top 5 county adapters (LA, Cook, Harris, Maricopa, Miami-Dade)
- [ ] LiteLLM connectivity validation (DeepSeek V4 via :4049)
- [ ] Basic scraper -> parser -> storage pipeline
- [ ] Health check endpoints for all services
- [ ] Prometheus metrics: adapter runs, cases collected, errors
- [ ] PM2 ecosystem config for: parser-service (:8104), scoring-service (:8105)
- [ ] Tenant provisioning API (admin endpoint)
- [ ] Neo4j case indexing (:7687)

**Phase 1 Gate Criteria:**
| Metric | Target | Measurement |
|--------|--------|-------------|
| Tenant provisioning | < 5 seconds from API call to live schema | End-to-end timing |
| Auth latency | < 100ms p95 for JWT validation | Prometheus histogram |
| Scraper uptime (top 5 adapters) | > 99% over 7 days | PM2 status |
| Parse throughput | > 100 documents/hour | Prometheus counter |
| API response time | < 200ms p95 | Prometheus histogram |
| PRs merged | All Phase 1 PRs passing CI + reviewed | GitHub status |

### Phase 2: Intelligence Engine (Weeks 3-4)

**Objective**: AI extraction pipeline, lead scoring, confidence system.

**Deliverables:**
- [ ] Parser service (:8104): full 5-stage pipeline
- [ ] Document classification (PDF text, scanned, HTML)
- [ ] DeepSeek extraction prompt system with few-shot examples
- [ ] Field-level validation rules
- [ ] Confidence scoring engine
- [ ] Human review queue API + admin UI
- [ ] Training data collection pipeline
- [ ] Scoring service (:8105): composite score formula
- [ ] Configurable scoring weights (stored in DB)
- [ ] Territory-based lead prioritization
- [ ] County adapter expansion to 50 counties (top by volume)

**Phase 2 Gate Criteria:**
| Metric | Target | Measurement |
|--------|--------|-------------|
| AI extraction auto-accept rate | > 75% across 1,000 documents | Training examples table |
| Extraction latency | < 10s per document (p95) | Service metrics |
| Document classification accuracy | > 95% | Validation set |
| Lead scoring latency | < 2s per score | Service metrics |
| Adaptors operational | 50 counties, < 5% error rate | Adapter health checks |
| Human review queue empty | < 100 pending items | DB query |

### Phase 3: Attorney Routing & CRM (Weeks 5-6)

**Objective**: Connect scored leads to attorneys with automated routing.

**Deliverables:**
- [ ] Attorney routing engine with 6 configurable dimensions
- [ ] Routing config per organization (weights table)
- [ ] Pre-filter pipeline (jurisdiction, capacity, conflict check)
- [ ] Offer management (create, accept, decline, timeout, reassign)
- [ ] Attorney capacity tracking
- [ ] FRGCRM bidirectional sync (leads out, outcomes in)
- [ ] Webhook system (extend existing push.py)
- [ ] n8n workflow templates (high-value alerts, weekly digest)
- [ ] Attorney dashboard v1 (my leads, my territory, my performance)
- [ ] Email notifications (SendGrid through existing usesend infrastructure)

**Phase 3 Gate Criteria:**
| Metric | Target | Measurement |
|--------|--------|-------------|
| Time-to-assignment | < 1 hour for score > 80 | Workflow metrics |
| Offer acceptance rate | > 60% | DB query |
| Auto-routing rate | > 90% of cases | Log analysis |
| FRGCRM sync latency | < 5 minutes | Monitoring |
| Webhook delivery success | > 99% | Retry log |

### Phase 4: Document Automation (Weeks 7-8)

**Objective**: Full document lifecycle from template generation to signed storage.

**Deliverables:**
- [ ] Document template system (Jinja2 + WeasyPrint PDF)
- [ ] County-specific template library (per document type)
- [ ] Docuseal integration (:3010): submission, signing, webhooks
- [ ] InsForge integration (:7130): encrypted signed document storage
- [ ] Filing deadline calendar with multi-escalation reminders
- [ ] Document status tracking UI (drafted -> sent -> signed -> filed)
- [ ] Superset dashboards (:8088): pipeline, forecast, attorney performance, county
- [ ] Real-time KPI WebSocket (extend ws.py)
- [ ] Executive report generator (weekly PDF export)

**Phase 4 Gate Criteria:**
| Metric | Target | Measurement |
|--------|--------|-------------|
| Document generation success | > 95% | Service metrics |
| E-signature turnaround | < 48 hours avg | Docuseal webhooks |
| Calendar reminder accuracy | 100% of deadlines notified | Audit log |
| Dashboard rendering | < 3s load time | Frontend metrics |

### Phase 5: Monetization (Weeks 9-10)

**Objective**: Tiered billing, self-service signup, and revenue operations.

**Deliverables:**
- [ ] Stripe integration: products, prices, checkout sessions
- [ ] Subscription lifecycle management (trial, active, past-due, canceled)
- [ ] Entitlement middleware (feature gating per plan)
- [ ] Usage metering and quota enforcement
- [ ] Self-service signup flow (basic tier)
- [ ] White-label onboarding flow (custom domain, logo, colors)
- [ ] Billing dashboard in admin console (MRR, churn, ARPU)
- [ ] SAML/OIDC SSO configuration UI (Enterprise tier)
- [ ] Admin billing management (credits, invoices, refunds)

**Phase 5 Gate Criteria:**
| Metric | Target | Measurement |
|--------|--------|-------------|
| Self-service signup | < 2 minutes to active account | End-to-end timing |
| Payment processing | < 30s (Stripe Checkout) | Monitoring |
| Entitlement enforcement | 100% of restricted endpoints | Integration tests |
| MRR | > $10,000 | Stripe dashboard |
| Churn rate | < 5% in first 60 days | Subscription table |

### Phase 6: Scale & Optimize (Weeks 11-12)

**Objective**: Performance optimization, compliance hardening, and scale readiness.

**Deliverables:**
- [ ] Database partitioning (monthly partitions for cases, audit_log)
- [ ] Read replica deployment for reporting queries
- [ ] Redis cluster migration (from single instance)
- [ ] PII encryption implementation (column-level Fernet)
- [ ] Audit log completeness verification
- [ ] Load testing to 200,000 cases/month equivalent
- [ ] SLA monitoring and reporting system
- [ ] Automated backup/restore testing
- [ ] Security review + penetration testing
- [ ] County adapter expansion to 500+ counties
- [ ] Performance optimization: query tuning, index analysis, cache tuning

**Phase 6 Gate Criteria:**
| Metric | Target | Measurement |
|--------|--------|-------------|
| Load test throughput | 200,000 cases/month equivalent | Load test results |
| P95 API response at load | < 500ms | Load test metrics |
| Database query time (p95) | < 100ms | PG statistics |
| Zero security findings (critical/high) | 0 | Pen test report |
| Backup restore time | < 1 hour for full DB | Restore test |
| County coverage | 500+ counties active | DB query |

### 13.2 Critical Path Dependency Graph

```
Phase 1 (Weeks 1-2): Foundation
  - Multi-tenant infra ──> BLOCKS ──> Phase 2 (tenant schemas needed for data)
  - Auth & RBAC ──> BLOCKS ──> Phase 3 (routing needs roles)
  - County adapters (5) ──> BLOCKS ──> Phase 2 (no data to parse)
  - LiteLLM validation ──> BLOCKS ──> Phase 2 (no AI extraction)
       │
       ▼
Phase 2 (Weeks 3-4): Intelligence
  - AI parsing pipeline ──> BLOCKS ──> Phase 3 (no structured leads)
  - Lead scoring engine ──> BLOCKS ──> Phase 3 (no score to route on)
  - County expansion (50) ──> PARALLEL with Phase 3
       │
       ▼
Phase 3 (Weeks 5-6): Routing
  - Attorney routing ──> BLOCKS ──> Phase 4 (need assigned pipeline)
  - CRM sync ──> PARALLEL with Phase 4
  - Webhook system ──> PARALLEL with Phase 4
       │
       ▼
Phase 4 (Weeks 7-8): Documents
  - Document automation ──> BLOCKS ──> Phase 5 (need billable feature)
  - Dashboards ──> PARALLEL with Phase 5
       │
       ▼
Phase 5 (Weeks 9-10): Monetization
  - Billing & subscriptions ──> BLOCKS ──> Phase 6 (need revenue to scale)
  - SSO ──> PARALLEL with Phase 6
       │
       ▼
Phase 6 (Weeks 11-12): Scale
  - Performance + security
  - County expansion to 500+
```

### 13.3 Success Metrics (North Star)

| Metric | Month 3 Target | Month 6 Target | Month 12 Target |
|--------|---------------|----------------|-----------------|
| Active tenants (paying) | 10 | 30 | 100 |
| Monthly cases scraped | 25,000 | 75,000 | 200,000 |
| AI parsing auto-accept rate | 80% | 90% | 95% |
| Leads scored per month | 15,000 | 45,000 | 120,000 |
| Leads assigned per month | 2,500 | 7,500 | 20,000 |
| Attorney acceptance rate | 60% | 70% | 80% |
| Avg time from scrape to assignment | < 6 hours | < 1 hour | < 15 minutes |
| MRR | $15,000 | $50,000 | $200,000+ |
| Gross margin (hosting cost / revenue) | < 30% | < 20% | < 15% |
| API uptime | 99.5% | 99.9% | 99.95% |

---

## Appendix A: Complete Schema DDL

### A.1 Reference Schema (public)

```sql
-- ============================================================
-- SURPLUSAI ENTERPRISE -- COMPLETE DDL
-- ============================================================

-- Organizations / Tenants
CREATE TABLE public.organizations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(256) NOT NULL,
    slug            VARCHAR(64) UNIQUE NOT NULL,
    tier            VARCHAR(32) NOT NULL DEFAULT 'pro',
    isolation_model VARCHAR(16) NOT NULL DEFAULT 'schema',  -- 'schema' or 'database'
    schema_name     VARCHAR(64) UNIQUE,                      -- For schema-per-tenant
    database_name   VARCHAR(64) UNIQUE,                      -- For database-per-tenant
    custom_domain   VARCHAR(256),
    logo_url        VARCHAR(512),
    primary_color   VARCHAR(7),                              -- Hex color for white-label
    is_active       BOOLEAN DEFAULT TRUE,
    settings        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Users (global)
CREATE TABLE public.users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(256) UNIQUE NOT NULL,
    password_hash   VARCHAR(256),                             -- NULL for SSO users
    first_name      VARCHAR(128),
    last_name       VARCHAR(128),
    avatar_url      VARCHAR(512),
    auth_provider   VARCHAR(32) DEFAULT 'native',             -- native | saml | oidc
    auth_provider_id VARCHAR(256),                            -- Subject ID from IdP
    is_active       BOOLEAN DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Organization memberships
CREATE TABLE public.organization_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role            VARCHAR(32) NOT NULL,                     -- superadmin | attorney_admin | attorney | viewer
    is_default      BOOLEAN DEFAULT FALSE,                    -- Default org for user
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organization_id, user_id)
);

-- Refresh tokens
CREATE TABLE public.refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token_hash      VARCHAR(256) NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked         BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_hash ON public.refresh_tokens(token_hash);

-- County adapters
CREATE TABLE public.county_adapters (
    county_code             VARCHAR(32) PRIMARY KEY,
    county_name             VARCHAR(128) NOT NULL,
    state_code              CHAR(2) NOT NULL,
    fips_code               VARCHAR(5),
    adapter_class           VARCHAR(128) NOT NULL,
    template_type           VARCHAR(64),
    base_url                VARCHAR(512),
    search_url_pattern      VARCHAR(512),
    detail_url_pattern      VARCHAR(512),
    auth_type               VARCHAR(32) DEFAULT 'none',
    auth_config             JSONB,
    enabled                 BOOLEAN DEFAULT FALSE,
    poll_interval_minutes   INTEGER DEFAULT 1440,
    rate_limit_rps          NUMERIC(4,1) DEFAULT 1.0,
    rate_limit_burst        INTEGER DEFAULT 2,
    backoff_minutes         INTEGER DEFAULT 30,
    max_retries             INTEGER DEFAULT 3,
    health_status           VARCHAR(32) DEFAULT 'unknown',
    last_run_at             TIMESTAMPTZ,
    last_success_at         TIMESTAMPTZ,
    last_error              TEXT,
    consecutive_errors      INTEGER DEFAULT 0,
    total_runs              INTEGER DEFAULT 0,
    successful_runs         INTEGER DEFAULT 0,
    failed_runs             INTEGER DEFAULT 0,
    cases_collected_total   INTEGER DEFAULT 0,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Document templates
CREATE TABLE public.document_templates (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    county_code     VARCHAR(32) REFERENCES public.county_adapters(county_code),
    document_type   VARCHAR(64) NOT NULL,
    template_body   TEXT NOT NULL,
    fields_required JSONB,
    fields_optional JSONB,
    version         INTEGER DEFAULT 1,
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Billing plans
CREATE TABLE public.billing_plans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_code       VARCHAR(32) UNIQUE NOT NULL,
    name            VARCHAR(128) NOT NULL,
    description     TEXT,
    price_cents     INTEGER NOT NULL,
    interval        VARCHAR(16) DEFAULT 'month',             -- month | year
    features        JSONB NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE,
    sort_order      INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Billing subscriptions
CREATE TABLE public.billing_subscriptions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id         UUID NOT NULL REFERENCES public.organizations(id),
    plan_id                 UUID NOT NULL REFERENCES public.billing_plans(id),
    status                  VARCHAR(32) DEFAULT 'active',
    current_period_start    DATE NOT NULL,
    current_period_end      DATE NOT NULL,
    trial_end               DATE,
    canceled_at             TIMESTAMPTZ,
    stripe_customer_id      VARCHAR(128),
    stripe_subscription_id  VARCHAR(128),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Usage records
CREATE TABLE public.usage_records (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id),
    metric          VARCHAR(64) NOT NULL,
    quantity        INTEGER NOT NULL DEFAULT 1,
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_usage_org_metric ON public.usage_records(organization_id, metric, recorded_at);

-- Monthly usage rollup
CREATE MATERIALIZED VIEW public.usage_monthly AS
SELECT 
    organization_id,
    metric,
    DATE_TRUNC('month', recorded_at) AS month,
    SUM(quantity) AS total
FROM public.usage_records
GROUP BY organization_id, metric, DATE_TRUNC('month', recorded_at);

-- Routing configurations
CREATE TABLE public.routing_configs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id         UUID NOT NULL REFERENCES public.organizations(id),
    name                    VARCHAR(128) DEFAULT 'default',
    is_active               BOOLEAN DEFAULT TRUE,
    weights                 JSONB NOT NULL,
    min_score_for_offer     NUMERIC(5,2) DEFAULT 60.00,
    offer_timeout_hours     INTEGER DEFAULT 48,
    max_candidates_returned INTEGER DEFAULT 5,
    fallback_strategy       VARCHAR(32) DEFAULT 'next_best',
    enforce_load_balancing  BOOLEAN DEFAULT TRUE,
    max_cases_per_attorney  INTEGER DEFAULT 10,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organization_id, name)
);

-- Training examples
CREATE TABLE public.training_examples (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    raw_document_hash   VARCHAR(64) NOT NULL,
    raw_document_text   TEXT,
    county_code         VARCHAR(32) NOT NULL,
    state_code          CHAR(2) NOT NULL,
    llm_extraction      JSONB NOT NULL,
    human_corrected     JSONB,
    reviewer_id         UUID REFERENCES public.users(id),
    reviewed_at         TIMESTAMPTZ,
    confidence_scores   JSONB,
    extraction_latency_ms INTEGER,
    used_in_training    BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(raw_document_hash)
);

-- Global audit log
CREATE TABLE public.audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id),
    actor_id        UUID,
    actor_type      VARCHAR(32),
    action          VARCHAR(64) NOT NULL,
    resource_type   VARCHAR(64) NOT NULL,
    resource_id     UUID NOT NULL,
    changes         JSONB,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- PII access log
CREATE TABLE public.pii_access_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id),
    user_id         UUID NOT NULL,
    action          VARCHAR(32) NOT NULL,
    resource_type   VARCHAR(64) NOT NULL,
    resource_id     UUID NOT NULL,
    fields_accessed TEXT[],
    ip_address      INET,
    user_agent      TEXT,
    accessed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### A.2 Tenant Schema Template

```sql
-- ============================================================
-- TENANT SCHEMA -- Created per organization
-- ============================================================

CREATE SCHEMA IF NOT EXISTS tenant_{org_id};

-- Cases
CREATE TABLE tenant_{org_id}.cases (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_number     VARCHAR(128) NOT NULL,
    property_address VARCHAR(512),
    surplus_amount  NUMERIC(12,2),
    sale_date       DATE,
    sale_type       VARCHAR(32),
    court_name      VARCHAR(256),
    county          VARCHAR(128),
    state           CHAR(2),
    trustee_name    VARCHAR(256),
    original_judgment NUMERIC(12,2),
    raw_data        JSONB,
    ingestion_method VARCHAR(32),                       -- scraped | api | manual | imported
    source_url      VARCHAR(512),
    doc_hash        VARCHAR(64),                        -- SHA-256 of source document
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(case_number, state, county)
) PARTITION BY RANGE (sale_date);

-- Leads
CREATE TABLE tenant_{org_id}.leads (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id         UUID NOT NULL REFERENCES tenant_{org_id}.cases(id),
    score           NUMERIC(5,2),
    score_breakdown JSONB,
    score_tier      VARCHAR(16),
    status          VARCHAR(32) DEFAULT 'new',          -- new | scored | assigned | contacted | represented | won | lost
    assigned_to     UUID,
    assigned_at     TIMESTAMPTZ,
    converted_at    TIMESTAMPTZ,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Attorney assignments
CREATE TABLE tenant_{org_id}.attorney_assignments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id         UUID NOT NULL REFERENCES tenant_{org_id}.leads(id),
    attorney_id     UUID NOT NULL,
    assignment_method VARCHAR(32),
    routing_score   NUMERIC(5,2),
    status          VARCHAR(32) DEFAULT 'pending',      -- pending | offered | accepted | declined | active | completed
    offered_at      TIMESTAMPTZ,
    accepted_at     TIMESTAMPTZ,
    declined_at     TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    timeout_at      TIMESTAMPTZ,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Documents
CREATE TABLE tenant_{org_id}.documents (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id             UUID NOT NULL REFERENCES tenant_{org_id}.cases(id),
    assignment_id       UUID REFERENCES tenant_{org_id}.attorney_assignments(id),
    document_type       VARCHAR(64) NOT NULL,
    status              VARCHAR(32) DEFAULT 'draft',    -- draft | generated | sent | signed | completed | void
    docuseal_submission_id VARCHAR(128),
    insforge_url        VARCHAR(512),
    generated_at        TIMESTAMPTZ,
    sent_at             TIMESTAMPTZ,
    signed_at           TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    version             SMALLINT DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Calendar events
CREATE TABLE tenant_{org_id}.calendar_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id             UUID NOT NULL REFERENCES tenant_{org_id}.cases(id),
    event_type          VARCHAR(64) NOT NULL,
    title               VARCHAR(256) NOT NULL,
    description         TEXT,
    due_date            TIMESTAMPTZ NOT NULL,
    reminder_schedule   INTEGER[] DEFAULT '{14,7,3,1}',
    reminders_sent      INTEGER[] DEFAULT '{}',
    completed_at        TIMESTAMPTZ,
    assigned_attorney_id UUID,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Claimant PII (encrypted)
CREATE TABLE tenant_{org_id}.claimant_pii (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id             UUID NOT NULL REFERENCES tenant_{org_id}.cases(id) ON DELETE CASCADE,
    full_name_enc       TEXT,
    ssn_hash            VARCHAR(128),
    ssn_enc             TEXT,
    phone_enc           TEXT,
    email_enc           TEXT,
    address_enc         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    accessed_at         TIMESTAMPTZ,
    accessed_by         UUID,
    UNIQUE(case_id)
);

-- Notifications
CREATE TABLE tenant_{org_id}.notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    notification_type VARCHAR(64) NOT NULL,
    title           VARCHAR(256) NOT NULL,
    body            TEXT,
    data            JSONB,
    is_read         BOOLEAN DEFAULT FALSE,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON tenant_{org_id}.notifications(user_id, is_read, created_at DESC);

-- Tenant audit log
CREATE TABLE tenant_{org_id}.audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id        UUID,
    actor_type      VARCHAR(32),
    action          VARCHAR(64) NOT NULL,
    resource_type   VARCHAR(64) NOT NULL,
    resource_id     UUID NOT NULL,
    changes         JSONB,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Indexes
CREATE INDEX idx_cases_county ON tenant_{org_id}.cases(county, state);
CREATE INDEX idx_cases_sale_date ON tenant_{org_id}.cases(sale_date DESC);
CREATE INDEX idx_cases_surplus ON tenant_{org_id}.cases(surplus_amount DESC) WHERE surplus_amount IS NOT NULL;
CREATE INDEX idx_leads_score ON tenant_{org_id}.leads(score DESC) WHERE status = 'new';
CREATE INDEX idx_leads_status ON tenant_{org_id}.leads(status);
CREATE INDEX idx_assignments_attorney ON tenant_{org_id}.attorney_assignments(attorney_id, status);
CREATE INDEX idx_assignments_status ON tenant_{org_id}.attorney_assignments(status);
CREATE INDEX idx_documents_case ON tenant_{org_id}.documents(case_id);
CREATE INDEX idx_documents_status ON tenant_{org_id}.documents(status);
CREATE INDEX idx_calendar_due ON tenant_{org_id}.calendar_events(due_date) WHERE completed_at IS NULL;
```

---

## Appendix B: Service Port Map

| Port | Service | Protocol | PM2/Docker | Purpose |
|------|---------|----------|-----------|---------|
| 8007 | surplusai-scraper-agent-svc | HTTP | PM2 id 7 | County data collection, adapter orchestration |
| 8103 | surplusai-portal-api | HTTP | PM2 id 21 | Customer-facing REST API, multi-tenant auth |
| 8104 | surplusai-parser-service | HTTP | New PM2 | AI docket parsing pipeline |
| 8105 | surplusai-scoring-service | HTTP | New PM2 | Lead scoring ML engine |
| 3003 | surplusai-portal-frontend | HTTP | PM2 | React/Next.js customer dashboard |
| 8120 | surplusai-routing-engine | HTTP | New PM2 | Attorney routing engine |
| 4049 | LiteLLM Proxy | HTTP | PM2 id 17 | DeepSeek V4 model gateway |
| 3010 | Docuseal | HTTP | Docker | E-signature platform |
| 7130 | InsForge | HTTP | Existing | Document intelligence storage |
| 5433 | PostgreSQL (frgops-standby) | PostgreSQL | Docker | Shared database (Phase 1) |
| 5435 | PostgreSQL (surplusai-dedicated) | PostgreSQL | New Docker | Dedicated SurplusAI DB (Phase 2+) |
| 7687 | Neo4j (ecosystem-graph) | Bolt | Docker | Case relationship graph |
| 7474 | Neo4j HTTP | HTTP | Docker | Graph admin UI |
| 7233 | Temporal Server | gRPC | Docker | Durable workflow orchestration |
| 8088 | Apache Superset | HTTP | Docker | BI dashboards |
| 5678 | n8n | HTTP | Docker | Workflow automation |
| 6379 | Redis | Redis | Docker | Cache, queues, rate limiting |
| 9090 | Prometheus | HTTP | Docker | Metrics collection |
| 3100 | Loki | HTTP | Docker | Log aggregation |
| 9093 | Alertmanager | HTTP | Docker | Alert routing |
| 19999 | Netdata | HTTP | Docker | Real-time system metrics |

**Binding policy:** All services bind to `127.0.0.1` only. External access via Cloudflare Tunnel -> Traefik -> service.

---

*End of SurplusAI Enterprise Architecture Document v1.0.0*

**Classification**: INTERNAL -- EXECUTIVE ARCHITECTURE
**Date**: 2026-05-24
**Author**: Wheeler Brain OS -- Revenue Engineering
**Next Review Date**: 2026-06-24
**Related Documents:**
- `/root/SURPLUSAI_PRODUCTIZATION_PLAN.md` -- Base productization plan
- `/root/WHEELER_REVENUE_ENGINE_ARCHITECTURE.md` -- Revenue context, sections 5 and 12
- `/root/ATTORNEY_MARKETPLACE_ARCHITECTURE.md` -- Integration points
- `/root/STAGE2_QA_SCORECARD_FINAL.md` -- Infrastructure QA validation
- `/root/MASTER_EXECUTION_STATE.md` -- Current execution state
