from __future__ import annotations

import argparse
import json
import re
import tempfile
import time
from pathlib import Path
from typing import Any

import programmer_agent_v1 as p1
import programmer_agent_v2 as p2
import programmer_agent_v4_2 as transport
import programmer_agent_v4_4 as v44
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
BASE_HUB = "godot/scripts/base/base_hub.gd"
BUILDING_DATA = "godot/scripts/base/building_data.gd"
BASE_BUILDING = "godot/scripts/base/base_building.gd"
HERO_AGENT = "godot/scripts/base/hero_agent.gd"

_ORIGINAL_P2_REVIEW = p2._review

FACILITY_PLAN_SYSTEM = """You are Agent A, first-line programmer for Riftward. Produce a concise grounded implementation decision from repository evidence.
The newest USER TASK outranks older docs/code. Do not invent facts or changes.

A DETERMINISTIC FACILITY INVENTORY may be supplied. It was extracted by the runtime directly from the current repository and is authoritative for what facility-like BaseBuildingData entries actually exist in the current hub code.
When the task concerns the base/hub/facilities/Level 1 or hero destinations:
- account for EVERY inventory row; do not silently omit Warehouse, Summoning, Plaza, or any other entry;
- distinguish code presence, physical BaseBuilding instantiation, click/hotspot eligibility, and hero-destination eligibility;
- compare every present entry with the authoritative design evidence;
- do not claim the entire Level 1 is aligned if a present facility has no clear Level 1 decision in the authoritative docs;
- if a complete audit requires a product decision that the docs do not resolve, prefer NEED_USER_DECISION rather than guessing;
- if the central plaza is represented as BaseBuildingData/hotspot while authoritative docs say it is an open plaza rather than a separate building/facility, explicitly discuss that representation instead of ignoring it.

Choose exactly one status:
- STATUS: IMPLEMENT when a concrete repository change is actually required and safe.
- STATUS: NO_CHANGE when the requested behavior is already correctly implemented and every relevant inventory row is accounted for.
- STATUS: NEED_USER_DECISION only for a genuine unresolved product choice.
- STATUS: ESCALATE only when evidence is insufficient or the task is technically unsafe.

For facility/base scoped tasks output:
STATUS: <IMPLEMENT | NO_CHANGE | NEED_USER_DECISION | ESCALATE>
FACILITY_AUDIT: <mention EVERY inventory id and give a brief verdict for each>
FILES: <comma-separated real files that need changing, or NONE>
CHANGE: <smallest complete change, or NONE>
PRESERVE: <working behavior that must remain>
VERIFY: <checks to run>
LIMITATION: <known limitation, or NONE>
QUESTION: <only when NEED_USER_DECISION; otherwise NONE>
BLOCKER: <only when ESCALATE; otherwise NONE>

For non-facility tasks use the same fields but FACILITY_AUDIT may be NONE.
Never invent an edit merely to produce a diff.
""".strip()

FACILITY_NO_CHANGE_REVIEW_SYSTEM = """You are the independent verification pass for a Riftward task where Agent A concluded NO_CHANGE.
The deterministic facility inventory is authoritative for what entries are actually present in the current hub code.
For a base/facility/Level 1 audit, PASS only if the plan and evidence account for EVERY inventory id and no present entry is silently omitted.
Distinguish present BaseBuildingData entries, instantiated BaseBuilding nodes/hotspots, and hero destination candidates.
Do not accept a blanket claim that the Level 1 is aligned when authoritative docs leave the Level 1 status of a present facility unresolved; that requires NEEDS_FIX/ESCALATE rather than guessing.
Also reject a false limitation: if GODOT CHECK shows GODOT_CHECK_EXIT=0, do not claim headless Godot was unavailable.

Output exactly one first line:
REVIEW: PASS
REVIEW: NEEDS_FIX
REVIEW: ESCALATE
Then one short REASON: paragraph grounded in supplied evidence and inventory.
""".strip()

