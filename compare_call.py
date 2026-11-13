"""Compare one specialist call through the MCP server: the old response (full) vs the new one (filtered).

This is the smallest possible version of the before/after. It makes the same MCP call twice and prints what
came back each time, and where each number comes from:

  context sent back    len() of the tool result text           what lands in your orchestrator's context
  tokens               result -> metadata.usage.tokens_consumed  the specialist agent's own run
  credits              those tokens x the billed per-token rates  (cached input is ~12x cheaper)
  latency              wall-clock time of the MCP call
  chart for the app    result -> structuredContent._mcp_app       MCP Apps; never enters the context

Usage:
  export SNOWFLAKE_ACCOUNT=<org>-<account> SNOWFLAKE_PAT=<token>
  python3 compare_call.py                                  # default specialist and question
  python3 compare_call.py procurement_agent "Which 5 suppliers have the highest total purchase spend?"
"""
import json
import os
import sys
import time

import requests

ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"]
HOST = f"https://{ACCOUNT.lower().replace('_', '-')}.snowflakecomputing.com"
MCP_URL = f"{HOST}/api/v2/databases/MULTIAGENT_DEMO/schemas/DEMO/mcp-servers/SPECIALIST_AGENTS_MCP"
HEADERS = {
    "Authorization": f"Bearer {os.environ['SNOWFLAKE_PAT']}",
    "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
    "Content-Type": "application/json",
}
# Credits per token for claude-sonnet-4-6, as billed in SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY.
RATES = {"cache_read": 0.0000002, "input": 0.00000244, "output": 0.00000976}

# The only thing that changes between before and after:
FILTERS = {
    "before (full)": "full",
    "after (tables + text)": "content.filter(c, c.type == 'table' || c.type == 'text')",
}


def call_specialist(agent, question, content_filter):
    """One JSON-RPC tools/call to the managed MCP server."""
    body = {
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": agent, "arguments": {"text": question, "content_cel_filter": content_filter}},
    }
    start = time.time()
    response = requests.post(MCP_URL, headers=HEADERS, json=body, timeout=600)
    response.raise_for_status()
    return response.json()["result"], time.time() - start


def measure(result, seconds):
    text = result["content"][0]["text"]               # what the orchestrator reads
    usage = json.loads(text).get("metadata", {}).get("usage", {})
    tokens = credits = 0
    for u in usage.get("tokens_consumed", []):
        inp, out = u["input_tokens"], u["output_tokens"]["total"]
        cached = inp.get("cache_read", 0)
        tokens += inp["total"] + out
        credits += cached * RATES["cache_read"] + (inp["total"] - cached) * RATES["input"] + out * RATES["output"]
    app_blocks = (result.get("structuredContent") or {}).get("_mcp_app", {}).get("blocks", [])
    return {
        "context sent back": f"{len(text) / 1024:.1f} KB",
        "~orchestrator tokens": f"{len(text) // 4:,}",   # rough rule: ~4 characters per token
        "specialist tokens": f"{tokens:,}",
        "specialist credits": f"{credits:.4f}",
        "latency": f"{seconds:.1f} s",
        "chart for the app": "yes" if any(b.get("type") == "chart" for b in app_blocks) else "no",
    }


def main():
    agent = sys.argv[1] if len(sys.argv) > 1 else "supplier_quality_agent"
    question = sys.argv[2] if len(sys.argv) > 2 else "Which 5 suppliers have the worst defect rate in PPM?"
    print(f"{agent}: {question}\n")
    rows = {label: measure(*call_specialist(agent, question, f)) for label, f in FILTERS.items()}

    labels = list(rows)
    print(f"{'':20}" + "".join(f"{label:>24}" for label in labels))
    for metric in rows[labels[0]]:
        print(f"{metric:20}" + "".join(f"{rows[label][metric]:>24}" for label in labels))
    print("\nThe specialist does the same work either way (its credits vary a little run to run with caching).\n"
          "What changes is how much comes back for the orchestrator to read, on every call and every later turn.\n"
          "'chart for the app' needs MCP Apps enabled on the account.")


if __name__ == "__main__":
    main()
