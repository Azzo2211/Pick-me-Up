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
import programmer_agent_v3 as p3
import programmer_agent_v4_2 as transport
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
NUM_CTX = 8192
MAX_TARGET_FILES = 4
MAX_CANDIDATES = 14

ACTION_SYSTEM = """You are Agent A, first-line programmer for Riftward.
The task has already been researched and planned. Choose ONE smallest concrete repository edit now.
You MUST call exactly one provided function. Do not answer with prose.

Use choose_line_deletion when the intended change is removing one whole existing source line and the candidate list contains the exact correct line.
Use replace_text only when a deletion candidate cannot express the required edit safely.
Use need_user_decision only for a genuine unresolved product choice.
Use escalate_to_codex only for a concrete technical blocker.

The USER TASK and current repository text are authoritative. The plan is advisory and may be imperfect.
Do not delete generic future-support handlers merely because a Level 1 data entry is being removed.
Prefer the smallest complete change and preserve unrelated working systems.
""".strip()

REPAIR_SYSTEM = """You are Agent A performing one bounded repair after independent review.
Choose ONE concrete edit that fixes only the review issue. You MUST call exactly one provided function.
Do not broaden scope. If no safe repair is possible, call escalate_to_codex.
""".strip()


def _tool(name: str, description: str, parameters: dict[str, Any]) -> dict[str, Any]:
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": description,
            "parameters": parameters,
        },
    }


ACTION_TOOLS = [
    _tool(
        "choose_line_deletion",
        "Select one numbered candidate source line shown in the prompt. Runtime deletes that exact current line only after validation.",
        {
            "type": "object",
            "required": ["candidate_id"],
            "properties": {
                "candidate_id": {"type": "integer", "minimum": 1, "maximum": MAX_CANDIDATES},
                "reason": {"type": "string"},
                "limitation": {"type": "string"},
            },
        },
    ),
    _tool(
        "replace_text",
        "Submit one exact small replacement in a real target file. Use only when a whole-line deletion candidate cannot solve the task.",
        {
            "type": "object",
            "required": ["path", "old", "new"],
            "properties": {
                "path": {"type": "string"},
                "old": {"type": "string"},
                "new": {"type": "string"},
                "expected_count": {"type": "integer", "minimum": 1, "maximum": 10},
                "reason": {"type": "string"},
                "limitation": {"type": "string"},
            },
        },
    ),
    _tool(
        "need_user_decision",
        "Stop because a genuine product decision is required before a safe edit can be made.",
        {
            "type": "object",
            "required": ["question"],
            "properties": {"question": {"type": "string"}},
        },
    ),
    _tool(
        "escalate_to_codex",
        "Stop because a concrete technical blocker prevents a safe implementation.",
        {
            "type": "object",
            "required": ["blocker"],
            "properties": {"blocker": {"type": "string"}},
        },
    ),
]


def _counts(response: dict[str, Any]) -> tuple[int, int]:
    return int(response.get("prompt_eval_count") or 0), int(response.get("eval_count") or 0)


def _current_branch() -> str:
    return p1._git_output(["branch", "--show-current"]).strip()


def _check_base_state() -> None:
    branch = _current_branch()
    if not branch:
        raise RuntimeError("Detached HEAD is not allowed")
    if re.search(r"-\d{8}-\d{6}$", branch):
        raise RuntimeError(
            "Current branch looks like a previous Agent A task branch (" + branch + "). "
            "Switch back to agent-a/readonly-runtime before starting a new task."
        )
    raw = p1._git_output(["status", "--porcelain=v1", "--untracked-files=all"])
    tracked_dirty = [line for line in raw.splitlines() if line and not line.startswith("??")]
    if tracked_dirty:
        raise RuntimeError(
            "Tracked working-tree changes already exist. Agent A refuses to plan/edit over them:\n"
            + "\n".join(tracked_dirty)
        )


def _significant_terms(task: str) -> list[str]:
    stop = {
        "della", "delle", "degli", "dello", "dalla", "dalle", "questo", "questa", "quello",
        "quella", "perche", "affinche", "secondo", "attuale", "livello", "level", "base", "godot",
        "essere", "disponibile", "abbia", "fisicamente", "assente", "hero", "heroes", "interattivo",
        "correggi", "senza", "dentro", "nella", "nelle", "with", "that", "this", "from", "into",
    }
    raw = re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", task)
    terms: list[str] = []
    for token in raw:
        folded = token.casefold()
        if folded in stop:
            continue
        if folded in {item.casefold() for item in terms}:
            continue
        terms.append(token)
    # Strong implementation/domain terms first.
    terms.sort(key=lambda value: (0 if value.lower() in {"workshop", "alchemy", "hotspot", "armory", "fusion", "portal"} else 1, -len(value)))
    return terms[:8]


