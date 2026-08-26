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

import programmer_agent_v4 as v4
import readonly_agent as core
import readonly_agent_v5 as v5


MODEL = core.DEFAULT_MODEL
CHAT_URL = os.environ.get("OLLAMA_CHAT_URL", "http://127.0.0.1:11434/api/chat").strip()
TAGS_URL = "http://127.0.0.1:11434/api/tags"


def _direct_opener() -> urllib.request.OpenerDirector:
    # Local Ollama traffic must never be routed through Windows/system HTTP proxies.
    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


def _read_http_error(exc: urllib.error.HTTPError) -> str:
    try:
        body = exc.read().decode("utf-8", errors="replace").strip()
    except Exception:
        body = ""
    return body[:1200]


def _direct_request_ollama(payload: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        CHAT_URL,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    last_error = ""
    for attempt in range(2):
        try:
            with _direct_opener().open(request, timeout=900) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = _read_http_error(exc)
            raise RuntimeError(
                f"Ollama HTTP {exc.code} at {CHAT_URL}: {body or exc.reason}"
            ) from exc
        except (urllib.error.URLError, ConnectionResetError, TimeoutError, OSError) as exc:
            reason = getattr(exc, "reason", exc)
            last_error = f"{type(exc).__name__}: {reason}"
            if attempt == 0:
                time.sleep(1.5)
                continue
            raise RuntimeError(
                f"Ollama chat connection failed at {CHAT_URL} after 2 attempts: {last_error}"
            ) from exc
    raise RuntimeError(f"Ollama chat connection failed at {CHAT_URL}: {last_error}")


def _tags_preflight(model: str) -> tuple[bool, str]:
    request = urllib.request.Request(TAGS_URL, method="GET")
    try:
        with _direct_opener().open(request, timeout=5) as response:
            payload: dict[str, Any] = json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        return False, f"/api/tags non raggiungibile su {TAGS_URL}: {type(exc).__name__}: {exc}"

    names = {
        str(item.get("name") or item.get("model") or "").strip()
        for item in (payload.get("models") or [])
        if isinstance(item, dict)
    }
    if model not in names:
        return False, (
            f"Ollama risponde, ma il modello {model!r} non e installato. "
            f"Disponibili: {', '.join(sorted(name for name in names if name)) or 'NESSUNO'}"
        )
    return True, f"/api/tags OK; modello trovato: {model}"


def _chat_preflight(model: str) -> tuple[bool, str]:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": "Reply with exactly OK"}],
        "stream": False,
        "think": False,
        "options": {
            "num_ctx": 2048,
            "temperature": 0.0,
            "num_predict": 8,
        },
    }
    started = time.perf_counter()
    try:
        response = _direct_request_ollama(payload)
    except Exception as exc:
        return False, f"/api/chat con {model} ha fallito: {type(exc).__name__}: {exc}"
    elapsed = time.perf_counter() - started
    message = response.get("message") or {}
    content = str(message.get("content") or "").strip()
    if not content:
        return False, f"/api/chat ha risposto ma senza contenuto per {model}."
    return True, f"/api/chat OK con {model} in {elapsed:.1f}s (risposta: {content[:40]!r})"


def _full_preflight(model: str) -> tuple[bool, str]:
    ok, tags = _tags_preflight(model)
    if not ok:
        return False, tags
    ok, chat = _chat_preflight(model)
    if not ok:
        return False, tags + "\n" + chat
    return True, tags + "\n" + chat


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_2_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Agent A programmer v4.2 with direct Ollama transport.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    print("Riftward Agent A - PROGRAMMER v4.2 / DIRECT OLLAMA CHAT")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print(f"Ollama chat: {CHAT_URL}")
    print("Pipeline: real model-chat preflight -> evidence -> plan -> edit manifest -> apply -> verify -> review. No commit/push/merge.\n")

    # Patch the shared Ollama transport before any downstream Agent A stage runs.
    core.OLLAMA_CHAT_URL = CHAT_URL
    v5._request_ollama = _direct_request_ollama

    ok, note = _full_preflight(args.model)
    if not ok:
        print("OLLAMA MODEL PREFLIGHT FAILED:")
        print(note)
        print("\nNessuna branch del task e stata creata.")
        print(f"Test manuale consigliato: ollama run {args.model} \"Rispondi solo OK\"")
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

    # A cheap second connectivity check immediately before the branch-creating run.
    ok, note = _tags_preflight(args.model)
    if not ok:
        print("\nOLLAMA CONNECTION LOST BEFORE TASK START:")
        print(note)
        print("Nessuna branch del task e stata creata.")
        return 5

    try:
        result = v4.run_programmer(task, args.model)
    except Exception as exc:
        print(f"\nPREFLIGHT/RUNTIME ERROR: {type(exc).__name__}: {exc}")
        print("Nessuna operazione distruttiva, commit, push o merge e stata eseguita.")
        return 1

    result["runtime"] = "programmer-v4.2-direct-ollama-chat"
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
