from __future__ import annotations

import argparse
import json
import os
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OLLAMA_CHAT_URL = os.environ.get("OLLAMA_CHAT_URL", "http://localhost:11434/api/chat")
DEFAULT_MODEL = os.environ.get("AGENT_A_MODEL", "qwen3.5:9b")

IGNORE_DIRS = {
    ".git",
    ".godot",
    "node_modules",
    "__pycache__",
    ".idea",
    ".vscode",
}

MAX_FILE_BYTES = 1_000_000
MAX_READ_LINES = 220
MAX_SEARCH_RESULTS = 60

REQUIRED_DOCS = {
    "AGENTS.md",
    "docs/AGENT_A.md",
    "docs/GAME_VISION.md",
    "docs/ART_DIRECTION.md",
    "docs/CURRENT_STATE.md",
}

SYSTEM_PROMPT = r"""
You are Agent A, an independent second Senior Game Engineer for Riftward: The Last Ascent.
This runtime is READ-ONLY. You are analyzing the real local repository and may not modify files.

Your job is to behave like a careful programmer, not a generic chatbot.

Evidence rules:
1. Before giving a final answer, use read_file to read AGENTS.md, docs/AGENT_A.md, docs/GAME_VISION.md, docs/ART_DIRECTION.md and docs/CURRENT_STATE.md.
2. Then use search_text/list_files to locate the relevant implementation. Do not guess filenames.
3. Read the relevant code before making claims about it.
4. Never claim that a file, function, class, field or behavior exists unless it was shown by a tool result or by a required project document you actually read.
5. If evidence is missing, search or read more. Do not fill gaps with assumptions.
6. Newest project documentation outranks older code when they conflict.
7. Godot is the active product only if the project evidence says so; determine this from the repository rather than assuming it.
8. Prefer the smallest safe change that would solve the user's actual request. Do not invent unrelated refactors.
9. Because this runtime is read-only, describe what you would change but do not output patches or pretend you changed anything.

Use the available repository tools autonomously. Your final answer should be based on evidence gathered during this run.
""".strip()

BENCHMARK_TASK = r"""
Analizza il progetto come se fossi il programmatore incaricato di correggere la base Level 1.
NON modificare nulla.

Rispondi ESATTAMENTE con queste sezioni:

1. IMPLEMENTAZIONE ATTIVA
Spiega quale versione del gioco deve essere sviluppata.

2. PROBLEMA PRINCIPALE
Individua almeno una contraddizione concreta tra il codice attuale della base e la direzione Level 1 documentata.

3. FILE COINVOLTI
Indica solo file che hai realmente trovato e letto o localizzato con gli strumenti, e spiega perche sono rilevanti.

4. HERO MOVEMENT
Spiega brevemente, sulla base del codice realmente letto, come gli hero agent scelgono e raggiungono le strutture.

5. PIANO MINIMO
Proponi una modifica minima e sicura per allineare la base Level 1 alla documentazione senza riscrivere sistemi funzionanti.

6. RISCHI
Indica i possibili effetti collaterali/regressioni che controlleresti.

7. VERDETTO
Scrivi una delle sole tre opzioni:
READY TO IMPLEMENT
NEED MORE CODE
NEED USER DECISION

Non scrivere codice. Non inventare file o funzioni.
""".strip()

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "list_files",
            "description": "List real repository files under a relative directory. Read-only.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Relative directory inside the repository, e.g. godot/scripts/base. Empty means repository root.",
                    },
                    "contains": {
                        "type": "string",
                        "description": "Optional case-insensitive substring used to filter returned paths.",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of paths to return (1-200).",
                    },
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read a real UTF-8 repository text file with line numbers. Read-only.",
            "parameters": {
                "type": "object",
                "required": ["path"],
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Exact relative repository path returned by search/list tools or known project docs.",
                    },
                    "start_line": {
                        "type": "integer",
                        "description": "1-based first line. Defaults to 1.",
                    },
                    "end_line": {
                        "type": "integer",
                        "description": "1-based last line. At most 220 lines are returned per call.",
                    },
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "search_text",
            "description": "Search text case-insensitively across real repository files and return matching file paths, line numbers and snippets. Read-only.",
            "parameters": {
                "type": "object",
                "required": ["query"],
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Literal text to search for, e.g. Workshop, hero_agent, navigation_path.",
                    },
                    "path": {
                        "type": "string",
                        "description": "Optional relative directory/file to restrict the search. Empty means repository root.",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum matches to return (1-60).",
                    },
                },
            },
        },
    },
]


def _safe_path(relative: str, must_exist: bool = True) -> Path:
    relative = (relative or "").replace("\\", "/").lstrip("/")
    candidate = (ROOT / relative).resolve()
    root_resolved = ROOT.resolve()
    if candidate != root_resolved and root_resolved not in candidate.parents:
        raise ValueError("Path outside repository is not allowed")
    if must_exist and not candidate.exists():
        raise FileNotFoundError(f"Repository path not found: {relative}")
    return candidate


