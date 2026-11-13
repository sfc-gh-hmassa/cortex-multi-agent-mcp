-- =====================================================================================================
-- Step 7 of 7 (optional): Appendix, the agent_toolset pattern
--
-- If Snowflake Intelligence is your front end, an orchestrator can borrow the specialists' tools with
-- agent_toolset instead of calling them as separate agents. It charts natively and works well with a
-- handful of specialists. With many, every borrowed tool is listed on each step and cost grows, so for
-- your own app the MCP approach is the better fit.
-- =====================================================================================================

USE SCHEMA MULTIAGENT_DEMO.DEMO;

CREATE OR REPLACE AGENT ORCHESTRATOR_TOOLSET
  COMMENT = 'Appendix pattern: borrows the specialists'' tools with agent_toolset.'
  FROM SPECIFICATION $$
models:
  orchestration: claude-sonnet-4-6
instructions:
  response: "Be concise. Return the result table, and a chart when the answer has more than one row. Report exact values."
tools:
  - tool_spec: {type: agent_toolset, name: procurement_tools}
  - tool_spec: {type: agent_toolset, name: supplier_quality_tools}
  - tool_spec: {type: agent_toolset, name: inventory_tools}
  - tool_spec: {type: agent_toolset, name: orders_tools}
tool_resources:
  procurement_tools:      {agent_name: MULTIAGENT_DEMO.DEMO.PROCUREMENT_AGENT}
  supplier_quality_tools: {agent_name: MULTIAGENT_DEMO.DEMO.SUPPLIER_QUALITY_AGENT}
  inventory_tools:        {agent_name: MULTIAGENT_DEMO.DEMO.INVENTORY_AGENT}
  orders_tools:           {agent_name: MULTIAGENT_DEMO.DEMO.ORDERS_AGENT}
$$;
