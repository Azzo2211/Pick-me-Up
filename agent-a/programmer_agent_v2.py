from __future__ import annotations

import argparse
import json
import re
import tempfile
import time
from pathlib import Path
from typing import Any

import programmer_agent_v1 as p1
import readonly_agent as core
import readonly_agent_v3 as v3
import readonly_agent_v5 as v5
import readonly_agent_v6 as v6


MODEL = core.DEFAULT_MODEL
ROOT = core.ROOT
NUM_CTX = 8192
RESEARCH_ROUNDS = 4
EXECUTION_ROUNDS = 5
REPAIR_ROUNDS = 3
EVIDENCE_BUDGET = 16500

MANDATORY_DOCS = [
    "AGENTS.md",
    "docs/AGENT_A.md",
    "docs/DEVELOPMENT_RULES.md",
    "docs/GAME_VISION.md",
    "docs/GAME_SYSTEMS.md",
    "docs/ART_DIRECTION.md",
    "docs/CURRENT_STATE.md",
]

READ_ONLY_TOOLS = v5.TOOLS
EXECUTION_TOOL_NAMES = {
    "read_file",
    "search_text",
    "list_files",
    "inspect_image",
    "git_status",
    "git_diff",
    "replace_text",
    "create_file",
    "restore_file",
}
EXECUTION_TOOLS = [
    tool
    for tool in p1.TOOLS
    if str((tool.get("function") or {}).get("name") or "") in EXECUTION_TOOL_NAMES
]

RESEARCH_SYSTEM = """You are Agent A in RESEARCH stage for a real programming task in Riftward.
The runtime has already read the mandatory repository and design documents. Your job is only to locate and read the concrete implementation evidence needed to edit safely.

Rules:
- Use only read/search/image tools. No implementation in this stage.
- Prefer exact files named by the user, then adjacent implementation files.
- Do not reread mandatory docs unless a different line range is genuinely needed.
- Do not explore unrelated systems.
- Never invent files/functions/behaviors.
- When enough evidence exists to identify the actual change surface and side effects, respond with exactly RESEARCH_COMPLETE and no tool calls.
""".strip()

PLAN_SYSTEM = """You are Agent A, first-line programmer for Riftward. Produce a concise implementation plan from repository evidence.
The newest USER TASK outranks older docs/code.
Do not write code in the plan and do not invent facts.

Output exactly:
STATUS: IMPLEMENT
FILES: <comma-separated real files to change, or NONE>
CHANGE: <smallest complete change>
PRESERVE: <working behavior that must remain>
VERIFY: <checks to run>
LIMITATION: <known limitation, or NONE>

If a genuine product decision is unresolved, output STATUS: NEED_USER_DECISION and one QUESTION line.
If the task is technically unsafe or evidence is insufficient after research, output STATUS: ESCALATE and one BLOCKER line.
""".strip()

EXECUTION_SYSTEM = """You are Agent A in EXECUTION stage. You are the first-line programmer, not an analyst.
The task has already been researched and planned. Implement the smallest complete fix in the real repository now.

Rules:
- Use exact evidence and the plan. Do not restart broad research.
- Read a target file only if the exact edit string is missing from evidence. The runtime remembers which files were already read.
- Prefer replace_text for small changes. Do not rewrite whole systems.
- The newest USER TASK outranks older docs/code.
- Preserve unrelated working behavior.
- Do not edit protected runtime files.
- Do not commit, push, merge, reset or clean.
- Runtime performs verification after your edits; you do not need to run Godot here.
- If a genuine product decision is missing, return NEED_USER_DECISION: ...
- If implementation is unsafe/impossible with available evidence/tools, return ESCALATE_TO_CODEX: ...
- Otherwise make the required mutation(s). Once the implementation is complete, respond IMPLEMENTATION_COMPLETE.
""".strip()

REPAIR_SYSTEM = """You are Agent A in one bounded REPAIR stage after independent review.
Fix only the concrete review issue in the current diff. Do not broaden scope or restart research.
Use repository/edit tools. If the issue cannot be repaired safely, return ESCALATE_TO_CODEX with the concrete blocker.
When fixed, respond REPAIR_COMPLETE.
""".strip()