def _record(session: p1.ProgrammerSession, phase: str, tool: str, arguments: dict[str, Any], result: str) -> None:
    session.tool_trace.append({"round": phase, "tool": tool, "arguments": arguments, "result": result})


def _deterministic_discovery(session: p1.ProgrammerSession, task: str) -> list[str]:
    discovered: list[str] = []
    terms = _significant_terms(task)
    if not terms:
        terms = ["Workshop", "Alchemy"]

    for term in terms:
        try:
            result = session.search_text(query=term, path="godot", limit=12)
        except Exception as exc:
            result = f"ERROR: {type(exc).__name__}: {exc}"
        _record(session, "fast-search", "search_text", {"query": term, "path": "godot", "limit": 12}, result)
        if result.startswith("ERROR:") or result.startswith("NO MATCHES"):
            continue
        for line in result.splitlines():
            path = line.split(":", 1)[0].strip()
            if path.endswith(".gd") and path not in discovered:
                discovered.append(path)

    # Resolve filenames explicitly named by the user, if any.
    for path in p3._task_named_paths(task):
        if path not in discovered:
            discovered.insert(0, path)

    # Read the strongest implementation hits. This satisfies the programmer write gate
    # and gives the plan call actual source instead of broad tool loops.
    for path in discovered[:8]:
        try:
            result = session.read_file(path=path, start_line=1, end_line=220)
        except Exception as exc:
            result = f"ERROR: {type(exc).__name__}: {exc}"
        _record(session, "fast-read", "read_file", {"path": path, "start_line": 1, "end_line": 220}, result)
    return discovered


def _resolve_targets(plan: str, task: str, discovered: list[str]) -> list[str]:
    targets = p3._plan_paths(plan)
    for path in p3._task_named_paths(task):
        if path not in targets:
            targets.append(path)
    if not targets:
        targets.extend(discovered[:2])
    return list(dict.fromkeys(path for path in targets if (core.ROOT / path).is_file()))[:MAX_TARGET_FILES]


def _candidate_terms(task: str, plan: str) -> list[str]:
    terms = _significant_terms(task)
    for token in re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", plan):
        if token.casefold() in {x.casefold() for x in terms}:
            continue
        if token.lower() in {"status", "implement", "files", "change", "preserve", "verify", "limitation", "remove", "entry", "array", "ensure", "from", "level"}:
            continue
        terms.append(token)
        if len(terms) >= 14:
            break
    return terms


def _build_candidates(paths: list[str], task: str, plan: str) -> list[dict[str, Any]]:
    terms = [term.casefold() for term in _candidate_terms(task, plan)]
    scored: list[tuple[int, str, int, str]] = []
    for path in paths:
        text = core._safe_path(path).read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(keepends=True), 1):
            folded = line.casefold()
            hits = sum(1 for term in terms if term in folded)
            if hits <= 0:
                continue
            score = hits * 10
            if "BaseBuildingData.create" in line:
                score += 12
            if '"id"' in line or '"state_key"' in line:
                score += 6
            if line.lstrip().startswith("#"):
                score -= 8
            scored.append((score, path, line_no, line))
    scored.sort(key=lambda item: (-item[0], item[1], item[2]))

    candidates: list[dict[str, Any]] = []
    for _, path, line_no, line in scored[:MAX_CANDIDATES]:
        candidates.append({
            "id": len(candidates) + 1,
            "path": path,
            "line_no": line_no,
            "line": line,
        })
    return candidates


def _candidate_prompt(candidates: list[dict[str, Any]]) -> str:
    if not candidates:
        return "NO LINE DELETION CANDIDATES"
    rows: list[str] = []
    for candidate in candidates:
        visible = candidate["line"].rstrip("\r\n")
        if len(visible) > 900:
            visible = visible[:900] + " ... [line truncated in prompt; runtime retains exact line]"
        rows.append(
            f"CANDIDATE {candidate['id']} | {candidate['path']}:{candidate['line_no']}\n{visible}"
        )
    return "\n\n".join(rows)


def _target_context(paths: list[str], task: str, plan: str) -> str:
    return p3._file_context(paths, task, plan)[:18000]


