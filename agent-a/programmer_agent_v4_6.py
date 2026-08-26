from __future__ import annotations

import argparse
import json
import re
import tempfile
from pathlib import Path
from typing import Any

import programmer_agent_v2 as p2
import programmer_agent_v4_2 as transport
import programmer_agent_v4_3 as v43
import programmer_agent_v4_4 as v44
import programmer_agent_v4_5 as v45
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL

# Deterministic projection of the currently authoritative Level 1 decisions in
# GAME_VISION.md + ART_DIRECTION.md. This is deliberately narrower than general
# lore: UNKNOWN means the docs do not currently decide Level 1 presence.
LEVEL1_POLICY: dict[str, dict[str, str]] = {
    "plaza": {
        "status": "OPEN_NOT_FACILITY",
        "evidence": "Central square/plaza is an open public space, not a separate building/facility.",
    },
    "training": {
        "status": "REQUIRED_PRESENT",
        "evidence": "Training Center exists at Level 1 and is slightly elevated.",
    },
    "portal": {
        "status": "REQUIRED_PRESENT",
        "evidence": "Mission Gate exists at Level 1 and is physically connected to base circulation.",
    },
    "lodgings": {
        "status": "REQUIRED_PRESENT",
        "evidence": "Dormitory/Lodging exists at Level 1 and should plausibly host about five heroes.",
    },
    "fusion": {
        "status": "REQUIRED_PRESENT",
        "evidence": "Merging Center exists and is unlocked at Level 1.",
    },
    "alchemy": {
        "status": "REQUIRED_ABSENT",
        "evidence": "Workshop is not physically present at Level 1.",
    },
    "armory": {
        "status": "REQUIRED_ABSENT",
        "evidence": "Armory is not physically present at Level 1.",
    },
    "warehouse": {
        "status": "UNRESOLVED",
        "evidence": "Current authoritative Level 1 notes do not explicitly decide Warehouse presence.",
    },
    "summoning": {
        "status": "UNRESOLVED",
        "evidence": "Current authoritative Level 1 notes do not explicitly decide Summoning Center presence.",
    },
}

PLAN_SYSTEM = """You are Agent A, first-line programmer for Riftward.
You receive two deterministic inputs extracted/provided by the runtime:
1) FACILITY INVENTORY = what the current Godot hub code actually instantiates and exposes.
2) AUTHORITATIVE LEVEL 1 POLICY = what the current project documents explicitly decide.

These inputs are authoritative. Never promote UNRESOLVED into required-present or required-absent. In particular, do NOT claim Warehouse or Summoning are forbidden/required at Level 1 unless the supplied policy says so.

For every inventory id, write one FACILITY_AUDIT line and distinguish:
- actual code presence/instantiation;
- clickable hotspot eligibility;
- hero destination eligibility;
- documented Level 1 policy status.

Policy meanings:
- REQUIRED_PRESENT: presence is explicitly required.
- REQUIRED_ABSENT: physical facility must not be instantiated at Level 1.
- OPEN_NOT_FACILITY: the space may exist visually, but treating it as a separate facility/building/hotspot/hero destination conflicts with the documented mental model and must be discussed.
- UNRESOLVED: docs do not decide presence; do not remove/add it on your own.

If USER TASK is a complete Level 1 facility audit and one or more CURRENTLY PRESENT entries are UNRESOLVED, use STATUS: NEED_USER_DECISION and ask one concise question covering those ids. You may still identify other definite discrepancies in FACILITY_AUDIT, but do not mutate the repository before the unresolved Level 1 composition is decided.

Choose exactly one status:
STATUS: IMPLEMENT
STATUS: NO_CHANGE
STATUS: NEED_USER_DECISION
STATUS: ESCALATE

Output exactly:
STATUS: <status>
FACILITY_AUDIT:
- <one line for EVERY inventory id>
FILES: <real files to change, or NONE>
CHANGE: <smallest change, or NONE>
PRESERVE: <what must remain>
VERIFY: <checks>
LIMITATION: <known limitation or NONE>
QUESTION: <question only for NEED_USER_DECISION; otherwise NONE>
BLOCKER: <blocker only for ESCALATE; otherwise NONE>

Never invent an edit merely to produce a diff.
""".strip()

