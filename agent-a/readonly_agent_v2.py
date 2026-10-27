from __future__ import annotations

import argparse
import json
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import readonly_agent as core


BENCHMARK_HEADINGS = [
    "1. IMPLEMENTAZIONE ATTIVA",
    "2. PROBLEMA PRINCIPALE",
    "3. FILE COINVOLTI",
    "4. HERO MOVEMENT",
    "5. PIANO MINIMO",
    "6. RISCHI",
    "7. VERDETTO",
]
VALID_VERDICTS = ("READY TO IMPLEMENT", "NEED MORE CODE", "NEED USER DECISION")


def _evidence_gap(read_paths: set[str], discovery_count: int, gd_read: bool) -> str:
    missing_docs = sorted(core.REQUIRED_DOCS - read_paths)
    missing: list[str] = []
    if missing_docs:
        missing.append("required docs not read: " + ", ".join(missing_docs))
    if discovery_count < 1:
        missing.append("no repository discovery performed (search_text or list_files)")
    if not gd_read:
        missing.append("no Godot .gd implementation file read")
    return "; ".join(missing)


def _benchmark_validation_error(text: str) -> str:
    missing = [heading for heading in BENCHMARK_HEADINGS if heading not in text]
    if missing:
        return "missing exact sections: " + ", ".join(missing)

    verdict_block = text.split("7. VERDETTO", 1)[1].strip()
    verdict_lines = [line.strip() for line in verdict_block.splitlines() if line.strip()]
    if not verdict_lines:
        return "section 7 has no verdict"
    if verdict_lines[0] not in VALID_VERDICTS:
        return "section 7 must begin with exactly one allowed verdict"
    return ""


def _assistant_history(message: dict[str, Any]) -> dict[str, Any]:
    item: dict[str, Any] = {"role": "assistant", "content": message.get("content", "")}
    if message.get("tool_calls"):
        item["tool_calls"] = message["tool_calls"]
    return item


