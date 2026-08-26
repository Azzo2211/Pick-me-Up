from __future__ import annotations

import argparse
import json
import tempfile
import time
from pathlib import Path
from typing import Any

import programmer_agent_v1 as p1
import programmer_agent_v2 as p2
import programmer_agent_v3 as p3
import programmer_agent_v4_2 as transport
import programmer_agent_v4_3 as v43
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
NUM_CTX = 8192

PLAN_SYSTEM = """You are Agent A, first-line programmer for Riftward. Produce a concise grounded plan from repository evidence.
The newest USER TASK outranks older docs/code. Do not invent facts or changes.

Choose exactly one status:
- STATUS: IMPLEMENT when a concrete repository change is actually required.
- STATUS: NO_CHANGE when the requested behavior is already correctly implemented and changing code would be unnecessary or harmful.
- STATUS: NEED_USER_DECISION only for a genuine unresolved product choice.
- STATUS: ESCALATE only when evidence is insufficient or the task is technically unsafe.

For IMPLEMENT or NO_CHANGE output exactly these lines:
STATUS: <IMPLEMENT or NO_CHANGE>
FILES: <comma-separated real files that need changing, or NONE>
CHANGE: <smallest complete change, or NONE when no change is needed>
PRESERVE: <working behavior that must remain>
VERIFY: <checks to run>
LIMITATION: <known limitation, or NONE>

If NEED_USER_DECISION, output STATUS: NEED_USER_DECISION and one QUESTION line.
If ESCALATE, output STATUS: ESCALATE and one BLOCKER line.

Important: if repository evidence proves the task is already satisfied, use NO_CHANGE. Never invent an edit merely to produce a diff.
""".strip()

NO_CHANGE_REVIEW_SYSTEM = """You are the independent verification pass for a Riftward programming task where Agent A concluded NO_CHANGE.
Audit the USER TASK, repository evidence, plan, git diff check, and Godot smoke result.
PASS only if the evidence actually demonstrates that the requested behavior is already satisfied and no code change is required.
If a concrete change is still required, return NEEDS_FIX. If evidence is insufficient, return ESCALATE.

Output exactly one first line:
REVIEW: PASS
REVIEW: NEEDS_FIX
REVIEW: ESCALATE
Then one short REASON: paragraph grounded in supplied evidence.
""".strip()


def _counts(response: dict[str, Any]) -> tuple[int, int]:
    return int(response.get("prompt_eval_count") or 0), int(response.get("eval_count") or 0)


def _plan44(session: p1.ProgrammerSession, task: str, model: str) -> tuple[str, int, int]:
    packet = p2._evidence(task, session)
    response = p2._chat(
        model,
        [
            {"role": "system", "content": PLAN_SYSTEM},
            {"role": "user", "content": "USER TASK:\n" + task + "\n\nREPOSITORY EVIDENCE:\n" + packet},
        ],
        None,
        650,
    )
    p, o = _counts(response)
    return p2._assistant_text(response), p, o


def _review_no_change(
    session: p1.ProgrammerSession,
    task: str,
    plan: str,
    model: str,
    diff_check: str,
    godot_check: str,
) -> tuple[str, int, int]:
    packet = p2._evidence(task, session, budget=12500)
    response = p2._chat(
        model,
        [
            {"role": "system", "content": NO_CHANGE_REVIEW_SYSTEM},
            {
                "role": "user",
                "content": (
                    "USER TASK:\n" + task
                    + "\n\nNO-CHANGE PLAN:\n" + plan
                    + "\n\nREPOSITORY EVIDENCE:\n" + packet
                    + "\n\nCURRENT GIT DIFF:\n" + session.git_diff()
                    + "\n\nGIT DIFF CHECK:\n" + diff_check
                    + "\n\nGODOT CHECK:\n" + godot_check
                ),
            },
        ],
        None,
        550,
    )
    p, o = _counts(response)
    return p2._assistant_text(response), p, o


def _no_change_final(diff_check: str, godot_check: str, review: str, plan: str) -> str:
    limitation = "NONE"
    for line in plan.splitlines():
        if line.strip().upper().startswith("LIMITATION:"):
            limitation = line.split(":", 1)[1].strip() or "NONE"
            break
    return (
        "NO_CHANGE_NEEDED: Agent A ha verificato che il comportamento richiesto e gia soddisfatto; "
        "nessuna modifica e stata inventata.\n"
        "FILE MODIFICATI: NONE\n"
        "VERIFICA: " + diff_check.splitlines()[0] + "; " + godot_check.splitlines()[0] + ".\n"
        "REVIEW: " + (review.splitlines()[0] if review else "NOT RUN") + "\n"
        "LIMITI: " + limitation
    )