def _is_ignored(path: Path) -> bool:
    try:
        parts = path.relative_to(ROOT).parts
    except ValueError:
        return True
    return any(part in IGNORE_DIRS for part in parts)


def _looks_text(path: Path) -> bool:
    if not path.is_file() or _is_ignored(path):
        return False
    try:
        if path.stat().st_size > MAX_FILE_BYTES:
            return False
        with path.open("rb") as handle:
            sample = handle.read(2048)
        return b"\x00" not in sample
    except OSError:
        return False


def list_files(path: str = "", contains: str = "", limit: int = 100) -> str:
    base = _safe_path(path)
    if base.is_file():
        return base.relative_to(ROOT).as_posix()

    needle = (contains or "").casefold()
    cap = max(1, min(int(limit or 100), 200))
    results: list[str] = []
    for candidate in sorted(base.rglob("*")):
        if len(results) >= cap:
            break
        if not candidate.is_file() or _is_ignored(candidate):
            continue
        rel = candidate.relative_to(ROOT).as_posix()
        if needle and needle not in rel.casefold():
            continue
        results.append(rel)
    return "\n".join(results) if results else "NO FILES FOUND"


def read_file(path: str, start_line: int = 1, end_line: int = 220) -> str:
    target = _safe_path(path)
    if not target.is_file():
        raise ValueError(f"Not a file: {path}")
    if not _looks_text(target):
        raise ValueError(f"File is binary or too large for read-only text inspection: {path}")

    start = max(1, int(start_line or 1))
    requested_end = max(start, int(end_line or (start + MAX_READ_LINES - 1)))
    end = min(requested_end, start + MAX_READ_LINES - 1)
    text = target.read_text(encoding="utf-8", errors="replace").splitlines()
    if start > len(text):
        return f"{path}: requested line {start}, but file has {len(text)} lines"
    end = min(end, len(text))
    rel = target.relative_to(ROOT).as_posix()
    lines = [f"{idx}: {text[idx - 1]}" for idx in range(start, end + 1)]
    return f"FILE {rel} LINES {start}-{end} OF {len(text)}\n" + "\n".join(lines)


def search_text(query: str, path: str = "", limit: int = 40) -> str:
    if not query:
        raise ValueError("query is required")
    base = _safe_path(path)
    cap = max(1, min(int(limit or 40), MAX_SEARCH_RESULTS))
    needle = query.casefold()
    candidates = [base] if base.is_file() else sorted(base.rglob("*"))
    hits: list[str] = []

    for candidate in candidates:
        if len(hits) >= cap:
            break
        if not _looks_text(candidate):
            continue
        try:
            lines = candidate.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        rel = candidate.relative_to(ROOT).as_posix()
        for idx, line in enumerate(lines, start=1):
            if needle in line.casefold():
                snippet = line.strip()
                if len(snippet) > 240:
                    snippet = snippet[:237] + "..."
                hits.append(f"{rel}:{idx}: {snippet}")
                if len(hits) >= cap:
                    break

    return "\n".join(hits) if hits else f"NO MATCHES FOR: {query}"


AVAILABLE_FUNCTIONS = {
    "list_files": list_files,
    "read_file": read_file,
    "search_text": search_text,
}


