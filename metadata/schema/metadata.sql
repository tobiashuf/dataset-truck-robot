-- =============================================================================
-- Schema: metadata
-- =============================================================================
-- Reference DDL for the `metadata` schema of the Truck-and-Robot dataset.
--
-- Purpose of this file
--   Documentation and reference. It describes the structure of the published
--   database dump so that the dump can be understood, queried and validated
--   without restoring it first. Restoring the dump (see examples/restore.md)
--   recreates these objects; you do not need to run this file.
--
-- Scope
--   The `metadata` schema is the entry point of the dataset. It answers:
--     - which publication does an instance belong to?   -> metadata.papers
--     - how was a group of instances generated?         -> metadata.instance_batches
--     - which individual instances exist?               -> metadata.instances
--
-- Conventions
--   - `key`  is the surrogate primary key (integer). It is an internal
--            identifier and is NOT stable across dataset releases.
--   - `id`   is the human-readable business identifier (e.g. 'P5', 'C100-CR0.2-TC0.2',
--            'I17'). Cite and reference instances by `id`, not by `key`.
--   - Ownership, role, grant and tablespace statements are intentionally
--     omitted; they are deployment-specific and not part of the dataset.
--
-- Units
--   See metadata/description.md, section "Units and conventions".
--   The database is strict SI (m, s, m/s, m/s^2, kg, m^2), including for
--   monetary rates: cost_per_distance is EUR/m and cost_per_time is EUR/s.
--   Coordinates are the one exception and carry no unit at all -- their scale
--   is instance-set specific. Enumerated values are Capitalized.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS metadata;

COMMENT ON SCHEMA metadata IS
    'Descriptive layer of the dataset: publications, instance batches, '
    'instances.';


-- -----------------------------------------------------------------------------
-- metadata.papers
-- -----------------------------------------------------------------------------
-- One row per publication that is associated with instances in this dataset.
--
-- This table drives the citation requirement of the dataset: every instance
-- belongs to exactly one batch, and every batch belongs to exactly one paper.
-- Whoever uses instances must cite the paper reachable via that chain.
-- See the "Citation" section of README.md.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.paper_key_seq;

CREATE TABLE metadata.papers
(
    key              integer      NOT NULL DEFAULT nextval('metadata.paper_key_seq'::regclass),
    id               varchar(255) NOT NULL,
    authors          text         NOT NULL,
    title            varchar(255) NOT NULL,
    keywords         text,
    journal          varchar(255),
    doi              varchar(255),
    publication_date date,
    description      text,

    CONSTRAINT paper_pkey   PRIMARY KEY (key),
    CONSTRAINT paper_id_key UNIQUE (id)
);

ALTER SEQUENCE metadata.paper_key_seq OWNED BY metadata.papers.key;

COMMENT ON TABLE  metadata.papers                  IS 'describes relevant information of the papers';
COMMENT ON COLUMN metadata.papers.key              IS 'Surrogate primary key. Internal, not stable across releases.';
COMMENT ON COLUMN metadata.papers.id               IS 'Stable short identifier of the publication, e.g. ''P5''.';
COMMENT ON COLUMN metadata.papers.authors          IS 'Author list in the form ''Lastname I., Lastname I.''.';
COMMENT ON COLUMN metadata.papers.title            IS 'Title of the publication.';
COMMENT ON COLUMN metadata.papers.keywords         IS 'Free-text keywords of the publication.';
COMMENT ON COLUMN metadata.papers.journal          IS 'Journal name. NULL while the publication is unpublished or under review.';
COMMENT ON COLUMN metadata.papers.doi              IS 'DOI without resolver prefix, e.g. ''10.1002/net.22030''. NULL while unpublished.';
COMMENT ON COLUMN metadata.papers.publication_date IS 'Date of publication. NULL while unpublished.';
COMMENT ON COLUMN metadata.papers.description      IS 'Notes on the publication and its relation to the dataset.';


-- -----------------------------------------------------------------------------
-- metadata.instance_batches
-- -----------------------------------------------------------------------------
-- One row per batch of instances generated with an identical parameter
-- configuration. A batch is the unit at which generation parameters are
-- recorded: this table IS the generation-parameter record of the dataset.
-- metadata/generation_parameters/generator.yaml only documents what cannot be
-- expressed as a column here (the generator's inputs and modes, generator
-- version, seeding policy, network source); it never duplicates these values.
--
-- `sensitivity_type` names the dimension that a batch varies relative to the
-- batch marked 'default' of the same paper. This makes sensitivity analyzes
-- selectable with a single predicate.
--
-- Columns are grouped below as: identity, size, demand composition, network,
-- topography, emission zones, robot supply, time windows, bookkeeping.
-- Many columns are only meaningful for problem variants that use the
-- corresponding feature and are NULL otherwise; see
-- metadata/variables/metadata.instance_batches.csv for the per-column domain.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.instance_sets_key_seq1;

