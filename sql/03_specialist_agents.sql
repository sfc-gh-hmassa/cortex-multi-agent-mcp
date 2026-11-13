-- =====================================================================================================
-- Step 3 of 7: Specialist agents
--
-- One Cortex Agent per domain. Each has two tools:
--   * an Analyst tool over its own semantic view, which writes and runs the SQL
--   * data_to_chart, which turns the result into a Vega-Lite chart
--
-- These agents are the same in the "before" and "after" patterns. What changes is how the orchestrator
-- calls them and what comes back.
--
-- Before running: replace COMPUTE_WH with your warehouse (deploy.sh does this for you).
-- =====================================================================================================

USE SCHEMA MULTIAGENT_DEMO.DEMO;

CREATE OR REPLACE AGENT PROCUREMENT_AGENT
  COMMENT = 'Procurement specialist: spend, suppliers and prices.'
  FROM SPECIFICATION $$
models:
  orchestration: claude-sonnet-4-6
instructions:
  response: "Be concise. Return the result table, and a chart when the answer has more than one row. Report exact values."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: query_procurement
      description: "Purchase orders, spend, units and prices by supplier, part, commodity, plant and date."
  - tool_spec:
      type: data_to_chart
      name: data_to_chart
      description: "Create a chart from query results."
tool_resources:
  query_procurement:
    semantic_view: MULTIAGENT_DEMO.DEMO.PROCUREMENT_SV
    execution_environment: {type: warehouse, warehouse: COMPUTE_WH}
$$;

CREATE OR REPLACE AGENT SUPPLIER_QUALITY_AGENT
  COMMENT = 'Supplier quality specialist: inspections, defect rate (PPM) and NCRs.'
  FROM SPECIFICATION $$
models:
  orchestration: claude-sonnet-4-6
instructions:
  response: "Be concise. Return the result table, and a chart when the answer has more than one row. Report exact values."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: query_supplier_quality
      description: "Inspections, defects, defect rate (PPM) and NCRs by supplier, part, plant and date."
  - tool_spec:
      type: data_to_chart
      name: data_to_chart
      description: "Create a chart from query results."
tool_resources:
  query_supplier_quality:
    semantic_view: MULTIAGENT_DEMO.DEMO.SUPPLIER_QUALITY_SV
    execution_environment: {type: warehouse, warehouse: COMPUTE_WH}
$$;

CREATE OR REPLACE AGENT INVENTORY_AGENT
  COMMENT = 'Inventory specialist: stock on hand, safety stock and days of supply.'
  FROM SPECIFICATION $$
models:
  orchestration: claude-sonnet-4-6
instructions:
  response: "Be concise. Return the result table, and a chart when the answer has more than one row. Report exact values."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: query_inventory
      description: "Stock on hand, safety stock, parts below safety stock and days of supply by part and plant."
  - tool_spec:
      type: data_to_chart
      name: data_to_chart
      description: "Create a chart from query results."
tool_resources:
  query_inventory:
    semantic_view: MULTIAGENT_DEMO.DEMO.INVENTORY_SV
    execution_environment: {type: warehouse, warehouse: COMPUTE_WH}
$$;

CREATE OR REPLACE AGENT ORDERS_AGENT
  COMMENT = 'Customer orders specialist: bookings, backlog and on-time delivery.'
  FROM SPECIFICATION $$
models:
  orchestration: claude-sonnet-4-6
instructions:
  response: "Be concise. Return the result table, and a chart when the answer has more than one row. Report exact values."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: query_orders
      description: "Customer bookings, open backlog value and on-time delivery by customer, part, plant and date."
  - tool_spec:
      type: data_to_chart
      name: data_to_chart
      description: "Create a chart from query results."
tool_resources:
  query_orders:
    semantic_view: MULTIAGENT_DEMO.DEMO.ORDERS_SV
    execution_environment: {type: warehouse, warehouse: COMPUTE_WH}
$$;
