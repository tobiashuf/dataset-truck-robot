-- =============================================================================
-- Truck-and-Robot Instance Dataset -- example queries
-- =============================================================================
-- Runnable, self-contained queries for the common tasks. Every query works
-- against a restored dump with no additional setup.
--
-- Tested against PostgreSQL 18; requires 13 or newer.
--
-- Sections
--   1  What does this release contain?
--   2  Finding instances
--   3  Reading one complete instance
--   4  Selecting instances by characteristics
--   5  Sensitivity analysis
--   6  Working around the awkward columns
--   7  Validating a restored database
--   8  Producing the citation you owe
--
-- THREE RULES THAT APPLY TO EVERY QUERY BELOW
--
--   1. Always restrict raw_data.travel_matrices by instance_key before joining
--      anything else. It holds over 99% of the rows in the dataset; a query
--      without that predicate reads the entire table.
--
--   2. Carry metadata.instance_batches.sensitivity_type alongside its id. The
--      uniqueness constraint is UNIQUE (id, sensitivity_type), so grouping by
--      id alone can merge two distinct batches.
--
--   3. Match customers on customer_type, not on an id prefix. Ids are
--      'C-<n>' regular, 'CR-<n>' return and 'CP-<n>' pickup, so a filter of
--      id LIKE 'C-%' silently drops return and pickup requests. For the same
--      reason drop-off points are 'S-<n>', not 'D-<n>'.
--
-- See ../metadata/description.md for units, sentinel values and pitfalls.
-- =============================================================================


-- =============================================================================
-- 1  What does this release contain?
-- =============================================================================

-- 1.1  Publications, with how many instances each contributes.
--      This is also the table you need to know which papers to cite.
SELECT p.id                       AS publication,
       p.authors,
       p.title,
       p.journal,
       p.publication_date,
       p.doi,
       count(DISTINCT b.key)      AS batches,
       count(i.key)               AS instances
FROM metadata.papers                p
LEFT JOIN metadata.instance_batches b ON b.paper_key        = p.key
LEFT JOIN metadata.instances        i ON i.instance_batch_key = b.key
GROUP BY p.key, p.id, p.authors, p.title, p.journal, p.publication_date, p.doi
ORDER BY p.id;


-- 1.2  Every batch, with the dimension it varies and its headline parameters.
SELECT p.id               AS publication,
       b.id               AS batch,
       b.sensitivity_type,
       b.no_of_customers,
       b.no_of_trucks,
       b.no_of_robots,
       b.no_of_robot_depots,
       b.no_of_dropoff_points,
       b.area_size,
       b.city,
       b.no_of_instances  AS declared_instances,
       count(i.key)       AS actual_instances,
       b.description
FROM metadata.papers                p
JOIN metadata.instance_batches      b ON b.paper_key        = p.key
LEFT JOIN metadata.instances        i ON i.instance_batch_key = b.key
GROUP BY p.id, b.key, b.id, b.sensitivity_type, b.no_of_customers, b.no_of_trucks,
         b.no_of_robots, b.no_of_robot_depots, b.no_of_dropoff_points, b.area_size,
         b.city, b.no_of_instances, b.description
ORDER BY p.id, b.id;


-- 1.3  Size of each table. Useful before running anything expensive.
SELECT n.nspname || '.' || c.relname            AS table_name,
       c.reltuples::bigint                      AS approx_rows,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname IN ('metadata', 'raw_data')
ORDER BY pg_total_relation_size(c.oid) DESC;


-- =============================================================================
-- 2  Finding instances
-- =============================================================================

-- 2.1  Qualified identifier for every instance.
--      Instance id ('I17') repeats across batches -- always reference an
--      instance in this qualified form in a publication.
SELECT p.id || ' / ' || b.id || ' / ' || i.id AS qualified_id,
       i.key                                  AS instance_key
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key        = p.key
JOIN metadata.instances        i ON i.instance_batch_key = b.key
ORDER BY p.id, b.id, i.id;


-- 2.2  Resolve a qualified identifier to the internal key you join on.
SELECT i.key AS instance_key
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key        = p.key
JOIN metadata.instances        i ON i.instance_batch_key = b.key
WHERE p.id = 'P5'
  AND b.id = 'C100-CR0.2-TC0.2'
  AND i.id = 'I17';


-- 2.3  All instance keys of one publication -- the input to any bulk export.
SELECT i.key
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key        = p.key
JOIN metadata.instances        i ON i.instance_batch_key = b.key
WHERE p.id = 'P5'
ORDER BY i.key;


-- =============================================================================
-- 3  Reading one complete instance
-- =============================================================================
-- Everything below is scoped by a single instance_key. Set it once.

