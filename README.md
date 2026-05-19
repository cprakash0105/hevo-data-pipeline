# Hevo Interview Exercise — End-to-End Data Pipeline

## Overview

This project implements a production-grade data pipeline that ingests data from a PostgreSQL source into Snowflake using Hevo Data (CDC via logical replication), then transforms it using dbt into an analytics-ready `customers` table.

## Problem Statement

The objective of this exercise is to design and implement a reliable, scalable data pipeline that ingests transactional data from a PostgreSQL source system into a cloud data warehouse (Snowflake), and transforms it into an analytics-ready data model using modern data engineering practices.

The solution must support:
- Near real-time data ingestion using CDC
- Data quality validation through automated testing
- Secure and configurable deployment without hardcoded credentials
- Clear separation between ingestion, storage, and transformation layers

```
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│   PostgreSQL    │──CDC──▶│    Hevo Data  │──ETL──▶│    Snowflake    │──dbt──▶│    customers    │
│   (Docker/GCP)  │       │   (Pipeline)    │       │   (Warehouse)   │       │   (Mart Table)  │
└─────────────────┘       └─────────────────┘       └─────────────────┘       └─────────────────┘
```

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Zero hardcoded secrets** | All credentials via environment variables (`env_var()`) |
| **Idempotent operations** | dbt models are re-runnable; Hevo uses merge/upsert |
| **Data quality as code** | 21 automated tests covering integrity, referential, domain, and range checks |
| **Separation of concerns** | Ingestion (Hevo) → Storage (Snowflake) → Transformation (dbt) |
| **Observability** | Observability through freshness checks, dbt test automation, and a simple operational runbook |
| **Reproducibility** | Dockerized source, IaC-ready, version-controlled transformations |

## Architecture

### Source Layer — PostgreSQL (Docker on GCP VM)

- **Image**: `postgres:15` on GCP Compute Engine (e2-micro)
- **WAL Level**: `logical` — enables CDC without polling or table scans
- **Publication**: `hevo_publication` — defines replication scope (all tables)
- **Replication Slot**: `hevo_slot` — ensures no data loss during disconnections

**Why logical replication?**
- Near real-time change capture (INSERT/UPDATE/DELETE)
- Minimal load on source (reads WAL stream, not table data)
- Replication slots ensure reliable delivery by preventing data loss even if the pipeline is temporarily unavailable
- No schema intrusion (no triggers, no audit columns needed)

### Ingestion Layer — Hevo Data

- **Mode**: Logical Replication (WAL-based CDC)
- **Sync Frequency**: 5 minutes
- **Load Strategy**: Merge (upsert on primary key)
- **Tables Replicated**: `raw_customers`, `raw_orders`, `raw_payments`

**Why Hevo?**
- Managed CDC pipeline — no custom Debezium/Kafka infrastructure
- Built-in schema mapping and type handling
- Automatic retry and exactly-once delivery
- Native Snowflake Partner Connect integration

### Storage Layer — Snowflake

- **Database**: `HEVO_DB`
- **Raw Schema**: `CP_PUBLIC` (Hevo-managed, landing zone)
- **Transformed Schema**: `PUBLIC` (dbt-managed, consumption zone)
- **Warehouse**: `HEVO_WH` (XSMALL, auto-suspend 60s)

### Transformation Layer — dbt

Two-layer model architecture following the **staging → marts** pattern:

```
Sources (CP_PUBLIC)           Staging (PUBLIC)             Marts (PUBLIC)
┌────────────────────┐       ┌────────────────────┐       ┌────────────────────┐
│  RAW_CUSTOMERS     │──────▶│  stg_customers     │──┐    │                    │
└────────────────────┘       └────────────────────┘  │    │                    │
                                                     ├───▶│     customers      │
┌────────────────────┐       ┌────────────────────┐  │    │                    │
│  RAW_ORDERS        │──────▶│  stg_orders        │──┤    │   (materialized    │
└────────────────────┘       └────────────────────┘  │    │       table)       │
                                                     │    │                    │
┌────────────────────┐       ┌────────────────────┐  │    │                    │
│  RAW_PAYMENTS      │──────▶│  stg_payments      │──┘    │                    │
└────────────────────┘       └────────────────────┘       └────────────────────┘
       (views)                      (views)                     (table)
```

