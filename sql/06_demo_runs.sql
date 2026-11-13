-- =====================================================================================================
-- Step 6 of 7: Run log for the demo app
--
-- Every question asked in the app is logged here, once for "before" and once for "after". The app's
-- scoreboard and metrics.sql both read from this table.
--
-- est_credits uses the billed per-token rates for the model (cached input is much cheaper than uncached
-- input or output). metrics.sql query 3 checks it against the billed credits in ACCOUNT_USAGE, matched on
-- specialist_thread_ids.
-- =====================================================================================================

USE SCHEMA MULTIAGENT_DEMO.DEMO;

CREATE TABLE IF NOT EXISTS DEMO_RUNS (
    run_at                TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    mode                  STRING,   -- 'before' or 'after'
    question              STRING,
    specialists           STRING,   -- which specialists the orchestrator called, comma-separated
    orchestrator_tokens   NUMBER,   -- the orchestrator's own LLM tokens
    specialist_tokens     NUMBER,   -- tokens used by the specialist agent runs
    total_tokens          NUMBER,
    full_price_tokens     NUMBER,   -- tokens billed at the full (uncached) rate
    est_credits           FLOAT,
    kb_to_orchestrator    FLOAT,    -- size of what the specialists sent back to the orchestrator
    seconds               FLOAT,
    charts                NUMBER,   -- charts delivered to the app
    specialist_thread_ids STRING    -- for matching to ACCOUNT_USAGE billing
);