REVIEW_SYSTEM = """You are the independent verification pass for Riftward.
The deterministic FACILITY INVENTORY and AUTHORITATIVE LEVEL 1 POLICY are authoritative.
Reject any claim that an UNRESOLVED facility is forbidden, unauthorized, required, illegal, or definitely correct at Level 1.
Reject any facility removal/addition that is unsupported by the policy.
For OPEN_NOT_FACILITY plaza policy, do not call a clickable BaseBuildingData facility/hotspot representation fully aligned without addressing that discrepancy.
If Godot check says GODOT_CHECK_EXIT=0, do not claim headless Godot was unavailable.

Output exactly one first line:
REVIEW: PASS
REVIEW: NEEDS_FIX
REVIEW: ESCALATE
Then one short REASON: paragraph grounded in the supplied deterministic inputs and diff.
""".strip()

_ORIGINAL_REQUEST_ACTION = v43._request_action
_ORIGINAL_VALIDATE_ACTION = v43._validate_action
_ALLOWED_FACILITY_CANDIDATE_IDS: set[int] | None = None


def _policy_for(facility_id: str) -> dict[str, str]:
    return LEVEL1_POLICY.get(
        facility_id,
        {"status": "UNRESOLVED", "evidence": "No explicit Level 1 decision is registered for this facility id."},
    )


def _policy_packet(inventory: dict[str, Any]) -> str:
    present = {str(row.get("id") or "") for row in inventory.get("rows") or []}
    ids = list(dict.fromkeys([str(row.get("id") or "") for row in inventory.get("rows") or []] + ["armory"]))
    lines = ["AUTHORITATIVE LEVEL 1 FACILITY POLICY:"]
    for facility_id in ids:
        if not facility_id:
            continue
        policy = _policy_for(facility_id)
        lines.append(
            f"- id={facility_id} | current_presence={'YES' if facility_id in present else 'NO'} | "
            f"policy={policy['status']} | evidence={policy['evidence']}"
        )
    return "\n".join(lines)


def _full_audit(task: str) -> bool:
    folded = task.casefold()
    audit_markers = ("audit", "completo", "completa", "tutte le strutture", "tutte le facility", "all facilities")
    base_markers = ("level 1", "livello 1", "base", "hub", "facility", "strutture")
    return any(marker in folded for marker in audit_markers) and any(marker in folded for marker in base_markers)


def _present_unresolved(inventory: dict[str, Any]) -> list[str]:
    return [
        str(row.get("id") or "")
        for row in inventory.get("rows") or []
        if _policy_for(str(row.get("id") or ""))["status"] == "UNRESOLVED"
    ]


def _audit_line(plan: str, facility_id: str) -> str:
    for line in plan.splitlines():
        if facility_id.casefold() in line.casefold():
            return line
    return ""


def _plan_has_policy_violation(plan: str, inventory: dict[str, Any]) -> list[str]:
    problems: list[str] = []
    for row in inventory.get("rows") or []:
        facility_id = str(row.get("id") or "")
        line = _audit_line(plan, facility_id)
        policy = _policy_for(facility_id)["status"]
        if not line:
            problems.append(f"missing audit row for {facility_id}")
            continue
        folded = line.casefold()
        if policy == "UNRESOLVED":
            uncertainty = ("unresolved", "not specified", "not explicitly", "unclear", "unknown", "decision", "non specific", "non defin")
            if not any(token in folded for token in uncertainty):
                problems.append(f"{facility_id} must remain UNRESOLVED")
        elif policy == "OPEN_NOT_FACILITY":
            mismatch_terms = ("not a facility", "open", "hotspot", "discrep", "mismatch", "non facility", "spazio", "piazza")
            if not any(token in folded for token in mismatch_terms):
                problems.append("plaza OPEN_NOT_FACILITY policy was not addressed")
    return problems


