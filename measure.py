"""Benchmark the multi-agent patterns on the same questions.

Patterns
  before_sproc      ORCHESTRATOR_SPROC agent: its tools are stored procedures that call DATA_AGENT_RUN
                    and return only text (sql/04_before_stored_procedures.sql)
  before_mcp_full   the app's orchestrator in "before" mode: specialists return their full response
  now_mcp_apps      the app's orchestrator in "after" mode: specialists return only the result table,
                    and charts arrive through MCP Apps
  appendix_toolset  ORCHESTRATOR_TOOLSET agent, which borrows the specialists' tools (agent_toolset)

The two MCP patterns run the same orchestrator code as the demo app (app/server.py), so the benchmark
measures exactly what the app shows. Credits use the billed per-token rates defined in app/server.py.

Usage:
  export SNOWFLAKE_ACCOUNT=<org>-<account> SNOWFLAKE_USER=<user> SNOWFLAKE_PAT=<token> DEMO_WAREHOUSE=<warehouse>
  python3 measure.py --pattern all --reps 3          # writes results/results_all.csv
"""
import argparse
import csv
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "app"))
import server  # noqa: E402  the demo app's orchestrator, auth and credit rates

PATTERNS = ["before_sproc", "before_mcp_full", "now_mcp_apps", "appendix_toolset"]
AGENT_PATTERNS = {"before_sproc": "ORCHESTRATOR_SPROC", "appendix_toolset": "ORCHESTRATOR_TOOLSET"}
APP_MODES = {"before_mcp_full": "before", "now_mcp_apps": "after"}


def is_correct(text, q):
    """True if the answer names the expected entity and contains the expected value (within 0.5%).

    Suppliers may be named by ID ("SUP-003") or by display name ("Supplier 003"); both count.
    """
    label = q["gt_label"].lower()
    names = {label, label.replace("sup-", "supplier ")}
    numbers = [float(n.replace(",", "")) for n in re.findall(r"\d[\d,]*\.?\d*", text)]
    tolerance = max(1.0, abs(q["gt_value"]) * 0.005)
    return any(n in text.lower() for n in names) and any(abs(x - q["gt_value"]) <= tolerance for x in numbers)


def run_agent(name, question):
    """Call a Cortex Agent object directly and return its full response."""
    url = f"{server.HOST}/api/v2/databases/{server.DB}/schemas/{server.SC}/agents/{name}:run"
    body = {"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}], "stream": False}
    r = server.http.post(url, headers=server.headers(), json=body, timeout=900)
    r.raise_for_status()
    return r.json()


def logged_specialist_usage(since):
    """Specialist runs logged by the stored procedures since a timestamp (before_sproc only)."""
    rows = server.sql("SELECT usage FROM SPECIALIST_USAGE_LOG WHERE logged_at > ?::TIMESTAMP_LTZ", since)
    return [json.loads(r[0]) for r in rows if r[0]]


def measure_agent_pattern(pattern, q):
    since = server.sql("SELECT CURRENT_TIMESTAMP()::STRING")[0][0]
    start = time.time()
    response = run_agent(AGENT_PATTERNS[pattern], q["question"])
    seconds = time.time() - start

    # The orchestrator agent's own usage, in the same shape the specialists report it.
    orch_tokens, orch_full_price, orch_credits, _ = server.specialist_usage(json.dumps(response))
    spec_tokens = spec_full_price = calls = 0
    spec_credits = 0.0
    if pattern == "before_sproc":
        for usage in logged_specialist_usage(since):
            tok, full, cr, _ = server.specialist_usage(json.dumps({"metadata": {"usage": usage}}))
            spec_tokens, spec_full_price, spec_credits, calls = (spec_tokens + tok, spec_full_price + full,
                                                                 spec_credits + cr, calls + 1)
    blocks = response.get("content", [])
    answer = json.dumps([b for b in blocks if b.get("type") in ("text", "table")])
    return {"orchestrator_tokens": orch_tokens, "specialist_tokens": spec_tokens,
            "total_tokens": orch_tokens + spec_tokens, "full_price_tokens": orch_full_price + spec_full_price,
            "credits": orch_credits + spec_credits, "specialist_calls": calls, "kb_to_orchestrator": 0,
            "seconds": seconds, "chart": any(b.get("type") == "chart" for b in blocks),
            "correct": is_correct(answer, q), "answer": " ".join(b.get("text", "") for b in blocks)[:1000]}


def measure_app_pattern(pattern, q):
    result = server.run(APP_MODES[pattern], q["question"])
    s = result["stats"]
    return {"orchestrator_tokens": s["orchestrator_tokens"], "specialist_tokens": s["specialist_tokens"],
            "total_tokens": s["total_tokens"], "full_price_tokens": s["full_price_tokens"],
            "credits": s["credits"], "specialist_calls": len(result["specialists"]),
            "kb_to_orchestrator": s["kb_to_orchestrator"], "seconds": s["seconds"], "chart": s["charts"] > 0,
            "correct": is_correct(result["answer"], q), "answer": result["answer"][:1000]}


def measure(pattern, q, rep):
    try:
        row = (measure_agent_pattern if pattern in AGENT_PATTERNS else measure_app_pattern)(pattern, q)
        row["error"] = ""
    except Exception as e:  # keep going; failures are recorded in the CSV
        row = {"error": str(e)[:200]}
    row.update(pattern=pattern, question=q["id"], rep=rep)
    print(f"{pattern:17} {q['id']:24} rep {rep}  "
          + (row["error"] or f"{row['credits']:.3f} credits  {row['seconds']:5.1f}s  correct={row['correct']}"),
          flush=True)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pattern", default="all", choices=["all"] + PATTERNS)
    parser.add_argument("--reps", type=int, default=3)
    args = parser.parse_args()

    questions = json.load(open(os.path.join(HERE, "questions.json")))
    patterns = PATTERNS if args.pattern == "all" else [args.pattern]
    rows = []
    for pattern in patterns:
        jobs = [(q, rep) for rep in range(args.reps) for q in questions]
        if pattern == "before_sproc":
            # Sequential, so each run's logged specialist usage can be attributed to it by time.
            rows += [measure(pattern, q, rep) for q, rep in jobs]
        else:
            with ThreadPoolExecutor(4) as pool:
                rows += list(pool.map(lambda job: measure(pattern, *job), jobs))

    os.makedirs(os.path.join(HERE, "results"), exist_ok=True)
    out = os.path.join(HERE, "results", f"results_{args.pattern}.csv")
    columns = ["pattern", "question", "rep", "credits", "seconds", "correct", "chart", "orchestrator_tokens",
               "specialist_tokens", "total_tokens", "full_price_tokens", "specialist_calls",
               "kb_to_orchestrator", "answer", "error"]
    with open(out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print("wrote", out)


if __name__ == "__main__":
    main()