def _request_action(
    session: p1.ProgrammerSession,
    task: str,
    plan: str,
    targets: list[str],
    candidates: list[dict[str, Any]],
    model: str,
    review_issue: str = "",
) -> tuple[dict[str, Any], int, int, str]:
    issue = ("\n\nINDEPENDENT REVIEW ISSUE:\n" + review_issue) if review_issue else ""
    content = (
        "USER TASK:\n" + task
        + "\n\nADVISORY PLAN:\n" + plan
        + issue
        + "\n\nNUMBERED WHOLE-LINE DELETION CANDIDATES:\n" + _candidate_prompt(candidates)
        + "\n\nCURRENT TARGET FILE CONTEXT:\n" + _target_context(targets, task, plan)
        + "\n\nCall exactly one function now."
    )
    system = REPAIR_SYSTEM if review_issue else ACTION_SYSTEM

    total_p = 0
    total_o = 0
    last_text = ""
    for attempt in range(1, 4):
        response = v5._request_ollama({
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": content + ("\n\nAttempt %d: a function call is mandatory." % attempt)},
            ],
            "tools": ACTION_TOOLS,
            "stream": False,
            "think": False,
            "options": {"num_ctx": NUM_CTX, "temperature": 0.0, "num_predict": 420},
        })
        p, o = _counts(response)
        total_p += p
        total_o += o
        message = response.get("message") or {}
        last_text = str(message.get("content") or "").strip()
        calls = message.get("tool_calls") or []
        for call in calls:
            fn = call.get("function") or {}
            name = str(fn.get("name") or "")
            if name not in {"choose_line_deletion", "replace_text", "need_user_decision", "escalate_to_codex"}:
                continue
            args = fn.get("arguments") or {}
            if not isinstance(args, dict):
                continue
            return {"name": name, "arguments": args}, total_p, total_o, last_text
    raise RuntimeError(
        "Qwen did not emit any valid edit/decision tool call after 3 compact attempts. Last text: "
        + (last_text[:500] or "[empty]")
    )


def _validate_action(
    session: p1.ProgrammerSession,
    action: dict[str, Any],
    candidates: list[dict[str, Any]],
) -> dict[str, Any]:
    name = action["name"]
    args = action["arguments"]
    if name == "choose_line_deletion":
        candidate_id = int(args.get("candidate_id") or 0)
        match = next((item for item in candidates if item["id"] == candidate_id), None)
        if match is None:
            raise ValueError(f"Unknown candidate_id {candidate_id}")
        path = str(match["path"])
        p3._ensure_read(session, path)
        current = core._safe_path(path).read_text(encoding="utf-8", errors="replace")
        old = str(match["line"])
        if current.count(old) != 1:
            raise ValueError("Selected candidate line is no longer unique/current")
        return {
            "kind": "edit",
            "path": path,
            "old": old,
            "new": "",
            "expected_count": 1,
            "reason": str(args.get("reason") or ""),
            "limitation": str(args.get("limitation") or ""),
            "source": f"candidate:{candidate_id}",
        }

    if name == "replace_text":
        path = str(args.get("path") or "").replace("\\", "/").lstrip("/")
        old = str(args.get("old") or "")
        new = str(args.get("new") or "")
        expected = int(args.get("expected_count") or 1)
        if not path or not old:
            raise ValueError("replace_text requires path and non-empty old")
        if path not in session.read_paths:
            p3._ensure_read(session, path)
        _, target = p1._editable_path(path, must_exist=True)
        current = target.read_text(encoding="utf-8", errors="replace")
        if current.count(old) != expected:
            raise ValueError(
                f"replace_text mismatch in {path}: expected {expected}, found {current.count(old)}"
            )
        return {
            "kind": "edit",
            "path": path,
            "old": old,
            "new": new,
            "expected_count": expected,
            "reason": str(args.get("reason") or ""),
            "limitation": str(args.get("limitation") or ""),
            "source": "replace_text",
        }

    if name == "need_user_decision":
        return {"kind": "decision", "message": str(args.get("question") or "Product decision required.")}
    if name == "escalate_to_codex":
        return {"kind": "escalate", "message": str(args.get("blocker") or "Concrete technical blocker.")}
    raise ValueError(f"Unsupported action {name}")


def _apply_edit(session: p1.ProgrammerSession, edit: dict[str, Any]) -> str:
    result = session.replace_text(
        path=edit["path"],
        old=edit["old"],
        new=edit["new"],
        expected_count=edit["expected_count"],
    )
    _record(
        session,
        "fast-edit",
        edit["source"],
        {"path": edit["path"], "expected_count": edit["expected_count"]},
        result,
    )
    return result