FACILITY_CHANGE_REVIEW_SYSTEM = """You are the independent verification pass for an Agent A code change.
Audit the USER TASK, deterministic facility inventory, evidence, plan, git diff, git diff --check and Godot smoke result.
For base/facility tasks, explicitly account for every current inventory id relevant to the requested behavior and make sure the change does not accidentally alter unrelated facilities.
Distinguish physical/current hub entries, click/hotspot behavior, and hero-destination eligibility.
Reject invented facility facts or a plan that silently omits real inventory entries.

Output exactly one first line:
REVIEW: PASS
REVIEW: NEEDS_FIX
REVIEW: ESCALATE
Then one short REASON: paragraph with concrete evidence.
""".strip()


def _field(line: str, key: str) -> str:
    match = re.search(r'"' + re.escape(key) + r'"\s*:\s*"([^"]*)"', line)
    return match.group(1) if match else ""


def _explicit_bool(line: str, key: str) -> bool | None:
    match = re.search(r'"' + re.escape(key) + r'"\s*:\s*(true|false)', line, flags=re.IGNORECASE)
    if not match:
        return None
    return match.group(1).lower() == "true"


def _activity_slot_count(line: str) -> int:
    match = re.search(r'"activity_slots"\s*:\s*\[(.*?)\]\s*,\s*"navigation_path"', line)
    if not match:
        return 0
    return match.group(1).count("Vector2(")


def _default_unlocked() -> bool | None:
    path = core._safe_path(BUILDING_DATA)
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r'@export\s+var\s+is_unlocked\s*:=\s*(true|false)', text, flags=re.IGNORECASE)
    if match:
        return match.group(1).lower() == "true"
    match = re.search(r'config\.get\("is_unlocked"\s*,\s*(true|false)\)', text, flags=re.IGNORECASE)
    if match:
        return match.group(1).lower() == "true"
    return None


def _facility_scope(task: str) -> bool:
    folded = task.casefold()
    markers = (
        "facility", "facilities", "base", "hub", "level 1", "livello 1",
        "struttura", "strutture", "workshop", "armory", "alchemy", "plaza",
        "magazzino", "warehouse", "summoning", "hero", "eroi",
    )
    return any(marker in folded for marker in markers)


def _facility_inventory() -> dict[str, Any]:
    hub_path = core._safe_path(BASE_HUB)
    hub_text = hub_path.read_text(encoding="utf-8", errors="replace")
    hero_text = core._safe_path(HERO_AGENT).read_text(encoding="utf-8", errors="replace")
    building_text = core._safe_path(BASE_BUILDING).read_text(encoding="utf-8", errors="replace")
    default_unlocked = _default_unlocked()

    instantiates_all = (
        "for data in building_data:" in hub_text
        and "building.setup(data)" in hub_text
        and "world_root.add_child(building)" in hub_text
    )
    hero_filter_known = bool(re.search(
        r'item\.is_unlocked\s+and\s+not\s+item\.activity_slots\.is_empty\(\)',
        hero_text,
    ))
    click_filter_known = (
        "mouse_filter = Control.MOUSE_FILTER_PASS" in building_text
        and "data.is_unlocked" in building_text
        and "building_selected.emit(self)" in building_text
    )

    rows: list[dict[str, Any]] = []
    in_create = False
    for line_no, line in enumerate(hub_text.splitlines(), 1):
        if line.startswith("func _create_building_data()"):
            in_create = True
            continue
        if in_create and line.startswith("func "):
            break
        if not in_create or "BaseBuildingData.create({" not in line:
            continue

        facility_id = _field(line, "id")
        explicit_unlocked = _explicit_bool(line, "is_unlocked")
        effective_unlocked = explicit_unlocked if explicit_unlocked is not None else default_unlocked
        slots = _activity_slot_count(line)
        hero_candidate: bool | None
        if hero_filter_known and effective_unlocked is not None:
            hero_candidate = effective_unlocked and slots > 0
        else:
            hero_candidate = None
        clickable: bool | None
        if instantiates_all and click_filter_known and effective_unlocked is not None:
            clickable = effective_unlocked
        else:
            clickable = None

        rows.append({
            "id": facility_id or "UNKNOWN",
            "building_type": _field(line, "building_type"),
            "state_key": _field(line, "state_key"),
            "display_name": _field(line, "display_name"),
            "interaction_type": _field(line, "interaction_type"),
            "visual_variant": _field(line, "visual_variant"),
            "source_line": line_no,
            "explicit_is_unlocked": explicit_unlocked,
            "effective_is_unlocked": effective_unlocked,
            "activity_slots": slots,
            "instantiated_as_BaseBuilding": instantiates_all,
            "clickable_hotspot_under_current_logic": clickable,
            "hero_destination_under_current_filter": hero_candidate,
        })

    return {
        "source": BASE_HUB,
        "default_is_unlocked": default_unlocked,
        "all_building_data_instantiated": instantiates_all,
        "hero_filter_detected": hero_filter_known,
        "click_filter_detected": click_filter_known,
        "rows": rows,
    }


