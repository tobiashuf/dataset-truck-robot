# Changelog

All notable changes to the Truck-and-Robot Instance Dataset are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/) as applied to data:

- **major** — breaking schema change, or a change to existing instance values
- **minor** — new instance sets, tables or columns; existing data unchanged
- **patch** — corrections to documentation or metadata; instance values unchanged

`key` values are sequence-assigned and are **not stable across releases**. Pin the
release you used and reference instances by their qualified `id`
(`paper / batch / instance`).

---

## [1.0.0] — 2026-09-18

First public release. Archived on Zenodo: [10.5281/zenodo.22833476](https://doi.org/10.5281/zenodo.22833476)

### Added

- Single PostgreSQL database containing the truck-and-robot instances of publication
  `P5`, organized into the `metadata` and `raw_data` schemas.
- `core` dump (without `raw_data.travel_matrices`) distributed in the repository, and
  `full` dump distributed as a release asset and archived on Zenodo.
- Annotated reference DDL per schema in `metadata/schema/`.
- Column-level documentation for every published table in `metadata/variables/`, giving
  type, unit, nullability, key role, domain and meaning. Units are taken from the
  `COMMENT ON COLUMN` text in the database, which is authoritative.
- Instance generator reference in `metadata/generation_parameters/generator.yaml`,
  recording the generator's input panels and the modes they offer, the label each mode is
  recorded as in the database, its terminology, its seeding policy, its city catalog, and
  the parameters that are preset rather than entered at every run.
- Restore instructions in `examples/restore.md`, including selective restore of
  individual batches.
- Runnable example queries in `examples/example_queries.sql`.
- CC BY-ND 4.0 license covering the material licensable by the dataset authors.

### Notes

- **Computational results are not part of this release.** Solver runs, per-thread
  solutions and routes, aggregated solution characteristics, algorithmic performance and
  comparison metrics are withheld until the publications that report them are out, and
  are expected to be added in a later release together with their schema documentation.
  Their absence is a publication-timing decision, not a gap in the data model.
- The instance generator is not part of this repository. Publication of its source code
  is work in progress and is intended to follow on GitHub shortly.
- `CITATION.cff` was deliberately **not** included. It would cause GitHub to offer a
  "Cite this repository" action, which contradicts the citation policy: this repository
  is not an independent scientific contribution and the required citation is always the
  publication associated with the instances used. See the "Citation" section of
  `README.md`.
