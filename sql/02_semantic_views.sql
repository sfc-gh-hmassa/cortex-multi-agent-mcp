-- =====================================================================================================
-- Step 2 of 7: Semantic views (one per domain)
--
-- Each specialist agent answers questions through one semantic view. A semantic view tells Cortex
-- Analyst how the business talks about the data: which tables join, what each column means, how
-- metrics are calculated, which synonyms people use, and some verified example queries.
--
-- This content is also what the "before" pattern was paying for: when a specialist returned its full
-- response, its semantic view context traveled back into the orchestrator's context window on every call.
-- =====================================================================================================

USE SCHEMA MULTIAGENT_DEMO.DEMO;

-- ------------------------------------------------------------------------------------- Procurement

CREATE OR REPLACE SEMANTIC VIEW PROCUREMENT_SV
  TABLES (
    po        AS PURCHASE_ORDERS PRIMARY KEY (po_line_id)
              COMMENT = 'One row per purchase order line placed with a supplier.',
    suppliers AS SUPPLIERS PRIMARY KEY (supplier_id)
              COMMENT = 'Approved suppliers and their classification.',
    parts     AS PARTS PRIMARY KEY (part_id)
              COMMENT = 'Part master: product line, commodity and standard cost.',
    plants    AS PLANTS PRIMARY KEY (plant)
              COMMENT = 'Manufacturing plants that receive the goods.'
  )
  RELATIONSHIPS (
    po_supplier AS po (supplier_id) REFERENCES suppliers,
    po_part     AS po (part_id)     REFERENCES parts,
    po_plant    AS po (plant)       REFERENCES plants
  )
  FACTS (
    po.quantity       AS quantity       COMMENT = 'Units ordered on the line.',
    po.unit_price_usd AS unit_price_usd COMMENT = 'Negotiated price per unit, in USD.',
    po.line_spend_usd AS quantity * unit_price_usd
                      COMMENT = 'Spend for the line: quantity times unit price, in USD.'
  )
  DIMENSIONS (
    po.po_date        AS po_date WITH SYNONYMS = ('order date', 'purchase date')
                      COMMENT = 'Date the purchase order line was placed.',
    po.incoterm       AS incoterm WITH SYNONYMS = ('shipping terms', 'delivery terms')
                      COMMENT = 'Incoterm on the order: FCA, DAP, DDP or FOB.',
    suppliers.supplier_id      AS supplier_id WITH SYNONYMS = ('supplier', 'vendor', 'vendor id')
                      COMMENT = 'Supplier identifier, formatted SUP-###.',
    suppliers.supplier_name    AS supplier_name COMMENT = 'Supplier display name.',
    suppliers.supplier_tier    AS supplier_tier WITH SYNONYMS = ('tier')
                      COMMENT = 'Position in the supply network: Tier 1 ships to us directly.',
    suppliers.supplier_country AS supplier_country COMMENT = 'Country of the supplier''s main site.',
    suppliers.supplier_segment AS supplier_segment WITH SYNONYMS = ('segment', 'strategic')
                      COMMENT = 'Sourcing segment: Strategic, Preferred or Approved.',
    parts.part_id       AS part_id WITH SYNONYMS = ('part', 'part number', 'PN')
                      COMMENT = 'Part number, formatted PN-####.',
    parts.product_line  AS product_line COMMENT = 'Product line the part belongs to, e.g. Connectors.',
    parts.commodity     AS commodity WITH SYNONYMS = ('category', 'spend category')
                      COMMENT = 'Commodity the part is bought under, e.g. Copper Alloy or Resin.',
    parts.business_unit AS business_unit WITH SYNONYMS = ('BU', 'division')
                      COMMENT = 'Business unit that uses the part.',
    plants.plant        AS plant WITH SYNONYMS = ('site', 'factory')
                      COMMENT = 'Receiving plant: Lisle, Guadalajara, Shannon, Penang or Chengdu.',
    plants.plant_region AS plant_region WITH SYNONYMS = ('region')
                      COMMENT = 'Region of the receiving plant: AMERICAS, EMEA or APAC.'
  )
  METRICS (
    po.total_spend_usd AS SUM(po.line_spend_usd) WITH SYNONYMS = ('spend', 'purchase spend', 'total spend')
                       COMMENT = 'Total purchase spend in USD. The default measure for "spend" questions.',
    po.units_purchased AS SUM(po.quantity) COMMENT = 'Total units purchased.',
    po.po_line_count   AS COUNT(po.po_line_id) WITH SYNONYMS = ('number of orders', 'PO lines')
                       COMMENT = 'Number of purchase order lines.',
    po.avg_unit_price_usd AS SUM(po.line_spend_usd) / NULLIF(SUM(po.quantity), 0)
                       COMMENT = 'Volume-weighted average unit price, in USD.'
  )
  COMMENT = 'Procurement spend: what we buy, from which suppliers, at what price.'
  AI_SQL_GENERATION 'Spend means total_spend_usd unless the user asks for units. When ranking suppliers, return supplier_id and the metric, ordered descending. Dates are order dates; "last year" means the 12 months before the latest po_date.'
  AI_VERIFIED_QUERIES (
    top_suppliers_by_spend AS (
      QUESTION 'Which 5 suppliers have the highest total purchase spend?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT supplier_id, SUM(quantity * unit_price_usd) AS total_spend_usd FROM __po GROUP BY supplier_id ORDER BY total_spend_usd DESC LIMIT 5'
    ),
    spend_by_commodity AS (
      QUESTION 'What is total spend by commodity?'
      SQL 'SELECT p.commodity, SUM(o.quantity * o.unit_price_usd) AS total_spend_usd FROM __po o JOIN __parts p ON o.part_id = p.part_id GROUP BY p.commodity ORDER BY total_spend_usd DESC'
    )
  );

