from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path
from typing import Any

import programmer_agent_v2 as p2
import programmer_agent_v4_2 as transport
import programmer_agent_v4_5 as v45
import programmer_agent_v4_6 as v46
import programmer_agent_v4_7 as v47
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
_ORIGINAL_PLAN47 = v47._plan47
BASE_HUB = "godot/scripts/base/base_hub.gd"


def _plaza_row() -> str:
    path = core._safe_path(BASE_HUB)
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if 'BaseBuildingData.create({' in line and '"id": "plaza"' in line:
            return line
    return ""


def _task_requires_plaza_interactions_preserved(task: str) -> bool:
    folded = " ".join(task.casefold().split())
    preserve = any(token in folded for token in (
        "non perdere", "mantieni", "preserva", "preserve", "keep", "non rompere", "intatt",
    ))
    dependency = any(token in folded for token in (
        "dev/qa", "dev", "qa", "squad", "squadra", "nexus",
    ))
    return preserve and dependency


def _task_requires_plaza_as_nonfacility_space(task: str) -> bool:
    folded = " ".join(task.casefold().split())
    plaza = "plaza" in folded or "piazza" in folded
    open_space = any(token in folded for token in ("spazio aperto", "open space", "attraversabile", "sosta"))
    nonfacility = any(token in folded for token in (
        "non deve essere trattata come una facility", "non deve essere trattato come una facility",
        "non facility", "senza hotspot", "non deve essere trattata come", "facility/hotspot",
    ))
    return plaza and (open_space or nonfacility)


def _plan48(session: Any, task: str, model: str) -> tuple[str, int, int]:
    plan, total_p, total_o = _ORIGINAL_PLAN47(session, task, model)
    first = next((line.strip().upper() for line in plan.splitlines() if line.strip()), "")
    if not first.startswith("STATUS: IMPLEMENT"):
        return plan, total_p, total_o

    inventory = v45._facility_inventory()
    removal_ids = v46._planned_removal_ids(plan, inventory)
    if "plaza" not in removal_ids:
        return plan, total_p, total_o

    row = _plaza_row()
    carries_squad = '"interaction_type": "squad"' in row
    carries_dev = '"secondary_interaction_type": "dev"' in row
    preserve_interactions = _task_requires_plaza_interactions_preserved(task)
    preserve_space = _task_requires_plaza_as_nonfacility_space(task)

    if preserve_interactions and (carries_squad or carries_dev):
        return (
            "STATUS: ESCALATE\n"
            "FACILITY_AUDIT:\n"
            "- plaza: current BaseBuildingData is a clickable hero destination and also carries protected squad/DEV interactions. "
            "User requires the plaza to remain as open traversable/stay space while no longer being a facility/hotspot.\n"
            "- training: PRESERVE\n- portal: PRESERVE\n- lodgings: PRESERVE\n"
            "- warehouse: PRESERVE per USER TASK\n- fusion: PRESERVE\n- summoning: PRESERVE per USER TASK\n"
            "FILES: NONE\n"
            "CHANGE: NONE\n"
            "PRESERVE: Squad and DEV/QA access, open plaza space, hero movement/stay behavior, and all explicitly preserved facilities.\n"
            "VERIFY: No mutation should occur before the dependent interactions are safely relocated.\n"
            "LIMITATION: The bounded local edit path cannot safely remove the plaza BaseBuildingData row and simultaneously relocate squad/DEV access plus preserve non-facility plaza movement/stay semantics.\n"
            "QUESTION: NONE\n"
            "BLOCKER: Removing the current plaza row would also remove protected squad/DEV behavior; this requires a coordinated refactor and should escalate to Codex."
        ), total_p, total_o

    if preserve_space:
        return (
            "STATUS: ESCALATE\n"
            "FACILITY_AUDIT:\n"
            "- plaza: current BaseBuildingData couples visual/open-space semantics, hotspot behavior and hero destination behavior.\n"
            "FILES: NONE\nCHANGE: NONE\n"
            "PRESERVE: Open traversable/stay plaza semantics and unrelated facilities.\n"
            "VERIFY: No mutation should occur until the plaza has a non-facility representation.\n"
            "LIMITATION: A one-row removal would eliminate the current destination data rather than replace it with a non-facility plaza-space mechanism.\n"
            "QUESTION: NONE\n"
            "BLOCKER: Safe implementation requires a coordinated plaza representation refactor; escalate to Codex."
        ), total_p, total_o

    return plan, total_p, total_o


def run_programmer(task: str, model: str) -> dict[str, Any]:
    old_plan47 = v47._plan47
    v47._plan47 = _plan48
    try:
        result = v47.run_programmer(task, model)
    finally:
        v47._plan47 = old_plan47
    result["runtime"] = "programmer-v4.8-multiline-dependency-guard"
    return result


def _read_multiline_task() -> str:
    print("Descrivi il lavoro da fare ad Agent A.")
    print("Puoi incollare piu righe. Quando hai finito, scrivi FINE su una riga da sola e premi Invio.")
    print("> ", end="", flush=True)
    lines: list[str] = []
    first = True
    while True:
        try:
            line = input() if first else input("  ")
        except EOFError:
            break
        first = False
        if line.strip().upper() == "FINE":
            break
        lines.append(line)
    return "\n".join(lines).strip()


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_8_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Multiline, dependency-aware programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.8 / MULTILINE + DEPENDENCY GUARD")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Pipeline: complete user task -> deterministic inventory/policy -> dependency guard -> safe edit/escalation -> Godot/review.\n")

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

    task = args.task.strip() or _read_multiline_task()
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
