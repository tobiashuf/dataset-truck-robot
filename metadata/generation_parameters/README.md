# Generation parameters

One file, [`generator.yaml`](generator.yaml), describing **how** instances are generated:
which inputs the instance generator asks for, which modes each input offers, and which
value a chosen mode ends up as in the database.

---

## What belongs in this file, and what does not

`metadata.instance_batches` already holds the numeric generation parameters as columns —
customer counts, truck and robot counts, demand composition shares, robot hub and
drop-off point counts, topography settings, time-window rules, deadline intervals. That
table **is** the authoritative generation-parameter record of the dataset.

`generator.yaml` therefore carries only what a database column cannot express:

| Belongs here | Belongs in `metadata.instance_batches` |
|---|---|
| generator name and version | customer / truck / robot counts |
| the inputs and modes the generator offers | demand composition shares |
| which value a mode is recorded as | hub and drop-off point counts |
| random seeding policy | time-window rules and deadline intervals |
| source of the road and sidewalk networks | area size, city, topography settings |
| parameters that are preset rather than entered per run | anything else already a column |

The rule is deliberate: there is exactly one source of truth for every parameter. A YAML
file that repeated the numeric values would go stale the moment a batch was regenerated,
and a reader would have no way to tell which of the two was right. Where `generator.yaml`
and the database disagree, **the database is right** — a preset in the file is the
starting point of a generation session, not a record of what was run.

To read the authoritative values, query the database:

```sql
SELECT * FROM metadata.instance_batches WHERE id = 'C100-CR0.2-TC0.2';
```

```sql
-- All batches of a publication, with the dimension each one varies
SELECT b.id, b.sensitivity_type, b.no_of_customers, b.no_of_robot_depots,
       b.no_of_dropoff_points, b.no_of_instances, b.description
FROM metadata.instance_batches b
JOIN metadata.papers           p ON p.key = b.paper_key
WHERE p.id = 'P5'
ORDER BY b.no_of_customers, b.sensitivity_type;
```

---

## How `generator.yaml` is organized

| Block | Contents |
|---|---|
| `generator` | name, version, interface, publication status |
| `parameter_groups` | the generator's input panels, in the order it presents them — one entry per panel, with its inputs, its options or modes, and the label each choice is recorded as |
| `not_modeled_semantics` | which model components are optional, and what the database looks like when one is not modeled |
| `randomization` | random number generator and seeding policy |
| `planning_horizon` | the horizon all time windows are relative to |
| `spatial_basis` | elevation source, coordinate frame, and the city catalog with the anchor and elevation tile per city |
| `customer_sampling` | how customer locations are drawn |
| `vehicles` | the vehicle catalog behind `raw_data.vehicles` |
| `preset_parameters` | parameters configured once in the generator rather than entered at every run: energy and emission model, kinematics, masses, efficiencies, interruptions, deadline multipliers |

Within `parameter_groups`, `inputs` are the values a run is asked for, `options` and
`modes` are the choices an input offers — `modes` where the generator carries an internal
code for the choice — and `stored_as` gives the label written to the database wherever it
differs from the label shown in the interface.

### Read `generator.yaml` first

It carries three things you will otherwise trip over:

1. **Interface labels are not database values.** A mode shown as `Random` in the
   generator may be recorded as `Location Independent`; entering the depot location as
   `Origin` is recorded as `Centered`. The `stored_as` entries give the mapping. 
   This will adjusted in the future.
2. **Units differ.** The generator takes km, km/h, EUR/km, EUR/h and minutes; the
   database stores strict SI — m, m/s, EUR/m, EUR/s and seconds. A value in the database
   will not look like the value that was entered. The unit of every column is documented
   in [`../variables/`](../variables/) and in a `COMMENT ON COLUMN` in the database.

### Which model components are optional

The energy and emission model, access-restricted zones and topography are optional in
the generator. A batch models them only if the corresponding inputs were set; otherwise
the matching database columns are `NULL`, meaning "not applicable to this batch" — never
zero. The one exception is the unconstrained vehicle assignment, which is recorded as the
literal string `'Optional'` rather than as `NULL`.

---

## The generator

Publication of the instance generator is **work in progress**. The source code is not
part of this repository yet; we intend to release it on GitHub shortly.

Until then, `generator.yaml` together with `metadata.instance_batches` is the record of
how the instances were produced.
