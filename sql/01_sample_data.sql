-- =====================================================================================================
-- Step 1 of 7: Sample data
--
-- A small manufacturing dataset in a star schema. Three shared dimension tables (plants, suppliers,
-- parts) are used by four fact tables, one per business domain:
--
--   PURCHASE_ORDERS      Procurement team      what we buy, from whom, at what price
--   QUALITY_INSPECTIONS  Supplier Quality team incoming inspections, defects and NCRs
--   INVENTORY_POSITIONS  Supply Chain team     current stock by part and plant
--   CUSTOMER_ORDERS      Sales Ops team        customer bookings, backlog and on-time delivery
--
-- The data is synthetic but deterministic: values come from HASH() of the row number, so every deploy
-- produces the same rows and the answers in questions.json stay correct.
-- =====================================================================================================

CREATE DATABASE IF NOT EXISTS MULTIAGENT_DEMO;
CREATE SCHEMA IF NOT EXISTS MULTIAGENT_DEMO.DEMO;
USE SCHEMA MULTIAGENT_DEMO.DEMO;

-- ---------------------------------------------------------------------------------------- dimensions

CREATE OR REPLACE TABLE PLANTS (
    plant         VARCHAR PRIMARY KEY,
    plant_region  VARCHAR,
    plant_country VARCHAR
) AS
SELECT * FROM VALUES
    ('Lisle',       'AMERICAS', 'US'),
    ('Guadalajara', 'AMERICAS', 'MX'),
    ('Shannon',     'EMEA',     'IE'),
    ('Penang',      'APAC',     'MY'),
    ('Chengdu',     'APAC',     'CN');

-- 60 suppliers: SUP-001 .. SUP-060
CREATE OR REPLACE TABLE SUPPLIERS AS
SELECT
    'SUP-' || LPAD(n::VARCHAR, 3, '0')                                                    AS supplier_id,
    'Supplier ' || LPAD(n::VARCHAR, 3, '0')                                               AS supplier_name,
    ['Tier 1', 'Tier 2', 'Tier 3'][ABS(HASH(n, 'tier')) % 3]::VARCHAR                     AS supplier_tier,
    ['US', 'MX', 'CN', 'TW', 'DE', 'JP', 'IN'][ABS(HASH(n, 'country')) % 7]::VARCHAR      AS supplier_country,
    ['Strategic', 'Preferred', 'Approved'][ABS(HASH(n, 'segment')) % 3]::VARCHAR          AS supplier_segment,
    ['IATF 16949', 'ISO 9001', 'ISO 13485'][ABS(HASH(n, 'cert')) % 3]::VARCHAR            AS certification
FROM (SELECT SEQ4() + 1 AS n FROM TABLE(GENERATOR(ROWCOUNT => 60)));

-- 300 parts: PN-0001 .. PN-0300
CREATE OR REPLACE TABLE PARTS AS
SELECT
    'PN-' || LPAD(n::VARCHAR, 4, '0')                                                               AS part_id,
    ['Connectors', 'Cable Assemblies', 'Sensors', 'Antennas', 'Switches'][ABS(HASH(n, 'line')) % 5]::VARCHAR
                                                                                                    AS product_line,
    ['Copper Alloy', 'Resin', 'PCB', 'Terminals', 'Plating'][ABS(HASH(n, 'commodity')) % 5]::VARCHAR AS commodity,
    ['Automotive', 'Industrial', 'Datacom', 'Medical'][ABS(HASH(n, 'bu')) % 4]::VARCHAR             AS business_unit,
    ['A', 'B', 'C'][ABS(HASH(n, 'crit')) % 3]::VARCHAR                                              AS criticality,
    ROUND((ABS(HASH(n, 'cost')) % 900 + 10) / 100.0, 2)                                             AS standard_cost_usd
FROM (SELECT SEQ4() + 1 AS n FROM TABLE(GENERATOR(ROWCOUNT => 300)));

-- ------------------------------------------------------------------------------------------- facts
-- Each fact row picks a supplier / part / plant / date from its row number, so rows spread evenly.

