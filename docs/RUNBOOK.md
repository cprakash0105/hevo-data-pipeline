# Operational Runbook

## Daily Operations

### Health Check
```bash
# 1. Verify PostgreSQL is running
sudo docker ps | grep hevo_postgres

# 2. Check replication slot lag
sudo docker exec hevo_postgres psql -U hevo_user -d hevo_db -c \
  "SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS lag_bytes FROM pg_replication_slots;"

# 3. Check source freshness in dbt
cd dbt_project && dbt source freshness

# 4. Run dbt tests
dbt test
```

### Key Metrics to Monitor
| Metric | Threshold | Action |
|--------|-----------|--------|
| Replication slot lag | > 100MB | Investigate Hevo connectivity |
| Source freshness | > 24h warn, > 48h error | Check Hevo pipeline status |
| dbt test failures | Any | Block deployment, investigate |
| Hevo events failed | > 0 | Check event logs in Hevo UI |

## Incident Response

### Scenario: Data Not Syncing

1. **Check Hevo pipeline status** — Is it running? Any errors in the UI?
2. **Check source connectivity**:
   ```bash
   sudo docker exec hevo_postgres psql -U hevo_user -d hevo_db -c "SELECT 1;"
   ```
3. **Check replication slot**:
   ```bash
   sudo docker exec hevo_postgres psql -U hevo_user -d hevo_db -c "SELECT * FROM pg_replication_slots;"
   ```
4. **Check firewall** — Is port 5432 still open?
5. **Restart if needed**:
   ```bash
   sudo docker restart hevo_postgres
   ```

### Scenario: dbt Tests Failing

1. **Identify failing test**: `dbt test --store-failures`
2. **Inspect failed rows**: Query the `dbt_test__audit` schema in Snowflake
3. **Check source data**: Verify raw tables in `CP_PUBLIC` schema
4. **Fix and re-run**: `dbt run --select <model>+ && dbt test`

### Scenario: Replication Slot Bloat

If the replication slot lag grows unbounded (Hevo disconnected for too long):

```bash
# Check current lag
sudo docker exec hevo_postgres psql -U hevo_user -d hevo_db -c \
  "SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag FROM pg_replication_slots;"

# If lag is critical and Hevo cannot catch up, drop and recreate slot
sudo docker exec hevo_postgres psql -U hevo_user -d hevo_db -c "SELECT pg_drop_replication_slot('hevo_slot');"
sudo docker exec hevo_postgres psql -U hevo_user -d hevo_db -c "SELECT pg_create_logical_replication_slot('hevo_slot', 'pgoutput');"
# Then trigger a full re-sync in Hevo
```

## Deployment Checklist

### Before Deploying dbt Changes
- [ ] `dbt compile` — Verify SQL compiles without errors
- [ ] `dbt run` — Models build successfully
- [ ] `dbt test` — All tests pass
- [ ] `dbt source freshness` — Sources are fresh
- [ ] PR reviewed and approved
- [ ] CI/CD pipeline green

### Infrastructure Changes
- [ ] PostgreSQL config changes require container restart
- [ ] Firewall rule changes verified with connectivity test
- [ ] Snowflake role/permission changes tested with `dbt debug`