def _deterministic_decision_plan(inventory: dict[str, Any], problems: list[str]) -> str:
    unresolved = _present_unresolved(inventory)
    audit_lines: list[str] = []
    for row in inventory.get("rows") or []:
        facility_id = str(row.get("id") or "")
        policy = _policy_for(facility_id)
        audit_lines.append(
            f"- {facility_id}: present=YES, hotspot={v45._yes_no(row.get('clickable_hotspot_under_current_logic'))}, "
            f"hero_destination={v45._yes_no(row.get('hero_destination_under_current_filter'))}, policy={policy['status']}."
        )
    question = (
        "Decidi la presenza al Level 1 di " + ", ".join(unresolved) + ". "
        "La documentazione attuale non la specifica; inoltre la plaza e documentata come spazio aperto, non facility."
    )
    return (
        "STATUS: NEED_USER_DECISION\nFACILITY_AUDIT:\n" + "\n".join(audit_lines)
        + "\nFILES: NONE\nCHANGE: NONE\n"
        "PRESERVE: Nessuna modifica finche la composizione Level 1 non e decisa.\n"
        "VERIFY: Dopo la decisione, rieseguire inventario, git diff check e Godot headless.\n"
        "LIMITATION: " + ("; ".join(problems) if problems else "NONE") + "\n"
        "QUESTION: " + question + "\nBLOCKER: NONE"
    )


def _plan46(session: Any, task: str, model: str) -> tuple[str, int, int]:
    packet = p2._evidence(task, session)
    inventory = v45._facility_inventory()
    prompt = (
        "USER TASK:\n" + task
        + "\n\nREPOSITORY EVIDENCE:\n" + packet
        + "\n\n" + v45._inventory_packet(inventory)
        + "\n\n" + _policy_packet(inventory)
    )
    response = p2._chat(
        model,
        [
            {"role": "system", "content": PLAN_SYSTEM},
            {"role": "user", "content": prompt},
        ],
        None,
        1000,
    )
    p = int(response.get("prompt_eval_count") or 0)
    o = int(response.get("eval_count") or 0)
    plan = p2._assistant_text(response)

    problems = _plan_has_policy_violation(plan, inventory)
    unresolved = _present_unresolved(inventory)
    first = next((line.strip().upper() for line in plan.splitlines() if line.strip()), "")
    if _full_audit(task) and unresolved and not first.startswith("STATUS: NEED_USER_DECISION"):
        problems.append("complete audit has present UNRESOLVED facilities but status was not NEED_USER_DECISION")

    if problems:
        retry = p2._chat(
            model,
            [
                {"role": "system", "content": PLAN_SYSTEM},
                {
                    "role": "user",
                    "content": (
                        prompt
                        + "\n\nPREVIOUS PLAN FAILED DETERMINISTIC POLICY VALIDATION:\n- "
                        + "\n- ".join(problems)
                        + "\nRewrite once. Do not invent Level 1 decisions for UNRESOLVED facilities.\n\nPREVIOUS PLAN:\n"
                        + plan
                    ),
                },
            ],
            None,
            1050,
        )
        p += int(retry.get("prompt_eval_count") or 0)
        o += int(retry.get("eval_count") or 0)
        plan = p2._assistant_text(retry)
        problems = _plan_has_policy_violation(plan, inventory)
        first = next((line.strip().upper() for line in plan.splitlines() if line.strip()), "")
        if _full_audit(task) and unresolved and not first.startswith("STATUS: NEED_USER_DECISION"):
            problems.append("complete audit still failed to request decision for present UNRESOLVED facilities")
        if problems:
            plan = _deterministic_decision_plan(inventory, problems)
    return plan, p, o


def _facility_aliases(row: dict[str, Any]) -> list[str]:
    values = [
        str(row.get("id") or ""),
        str(row.get("building_type") or ""),
        str(row.get("state_key") or ""),
        str(row.get("display_name") or ""),
    ]
    return [value.casefold() for value in values if value.strip()]


def _planned_removal_ids(plan: str, inventory: dict[str, Any]) -> list[str]:
    change = next((line.split(":", 1)[1].strip() for line in plan.splitlines() if line.strip().upper().startswith("CHANGE:")), "")
    folded = change.casefold()
    if not any(word in folded for word in ("remove", "delete", "elimina", "rimuov")):
        return []
    targets: list[str] = []
    for row in inventory.get("rows") or []:
        if any(alias and alias in folded for alias in _facility_aliases(row)):
            targets.append(str(row.get("id") or ""))
    return targets