-- 3.1  Customers of one instance.
--      Coordinates in m, time windows in s relative to t = 0.
SELECT c.id,
       c.x_coordinate,
       c.y_coordinate,
       c.z_coordinate,
       c.customer_type,
       c.priority,
       c.parcel_demand,
       c.parcel_weight,
       c.served_by,
       c.time_window_start,
       c.time_window_end,
       c.parcel_origin_id
FROM raw_data.customers c
WHERE c.instance_key = 1
ORDER BY c.id;


-- 3.2  Depot, robot hubs and drop-off points of one instance.
--      initial_robot_availability and max_robot_capacity use Infinity for
--      "unlimited" -- never cast them to integer.
SELECT n.id,
       n.location_type,
       n.x_coordinate,
       n.y_coordinate,
       n.z_coordinate,
       n.initial_robot_availability,
       n.max_robot_capacity,
       n.charging_station
FROM raw_data.network_locations n
WHERE n.instance_key = 1
ORDER BY n.location_type, n.id;


-- 3.3  Every location of one instance, in one result set.
--      This is the referent of travel_matrices.start_location_id /
--      .end_location_id: the three location tables share one id namespace per
--      instance, which is why no foreign key can be defined on those columns.
WITH locations AS (
    SELECT instance_key, id, x_coordinate, y_coordinate, z_coordinate,
           'Customer'  AS kind, customer_type AS subtype
    FROM raw_data.customers
    UNION ALL
    SELECT instance_key, id, x_coordinate, y_coordinate, z_coordinate,
           'Network'   AS kind, location_type AS subtype
    FROM raw_data.network_locations
    UNION ALL
    SELECT instance_key, id, x_coordinate, y_coordinate, z_coordinate,
           'Pickup'    AS kind, location_type AS subtype
    FROM raw_data.pickup_locations
)
SELECT id, kind, subtype, x_coordinate, y_coordinate, z_coordinate
FROM locations
WHERE instance_key = 1
ORDER BY kind, id;


-- 3.4  Travel matrix of one instance, in long form.
--      Truck values follow the road network, robot values the sidewalk
--      network. Neither is derivable from the other, and robot distances are
--      not derivable from the coordinates.
SELECT t.start_location_id,
       t.end_location_id,
       t.truck_time,
       t.truck_distance,
       t.robot_time,
       t.robot_distance,
       t.truck_emission,
       t.robot_emission
FROM raw_data.travel_matrices t
WHERE t.instance_key = 1
ORDER BY t.start_location_id, t.end_location_id;


-- 3.5  Vehicle parametrization applying to an instance.
--      Note the join: vehicle parameters attach to the BATCH, not the
--      instance, because all instances of a batch share them.
SELECT v.id           AS vehicle,
       v.vehicle_type,
       vp.max_robots,
       vp.initial_robots,
       vp.max_parcels,
       vp.speed_min,
       vp.speed_max,
       vp.service_time,
       vp.cost_per_distance,
       vp.cost_per_time,
       vp.max_load,
       vp.battery_capacity
FROM metadata.instances             i
JOIN metadata.instance_batches      b  ON b.key = i.instance_batch_key
JOIN raw_data.vehicle_parameters    vp ON vp.instance_batch_key = b.key
JOIN raw_data.vehicles              v  ON v.key = vp.vehicle_key
WHERE i.key = 1
ORDER BY v.vehicle_type, v.id;


-- 3.6  One instance as a single summary row -- a sanity check before export.
SELECT p.id || ' / ' || b.id || ' / ' || i.id AS qualified_id,
       (SELECT count(*) FROM raw_data.customers        c WHERE c.instance_key = i.key) AS customers,
       (SELECT count(*) FROM raw_data.network_locations n WHERE n.instance_key = i.key) AS network_locations,
       (SELECT count(*) FROM raw_data.pickup_locations  l WHERE l.instance_key = i.key) AS pickup_locations,
       (SELECT count(*) FROM raw_data.travel_matrices   t WHERE t.instance_key = i.key) AS matrix_entries
FROM metadata.instances        i
JOIN metadata.instance_batches b ON b.key = i.instance_batch_key
JOIN metadata.papers           p ON p.key = b.paper_key
WHERE i.key = 1;


-- =============================================================================
-- 4  Selecting instances by characteristics
-- =============================================================================

-- 4.1  Instances matching a target size and setting.
SELECT p.id AS publication, b.id AS batch, i.id AS instance, i.key,
       b.no_of_customers, b.no_of_robot_depots, b.area_size
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key        = p.key
JOIN metadata.instances        i ON i.instance_batch_key = b.key
WHERE b.no_of_customers BETWEEN 75 AND 125
  AND b.no_of_robot_depots >= 16
  AND b.city = 'Munich'
