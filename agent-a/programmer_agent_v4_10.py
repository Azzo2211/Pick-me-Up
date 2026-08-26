from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path
from typing import Any

import programmer_agent_v4_2 as transport
import programmer_agent_v4_5 as v45
import programmer_agent_v4_6 as v46
import programmer_agent_v4_8 as v48
import programmer_agent_v4_9 as v49
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
_ORIGINAL_PLAN49 = v49._plan49


def _first_status(plan: str) -> str:
    line = next((line.strip().upper() for line in plan.splitlines() if line.strip()), "")
    if not line.startswith("STATUS:"):
        return ""
    return line.split(":", 1)[1].strip()


def _field(plan: str, name: str) -> str:
    prefix = name.strip().upper() + ":"
    for line in plan.splitlines():
        if line.strip().upper().startswith(prefix):
            return line.split(":", 1)[1].strip()
    return ""


def _plan410(session: Any, task: str, model: str) -> tuple[str, int, int]:
    # Deterministic architectural guards run before spending a planning turn.
    must_escalate, reason = v49._semantic_plaza_refactor_required(task)
    if must_escalate:
        return v49._architectural_escalation_plan(reason), 0, 0
    return _ORIGINAL_PLAN49(session, task, model)


def _terminal_status(result: dict[str, Any]) -> str:
    status = _first_status(str(result.get("plan") or ""))
    if result.get("needs_user_decision") or status == "NEED_USER_DECISION":
        return "NEED_USER_DECISION"
    if result.get("escalate_to_codex") or status == "ESCALATE":
        return "ESCALATE_TO_CODEX"
    if status == "NO_CHANGE":
        return "NO_CHANGE"
    if result.get("changed_files") and not result.get("escalate_to_codex"):
        return "COMPLETED"
    return status or "UNKNOWN"


def _normalize_terminal_result(result: dict[str, Any]) -> dict[str, Any]:
    plan = str(result.get("plan") or "")
    status = _first_status(plan)

    if status == "ESCALATE" and not result.get("changed_files") and int(result.get("mutations") or 0) == 0:
        blocker = _field(plan, "BLOCKER") or _field(plan, "LIMITATION") or "Agent A determined that the task requires Codex."
        result["escalate_to_codex"] = True
        result["needs_user_decision"] = False
        result["final"] = "ESCALATE_TO_CODEX: " + blocker

    elif status == "NEED_USER_DECISION" and not result.get("changed_files") and int(result.get("mutations") or 0) == 0:
        question = _field(plan, "QUESTION") or "A genuine product decision is required before editing."
        result["needs_user_decision"] = True
        result["escalate_to_codex"] = False
        result["final"] = "NEED_USER_DECISION: " + question

    result["terminal_status"] = _terminal_status(result)
    return result


def run_programmer(task: str, model: str) -> dict[str, Any]:
    old_plan49 = v49._plan49
    v49._plan49 = _plan410
    try:
        result = v49.run_programmer(task, model)
    finally:
        v49._plan49 = old_plan49

    result["runtime"] = "programmer-v4.10-terminal-status-normalized"
    return _normalize_terminal_result(result)


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_10_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Terminal-status-normalized programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.10 / TERMINAL STATUS NORMALIZED")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Pipeline: full task -> deterministic guards -> local programmer -> normalized terminal result.\n")

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

    must_escalate, reason = v49._semantic_plaza_refactor_required(task)
    print("========== SEMANTIC PRE-EDIT GUARD ==========")
    print("TRIGGERED=" + ("YES" if must_escalate else "NO"))
    print("REASON=" + reason)
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
    print(f"Terminal status: {result.get('terminal_status', 'UNKNOWN')}")
    print(f"Time: {result['elapsed_seconds']} seconds")
    print(f"Base branch: {result['base_branch']}")
    print(f"Task branch: {result['task_branch']}")
    print(f"Bootstrap reads: {result['bootstrap_reads']}")
    print("Target paths: " + (", ".join(result["target_paths"]) or "NONE"))
    print(f"Deletion candidates: {result['candidate_count']}")
    print("Changed files: " + (", ".join(result["changed_files"]) or "NONE"))
    print(f"Mutations: {result['mutations']}")
    print(f"Semantic pre-edit escalation: {result.get('semantic_pre_edit_escalation', False)}")
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