CREATE OR REPLACE TABLE PURCHASE_ORDERS AS
SELECT
    n                                                                         AS po_line_id,
    DATEADD(day, -(ABS(HASH(n, 'date')) % 730), DATE '2026-11-01')            AS po_date,
    'SUP-' || LPAD((ABS(HASH(n, 'sup')) % 60 + 1)::VARCHAR, 3, '0')           AS supplier_id,
    'PN-' || LPAD((ABS(HASH(n, 'part')) % 300 + 1)::VARCHAR, 4, '0')          AS part_id,
    ['Lisle', 'Guadalajara', 'Shannon', 'Penang', 'Chengdu'][ABS(HASH(n, 'plant')) % 5]::VARCHAR AS plant,
    ABS(HASH(n, 'qty')) % 5000 + 50                                           AS quantity,
    ROUND((ABS(HASH(n, 'price')) % 900 + 10) / 100.0, 2)                      AS unit_price_usd,
    ['FCA', 'DAP', 'DDP', 'FOB'][ABS(HASH(n, 'inco')) % 4]::VARCHAR           AS incoterm
FROM (SELECT SEQ4() + 1 AS n FROM TABLE(GENERATOR(ROWCOUNT => 40000)));

CREATE OR REPLACE TABLE QUALITY_INSPECTIONS AS
SELECT
    n                                                                         AS inspection_id,
    DATEADD(day, -(ABS(HASH(n, 'date')) % 730), DATE '2026-11-01')            AS inspection_date,
    'SUP-' || LPAD((ABS(HASH(n, 'sup')) % 60 + 1)::VARCHAR, 3, '0')           AS supplier_id,
    'PN-' || LPAD((ABS(HASH(n, 'part')) % 300 + 1)::VARCHAR, 4, '0')          AS part_id,
    ['Lisle', 'Guadalajara', 'Shannon', 'Penang', 'Chengdu'][ABS(HASH(n, 'plant')) % 5]::VARCHAR AS plant,
    ABS(HASH(n, 'inspected')) % 2000 + 100                                    AS qty_inspected,
    -- About 18% of lots have defects, 0-11 parts each.
    IFF(ABS(HASH(n, 'has_defect')) % 100 < 18, ABS(HASH(n, 'defects')) % 12, 0) AS qty_defective,
    ['Dimensional', 'Cosmetic', 'Plating', 'Electrical'][ABS(HASH(n, 'cat')) % 4]::VARCHAR AS defect_category,
    -- A non-conformance report (NCR) is raised on about 4% of inspections.
    IFF(ABS(HASH(n, 'ncr')) % 100 < 4, 1, 0)                                  AS ncr_raised
FROM (SELECT SEQ4() + 1 AS n FROM TABLE(GENERATOR(ROWCOUNT => 30000)));

-- One row per part per plant (300 x 5).
CREATE OR REPLACE TABLE INVENTORY_POSITIONS AS
SELECT
    p.part_id,
    l.plant,
    ABS(HASH(p.part_id, l.plant, 'on_hand')) % 4000             AS on_hand_qty,
    ABS(HASH(p.part_id, l.plant, 'safety')) % 1500 + 500        AS safety_stock_qty,
    ABS(HASH(p.part_id, l.plant, 'usage')) % 300 + 20           AS avg_daily_usage
FROM PARTS p CROSS JOIN PLANTS l;

CREATE OR REPLACE TABLE CUSTOMER_ORDERS AS
SELECT
    n                                                                         AS order_line_id,
    DATEADD(day, -(ABS(HASH(n, 'date')) % 730), DATE '2026-11-01')            AS order_date,
    'CUST-' || LPAD((ABS(HASH(n, 'cust')) % 80 + 1)::VARCHAR, 3, '0')         AS customer_id,
    ['Automotive OEM', 'Industrial', 'Datacenter', 'Medical Device'][ABS(HASH(n, 'seg')) % 4]::VARCHAR AS customer_segment,
    'PN-' || LPAD((ABS(HASH(n, 'part')) % 300 + 1)::VARCHAR, 4, '0')          AS part_id,
    ['Lisle', 'Guadalajara', 'Shannon', 'Penang', 'Chengdu'][ABS(HASH(n, 'plant')) % 5]::VARCHAR AS plant,
    ABS(HASH(n, 'qty')) % 3000 + 20                                           AS order_qty,
    ROUND((ABS(HASH(n, 'price')) % 1500 + 30) / 100.0, 2)                     AS unit_price_usd,
    -- About 12% of lines are still open (the backlog); 88% of shipped lines were on time.
    IFF(ABS(HASH(n, 'open')) % 100 < 12, 'Open', 'Shipped')                   AS line_status,
    IFF(ABS(HASH(n, 'ontime')) % 100 < 88, 1, 0)                              AS shipped_on_time
FROM (SELECT SEQ4() + 1 AS n FROM TABLE(GENERATOR(ROWCOUNT => 40000)));
