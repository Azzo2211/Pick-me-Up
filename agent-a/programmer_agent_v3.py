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
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
ROOT = core.ROOT
NUM_CTX = 8192
MAX_MANIFEST_EDITS = 6
MAX_FILE_CONTEXT_CHARS = 24000

MANIFEST_SYSTEM = """You are Agent A, first-line programmer for Riftward.
Convert the user's task, repository evidence, advisory plan, and exact current file context into a SMALL STRUCTURED EDIT MANIFEST.

The USER TASK and actual file contents are authoritative. The advisory plan may be wrong: correct it instead of preserving a false assumption.
Prefer the smallest complete implementation. Do not add speculative abstractions or edit files that do not actually need a change.

Return ONLY valid JSON, no markdown, with this schema:
{
  "status": "IMPLEMENT" | "NEED_USER_DECISION" | "ESCALATE",
  "reason": "short grounded reason",
  "edits": [
    {
      "op": "replace_text",
      "path": "real/repository/path",
      "old": "exact current text copied from CURRENT FILE CONTEXT",
      "new": "replacement text",
      "expected_count": 1
    }
  ],
  "limitations": ["short limitation"]
}

Rules:
- For status IMPLEMENT, provide 1-6 edits.
- Use only replace_text in this version. Do not output a whole-file rewrite.
- old MUST be copied exactly from the supplied current file context, including tabs/newlines, and should be the smallest stable block that uniquely identifies the intended change.
- Never invent a list/property/function that the current file does not contain merely because the advisory plan mentions it.
- Preserve unrelated working systems, hero movement, save/progression behavior, and future code unless the user explicitly requests otherwise.
- If an asset visibly remains inconsistent but the user explicitly asked to implement the software part anyway, implement the software part and put the visual issue in limitations rather than blocking.
""".strip()

REPAIR_MANIFEST_SYSTEM = """You are Agent A repairing one failed or review-rejected structured edit.
Return ONLY valid JSON using the same manifest schema. Fix only the concrete error/review issue. Use exact text from CURRENT FILE CONTEXT. Do not broaden scope.
""".strip()


def _chat(model: str, messages: list[dict[str, Any]], num_predict: int) -> dict[str, Any]:
    return v5._request_ollama({
        "model": model,
        "messages": messages,
        "stream": False,
        "think": False,
        "options": {"num_ctx": NUM_CTX, "temperature": 0.05, "num_predict": num_predict},
    })


def _counts(response: dict[str, Any]) -> tuple[int, int]:
    return int(response.get("prompt_eval_count") or 0), int(response.get("eval_count") or 0)


def _text(response: dict[str, Any]) -> str:
    return str((response.get("message") or {}).get("content") or "").strip()


def _extract_json(text: str) -> dict[str, Any]:
    raw = text.strip()
    if raw.startswith("```"):
        raw = re.sub(r"^```(?:json)?\s*", "", raw, flags=re.IGNORECASE)
        raw = re.sub(r"\s*```$", "", raw)
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        start = raw.find("{")
        end = raw.rfind("}")
        if start < 0 or end <= start:
            raise ValueError("Model did not return a JSON object")
        value = json.loads(raw[start : end + 1])
    if not isinstance(value, dict):
        raise ValueError("Manifest root must be a JSON object")
    return value


def _exact_basename_matches(name: str) -> list[str]:
    results: list[str] = []
    for path in ROOT.rglob(name):
        if not path.is_file() or core._is_ignored(path):
            continue
        results.append(path.relative_to(ROOT).as_posix())
    return sorted(results)


def _task_named_paths(task: str) -> list[str]:
    found: list[str] = []
    pattern = r"(?i)([A-Za-z0-9_./\\-]+\.(?:gd|tscn|tres|md|json|cfg))"
    for match in re.finditer(pattern, task):
        token = match.group(1).replace("\\", "/").strip("`'\".,:;()[]{}")
        if not token:
            continue
        candidates: list[str]
        if "/" in token and (ROOT / token).is_file():
            candidates = [token]
        else:
            candidates = _exact_basename_matches(Path(token).name)
        if len(candidates) == 1 and candidates[0] not in found:
            found.append(candidates[0])
    return found


def _plan_paths(plan: str) -> list[str]:
    line = next((line for line in plan.splitlines() if line.strip().upper().startswith("FILES:")), "")
    if not line:
        return []
    value = line.split(":", 1)[1].strip()
    if not value or value.upper() == "NONE":
        return []
    results: list[str] = []
    for token in re.split(r"[,;]", value):
        rel = token.strip().strip("`'\"").replace("\\", "/")
        if not rel:
            continue
        if (ROOT / rel).is_file():
            path = rel
        else:
            matches = _exact_basename_matches(Path(rel).name)
            if len(matches) != 1:
                continue
            path = matches[0]
        if path not in results:
            results.append(path)
    return results


