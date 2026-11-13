-- =====================================================================================================
-- Step 5 of 7: The managed MCP server (used by both "before" and "after")
--
-- One MCP server exposes the four specialists as CORTEX_AGENT_RUN tools. The server is the same in both
-- patterns; the difference is in what the orchestrator asks for on each call:
--
--   before: "content_cel_filter": "full"
--           The specialist's whole response comes back, including its semantic-view context, chart
--           instructions and SQL. About 100 KB per call lands in the orchestrator's context.
--
--   after:  "content_cel_filter": "content.filter(c, c.type == 'table' || c.type == 'text')"
--           Only the result tables and the specialist's short written answer come back (about 1-2 KB).
--           Keep the text blocks: a single-number answer often has no table, and a table-only filter
--           would return nothing for it. With MCP Apps enabled on the account, the
--           specialist's chart and table are also returned in structuredContent._mcp_app, which the app
--           draws directly. That part never enters the orchestrator's context.
--
-- MCP Apps is an account-level preview setting. Ask your Snowflake account team to enable it.
-- =====================================================================================================

USE SCHEMA MULTIAGENT_DEMO.DEMO;

CREATE OR REPLACE MCP SERVER SPECIALIST_AGENTS_MCP FROM SPECIFICATION $$
tools:
  - name: "procurement_agent"
    type: "CORTEX_AGENT_RUN"
    identifier: "MULTIAGENT_DEMO.DEMO.PROCUREMENT_AGENT"
    title: "Procurement"
    description: "Purchase orders, spend, units and prices by supplier, part, commodity, plant and date."
    annotations: {readOnlyHint: true, destructiveHint: false}
  - name: "supplier_quality_agent"
    type: "CORTEX_AGENT_RUN"
    identifier: "MULTIAGENT_DEMO.DEMO.SUPPLIER_QUALITY_AGENT"
    title: "Supplier Quality"
    description: "Inspections, defects, defect rate (PPM) and NCRs by supplier, part, plant and date."
    annotations: {readOnlyHint: true, destructiveHint: false}
  - name: "inventory_agent"
    type: "CORTEX_AGENT_RUN"
    identifier: "MULTIAGENT_DEMO.DEMO.INVENTORY_AGENT"
    title: "Inventory"
    description: "Stock on hand, safety stock, parts below safety stock and days of supply by part and plant."
    annotations: {readOnlyHint: true, destructiveHint: false}
  - name: "orders_agent"
    type: "CORTEX_AGENT_RUN"
    identifier: "MULTIAGENT_DEMO.DEMO.ORDERS_AGENT"
    title: "Customer Orders"
    description: "Customer bookings, open backlog value and on-time delivery by customer, part, plant and date."
    annotations: {readOnlyHint: true, destructiveHint: false}
$$;