-- -------------------------------------------------------------------------------- Supplier quality

CREATE OR REPLACE SEMANTIC VIEW SUPPLIER_QUALITY_SV
  TABLES (
    qi        AS QUALITY_INSPECTIONS PRIMARY KEY (inspection_id)
              COMMENT = 'One row per incoming inspection of a supplier lot.',
    suppliers AS SUPPLIERS PRIMARY KEY (supplier_id)
              COMMENT = 'Approved suppliers and their certifications.',
    parts     AS PARTS PRIMARY KEY (part_id)
              COMMENT = 'Part master.',
    plants    AS PLANTS PRIMARY KEY (plant)
              COMMENT = 'Plant where the inspection took place.'
  )
  RELATIONSHIPS (
    qi_supplier AS qi (supplier_id) REFERENCES suppliers,
    qi_part     AS qi (part_id)     REFERENCES parts,
    qi_plant    AS qi (plant)       REFERENCES plants
  )
  FACTS (
    qi.qty_inspected AS qty_inspected COMMENT = 'Units inspected in the lot.',
    qi.qty_defective AS qty_defective COMMENT = 'Units found defective in the lot.',
    qi.ncr_raised    AS ncr_raised    COMMENT = '1 if a non-conformance report was raised for the lot, else 0.'
  )
  DIMENSIONS (
    qi.inspection_date AS inspection_date WITH SYNONYMS = ('inspection date', 'receipt date')
                       COMMENT = 'Date the lot was inspected.',
    qi.defect_category AS defect_category WITH SYNONYMS = ('defect type', 'failure mode')
                       COMMENT = 'Main defect category: Dimensional, Cosmetic, Plating or Electrical.',
    suppliers.supplier_id    AS supplier_id WITH SYNONYMS = ('supplier', 'vendor')
                       COMMENT = 'Supplier identifier, formatted SUP-###.',
    suppliers.supplier_name  AS supplier_name COMMENT = 'Supplier display name.',
    suppliers.supplier_tier  AS supplier_tier WITH SYNONYMS = ('tier') COMMENT = 'Supplier tier.',
    suppliers.certification  AS certification WITH SYNONYMS = ('quality certification', 'IATF', 'ISO')
                       COMMENT = 'Highest quality certification the supplier holds.',
    parts.part_id      AS part_id WITH SYNONYMS = ('part', 'part number', 'PN')
                       COMMENT = 'Part number, formatted PN-####.',
    parts.product_line AS product_line COMMENT = 'Product line of the inspected part.',
    parts.criticality  AS criticality WITH SYNONYMS = ('critical parts', 'ABC class')
                       COMMENT = 'Supply criticality: A is most critical.',
    plants.plant       AS plant WITH SYNONYMS = ('site', 'factory')
                       COMMENT = 'Plant where the lot was inspected.'
  )
  METRICS (
    qi.units_inspected AS SUM(qi.qty_inspected) COMMENT = 'Total units inspected.',
    qi.units_defective AS SUM(qi.qty_defective) COMMENT = 'Total defective units.',
    qi.defect_ppm AS SUM(qi.qty_defective) * 1000000 / NULLIF(SUM(qi.qty_inspected), 0)
                  WITH SYNONYMS = ('defect rate', 'PPM', 'quality rate')
                  COMMENT = 'Defects per million units inspected (PPM). The standard measure for defect rate.',
    qi.ncr_count  AS SUM(qi.ncr_raised) WITH SYNONYMS = ('NCRs', 'non-conformances')
                  COMMENT = 'Number of non-conformance reports raised.'
  )
  COMMENT = 'Supplier quality: incoming inspection results, defect rate (PPM) and NCRs.'
  AI_SQL_GENERATION 'Defect rate always means defect_ppm (parts per million), never a percentage. Worst quality means the highest defect_ppm. When the user names specific supplier IDs, filter on supplier_id IN (...).'
  AI_VERIFIED_QUERIES (
    worst_suppliers_by_ppm AS (
      QUESTION 'Which 5 suppliers have the worst defect rate in PPM?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT supplier_id, SUM(qty_defective) * 1000000 / NULLIF(SUM(qty_inspected), 0) AS defect_ppm FROM __qi GROUP BY supplier_id ORDER BY defect_ppm DESC LIMIT 5'
    )
  );