def _ensure_read(session: p1.ProgrammerSession, path: str) -> None:
    if path in session.read_paths:
        return
    result = session.read_file(path=path, start_line=1, end_line=220)
    session.tool_trace.append({
        "round": "manifest-preload",
        "tool": "read_file",
        "arguments": {"path": path, "start_line": 1, "end_line": 220},
        "result": result,
    })


def _keywords(task: str, plan: str) -> list[str]:
    stop = {
        "della", "delle", "degli", "dello", "anche", "questo", "questa", "quello", "quella",
        "with", "that", "this", "from", "into", "file", "files", "godot", "level", "base",
        "deve", "essere", "senza", "quando", "perche", "secondo", "attuale", "real", "current",
    }
    words = re.findall(r"[A-Za-z_][A-Za-z0-9_]{3,}", task + "\n" + plan)
    result: list[str] = []
    for word in words:
        folded = word.casefold()
        if folded in stop or folded in {x.casefold() for x in result}:
            continue
        result.append(word)
        if len(result) >= 14:
            break
    return result


def _focused_file_context(path: str, task: str, plan: str, budget: int) -> str:
    target = core._safe_path(path)
    text = target.read_text(encoding="utf-8", errors="replace")
    if len(text) <= budget:
        return f"=== CURRENT FILE {path} ===\n{text}"

    lines = text.splitlines(keepends=True)
    terms = [term.casefold() for term in _keywords(task, plan)]
    selected: set[int] = set()
    for idx, line in enumerate(lines):
        folded = line.casefold()
        if any(term in folded for term in terms):
            for pos in range(max(0, idx - 8), min(len(lines), idx + 9)):
                selected.add(pos)
    # Always preserve imports/class header and function boundaries near the top.
    selected.update(range(0, min(28, len(lines))))
    if not selected:
        selected.update(range(0, min(120, len(lines))))

    blocks: list[str] = []
    current: list[str] = []
    previous = -2
    for idx in sorted(selected):
        if idx != previous + 1 and current:
            blocks.append("".join(current))
            current = []
        current.append(lines[idx])
        previous = idx
    if current:
        blocks.append("".join(current))

    joined = "\n... [unrelated lines omitted] ...\n".join(blocks)
    if len(joined) > budget:
        joined = joined[:budget] + "\n... [context truncated]"
    return f"=== CURRENT FILE {path} (focused excerpts) ===\n{joined}"


