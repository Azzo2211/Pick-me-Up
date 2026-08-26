from __future__ import annotations

import argparse
import json
import re
import tempfile
import time
from pathlib import Path
from typing import Any

import readonly_agent as core
import readonly_agent_v2 as v2


FINAL_EVIDENCE_BUDGET = 21000
FINAL_SYSTEM = """You are Agent A, an independent Senior Game Engineer for Riftward.
You already completed read-only repository research. The EVIDENCE PACKET below is persistent evidence copied from real tool results from this run.
Treat every source named in that packet as actually read/found. Never claim that those documents were unavailable merely because earlier chat history is not present.
Answer the ORIGINAL TASK, not the last lookup. Use only evidence in the packet. Do not invent files, functions, behavior, or requirements.
When documentation conflicts with code, follow the repository priority rules shown in the evidence. Be concise and technically specific.
""".strip()

STOPWORDS = {
    "della", "delle", "degli", "dello", "dalla", "dalle", "dallo", "dentro", "senza", "questo",
    "questa", "queste", "questi", "come", "deve", "essere", "sono", "solo", "file", "codice", "progetto",
    "spiega", "indica", "brevemente", "modifica", "modifiche", "attuale", "attuali", "rispondi", "sezioni",
    "with", "that", "this", "from", "into", "only", "using", "project", "answer", "section", "files",
}

BENCHMARK_TERMS = {
    "godot", "level", "base", "hub", "workshop", "armory", "merging", "fusion", "alchemy", "square", "plaza",
    "mission", "gate", "portal", "training", "dormitory", "lodgings", "hero", "movement", "activity_slots",
    "navigation_path", "choose_destination", "route_to", "building", "facility", "unlock", "web",
}


def _task_terms(task: str, trace: list[dict[str, Any]]) -> set[str]:
    terms = set(BENCHMARK_TERMS)
    for token in re.findall(r"[A-Za-zÀ-ÿ_][A-Za-zÀ-ÿ0-9_]{3,}", task):
        folded = token.casefold()
        if folded not in STOPWORDS:
            terms.add(folded)
    for item in trace:
        if item.get("tool") == "search_text":
            query = str((item.get("arguments") or {}).get("query") or "").strip().casefold()
            if query:
                terms.add(query)
    return terms


def _source_path(item: dict[str, Any]) -> str:
    args = item.get("arguments") or {}
    return str(args.get("path") or "").replace("\\", "/").lstrip("/")


def _select_lines(result: str, terms: set[str], max_chars: int) -> str:
    lines = result.splitlines()
    if not lines:
        return result[:max_chars]

    header = lines[0]
    body = lines[1:]
    selected_indexes: set[int] = set()

    for idx, line in enumerate(body):
        folded = line.casefold()
        if any(term in folded for term in terms):
            for nearby in range(max(0, idx - 2), min(len(body), idx + 3)):
                selected_indexes.add(nearby)

    if not selected_indexes:
        selected_indexes.update(range(min(len(body), 40)))

    chosen = [header]
    last_idx = -2
    for idx in sorted(selected_indexes):
        if idx > last_idx + 1:
            chosen.append("...")
        chosen.append(body[idx])
        last_idx = idx
        if len("\n".join(chosen)) >= max_chars:
            break

    text = "\n".join(chosen)
    return text[:max_chars]


def _entry_priority(item: dict[str, Any]) -> tuple[int, int]:
    tool = str(item.get("tool") or "")
    path = _source_path(item)
    doc_order = {
        "docs/GAME_VISION.md": 0,
        "docs/ART_DIRECTION.md": 1,
        "docs/CURRENT_STATE.md": 2,
        "AGENTS.md": 3,
        "docs/AGENT_A.md": 4,
    }
    if path in doc_order:
        return (0, doc_order[path])
    if tool == "read_file" and path.endswith("base_hub.gd"):
        return (1, 0)
    if tool == "read_file" and path.endswith("hero_agent.gd"):
        return (1, 1)
    if tool == "read_file" and path.endswith("building_data.gd"):
        return (1, 2)
    if tool == "read_file" and path.endswith("base_building.gd"):
        return (1, 3)
    if tool in {"search_text", "list_files"}:
        return (2, 0)
    if tool == "read_file" and path.endswith(".gd"):
        return (3, 0)
    return (4, 0)


def _per_source_cap(item: dict[str, Any]) -> int:
    path = _source_path(item)
    if path == "docs/GAME_VISION.md":
        return 2800
    if path in {"docs/ART_DIRECTION.md", "docs/CURRENT_STATE.md"}:
        return 2300
    if path in {"AGENTS.md", "docs/AGENT_A.md"}:
        return 1300
    if path.endswith("base_hub.gd") or path.endswith("hero_agent.gd"):
        return 3000
    if path.endswith("building_data.gd") or path.endswith("base_building.gd"):
        return 1800
    if item.get("tool") in {"search_text", "list_files"}:
        return 1200
    return 1500


def build_evidence_packet(task: str, trace: list[dict[str, Any]], budget: int = FINAL_EVIDENCE_BUDGET) -> str:
    terms = _task_terms(task, trace)
    successful: list[dict[str, Any]] = []
    seen: set[str] = set()

    for item in trace:
        result = str(item.get("result") or "")
        if result.startswith("ERROR:") or result.startswith("DUPLICATE"):
            continue
        key = json.dumps(
            {"tool": item.get("tool"), "arguments": item.get("arguments")},
            sort_keys=True,
            ensure_ascii=False,
        )
        if key in seen:
            continue
        seen.add(key)
        successful.append(item)

    successful.sort(key=_entry_priority)
    chunks: list[str] = []
    used = 0

    for item in successful:
        tool = str(item.get("tool") or "")
        args = item.get("arguments") or {}
        result = str(item.get("result") or "")
        cap = _per_source_cap(item)
        if tool == "read_file":
            compact = _select_lines(result, terms, cap)
        else:
            compact = result[:cap]

        label = f"SOURCE tool={tool} args={json.dumps(args, ensure_ascii=False)}\n{compact}"
        remaining = budget - used
        if remaining <= 200:
            break
        if len(label) > remaining:
            label = label[:remaining]
        chunks.append(label)
        used += len(label) + 8

    return "\n\n---\n\n".join(chunks)