-- --------------------------------------------------------------------------------------- Inventory

CREATE OR REPLACE SEMANTIC VIEW INVENTORY_SV
  TABLES (
    inv    AS INVENTORY_POSITIONS PRIMARY KEY (part_id, plant)
           COMMENT = 'Current stock position: one row per part per plant.',
    parts  AS PARTS PRIMARY KEY (part_id) COMMENT = 'Part master, including standard cost.',
    plants AS PLANTS PRIMARY KEY (plant)  COMMENT = 'Plant holding the stock.'
  )
  RELATIONSHIPS (
    inv_part  AS inv (part_id) REFERENCES parts,
    inv_plant AS inv (plant)   REFERENCES plants
  )
  FACTS (
    inv.on_hand_qty      AS on_hand_qty      COMMENT = 'Units physically on hand.',
    inv.safety_stock_qty AS safety_stock_qty COMMENT = 'Minimum units the planners want on hand.',
    inv.avg_daily_usage  AS avg_daily_usage  COMMENT = 'Average units consumed per day.',
    inv.below_safety_stock AS IFF(on_hand_qty < safety_stock_qty, 1, 0)
                         COMMENT = '1 if on hand is below safety stock, else 0.'
  )
  DIMENSIONS (
    parts.part_id       AS part_id WITH SYNONYMS = ('part', 'part number', 'PN')
                        COMMENT = 'Part number, formatted PN-####.',
    parts.product_line  AS product_line COMMENT = 'Product line of the part.',
    parts.criticality   AS criticality WITH SYNONYMS = ('critical parts', 'ABC class')
                        COMMENT = 'Supply criticality: A is most critical.',
    plants.plant        AS plant WITH SYNONYMS = ('site', 'factory', 'warehouse')
                        COMMENT = 'Plant holding the stock.',
    plants.plant_region AS plant_region WITH SYNONYMS = ('region') COMMENT = 'Region of the plant.'
  )
  METRICS (
    inv.total_on_hand AS SUM(inv.on_hand_qty) WITH SYNONYMS = ('stock', 'inventory', 'on hand')
                      COMMENT = 'Total units on hand.',
    inv.parts_below_safety_stock AS SUM(inv.below_safety_stock)
                      WITH SYNONYMS = ('shortages', 'stock-outs', 'below safety stock')
                      COMMENT = 'Number of part-plant positions with on hand below safety stock.',
    inv.days_of_supply AS SUM(inv.on_hand_qty) / NULLIF(SUM(inv.avg_daily_usage), 0)
                      WITH SYNONYMS = ('coverage', 'DOS')
                      COMMENT = 'Days the current stock lasts at average usage.'
  )
  COMMENT = 'Inventory: stock on hand, safety stock, shortages and days of supply by part and plant.'
  AI_SQL_GENERATION 'Positions are part-plant combinations. "Parts below safety stock" means parts_below_safety_stock. This is a current snapshot with no date column; do not filter by date.'
  AI_VERIFIED_QUERIES (
    shortages_by_plant AS (
      QUESTION 'How many part-plant positions are below safety stock at each plant?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT plant, SUM(IFF(on_hand_qty < safety_stock_qty, 1, 0)) AS parts_below_safety_stock FROM __inv GROUP BY plant ORDER BY parts_below_safety_stock DESC'
    )
  );

