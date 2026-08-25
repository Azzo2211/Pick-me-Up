from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unicodedata
from pathlib import Path
from typing import Any

import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
ROOT = core.ROOT
MAX_CHANGED_FILES = 8
MAX_MUTATIONS = 20
MAX_WRITE_BYTES = 350_000
MAX_DIFF_CHARS = 28_000

PROTECTED_EXACT = {
    "AGENTS.md",
    "docs/AGENT_A.md",
    "Avvia_Agente_A_Programmatore.cmd",
    "Avvia_Agente_A_ReadOnly.cmd",
}
PROTECTED_PREFIXES = ("agent-a/", ".git/")
ALLOWED_EDIT_PREFIXES = ("godot/", "docs/")
DESIGN_DOCS = {
    "docs/GAME_VISION.md",
    "docs/GAME_SYSTEMS.md",
    "docs/ART_DIRECTION.md",
    "docs/CURRENT_STATE.md",
}
BOOTSTRAP_DOCS = [
    "AGENTS.md",
    "docs/AGENT_A.md",
    "docs/DEVELOPMENT_RULES.md",
]

SYSTEM_PROMPT = """You are Agent A, the first-line independent Senior Game Engineer for Riftward: The Last Ascent.
You are not an analyst-only assistant. Your default job is to SOLVE the user's programming task in the real local Godot project.
Codex is escalation: use ESCALATE_TO_CODEX only when the task remains technically unsafe/unsolved after serious repository inspection and at most one repair cycle.

Operating rules:
- Godot under godot/ is the active implementation. Historical web code is reference only.
- Inspect before editing. Read the actual target file before changing it.
- Read relevant design/current-state docs before changing product behavior.
- The newest user task outranks older docs/code; do not invent missing product decisions.
- Preserve working architecture; prefer the smallest complete change.
- Never modify AGENTS.md, docs/AGENT_A.md, the Agent A runtime, launchers, or .git.
- You have NO arbitrary shell tool. Use only the provided repository/edit/Godot tools.
- Never claim tests passed unless a tool result says they passed.
- Do not invent collisions, nodes, files, functions, assets, or systems.
- After editing, inspect git_diff and run relevant checks/tests when available.
- Do not commit, push, merge, reset, clean, or touch main. The runtime creates a dedicated task branch before you can write.

Completion behavior:
- If the user must decide a genuine unresolved product choice, finish with NEED_USER_DECISION: <brief question> and do not leave speculative edits.
- If you cannot safely complete the task, finish with ESCALATE_TO_CODEX: <specific blocker and evidence>.
- Otherwise implement the task. Do not merely describe what you would do.
""".strip()

REVIEW_SYSTEM = """You are the independent verification pass for Agent A's completed code change.
Review only the supplied task, git diff and verification outputs. Be strict but practical.
Check for factual/design drift, unrelated rewrites, syntax-risk, missing adjacent updates, save/progression regressions, and whether the change actually solves the task.
A missing local Godot executable is a verification limitation, not automatically a code failure.
Output exactly one first line:
REVIEW: PASS
REVIEW: NEEDS_FIX
REVIEW: ESCALATE
Then a short REASON: paragraph with concrete evidence. Do not propose broad rewrites.
""".strip()

