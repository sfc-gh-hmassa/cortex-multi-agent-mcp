-- =====================================================================================================
-- Step 4 of 7: The "before" pattern, stored-procedure wrappers
--
-- A common first build: the orchestrator agent gets one custom tool per specialist. Each tool is a
-- stored procedure that calls the specialist with DATA_AGENT_RUN and returns its written answer.
--
-- Why this falls short: DATA_AGENT_RUN returns the specialist's full response (text, table, chart), but
-- a custom tool can only hand text back to the orchestrator. The table and chart are lost, so the
-- orchestrator often asks the specialist again for "the exact numbers", which is a second full agent run.
-- =====================================================================================================

USE SCHEMA MULTIAGENT_DEMO.DEMO;

-- Specialist token usage is logged here, so measure.py can count what the specialists cost.
CREATE TABLE IF NOT EXISTS SPECIALIST_USAGE_LOG (
    logged_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    agent     STRING,
    usage     VARIANT
);

-- One procedure does the work for every specialist.
CREATE OR REPLACE PROCEDURE ASK_SPECIALIST(AGENT_NAME STRING, QUESTION STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    request  STRING;
    response STRING;
    answer   STRING;
BEGIN
    request := OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
                   'role', 'user',
                   'content', ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type', 'text', 'text', :question)))))::STRING;

    response := SNOWFLAKE.CORTEX.DATA_AGENT_RUN('MULTIAGENT_DEMO.DEMO.' || :agent_name, :request);

    INSERT INTO MULTIAGENT_DEMO.DEMO.SPECIALIST_USAGE_LOG (agent, usage)
        SELECT :agent_name, PARSE_JSON(:response):metadata:usage;

    -- Keep only the text blocks. This is the step that throws away the table and the chart.
    SELECT LISTAGG(value:text::STRING, '') WITHIN GROUP (ORDER BY index) INTO :answer
      FROM TABLE(FLATTEN(INPUT => PARSE_JSON(:response):content))
     WHERE value:type = 'text';

    RETURN COALESCE(NULLIF(:answer, ''), :response);
END;
$$;

-- Thin wrappers: an agent custom tool binds its inputs to procedure parameters, so each specialist gets
-- its own one-argument procedure. Names are fully qualified because a procedure called by an agent has
-- no current schema.
CREATE OR REPLACE PROCEDURE ASK_PROCUREMENT_AGENT(QUESTION STRING)
RETURNS STRING LANGUAGE SQL EXECUTE AS CALLER
AS $$ BEGIN CALL MULTIAGENT_DEMO.DEMO.ASK_SPECIALIST('PROCUREMENT_AGENT', :question); RETURN (SELECT $1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))); END; $$;

CREATE OR REPLACE PROCEDURE ASK_SUPPLIER_QUALITY_AGENT(QUESTION STRING)
RETURNS STRING LANGUAGE SQL EXECUTE AS CALLER
AS $$ BEGIN CALL MULTIAGENT_DEMO.DEMO.ASK_SPECIALIST('SUPPLIER_QUALITY_AGENT', :question); RETURN (SELECT $1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))); END; $$;

CREATE OR REPLACE PROCEDURE ASK_INVENTORY_AGENT(QUESTION STRING)
RETURNS STRING LANGUAGE SQL EXECUTE AS CALLER
AS $$ BEGIN CALL MULTIAGENT_DEMO.DEMO.ASK_SPECIALIST('INVENTORY_AGENT', :question); RETURN (SELECT $1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))); END; $$;

CREATE OR REPLACE PROCEDURE ASK_ORDERS_AGENT(QUESTION STRING)
RETURNS STRING LANGUAGE SQL EXECUTE AS CALLER
AS $$ BEGIN CALL MULTIAGENT_DEMO.DEMO.ASK_SPECIALIST('ORDERS_AGENT', :question); RETURN (SELECT $1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))); END; $$;

-- The "before" orchestrator: one custom tool per specialist, plus data_to_chart for its own charts.
CREATE OR REPLACE AGENT ORCHESTRATOR_SPROC
  COMMENT = 'Before pattern: calls specialists through stored procedures (text only).'
  FROM SPECIFICATION $$
models:
  orchestration: claude-sonnet-4-6
instructions:
  response: "Be concise. Return the result table, and a chart when the answer has more than one row. Report exact values."
  orchestration: "Call only the specialists the question needs. For questions that span domains, use the first specialist's results (for example supplier IDs) in the question to the next."
tools:
  - tool_spec:
      type: generic
      name: ask_procurement_agent
      description: "Procurement specialist: purchase orders, spend, units and prices by supplier, part, plant and date."
      input_schema: {type: object, properties: {question: {type: string, description: "Question for the specialist"}}, required: [question]}
  - tool_spec:
      type: generic
      name: ask_supplier_quality_agent
      description: "Supplier quality specialist: inspections, defect rate (PPM) and NCRs by supplier, part and plant."
      input_schema: {type: object, properties: {question: {type: string, description: "Question for the specialist"}}, required: [question]}
  - tool_spec:
      type: generic
      name: ask_inventory_agent
      description: "Inventory specialist: stock on hand, parts below safety stock and days of supply by part and plant."
      input_schema: {type: object, properties: {question: {type: string, description: "Question for the specialist"}}, required: [question]}
  - tool_spec:
      type: generic
      name: ask_orders_agent
      description: "Customer orders specialist: bookings, open backlog and on-time delivery by customer, part and plant."
      input_schema: {type: object, properties: {question: {type: string, description: "Question for the specialist"}}, required: [question]}
  - tool_spec:
      type: data_to_chart
      name: data_to_chart
      description: "Create a chart from data."
tool_resources:
  ask_procurement_agent:
    type: procedure
    identifier: MULTIAGENT_DEMO.DEMO.ASK_PROCUREMENT_AGENT
    execution_environment: {type: warehouse, warehouse: COMPUTE_WH}
  ask_supplier_quality_agent:
    type: procedure
    identifier: MULTIAGENT_DEMO.DEMO.ASK_SUPPLIER_QUALITY_AGENT
    execution_environment: {type: warehouse, warehouse: COMPUTE_WH}
  ask_inventory_agent:
    type: procedure
    identifier: MULTIAGENT_DEMO.DEMO.ASK_INVENTORY_AGENT
    execution_environment: {type: warehouse, warehouse: COMPUTE_WH}
  ask_orders_agent:
    type: procedure
    identifier: MULTIAGENT_DEMO.DEMO.ASK_ORDERS_AGENT
    execution_environment: {type: warehouse, warehouse: COMPUTE_WH}
$$;