**Staging layer** (materialized as views):
- 1:1 mapping with source tables
- Column renaming for consistency (e.g., `id` → `customer_id`)
- Isolates downstream models from source schema changes

**Marts layer** (materialized as table):
- Business logic: joins, aggregations, derived metrics
- Final `customers` table with all required columns

## Final Output — `customers` Table

| Column | Source | Logic |
|--------|--------|-------|
| `customer_id` | stg_customers | Primary key |
| `first_name` | stg_customers | Direct mapping |
| `last_name` | stg_customers | Direct mapping |
| `first_order` | stg_orders | `MIN(order_date)` per customer |
| `most_recent_order` | stg_orders | `MAX(order_date)` per customer |
| `number_of_orders` | stg_orders | `COUNT(order_id)` per customer |
| `customer_lifetime_value` | stg_payments | `SUM(amount)` across all customer orders |

## Data Quality Framework

### Test Coverage (21 tests)

| Category | Tests | Purpose |
|----------|-------|---------|
| **Integrity** | unique, not_null on all PKs | Ensures no duplicates or missing keys |
| **Referential** | relationships (orders→customers, payments→orders) | Validates FK constraints |
| **Domain** | accepted_values on status, payment_method | Catches unexpected enum values |
| **Range** | accepted_range on number_of_orders, lifetime_value | Ensures non-negative metrics |
| **Custom** | assert_customer_lifetime_value_is_positive | Business rule validation |

### Source Freshness Monitoring

```yaml
freshness:
  warn_after: {count: 24, period: hour}   # Alert if data > 24h stale
  error_after: {count: 48, period: hour}  # Fail if data > 48h stale
```

## CI/CD Pipeline (GitHub Actions)

Every push/PR triggers:
1. `dbt deps` — Install packages
2. `dbt debug` — Validate connection
3. `dbt run` — Build all models
4. `dbt test` — Run all 21 tests
5. `dbt source freshness` — Check data staleness
6. `dbt docs generate` — Update documentation

Credentials are managed via **GitHub Secrets** — never exposed in code or logs.

This setup simulates a production-ready validation pipeline, though for this exercise it is kept intentionally lightweight.

## Project Structure

```
├── .github/
│   └── workflows/
│       └── dbt_ci.yml                  # CI/CD pipeline
├── docker/
│   ├── docker-compose.yml              # PostgreSQL with logical replication
│   ├── init/
│   │   └── 01_init.sql                 # DDL + data load + publication
│   └── data/
│       ├── raw_customers.csv           # 100 rows
│       ├── raw_orders.csv              # 99 rows
│       └── raw_payments.csv            # 113 rows
├── dbt_project/
│   ├── dbt_project.yml                 # Project config
│   ├── packages.yml                    # dbt_utils dependency
│   ├── profiles.yml                    # Snowflake connection (env vars)
│   ├── models/
│   │   ├── staging/
│   │   │   ├── sources.yml             # Source definitions + freshness + tests
│   │   │   ├── stg_customers.sql
│   │   │   ├── stg_orders.sql
│   │   │   └── stg_payments.sql
│   │   └── marts/
│   │       ├── customers.sql           # Final materialized table
│   │       └── schema.yml              # Column tests + documentation
│   └── tests/
│       └── assert_customer_lifetime_value_is_positive.sql
├── docs/
│   ├── ARCHITECTURE_DECISIONS.md       # ADRs for key design choices
│   ├── DATA_LINEAGE.md                 # Full data flow + quality gates
│   └── RUNBOOK.md                      # Operational procedures
├── .env.example                        # Template for env vars
├── .gitignore                          # Excludes secrets + artifacts
├── Makefile                            # Common operations
└── README.md                           # This file
```

## Setup Instructions

### Prerequisites

- Docker (or Podman)
- Python 3.8+
- `pip install dbt-snowflake`
- Snowflake trial account
- Hevo trial account
- GCP VM (or any machine with public IP for PostgreSQL)

### Step 1: Start PostgreSQL

```bash
# On your GCP VM (or local machine with Docker)
cd docker
docker-compose up -d

# Verify
docker exec hevo_postgres psql -U hevo_user -d hevo_db -c \
  "SELECT 'raw_customers', count(*) FROM raw_customers
   UNION ALL SELECT 'raw_orders', count(*) FROM raw_orders
   UNION ALL SELECT 'raw_payments', count(*) FROM raw_payments;"
```