REVIEW_SYSTEM = """You are the independent verification pass for Agent A's code change.
Audit the USER TASK, evidence, plan, git diff, git diff --check, and Godot smoke result.
The newest user instruction is authoritative.
Check whether the diff actually solves the task, is minimal, preserves adjacent behavior, and avoids invented systems.
A missing Godot executable is a verification limitation, not by itself a code failure.

Output exactly one first line:
REVIEW: PASS
REVIEW: NEEDS_FIX
REVIEW: ESCALATE
Then one short REASON: paragraph naming concrete evidence.
""".strip()

REPORT_SYSTEM = """Summarize a completed Agent A programming task from supplied facts only.
Output short Italian text with these labels:
COMPLETATO:
FILE MODIFICATI:
VERIFICA:
LIMITI:
Do not claim tests passed unless verification says so. Do not mention hypothetical work.
""".strip()


def _chat(model: str, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None, num_predict: int) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": False,
        "think": False,
        "options": {"num_ctx": NUM_CTX, "temperature": 0.1, "num_predict": num_predict},
    }
    if tools:
        payload["tools"] = tools
    return v5._request_ollama(payload)


def _assistant_text(response: dict[str, Any]) -> str:
    return str((response.get("message") or {}).get("content") or "").strip()


def _token_counts(response: dict[str, Any]) -> tuple[int, int]:
    return int(response.get("prompt_eval_count") or 0), int(response.get("eval_count") or 0)


def _record_tool(session: p1.ProgrammerSession, phase: str, name: str, args: dict[str, Any], result: str) -> None:
    session.tool_trace.append({"round": phase, "tool": name, "arguments": args, "result": result})


def _bootstrap(session: p1.ProgrammerSession) -> int:
    count = 0
    for path in MANDATORY_DOCS:
        try:
            if not core._safe_path(path).is_file():
                continue
            result = session.read_file(path=path, start_line=1, end_line=220)
        except Exception as exc:
            result = f"ERROR: {type(exc).__name__}: {exc}"
        _record_tool(session, "bootstrap", "read_file", {"path": path, "start_line": 1, "end_line": 220}, result)
        if not result.startswith("ERROR:"):
            count += 1
    return count


def _resolve_named_files(session: p1.ProgrammerSession, task: str) -> int:
    names = []
    for match in re.finditer(r"(?i)([A-Za-z0-9_./\\-]+\.(?:gd|tscn|tres|md|json|cfg))", task):
        name = match.group(1).replace("\\", "/").strip("`'\".,:;()[]{}")
        if name and name not in names:
            names.append(name)

    reads = 0
    for name in names[:10]:
        candidates: list[str] = []
        if "/" in name:
            if (ROOT / name).is_file():
                candidates = [name]
        else:
            try:
                listing = session.list_files(path="", contains=name, limit=20)
                _record_tool(session, "named-file", "list_files", {"path": "", "contains": name, "limit": 20}, listing)
                candidates = [line.strip() for line in listing.splitlines() if line.strip().endswith("/" + name) or line.strip() == name]
            except Exception:
                candidates = []

        if len(candidates) == 1:
            path = candidates[0]
            try:
                result = session.read_file(path=path, start_line=1, end_line=220)
            except Exception as exc:
                result = f"ERROR: {type(exc).__name__}: {exc}"
            _record_tool(session, "named-file", "read_file", {"path": path, "start_line": 1, "end_line": 220}, result)
            if not result.startswith("ERROR:"):
                reads += 1
    return reads


def _evidence(task: str, session: p1.ProgrammerSession, budget: int = EVIDENCE_BUDGET) -> str:
    return v3.build_evidence_packet(task, session.tool_trace, budget=budget)


def _execute_calls(
    session: p1.ProgrammerSession,
    response: dict[str, Any],
    phase: str,
    max_calls: int = 4,
) -> int:
    calls = (response.get("message") or {}).get("tool_calls") or []
    executed = 0
    for call in calls[:max_calls]:
        fn = call.get("function") or {}
        name = str(fn.get("name") or "")
        args = fn.get("arguments") or {}
        if not isinstance(args, dict):
            args = {}
        print(f"[A {phase}] {name} {json.dumps(args, ensure_ascii=False)}")
        result = session.execute_tool(name, args)
        _record_tool(session, phase, name, args, result)
        executed += 1
    return executed