ORDER BY b.no_of_customers, b.id, i.id;


-- 4.2  Instances that actually carry customer time windows.
--      NULL means "this batch does not model time windows" -- not "t = 0".
SELECT DISTINCT p.id AS publication, b.id AS batch, b.time_windows_customers,
       b.deadline_multiplicator
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key = p.key
WHERE b.time_windows_customers IS NOT NULL
ORDER BY p.id, b.id;


-- 4.3  Instances with an unlimited robot fleet, and those without.
SELECT p.id AS publication, b.id AS batch,
       b.no_of_robots,
       b.no_of_robots = 'Infinity' AS robots_unlimited
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key = p.key
ORDER BY robots_unlimited DESC, p.id, b.id;


-- 4.4  Instances whose robot hubs have a binding capacity.
--      Infinity in max_robot_capacity means unlimited, so a finite maximum is
--      what makes hub capacity a constraint.
SELECT DISTINCT i.key, i.id, b.id AS batch
FROM metadata.instances         i
JOIN metadata.instance_batches  b ON b.key = i.instance_batch_key
JOIN raw_data.network_locations n ON n.instance_key = i.key
WHERE n.location_type = 'Robot Hub'
  AND n.max_robot_capacity IS NOT NULL
  AND n.max_robot_capacity <> 'Infinity'::double precision
ORDER BY b.id, i.id;


-- =============================================================================
-- 5  Sensitivity analysis
-- =============================================================================

-- 5.1  What each batch of a publication varies, next to the default.
--      sensitivity_type names the single dimension varied relative to the
--      batch with sensitivity_type = 'default'.
SELECT b.sensitivity_type,
       b.id                   AS batch,
       b.no_of_customers,
       b.no_of_robot_depots,
       b.no_of_dropoff_points,
       b.no_of_robots,
       b.description
FROM metadata.instance_batches b
JOIN metadata.papers           p ON p.key = b.paper_key
WHERE p.id = 'P5'
ORDER BY b.no_of_customers,
         (b.sensitivity_type <> 'default'),   -- default first within each size
         b.sensitivity_type;


-- 5.2  Each sensitivity batch paired with its default, same customer count.
--      Gives you the two instance sets to compare, without hand-maintaining
--      a list of batch names.
WITH batches AS (
    SELECT b.key, b.id, b.sensitivity_type, b.no_of_customers, p.id AS paper
    FROM metadata.instance_batches b
    JOIN metadata.papers           p ON p.key = b.paper_key
    WHERE p.id = 'P5'
)
SELECT v.sensitivity_type,
       d.id AS default_batch,
       v.id AS variant_batch,
       v.no_of_customers
FROM batches v
JOIN batches d
  ON d.paper           = v.paper
 AND d.no_of_customers = v.no_of_customers
 AND d.sensitivity_type = 'default'
WHERE v.sensitivity_type <> 'default'
ORDER BY v.no_of_customers, v.sensitivity_type;


-- =============================================================================
-- 6  Working around the awkward columns
-- =============================================================================

-- 6.1  Parse metadata.instance_batches.no_of_robots.
--      It is text and encodes a total, an optional effective count in
--      parentheses, and the sentinel 'Infinity'. ::integer fails on both forms.
SELECT b.id                                   AS batch,
       b.no_of_robots                         AS raw_value,
       b.no_of_robots = 'Infinity'                 AS robots_unlimited,
       CASE WHEN b.no_of_robots = 'Infinity' THEN NULL
            ELSE (regexp_match(b.no_of_robots, '^\s*(\d+)'))[1]::integer
       END                                    AS robots_total,
       CASE WHEN b.no_of_robots = 'Infinity' THEN NULL
            ELSE (regexp_match(b.no_of_robots, '\((\d+)\)'))[1]::integer
       END                                    AS robots_effective
FROM metadata.instance_batches b
ORDER BY b.id;


-- 6.2  Parse deadline_multiplicator, stored as the text '[lower, upper]'.
SELECT b.id                                                             AS batch,
       b.deadline_multiplicator                                         AS raw_value,
       (regexp_match(b.deadline_multiplicator, '\[\s*([0-9.]+)'))[1]::numeric AS deadline_lower,
       (regexp_match(b.deadline_multiplicator, ',\s*([0-9.]+)\s*\]'))[1]::numeric AS deadline_upper
FROM metadata.instance_batches b
WHERE b.deadline_multiplicator IS NOT NULL
ORDER BY b.id;


-- 6.3  Read the unit and meaning of every column straight from the database.
--      Often faster than opening the documentation. In psql, \d+ does the same.
SELECT a.attname                              AS column_name,
       format_type(a.atttypid, a.atttypmod)    AS data_type,
       NOT a.attnotnull                        AS nullable,
       col_description(c.oid, a.attnum)        AS comment