def _chat_without_tools(model: str, messages: list[dict[str, Any]], num_ctx: int, num_predict: int = 1100) -> dict[str, Any]:
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
        "think": False,
        "options": {
            "num_ctx": num_ctx,
            "temperature": 0.1,
            "num_predict": num_predict,
        },
    }
    request = urllib.request.Request(
        core.OLLAMA_CHAT_URL,
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


def run_agent_v2(
    task: str,
    model: str,
    num_ctx: int = 8192,
    max_research_rounds: int = 5,
    strict_benchmark: bool = False,
) -> dict[str, Any]:
    messages: list[dict[str, Any]] = [
        {"role": "system", "content": core.SYSTEM_PROMPT},
        {"role": "user", "content": task},
    ]

    read_paths: set[str] = set()
    discovery_count = 0
    gd_read = False
    trace: list[dict[str, Any]] = []
    seen_calls: set[str] = set()
    total_prompt_tokens = 0
    total_output_tokens = 0
    started = time.perf_counter()
    gap = ""

    # Phase 1: research only. Once the evidence gate is satisfied, stop tool use
    # immediately instead of allowing the model to drift toward the last tool result.
    for round_no in range(1, max_research_rounds + 1):
        response = core.ollama_chat(model=model, messages=messages, num_ctx=num_ctx)
        total_prompt_tokens += int(response.get("prompt_eval_count") or 0)
        total_output_tokens += int(response.get("eval_count") or 0)
        message = response.get("message") or {}
        messages.append(_assistant_history(message))
        tool_calls = message.get("tool_calls") or []

        if not tool_calls:
            gap = _evidence_gap(read_paths, discovery_count, gd_read)
            if gap:
                messages.append(
                    {
                        "role": "user",
                        "content": (
                            "RESEARCH NOT COMPLETE. Do not answer the task yet. "
                            f"Missing evidence: {gap}. Use repository tools now."
                        ),
                    }
                )
                continue
            break

        for call in tool_calls:
            function = call.get("function") or {}
            name = str(function.get("name") or "")
            args = function.get("arguments") or {}
            if not isinstance(args, dict):
                args = {}

            call_key = json.dumps({"name": name, "args": args}, sort_keys=True, ensure_ascii=False)
            print(f"[A tool] {name} {json.dumps(args, ensure_ascii=False)}")

            if call_key in seen_calls:
                result = "DUPLICATE TOOL CALL SKIPPED. This exact evidence was already gathered."
            else:
                seen_calls.add(call_key)
                fn = core.AVAILABLE_FUNCTIONS.get(name)
                if fn is None:
                    result = f"ERROR: unknown tool {name}"
                else:
                    try:
                        result = fn(**args)
                    except Exception as exc:
                        result = f"ERROR: {type(exc).__name__}: {exc}"

            if not result.startswith("ERROR:") and not result.startswith("DUPLICATE"):
                if name == "read_file":
                    requested = str(args.get("path", "")).replace("\\", "/").lstrip("/")
                    read_paths.add(requested)
                    if requested.lower().endswith(".gd"):
                        gd_read = True
                elif name in {"search_text", "list_files"}:
                    discovery_count += 1

            trace.append({"round": round_no, "tool": name, "arguments": args, "result": result})
            messages.append({"role": "tool", "tool_name": name, "content": result})

        gap = _evidence_gap(read_paths, discovery_count, gd_read)
        if not gap:
            break

        messages.append(
            {
                "role": "user",
                "content": (
                    "Continue repository research only. Do not provide a final answer yet. "
                    f"Evidence still missing: {gap}. Avoid repeating identical tool calls."
                ),
            }
        )

    gap = _evidence_gap(read_paths, discovery_count, gd_read)
    final_text = ""
    validation_error = ""

    if not gap:
        # Phase 2: anchored final answer with NO tools available. Repeating the
        # original task here prevents the final response from answering the last
        # repository lookup instead of the user's actual request.
        final_messages = messages + [
            {
                "role": "user",
                "content": (
                    "RESEARCH COMPLETE. Tool use is now finished. Answer the ORIGINAL TASK below using only the "
                    "evidence already gathered. Do not answer or summarize the most recent tool lookup by itself.\n\n"
                    "ORIGINAL TASK:\n"
                    + task
                ),
            }
        ]
        response = _chat_without_tools(model=model, messages=final_messages, num_ctx=num_ctx)
        total_prompt_tokens += int(response.get("prompt_eval_count") or 0)
        total_output_tokens += int(response.get("eval_count") or 0)
        final_text = str((response.get("message") or {}).get("content") or "").strip()

        if strict_benchmark:
            validation_error = _benchmark_validation_error(final_text)
            if validation_error:
                retry_messages = final_messages + [
                    {"role": "assistant", "content": final_text},
                    {
                        "role": "user",
                        "content": (
                            "FINAL ANSWER REJECTED BY FORMAT GATE: "
                            + validation_error
                            + ". Rewrite the answer now. Do not research again. Follow the ORIGINAL TASK exactly, "
                            "including all seven exact section headings and one allowed verdict."
                        ),
                    },
                ]
                retry = _chat_without_tools(model=model, messages=retry_messages, num_ctx=num_ctx)
                total_prompt_tokens += int(retry.get("prompt_eval_count") or 0)
                total_output_tokens += int(retry.get("eval_count") or 0)
                final_text = str((retry.get("message") or {}).get("content") or "").strip()
                validation_error = _benchmark_validation_error(final_text)

    elapsed = time.perf_counter() - started
    result = {
        "runtime": "v2-anchored",
        "model": model,
        "elapsed_seconds": round(elapsed, 1),
        "prompt_tokens_total_across_rounds": total_prompt_tokens,
        "output_tokens_total_across_rounds": total_output_tokens,
        "required_docs_read": sorted(core.REQUIRED_DOCS & read_paths),
        "evidence_gate_remaining": gap,
        "final_validation_error": validation_error,
        "tool_calls": len(trace),
        "unique_tool_calls": len(seen_calls),
        "trace": trace,
        "final": final_text or "NO FINAL ANSWER PRODUCED",
    }
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_readonly_v2_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Anchored read-only local Agent A for Riftward using Ollama.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--benchmark", action="store_true", help="Run the standard Level 1 base analysis benchmark.")
    mode.add_argument("--ask", type=str, help="Run one custom read-only engineering task.")
    parser.add_argument("--model", default=core.DEFAULT_MODEL, help=f"Ollama model (default: {core.DEFAULT_MODEL}).")
    parser.add_argument("--ctx", type=int, default=8192, help="Ollama context length (default: 8192).")
    parser.add_argument("--max-research-rounds", type=int, default=5, help="Maximum research rounds before finalization.")
    args = parser.parse_args()

    task = core.BENCHMARK_TASK if args.benchmark else str(args.ask)
    print("Riftward Agent A v2 - READ ONLY / ANCHORED")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print("Research tools: list/read/search only. Final answer phase has no tools.\n")

    try:
        result = run_agent_v2(
            task=task,
            model=args.model,
            num_ctx=max(4096, args.ctx),
            max_research_rounds=max(1, args.max_research_rounds),
            strict_benchmark=bool(args.benchmark),
        )
    except Exception as exc:
        print(f"ERROR: {type(exc).__name__}: {exc}")
        return 1

    output_file = save_result(result)
    print("\n========== AGENT A FINAL ==========")
    print(result["final"])
    print("\n========== RUN DATA ==========")
    print(f"Runtime: {result['runtime']}")
    print(f"Time: {result['elapsed_seconds']} seconds")
    print(f"Tool calls: {result['tool_calls']} ({result['unique_tool_calls']} unique)")
    print(f"Prompt tokens (sum across rounds): {result['prompt_tokens_total_across_rounds']}")
    print(f"Output tokens (sum across rounds): {result['output_tokens_total_across_rounds']}")
    print(f"Evidence gate remaining: {result['evidence_gate_remaining'] or 'NONE'}")
    print(f"Final validation error: {result['final_validation_error'] or 'NONE'}")
    print(f"Trace/result JSON: {output_file}")

    ok = (
        result["final"] != "NO FINAL ANSWER PRODUCED"
        and not result["evidence_gate_remaining"]
        and not result["final_validation_error"]
    )
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