def _research(session: p1.ProgrammerSession, task: str, model: str) -> tuple[int, int]:
    total_p = 0
    total_o = 0
    for round_no in range(1, RESEARCH_ROUNDS + 1):
        packet = _evidence(task, session, budget=14500)
        response = _chat(
            model,
            [
                {"role": "system", "content": RESEARCH_SYSTEM},
                {
                    "role": "user",
                    "content": (
                        "USER TASK:\n" + task
                        + "\n\nCURRENT EVIDENCE NOTEBOOK:\n" + packet
                        + "\n\nUse tools only for missing implementation evidence. If enough, answer RESEARCH_COMPLETE."
                    ),
                },
            ],
            READ_ONLY_TOOLS,
            500,
        )
        p, o = _token_counts(response)
        total_p += p
        total_o += o
        calls = (response.get("message") or {}).get("tool_calls") or []
        if calls:
            _execute_calls(session, response, f"research-{round_no}", max_calls=3)
            continue
        if "RESEARCH_COMPLETE" in _assistant_text(response).upper():
            break
        # No tool and no completion: one more fresh round may recover without
        # carrying the old conversation/context forward.
    return total_p, total_o


def _auto_visual(session: p1.ProgrammerSession, model: str) -> tuple[int, int]:
    image_paths: set[str] = {
        str(item.get("arguments", {}).get("path") or "")
        for item in session.tool_trace
        if item.get("tool") == "inspect_image" and not str(item.get("result") or "").startswith("ERROR:")
    }
    return v6._append_auto_image_inspections(session.tool_trace, image_paths, model, NUM_CTX)


def _plan(session: p1.ProgrammerSession, task: str, model: str) -> tuple[str, int, int]:
    packet = _evidence(task, session)
    response = _chat(
        model,
        [
            {"role": "system", "content": PLAN_SYSTEM},
            {"role": "user", "content": "USER TASK:\n" + task + "\n\nREPOSITORY EVIDENCE:\n" + packet},
        ],
        None,
        650,
    )
    p, o = _token_counts(response)
    return _assistant_text(response), p, o


def _execution(
    session: p1.ProgrammerSession,
    task: str,
    plan: str,
    model: str,
    rounds: int = EXECUTION_ROUNDS,
    repair_reason: str = "",
) -> tuple[str, int, int]:
    total_p = 0
    total_o = 0
    last_text = ""
    system = REPAIR_SYSTEM if repair_reason else EXECUTION_SYSTEM

    for round_no in range(1, rounds + 1):
        packet = _evidence(task, session, budget=13500)
        diff = session.git_diff()
        urgency = ""
        if not session.changed_paths and round_no >= 3:
            urgency = (
                "\n\nIMPORTANT: no mutation has been made yet. This round must either call replace_text/create_file "
                "for the planned fix or return a concrete ESCALATE_TO_CODEX/NEED_USER_DECISION. Do not continue researching."
            )
        repair = ("\n\nREVIEW ISSUE TO REPAIR:\n" + repair_reason) if repair_reason else ""
        response = _chat(
            model,
            [
                {"role": "system", "content": system},
                {
                    "role": "user",
                    "content": (
                        "USER TASK:\n" + task
                        + "\n\nAPPROVED PLAN:\n" + plan
                        + repair
                        + "\n\nEVIDENCE NOTEBOOK:\n" + packet
                        + "\n\nCURRENT DIFF:\n" + p1._cap(diff, 9000)
                        + urgency
                    ),
                },
            ],
            EXECUTION_TOOLS,
            650,
        )
        p, o = _token_counts(response)
        total_p += p
        total_o += o
        calls = (response.get("message") or {}).get("tool_calls") or []
        if calls:
            _execute_calls(session, response, f"execute-{round_no}", max_calls=4)
            continue

        last_text = _assistant_text(response)
        folded = last_text.upper()
        if "NEED_USER_DECISION" in folded or "ESCALATE_TO_CODEX" in folded:
            break
        if session.changed_paths and ("IMPLEMENTATION_COMPLETE" in folded or "REPAIR_COMPLETE" in folded):
            break
        if session.changed_paths and round_no >= 2:
            # Runtime verification is the authoritative completion check; avoid
            # wasting more model rounds when a real diff already exists.
            break

    return last_text, total_p, total_o


