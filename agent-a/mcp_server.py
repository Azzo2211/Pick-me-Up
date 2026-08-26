from __future__ import annotations

import contextlib
import os
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any

from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations

import programmer_agent_stable as stable
import programmer_agent_v4_2 as transport
import readonly_agent as core
import readonly_agent_v5 as v5


ROOT = Path(__file__).resolve().parents[1]
MODEL = stable.MODEL
MAX_TASK_CHARS = 20000
MAX_DIFF_CHARS = 24000
_RUN_LOCK = threading.Lock()

# The MCP process is dedicated to this repository. Keeping cwd deterministic is
# useful for Git/Godot subprocesses even though Agent A also resolves ROOT.
os.chdir(ROOT)

mcp = MCPServer(
    "Riftward Agent A",
    version="1.0.0",
    instructions=(
        "Qualified first-line local programmer for Riftward. Use run_agent_a for repository programming work. "
        "Agent A may create a task branch and edit local files, but it never commits, pushes, or merges automatically. "
        "If terminal_status is NEED_USER_DECISION, ask the user the returned question before doing anything else. "
        "If terminal_status is ESCALATE_TO_CODEX, report the blocker and do not invent a local implementation."
    ),
)


def _configure_local_transport() -> None:
    core.OLLAMA_CHAT_URL = transport.CHAT_URL
    v5._request_ollama = transport._direct_request_ollama


def _current_branch() -> str:
    completed = subprocess.run(
        ["git", "-C", str(ROOT), "branch", "--show-current"],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    return completed.stdout.strip() or "UNKNOWN"


def _trim(value: Any, limit: int) -> str:
    text = str(value or "")
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n...[truncated {len(text) - limit} chars]"


def _public_result(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "terminal_status": result.get("terminal_status", "UNKNOWN"),
        "final": result.get("final", ""),
        "plan": result.get("plan", ""),
        "stable_version": result.get("stable_version", stable.STABLE_VERSION),
        "qualified_baseline": result.get("qualified_baseline", stable.QUALIFIED_BASELINE),
        "runtime": result.get("runtime", ""),
        "base_branch": result.get("base_branch", ""),
        "task_branch": result.get("task_branch", "NOT CREATED"),
        "changed_files": list(result.get("changed_files") or []),
        "mutations": int(result.get("mutations") or 0),
        "diff_check": result.get("diff_check", "NOT RUN"),
        "godot_check": result.get("godot_check", "NOT RUN"),
        "reviews": list(result.get("reviews") or []),
        "needs_user_decision": bool(result.get("needs_user_decision")),
        "escalate_to_codex": bool(result.get("escalate_to_codex")),
        "product_decision_guard": bool(result.get("unresolved_product_decision_guard")),
        "product_decision_ids": list(result.get("unresolved_product_decision_ids") or []),
        "elapsed_seconds": result.get("elapsed_seconds"),
        "prompt_tokens": int(result.get("prompt_tokens_total") or 0),
        "output_tokens": int(result.get("output_tokens_total") or 0),
        "diff": _trim(result.get("diff", ""), MAX_DIFF_CHARS),
    }


@mcp.tool(
    title="Check Agent A status",
    annotations=ToolAnnotations(
        read_only_hint=True,
        destructive_hint=False,
        idempotent_hint=True,
        open_world_hint=False,
    ),
)
def get_agent_a_status() -> dict[str, Any]:
    """Check whether the qualified local Agent A runtime and Qwen/Ollama model are reachable."""
    _configure_local_transport()
    ok, note = transport._full_preflight(MODEL)
    return {
        "ready": bool(ok),
        "note": note,
        "stable_version": stable.STABLE_VERSION,
        "qualified_baseline": stable.QUALIFIED_BASELINE,
        "model": MODEL,
        "repository": str(ROOT),
        "branch": _current_branch(),
        "ollama_endpoint": transport.CHAT_URL,
    }


@mcp.tool(
    title="Run Agent A programmer",
    annotations=ToolAnnotations(
        read_only_hint=False,
        destructive_hint=False,
        idempotent_hint=False,
        open_world_hint=False,
    ),
)
def run_agent_a(task: str) -> dict[str, Any]:
    """Run Agent A v1 Stable on one Riftward programming task.

    Use for implementation, bug fixing, refactoring, Godot checks, repository
    audits, and related engineering work. The tool can edit the local working
    tree and create an agent-a task branch, but Agent A never commits, pushes,
    or merges automatically. Product decisions return NEED_USER_DECISION;
    technically unsafe work returns ESCALATE_TO_CODEX.
    """
    task = task.strip()
    if not task:
        return {
            "terminal_status": "INVALID_TASK",
            "final": "Task is empty.",
            "changed_files": [],
            "mutations": 0,
        }
    if len(task) > MAX_TASK_CHARS:
        return {
            "terminal_status": "INVALID_TASK",
            "final": f"Task exceeds the {MAX_TASK_CHARS}-character MCP safety limit.",
            "changed_files": [],
            "mutations": 0,
        }

    if not _RUN_LOCK.acquire(blocking=False):
        return {
            "terminal_status": "BUSY",
            "final": "Agent A is already running another repository task. Wait for that run to finish before retrying.",
            "changed_files": [],
            "mutations": 0,
        }

    try:
        _configure_local_transport()
        ok, note = transport._full_preflight(MODEL)
        if not ok:
            return {
                "terminal_status": "LOCAL_RUNTIME_UNAVAILABLE",
                "final": "Qwen/Ollama preflight failed: " + note,
                "stable_version": stable.STABLE_VERSION,
                "qualified_baseline": stable.QUALIFIED_BASELINE,
                "model": MODEL,
                "repository": str(ROOT),
                "branch": _current_branch(),
                "changed_files": [],
                "mutations": 0,
            }

        # stdout is the MCP protocol wire. Route legacy runtime prints to stderr
        # so they can never corrupt MCP JSON-RPC traffic.
        with contextlib.redirect_stdout(sys.stderr):
            result = stable.run_programmer(task, MODEL)
        return _public_result(result)
    except Exception as exc:
        return {
            "terminal_status": "MCP_BRIDGE_ERROR",
            "final": f"Agent A MCP bridge failed: {type(exc).__name__}: {exc}",
            "stable_version": stable.STABLE_VERSION,
            "qualified_baseline": stable.QUALIFIED_BASELINE,
            "repository": str(ROOT),
            "branch": _current_branch(),
            "changed_files": [],
            "mutations": 0,
        }
    finally:
        _RUN_LOCK.release()


if __name__ == "__main__":
    mcp.run(transport="stdio")