CREATE TABLE metadata.instance_batches
(
    -- identity ---------------------------------------------------------------
    paper_key                              integer          NOT NULL,
    key                                    integer          NOT NULL DEFAULT nextval('metadata.instance_sets_key_seq1'::regclass),
    id                                     varchar(255)     NOT NULL,
    sensitivity_type                       varchar(255)     NOT NULL,

    -- size and setting -------------------------------------------------------
    city                                   text,
    no_of_trucks                           integer          NOT NULL,
    no_of_robots                           text             NOT NULL,
    no_of_customers                        integer          NOT NULL,

    -- demand composition (shares in [0, 1]) ----------------------------------
    share_of_truck_customers_regular       double precision NOT NULL,
    share_of_truck_customers_return        double precision,
    share_of_truck_customers_pickup        double precision,
    share_of_truck_pickup_locations        double precision,
    share_of_robot_customers_regular       double precision,
    share_of_robot_customers_return        double precision,
    share_of_robot_customers_pickup        double precision,
    share_of_robot_pickup_locations        double precision,
    share_of_return_customers              double precision NOT NULL,
    share_of_pickup_customers              double precision NOT NULL,

    -- network ----------------------------------------------------------------
    -- NOTE: an AVERAGE, hence double precision, not integer. Takes fractional
    -- values such as 2.9, 5.7 and 6.7.
    no_of_customers_per_pickup_location    double precision NOT NULL,
    no_of_pickup_locations                 integer          NOT NULL,
    no_of_robot_depots                     integer          NOT NULL,
    no_of_dropoff_points                   integer          NOT NULL,

    -- topography -------------------------------------------------------------
    altitude_difference                    double precision,
    altitude_volatility                    double precision,
    area_size                              varchar(255)     NOT NULL,

    -- low emission zones -----------------------------------------------------
    low_emissions_zone_type                text,
    low_emissions_zone_percent             double precision,
    low_emissions_zone_number              integer,

    -- depots and robot supply ------------------------------------------------
    depot_location                         varchar(255)     NOT NULL,
    robot_release_from_depot               boolean          NOT NULL,
    no_pickup_locations_determination      text,
    distribution_of_pickup_locations       text,
    customer_to_pickup_location_assignment text,
    distribution_of_robot_depots           text,
    available_robots_per_depot             varchar(255)     NOT NULL,
    maximum_robots_per_depot               varchar(255)     NOT NULL,

    -- time windows -----------------------------------------------------------
    -- NOTE: the time_window_length_* columns are double precision in SECONDS,
    -- not text. The generator takes minutes and multiplies by 60 on write.
    time_windows_pickup_locations          text,
    time_window_length_pickup_location     double precision,
    time_windows_customers                 text,
    time_window_length_customer            double precision,
    time_windows_pickup_customers          text,
    time_window_length_pickup_customer     double precision,
    deadline_multiplicator                 text,

    -- bookkeeping ------------------------------------------------------------
    no_of_instances                        integer          NOT NULL,
    creation_date                          date             NOT NULL,
    description                            text,

    -- counterpart of distribution_of_robot_depots for drop-off points.
    -- Appended after the column above, hence its position at the end.
    distribution_of_dropoff_points         text,

    CONSTRAINT instance_batches_pkey PRIMARY KEY (key),
    CONSTRAINT unique_id_sensitivity_type UNIQUE (id, sensitivity_type),
    CONSTRAINT instance_batch_paper_key_fkey
        FOREIGN KEY (paper_key) REFERENCES metadata.papers (key) ON DELETE CASCADE
);

ALTER SEQUENCE metadata.instance_sets_key_seq1 OWNED BY metadata.instance_batches.key;

COMMENT ON TABLE metadata.instance_batches IS
    'One row per group of instances sharing an identical generation configuration. '
    'This table is the authoritative record of generation parameters.';