def _request_action46(session: Any, task: str, plan: str, targets: list[str], candidates: list[dict[str, Any]], model: str, review_issue: str = ""):
    global _ALLOWED_FACILITY_CANDIDATE_IDS
    inventory = v45._facility_inventory()
    removal_ids = _planned_removal_ids(plan, inventory)
    filtered = candidates
    if v45._facility_scope(task) and removal_ids:
        unsafe = [facility_id for facility_id in removal_ids if _policy_for(facility_id)["status"] != "REQUIRED_ABSENT"]
        if unsafe:
            raise RuntimeError(
                "Policy guard blocked removal of unresolved/non-absent facility ids: " + ", ".join(unsafe)
            )
        allowed: list[dict[str, Any]] = []
        for candidate in candidates:
            line = str(candidate.get("line") or "")
            if "BaseBuildingData.create({" not in line:
                continue
            if any(f'\"id\": \"{facility_id}\"' in line for facility_id in removal_ids):
                allowed.append(candidate)
        if not allowed:
            raise RuntimeError("Planned facility removal has no exact BaseBuildingData row candidate")
        filtered = allowed
        _ALLOWED_FACILITY_CANDIDATE_IDS = {int(item["id"]) for item in allowed}
    else:
        _ALLOWED_FACILITY_CANDIDATE_IDS = None
    return _ORIGINAL_REQUEST_ACTION(session, task, plan, targets, filtered, model, review_issue=review_issue)


def _validate_action46(session: Any, action: dict[str, Any], candidates: list[dict[str, Any]]) -> dict[str, Any]:
    if _ALLOWED_FACILITY_CANDIDATE_IDS is not None and action.get("name") == "choose_line_deletion":
        candidate_id = int((action.get("arguments") or {}).get("candidate_id") or 0)
        if candidate_id not in _ALLOWED_FACILITY_CANDIDATE_IDS:
            raise ValueError(
                f"Facility edit guard rejected unrelated candidate {candidate_id}; allowed={sorted(_ALLOWED_FACILITY_CANDIDATE_IDS)}"
            )
    return _ORIGINAL_VALIDATE_ACTION(session, action, candidates)


def _review46(session: Any, task: str, plan: str, model: str, diff_check: str, godot_check: str):
    inventory = v45._facility_inventory()
    response = p2._chat(
        model,
        [
            {"role": "system", "content": REVIEW_SYSTEM},
            {
                "role": "user",
                "content": (
                    "USER TASK:\n" + task
                    + "\n\nPLAN:\n" + plan
                    + "\n\n" + v45._inventory_packet(inventory)
                    + "\n\n" + _policy_packet(inventory)
                    + "\n\nGIT DIFF:\n" + session.git_diff()
                    + "\n\nGIT DIFF CHECK:\n" + diff_check
                    + "\n\nGODOT CHECK:\n" + godot_check
                ),
            },
        ],
        None,
        750,
    )
    text = p2._assistant_text(response)
    # Deterministic reviewer sanity guard for the exact hallucination seen in v4.5.
    lowered = text.casefold()
    for facility_id in _present_unresolved(inventory):
        if facility_id.casefold() in lowered and any(word in lowered for word in ("forbid", "unauthor", "illegal", "vietat", "non autoriz")):
            text = (
                "REVIEW: ESCALATE\nREASON: Reviewer made an unsupported Level 1 policy claim about "
                + facility_id + "; deterministic policy marks it UNRESOLVED."
            )
            break
    return text, int(response.get("prompt_eval_count") or 0), int(response.get("eval_count") or 0)


def run_programmer(task: str, model: str) -> dict[str, Any]:
    old_plan = v44._plan44
    old_no_change_review = v44._review_no_change
    old_change_review = p2._review
    old_request = v43._request_action
    old_validate = v43._validate_action
    v44._plan44 = _plan46
    v44._review_no_change = _review46
    p2._review = _review46
    v43._request_action = _request_action46
    v43._validate_action = _validate_action46
    try:
        result = v44.run_programmer(task, model)
    finally:
        v44._plan44 = old_plan
        v44._review_no_change = old_no_change_review
        p2._review = old_change_review
        v43._request_action = old_request
        v43._validate_action = old_validate
    result["runtime"] = "programmer-v4.6-level1-policy-guard"
    result["facility_inventory"] = v45._facility_inventory() if v45._facility_scope(task) else {}
    result["facility_policy"] = _policy_packet(result["facility_inventory"]) if result["facility_inventory"] else ""
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_6_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Level 1 policy-guarded programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.6 / LEVEL 1 POLICY GUARD")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Pipeline: deterministic inventory + authoritative Level 1 policy -> guarded decision/edit -> Godot -> guarded review.\n")

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
        print(_policy_packet(inventory))
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