FROM pg_class     c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'raw_data'
  AND c.relname = 'vehicle_parameters'
ORDER BY a.attnum;


-- =============================================================================
-- 7  Validating a restored database
-- =============================================================================
-- For each check below, AN EMPTY RESULT IS THE PASS CONDITION.

-- 7.1  Every batch holds the number of instances it declares.
--      no_of_instances is recorded at generation time and not enforced by a
--      constraint, so this is a real check.
--      Note sensitivity_type in the grouping: batch id alone is not unique, so
--      omitting it merges batches that share an id.
SELECT p.id AS publication, b.id AS batch, b.sensitivity_type,
       b.no_of_instances AS declared, count(i.key) AS actual
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key          = p.key
LEFT JOIN metadata.instances   i ON i.instance_batch_key = b.key
GROUP BY p.id, b.id, b.sensitivity_type, b.no_of_instances
HAVING b.no_of_instances <> count(i.key)
ORDER BY p.id, b.id;


-- 7.2  Every instance has exactly one depot and at least one customer.
SELECT i.key, i.id,
       (SELECT count(*) FROM raw_data.network_locations n
         WHERE n.instance_key = i.key AND n.location_type = 'Depot') AS depots,
       (SELECT count(*) FROM raw_data.customers c
         WHERE c.instance_key = i.key)                               AS customers
FROM metadata.instances i
WHERE (SELECT count(*) FROM raw_data.network_locations n
        WHERE n.instance_key = i.key AND n.location_type = 'Depot') <> 1
   OR (SELECT count(*) FROM raw_data.customers c
        WHERE c.instance_key = i.key) = 0
ORDER BY i.key
LIMIT 100;


-- 7.3  Every travel matrix covers every ordered pair of its locations,
--      including self-pairs.
--      Skip this check on a core dump: travel_matrices is empty there by
--      design, so every instance will be reported.
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
SELECT e.instance_key,
       e.pairs                 AS expected_pairs,
       coalesce(a.pairs, 0)    AS actual_pairs
FROM expected e
LEFT JOIN actual a USING (instance_key)
WHERE coalesce(a.pairs, 0) <> e.pairs
ORDER BY e.instance_key
LIMIT 100;


-- 7.4  Every location id used in a travel matrix resolves to a location.
--      No foreign key can enforce this, because the referent may live in any
--      of the three location tables.
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


-- 7.5  Self-pairs have zero travel, and no travel value is negative.
SELECT t.instance_key, t.start_location_id, t.end_location_id,
       t.truck_time, t.truck_distance, t.robot_time, t.robot_distance
FROM raw_data.travel_matrices t
WHERE (t.start_location_id = t.end_location_id
       AND (coalesce(t.truck_distance, 0) <> 0 OR coalesce(t.robot_distance, 0) <> 0
         OR coalesce(t.truck_time, 0)     <> 0 OR coalesce(t.robot_time, 0)     <> 0))
   OR t.truck_time     < 0 OR t.robot_time     < 0
   OR t.truck_distance < 0 OR t.robot_distance < 0
LIMIT 100;


-- 7.6  Demand composition shares are within [0, 1].
SELECT b.id AS batch,
       b.share_of_truck_customers_regular,
       b.share_of_return_customers,
       b.share_of_pickup_customers
FROM metadata.instance_batches b
WHERE b.share_of_truck_customers_regular NOT BETWEEN 0 AND 1
   OR b.share_of_return_customers        NOT BETWEEN 0 AND 1
   OR b.share_of_pickup_customers        NOT BETWEEN 0 AND 1
ORDER BY b.id;


-- 7.7  Every time window is well formed: start no later than end.
SELECT c.instance_key, c.id, c.time_window_start, c.time_window_end
FROM raw_data.customers c
WHERE c.time_window_start IS NOT NULL
  AND c.time_window_end   IS NOT NULL
  AND c.time_window_start > c.time_window_end
ORDER BY c.instance_key, c.id
LIMIT 100;


-- =============================================================================
-- 8  Producing the citation you owe
-- =============================================================================
-- This repository must not be cited. Cite the publication that the instances
-- you used belong to. Replace the key list with the instances your study
-- actually used, and cite exactly what comes back.

SELECT DISTINCT p.id  AS publication,
       p.authors,
       p.title,
       p.journal,
       p.publication_date,
       p.doi
FROM metadata.papers           p
JOIN metadata.instance_batches b ON b.paper_key        = p.key
JOIN metadata.instances        i ON i.instance_batch_key = b.key
WHERE i.key IN (1, 2, 3)          -- <-- the instance keys you used
ORDER BY p.id;