COMMENT ON COLUMN metadata.instance_batches.paper_key                              IS 'Publication this batch belongs to. Determines the citation requirement.';
COMMENT ON COLUMN metadata.instance_batches.key                                    IS 'Surrogate primary key. Internal, not stable across releases.';
COMMENT ON COLUMN metadata.instance_batches.id                                     IS 'Human-readable batch identifier, e.g. ''C100-CR0.2-TC0.2'' or ''C150-CR0.4-TC0.0''. Unique only together with sensitivity_type.';
COMMENT ON COLUMN metadata.instance_batches.sensitivity_type                       IS 'Dimension varied by this batch relative to the ''default'' batch of the same paper. Value ''auto'' marks batches whose design is taken as a whole from the referenced publication rather than varied along one dimension.';
COMMENT ON COLUMN metadata.instance_batches.city                                   IS 'City whose road network was used as the spatial basis. NULL for instances on a synthetic network.';
COMMENT ON COLUMN metadata.instance_batches.no_of_trucks                           IS 'Number of trucks available per instance.';
COMMENT ON COLUMN metadata.instance_batches.no_of_robots                           IS 'Number of robots available per instance, stored as text because it encodes both the total number and number of robots within the robot hubs, e.g. ''258 (250)'', and the sentinel ''Infinity'' for an unlimited robot fleet. Note the capitalization: the sentinel is ''Infinity'', not ''inf''. Parse rather than cast; see metadata/description.md.';
COMMENT ON COLUMN metadata.instance_batches.no_of_customers                        IS 'Number of customers per instance.';
COMMENT ON COLUMN metadata.instance_batches.share_of_return_customers              IS 'Share of customers with a return request, in [0, 1].';
COMMENT ON COLUMN metadata.instance_batches.share_of_pickup_customers              IS 'Share of customers with a pickup request, in [0, 1].';
COMMENT ON COLUMN metadata.instance_batches.no_of_robot_depots                     IS 'Number of robot hubs per instance.';
COMMENT ON COLUMN metadata.instance_batches.no_of_dropoff_points                   IS 'Number of drop-off points per instance.';
COMMENT ON COLUMN metadata.instance_batches.altitude_difference                    IS 'Altitude spread of the generated topography in m. NULL for flat instances.';
COMMENT ON COLUMN metadata.instance_batches.altitude_volatility                    IS 'For synthetic topographies, this factor scales the smoothness of the entire elevation, dimensionless. NULL for flat instances.';
COMMENT ON COLUMN metadata.instance_batches.area_size                              IS 'Nominal label of the service area in meters, ''2000 x 2000 m'' or ''4000 x 4000 m''. Descriptive label ONLY: the coordinates in raw_data carry no dataset-wide unit and bear no arithmetic relationship to this label. Do not parse it to derive an extent.';
COMMENT ON COLUMN metadata.instance_batches.depot_location                          IS 'Rule used to place the truck depot. The generator offers placement at the origin, at the upper left corner, or at random.';
COMMENT ON COLUMN metadata.instance_batches.robot_release_from_depot                IS 'TRUE if robots may be released from the truck depot in addition to classical network locations (robot hubs, drop-off points, and potential customers).';
COMMENT ON COLUMN metadata.instance_batches.distribution_of_robot_depots            IS 'Rule used to place robot depots. ''Equal'' distributes them evenly over the area.';
COMMENT ON COLUMN metadata.instance_batches.distribution_of_dropoff_points          IS 'Rule used to place drop-off points.';
COMMENT ON COLUMN metadata.instance_batches.available_robots_per_depot              IS 'Rule for the initial robot count per hub: ''Fixed'' or ''Variable''. The realized values are in raw_data.network_locations.initial_robot_availability.';
COMMENT ON COLUMN metadata.instance_batches.maximum_robots_per_depot                IS 'Rule for the robot capacity per depot: ''Fixed'' or ''Variable''. The realized values are in raw_data.network_locations.max_robot_capacity.';
COMMENT ON COLUMN metadata.instance_batches.time_windows_customers                  IS 'Rule used to derive customer time windows: ''Depot Dependent'' or ''Flexible''. NULL if the batch has no customer time windows.';
COMMENT ON COLUMN metadata.instance_batches.deadline_multiplicator                  IS 'Interval, written as ''[lower, upper]'', of the multiplier applied to the direct depot-to-customer travel time to obtain the customer deadline.';
COMMENT ON COLUMN metadata.instance_batches.no_of_instances                         IS 'Number of instances generated in this batch.';
COMMENT ON COLUMN metadata.instance_batches.creation_date                           IS 'Date the batch was generated.';
COMMENT ON COLUMN metadata.instance_batches.description                             IS 'Human-readable summary of what distinguishes this batch.';


-- -----------------------------------------------------------------------------
-- metadata.instances
-- -----------------------------------------------------------------------------
-- One row per individual problem instance. This is the central join target:
-- every row in the `raw_data` schema references metadata.instances.key.
--
-- NOTE ON IDENTIFIERS
--   `id` (e.g. 'I17') is unique only WITHIN a batch, enforced by the UNIQUE
--   constraint below. To address an instance unambiguously, always qualify it
--   by its batch and paper:
--       papers.id || '/' || instance_batches.id || '/' || instances.id
--   e.g. 'P5/C100-CR0.2-TC0.2/I17'. Use this qualified form in publications.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.instances_key_seq1;

CREATE TABLE metadata.instances
(
    instance_batch_key integer      NOT NULL,
    key                integer      NOT NULL DEFAULT nextval('metadata.instances_key_seq1'::regclass),
    id                 varchar(255) NOT NULL,

    CONSTRAINT instances_pkey PRIMARY KEY (key),
    CONSTRAINT instances_instance_batch_key_id_key UNIQUE (instance_batch_key, id),
    CONSTRAINT instances_instance_batch_key_fkey
        FOREIGN KEY (instance_batch_key) REFERENCES metadata.instance_batches (key) ON DELETE CASCADE
);

ALTER SEQUENCE metadata.instances_key_seq1 OWNED BY metadata.instances.key;

COMMENT ON TABLE  metadata.instances                    IS 'One row per individual problem instance. Central join target of the dataset.';
COMMENT ON COLUMN metadata.instances.instance_batch_key IS 'Batch this instance belongs to; references metadata.instance_batches.key.';
COMMENT ON COLUMN metadata.instances.key                IS 'Surrogate primary key and the join target of every table in the raw_data schema. Internal, not stable across releases.';
COMMENT ON COLUMN metadata.instances.id                 IS 'Instance identifier within the batch, e.g. ''I17''.';