def ollama_chat(model: str, messages: list[dict[str, Any]], num_ctx: int) -> dict[str, Any]:
    payload = {
        "model": model,
        "messages": messages,
        "tools": TOOLS,
        "stream": False,
        "think": False,
        "options": {
            "num_ctx": num_ctx,
            "temperature": 0.1,
            "num_predict": 700,
        },
    }
    request = urllib.request.Request(
        OLLAMA_CHAT_URL,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(
            "Cannot reach Ollama at http://localhost:11434. Start Ollama and verify `ollama list`."
        ) from exc


def _assistant_message_for_history(message: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "role": "assistant",
        "content": message.get("content", ""),
    }
    if message.get("tool_calls"):
        result["tool_calls"] = message["tool_calls"]
    return result


def _evidence_gap(read_paths: set[str], search_count: int, gd_read: bool) -> str:
    missing_docs = sorted(REQUIRED_DOCS - read_paths)
    missing: list[str] = []
    if missing_docs:
        missing.append("required docs not read: " + ", ".join(missing_docs))
    if search_count < 1:
        missing.append("no repository search performed")
    if not gd_read:
        missing.append("no Godot .gd implementation file read")
    return "; ".join(missing)


def run_agent(task: str, model: str, num_ctx: int = 8192, max_rounds: int = 14) -> dict[str, Any]:
    messages: list[dict[str, Any]] = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": task},
    ]
    read_paths: set[str] = set()
    search_count = 0
    gd_read = False
    trace: list[dict[str, Any]] = []
    total_prompt_tokens = 0
    total_output_tokens = 0
    started = time.perf_counter()
    final_text = ""

    for round_no in range(1, max_rounds + 1):
        response = ollama_chat(model=model, messages=messages, num_ctx=num_ctx)
        total_prompt_tokens += int(response.get("prompt_eval_count") or 0)
        total_output_tokens += int(response.get("eval_count") or 0)
        message = response.get("message") or {}
        messages.append(_assistant_message_for_history(message))
        tool_calls = message.get("tool_calls") or []

        if tool_calls:
            for call in tool_calls:
                function = call.get("function") or {}
                name = function.get("name", "")
                args = function.get("arguments") or {}
                if not isinstance(args, dict):
                    args = {}
                print(f"[A tool] {name} {json.dumps(args, ensure_ascii=False)}")
                fn = AVAILABLE_FUNCTIONS.get(name)
                if fn is None:
                    result = f"ERROR: unknown tool {name}"
                else:
                    try:
                        result = fn(**args)
                    except Exception as exc:  # tool errors are evidence, not fatal runtime errors
                        result = f"ERROR: {type(exc).__name__}: {exc}"

                if name == "read_file" and not result.startswith("ERROR:"):
                    requested = str(args.get("path", "")).replace("\\", "/").lstrip("/")
                    read_paths.add(requested)
                    if requested.lower().endswith(".gd"):
                        gd_read = True
                elif name == "search_text" and not result.startswith("ERROR:"):
                    search_count += 1

                trace.append({"round": round_no, "tool": name, "arguments": args, "result": result})
                messages.append({"role": "tool", "tool_name": name, "content": result})
            continue

        final_text = str(message.get("content") or "").strip()
        gap = _evidence_gap(read_paths, search_count, gd_read)
        if gap:
            messages.append(
                {
                    "role": "user",
                    "content": (
                        "You attempted to finish before satisfying the read-only evidence gate. "
                        f"Missing evidence: {gap}. Continue using repository tools; do not answer yet."
                    ),
                }
            )
            final_text = ""
            continue
        if final_text:
            break
        messages.append(
            {
                "role": "user",
                "content": "All required evidence has been gathered. Provide the requested final answer now.",
            }
        )

    elapsed = time.perf_counter() - started
    gap = _evidence_gap(read_paths, search_count, gd_read)
    result = {
        "model": model,
        "elapsed_seconds": round(elapsed, 1),
        "prompt_tokens_total_across_rounds": total_prompt_tokens,
        "output_tokens_total_across_rounds": total_output_tokens,
        "required_docs_read": sorted(REQUIRED_DOCS & read_paths),
        "evidence_gate_remaining": gap,
        "tool_calls": len(trace),
        "trace": trace,
        "final": final_text or "NO FINAL ANSWER PRODUCED",
    }
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_readonly_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only local Agent A for Riftward using Ollama.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--benchmark", action="store_true", help="Run the standard Level 1 base analysis benchmark.")
    mode.add_argument("--ask", type=str, help="Run one custom read-only engineering task.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Ollama model (default: {DEFAULT_MODEL}).")
    parser.add_argument("--ctx", type=int, default=8192, help="Ollama context length (default: 8192).")
    parser.add_argument("--max-rounds", type=int, default=14, help="Maximum model/tool rounds (default: 14).")
    args = parser.parse_args()

    task = BENCHMARK_TASK if args.benchmark else str(args.ask)
    print("Riftward Agent A - READ ONLY")
    print(f"Repository: {ROOT}")
    print(f"Model: {args.model}")
    print("No write/edit/shell tools are available in this runtime.\n")

    try:
        result = run_agent(task=task, model=args.model, num_ctx=max(4096, args.ctx), max_rounds=max(4, args.max_rounds))
    except Exception as exc:
        print(f"ERROR: {type(exc).__name__}: {exc}")
        return 1

    output_file = save_result(result)
    print("\n========== AGENT A FINAL ==========")
    print(result["final"])
    print("\n========== RUN DATA ==========")
    print(f"Time: {result['elapsed_seconds']} seconds")
    print(f"Tool calls: {result['tool_calls']}")
    print(f"Prompt tokens (sum across rounds): {result['prompt_tokens_total_across_rounds']}")
    print(f"Output tokens (sum across rounds): {result['output_tokens_total_across_rounds']}")
    print(f"Evidence gate remaining: {result['evidence_gate_remaining'] or 'NONE'}")
    print(f"Trace/result JSON: {output_file}")
    return 0 if result["final"] != "NO FINAL ANSWER PRODUCED" and not result["evidence_gate_remaining"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