def _yes_no(value: bool | None) -> str:
    if value is True:
        return "YES"
    if value is False:
        return "NO"
    return "UNKNOWN"


def _inventory_packet(inventory: dict[str, Any]) -> str:
    rows = inventory.get("rows") or []
    lines = [
        "DETERMINISTIC FACILITY INVENTORY FROM CURRENT REPOSITORY",
        f"source={inventory.get('source')}",
        f"default_is_unlocked={_yes_no(inventory.get('default_is_unlocked'))}",
        f"all_building_data_instantiated={_yes_no(inventory.get('all_building_data_instantiated'))}",
        f"hero_filter_detected={_yes_no(inventory.get('hero_filter_detected'))}",
        f"click_filter_detected={_yes_no(inventory.get('click_filter_detected'))}",
        "ROWS:",
    ]
    for row in rows:
        lines.append(
            "- id={id} | type={building_type} | state_key={state_key} | name={display_name} | "
            "interaction={interaction_type} | unlocked={unlocked} | activity_slots={activity_slots} | "
            "instantiated={instantiated} | clickable_hotspot={clickable} | hero_destination={hero} | source_line={source_line}".format(
                id=row.get("id") or "",
                building_type=row.get("building_type") or "",
                state_key=row.get("state_key") or "<empty>",
                display_name=row.get("display_name") or "",
                interaction_type=row.get("interaction_type") or "",
                unlocked=_yes_no(row.get("effective_is_unlocked")),
                activity_slots=row.get("activity_slots", 0),
                instantiated=_yes_no(row.get("instantiated_as_BaseBuilding")),
                clickable=_yes_no(row.get("clickable_hotspot_under_current_logic")),
                hero=_yes_no(row.get("hero_destination_under_current_filter")),
                source_line=row.get("source_line", 0),
            )
        )
    return "\n".join(lines)


def _missing_inventory_ids(plan: str, inventory: dict[str, Any]) -> list[str]:
    folded = plan.casefold()
    missing: list[str] = []
    for row in inventory.get("rows") or []:
        facility_id = str(row.get("id") or "").strip()
        if facility_id and facility_id.casefold() not in folded:
            missing.append(facility_id)
    return missing


def _plan45(session: p1.ProgrammerSession, task: str, model: str) -> tuple[str, int, int]:
    packet = p2._evidence(task, session)
    inventory = _facility_inventory()
    facility_packet = _inventory_packet(inventory) if _facility_scope(task) else "NOT A FACILITY-SCOPED TASK"
    user_prompt = (
        "USER TASK:\n" + task
        + "\n\nREPOSITORY EVIDENCE:\n" + packet
        + "\n\n" + facility_packet
    )
    response = p2._chat(
        model,
        [
            {"role": "system", "content": FACILITY_PLAN_SYSTEM},
            {"role": "user", "content": user_prompt},
        ],
        None,
        900,
    )
    p1c, o1c = int(response.get("prompt_eval_count") or 0), int(response.get("eval_count") or 0)
    plan = p2._assistant_text(response)

    if _facility_scope(task):
        missing = _missing_inventory_ids(plan, inventory)
        if missing:
            retry = p2._chat(
                model,
                [
                    {"role": "system", "content": FACILITY_PLAN_SYSTEM},
                    {
                        "role": "user",
                        "content": (
                            user_prompt
                            + "\n\nYOUR PREVIOUS PLAN WAS INVALID BECAUSE IT OMITTED THESE REAL FACILITY IDS: "
                            + ", ".join(missing)
                            + "\nRewrite the plan once and explicitly include every inventory id in FACILITY_AUDIT."
                            + "\n\nPREVIOUS PLAN:\n" + plan
                        ),
                    },
                ],
                None,
                1000,
            )
            p2c, o2c = int(retry.get("prompt_eval_count") or 0), int(retry.get("eval_count") or 0)
            plan = p2._assistant_text(retry)
            p1c += p2c
            o1c += o2c
            still_missing = _missing_inventory_ids(plan, inventory)
            if still_missing:
                plan = (
                    "STATUS: ESCALATE\n"
                    "FACILITY_AUDIT: INVALID - missing real facility ids: " + ", ".join(still_missing) + "\n"
                    "FILES: NONE\nCHANGE: NONE\nPRESERVE: NONE\nVERIFY: NONE\n"
                    "LIMITATION: Model could not account for complete deterministic facility inventory.\n"
                    "QUESTION: NONE\n"
                    "BLOCKER: Facility audit omitted real current hub entries after retry."
                )
    return plan, p1c, o1c


