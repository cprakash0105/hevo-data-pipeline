# Architecture Decision Records

## ADR-001: Logical Replication for CDC

**Status:** Accepted

**Context:**
Hevo supports multiple ingestion modes for PostgreSQL: table-based, query-based, and logical replication. We need a mode that captures inserts, updates, and deletes with minimal impact on the source database.

**Decision:**
Use PostgreSQL logical replication (WAL-based CDC) as the ingestion mode.

**Rationale:**
- Captures all DML operations (INSERT, UPDATE, DELETE) in near real-time
- Minimal performance impact on the source database (reads WAL stream, not table scans)
- Supports schema evolution without pipeline reconfiguration
- Provides exactly-once delivery semantics when combined with replication slots
- Industry-standard approach for production CDC pipelines

**Consequences:**
- Requires `wal_level=logical` on PostgreSQL (configured at container startup)
- Requires a replication slot (managed resource — must monitor for slot lag)
- Requires a publication to define which tables are replicated

---

## ADR-002: dbt for Transformation Layer

**Status:** Accepted

**Context:**
Raw data lands in Snowflake via Hevo. We need to transform it into analytics-ready models with testing and documentation.

**Decision:**
Use dbt (data build tool) for all transformations in Snowflake.

**Rationale:**
- SQL-based transformations are accessible and auditable
- Built-in testing framework for data quality validation
- DAG-based dependency management between models
- Version-controlled transformations (GitOps-friendly)
- Auto-generated documentation and lineage graphs
- Separation of concerns: Hevo handles ingestion, dbt handles transformation

**Consequences:**
- Requires Snowflake credentials managed via environment variables
- CI/CD pipeline needed to automate model deployment
- Staging layer adds a level of indirection but improves maintainability

---

## ADR-003: Environment Variable-Based Configuration

**Status:** Accepted

**Context:**
The project must not contain any hardcoded credentials, URLs, or access keys.

**Decision:**
All sensitive configuration is read from environment variables using dbt's `env_var()` function.

**Rationale:**
- Follows 12-factor app principles
- Compatible with CI/CD secret management (GitHub Secrets)
- No risk of credential leakage in version control
- Supports multiple environments (dev/staging/prod) without code changes

**Consequences:**
- Developers must set environment variables before running dbt
- `.env.example` provided as a template
- `profiles.yml` uses `env_var()` Jinja functions

---

## ADR-004: Staging + Marts Layer Pattern

**Status:** Accepted

**Context:**
We need a transformation architecture that is maintainable, testable, and follows industry best practices.

**Decision:**
Implement a two-layer dbt model architecture:
1. **Staging layer** — 1:1 mapping with source tables, handles renaming and type casting
2. **Marts layer** — Business-logic aggregations producing analytics-ready tables

**Rationale:**
- Staging layer isolates source schema changes from business logic
- Marts layer is the single source of truth for downstream consumers
- Clear separation enables independent testing at each layer
- Follows dbt best practices and the "MVC for data" pattern

**Consequences:**
- Staging models materialized as views (no storage cost, always fresh)
- Mart models materialized as tables (optimized for query performance)
- Changes to source schema only require staging layer updates
