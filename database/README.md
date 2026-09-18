# Database dumps

This directory holds the distributed database dumps and the per-release manifest.

For what the data *means*, see [`../metadata/description.md`](../metadata/description.md).
For how to restore a dump, see [`../examples/restore.md`](../examples/restore.md).

---

## Which dump do I need?

Two dumps are published per release, both produced from the same database.

| Dump | File | Contains | Distributed via |
|---|---|---|---|
| **core** | `truck_robot_core_<version>.sql.gz` | everything **except** `raw_data.travel_matrices` | this repository, in this directory |
| **full** | `truck_robot_full_<version>.sql.gz` | everything | GitHub release asset, archived on Zenodo |

**Use `core`** to explore the dataset: browse the schema, read the instance definitions,
inspect customers and locations, and work out which instances you need. It clones with
the repository and restores in seconds.

**Use `full`** to solve instances. Truck and robot travel times and distances are
precomputed per ordered location pair and are **not** reconstructible from the
coordinates — robot paths follow a sidewalk network and are potentially systematically
longer than the straight-line distance, with no constant factor relating the two, as most
instances rely on real geographical infrastructures. The coordinates additionally carry no
dataset-wide unit. Without `raw_data.travel_matrices` the instances are not solvable.

Both dumps contain the complete schema, so a `core` restore gives you every table; the
travel matrix table is simply empty.

---

## Release manifest

**Version:** `v1.0.0` — not yet released
**Schemas published:** `metadata`, `raw_data`
**PostgreSQL version used to create the dumps:** 18.3
**Minimum PostgreSQL version required to restore:** 13
**Zenodo DOI:** _assigned on release_

### Contents of this release

| Publication | Batches | Instances |
|---|---|---|
| `P5` | 63 | 1575 |
| **total** | **63** | **1575** |

### Row counts per table

| Table | Rows |
|---|---|
| `metadata.papers` | 1 |
| `metadata.instance_batches` | 63 |
| `metadata.instances` | 1 575 |
| `raw_data.customers` | 132 525 |
| `raw_data.network_locations` | 99 600 |
| `raw_data.pickup_locations` | 0 |
| `raw_data.vehicles` | 3 |
| `raw_data.vehicle_parameters` | 126 |
| `raw_data.travel_matrices` | 40 343 775 |

`raw_data.travel_matrices` is empty in the `core` dump; every other count is identical in
both dumps.

`raw_data.pickup_locations` is empty because this release models no parcel pickup points;
the table is part of the schema and is restored empty. `raw_data.vehicles` is the vehicle
catalog referenced by `raw_data.vehicle_parameters` and ships complete.

### Files and checksums

| File | Size | SHA-256 |
|---|---|---|
| `truck_robot_core_v1.0.0.sql.gz` | 2,899,584 bytes | 34b22623fbd7e77d69905906f3be55250a72a11c8cd10526b03bb79d5545e196 |
| `truck_robot_full_v1.0.0.sql.gz` | 1,615,457,486 bytes | 3b04e0763b9253ba90553a14976d73689f8ea179ed1d2b6b5d652358e4186805 |

Verify a download before restoring it:

```powershell
# Windows / PowerShell
Get-FileHash .\truck_robot_full_v1.0.0.sql.gz -Algorithm SHA256
```

```bash
# Linux / macOS
sha256sum truck_robot_full_v1.0.0.sql.gz
```

---

## Reproducing the figures above

```sql
-- Contents of the release, per publication
SELECT p.id                  AS publication,
       count(DISTINCT b.key) AS batches,
       count(i.key)          AS instances
FROM metadata.papers                p
LEFT JOIN metadata.instance_batches b ON b.paper_key          = p.key
LEFT JOIN metadata.instances        i ON i.instance_batch_key = b.key
GROUP BY p.id
ORDER BY p.id;
```

```sql
-- Exact row count and on-disk size per table
SELECT n.nspname || '.' || c.relname                  AS table_name,
       c.reltuples::bigint                            AS approx_rows,
       pg_size_pretty(pg_total_relation_size(c.oid))  AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname IN ('metadata', 'raw_data')
ORDER BY pg_total_relation_size(c.oid) DESC;
```

`reltuples` is an estimate maintained by the planner. Run `ANALYZE` after restoring, or
use `count(*)` where an exact figure is needed — the counts in the table above are exact.