def _review_no_change45(
    session: p1.ProgrammerSession,
    task: str,
    plan: str,
    model: str,
    diff_check: str,
    godot_check: str,
) -> tuple[str, int, int]:
    packet = p2._evidence(task, session, budget=12500)
    inventory = _facility_inventory()
    response = p2._chat(
        model,
        [
            {"role": "system", "content": FACILITY_NO_CHANGE_REVIEW_SYSTEM},
            {
                "role": "user",
                "content": (
                    "USER TASK:\n" + task
                    + "\n\nNO-CHANGE PLAN:\n" + plan
                    + "\n\nREPOSITORY EVIDENCE:\n" + packet
                    + "\n\n" + _inventory_packet(inventory)
                    + "\n\nCURRENT GIT DIFF:\n" + session.git_diff()
                    + "\n\nGIT DIFF CHECK:\n" + diff_check
                    + "\n\nGODOT CHECK:\n" + godot_check
                ),
            },
        ],
        None,
        750,
    )
    return p2._assistant_text(response), int(response.get("prompt_eval_count") or 0), int(response.get("eval_count") or 0)


def _review_change45(
    session: p1.ProgrammerSession,
    task: str,
    plan: str,
    model: str,
    diff_check: str,
    godot_check: str,
) -> tuple[str, int, int]:
    packet = p2._evidence(task, session, budget=10500)
    inventory = _facility_inventory()
    response = p2._chat(
        model,
        [
            {"role": "system", "content": FACILITY_CHANGE_REVIEW_SYSTEM},
            {
                "role": "user",
                "content": (
                    "USER TASK:\n" + task
                    + "\n\nPLAN:\n" + plan
                    + "\n\nEVIDENCE:\n" + packet
                    + "\n\n" + (_inventory_packet(inventory) if _facility_scope(task) else "FACILITY INVENTORY NOT REQUIRED")
                    + "\n\nGIT DIFF:\n" + p1._cap(session.git_diff(), 13000)
                    + "\n\nGIT DIFF CHECK:\n" + diff_check
                    + "\n\nGODOT CHECK:\n" + godot_check
                ),
            },
        ],
        None,
        700,
    )
    return p2._assistant_text(response), int(response.get("prompt_eval_count") or 0), int(response.get("eval_count") or 0)


def run_programmer(task: str, model: str) -> dict[str, Any]:
    # Reuse the proven v4.4 execution/write safety path while replacing only
    # planning and review with inventory-aware versions.
    old_plan = v44._plan44
    old_no_change_review = v44._review_no_change
    old_change_review = p2._review
    v44._plan44 = _plan45
    v44._review_no_change = _review_no_change45
    p2._review = _review_change45
    try:
        result = v44.run_programmer(task, model)
    finally:
        v44._plan44 = old_plan
        v44._review_no_change = old_no_change_review
        p2._review = old_change_review

    result["runtime"] = "programmer-v4.5-deterministic-facility-inventory"
    result["facility_inventory"] = _facility_inventory() if _facility_scope(task) else {}
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_5_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Facility-inventory-aware programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.5 / DETERMINISTIC FACILITY INVENTORY")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Pipeline: preflight -> deterministic repository/facility inventory -> decision -> verify -> inventory-aware review.\n")

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

    if _facility_scope(task):
        print("========== FACILITY INVENTORY PRE-RUN ==========")
        print(_inventory_packet(_facility_inventory()))
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
        print(_inventory_packet(result["facility_inventory"]))
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
