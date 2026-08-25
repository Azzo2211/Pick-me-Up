from __future__ import annotations

import argparse
import json
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import programmer_agent_v4 as v4
import readonly_agent as core


MODEL = core.DEFAULT_MODEL
OLLAMA_TAGS_URL = "http://localhost:11434/api/tags"


def _ollama_preflight(model: str) -> tuple[bool, str]:
    request = urllib.request.Request(OLLAMA_TAGS_URL, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=4) as response:
            payload: dict[str, Any] = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return False, (
            "Ollama non risponde su http://localhost:11434. "
            "Apri una seconda finestra PowerShell, esegui `ollama serve` e lasciala aperta; "
            "poi verifica con `ollama list`. Dettaglio: " + str(exc)
        )
    except Exception as exc:
        return False, "Ollama ha risposto ma /api/tags non e leggibile: " + f"{type(exc).__name__}: {exc}"

    models = payload.get("models") or []
    names = {
        str(item.get("name") or item.get("model") or "").strip()
        for item in models
        if isinstance(item, dict)
    }
    if model not in names:
        return False, (
            f"Ollama e attivo, ma il modello richiesto `{model}` non compare in `ollama list`. "
            f"Modelli rilevati: {', '.join(sorted(name for name in names if name)) or 'NESSUNO'}."
        )
    return True, f"Ollama OK; modello disponibile: {model}"


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_programmer_v4_1_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Agent A programmer v4.1 with Ollama preflight.")
    parser.add_argument("--task", type=str, default="")
    parser.add_argument("--model", default=MODEL)
    args = parser.parse_args()

    task = args.task.strip()
    print("Riftward Agent A - PROGRAMMER v4.1 / TOOL EDIT MANIFEST")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print("Pipeline: Ollama preflight -> evidence -> plan -> edit manifest -> apply -> verify -> review. No commit/push/merge.\n")

    ok, note = _ollama_preflight(args.model)
    if not ok:
        print("OLLAMA PREFLIGHT FAILED:")
        print(note)
        print("\nNessuna branch del task e stata creata.")
        return 5
    print(note + "\n")

    if not task:
        try:
            task = input("Descrivi il lavoro da fare ad Agent A:\n> ").strip()
        except EOFError:
            task = ""
    if not task:
        print("Nessun task inserito. Uscita senza modifiche.")
        return 2

    # Check again immediately before the branch-creating programmer run in case
    # Ollama was stopped while the user was typing a long task.
    ok, note = _ollama_preflight(args.model)
    if not ok:
        print("\nOLLAMA PREFLIGHT FAILED BEFORE TASK START:")
        print(note)
        print("Nessuna branch del task e stata creata.")
        return 5

    try:
        result = v4.run_programmer(task, args.model)
    except Exception as exc:
        print(f"\nPREFLIGHT/RUNTIME ERROR: {type(exc).__name__}: {exc}")
        print("Nessuna operazione distruttiva, commit, push o merge e stata eseguita.")
        return 1

    result["runtime"] = "programmer-v4.1-ollama-preflight"
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
