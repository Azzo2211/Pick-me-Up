from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path
from typing import Any

import programmer_agent_v1 as p1
import programmer_agent_v3 as p3
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
NUM_CTX = 8192
MAX_MANIFEST_EDITS = 6

MANIFEST_SCHEMA: dict[str, Any] = {
    "type": "object",
    "required": ["status", "reason", "edits", "limitations"],
    "properties": {
        "status": {"type": "string", "enum": ["IMPLEMENT", "NEED_USER_DECISION", "ESCALATE"]},
        "reason": {"type": "string"},
        "edits": {
            "type": "array",
            "maxItems": MAX_MANIFEST_EDITS,
            "items": {
                "type": "object",
                "required": ["op", "path"],
                "properties": {
                    "op": {
                        "type": "string",
                        "enum": ["replace_text", "delete_line_containing"],
                    },
                    "path": {"type": "string"},
                    "old": {"type": "string"},
                    "new": {"type": "string"},
                    "expected_count": {"type": "integer", "minimum": 1, "maximum": 20},
                    "contains": {"type": "string"},
                },
            },
        },
        "limitations": {"type": "array", "items": {"type": "string"}},
    },
}

MANIFEST_TOOL = {
    "type": "function",
    "function": {
        "name": "submit_edit_manifest",
        "description": (
            "Submit the exact bounded edit manifest for the implementation. This is not an editor; "
            "the runtime validates every operation against the current repository before applying it."
        ),
        "parameters": MANIFEST_SCHEMA,
    },
}

MANIFEST_SYSTEM = """You are Agent A, first-line programmer for Riftward.
The task has already been researched. Submit the smallest safe edit manifest by CALLING submit_edit_manifest.
Do not answer with prose and do not print JSON as text when the function is available.

The USER TASK and actual CURRENT FILE CONTEXT are authoritative. The advisory plan may be wrong; correct it.
Allowed operations:
1. replace_text: use for a small exact replacement. `old` must occur exactly `expected_count` times in the current file.
2. delete_line_containing: use when one complete source line should be removed. Supply a short literal `contains` anchor that occurs on exactly one line in that file. Prefer this for long one-line data entries.

Rules:
- Status IMPLEMENT requires 1-6 edits.
- Never invent a property/function/list that is not shown by evidence.
- Do not edit unrelated files merely because the advisory plan listed them.
- Preserve future-support code when possible. For example, removing a Level 1 data entry does not require deleting a generic future activity handler.
- If the user explicitly accepts a remaining visual-asset limitation, implement the software fix and report that limitation instead of blocking.
""".strip()

REPAIR_SYSTEM = """You are Agent A repairing one rejected edit manifest.
CALL submit_edit_manifest with a corrected bounded manifest. Fix only the concrete runtime/review issue. Use exact current file evidence and unique anchors. Do not broaden scope.
""".strip()


def _manifest_from_tool_response(response: dict[str, Any]) -> dict[str, Any] | None:
    message = response.get("message") or {}
    calls = message.get("tool_calls") or []
    for call in calls:
        function = call.get("function") or {}
        if str(function.get("name") or "") != "submit_edit_manifest":
            continue
        args = function.get("arguments") or {}
        if isinstance(args, str):
            args = json.loads(args)
        if isinstance(args, dict):
            return args
    return None


def _structured_fallback(model: str, user_content: str, system: str) -> tuple[dict[str, Any], str, int, int]:
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": (
                    system
                    + "\nThe function-call channel was not used. Return the same manifest as a structured JSON object matching the supplied schema."
                ),
            },
            {"role": "user", "content": user_content},
        ],
        "format": MANIFEST_SCHEMA,
        "stream": False,
        "think": False,
        "options": {"num_ctx": NUM_CTX, "temperature": 0.0, "num_predict": 1400},
    }
    response = v5._request_ollama(payload)
    text = str((response.get("message") or {}).get("content") or "").strip()
    manifest = json.loads(text)
    return (
        manifest,
        "STRUCTURED_FALLBACK\n" + text,
        int(response.get("prompt_eval_count") or 0),
        int(response.get("eval_count") or 0),
    )


