# Truck-and-Robot Instance Dataset

Benchmark instances for truck-and-robot last-mile delivery problems, published as a
single PostgreSQL database.

In truck-and-robot delivery, a truck carries a number of autonomous delivery robots
into a service area, releases them to serve customers on foot networks, and collects
them again — or lets them return to a robot hub on their own. Instances for these
problems therefore need more than customers and a distance matrix: they need two
separate travel networks, robot supply and capacity per hub, release and collection
points, and time windows that couple truck and robot movements. This dataset provides
all of that in a single, queryable structure, so that instances used across several
publications can be compared without reconciling file formats.

> **This repository is not an independent scientific contribution and must not be
> cited as a standalone dataset.** If you use instances from it, cite the publication
> that the instances belong to. See [Citation](#citation).

---

## Contents

- [What is in here](#what-is-in-here)
- [Repository structure](#repository-structure)
- [Getting the data](#getting-the-data)
- [Data model](#data-model)
- [Selecting the instances you need](#selecting-the-instances-you-need)
- [Units and conventions](#units-and-conventions)
- [Instance generation](#instance-generation)
- [Scope](#scope)
- [Citation](#citation)
- [License](#license)
- [Versioning](#versioning)

---

## What is in here

The dataset is **one** PostgreSQL database, not one file per publication. Instances
belonging to different publications live side by side and are separated by a
foreign-key chain, so a single query selects exactly the instances you want.

What is published is **instance input data** — everything a solver needs to read an
instance and nothing else. It is organized in two schemas:

| Schema | Role | Contents |
|---|---|---|
| `metadata` | descriptive layer | publications, instance batches and their generation parameters, individual instances |
| `raw_data` | solver input | customers, depot, robot hubs, drop-off points, pickup locations, truck and robot travel matrices, vehicle parametrization |

Full column-level documentation is in [`metadata/`](metadata/):

- [`metadata/description.md`](metadata/description.md) — what the dataset contains, how
  the parts relate, units, sentinel values, known pitfalls
- [`metadata/schema/`](metadata/schema/) — annotated DDL, one file per schema
- [`metadata/variables/`](metadata/variables/) — one CSV per table describing every
  column: type, unit, nullability, key role, domain, meaning
- [`metadata/generation_parameters/`](metadata/generation_parameters/) — the instance
  generator's inputs, the modes they offer, and the value each mode is recorded as

Computational results are **not** distributed here; see [Scope](#scope).

---

## Repository structure

```
dataset-truck-robot/
├── README.md
├── LICENSE                                 CC BY-ND 4.0
├── CHANGELOG.md
│
├── database/
│   ├── README.md                           which dump to download, checksums
│   └── truck_robot_core_v1.0.0.sql.gz      core dump, no travel matrices
│
├── metadata/
│   ├── description.md
│   ├── schema/
│   │   ├── metadata.sql
│   │   └── raw_data.sql
│   ├── variables/
│   │   ├── metadata.papers.csv
│   │   ├── metadata.instance_batches.csv
│   │   ├── metadata.instances.csv
│   │   ├── raw_data.customers.csv
│   │   ├── raw_data.network_locations.csv
│   │   ├── raw_data.pickup_locations.csv
│   │   ├── raw_data.travel_matrices.csv
│   │   ├── raw_data.vehicles.csv
│   │   └── raw_data.vehicle_parameters.csv
│   └── generation_parameters/
│       ├── README.md
│       └── generator.yaml                  generator reference: inputs, modes, presets
│
└── examples/
    ├── restore.md                          how to restore the dump
    └── example_queries.sql                 runnable, commented queries
```

---

## Getting the data

Two dumps are published per release. Both are produced from the same database.

| Dump | Size (gzipped) | Contains | Where |
|---|---|---|---|
| **core** | ~2.900 MB | everything **except** `raw_data.travel_matrices` | in this repository, under [`database/`](database/) |
| **full** | ~1.616 GB | everything, including travel matrices | GitHub release asset and Zenodo |

Use the **core** dump to browse the dataset, understand the schema, and select the
instances you need — it clones with the repository and restores in seconds.

Use the **full** dump to actually solve instances. Truck and robot travel times and
distances are precomputed per location pair and are **not** derivable from the
coordinates: robot paths follow a sidewalk network and are longer than the
straight-line distance. Without `raw_data.travel_matrices` the instances are not
solvable.

Restore instructions, including how to restore only selected instances, are in
[`examples/restore.md`](examples/restore.md).

Requires PostgreSQL 13 or newer; the dumps are produced with PostgreSQL 18.

---

## Data model

Every instance is reachable from a publication, and every piece of instance data is
reachable from an instance:

```
metadata.papers                     one row per publication
  └─ metadata.instance_batches      one row per generation configuration
     └─ metadata.instances          one row per instance          ◄── central join target
        ├─ raw_data.customers
        ├─ raw_data.network_locations          depot, robot hubs, drop-off points
        ├─ raw_data.pickup_locations
        └─ raw_data.travel_matrices            truck and robot, per location pair

raw_data.vehicle_parameters attaches to metadata.instance_batches, not to a single
instance: all instances of a batch share one vehicle parametrization.
raw_data.vehicles is the vehicle catalog it references.
```

Three things about this model are worth knowing before you write a query:

**Batches are the unit of generation.** A batch groups all instances produced with an
identical parameter configuration. `metadata.instance_batches` carries those parameters
as columns and is the authoritative record of how instances were generated —
`metadata/generation_parameters/generator.yaml` only adds what cannot be expressed as a
column, and never duplicates it. `sensitivity_type` names the single dimension a batch
varies relative to the `default` batch of the same publication, which makes sensitivity
analyzes selectable with one predicate.

**`key` is internal, `id` is stable.** Every table has an integer `key` used for joins
and a human-readable `id`. The `key` values are assigned by sequences and are **not
stable across releases** — never cite them, never hard-code them. Instance `id` values
such as `I17` are unique only *within* a batch, so reference an instance by its
qualified form:

```
papers.id / instance_batches.id / instances.id      e.g.  P5 / C100-CR0.2-TC0.2 / I17
```

**Location ids share one namespace per instance.** `raw_data.travel_matrices` refers to
locations by id, and the target may live in `customers`, `network_locations` or
`pickup_locations`. The conventions are:

| Pattern | Meaning | Table | Discriminator |
|---|---|---|---|
| `DP` | truck depot | `network_locations` | `location_type = 'Depot'` |
| `R-<n>` | robot hub | `network_locations` | `location_type = 'Robot Hub'` |
| `S-<n>` | drop-off point | `network_locations` | `location_type = 'Drop-off Point'` |
| `C-<n>` | regular delivery customer | `customers` | `customer_type = 'Regular'` |
| `CR-<n>` | return-request customer | `customers` | `customer_type = 'Return'` |
| `CP-<n>` | pickup-request customer | `customers` | `customer_type = 'Pickup'` |
| `P-<n>` | parcel pickup point | `pickup_locations` | `location_type = 'Parcel Pickup Point'` |

Note that drop-off points use the prefix `S-`, not `D-`, and that customers carry a
type-dependent prefix: a query that matches customers by `id LIKE 'C-%'` silently
misses every return and pickup request.

There is deliberately no foreign key on `start_location_id` / `end_location_id`, because
no single table can be the target.

---

## Selecting the instances you need

Selecting everything belonging to one publication is a three-table join:

```sql
SELECT p.id AS paper, b.id AS batch, b.sensitivity_type, i.id AS instance, i.key
FROM metadata.papers            p
JOIN metadata.instance_batches  b ON b.paper_key          = p.key
JOIN metadata.instances         i ON i.instance_batch_key = b.key
WHERE p.id = 'P5'
ORDER BY b.id, i.id;
```

The resulting `i.key` values are what every table in `raw_data` joins on.

> **One performance rule.** `raw_data.travel_matrices` is by far the largest table in
> the dataset — it grows with the square of the location count per instance and holds
> the overwhelming majority of all rows. Always restrict it by `instance_key` before
> joining anything else. A query that joins the travel matrix to the instance list
> without an `instance_key` predicate will read the entire table.

[`examples/example_queries.sql`](examples/example_queries.sql) contains runnable,
commented queries for the common tasks: listing what a release contains, exporting one
complete instance, extracting a travel matrix, comparing sensitivity batches, and
validating a restored database.

---

## Units and conventions

Travel quantities and vehicle parameters are **SI**:

| Quantity | Unit |
|---|---|
| distances in `travel_matrices`, elevation | m |
| times, durations, time windows | s |
| speed | m/s |
| acceleration | m/s² |
| mass | kg |
| area | m² |
| emissions | kg CO₂-equivalent |

Time windows and deadlines are relative to the start of the planning horizon, `t = 0`.

**Coordinates are an exception and carry no dataset-wide unit.** The scale of
`x_coordinate` / `y_coordinate` is chosen per instance set and differs between
publications; values may be negative. They are planar and not georeferenced. Use them
for topology and plotting only — **never derive a distance from them.** Every distance
and travel time you need is precomputed in `raw_data.travel_matrices`, which is the
only authoritative source for them.

**Monetary rates are SI too, and this surprises people.** `cost_per_distance` is
`EUR/m`, not `EUR/km`, and `cost_per_time` and `delay_cost` are `EUR/s`, not `EUR/h`. A
truck at `0.2 EUR/km` is therefore stored as `0.0002`, and a driver wage of `30 EUR/h` as
`0.008333…`. Multiply by `1000` or `3600` to recover the familiar figures. Every one of
those columns carries its unit explicitly in
[`metadata/variables/raw_data.vehicle_parameters.csv`](metadata/variables/raw_data.vehicle_parameters.csv)
and in a `COMMENT ON COLUMN` in the database.

The parameters of the energy and emission model are stored in **SI as well**, not in the
units the emission-model literature uses: `fuel_heating_value` is `J/kg` and not `kJ/g`,
`engine_displacement` is `m³` and not `L`, `battery_capacity` is `J` and not `kWh`, and
so on. Feeding these columns into a published formula unchanged gives a result wrong by
orders of magnitude. The full mapping is in
[`metadata/description.md`](metadata/description.md); the units these parameters are
configured in on the generator side are recorded in
[`metadata/generation_parameters/generator.yaml`](metadata/generation_parameters/generator.yaml).

Two conventions are easy to get wrong and worth stating here:

- **`Infinity` is a sentinel, not a value.** Robot availability and capacity columns are
  `double precision` rather than `integer` specifically so they can hold IEEE-754
  `Infinity`, meaning "unlimited". Never cast these columns to `integer`: the cast
  cannot represent `Infinity` and silently destroys the distinction between "unlimited"
  and an arbitrary bound. All finite values in these columns are whole numbers. The same
  concept appears as the literal text `'Infinity'` in
  `metadata.instance_batches.no_of_robots`.
- **`NULL` means "not applicable", not "zero".** A parameter that a problem variant does
  not model is `NULL`. Coalescing to `0` turns "this batch has no time windows" into
  "every customer must be served at `t = 0`".

The full list, including the domain of every enumerated column, is in
[`metadata/description.md`](metadata/description.md).

---

## Instance generation

Instances were produced with a configurable generator. The parameters of each batch are
recorded in `metadata.instance_batches`; query the database for the authoritative
values:

```sql
SELECT * FROM metadata.instance_batches WHERE id = 'C100-CR0.2-TC0.2';
```

[`metadata/generation_parameters/generator.yaml`](metadata/generation_parameters/generator.yaml)
documents what the database cannot express: which inputs the generator asks for, which
modes each input offers, which label a chosen mode is recorded as, the random seeding
policy, the source of the underlying road and sidewalk networks, and the parameters that
are preset in the generator rather than entered at every run. It is deliberately thin —
there is exactly one authoritative record of the numeric parameters, and it is the
database.

**Publication of the generator itself is work in progress.** The generator source code
is not part of this repository yet; we intend to publish it on GitHub shortly. Until
then, `metadata.instance_batches` together with
[`metadata/generation_parameters/generator.yaml`](metadata/generation_parameters/generator.yaml)
is the complete record of how the instances were produced.

---

## Scope

This dataset publishes **instance input**: everything a solver needs to read and solve an
instance.

Computational results — solver runs, per-thread solutions and routes, aggregated
solution characteristics, algorithmic performance and comparison metrics — are **not
distributed here**. They are withheld until the publications that report them are out,
and are expected to be added later together with the corresponding schema documentation.
Their absence is a publication-timing decision, not a gap in the data model.

Practically, this means:

- the published dumps contain the `metadata` and `raw_data` schemas only;
- every published instance is complete and solvable from the `full` dump;
- no best-known solution values are distributed here, so any objective value you
  produce should be compared against the associated publication, not against this
  repository.

This release contains the instances of publication `P5`. The query under
[Citation](#citation) returns the publication to cite for the instances you used.

---

## Citation

**Do not cite this repository.** It is a distribution channel for instances, not a
scientific contribution in its own right.

If you use instances from this dataset, cite the publication the instances belong to.
Which publication that is follows from the data itself:

```sql
SELECT DISTINCT p.id, p.authors, p.title, p.journal, p.publication_date, p.doi
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key          = p.key
JOIN metadata.instances        i ON i.instance_batch_key = b.key
WHERE i.key IN ( /* the instance keys you used */ );
```

Cite **only** the publications corresponding to the instances you actually used.

| Instance set | Required citation |
|---|---|
| `P5` | Huf, T., & Ostermeier, M. (in press). Return of the robots: The truck-and-robot routing problem with robot reuse and reallocation. *Transportation Science*. [10.1287/trsc.2025.0523](https://doi.org/10.1287/trsc.2025.0523) |

If your study needs a persistent identifier for the data *artifact* — for example for a
journal's data-availability statement — use the Zenodo DOI of the release you used. That
is a reference to a distribution, not a scientific citation, and it does not replace
citing the publications above.

---

## License

The material in this repository that is licensable by the dataset authors is released
under the **Creative Commons Attribution-NoDerivatives 4.0 International License
(CC BY-ND 4.0)**. See [`LICENSE`](LICENSE).

In short — the license text governs, not this summary:

- **You may** use the dataset for any purpose, including commercially; run experiments
  on it; publish results obtained from it; and redistribute it verbatim and unmodified.
- **You must** give appropriate credit and indicate the license. For scientific use, the
  citation requirement above is how you do this.
- **You may not** distribute modified or adapted versions of the dataset — including
  reformatted, filtered, extended or partially extracted redistributions.

Using the data to compute and publish results is *not* an adaptation and is explicitly
permitted. Republishing the instances in another format or as part of another instance
library is, and requires separate permission.

---

## Versioning

Releases follow [Semantic Versioning](https://semver.org/) as applied to data:

- **major** — breaking change to the schema, or a change to existing instance values
- **minor** — new instance sets, new tables, new columns; existing data unchanged
- **patch** — corrections to documentation or metadata; instance values unchanged

`key` values are sequence-assigned and are not stable across releases. Pin the release
you used — by tag and Zenodo DOI — and reference instances by their qualified `id`.

Changes per release are recorded in [`CHANGELOG.md`](CHANGELOG.md).
