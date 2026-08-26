from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path
from typing import Any

import programmer_agent_v2 as p2
import programmer_agent_v4_2 as transport
import programmer_agent_v4_4 as v44
import programmer_agent_v4_5 as v45
import programmer_agent_v4_6 as v46
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL

SCOPE_SYSTEM_SUFFIX = """

TASK-SCOPE PRECEDENCE:
- The newest USER TASK is authoritative for the current operation and may resolve behavior that older docs left UNRESOLVED.
- Do not ask the user to re-confirm an instruction already stated in USER TASK.
- If USER TASK explicitly says to preserve a facility/system, keep it out of scope even when its global Level 1 policy is UNRESOLVED.
- Do not let unrelated UNRESOLVED facilities block a targeted task.
- For the plaza, if USER TASK explicitly says it must remain visually/physically as open space while no longer behaving as a facility/hotspot, that behavior is decided for this task. Do not ask whether to remove the hotspot again.
- If the requested behavior is clear but implementing it safely would require coordinated architectural changes beyond the bounded edit capability, use STATUS: ESCALATE rather than NEED_USER_DECISION.
""".strip()


def _task_fold(task: str) -> str:
    return " ".join(task.casefold().split())


def _question_fold(plan: str) -> str:
    for line in plan.splitlines():
        if line.strip().upper().startswith("QUESTION:"):
            return line.split(":", 1)[1].strip().casefold()
    return ""


def _explicitly_preserved(task: str, facility_id: str) -> bool:
    folded = _task_fold(task)
    if facility_id.casefold() not in folded:
        return False
    preserve_markers = (
        "mantieni intatt", "mantieni invariat", "preserva", "preserve", "leave intact",
        "non modificare", "non toccare", "keep intact",
    )
    return any(marker in folded for marker in preserve_markers)


def _plaza_behavior_explicit(task: str) -> bool:
    folded = _task_fold(task)
    if not ("plaza" in folded or "piazza" in folded):
        return False
    open_space = any(token in folded for token in ("spazio aperto", "open space", "piazza centrale"))
    hotspot_change = "hotspot" in folded and any(token in folded for token in ("eliminar", "rimuov", "non deve", "senza"))
    facility_change = "facility" in folded and any(token in folded for token in ("eliminar", "rimuov", "non deve", "non tratt", "senza"))
    return open_space and (hotspot_change or facility_change)


def _decision_is_redundant(task: str, plan: str) -> list[str]:
    question = _question_fold(plan)
    if not question:
        return []
    reasons: list[str] = []
    if ("plaza" in question or "piazza" in question) and _plaza_behavior_explicit(task):
        reasons.append("plaza behavior was explicitly decided by USER TASK")
    for facility_id in ("warehouse", "summoning"):
        if facility_id in question and _explicitly_preserved(task, facility_id):
            reasons.append(f"{facility_id} was explicitly preserved by USER TASK")
    return reasons


def _plan47(session: Any, task: str, model: str) -> tuple[str, int, int]:
    # First use the v4.6 grounded policy planner.
    plan, total_p, total_o = v46._plan46(session, task, model)
    first = next((line.strip().upper() for line in plan.splitlines() if line.strip()), "")
    reasons = _decision_is_redundant(task, plan) if first.startswith("STATUS: NEED_USER_DECISION") else []
    if not reasons:
        return plan, total_p, total_o

    inventory = v45._facility_inventory()
    prompt = (
        "USER TASK:\n" + task
        + "\n\nREPOSITORY EVIDENCE:\n" + p2._evidence(task, session)
        + "\n\n" + v45._inventory_packet(inventory)
        + "\n\n" + v46._policy_packet(inventory)
        + "\n\nPREVIOUS PLAN:\n" + plan
        + "\n\nDETERMINISTIC SCOPE VALIDATION REJECTED THAT USER QUESTION BECAUSE:\n- "
        + "\n- ".join(reasons)
        + "\nThe user already resolved those points. Rewrite once. Keep explicitly preserved systems out of scope. "
          "Choose IMPLEMENT if a safe bounded change is clear, otherwise ESCALATE. Do not ask the same decision again."
    )
    response = p2._chat(
        model,
        [
            {"role": "system", "content": v46.PLAN_SYSTEM + "\n\n" + SCOPE_SYSTEM_SUFFIX},
            {"role": "user", "content": prompt},
        ],
        None,
        1050,
    )
    total_p += int(response.get("prompt_eval_count") or 0)
    total_o += int(response.get("eval_count") or 0)
    retry = p2._assistant_text(response)
    retry_first = next((line.strip().upper() for line in retry.splitlines() if line.strip()), "")
    retry_reasons = _decision_is_redundant(task, retry) if retry_first.startswith("STATUS: NEED_USER_DECISION") else []
    if retry_reasons:
        retry = (
            "STATUS: ESCALATE\n"
            "FACILITY_AUDIT: The requested plaza behavior is explicit, and unrelated preserved facilities remain out of scope.\n"
            "FILES: NONE\nCHANGE: NONE\n"
            "PRESERVE: Explicitly preserved facilities and working hero/base behavior.\n"
            "VERIFY: No mutation was made.\n"
            "LIMITATION: The local planner repeated a decision already resolved by USER TASK.\n"
            "QUESTION: NONE\n"
            "BLOCKER: Safe implementation requires a stronger programmer because the bounded local planner could not proceed without re-asking an already answered question."
        )
    return retry, total_p, total_o


def run_programmer(task: str, model: str) -> dict[str, Any]:
    old_plan46 = v46._plan46
    v46._plan46 = _plan47
    try:
        result = v46.run_programmer(task, model)
    finally:
        v46._plan46 = old_plan46
    result["runtime"] = "programmer-v4.7-task-scope-precedence"
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_7_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Task-scope-aware programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.7 / TASK SCOPE PRECEDENCE")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Pipeline: explicit user scope -> deterministic inventory/policy -> guarded decision/edit -> Godot -> guarded review.\n")

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

    task = args.task.strip()
    if not task:
        try:
            task = input("Descrivi il lavoro da fare ad Agent A:\n> ").strip()
        except EOFError:
            task = ""
    if not task:
        print("Nessun task inserito. Uscita senza modifiche.")
        return 2

    if v45._facility_scope(task):
        inventory = v45._facility_inventory()
        print("========== FACILITY INVENTORY PRE-RUN ==========")
        print(v45._inventory_packet(inventory))
        print("\n========== LEVEL 1 POLICY PRE-RUN ==========")
        print(v46._policy_packet(inventory))
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
    print(f"Time: {result['elapsed_seconds']} seconds")
    print(f"Base branch: {result['base_branch']}")
    print(f"Task branch: {result['task_branch']}")
    print(f"Bootstrap reads: {result['bootstrap_reads']}")
    print("Target paths: " + (", ".join(result["target_paths"]) or "NONE"))
    print(f"Deletion candidates: {result['candidate_count']}")
    print("Changed files: " + (", ".join(result["changed_files"]) or "NONE"))
    print(f"Mutations: {result['mutations']}")
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
