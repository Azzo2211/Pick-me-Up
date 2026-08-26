from __future__ import annotations

import argparse
import json
import tempfile
import time
from pathlib import Path
from typing import Any

import readonly_agent as core
import readonly_agent_v2 as v2
import readonly_agent_v5 as v5
import readonly_agent_v6 as v6


BOOTSTRAP_SEARCHES = [
    {"query": "Workshop", "path": "godot/scripts/base", "limit": 40},
    {"query": "level_one_background", "path": "godot/scripts/base", "limit": 40},
    {"query": "HubBackground", "path": "godot/scripts/base", "limit": 40},
    {"query": "Armory", "path": "", "limit": 40},
]


def _normalize_path(path: str) -> str:
    return path.replace("\\", "/").lstrip("/")


def _record_read(
    path: str,
    trace: list[dict[str, Any]],
    read_paths: set[str],
    start_line: int = 1,
    end_line: int = 220,
) -> bool:
    args = {"path": path, "start_line": start_line, "end_line": end_line}
    print(f"[A bootstrap] read_file {json.dumps(args, ensure_ascii=False)}")
    try:
        result = core.read_file(**args)
    except Exception as exc:
        result = f"ERROR: {type(exc).__name__}: {exc}"
    trace.append({"round": "bootstrap", "tool": "read_file", "arguments": args, "result": result})
    if result.startswith("ERROR:"):
        return False
    read_paths.add(_normalize_path(path))
    return True


def _record_search(
    args: dict[str, Any],
    trace: list[dict[str, Any]],
) -> bool:
    print(f"[A bootstrap] search_text {json.dumps(args, ensure_ascii=False)}")
    try:
        result = core.search_text(**args)
    except Exception as exc:
        result = f"ERROR: {type(exc).__name__}: {exc}"
    trace.append({"round": "bootstrap", "tool": "search_text", "arguments": args, "result": result})
    return not result.startswith("ERROR:")


def _bootstrap_mandatory_evidence(
    strict_benchmark: bool,
    trace: list[dict[str, Any]],
    read_paths: set[str],
) -> tuple[int, bool]:
    bootstrap_reads = 0
    gd_read = False

    # These are repository rules, not optional model choices.
    ordered_docs = [
        "AGENTS.md",
        "docs/AGENT_A.md",
        "docs/GAME_VISION.md",
        "docs/ART_DIRECTION.md",
        "docs/CURRENT_STATE.md",
    ]
    for path in ordered_docs:
        if _record_read(path, trace, read_paths):
            bootstrap_reads += 1

    if strict_benchmark:
        ordered_code = [
            "godot/scripts/base/base_hub.gd",
            "godot/scripts/base/base_building.gd",
            "godot/scripts/base/building_data.gd",
            "godot/scripts/base/hero_agent.gd",
        ]
        for path in ordered_code:
            if _record_read(path, trace, read_paths):
                bootstrap_reads += 1
                gd_read = True

    return bootstrap_reads, gd_read


def _seed_seen_calls(trace: list[dict[str, Any]]) -> set[str]:
    seen: set[str] = set()
    for item in trace:
        tool = str(item.get("tool") or "")
        args = item.get("arguments") or {}
        seen.add(json.dumps({"name": tool, "args": args}, sort_keys=True, ensure_ascii=False))
    return seen


def _optional_model_research(
    task: str,
    model: str,
    num_ctx: int,
    rounds: int,
    trace: list[dict[str, Any]],
    read_paths: set[str],
    image_paths: set[str],
    discovery_count: int,
    gd_read: bool,
) -> tuple[int, int, int, bool]:
    total_prompt = 0
    total_output = 0
    seen_calls = _seed_seen_calls(trace)

    messages: list[dict[str, Any]] = [
        {"role": "system", "content": v5.SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                task
                + "\n\nMandatory repository rules and core benchmark files have already been read by the runtime. "
                "Do not reread them unless you need a different line range. Use tools only to find additional evidence "
                "that could change the diagnosis, implementation plan, dependencies, or verdict. Do not answer yet."
            ),
        },
    ]

    for round_no in range(1, rounds + 1):
        response = v5.chat_with_tools(model, messages, num_ctx)
        total_prompt += int(response.get("prompt_eval_count") or 0)
        total_output += int(response.get("eval_count") or 0)
        message = response.get("message") or {}
        messages.append(v5._assistant_history(message))
        calls = message.get("tool_calls") or []
        if not calls:
            break

        useful_call = False
        for call in calls:
            fn = call.get("function") or {}
            name = str(fn.get("name") or "")
            args = fn.get("arguments") or {}
            if not isinstance(args, dict):
                args = {}
            key = json.dumps({"name": name, "args": args}, sort_keys=True, ensure_ascii=False)
            print(f"[A tool] {name} {json.dumps(args, ensure_ascii=False)}")

            if key in seen_calls:
                result = "DUPLICATE TOOL CALL SKIPPED."
            else:
                seen_calls.add(key)
                useful_call = True
                try:
                    result = v5._execute_tool(name, args, model, num_ctx)
                except Exception as exc:
                    result = f"ERROR: {type(exc).__name__}: {exc}"

            if not result.startswith("ERROR:") and not result.startswith("DUPLICATE"):
                if name == "read_file":
                    path = _normalize_path(str(args.get("path") or ""))
                    read_paths.add(path)
                    if path.lower().endswith(".gd"):
                        gd_read = True
                elif name in {"search_text", "list_files"}:
                    discovery_count += 1
                elif name == "inspect_image":
                    image_paths.add(_normalize_path(str(args.get("path") or "")))

            trace.append({"round": f"model-{round_no}", "tool": name, "arguments": args, "result": result})
            messages.append({"role": "tool", "tool_name": name, "content": result})

        if not useful_call:
            break

    return total_prompt, total_output, discovery_count, gd_read


