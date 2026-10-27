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
import programmer_agent_v4_10 as v410
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
_ORIGINAL_PLAN410 = v410._plan410


def _fold(value: str) -> str:
    return " ".join(value.casefold().split())


def _row_aliases(row: dict[str, Any]) -> list[str]:
    raw = [
        str(row.get("id") or ""),
        str(row.get("building_type") or ""),
        str(row.get("state_key") or ""),
        str(row.get("display_name") or ""),
    ]
    aliases: list[str] = []
    for value in raw:
        folded = _fold(value)
        if folded and folded not in aliases:
            aliases.append(folded)
    # Common project/user terminology.
    facility_id = str(row.get("id") or "")
    if facility_id == "summoning":
        aliases.extend(["summoning center", "centro evocativo", "summoning hall"])
    elif facility_id == "warehouse":
        aliases.extend(["magazzino"])
    return list(dict.fromkeys(aliases))


def _targeted_unresolved_ids(task: str) -> list[str]:
    folded = _fold(task)
    inventory = v45._facility_inventory()
    targets: list[str] = []
    for row in inventory.get("rows") or []:
        facility_id = str(row.get("id") or "")
        if not facility_id:
            continue
        if v46._policy_for(facility_id)["status"] != "UNRESOLVED":
            continue
        if any(alias and alias in folded for alias in _row_aliases(row)):
            targets.append(facility_id)
    return targets


def _task_requests_product_decision_guard(task: str) -> bool:
    folded = _fold(task)
    markers = (
        "non decidere tu",
        "non decidere",
        "chiedi a me",
        "chiedimi",
        "manca una decisione",
        "scelta di game design",
        "scelta game design",
        "documentazione non lo stabilisce",
        "documentazione non la stabilisce",
        "se la documentazione non",
        "do not decide",
        "ask me",
        "product decision",
        "game design decision",
        "if the documentation does not",
    )
    return any(marker in folded for marker in markers)


def _unresolved_decision_required(task: str) -> tuple[list[str], str]:
    ids = _targeted_unresolved_ids(task)
    if not ids:
        return [], "task does not target any currently present UNRESOLVED facility"
    if not _task_requests_product_decision_guard(task):
        return [], "task targets UNRESOLVED facilities but does not explicitly require user-owned product decision routing"
    return ids, (
        "USER TASK targets currently present facilities whose authoritative Level 1 policy is UNRESOLVED and explicitly says "
        "not to invent the game-design choice; the decision belongs to the user before repository mutation"
    )


def _audit_line(row: dict[str, Any], targeted: set[str]) -> str:
    facility_id = str(row.get("id") or "")
    policy = v46._policy_for(facility_id)["status"]
    hotspot = v45._yes_no(row.get("clickable_hotspot_under_current_logic"))
    hero = v45._yes_no(row.get("hero_destination_under_current_filter"))
    if facility_id in targeted:
        verdict = "TARGETED_UNRESOLVED: current implementation exists, but Level 1 presence is a product decision not resolved by authoritative policy."
    else:
        verdict = "OUT_OF_SCOPE: do not modify for this targeted decision task."
    return (
        f"- id={facility_id} | current_presence=YES | hotspot={hotspot} | hero_destination={hero} | "
        f"policy={policy} | {verdict}"
    )


def _decision_question(ids: list[str]) -> str:
    friendly = {
        "warehouse": "Warehouse/Magazzino",
        "summoning": "Summoning Center/Centro Evocativo",
    }
    names = [friendly.get(item, item) for item in ids]
    if len(names) == 1:
        subject = names[0]
    elif len(names) == 2:
        subject = names[0] + " e " + names[1]
    else:
        subject = ", ".join(names[:-1]) + " e " + names[-1]
    return (
        f"Per il Level 1, vuoi {subject} presenti fisicamente fin dall'inizio, assenti fino a uno sblocco successivo, "
        "oppure vuoi una scelta diversa per ciascuna struttura?"
    )


def _deterministic_need_user_decision_plan(ids: list[str], reason: str) -> str:
    inventory = v45._facility_inventory()
    targeted = set(ids)
    audit = "\n".join(_audit_line(row, targeted) for row in inventory.get("rows") or [])
    return (
        "STATUS: NEED_USER_DECISION\n"
        "FACILITY_AUDIT:\n" + audit + "\n"
        "FILES: NONE\n"
        "CHANGE: NONE\n"
        "PRESERVE: Current repository state and every facility outside the explicit unresolved product choice.\n"
        "VERIFY: After the user decides, rerun inventory/policy checks before any edit, then git diff --check and Godot headless if a change is made.\n"
        "LIMITATION: " + reason + ".\n"
        "QUESTION: " + _decision_question(ids) + "\n"
        "BLOCKER: NONE"
    )


def _plan411(session: Any, task: str, model: str) -> tuple[str, int, int]:
    ids, reason = _unresolved_decision_required(task)
    if ids:
        return _deterministic_need_user_decision_plan(ids, reason), 0, 0
    return _ORIGINAL_PLAN410(session, task, model)


def run_programmer(task: str, model: str) -> dict[str, Any]:
    old_plan410 = v410._plan410
    v410._plan410 = _plan411
    try:
        result = v410.run_programmer(task, model)
    finally:
        v410._plan410 = old_plan410

    ids, reason = _unresolved_decision_required(task)
    result["runtime"] = "programmer-v4.11-unresolved-product-decision-router"
    result["unresolved_product_decision_guard"] = bool(ids)
    result["unresolved_product_decision_ids"] = ids
    result["unresolved_product_decision_reason"] = reason
    # v4.10 normalizes terminal status after its own call. Re-normalize once
    # here so deterministic v4.11 plans are represented consistently.
    return v410._normalize_terminal_result(result)


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_11_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Unresolved-product-decision-aware programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.11 / PRODUCT DECISION ROUTER")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Pipeline: full task -> deterministic product/architecture guards -> local programmer only when appropriate.\n")

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

    decision_ids, decision_reason = _unresolved_decision_required(task)
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