def run_programmer(task: str, model: str) -> dict[str, Any]:
    started = time.perf_counter()
    v43._check_base_state()
    session = p1.ProgrammerSession(task)
    total_p = 0
    total_o = 0
    reviews: list[str] = []
    diff_check = "NOT RUN"
    godot_check = "NOT RUN"
    final = ""
    escalation = False
    user_decision = False
    branch_note = "NOT CREATED"
    edit: dict[str, Any] = {}
    targets: list[str] = []
    candidates: list[dict[str, Any]] = []

    bootstrap_reads = p2._bootstrap(session)
    discovered = v43._deterministic_discovery(session, task)
    if not any(path.endswith(".gd") for path in session.read_paths):
        escalation = True
        final = "ESCALATE_TO_CODEX: deterministic discovery did not find/read relevant Godot implementation."
        plan = ""
    else:
        plan, p, o = _plan44(session, task, model)
        total_p += p
        total_o += o
        status_line = next((line.strip().upper() for line in plan.splitlines() if line.strip()), "")

        if status_line.startswith("STATUS: NO_CHANGE"):
            diff_check = session.git_diff_check()
            godot_check = session.run_godot_check()
            review, p, o = _review_no_change(session, task, plan, model, diff_check, godot_check)
            total_p += p
            total_o += o
            reviews.append(review)
            status = p2._review_status(review)
            if status == "PASS":
                final = _no_change_final(diff_check, godot_check, review, plan)
            elif status == "NEEDS_FIX":
                escalation = True
                final = (
                    "ESCALATE_TO_CODEX: Agent A proposed NO_CHANGE but independent review found that a change is still required.\n"
                    + review
                )
            else:
                escalation = True
                final = "ESCALATE_TO_CODEX: NO_CHANGE review could not verify the conclusion.\n" + review

        elif status_line.startswith("STATUS: NEED_USER_DECISION"):
            user_decision = True
            final = plan
        elif status_line.startswith("STATUS: ESCALATE") or not status_line.startswith("STATUS: IMPLEMENT"):
            escalation = True
            final = "ESCALATE_TO_CODEX: planning stage did not reach a valid terminal status.\n" + plan
        else:
            targets = v43._resolve_targets(plan, task, discovered)
            for path in targets:
                p3._ensure_read(session, path)
            candidates = v43._build_candidates(targets, task, plan)

    if not final and not escalation and not user_decision:
        if not targets:
            escalation = True
            final = "ESCALATE_TO_CODEX: no real target files could be resolved from the grounded plan."
        else:
            try:
                raw_action, p, o, _ = v43._request_action(session, task, plan, targets, candidates, model)
                total_p += p
                total_o += o
                edit = v43._validate_action(session, raw_action, candidates)
            except Exception as exc:
                escalation = True
                final = "ESCALATE_TO_CODEX: compact edit selection failed: " + f"{type(exc).__name__}: {exc}"

    if not final and not escalation and not user_decision:
        if edit.get("kind") == "decision":
            user_decision = True
            final = "NEED_USER_DECISION: " + edit["message"]
        elif edit.get("kind") == "escalate":
            escalation = True
            final = "ESCALATE_TO_CODEX: " + edit["message"]
        elif edit.get("kind") == "edit":
            branch_note = session.preflight_and_branch()
            v43._apply_edit(session, edit)
        else:
            escalation = True
            final = "ESCALATE_TO_CODEX: no validated edit action was produced."

    if session.changed_paths and not user_decision:
        diff_check = session.git_diff_check()
        godot_check = session.run_godot_check()
        review, p, o = p2._review(session, task, plan, model, diff_check, godot_check)
        total_p += p
        total_o += o
        reviews.append(review)
        status = p2._review_status(review)

        if status == "NEEDS_FIX" and not escalation:
            try:
                repair_candidates = v43._build_candidates(targets, task, plan + "\n" + review)
                raw_action, p, o, _ = v43._request_action(
                    session, task, plan, targets, repair_candidates, model, review_issue=review
                )
                total_p += p
                total_o += o
                repair = v43._validate_action(session, raw_action, repair_candidates)
                if repair.get("kind") != "edit":
                    raise RuntimeError("repair stage did not produce an edit")
                v43._apply_edit(session, repair)
                edit = repair
            except Exception as exc:
                escalation = True
                final = "ESCALATE_TO_CODEX: bounded repair failed: " + f"{type(exc).__name__}: {exc}"

            diff_check = session.git_diff_check()
            godot_check = session.run_godot_check()
            review2, p, o = p2._review(session, task, plan, model, diff_check, godot_check)
            total_p += p
            total_o += o
            reviews.append(review2)
            review = review2
            status = p2._review_status(review2)

        if status != "PASS":
            escalation = True
            if not final:
                final = (
                    "ESCALATE_TO_CODEX: a real diff was produced but independent review did not reach PASS.\n" + review
                )
        elif not escalation:
            final = v43._deterministic_report(session, edit, diff_check, godot_check, review)

    if not final:
        escalation = True
        final = "ESCALATE_TO_CODEX: no reliable terminal result was produced."
    if "ESCALATE_TO_CODEX" in final.upper():
        escalation = True

    return {
        "runtime": "programmer-v4.4-no-change-aware",
        "model": model,
        "elapsed_seconds": round(time.perf_counter() - started, 1),
        "base_branch": session.base_branch or v43._current_branch(),
        "task_branch": session.task_branch or "NOT CREATED",
        "branch_note": branch_note,
        "bootstrap_reads": bootstrap_reads,
        "discovered_files": discovered,
        "target_paths": targets,
        "candidate_count": len(candidates),
        "changed_files": sorted(session.changed_paths),
        "mutations": session.mutations,
        "prompt_tokens_total": total_p,
        "output_tokens_total": total_o,
        "diff_check": diff_check,
        "godot_check": godot_check,
        "reviews": reviews,
        "plan": plan,
        "edit": edit,
        "escalate_to_codex": escalation,
        "needs_user_decision": user_decision,
        "final": final,
        "diff": session.git_diff() if session.task_branch else "NO TASK DIFF",
        "trace": session.tool_trace,
    }


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_4_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="No-change-aware programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.4 / NO-CHANGE AWARE")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Pipeline: model preflight -> deterministic evidence -> IMPLEMENT/NO_CHANGE decision -> verify -> independent review.\n")

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