def _manifest_request(
    session: p1.ProgrammerSession,
    task: str,
    plan: str,
    target_paths: list[str],
    model: str,
    repair_issue: str = "",
) -> tuple[dict[str, Any], str, int, int]:
    for path in target_paths:
        p3._ensure_read(session, path)

    context = p3._file_context(target_paths, task, plan)
    evidence = p3.p2._evidence(task, session, budget=8500)
    issue = ("\n\nCONCRETE FAILURE/REVIEW ISSUE:\n" + repair_issue) if repair_issue else ""
    user_content = (
        "USER TASK:\n" + task
        + "\n\nADVISORY PLAN (may contain mistakes):\n" + plan
        + issue
        + "\n\nREPOSITORY EVIDENCE:\n" + evidence
        + "\n\nCURRENT FILE CONTEXT:\n" + context
        + "\n\nCall submit_edit_manifest now."
    )
    system = REPAIR_SYSTEM if repair_issue else MANIFEST_SYSTEM
    response = v5._request_ollama({
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user_content},
        ],
        "tools": [MANIFEST_TOOL],
        "stream": False,
        "think": False,
        "options": {"num_ctx": NUM_CTX, "temperature": 0.0, "num_predict": 1200},
    })
    prompt_tokens = int(response.get("prompt_eval_count") or 0)
    output_tokens = int(response.get("eval_count") or 0)
    manifest = _manifest_from_tool_response(response)
    if manifest is not None:
        return manifest, "TOOL_CALL\n" + json.dumps(manifest, ensure_ascii=False), prompt_tokens, output_tokens

    fallback, raw, p2, o2 = _structured_fallback(model, user_content, system)
    return fallback, raw, prompt_tokens + p2, output_tokens + o2


def _line_matches(text: str, contains: str) -> list[int]:
    return [index for index, line in enumerate(text.splitlines(keepends=True)) if contains in line]


def _validate_manifest(session: p1.ProgrammerSession, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    status = str(manifest.get("status") or "").strip().upper()
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
        op = str(item.get("op") or "")
        path = str(item.get("path") or "").replace("\\", "/").lstrip("/")
        if not path:
            raise ValueError(f"Edit {index}: path is required")
        rel, target = p1._editable_path(path, must_exist=True)
        p3._ensure_read(session, rel)
        current = target.read_text(encoding="utf-8", errors="replace")

        if op == "replace_text":
            old = str(item.get("old") or "")
            new = str(item.get("new") or "")
            expected = int(item.get("expected_count") or 1)
            if not old:
                raise ValueError(f"Edit {index}: replace_text requires non-empty old")
            actual = current.count(old)
            if actual != expected:
                raise ValueError(
                    f"Edit {index} exact text mismatch in {rel}: expected_count={expected}, actual_count={actual}"
                )
            validated.append({
                "op": op,
                "path": rel,
                "old": old,
                "new": new,
                "expected_count": expected,
            })
            continue

        if op == "delete_line_containing":
            contains = str(item.get("contains") or "")
            if not contains or "\n" in contains or "\r" in contains:
                raise ValueError(f"Edit {index}: delete_line_containing requires a one-line literal anchor")
            matches = _line_matches(current, contains)
            if len(matches) != 1:
                raise ValueError(
                    f"Edit {index}: anchor must match exactly one line in {rel}; matched {len(matches)} lines: {contains!r}"
                )
            lines = current.splitlines(keepends=True)
            old_line = lines[matches[0]]
            validated.append({
                "op": op,
                "path": rel,
                "contains": contains,
                "old": old_line,
                "new": "",
                "expected_count": 1,
            })
            continue

        raise ValueError(f"Edit {index}: unsupported op {op!r}")

    return validated


def _apply_manifest(session: p1.ProgrammerSession, manifest: dict[str, Any]) -> str:
    edits = _validate_manifest(session, manifest)
    results: list[str] = []
    for edit in edits:
        result = session.replace_text(
            path=edit["path"],
            old=edit["old"],
            new=edit["new"],
            expected_count=edit["expected_count"],
        )
        session.tool_trace.append({
            "round": "manifest-apply-v4",
            "tool": edit["op"],
            "arguments": {
                "path": edit["path"],
                "contains": edit.get("contains", ""),
                "expected_count": edit["expected_count"],
            },
            "result": result,
        })
        results.append(result)
    return "\n".join(results)


def run_programmer(task: str, model: str) -> dict[str, Any]:
    original_request = p3._manifest_request
    original_validate = p3._validate_manifest
    original_apply = p3._apply_manifest
    try:
        p3._manifest_request = _manifest_request
        p3._validate_manifest = _validate_manifest
        p3._apply_manifest = _apply_manifest
        result = p3.run_programmer(task, model)
    finally:
        p3._manifest_request = original_request
        p3._validate_manifest = original_validate
        p3._apply_manifest = original_apply

    result["runtime"] = "programmer-v4-tool-manifest"
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Tool-submitted manifest programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    task = args.task.strip()
    print("Riftward Agent A - PROGRAMMER v4 / TOOL EDIT MANIFEST")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print("Pipeline: evidence -> plan -> submit_edit_manifest tool -> deterministic apply -> verify -> review. No commit/push/merge.\n")
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