Expected: 100 + 99 + 113 rows.

### Step 2: Configure Hevo Pipeline

| Setting | Value |
|---------|-------|
| Source | PostgreSQL |
| Host | `<VM external IP>` |
| Port | `5432` |
| Database | `hevo_db` |
| User | `hevo_user` |
| Ingestion Mode | **Logical Replication** |
| Publication | `hevo_publication` |
| Replication Slot | `hevo_slot` |
| Destination | Snowflake |
| Load Mode | Merge |
| Sync Frequency | 5 minutes |

### Step 3: Run dbt

```bash
# Set environment variables
export SNOWFLAKE_ACCOUNT=<your_account>
export SNOWFLAKE_USER=<your_user>
export SNOWFLAKE_PASSWORD=<your_password>
export SNOWFLAKE_ROLE=ACCOUNTADMIN
export SNOWFLAKE_DATABASE=HEVO_DB
export SNOWFLAKE_WAREHOUSE=HEVO_WH
export SNOWFLAKE_SCHEMA=PUBLIC

# Run
cd dbt_project
dbt deps
dbt run
dbt test
```

### Step 4: Verify in Snowflake

```sql
SELECT * FROM HEVO_DB.PUBLIC.CUSTOMERS ORDER BY customer_id LIMIT 10;
```

## Security

- ✅ No credentials in source code
- ✅ `profiles.yml` uses `env_var()` Jinja functions
- ✅ `.gitignore` excludes `.env`, build artifacts
- ✅ CI/CD uses GitHub Secrets for credential injection
- ✅ PostgreSQL uses `md5` authentication (not `trust`)
- ✅ Replication user has minimal required permissions

## Beyond the Exercise — What I Added

The exercise requirements cover steps 1–7 (source setup, pipeline, dbt model with tests). I went further to demonstrate how I'd approach this in a real platform context:

| Addition | Why |
|----------|-----|
| **Source-level data quality tests** (referential integrity, domain validation) | In production, bad data at the source propagates downstream. Catching it early is cheaper. |
| **Source freshness SLA** (warn 24h, error 48h) | Pipelines fail silently. Freshness checks make staleness visible before stakeholders notice. |
| **CI/CD pipeline** (GitHub Actions) | Ensures no broken model or failing test reaches production. Standard for any team-based dbt project. |
| **Architecture Decision Records** | Documents the *why* behind choices — critical for onboarding and future maintainability. |
| **Data lineage documentation** | Makes the full data flow traceable from source to mart, including quality gates at each layer. |
| **Operational runbook** | Reduces MTTR when things break. Covers common failure scenarios and recovery steps. |
| **Makefile** | One-command operations for common tasks — reduces friction for anyone running the project. |

These additions reflect how I think about data platforms: **reliability, observability, and operability are not afterthoughts — they're built in from day one.**

## Production Considerations

If this were a production system, I would additionally implement:

1. **Infrastructure as Code** — Terraform for GCP VM, firewall rules, Snowflake resources
2. **Alerting** — PagerDuty/Slack integration for freshness violations and test failures
3. **Data Contracts** — Schema registry or protobuf definitions for source tables
4. **Row-Level Monitoring** — Great Expectations or dbt-expectations for anomaly detection
5. **Cost Controls** — Snowflake resource monitors, warehouse auto-suspend policies
6. **RBAC** — Separate roles for ingestion (Hevo), transformation (dbt), and consumption (analysts)
7. **Lineage Visualization** — dbt docs or DataHub for interactive lineage exploration

## Challenges Faced

- Establishing a CDC-based connection from a locally hosted PostgreSQL instance was not feasible due to network restrictions on corporate environments. To address this, the PostgreSQL instance was deployed on a GCP VM with a public IP, enabling Hevo to establish a stable logical replication connection.
- The Snowflake Python connector has a known compatibility issue with the Windows Store version of Python (`platform.libc_ver()` fails on sandboxed executables). This was resolved by patching the connector's `_libc_ver` method to gracefully handle the `OSError`.

## Hevo Details

- **Team ID**: `bt.com_3`
- **Pipeline ID**: `3602`
- **GitHub**: https://github.com/cprakash0105/hevo-data-pipeline

## Loom Video

[Link to Loom video explaining the implementation]