def _review(
    session: p1.ProgrammerSession,
    task: str,
    plan: str,
    model: str,
    diff_check: str,
    godot_check: str,
) -> tuple[str, int, int]:
    packet = _evidence(task, session, budget=10500)
    diff = session.git_diff()
    response = _chat(
        model,
        [
            {"role": "system", "content": REVIEW_SYSTEM},
            {
                "role": "user",
                "content": (
                    "USER TASK:\n" + task
                    + "\n\nPLAN:\n" + plan
                    + "\n\nEVIDENCE:\n" + packet
                    + "\n\nGIT DIFF:\n" + p1._cap(diff, 13000)
                    + "\n\nGIT DIFF CHECK:\n" + diff_check
                    + "\n\nGODOT CHECK:\n" + godot_check
                ),
            },
        ],
        None,
        600,
    )
    p, o = _token_counts(response)
    return _assistant_text(response), p, o


def _review_status(text: str) -> str:
    first = next((line.strip().upper() for line in text.splitlines() if line.strip()), "")
    if first == "REVIEW: PASS":
        return "PASS"
    if first == "REVIEW: NEEDS_FIX":
        return "NEEDS_FIX"
    if first == "REVIEW: ESCALATE":
        return "ESCALATE"
    return "UNKNOWN"


def _final_report(
    session: p1.ProgrammerSession,
    task: str,
    plan: str,
    review: str,
    diff_check: str,
    godot_check: str,
    model: str,
) -> tuple[str, int, int]:
    response = _chat(
        model,
        [
            {"role": "system", "content": REPORT_SYSTEM},
            {
                "role": "user",
                "content": (
                    "TASK:\n" + task
                    + "\n\nPLAN:\n" + plan
                    + "\n\nCHANGED FILES:\n" + ", ".join(sorted(session.changed_paths))
                    + "\n\nDIFF CHECK:\n" + diff_check
                    + "\n\nGODOT CHECK:\n" + godot_check
                    + "\n\nFINAL REVIEW:\n" + review
                ),
            },
        ],
        None,
        450,
    )
    p, o = _token_counts(response)
    text = _assistant_text(response)
    if not text:
        text = (
            "COMPLETATO: modifica implementata e revisionata.\n"
            "FILE MODIFICATI: " + ", ".join(sorted(session.changed_paths)) + "\n"
            "VERIFICA: " + diff_check.splitlines()[0] + "; " + godot_check.splitlines()[0] + "\n"
            "LIMITI: vedere il report di review."
        )
    return text, p, o


def _is_previous_task_branch(branch: str) -> bool:
    return bool(re.search(r"-\d{8}-\d{6}$", branch))