def _file_context(paths: list[str], task: str, plan: str) -> str:
    unique = list(dict.fromkeys(paths))[:6]
    if not unique:
        return "NO TARGET FILE CONTEXT"
    per_file = max(4500, MAX_FILE_CONTEXT_CHARS // len(unique))
    chunks = [_focused_file_context(path, task, plan, per_file) for path in unique]
    text = "\n\n".join(chunks)
    return text[:MAX_FILE_CONTEXT_CHARS]


def _manifest_request(
    session: p1.ProgrammerSession,
    task: str,
    plan: str,
    target_paths: list[str],
    model: str,
    repair_issue: str = "",
) -> tuple[dict[str, Any], str, int, int]:
    for path in target_paths:
        _ensure_read(session, path)
    context = _file_context(target_paths, task, plan)
    evidence = p2._evidence(task, session, budget=8500)
    issue = ("\n\nCONCRETE FAILURE/REVIEW ISSUE:\n" + repair_issue) if repair_issue else ""
    response = _chat(
        model,
        [
            {"role": "system", "content": REPAIR_MANIFEST_SYSTEM if repair_issue else MANIFEST_SYSTEM},
            {
                "role": "user",
                "content": (
                    "USER TASK:\n" + task
                    + "\n\nADVISORY PLAN (may contain mistakes):\n" + plan
                    + issue
                    + "\n\nREPOSITORY EVIDENCE:\n" + evidence
                    + "\n\nCURRENT FILE CONTEXT (exact repository text; copy old blocks from here):\n" + context
                ),
            },
        ],
        1700,
    )
    p, o = _counts(response)
    raw = _text(response)
    return _extract_json(raw), raw, p, o


def _manifest_status(manifest: dict[str, Any]) -> str:
    return str(manifest.get("status") or "").strip().upper()


def _validate_manifest(session: p1.ProgrammerSession, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    status = _manifest_status(manifest)
    if status != "IMPLEMENT":
        return []
    edits = manifest.get("edits")
    if not isinstance(edits, list) or not edits:
        raise ValueError("IMPLEMENT manifest must contain at least one edit")
    if len(edits) > MAX_MANIFEST_EDITS:
        raise ValueError(f"Manifest exceeds edit limit ({MAX_MANIFEST_EDITS})")

    validated: list[dict[str, Any]] = []
    for index, item in enumerate(edits, 1):
        if not isinstance(item, dict):
            raise ValueError(f"Edit {index} is not an object")
        if str(item.get("op") or "") != "replace_text":
            raise ValueError(f"Edit {index}: only replace_text is allowed")
        path = str(item.get("path") or "").replace("\\", "/").lstrip("/")
        old = str(item.get("old") or "")
        new = str(item.get("new") or "")
        expected = int(item.get("expected_count") or 1)
        if not path or not old:
            raise ValueError(f"Edit {index}: path and old are required")
        rel, target = p1._editable_path(path, must_exist=True)
        _ensure_read(session, rel)
        current = target.read_text(encoding="utf-8", errors="replace")
        actual = current.count(old)
        if actual != expected:
            raise ValueError(
                f"Edit {index} exact text mismatch in {rel}: expected_count={expected}, actual_count={actual}"
            )
        validated.append({"path": rel, "old": old, "new": new, "expected_count": expected})
    return validated


def _apply_manifest(session: p1.ProgrammerSession, manifest: dict[str, Any]) -> str:
    edits = _validate_manifest(session, manifest)
    results: list[str] = []
    for edit in edits:
        result = session.replace_text(**edit)
        session.tool_trace.append({
            "round": "manifest-apply",
            "tool": "replace_text",
            "arguments": {
                "path": edit["path"],
                "old": edit["old"],
                "new": edit["new"],
                "expected_count": edit["expected_count"],
            },
            "result": result,
        })
        results.append(result)
    return "\n".join(results)


def _manifest_summary(manifest: dict[str, Any]) -> str:
    limitations = manifest.get("limitations")
    if isinstance(limitations, list):
        lim = "; ".join(str(x) for x in limitations if str(x).strip()) or "NONE"
    else:
        lim = str(limitations or "NONE")
    return f"Reason: {manifest.get('reason', '')}\nLimitations: {lim}"


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
    plan = ""
    manifest_raw = ""
    manifest: dict[str, Any] = {}
    diff_check = "NOT RUN"
    godot_check = "NOT RUN"
    final = ""
    escalation = False
    user_decision = False

    bootstrap_reads = p2._bootstrap(session)

    # Deterministic discovery and exact resolution of filenames named by the user.
    discovery = session.list_files(path="godot/scripts", contains=".gd", limit=6)
    session.tool_trace.append({
        "round": "deterministic-discovery",
        "tool": "list_files",
        "arguments": {"path": "godot/scripts", "contains": ".gd", "limit": 6},
        "result": discovery,
    })
    named_paths = _task_named_paths(task)
    for path in named_paths:
        _ensure_read(session, path)

    p, o = p2._research(session, task, model)
    total_p += p
    total_o += o
    auto_visual_added, auto_visual_failures = p2._auto_visual(session, model)

    if not any(path.endswith(".gd") for path in session.read_paths):
        escalation = True
        final = "ESCALATE_TO_CODEX: no relevant Godot implementation file was read."

    if not escalation:
        plan, p, o = p2._plan(session, task, model)
        total_p += p
        total_o += o
        status_line = next((line.strip().upper() for line in plan.splitlines() if line.strip()), "")
        if status_line.startswith("STATUS: NEED_USER_DECISION"):
            user_decision = True
            final = plan
        elif status_line.startswith("STATUS: ESCALATE"):
            escalation = True
            final = "ESCALATE_TO_CODEX: planning stage found a concrete blocker.\n" + plan
        elif not status_line.startswith("STATUS: IMPLEMENT"):
            escalation = True
            final = "ESCALATE_TO_CODEX: planning stage did not return a valid implementation status.\n" + plan

    target_paths = list(dict.fromkeys(_plan_paths(plan) + named_paths))[:6]

    if not escalation and not user_decision:
        if not target_paths:
            escalation = True
            final = "ESCALATE_TO_CODEX: no real target file could be resolved from task/research/plan."
        else:
            first_error = ""
            try:
                manifest, manifest_raw, p, o = _manifest_request(session, task, plan, target_paths, model)
                total_p += p
                total_o += o
                status = _manifest_status(manifest)
                if status == "NEED_USER_DECISION":
                    user_decision = True
                    final = "NEED_USER_DECISION: " + str(manifest.get("reason") or "Product decision required.")
                elif status == "ESCALATE":
                    escalation = True
                    final = "ESCALATE_TO_CODEX: " + str(manifest.get("reason") or "Manifest stage found a blocker.")
                elif status != "IMPLEMENT":
                    raise ValueError("Manifest status must be IMPLEMENT, NEED_USER_DECISION or ESCALATE")
                else:
                    _apply_manifest(session, manifest)
            except Exception as exc:
                first_error = f"{type(exc).__name__}: {exc}"

            if first_error and not escalation and not user_decision:
                session.restore_all()
                try:
                    manifest, manifest_raw, p, o = _manifest_request(
                        session,
                        task,
                        plan,
                        target_paths,
                        model,
                        repair_issue=(
                            "First edit manifest could not be applied. Runtime error: " + first_error
                            + ". Generate corrected exact replacements from the current file context."
                        ),
                    )
                    total_p += p
                    total_o += o
                    status = _manifest_status(manifest)
                    if status == "IMPLEMENT":
                        _apply_manifest(session, manifest)
                    elif status == "NEED_USER_DECISION":
                        user_decision = True
                        final = "NEED_USER_DECISION: " + str(manifest.get("reason") or "Product decision required.")
                    else:
                        escalation = True
                        final = "ESCALATE_TO_CODEX: " + str(manifest.get("reason") or first_error)
                except Exception as exc:
                    escalation = True
                    final = (
                        "ESCALATE_TO_CODEX: structured edit manifest failed twice. "
                        + first_error + " | retry: " + f"{type(exc).__name__}: {exc}"
                    )

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
                repair_manifest, repair_raw, p, o = _manifest_request(
                    session,
                    task,
                    plan,
                    target_paths,
                    model,
                    repair_issue=review + "\nCurrent diff:\n" + p1._cap(session.git_diff(), 9000),
                )
                total_p += p
                total_o += o
                if _manifest_status(repair_manifest) == "IMPLEMENT":
                    _apply_manifest(session, repair_manifest)
                    manifest = repair_manifest
                    manifest_raw = repair_raw
                else:
                    raise ValueError("repair manifest did not return IMPLEMENT")
            except Exception as exc:
                escalation = True
                final = "ESCALATE_TO_CODEX: review repair manifest failed: " + f"{type(exc).__name__}: {exc}"

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
            report, p, o = p2._final_report(session, task, plan, review, diff_check, godot_check, model)
            total_p += p
            total_o += o
            final = report + "\n" + _manifest_summary(manifest)

    if not session.changed_paths and not user_decision and not escalation:
        escalation = True
        final = "ESCALATE_TO_CODEX: manifest workflow completed without a real repository mutation."
    if not final:
        escalation = True
        final = "ESCALATE_TO_CODEX: no reliable final result was produced."
    if "ESCALATE_TO_CODEX" in final.upper():
        escalation = True

    return {
        "runtime": "programmer-v3-structured-manifest",
        "model": model,
        "elapsed_seconds": round(time.perf_counter() - started, 1),
        "base_branch": session.base_branch,
        "task_branch": session.task_branch,
        "branch_note": branch_note,
        "bootstrap_reads": bootstrap_reads,
        "named_paths": named_paths,
        "target_paths": target_paths,
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
        "manifest": manifest,
        "manifest_raw": manifest_raw,
        "escalate_to_codex": escalation,
        "needs_user_decision": user_decision,
        "final": final,
        "diff": session.git_diff(),
        "trace": session.tool_trace,
    }


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v3_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Structured-manifest programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    task = args.task.strip()
    print("Riftward Agent A - PROGRAMMER v3 / STRUCTURED EDIT MANIFEST")
    print(f"Repository: {ROOT}")
    print(f"Model: {args.model}")
    print("Pipeline: evidence -> plan -> exact JSON edit manifest -> apply -> verify -> review. No commit/push/merge.\n")
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
    print("\n========== EDIT MANIFEST ==========")
    print(json.dumps(result["manifest"], ensure_ascii=False, indent=2) if result["manifest"] else "NO MANIFEST")
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
    print("Named paths: " + (", ".join(result["named_paths"]) or "NONE"))
    print("Target paths: " + (", ".join(result["target_paths"]) or "NONE"))
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