def _gate_from_critic(text: str) -> str:
    return v5._gate_from_critic(text)


def run_agent_v7(
    task: str,
    model: str,
    num_ctx: int = 8192,
    strict_benchmark: bool = False,
    extra_research_rounds: int = 2,
) -> dict[str, Any]:
    started = time.perf_counter()
    trace: list[dict[str, Any]] = []
    read_paths: set[str] = set()
    image_paths: set[str] = set()
    discovery_count = 0
    total_prompt = 0
    total_output = 0

    bootstrap_reads, gd_read = _bootstrap_mandatory_evidence(
        strict_benchmark=strict_benchmark,
        trace=trace,
        read_paths=read_paths,
    )

    for args in BOOTSTRAP_SEARCHES:
        if _record_search(args, trace):
            discovery_count += 1

    # Deterministic visual inspection happens before any verdict. It extracts
    # real image references from the already-read code and inspects them locally.
    auto_added, auto_failures = v6._append_auto_image_inspections(
        trace=trace,
        image_paths=image_paths,
        model=model,
        num_ctx=num_ctx,
    )

    # The model may still explore for extra evidence, but missing mandatory files
    # can no longer block the run because they were bootstrapped above.
    p, o, discovery_count, gd_read = _optional_model_research(
        task=task,
        model=model,
        num_ctx=num_ctx,
        rounds=max(0, extra_research_rounds),
        trace=trace,
        read_paths=read_paths,
        image_paths=image_paths,
        discovery_count=discovery_count,
        gd_read=gd_read,
    )
    total_prompt += p
    total_output += o

    gap = v5._evidence_gap(
        read_paths=read_paths,
        discovery_count=discovery_count,
        gd_read=gd_read,
        image_paths=image_paths,
        strict_benchmark=strict_benchmark,
    )

    packet = v5.build_packet(task, trace) if not gap else ""
    draft = ""
    critic = ""
    ready_gate = "UNKNOWN"
    final_text = ""
    validation_error = ""

    if not gap:
        draft_response = v5.chat_no_tools(
            model,
            [
                {"role": "system", "content": v5.FINAL_SYSTEM},
                {"role": "user", "content": "ORIGINAL TASK:\n" + task + "\n\nEVIDENCE PACKET:\n" + packet},
            ],
            num_ctx,
            num_predict=1100,
        )
        total_prompt += int(draft_response.get("prompt_eval_count") or 0)
        total_output += int(draft_response.get("eval_count") or 0)
        draft = str((draft_response.get("message") or {}).get("content") or "").strip()

        critic_response = v5.chat_no_tools(
            model,
            [
                {"role": "system", "content": v5.CRITIC_SYSTEM},
                {"role": "user", "content": "ORIGINAL TASK:\n" + task + "\n\nDRAFT:\n" + draft + "\n\nEVIDENCE PACKET:\n" + packet},
            ],
            num_ctx,
            num_predict=850,
        )
        total_prompt += int(critic_response.get("prompt_eval_count") or 0)
        total_output += int(critic_response.get("eval_count") or 0)
        critic = str((critic_response.get("message") or {}).get("content") or "").strip()
        ready_gate = _gate_from_critic(critic)
        if ready_gate == "UNKNOWN":
            critic, p2, o2 = v5._repair_critic_gate(model, critic, num_ctx)
            total_prompt += p2
            total_output += o2
            ready_gate = _gate_from_critic(critic)

        revision_response = v5.chat_no_tools(
            model,
            [
                {"role": "system", "content": v5.REVISION_SYSTEM},
                {
                    "role": "user",
                    "content": (
                        "ORIGINAL TASK:\n" + task
                        + "\n\nEVIDENCE PACKET:\n" + packet
                        + "\n\nCRITIC REPORT:\n" + critic
                        + "\n\nDRAFT TO CORRECT:\n" + draft
                    ),
                },
            ],
            num_ctx,
            num_predict=1150,
        )
        total_prompt += int(revision_response.get("prompt_eval_count") or 0)
        total_output += int(revision_response.get("eval_count") or 0)
        final_text = str((revision_response.get("message") or {}).get("content") or "").strip()

        if strict_benchmark:
            validation_error = v2._benchmark_validation_error(final_text)
            if not validation_error and ready_gate == "BLOCK":
                verdict = final_text.split("7. VERDETTO", 1)[-1]
                if "READY TO IMPLEMENT" in verdict:
                    validation_error = "critic BLOCK but final verdict is READY TO IMPLEMENT"
            if not validation_error and ready_gate == "UNKNOWN":
                validation_error = "critic did not produce a valid READY gate"

    elapsed = time.perf_counter() - started
    return {
        "runtime": "v7-deterministic-bootstrap",
        "model": model,
        "elapsed_seconds": round(elapsed, 1),
        "prompt_tokens_total_across_rounds": total_prompt,
        "output_tokens_total_across_rounds": total_output,
        "bootstrap_reads": bootstrap_reads,
        "required_docs_read": sorted(core.REQUIRED_DOCS & read_paths),
        "code_files_read": sorted(path for path in read_paths if path.endswith(".gd")),
        "images_inspected": sorted(image_paths),
        "auto_visual_added": auto_added,
        "auto_visual_failures": auto_failures,
        "discovery_count": discovery_count,
        "evidence_gate_remaining": gap,
        "final_validation_error": validation_error,
        "tool_calls": len(trace),
        "evidence_packet_chars": len(packet),
        "ready_gate": ready_gate,
        "critic": critic,
        "draft": draft,
        "trace": trace,
        "final": final_text or "NO FINAL ANSWER PRODUCED",
    }


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_readonly_v7_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only Agent A v7 with deterministic mandatory evidence bootstrap.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--benchmark", action="store_true")
    mode.add_argument("--ask", type=str)
    parser.add_argument("--model", default=core.DEFAULT_MODEL)
    parser.add_argument("--ctx", type=int, default=8192)
    parser.add_argument("--extra-research-rounds", type=int, default=2)
    args = parser.parse_args()

    task = core.BENCHMARK_TASK if args.benchmark else str(args.ask)
    print("Riftward Agent A v7 - READ ONLY / DETERMINISTIC BOOTSTRAP")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print("Mandatory docs/code/searches are loaded by the runtime; visual assets are auto-inspected; model research is supplemental.\n")

    try:
        result = run_agent_v7(
            task=task,
            model=args.model,
            num_ctx=max(4096, args.ctx),
            strict_benchmark=bool(args.benchmark),
            extra_research_rounds=max(0, args.extra_research_rounds),
        )
    except Exception as exc:
        print(f"ERROR: {type(exc).__name__}: {exc}")
        return 1

    output_file = save_result(result)
    print("\n========== CRITIC REPORT ==========")
    print(result["critic"])
    print("\n========== AGENT A FINAL ==========")
    print(result["final"])
    print("\n========== RUN DATA ==========")
    print(f"Runtime: {result['runtime']}")
    print(f"Time: {result['elapsed_seconds']} seconds")
    print(f"Bootstrap reads: {result['bootstrap_reads']}")
    print(f"Tool/evidence records: {result['tool_calls']}")
    print(f"Prompt tokens (sum across model calls): {result['prompt_tokens_total_across_rounds']}")
    print(f"Output tokens (sum across model calls): {result['output_tokens_total_across_rounds']}")
    print(f"Evidence packet: {result['evidence_packet_chars']} chars")
    print("Required docs read: " + (", ".join(result["required_docs_read"]) or "NONE"))
    print("Images inspected: " + (", ".join(result["images_inspected"]) or "NONE"))
    print(f"Auto-visual inspections added: {result['auto_visual_added']}")
    print(f"Auto-visual failures: {result['auto_visual_failures']}")
    print(f"Evidence gate remaining: {result['evidence_gate_remaining'] or 'NONE'}")
    print(f"Critical READY gate: {result['ready_gate']}")
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
