# Restoring the database

How to get from a downloaded dump to a queryable database, and how to restore only the
parts you need.

Requires **PostgreSQL 13 or newer**. The dumps are produced with PostgreSQL 18; plain
SQL dumps restore into older majors as long as no newer syntax is used, and none is.

---

## Contents

- [Which dump](#which-dump)
- [Quick start](#quick-start)
- [Step by step](#step-by-step)
- [Docker](#docker)
- [Restoring only selected instances](#restoring-only-selected-instances)
- [Connecting from an IDE](#connecting-from-an-ide)
- [Connecting from Python](#connecting-from-python)
- [Verifying the restore](#verifying-the-restore)
- [Troubleshooting](#troubleshooting)

---

## Which dump

| You want to | Use |
|---|---|
| browse the schema, pick instances | `core` — in [`../database/`](../database/) |
| solve instances | `full` — GitHub release asset / Zenodo |

The `core` dump contains every table but leaves `raw_data.travel_matrices` empty. Travel
times and distances are not reconstructible from the coordinates, so instances cannot be
solved from `core` alone. See [`../database/README.md`](../database/README.md).

---

## Quick start

```bash
createdb truck_robot
gunzip -c truck_robot_full_v1.0.0.sql.gz | psql -d truck_robot -v ON_ERROR_STOP=1
psql -d truck_robot -c "ANALYZE;"
```

On Windows PowerShell, `gunzip` is usually unavailable; see
[Step by step](#step-by-step).

---

## Step by step

### 1. Verify the download

A truncated download fails late and confusingly. Check the hash against
[`../database/README.md`](../database/README.md) first.

```powershell
# Windows / PowerShell
Get-FileHash .\truck_robot_full_v1.0.0.sql.gz -Algorithm SHA256
```

```bash
# Linux / macOS
sha256sum truck_robot_full_v1.0.0.sql.gz
```

### 2. Create an empty database

```bash
createdb -h localhost -p 5432 -U postgres truck_robot
```

Restore into a **fresh, empty** database. The dump creates schemas named `metadata`
and `raw_data`; restoring into a database that already has them will fail or,
worse, merge two datasets.

### 3. Restore

The dump is plain SQL, gzipped. `ON_ERROR_STOP=1` is important: without it `psql`
continues past failures and leaves you with a partially populated database that looks
fine until a query returns too few rows.

```bash
# Linux / macOS
gunzip -c truck_robot_full_v1.0.0.sql.gz \
  | psql -h localhost -p 5432 -U postgres -d truck_robot -v ON_ERROR_STOP=1
```

```powershell
# Windows / PowerShell -- decompress first, then restore
$gz  = "truck_robot_full_v1.0.0.sql.gz"
$sql = "truck_robot_full_v1.0.0.sql"

$in  = [System.IO.File]::OpenRead((Resolve-Path $gz))
$out = [System.IO.File]::Create((Join-Path (Get-Location) $sql))
$stream = New-Object System.IO.Compression.GzipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
$stream.CopyTo($out)
$stream.Dispose(); $out.Dispose(); $in.Dispose()

psql -h localhost -p 5432 -U postgres -d truck_robot -v ON_ERROR_STOP=1 -f $sql
```

Expect the `full` restore to take several minutes and to need roughly 3 GB of disk for
the data plus index space. The `core` restore takes seconds.

### 4. Update planner statistics

```bash
psql -d truck_robot -c "ANALYZE;"
```

Skipping this leaves the planner with no statistics on a freshly loaded database, which
makes queries against the travel matrix dramatically slower.

---

## Docker

Useful when you do not want a local PostgreSQL installation, or need a specific major
version.

```bash
docker run -d --name truck-robot-db \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=truck_robot \
  -p 55432:5432 \
  -v truck_robot_data:/var/lib/postgresql/data \
  postgres:18

# wait until the server accepts connections
until docker exec truck-robot-db pg_isready -U postgres; do sleep 1; done

gunzip -c truck_robot_full_v1.0.0.sql.gz \
  | docker exec -i truck-robot-db psql -U postgres -d truck_robot -v ON_ERROR_STOP=1

docker exec truck-robot-db psql -U postgres -d truck_robot -c "ANALYZE;"
```

The database is then reachable on `localhost:55432`. Port `55432` avoids colliding with a
local PostgreSQL on `5432`. The named volume keeps the data when the container is
removed; drop it with `docker volume rm truck_robot_data`.

---

## Restoring only selected instances

If you only need part of the instances, restoring the full dump and deleting the rest is
simpler and safer than trying to filter the dump file — the foreign keys do the work.

```sql
-- Keep only the batches you need.
-- ON DELETE CASCADE removes the dependent customers, locations, travel matrices,
-- locations and travel matrices automatically.
BEGIN;

DELETE FROM metadata.instance_batches
WHERE key NOT IN (
    SELECT b.key FROM metadata.instance_batches b
    JOIN metadata.papers p ON p.key = b.paper_key
    WHERE p.id = 'P5' AND b.sensitivity_type = 'default'
);

COMMIT;
VACUUM FULL;
ANALYZE;
```

`VACUUM FULL` rewrites the tables and returns the disk space; without it the files stay
at their original size. It takes an exclusive lock and needs temporary space of roughly
the size of the table being rewritten.

To keep individual instances within a batch, delete from `metadata.instances` the same
way:

```sql
DELETE FROM metadata.instances
WHERE key NOT IN (
    SELECT i.key FROM metadata.instances i
    JOIN metadata.instance_batches b ON b.key = i.instance_batch_key
    WHERE b.id = 'C100-CR0.2-TC0.2'
);
```

> Do this on a restored copy, never treat the reduced database as the dataset. Deleting
> rows does not change `metadata.instance_batches.no_of_instances`, so the completeness
> check in [Verifying the restore](#verifying-the-restore) will legitimately fail
> afterwards.

---

## Connecting from an IDE

**DataGrip, PyCharm Professional, IntelliJ IDEA Ultimate**

1. Open the *Database* tool window.
2. `+` → *Data Source* → *PostgreSQL*.
3. Enter host, port, database, user and password; download the driver if prompted.
4. Open the **Schemas** tab and tick `metadata` and `raw_data`.
   This step is easy to miss: by default only the default schema is introspected, and
   the dataset's tables will appear to be missing.
5. *Test Connection* → *OK*.

**psql**

```bash
psql -h localhost -p 5432 -U postgres -d truck_robot
\dn                          -- list schemas
\dt metadata.*               -- list tables in a schema
\d+ raw_data.customers       -- describe a table, with column comments
```

`\d+` prints the `COMMENT ON COLUMN` text, which carries the unit and meaning of every
column — often faster than opening the documentation.

---

## Connecting from Python

```python
import pandas as pd
from sqlalchemy import create_engine

engine = create_engine("postgresql+psycopg://postgres:postgres@localhost:5432/truck_robot")

# Resolve a qualified instance identifier to its internal key
instance_key = pd.read_sql("""
    SELECT i.key
    FROM metadata.papers           p
    JOIN metadata.instance_batches b ON b.paper_key        = p.key
    JOIN metadata.instances        i ON i.instance_batch_key = b.key
    WHERE p.id = %(paper)s AND b.id = %(batch)s AND i.id = %(instance)s
""", engine, params={"paper": "P5", "batch": "C100-CR0.2-TC0.2", "instance": "I17"}).iat[0, 0]

customers = pd.read_sql(
    "SELECT * FROM raw_data.customers WHERE instance_key = %(k)s",
    engine, params={"k": int(instance_key)})

travel = pd.read_sql(
    "SELECT * FROM raw_data.travel_matrices WHERE instance_key = %(k)s",
    engine, params={"k": int(instance_key)})
```

Two things to watch:

- **Always pass `instance_key` as a parameter and filter in SQL.** Reading
  `raw_data.travel_matrices` without a predicate will attempt to materialise the entire
  table in memory.
- **`Infinity` survives the round trip as `float('inf')`**, in
  `initial_robot_availability`, `max_robot_capacity`, `battery_capacity` and
  `charging_rate`. Do not call `.astype(int)` on those columns — it raises on `inf`, and
  `fillna(0)` will not catch it because `inf` is not `NaN`. Test with `np.isinf`.

---

## Verifying the restore

Run the validation section of
[`example_queries.sql`](example_queries.sql), or these three checks directly. For each,
**an empty result is the pass condition.**

```sql
-- 1. Every batch holds the number of instances it declares
SELECT p.id AS paper, b.id AS batch, b.no_of_instances AS declared, count(i.key) AS actual
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key        = p.key
LEFT JOIN metadata.instances   i ON i.instance_batch_key = b.key
GROUP BY p.id, b.id, b.no_of_instances
HAVING b.no_of_instances <> count(i.key)
ORDER BY p.id, b.id;
```

```sql
-- 2. Every location id used in a travel matrix resolves to a location
WITH loc AS (
    SELECT instance_key, id FROM raw_data.customers
    UNION ALL SELECT instance_key, id FROM raw_data.network_locations
    UNION ALL SELECT instance_key, id FROM raw_data.pickup_locations
)
SELECT t.instance_key, t.start_location_id, t.end_location_id
FROM raw_data.travel_matrices t
WHERE NOT EXISTS (SELECT 1 FROM loc l
                  WHERE l.instance_key = t.instance_key AND l.id = t.start_location_id)
   OR NOT EXISTS (SELECT 1 FROM loc l
                  WHERE l.instance_key = t.instance_key AND l.id = t.end_location_id)
LIMIT 100;
```

```sql
-- 3. Every instance has a depot and at least one customer
SELECT i.key, i.id
FROM metadata.instances i
WHERE NOT EXISTS (SELECT 1 FROM raw_data.network_locations n
                  WHERE n.instance_key = i.key AND n.location_type = 'Depot')
   OR NOT EXISTS (SELECT 1 FROM raw_data.customers c
                  WHERE c.instance_key = i.key)
ORDER BY i.key
LIMIT 100;
```

On a `core` restore, check 2 returns nothing simply because the travel matrix is empty.
That is expected, not a pass.

---

## Troubleshooting

**`psql: error: FATAL: role "..." does not exist`**
The dumps are produced with `--no-owner --no-privileges`, so they contain no role
references. If you see this, you are restoring a dump produced differently; add
`--no-owner` to `pg_restore`, or restore with `psql` as shown above.

**`ERROR: schema "metadata" already exists`**
You are restoring into a non-empty database. Create a fresh one.

**Restore appears to succeed but tables are empty**
You ran `psql` without `-v ON_ERROR_STOP=1` and it continued past a failure. Drop the
database and restore again with the flag, then read the first error.

**Queries against `raw_data.travel_matrices` are very slow**
Either you did not run `ANALYZE` after the restore, or the query lacks an `instance_key`
predicate. Check with `EXPLAIN`: an index or index-only scan on the primary key is
expected, a sequential scan of the whole table is not.

**Tables are missing in the IDE**
Only the default schema was introspected. Enable `metadata` and `raw_data` in
the data source's *Schemas* tab.

**`invalid byte sequence for encoding "UTF8"`**
Your client is running a non-UTF8 encoding. Set `PGCLIENTENCODING=UTF8` before restoring;
on Windows PowerShell, `$env:PGCLIENTENCODING = "UTF8"`.