TOOLS = v5.TOOLS + [
    {
        "type": "function",
        "function": {
            "name": "git_status",
            "description": "Show current branch and working-tree status. Safe read-only Git inspection.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "git_diff",
            "description": "Show the current uncommitted diff, optionally for one repository path. Read-only.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Optional repository-relative file path."}
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "replace_text",
            "description": "Safely edit an EXISTING text file by replacing an exact old string with a new string. The file must have been read first. No regex.",
            "parameters": {
                "type": "object",
                "required": ["path", "old", "new"],
                "properties": {
                    "path": {"type": "string"},
                    "old": {"type": "string", "description": "Exact existing text to replace."},
                    "new": {"type": "string", "description": "Replacement text."},
                    "expected_count": {"type": "integer", "description": "Expected exact occurrence count, default 1."},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "create_file",
            "description": "Create a NEW UTF-8 text file under godot/ or docs/. Cannot overwrite an existing file.",
            "parameters": {
                "type": "object",
                "required": ["path", "content"],
                "properties": {
                    "path": {"type": "string"},
                    "content": {"type": "string"},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "restore_file",
            "description": "Undo this Agent A session's own edits to one file. Cannot affect pre-existing user changes.",
            "parameters": {
                "type": "object",
                "required": ["path"],
                "properties": {"path": {"type": "string"}},
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_godot_tests",
            "description": "List available scripts under godot/tests. Read-only.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_godot_check",
            "description": "Run the whitelisted headless Godot project parse/editor smoke check. No arbitrary command execution.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_godot_test",
            "description": "Run one existing GDScript test under res://tests/ using headless Godot. Only test scripts inside godot/tests are permitted.",
            "parameters": {
                "type": "object",
                "required": ["script"],
                "properties": {
                    "script": {"type": "string", "description": "Godot path like res://tests/test_something.gd"}
                },
            },
        },
    },
]


def _run_git(args: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        errors="replace",
        timeout=timeout,
        shell=False,
    )


def _git_output(args: list[str], timeout: int = 30) -> str:
    cp = _run_git(args, timeout=timeout)
    text = (cp.stdout + ("\n" + cp.stderr if cp.stderr else "")).strip()
    if cp.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed ({cp.returncode}): {text}")
    return text


def _normalize_rel(path: str) -> str:
    return (path or "").replace("\\", "/").lstrip("/")


def _editable_path(path: str, must_exist: bool) -> tuple[str, Path]:
    rel = _normalize_rel(path)
    if not rel:
        raise ValueError("path is required")
    if rel in PROTECTED_EXACT or any(rel.startswith(prefix) for prefix in PROTECTED_PREFIXES):
        raise PermissionError(f"Protected path cannot be edited by Agent A: {rel}")
    if not any(rel.startswith(prefix) for prefix in ALLOWED_EDIT_PREFIXES):
        raise PermissionError("Programmer v1 may edit only godot/ and docs/ paths")
    target = core._safe_path(rel, must_exist=must_exist)
    return rel, target


def _task_slug(task: str) -> str:
    plain = unicodedata.normalize("NFKD", task).encode("ascii", "ignore").decode("ascii").lower()
    words = [w for w in re.findall(r"[a-z0-9]+", plain) if len(w) >= 3][:4]
    stem = "-".join(words) or "task"
    stamp = time.strftime("%Y%m%d-%H%M%S")
    return f"agent-a/{stem[:36]}-{stamp}"


def _find_godot() -> str | None:
    env = os.environ.get("GODOT_EXE", "").strip()
    if env and Path(env).is_file():
        return env
    for name in ("godot", "godot4", "Godot_v4.7-stable_win64.exe", "Godot_v4.7-stable_win64_console.exe"):
        found = shutil.which(name)
        if found:
            return found
    return None


def _cap(text: str, limit: int = MAX_DIFF_CHARS) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n... [TRUNCATED {len(text) - limit} CHARS]"


class ProgrammerSession:
    def __init__(self, task: str):
        self.task = task
        self.base_branch = ""
        self.task_branch = ""
        self.read_paths: set[str] = set()
        self.discovery_count = 0
        self.snapshots: dict[str, str | None] = {}
        self.changed_paths: set[str] = set()
        self.mutations = 0
        self.tool_trace: list[dict[str, Any]] = []
        self.godot_exe = _find_godot()

    def preflight_and_branch(self) -> str:
        self.base_branch = _git_output(["branch", "--show-current"]).strip()
        if not self.base_branch:
            raise RuntimeError("Detached HEAD is not allowed")

        raw = _git_output(["status", "--porcelain=v1", "--untracked-files=all"])
        tracked_dirty = [line for line in raw.splitlines() if line and not line.startswith("??")]
        untracked = [line[3:] for line in raw.splitlines() if line.startswith("??")]
        if tracked_dirty:
            raise RuntimeError(
                "Tracked working-tree changes already exist. Agent A refuses to edit over them:\n"
                + "\n".join(tracked_dirty)
            )

        self.task_branch = _task_slug(self.task)
        _git_output(["switch", "-c", self.task_branch])
        note = f"Created task branch {self.task_branch} from {self.base_branch}."
        if untracked:
            note += " Pre-existing untracked files were left untouched: " + ", ".join(untracked[:12])
        return note

    def bootstrap_packet(self) -> str:
        chunks: list[str] = []
        for path in BOOTSTRAP_DOCS:
            try:
                content = core.read_file(path, 1, 220)
                self.read_paths.add(path)
                chunks.append(content)
            except Exception as exc:
                chunks.append(f"BOOTSTRAP ERROR {path}: {type(exc).__name__}: {exc}")
        return "\n\n--- MANDATORY REPOSITORY RULES ---\n\n".join(chunks)

    def _write_gate(self, path: str | None = None, existing: bool = False) -> str:
        missing: list[str] = []
        if not (self.read_paths & DESIGN_DOCS):
            missing.append("read at least one relevant design/current-state document")
        if not any(p.endswith(".gd") for p in self.read_paths):
            missing.append("read at least one relevant Godot .gd implementation file")
        if self.discovery_count < 1:
            missing.append("perform at least one repository search/list operation")
        if existing and path and path not in self.read_paths:
            missing.append(f"read the exact target file first: {path}")
        return "; ".join(missing)

    def _snapshot(self, rel: str, target: Path) -> None:
        if rel in self.snapshots:
            return
        if target.exists():
            self.snapshots[rel] = target.read_text(encoding="utf-8", errors="replace")
        else:
            self.snapshots[rel] = None

    def _check_mutation_budget(self, rel: str) -> None:
        if self.mutations >= MAX_MUTATIONS:
            raise RuntimeError(f"Mutation limit reached ({MAX_MUTATIONS})")
        projected = set(self.changed_paths)
        projected.add(rel)
        if len(projected) > MAX_CHANGED_FILES:
            raise RuntimeError(f"Changed-file limit reached ({MAX_CHANGED_FILES})")

    def list_files(self, **args: Any) -> str:
        result = core.list_files(**args)
        self.discovery_count += 1
        return result

    def search_text(self, **args: Any) -> str:
        result = core.search_text(**args)
        self.discovery_count += 1
        return result

    def read_file(self, **args: Any) -> str:
        result = core.read_file(**args)
        self.read_paths.add(_normalize_rel(str(args.get("path") or "")))
        return result

    def inspect_image(self, **args: Any) -> str:
        return v5.inspect_image(model=MODEL, num_ctx=8192, **args)

    def git_status(self) -> str:
        branch = _git_output(["branch", "--show-current"])
        status = _git_output(["status", "--short", "--untracked-files=all"])
        return f"BRANCH {branch.strip()}\n{status or 'WORKTREE CLEAN'}"

    def git_diff(self, path: str = "") -> str:
        args = ["diff", "--no-ext-diff", "--unified=3"]
        rel = _normalize_rel(path)
        if rel:
            core._safe_path(rel, must_exist=False)
            args.extend(["--", rel])
        out = _git_output(args)
        return _cap(out or "NO UNCOMMITTED DIFF")

    def replace_text(self, path: str, old: str, new: str, expected_count: int = 1) -> str:
        rel, target = _editable_path(path, must_exist=True)
        gap = self._write_gate(rel, existing=True)
        if gap:
            raise PermissionError("WRITE GATE BLOCKED: " + gap)
        if not old:
            raise ValueError("old text must be non-empty")
        expected = max(1, min(int(expected_count or 1), 20))
        if not core._looks_text(target):
            raise ValueError(f"Not an editable UTF-8 text file: {rel}")
        text = target.read_text(encoding="utf-8", errors="replace")
        actual = text.count(old)
        if actual != expected:
            raise ValueError(f"Expected {expected} exact occurrence(s), found {actual} in {rel}")
        updated = text.replace(old, new)
        if len(updated.encode("utf-8")) > MAX_WRITE_BYTES:
            raise ValueError("Resulting file exceeds programmer write limit")
        self._check_mutation_budget(rel)
        self._snapshot(rel, target)
        target.write_text(updated, encoding="utf-8")
        self.changed_paths.add(rel)
        self.mutations += 1
        return f"UPDATED {rel}: replaced {actual} exact occurrence(s)."

    def create_file(self, path: str, content: str) -> str:
        rel, target = _editable_path(path, must_exist=False)
        gap = self._write_gate(existing=False)
        if gap:
            raise PermissionError("WRITE GATE BLOCKED: " + gap)
        if target.exists():
            raise FileExistsError(f"Refusing to overwrite existing file: {rel}")
        if len(content.encode("utf-8")) > MAX_WRITE_BYTES:
            raise ValueError("New file exceeds programmer write limit")
        self._check_mutation_budget(rel)
        self._snapshot(rel, target)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        self.changed_paths.add(rel)
        self.mutations += 1
        return f"CREATED {rel}"

    def restore_file(self, path: str) -> str:
        rel = _normalize_rel(path)
        if rel not in self.snapshots:
            raise PermissionError("Can restore only files modified by this Agent A session")
        _, target = _editable_path(rel, must_exist=False)
        original = self.snapshots[rel]
        if original is None:
            if target.exists():
                target.unlink()
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(original, encoding="utf-8")
        self.changed_paths.discard(rel)
        return f"RESTORED {rel} to pre-session state"

    def restore_all(self) -> None:
        for rel in list(self.snapshots.keys()):
            try:
                self.restore_file(rel)
            except Exception:
                pass

    def list_godot_tests(self) -> str:
        tests = ROOT / "godot" / "tests"
        if not tests.is_dir():
            return "NO godot/tests DIRECTORY"
        items = [p.relative_to(ROOT / "godot").as_posix() for p in sorted(tests.rglob("*.gd"))]
        return "\n".join("res://" + item for item in items) if items else "NO GDSCRIPT TESTS FOUND"

    def run_godot_check(self) -> str:
        if not self.godot_exe:
            return "GODOT_CHECK_UNAVAILABLE: Godot executable not found in PATH. Set GODOT_EXE to the Godot executable path."
        command = [
            self.godot_exe,
            "--headless",
            "--editor",
            "--quit",
            "--path",
            str(ROOT / "godot"),
        ]
        try:
            cp = subprocess.run(command, capture_output=True, text=True, errors="replace", timeout=90, shell=False)
        except subprocess.TimeoutExpired:
            return "GODOT_CHECK_TIMEOUT after 90 seconds"
        text = _cap((cp.stdout + ("\n" + cp.stderr if cp.stderr else "")).strip(), 16_000)
        return f"GODOT_CHECK_EXIT={cp.returncode}\n{text or '[no output]'}"

    def run_godot_test(self, script: str) -> str:
        godot_path = (script or "").replace("\\", "/")
        if not godot_path.startswith("res://tests/") or not godot_path.endswith(".gd") or ".." in godot_path:
            raise PermissionError("Only existing res://tests/*.gd scripts are allowed")
        local = ROOT / "godot" / godot_path.removeprefix("res://")
        if not local.is_file():
            raise FileNotFoundError(f"Godot test script not found: {godot_path}")
        if not self.godot_exe:
            return "GODOT_TEST_UNAVAILABLE: Godot executable not found in PATH. Set GODOT_EXE."
        command = [
            self.godot_exe,
            "--headless",
            "--path",
            str(ROOT / "godot"),
            "--script",
            godot_path,
        ]
        try:
            cp = subprocess.run(command, capture_output=True, text=True, errors="replace", timeout=120, shell=False)
        except subprocess.TimeoutExpired:
            return "GODOT_TEST_TIMEOUT after 120 seconds"
        text = _cap((cp.stdout + ("\n" + cp.stderr if cp.stderr else "")).strip(), 16_000)
        return f"GODOT_TEST_EXIT={cp.returncode}\n{text or '[no output]'}"

    def git_diff_check(self) -> str:
        cp = _run_git(["diff", "--check"])
        text = (cp.stdout + ("\n" + cp.stderr if cp.stderr else "")).strip()
        return f"GIT_DIFF_CHECK_EXIT={cp.returncode}\n{text or 'OK'}"

    def execute_tool(self, name: str, args: dict[str, Any]) -> str:
        table = {
            "list_files": self.list_files,
            "read_file": self.read_file,
            "search_text": self.search_text,
            "inspect_image": self.inspect_image,
            "git_status": self.git_status,
            "git_diff": self.git_diff,
            "replace_text": self.replace_text,
            "create_file": self.create_file,
            "restore_file": self.restore_file,
            "list_godot_tests": self.list_godot_tests,
            "run_godot_check": self.run_godot_check,
            "run_godot_test": self.run_godot_test,
        }
        fn = table.get(name)
        if fn is None:
            return f"ERROR: unknown or forbidden tool {name}"
        try:
            return fn(**args)
        except Exception as exc:
            return f"ERROR: {type(exc).__name__}: {exc}"


def _chat_with_tools(model: str, messages: list[dict[str, Any]], num_ctx: int = 8192, num_predict: int = 850) -> dict[str, Any]:
    return v5._request_ollama({
        "model": model,
        "messages": messages,
        "tools": TOOLS,
        "stream": False,
        "think": False,
        "options": {"num_ctx": num_ctx, "temperature": 0.1, "num_predict": num_predict},
    })


def _history_message(message: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {"role": "assistant", "content": message.get("content", "")}
    if message.get("tool_calls"):
        out["tool_calls"] = message["tool_calls"]
    return out


def _tool_loop(
    session: ProgrammerSession,
    messages: list[dict[str, Any]],
    model: str,
    max_rounds: int,
) -> tuple[str, int, int]:
    total_prompt = 0
    total_output = 0
    final_text = ""

    for round_no in range(1, max_rounds + 1):
        response = _chat_with_tools(model, messages)
        total_prompt += int(response.get("prompt_eval_count") or 0)
        total_output += int(response.get("eval_count") or 0)
        message = response.get("message") or {}
        messages.append(_history_message(message))
        calls = message.get("tool_calls") or []

        if calls:
            for call in calls:
                fn = call.get("function") or {}
                name = str(fn.get("name") or "")
                args = fn.get("arguments") or {}
                if not isinstance(args, dict):
                    args = {}
                print(f"[A programmer] {name} {json.dumps(args, ensure_ascii=False)}")
                result = session.execute_tool(name, args)
                session.tool_trace.append({"round": round_no, "tool": name, "arguments": args, "result": result})
                messages.append({"role": "tool", "tool_name": name, "content": result})
            continue

        final_text = str(message.get("content") or "").strip()
        if "NEED_USER_DECISION" in final_text:
            if session.changed_paths:
                session.restore_all()
                final_text += "\nRuntime safety: speculative session edits were restored."
            break
        if "ESCALATE_TO_CODEX" in final_text:
            break
        if not session.changed_paths:
            messages.append({
                "role": "user",
                "content": (
                    "You have not implemented any change. If the task is clear, continue using tools and edit the real files. "
                    "If it truly cannot be solved safely, return ESCALATE_TO_CODEX with the concrete blocker."
                ),
            })
            final_text = ""
            continue
        break

    return final_text, total_prompt, total_output


def _review(model: str, task: str, diff: str, diff_check: str, godot_check: str) -> tuple[str, int, int]:
    response = v5.chat_no_tools(
        model,
        [
            {"role": "system", "content": REVIEW_SYSTEM},
            {
                "role": "user",
                "content": (
                    "TASK:\n" + task
                    + "\n\nGIT DIFF:\n" + _cap(diff, 22_000)
                    + "\n\nGIT DIFF CHECK:\n" + diff_check
                    + "\n\nGODOT PROJECT CHECK:\n" + godot_check
                ),
            },
        ],
        8192,
        num_predict=650,
    )
    text = str((response.get("message") or {}).get("content") or "").strip()
    return text, int(response.get("prompt_eval_count") or 0), int(response.get("eval_count") or 0)


def _review_status(text: str) -> str:
    first = next((line.strip().upper() for line in text.splitlines() if line.strip()), "")
    if first == "REVIEW: PASS":
        return "PASS"
    if first == "REVIEW: NEEDS_FIX":
        return "NEEDS_FIX"
    if first == "REVIEW: ESCALATE":
        return "ESCALATE"
    return "UNKNOWN"


def run_programmer(task: str, model: str, max_rounds: int = 14) -> dict[str, Any]:
    started = time.perf_counter()
    session = ProgrammerSession(task)
    branch_note = session.preflight_and_branch()
    bootstrap = session.bootstrap_packet()

    messages: list[dict[str, Any]] = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                "USER TASK:\n" + task
                + "\n\nRUNTIME STATE:\n" + branch_note
                + "\n\nMANDATORY RULE EVIDENCE ALREADY READ:\n" + bootstrap
                + "\n\nNow inspect the relevant design docs and current Godot implementation, then implement the task."
            ),
        },
    ]

    final_text, prompt_tokens, output_tokens = _tool_loop(session, messages, model, max_rounds)
    escalation = "ESCALATE_TO_CODEX" in final_text
    user_decision = "NEED_USER_DECISION" in final_text
    reviews: list[str] = []
    diff_check = "NOT RUN"
    godot_check = "NOT RUN"
    diff = session.git_diff()

    if session.changed_paths and not user_decision:
        diff_check = session.git_diff_check()
        godot_check = session.run_godot_check()
        review, p, o = _review(model, task, diff, diff_check, godot_check)
        prompt_tokens += p
        output_tokens += o
        reviews.append(review)
        status = _review_status(review)

        if status == "NEEDS_FIX" and not escalation:
            repair_messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": (
                        "Original task:\n" + task
                        + "\n\nIndependent review found issues:\n" + review
                        + "\n\nCurrent diff:\n" + _cap(diff, 18_000)
                        + "\n\nRepair ONLY the concrete review issues. Inspect files as needed, edit, then stop."
                    ),
                },
            ]
            repair_text, p2, o2 = _tool_loop(session, repair_messages, model, max_rounds=6)
            prompt_tokens += p2
            output_tokens += o2
            if "ESCALATE_TO_CODEX" in repair_text:
                escalation = True
                final_text = repair_text
            diff = session.git_diff()
            diff_check = session.git_diff_check()
            godot_check = session.run_godot_check()
            review2, p3, o3 = _review(model, task, diff, diff_check, godot_check)
            prompt_tokens += p3
            output_tokens += o3
            reviews.append(review2)
            status = _review_status(review2)

        if status not in {"PASS"} and not user_decision:
            escalation = True
            if "ESCALATE_TO_CODEX" not in final_text:
                final_text = (
                    "ESCALATE_TO_CODEX: Agent A's independent verification did not reach PASS after the allowed repair cycle. "
                    "Keep this task branch and diff for Codex/Sol inspection."
                )

    elapsed = round(time.perf_counter() - started, 1)
    result = {
        "runtime": "programmer-v1-controlled",
        "model": model,
        "elapsed_seconds": elapsed,
        "base_branch": session.base_branch,
        "task_branch": session.task_branch,
        "changed_files": sorted(session.changed_paths),
        "mutations": session.mutations,
        "prompt_tokens_total": prompt_tokens,
        "output_tokens_total": output_tokens,
        "diff_check": diff_check,
        "godot_check": godot_check,
        "reviews": reviews,
        "escalate_to_codex": escalation,
        "needs_user_decision": user_decision,
        "final": final_text or "ESCALATE_TO_CODEX: no reliable final result was produced.",
        "diff": diff,
        "trace": session.tool_trace,
    }
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v1_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Controlled local programmer mode for Riftward Agent A.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--max-rounds", type=int, default=14)
    args = parser.parse_args()

    task = args.task.strip()
    print("Riftward Agent A - PROGRAMMER v1 / CONTROLLED WRITES")
    print(f"Repository: {ROOT}")
    print(f"Model: {args.model}")
    print("Edits real Godot/docs files on a dedicated agent-a task branch. No commit/push/merge.\n")
    if not task:
        try:
            task = input("Descrivi il lavoro da fare ad Agent A:\n> ").strip()
        except EOFError:
            task = ""
    if not task:
        print("Nessun task inserito. Uscita senza modifiche.")
        return 2

    try:
        result = run_programmer(task, args.model, max_rounds=max(4, args.max_rounds))
    except Exception as exc:
        print(f"\nPREFLIGHT/RUNTIME ERROR: {type(exc).__name__}: {exc}")
        print("Nessuna operazione distruttiva e nessun merge sono stati eseguiti.")
        return 1

    output_file = save_result(result)
    print("\n========== AGENT A PROGRAMMER FINAL ==========")
    print(result["final"])
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
