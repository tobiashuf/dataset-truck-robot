# Dataset description

Reference documentation for the Truck-and-Robot Instance Dataset. It describes what the
dataset contains, how its parts relate, what the values mean, and which conventions you
must respect to read them correctly.

This document covers semantics. Per-release figures — instance counts, dump sizes,
checksums, DOI — are in [`../database/README.md`](../database/README.md). Column-by-column
documentation is in [`variables/`](variables/). The annotated DDL is in
[`schema/`](schema/).

This release publishes **instance input only**; computational results may follow. See the "Scope of this release" section of
[`../README.md`](../README.md).

---

## Contents

- [Scope and purpose](#scope-and-purpose)
- [Structure](#structure)
- [The three levels of the data model](#the-three-levels-of-the-data-model)
- [Identifiers](#identifiers)
- [Units and conventions](#units-and-conventions)
- [Missing values and sentinels](#missing-values-and-sentinels)
- [Enumerated domains](#enumerated-domains)
- [Known pitfalls](#known-pitfalls)
- [Provenance](#provenance)
- [Validating a restored database](#validating-a-restored-database)

---

## Scope and purpose

The dataset collects the benchmark instances used across a series of publications on
truck-and-robot last-mile delivery, in one place and one format.

In these problems a truck carries autonomous delivery robots into a service area,
releases them to serve customers, and either collects them again or lets them return to
a robot hub independently. Instances therefore need to express more than a customer set
and one distance matrix:

- **two travel networks** — trucks use roads, robots use sidewalks, so the same pair of
  locations has two different travel times and two different distances, and neither is
  derivable from the other
- **robot supply as a resource** — robots are stationed at hubs with an initial count
  and a capacity, can be reused after completing a tour, and can be relocated between
  hubs
- **release and collection geometry** — network locations where robots may be released or
  collectedm i.e., robot hubs, drop-off points and customers
- **coupled timing** — a truck may have to wait for a robot, and a robot may have to wait
  for a customer time window, so waiting time is a modeled quantity rather than slack

Publishing this as a relational database rather than one file format per paper means a
single query selects exactly the instances a study needs, and instances from different
publications become directly comparable.

**What the dataset is not.** It is not a scientific contribution in its own right, and it
is not a benchmark *library* with best-known solutions curated across the literature. It
is the instance data behind specific publications. See the "Citation" section of
[`../README.md`](../README.md).

---

## Structure

Two schemas, each with one job:

| Schema | Question it answers |
|---|---|
| `metadata` | Which publication, which generation configuration, which instance? |
| `raw_data` | What is the instance? — the complete solver/algorithm input |

The separation keeps the citation chain explicit: every row of instance data leads back
through `metadata` to exactly one publication.

---

## The three levels of the data model

### 1. Publication — `metadata.papers`

One row per publication associated with instances in the dataset. This table drives the
citation requirement: whoever uses an instance must cite the publication reachable from
it.

Unpublished work appears with `journal`, `doi` and `publication_date` set to `NULL`. A
row may exist without contributing any instances to the current release.

### 2. Batch — `metadata.instance_batches`

One row per group of instances generated with an identical parameter configuration.

**This table is the authoritative record of generation parameters.** Its columns hold the
customer count, truck and robot counts, demand composition shares, robot hub and
drop-off point counts, topography settings, time-window rules and deadline intervals
that were used.
[`generation_parameters/generator.yaml`](generation_parameters/generator.yaml) adds only
what a column cannot express — the generator's inputs and the modes they offer, the
label each mode is recorded as, generator version, seeding policy, network source — and
never duplicates these values. There is exactly one source of truth, and it is the
database.

`sensitivity_type` names the single dimension a batch varies relative to the batch with
`sensitivity_type = 'default'` of the same publication. This makes a sensitivity analysis
selectable with one predicate instead of a hand-maintained list of batch names:

```sql
SELECT b.sensitivity_type, b.id, b.no_of_robot_depots, b.no_of_dropoff_points
FROM metadata.instance_batches b
JOIN metadata.papers p ON p.key = b.paper_key
WHERE p.id = 'P5'
ORDER BY b.sensitivity_type, b.id;
```

The value `'auto'` marks a batch whose design is adopted as a whole from a referenced
publication rather than varied along one dimension. The value `'exact_comparison'` marks
deliberately small batches used for comparison against an exact method — it varies
instance size rather than a problem dimension.

**Batch `id` is not unique on its own.** The constraint is
`UNIQUE (id, sensitivity_type)`: the same identifier may recur under a different
`sensitivity_type`. Always carry both columns.

### 3. Instance — `metadata.instances`

One row per individual problem instance, and the **central join target** of the dataset:
every table in `raw_data` references `metadata.instances.key`.

The table is deliberately thin — it carries identity only. Everything that describes the
instance either lives one level up (generation parameters, shared by the batch) or one
level down (the actual customers, locations and matrices).

`raw_data.vehicle_parameters` is the one exception to "everything hangs off an
instance": it attaches to `metadata.instance_batches`, because all instances of a batch
share one vehicle parametrization.

---

## Identifiers

Every table carries two kinds of identifier, and confusing them is the most common way
to produce an unreproducible result.

**`key` — surrogate, internal, unstable.** An integer assigned by a sequence. Use it for
joins. It is **not stable across releases**: regenerating or reloading data reassigns it.
Never cite a `key`, never hard-code one in a script you intend to keep, never publish a
result table indexed by `key`.

**`id` — business identifier, stable, citable.** Human-readable and stable across
releases: `P5`, `C100-CR0.2-TC0.2`, `I17`, `C-42`, `R-7`.

**Instance `id` is not globally unique.** Values like `I17` repeat in every batch.
Uniqueness *within* a batch is enforced by `UNIQUE (instance_batch_key, id)`. To
reference an instance unambiguously, qualify it:

```
papers.id / instance_batches.id / instances.id   e.g.  P5 / C100-CR0.2-TC0.2 / I17
```

```sql
-- Qualified identifier for every instance
SELECT p.id || ' / ' || b.id || ' / ' || i.id AS qualified_id, i.key
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key          = p.key
JOIN metadata.instances        i ON i.instance_batch_key = b.key
ORDER BY p.id, b.id, i.id;
```

**Location ids share one namespace per instance.**
`raw_data.travel_matrices.start_location_id` and `.end_location_id` refer to locations
that may live in any of three tables:

| Pattern | Meaning | Table | Discriminator |
|---|---|---|---|
| `DP` | truck depot | `network_locations` | `location_type = 'Depot'` |
| `R-<n>` | robot hub | `network_locations` | `location_type = 'Robot Hub'` |
| `S-<n>` | drop-off point | `network_locations` | `location_type = 'Drop-off Point'` |
| `C-<n>` | regular delivery customer | `customers` | `customer_type = 'Regular'` |
| `CR-<n>` | return-request customer | `customers` | `customer_type = 'Return'` |
| `CP-<n>` | pickup-request customer | `customers` | `customer_type = 'Pickup'` |
| `P-<n>` | parcel pickup point | `pickup_locations` | `location_type = 'Parcel Pickup Point'` |

Two prefix facts are easy to get wrong:

- **Drop-off points are `S-`, not `D-`.** The mnemonic is the word *stop* and the potential future 
  drone hubs.
- **Customers carry a type-dependent prefix.** A filter of `id LIKE 'C-%'` matches
  regular customers only and silently drops every return (`CR-`) and pickup (`CP-`)
  request. Match on `customer_type` instead.

Because no single table can be the referent, there is deliberately no foreign key on
those columns. To resolve a location id to coordinates, union the three tables — see
[`../examples/example_queries.sql`](../examples/example_queries.sql).

---

## Units and conventions

### The database is strict SI

Every unit-bearing column carries its unit in a `COMMENT ON COLUMN`, and those comments
are the authoritative reference. They are **strict SI without exception** — including
where a field's literature convention differs.

| Quantity | Unit | Applies to |
|---|---|---|
| distances, elevation, altitude gain | `[m]` | `truck_distance`, `robot_distance`, `truck_altitude_up`, `robot_altitude_up`, `truck_altitude_down`, `robot_altitude_down`, `max_distance`, `altitude_difference`, `z_coordinate` |
| times, durations, time windows | `[s]` | `truck_time`, `robot_time`, `time_window_start`, `time_window_end`, `service_time`, `time_per_interruption`, `time_window_length_*` |
| speed | `[m/s]` | `speed_min`, `speed_max` |
| acceleration | `[m/s²]` | `acceleration`, `deceleration`, `gravity_constant` |
| mass | `[kg]` | `curb_weight`, `max_load`, `parcel_weight` |
| area | `[m²]` | `frontal_area` |
| emissions | `[kg]` CO₂-equivalent | `truck_emission`, `robot_emission` |
| counts, shares, dimensionless | `[-]` | all `no_of_*`, all `share_*`, `priority`, `parcel_demand`, `initial_robot_availability`, `max_robot_capacity`, efficiencies, coefficients |

**Time origin.** All time windows and deadlines within an instance are relative to the
start of the planning horizon, `t = 0`. The generator's horizon is e.g., 08:00–18:00 and can be set individually, so
`t = 0` corresponds to 08:00 and the horizon is 36 000 s long. These are **not** times of
day.

**Signs.** Descent columns (`truck_altitude_down`, `robot_altitude_down`) and
`deceleration` are reported as positive magnitudes, not as negative values.

### Coordinates are the one exception, and carry no unit at all

`x_coordinate` and `y_coordinate` have **no unit comment in the database**, deliberately.
Their scale is chosen per instance set, differs between publications, and values may be
negative. They are planar and not georeferenced.

Use them for topology and plotting. **Never derive a distance from them.** Every distance
and travel time you need is precomputed in `raw_data.travel_matrices`, which is the only
authoritative source. `metadata.instance_batches.area_size` is a descriptive label in
meters and bears no arithmetic relationship to the coordinate values.

### Monetary rates are SI too — and this surprises people

| Column | Unit | A familiar figure | Stored as |
|---|---|---|---|
| `cost_per_distance` | `[EUR/m]` | 0.2 EUR/km | `0.0002` |
| `cost_per_time` | `[EUR/s]` | 30 EUR/h | `0.008333…` |
| `delay_cost` | `[EUR/s]` | 5 EUR/h | `0.001388…` |
| `cost_per_energy` | `[EUR/J]` | — | — |
| `emission_to_cost_factor` | `[EUR/kg]` | — | — |

Multiply by `1000` or `3600` to recover the per-kilometer and per-hour figures. The
generator takes the familiar units — EUR/km and EUR/h — and converts on write; the units
its inputs use are recorded in
[`generation_parameters/generator.yaml`](generation_parameters/generator.yaml).

### The energy and emission model is SI, not literature convention

The parameters of the energy and emission model are stored in SI, **not** in the units
the emission-model literature uses mostly. If you take a published formula and feed these
columns into it unchanged, the result will be wrong by many orders of magnitude.

| Column | Database unit | Literature convention |
|---|---|---|
| `fuel_heating_value` | `[J/kg]` | kJ/g |
| `fuel_density` | `[kg/m³]` | g/L |
| `engine_displacement` | `[m³]` | L |
| `engine_speed` | `[1/s]` | rev/s |
| `engine_friction_factor` | `[J/m³]` | kJ/(rev·L) |
| `auxiliary_power_draw` | `[W]` | kW |
| `battery_capacity` | `[J]` | kWh |
| `charging_rate` | `[W]` | kW |
| `energy_consumption` | `[J/m]` | kWh/m |
| `fuel_to_emission_factor` | `[kg/m³]` | kg/L |
| `energy_to_emission_factor` | `[kg/J]` | kg/kWh |

The generator takes these parameters in the literature units and converts on write. Its
values, in those units, are recorded under `preset_parameters` in
[`generation_parameters/generator.yaml`](generation_parameters/generator.yaml). Note that
these columns have never been populated, so the conversion has never been exercised —
verify it before first use.

### Ratios

| Prefix / suffix | Range | Meaning |
|---|---|---|
| `share_*` | `[0, 1]` | fraction |

To read the unit and meaning of every column straight from the database:

```sql
SELECT a.attname                           AS column_name,
       format_type(a.atttypid, a.atttypmod) AS data_type,
       col_description(c.oid, a.attnum)     AS unit_and_meaning
FROM pg_class     c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'raw_data' AND c.relname = 'vehicle_parameters'
ORDER BY a.attnum;
```

---

## Missing values and sentinels

### `NULL` means "not applicable", never "zero"

The dataset spans several problem variants over one schema, so a column that a variant
does not model is `NULL` for that variant's batches. Examples:

- `customers.priority` is `NULL` for batches with homogeneous customer priorities
- `customers.parcel_weight` is `NULL` where weight is not modeled
- `z_coordinate` is `NULL` for flat instances
- `vehicle_parameters` columns are `NULL` for every parameter the batch does not model
- `network_locations.max_robot_capacity` is `NULL` where hub capacity is not a
  constraint at all — which is different from `Infinity`, meaning "unlimited capacity"

**Do not `COALESCE` these to `0`.** Turning "this batch has no time windows" into "every
customer must be served at `t = 0`" produces a different, much harder problem — and it
does so silently.

### `Infinity` means "unlimited"

Four columns are `double precision` rather than `integer` specifically so they can hold
IEEE-754 `Infinity`:

| Column | `Infinity` means |
|---|---|
| `network_locations.initial_robot_availability` | unlimited robots available at this location |
| `network_locations.max_robot_capacity` | unlimited robot capacity at this location |
| `vehicle_parameters.battery_capacity` | energy is not a limiting resource in this batch |
| `vehicle_parameters.charging_rate` | recharging is instantaneous |

**Never cast these to `integer`.** `integer` cannot represent `Infinity`; the cast errors
or truncates and in either case destroys the distinction between "unlimited" and an
arbitrary finite bound. All finite values in these columns are whole numbers, so read
them as counts but keep the floating-point type.

To test for the sentinel in SQL:

```sql
SELECT * FROM raw_data.network_locations
WHERE max_robot_capacity = 'Infinity'::double precision;
```

Be aware that many client libraries and data-frame loaders map `Infinity` to `inf`,
`NaN` or `NULL` depending on the column type they infer. Check this once for your
toolchain before relying on it.

### `'Infinity'` as text

`metadata.instance_batches.no_of_robots` is `text` and uses the literal string
`'Infinity'` for an unlimited robot fleet. Note the capitalization: it is `'Infinity'`,
not `'inf'`. It is a different representation of the same concept and needs separate
handling — see [Known pitfalls](#known-pitfalls).

### `'Optional'`, not `NULL`, for an unconstrained service choice

`customers.served_by` and `pickup_locations.served_by` encode "either vehicle may serve
this" as the literal string `'Optional'`. Both columns are nullable, but the
unconstrained case is expressed by `'Optional'` rather than by `NULL`. Code that tests
`served_by IS NULL` to find unconstrained locations may find none.

---

## Enumerated domains

Values listed below are those in use. These are open sets: new instance sets may
introduce further values, so treat them as documentation of what exists rather than as a
closed constraint. Note that the values are **capitalized** — a predicate written
against lower-case spellings will match nothing. The domain of every column is also
recorded in [`variables/`](variables/).

| Column | Values |
|---|---|
| `papers.id` | `P<n>` for the dataset authors' publications |
| `instance_batches.sensitivity_type` | `default`, `auto`, `exact_comparison`, `few_robot_depots`, `many_robot_depots`, `few_dropoff_points`, `many_dropoff_points`, `low_robot_service_time`, `high_robot_service_time`, `low_robot_availability`, `variable_robot_availability` |
| `instance_batches.city` | `Munich`, `NULL` (synthetic network) |
| `instance_batches.area_size` | `2000 x 2000 m`, `4000 x 4000 m` |
| `instance_batches.depot_location` | `Random` |
| `instance_batches.distribution_of_robot_depots` | `Equal` |
| `instance_batches.distribution_of_dropoff_points` | `Random` |
| `instance_batches.distribution_of_pickup_locations` | `Centered`, `NULL` |
| `instance_batches.no_pickup_locations_determination` | `Fixed`, `NULL` |
| `instance_batches.customer_to_pickup_location_assignment` | `Random`, `NULL` |
| `instance_batches.available_robots_per_depot` | `Fixed`, `Random`, `Variable` |
| `instance_batches.maximum_robots_per_depot` | `Fixed`, `Random` |
| `instance_batches.time_windows_customers` | `Depot Dependent`, `Location Dependent`, `NULL` |
| `instance_batches.time_windows_pickup_customers` | `Pickup Location Dependent`, `NULL` |
| `instance_batches.time_windows_pickup_locations` | `Location Independent`, `NULL` |
| `instance_batches.deadline_multiplicator` | interval as text: `[2, 4]`, `[3, 5]`, `[4, 12]`, `[4, 15]`, `[5, 8]` |
| `instance_batches.no_of_robots` | `<total> (<effective>)`, e.g. `258 (250)`; or the sentinel `Infinity` |
| `network_locations.location_type` | `Depot`, `Robot Hub`, `Drop-off Point` |
| `pickup_locations.location_type` | `Parcel Pickup Point` |
| `customers.customer_type` | `Regular`, `Return`, `Pickup` |
| `customers.served_by`, `pickup_locations.served_by` | `Robot`, `Truck`, `Optional` |
| `vehicles.id` | `diesel_truck`, `e_truck`, `sc_robot` |
| `vehicles.vehicle_type` | `Ground` (trucks), `Autonomous` (robots) |

`sensitivity_type` values encode a direction relative to the `default` batch: `few_*` and
`low_*` reduce the named quantity, `many_*` and `high_*` increase it.

To read the current domain of any enumerated column directly from the data:

```sql
SELECT DISTINCT sensitivity_type FROM metadata.instance_batches ORDER BY 1;
```

---

## Known pitfalls

Six things that will produce wrong results silently if you do not know about them. They
are listed in rough order of how often they bite.

**1. The travel matrix dominates everything.** `raw_data.travel_matrices` grows with the
square of the location count per instance and holds the overwhelming majority of all
rows in the dataset — for reference, it accounts for over 99% of the database volume.
Always restrict it by `instance_key` before joining anything else. A query that joins the
matrix to an instance list without an `instance_key` predicate reads the whole table.

```sql
-- Correct: instance-scoped
SELECT t.* FROM raw_data.travel_matrices t WHERE t.instance_key = 1234;

-- Wrong: reads the entire matrix, then filters
SELECT t.* FROM raw_data.travel_matrices t
JOIN metadata.instances i ON i.key = t.instance_key
WHERE i.id = 'I17';
```

**2. Customer ids are prefixed by type.** `C-`, `CR-` and `CP-` are regular, return and
pickup customers. Selecting customers with `id LIKE 'C-%'` quietly returns only the
regular ones and drops every return and pickup request. Filter on `customer_type`
instead. For the same reason, drop-off points are `S-<n>`, not `D-<n>`.

**3. `no_of_robots` must be parsed, not cast.** The column is `text` and encodes two
numbers — a total and an effective count — plus a sentinel:

| Value | Meaning |
|---|---|
| `258 (250)` | 258 robots in total, 250 effectively usable |
| `Infinity` | unlimited robot fleet |

`::integer` fails on both forms. Parse the leading integer and treat `Infinity`
explicitly:

```sql
SELECT id,
       no_of_robots,
       CASE WHEN no_of_robots = 'Infinity' THEN NULL
            ELSE (regexp_match(no_of_robots, '^\s*(\d+)'))[1]::integer
       END AS robots_total,
       CASE WHEN no_of_robots = 'Infinity' THEN NULL
            ELSE (regexp_match(no_of_robots, '\((\d+)\)'))[1]::integer
       END AS robots_effective,
       no_of_robots = 'Infinity' AS robots_unlimited
FROM metadata.instance_batches;
```

Note that `robots_effective` is `NULL` when the value carries no parenthesised count.

**4. Monetary rates are per meter and per second.** `cost_per_distance` is `EUR/m` and
`cost_per_time` and `delay_cost` are `EUR/s`. Reading `0.0002` as "0.0002 EUR/km"
understates truck cost by a factor of 1000. See
[Units and conventions](#units-and-conventions).

**5. Robot distances are not derivable from the coordinates.** Truck distances follow the
road network; robot distances follow the sidewalk network and are systematically longer
than the straight-line distance between the same two points. There is no factor that
converts one into the other. Coordinates additionally carry no dataset-wide unit. This is
why the `core` dump alone is not sufficient to solve instances, and why the travel
matrices cannot be regenerated from the `core` dump. Please additionally note that this may violate
the triangle inequality and must be ensured per instance.

**6. Service times may be implicitly included in the data.** Service times may be included
in the travel times, or the time windows may be reduced by the travel times. While this may initially seem incorrect or unusual, it allows for a more
accurate representation of time-window violations, as we assume that the entire service,
including its service time, must be completed within the time window. Note that, consequently,
the travel times from i to j and from j to i may differ, and that the paths on which service
times are included may be confusing.

**7. Batch `id` is not a key.** The uniqueness constraint is
`UNIQUE (id, sensitivity_type)`. Grouping by `b.id` alone can merge two distinct
batches that share an identifier.

---

## Provenance

**Instances** of `P5` were generated with the project's configurable instance generator.
The parameters of each batch are recorded in `metadata.instance_batches`, and the
generator's own inputs, modes, terminology and presets are in
[`generation_parameters/generator.yaml`](generation_parameters/generator.yaml).

Publication of the generator source code is work in progress; it is intended to be
released on GitHub shortly.

**Results.** Computational results are not part of this release. Absence of a result for
an instance therefore says nothing about whether the instance has been solved.

---

## Validating a restored database

After restoring a dump, three checks establish that it is complete and internally
consistent. The full versions, with expected outputs, are in
[`../examples/example_queries.sql`](../examples/example_queries.sql).

**Every batch holds the number of instances it claims.** `no_of_instances` is recorded at
generation time and is not enforced by a constraint, so it is a genuine check:

```sql
SELECT p.id AS paper, b.id AS batch, b.sensitivity_type,
       b.no_of_instances AS declared, count(i.key) AS actual
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key          = p.key
LEFT JOIN metadata.instances   i ON i.instance_batch_key = b.key
GROUP BY p.id, b.id, b.sensitivity_type, b.no_of_instances
HAVING b.no_of_instances <> count(i.key)
ORDER BY p.id, b.id;
```

An empty result is the pass condition. Note the `sensitivity_type` in the grouping —
without it, batches that share an `id` under different `sensitivity_type` values are
merged and counted together.

**Every travel matrix is complete.** A matrix must cover every ordered pair of locations
of its instance, including self-pairs:

```sql
WITH loc AS (
    SELECT instance_key, id FROM raw_data.customers
    UNION ALL SELECT instance_key, id FROM raw_data.network_locations
    UNION ALL SELECT instance_key, id FROM raw_data.pickup_locations
),
expected AS (
    SELECT instance_key, count(*) * count(*) AS pairs FROM loc GROUP BY instance_key
),
actual AS (
    SELECT instance_key, count(*) AS pairs FROM raw_data.travel_matrices GROUP BY instance_key
)
SELECT e.instance_key, e.pairs AS expected_pairs, coalesce(a.pairs, 0) AS actual_pairs
FROM expected e LEFT JOIN actual a USING (instance_key)
WHERE coalesce(a.pairs, 0) <> e.pairs
ORDER BY e.instance_key;
```

An empty result is the pass condition. On a `core` dump this check will report every
instance, because `raw_data.travel_matrices` is not part of that dump — that is expected.

**Every location id in a travel matrix resolves.** Since no foreign key can enforce it:

```sql
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

An empty result is the pass condition.