def run_programmer(task: str, model: str) -> dict[str, Any]:
    started = time.perf_counter()

    current = p1._git_output(["branch", "--show-current"]).strip()
    if _is_previous_task_branch(current):
        raise RuntimeError(
            "Current branch looks like a previous Agent A task branch (" + current + "). "
            "Switch back to agent-a/readonly-runtime before starting a new task."
        )

    session = p1.ProgrammerSession(task)
    branch_note = session.preflight_and_branch()
    total_p = 0
    total_o = 0
    reviews: list[str] = []
    diff_check = "NOT RUN"
    godot_check = "NOT RUN"
    plan = ""
    final = ""
    escalation = False
    user_decision = False

    bootstrap_reads = _bootstrap(session)
    named_reads = _resolve_named_files(session, task)
    p, o = _research(session, task, model)
    total_p += p
    total_o += o
    auto_visual_added, auto_visual_failures = _auto_visual(session, model)

    if not any(path.endswith(".gd") for path in session.read_paths):
        escalation = True
        final = "ESCALATE_TO_CODEX: Agent A could not locate and read a relevant Godot implementation file."
    elif session.discovery_count < 1:
        escalation = True
        final = "ESCALATE_TO_CODEX: Agent A did not establish a repository discovery trail for the task."

    if not escalation:
        plan, p, o = _plan(session, task, model)
        total_p += p
        total_o += o
        status_line = next((line.strip().upper() for line in plan.splitlines() if line.strip()), "")
        if status_line.startswith("STATUS: NEED_USER_DECISION"):
            user_decision = True
            final = plan
        elif status_line.startswith("STATUS: ESCALATE") or not status_line.startswith("STATUS: IMPLEMENT"):
            escalation = True
            final = "ESCALATE_TO_CODEX: planning stage did not reach a grounded implementation plan.\n" + plan

    if not escalation and not user_decision:
        exec_text, p, o = _execution(session, task, plan, model)
        total_p += p
        total_o += o
        folded = exec_text.upper()
        if "NEED_USER_DECISION" in folded:
            user_decision = True
            session.restore_all()
            final = exec_text + "\nRuntime safety: speculative edits were restored."
        elif "ESCALATE_TO_CODEX" in folded:
            escalation = True
            final = exec_text
        elif not session.changed_paths:
            escalation = True
            final = "ESCALATE_TO_CODEX: execution stage finished without producing a real code/document change."

    final_review = ""
    if session.changed_paths and not user_decision:
        diff_check = session.git_diff_check()
        godot_check = session.run_godot_check()
        review, p, o = _review(session, task, plan, model, diff_check, godot_check)
        total_p += p
        total_o += o
        reviews.append(review)
        status = _review_status(review)

        if status == "NEEDS_FIX" and not escalation:
            repair_text, p, o = _execution(
                session,
                task,
                plan,
                model,
                rounds=REPAIR_ROUNDS,
                repair_reason=review,
            )
            total_p += p
            total_o += o
            if "ESCALATE_TO_CODEX" in repair_text.upper():
                escalation = True
                final = repair_text
            diff_check = session.git_diff_check()
            godot_check = session.run_godot_check()
            review2, p, o = _review(session, task, plan, model, diff_check, godot_check)
            total_p += p
            total_o += o
            reviews.append(review2)
            review = review2
            status = _review_status(review2)

        final_review = review
        if status != "PASS":
            escalation = True
            final = (
                "ESCALATE_TO_CODEX: Agent A produced a diff but independent verification did not reach PASS. "
                "The task branch and diff are preserved for Codex/Sol inspection.\n" + review
            )
        elif not escalation:
            final, p, o = _final_report(session, task, plan, review, diff_check, godot_check, model)
            total_p += p
            total_o += o

    # Coherent fallback: if the runtime has no trustworthy terminal result, it is
    # an escalation, and the boolean must agree with the printed final text.
    if not final:
        escalation = True
        final = "ESCALATE_TO_CODEX: no reliable final result was produced by the staged programmer workflow."
    if "ESCALATE_TO_CODEX" in final.upper():
        escalation = True

    result = {
        "runtime": "programmer-v2-staged",
        "model": model,
        "elapsed_seconds": round(time.perf_counter() - started, 1),
        "base_branch": session.base_branch,
        "task_branch": session.task_branch,
        "branch_note": branch_note,
        "bootstrap_reads": bootstrap_reads,
        "named_file_reads": named_reads,
        "auto_visual_added": auto_visual_added,
        "auto_visual_failures": auto_visual_failures,
        "changed_files": sorted(session.changed_paths),
        "mutations": session.mutations,
        "prompt_tokens_total": total_p,
        "output_tokens_total": total_o,
        "diff_check": diff_check,
        "godot_check": godot_check,
        "reviews": reviews,
        "plan": plan,
        "escalate_to_codex": escalation,
        "needs_user_decision": user_decision,
        "final": final,
        "diff": session.git_diff(),
        "trace": session.tool_trace,
        "final_review": final_review,
    }
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v2_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Staged controlled programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    task = args.task.strip()
    print("Riftward Agent A - PROGRAMMER v2 / STAGED CONTROLLED WRITES")
    print(f"Repository: {ROOT}")
    print(f"Model: {args.model}")
    print("Pipeline: bootstrap -> research -> plan -> execute -> verify -> one repair -> report. No commit/push/merge.\n")
    if not task:
        try:
            task = input("Descrivi il lavoro da fare ad Agent A:\n> ").strip()
        except EOFError:
            task = ""
    if not task:
        print("Nessun task inserito. Uscita senza modifiche.")
        return 2

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
    print("\n========== VERIFICATION ==========")
    print(result["diff_check"])
    print(result["godot_check"])
    for index, review in enumerate(result["reviews"], 1):
        print(f"\n--- REVIEW {index} ---\n{review}")
    print("\n========== RUN DATA ==========")
    print(f"Runtime: {result['runtime']}")
    print(f"Time: {result['elapsed_seconds']} seconds")
    print(f"Base branch: {result['base_branch']}")
    print(f"Task branch: {result['task_branch']}")
    print(f"Bootstrap reads: {result['bootstrap_reads']}")
    print(f"Named-file reads: {result['named_file_reads']}")
    print(f"Auto-visual inspections: {result['auto_visual_added']} (failures {result['auto_visual_failures']})")
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