def _quality_signals(text: str) -> dict[str, bool]:
    folded = text.casefold()
    return {
        "mentions_godot": "godot" in folded,
        "mentions_base_hub": "base_hub.gd" in folded,
        "mentions_hero_agent": "hero_agent.gd" in folded,
        "mentions_workshop_or_alchemy": "workshop" in folded or "alchemy" in folded,
        "mentions_level_1": "level 1" in folded,
    }


def run_agent_v3(
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

    for round_no in range(1, max_research_rounds + 1):
        response = core.ollama_chat(model=model, messages=messages, num_ctx=num_ctx)
        total_prompt_tokens += int(response.get("prompt_eval_count") or 0)
        total_output_tokens += int(response.get("eval_count") or 0)
        message = response.get("message") or {}
        messages.append(v2._assistant_history(message))
        tool_calls = message.get("tool_calls") or []

        if not tool_calls:
            gap = v2._evidence_gap(read_paths, discovery_count, gd_read)
            if not gap:
                break
            messages.append({
                "role": "user",
                "content": f"RESEARCH NOT COMPLETE. Missing evidence: {gap}. Use repository tools now; do not answer yet.",
            })
            continue

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

        gap = v2._evidence_gap(read_paths, discovery_count, gd_read)
        if not gap:
            break

    gap = v2._evidence_gap(read_paths, discovery_count, gd_read)
    final_text = ""
    validation_error = ""
    packet = ""

    if not gap:
        packet = build_evidence_packet(task, trace)
        final_messages = [
            {"role": "system", "content": FINAL_SYSTEM},
            {
                "role": "user",
                "content": (
                    "ORIGINAL TASK:\n"
                    + task
                    + "\n\nEVIDENCE PACKET FROM THIS RUN:\n"
                    + packet
                ),
            },
        ]
        response = v2._chat_without_tools(model=model, messages=final_messages, num_ctx=num_ctx, num_predict=1000)
        total_prompt_tokens += int(response.get("prompt_eval_count") or 0)
        total_output_tokens += int(response.get("eval_count") or 0)
        final_text = str((response.get("message") or {}).get("content") or "").strip()

        if strict_benchmark:
            validation_error = v2._benchmark_validation_error(final_text)
            if validation_error:
                retry_messages = final_messages + [
                    {"role": "assistant", "content": final_text},
                    {
                        "role": "user",
                        "content": (
                            "FORMAT ERROR: " + validation_error + ". Rewrite using the seven exact requested headings. "
                            "Use the same evidence packet. Do not claim the evidence is unavailable."
                        ),
                    },
                ]
                retry = v2._chat_without_tools(model=model, messages=retry_messages, num_ctx=num_ctx, num_predict=1000)
                total_prompt_tokens += int(retry.get("prompt_eval_count") or 0)
                total_output_tokens += int(retry.get("eval_count") or 0)
                final_text = str((retry.get("message") or {}).get("content") or "").strip()
                validation_error = v2._benchmark_validation_error(final_text)

    elapsed = time.perf_counter() - started
    result = {
        "runtime": "v3-persistent-evidence",
        "model": model,
        "elapsed_seconds": round(elapsed, 1),
        "prompt_tokens_total_across_rounds": total_prompt_tokens,
        "output_tokens_total_across_rounds": total_output_tokens,
        "required_docs_read": sorted(core.REQUIRED_DOCS & read_paths),
        "evidence_gate_remaining": gap,
        "final_validation_error": validation_error,
        "tool_calls": len(trace),
        "unique_tool_calls": len(seen_calls),
        "evidence_packet_chars": len(packet),
        "quality_signals": _quality_signals(final_text),
        "trace": trace,
        "final": final_text or "NO FINAL ANSWER PRODUCED",
    }
    return result


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_readonly_v3_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only local Agent A v3 with persistent evidence packet.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--benchmark", action="store_true")
    mode.add_argument("--ask", type=str)
    parser.add_argument("--model", default=core.DEFAULT_MODEL)
    parser.add_argument("--ctx", type=int, default=8192)
    parser.add_argument("--max-research-rounds", type=int, default=5)
    args = parser.parse_args()

    task = core.BENCHMARK_TASK if args.benchmark else str(args.ask)
    print("Riftward Agent A v3 - READ ONLY / PERSISTENT EVIDENCE")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print("Research tools: list/read/search. Final phase receives a compact persistent evidence packet.\n")

    try:
        result = run_agent_v3(
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
    print(f"Evidence packet: {result['evidence_packet_chars']} chars")
    print(f"Evidence gate remaining: {result['evidence_gate_remaining'] or 'NONE'}")
    print(f"Final validation error: {result['final_validation_error'] or 'NONE'}")
    print("Quality signals: " + json.dumps(result["quality_signals"], ensure_ascii=False))
    print(f"Trace/result JSON: {output_file}")

    ok = (
        result["final"] != "NO FINAL ANSWER PRODUCED"
        and not result["evidence_gate_remaining"]
        and not result["final_validation_error"]
    )
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
