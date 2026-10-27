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
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
_ORIGINAL_PLAN48 = v48._plan48


def _semantic_plaza_refactor_required(task: str) -> tuple[bool, str]:
    """Return a deterministic architectural-escalation decision.

    This guard intentionally reasons from the USER TASK plus current repository
    facts, not from wording chosen by the local model in its CHANGE line.
    """
    if not v48._task_requires_plaza_as_nonfacility_space(task):
        return False, "task does not require converting plaza to non-facility open space"

    row = v48._plaza_row()
    if not row:
        return False, "current repository has no plaza BaseBuildingData row"

    carries_squad = '"interaction_type": "squad"' in row
    carries_dev = '"secondary_interaction_type": "dev"' in row
    carries_activity_slots = '"activity_slots": [' in row and '"activity_slots": []' not in row
    preserve_interactions = v48._task_requires_plaza_interactions_preserved(task)

    if preserve_interactions and (carries_squad or carries_dev):
        dependencies: list[str] = []
        if carries_squad:
            dependencies.append("squad")
        if carries_dev:
            dependencies.append("DEV/QA")
        if carries_activity_slots:
            dependencies.append("hero plaza stay/destination data")
        return True, (
            "the current plaza BaseBuildingData row couples facility/hotspot behavior with protected "
            + ", ".join(dependencies)
            + "; removing or excluding that row without relocating those responsibilities would violate the USER TASK"
        )

    # Even without explicit squad/DEV preservation, the requested open-space
    # semantics can still require replacing activity/destination data rather
    # than deleting it. Keep the guard conservative when the task explicitly
    # asks to preserve hero traversal/stay behavior.
    folded = " ".join(task.casefold().split())
    preserve_hero_space = any(token in folded for token in (
        "attraversabile", "sosta per gli hero", "sosta per gli eroi", "hero movement",
        "hero stay", "movimento degli hero", "movimento degli eroi",
    ))
    if preserve_hero_space and carries_activity_slots:
        return True, (
            "the current plaza row also carries hero activity/destination data, while USER TASK requires "
            "the plaza to remain traversable/stay space after it stops being a facility; a replacement non-facility "
            "space mechanism is required before deleting the row"
        )

    return False, "no deterministic cross-cutting plaza dependency was detected"


def _facility_audit_lines() -> str:
    inventory = v45._facility_inventory()
    rows = inventory.get("rows") or []
    lines: list[str] = []
    for row in rows:
        facility_id = str(row.get("id") or "")
        policy = v46._policy_for(facility_id)
        if facility_id == "plaza":
            verdict = (
                "CROSS-CUTTING: current row is instantiated/clickable/hero-eligible and also carries central interactions; "
                "must be refactored rather than blindly deleted."
            )
        else:
            verdict = "PRESERVE / OUT OF SCOPE for this targeted plaza task."
        lines.append(
            "- {id}: present=YES | hotspot={hotspot} | hero_destination={hero} | policy={policy} | {verdict}".format(
                id=facility_id,
                hotspot=v45._yes_no(row.get("clickable_hotspot_under_current_logic")),
                hero=v45._yes_no(row.get("hero_destination_under_current_filter")),
                policy=policy["status"],
                verdict=verdict,
            )
        )
    return "\n".join(lines)


def _architectural_escalation_plan(reason: str) -> str:
    return (
        "STATUS: ESCALATE\n"
        "FACILITY_AUDIT:\n" + _facility_audit_lines() + "\n"
        "FILES: NONE\n"
        "CHANGE: NONE\n"
        "PRESERVE: Open plaza visual/physical presence, hero traversal/stay semantics, Squad access, DEV/QA access, "
        "hero_agent.gd unless genuinely required, and all other Level 1 facilities named by USER TASK.\n"
        "VERIFY: No mutation should occur in Agent A. Codex should first separate plaza-space responsibilities from "
        "facility/hotspot responsibilities, then run git diff --check, targeted behavioral verification and Godot headless.\n"
        "LIMITATION: Agent A's bounded compact-edit path is appropriate for isolated edits, not this coordinated responsibility split.\n"
        "QUESTION: NONE\n"
        "BLOCKER: " + reason + ". This is a coordinated refactor, so escalate to Codex before editing."
    )


def _plan49(session: Any, task: str, model: str) -> tuple[str, int, int]:
    # Let the proven grounded planner inspect the repository first. We keep its
    # token accounting, but a deterministic semantic guard may override its
    # terminal status before any edit-selection stage begins.
    plan, total_p, total_o = _ORIGINAL_PLAN48(session, task, model)
    must_escalate, reason = _semantic_plaza_refactor_required(task)
    if must_escalate:
        return _architectural_escalation_plan(reason), total_p, total_o
    return plan, total_p, total_o


def run_programmer(task: str, model: str) -> dict[str, Any]:
    old_plan48 = v48._plan48
    v48._plan48 = _plan49
    try:
        result = v48.run_programmer(task, model)
    finally:
        v48._plan48 = old_plan48
    result["runtime"] = "programmer-v4.9-semantic-pre-edit-escalation"
    must_escalate, reason = _semantic_plaza_refactor_required(task)
    result["semantic_pre_edit_escalation"] = must_escalate
    result["semantic_pre_edit_reason"] = reason
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_9_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Semantic pre-edit escalation programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.9 / SEMANTIC PRE-EDIT ESCALATION")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Pipeline: complete task -> inventory/policy -> semantic dependency decision -> edit OR architectural escalation.\n")

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

    must_escalate, reason = _semantic_plaza_refactor_required(task)
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