-- --------------------------------------------------------------------------------- Customer orders

CREATE OR REPLACE SEMANTIC VIEW ORDERS_SV
  TABLES (
    co     AS CUSTOMER_ORDERS PRIMARY KEY (order_line_id)
           COMMENT = 'One row per customer order line.',
    parts  AS PARTS PRIMARY KEY (part_id) COMMENT = 'Part master.',
    plants AS PLANTS PRIMARY KEY (plant)  COMMENT = 'Plant that ships the order.'
  )
  RELATIONSHIPS (
    co_part  AS co (part_id) REFERENCES parts,
    co_plant AS co (plant)   REFERENCES plants
  )
  FACTS (
    co.order_qty       AS order_qty       COMMENT = 'Units ordered by the customer.',
    co.unit_price_usd  AS unit_price_usd  COMMENT = 'Selling price per unit, in USD.',
    co.shipped_on_time AS shipped_on_time COMMENT = '1 if a shipped line arrived on time, else 0.',
    co.line_value_usd  AS order_qty * unit_price_usd COMMENT = 'Booked value of the line, in USD.',
    co.backlog_value_usd AS IFF(line_status = 'Open', order_qty * unit_price_usd, 0)
                       COMMENT = 'Value of the line if it is still open, else 0.'
  )
  DIMENSIONS (
    co.order_date       AS order_date WITH SYNONYMS = ('booking date')
                        COMMENT = 'Date the customer order was booked.',
    co.customer_id      AS customer_id WITH SYNONYMS = ('customer', 'account')
                        COMMENT = 'Customer identifier, formatted CUST-###.',
    co.customer_segment AS customer_segment WITH SYNONYMS = ('segment', 'industry')
                        COMMENT = 'Customer industry segment.',
    co.line_status      AS line_status WITH SYNONYMS = ('status', 'open', 'shipped')
                        COMMENT = 'Open = not yet shipped (backlog); Shipped = fulfilled.',
    parts.part_id       AS part_id WITH SYNONYMS = ('part', 'part number', 'PN')
                        COMMENT = 'Part number, formatted PN-####.',
    parts.product_line  AS product_line COMMENT = 'Product line of the ordered part.',
    plants.plant        AS plant WITH SYNONYMS = ('site', 'factory', 'shipping plant')
                        COMMENT = 'Plant that ships the order.',
    plants.plant_region AS plant_region WITH SYNONYMS = ('region') COMMENT = 'Region of the shipping plant.'
  )
  METRICS (
    co.bookings_usd     AS SUM(co.line_value_usd) WITH SYNONYMS = ('bookings', 'order value', 'revenue')
                        COMMENT = 'Total booked order value, in USD.',
    co.open_backlog_usd AS SUM(co.backlog_value_usd) WITH SYNONYMS = ('backlog', 'open orders', 'past due')
                        COMMENT = 'Value of orders not yet shipped, in USD.',
    co.on_time_delivery_pct AS AVG(IFF(co.line_status = 'Shipped', co.shipped_on_time, NULL)) * 100
                        WITH SYNONYMS = ('OTD', 'on-time delivery')
                        COMMENT = 'Percent of shipped lines that arrived on time.'
  )
  COMMENT = 'Customer orders: bookings, open backlog and on-time delivery.'
  AI_SQL_GENERATION 'Backlog always means open_backlog_usd. On-time delivery is a percentage of shipped lines only. When the user names a plant, filter on plant.'
  AI_VERIFIED_QUERIES (
    backlog_by_plant AS (
      QUESTION 'What is the open backlog value by plant?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT plant, SUM(IFF(line_status = ''Open'', order_qty * unit_price_usd, 0)) AS open_backlog_usd FROM __co GROUP BY plant ORDER BY open_backlog_usd DESC'
    )
  );
