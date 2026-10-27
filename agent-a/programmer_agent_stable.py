from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path
from typing import Any

import programmer_agent_v4_11 as qualified
import programmer_agent_v4_2 as transport
import programmer_agent_v4_5 as v45
import programmer_agent_v4_6 as v46
import programmer_agent_v4_8 as v48
import programmer_agent_v4_9 as v49
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = qualified.MODEL
STABLE_VERSION = "1.0"
QUALIFIED_BASELINE = "v4.11"
RUNTIME_NAME = "programmer-v1-stable-qualified-v4.11"


def run_programmer(task: str, model: str) -> dict[str, Any]:
    """Run the exact qualified v4.11 behavior behind a stable public entrypoint.

    The experimental v4.x modules remain frozen dependencies for traceability.
    New experiments must use a new versioned module and must not silently alter
    this stable entrypoint until they pass qualification and the user approves a
    stable upgrade.
    """
    result = qualified.run_programmer(task, model)
    result["runtime"] = RUNTIME_NAME
    result["stable_version"] = STABLE_VERSION
    result["qualified_baseline"] = QUALIFIED_BASELINE
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_stable_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Stable first-line programmer for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print(f"Riftward Agent A - PROGRAMMER v{STABLE_VERSION} STABLE")
    print(f"Qualified baseline: {QUALIFIED_BASELINE}")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Role: first-line local programmer; user decision for unresolved product choices; Codex/Sol for technical escalation.")
    print("Safety: no automatic commit, push or merge.\n")

    core.OLLAMA_CHAT_URL = transport.CHAT_URL
    v5._request_ollama = transport._direct_request_ollama

    ok, note = transport._full_preflight(args.model)
    if not ok:
        print("OLLAMA MODEL PREFLIGHT FAILED:")
        print(note)
        print("\nNessuna branch del task e stata creata.")
        return 5
    print("OLLAMA MODEL PREFLIGHT OK:")
    print(note + "\n")

    task = args.task.strip() or v48._read_multiline_task()
    if not task:
        print("Nessun task inserito. Uscita senza modifiche.")
        return 2

    print("\n========== USER TASK RECEIVED ==========")
    print(task)
    print("========== END USER TASK ==========\n")

    if v45._facility_scope(task):
        inventory = v45._facility_inventory()
        print("========== FACILITY INVENTORY PRE-RUN ==========")
        print(v45._inventory_packet(inventory))
        print("\n========== LEVEL 1 POLICY PRE-RUN ==========")
        print(v46._policy_packet(inventory))
        print()

    decision_ids, decision_reason = qualified._unresolved_decision_required(task)
    arch_escalate, arch_reason = v49._semantic_plaza_refactor_required(task)
    print("========== DETERMINISTIC ROUTING GUARDS ==========")
    print("PRODUCT_DECISION=" + ("YES" if decision_ids else "NO"))
    print("PRODUCT_DECISION_IDS=" + (", ".join(decision_ids) if decision_ids else "NONE"))
    print("PRODUCT_DECISION_REASON=" + decision_reason)
    print("ARCHITECTURAL_ESCALATION=" + ("YES" if arch_escalate else "NO"))
    print("ARCHITECTURAL_REASON=" + arch_reason)
    print()

    try:
        result = run_programmer(task, args.model)
    except Exception as exc:
        print(f"\nPREFLIGHT/RUNTIME ERROR: {type(exc).__name__}: {exc}")
        print("Nessuna operazione distruttiva, commit, push o merge e stata eseguita.")
        return 1

    output_file = save_result(result)
    print("\n========== AGENT A PROGRAMMER FINAL ==========")
    print(result["final"])
    print("\n========== PLAN ==========")
    print(result["plan"] or "NO PLAN")
    print("\n========== EDIT ACTION ==========")
    print(json.dumps(result["edit"], ensure_ascii=False, indent=2) if result["edit"] else "NO EDIT ACTION")
    print("\n========== VERIFICATION ==========")
    print(result["diff_check"])
    print(result["godot_check"])
    for index, review in enumerate(result["reviews"], 1):
        print(f"\n--- REVIEW {index} ---\n{review}")
    if result.get("facility_inventory"):
        print("\n========== FACILITY INVENTORY FINAL ==========")
        print(v45._inventory_packet(result["facility_inventory"]))
        print("\n========== LEVEL 1 POLICY FINAL ==========")
        print(result.get("facility_policy") or "NONE")

    print("\n========== RUN DATA ==========")
    print(f"Runtime: {result['runtime']}")
    print(f"Stable version: {result['stable_version']}")
    print(f"Qualified baseline: {result['qualified_baseline']}")
    print(f"Terminal status: {result.get('terminal_status', 'UNKNOWN')}")
    print(f"Time: {result['elapsed_seconds']} seconds")
    print(f"Base branch: {result['base_branch']}")
    print(f"Task branch: {result['task_branch']}")
    print(f"Bootstrap reads: {result['bootstrap_reads']}")
    print("Target paths: " + (", ".join(result["target_paths"]) or "NONE"))
    print(f"Deletion candidates: {result['candidate_count']}")
    print("Changed files: " + (", ".join(result["changed_files"]) or "NONE"))
    print(f"Mutations: {result['mutations']}")
    print(f"Product decision guard: {result.get('unresolved_product_decision_guard', False)}")
    print("Product decision ids: " + (", ".join(result.get("unresolved_product_decision_ids") or []) or "NONE"))
    print(f"Escalate to Codex: {result['escalate_to_codex']}")
    print(f"Needs user decision: {result['needs_user_decision']}")
    print(f"Prompt tokens: {result['prompt_tokens_total']}")
    print(f"Output tokens: {result['output_tokens_total']}")
    print(f"Result JSON: {output_file}")
    print("\nNo commit, push or merge was performed.")

    if result["needs_user_decision"]:
        return 3
    if result["escalate_to_codex"]:
        return 4
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