def _deterministic_report(
    session: p1.ProgrammerSession,
    edit: dict[str, Any],
    diff_check: str,
    godot_check: str,
    review: str,
) -> str:
    limitation = edit.get("limitation") or "Nessun limite dichiarato dal modello."
    godot_first = godot_check.splitlines()[0] if godot_check else "NOT RUN"
    diff_first = diff_check.splitlines()[0] if diff_check else "NOT RUN"
    return (
        "COMPLETATO: Agent A ha applicato una modifica reale al progetto.\n"
        "FILE MODIFICATI: " + ", ".join(sorted(session.changed_paths)) + "\n"
        "MODIFICA: " + (edit.get("reason") or edit.get("source") or "modifica minima") + "\n"
        "VERIFICA: " + diff_first + "; " + godot_first + ".\n"
        "REVIEW: " + (review.splitlines()[0] if review else "NOT RUN") + "\n"
        "LIMITI: " + limitation
    )


def run_programmer(task: str, model: str) -> dict[str, Any]:
    started = time.perf_counter()
    _check_base_state()
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

    bootstrap_reads = p2._bootstrap(session)
    discovered = _deterministic_discovery(session, task)
    if not any(path.endswith(".gd") for path in session.read_paths):
        escalation = True
        final = "ESCALATE_TO_CODEX: deterministic discovery did not find/read relevant Godot implementation."
        plan = ""
        targets: list[str] = []
        candidates: list[dict[str, Any]] = []
    else:
        plan, p, o = p2._plan(session, task, model)
        total_p += p
        total_o += o
        status_line = next((line.strip().upper() for line in plan.splitlines() if line.strip()), "")
        if status_line.startswith("STATUS: NEED_USER_DECISION"):
            user_decision = True
            final = plan
        elif status_line.startswith("STATUS: ESCALATE") or not status_line.startswith("STATUS: IMPLEMENT"):
            escalation = True
            final = "ESCALATE_TO_CODEX: planning stage did not reach IMPLEMENT.\n" + plan

        targets = _resolve_targets(plan, task, discovered)
        for path in targets:
            p3._ensure_read(session, path)
        candidates = _build_candidates(targets, task, plan)

    if not escalation and not user_decision:
        if not targets:
            escalation = True
            final = "ESCALATE_TO_CODEX: no real target files could be resolved from the grounded plan."
        else:
            try:
                raw_action, p, o, _ = _request_action(session, task, plan, targets, candidates, model)
                total_p += p
                total_o += o
                edit = _validate_action(session, raw_action, candidates)
            except Exception as exc:
                escalation = True
                final = "ESCALATE_TO_CODEX: compact edit selection failed: " + f"{type(exc).__name__}: {exc}"

    if not escalation and not user_decision:
        if edit.get("kind") == "decision":
            user_decision = True
            final = "NEED_USER_DECISION: " + edit["message"]
        elif edit.get("kind") == "escalate":
            escalation = True
            final = "ESCALATE_TO_CODEX: " + edit["message"]
        elif edit.get("kind") == "edit":
            branch_note = session.preflight_and_branch()
            _apply_edit(session, edit)
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
                repair_candidates = _build_candidates(targets, task, plan + "\n" + review)
                raw_action, p, o, _ = _request_action(
                    session, task, plan, targets, repair_candidates, model, review_issue=review
                )
                total_p += p
                total_o += o
                repair = _validate_action(session, raw_action, repair_candidates)
                if repair.get("kind") != "edit":
                    raise RuntimeError("repair stage did not produce an edit")
                _apply_edit(session, repair)
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
            final = _deterministic_report(session, edit, diff_check, godot_check, review)

    if not final:
        escalation = True
        final = "ESCALATE_TO_CODEX: no reliable terminal result was produced."
    if "ESCALATE_TO_CODEX" in final.upper():
        escalation = True

    return {
        "runtime": "programmer-v4.3-fast-candidate-edit",
        "model": model,
        "elapsed_seconds": round(time.perf_counter() - started, 1),
        "base_branch": session.base_branch or _current_branch(),
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
        "diff": session.git_diff() if session.task_branch else "NO DIFF - TASK BRANCH NOT CREATED",
        "trace": session.tool_trace,
    }


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_3_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Fast candidate-edit programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.3 / FAST CANDIDATE EDIT")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {transport.CHAT_URL}")
    print("Pipeline: model preflight -> deterministic evidence -> plan -> one simple edit tool -> verify -> review.\n")

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
