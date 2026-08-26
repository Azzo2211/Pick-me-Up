from __future__ import annotations

import argparse
import base64
import json
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import readonly_agent as core
import readonly_agent_v2 as v2
import readonly_agent_v3 as v3


VISION_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}
MAX_IMAGE_BYTES = 12_000_000

SYSTEM_PROMPT = """You are Agent A, an independent Senior Game Engineer for Riftward: The Last Ascent.
This runtime is READ-ONLY. Inspect the real repository before answering.

Evidence rules:
1. Read AGENTS.md, docs/AGENT_A.md, docs/GAME_VISION.md, docs/ART_DIRECTION.md and docs/CURRENT_STATE.md.
2. Discover and read the relevant implementation. Never guess filenames/functions.
3. Describe CURRENT code behavior separately from DESIRED documented behavior.
4. A documented list is not automatically exhaustive. Never say 'only these facilities exist' unless the evidence explicitly says so.
5. Check defaults in data/config classes; do not use conditional 'if' language when the evidence proves the actual value.
6. Distinguish: data entry, instantiated node/hotspot, rendered primitive, and artwork baked into an image/background.
7. Do not invent collision, occupancy, reservation, navigation, rendering, or scene behavior.
8. If code references a visual image that can determine whether a facility is physically visible, inspect that image with inspect_image before deciding implementation readiness.
9. READY TO IMPLEMENT is allowed only if the actual change surface and adjacent effects are evidenced. Otherwise use NEED MORE CODE or NEED USER DECISION.
10. Do not modify files.
""".strip()

FINAL_SYSTEM = """You are Agent A producing the final read-only engineering analysis for Riftward.
Use only the persistent evidence packet gathered from the real repository in this run.
Do not invent facts. Correctly distinguish documented product direction from current implementation.
Do not turn non-exclusive facility notes into an exclusive facility list.
For hub visuals, distinguish background artwork from invisible interaction hotspots/nodes.
For hero movement, describe the actual code: availability filtering, random destination/slot selection, navigation paths, waypoints and state transitions. Do not invent collisions or slot reservations.
If an inspected image provides visual evidence, use it explicitly but conservatively.
Follow the ORIGINAL TASK exactly and use its seven exact headings.
""".strip()

CRITIC_SYSTEM = """You are a strict verification pass for a Senior Game Engineer.
Audit the draft against the evidence packet. Do not solve from memory.

Reject factual overreach, especially:
- claiming the Level 1 facility notes are an exhaustive list when they are not;
- claiming Armory exists in current code without evidence;
- saying project.godot must be edited merely because assets exist;
- inventing collision/occupancy/reservation systems;
- overlooking is_unlocked defaults;
- overlooking that every building_data entry may still create a BaseBuilding hotspot;
- overlooking that level_one_background can suppress procedural drawing while a background PNG provides the visible architecture;
- describing desired hero movement instead of current hero_agent.gd behavior.

Output exactly:
FACT CHECK
<short audit>
BLIND SPOTS
<short audit>
DEPENDENCIES
<short audit>
READY_GATE: ALLOW
or
READY_GATE: BLOCK

ALLOW only if the evidence supports a concrete implementation plan without an unresolved dependency that could invalidate it.
""".strip()

REVISION_SYSTEM = """You are Agent A revising a draft after an independent critic.
Use only the evidence packet and critic report. Fix every identified overreach.
Use all seven exact ORIGINAL TASK headings.
If READY_GATE is BLOCK due missing technical/asset evidence, verdict must be NEED MORE CODE.
If BLOCK due a genuine product decision, verdict must be NEED USER DECISION.
READY TO IMPLEMENT is allowed only if READY_GATE is ALLOW.
Do not invent collisions, reservations, files or exclusive facility lists.
""".strip()

IMAGE_TOOL = {
    "type": "function",
    "function": {
        "name": "inspect_image",
        "description": "Visually inspect a real repository PNG/JPG/WebP asset using the local multimodal Ollama model. Read-only.",
        "parameters": {
            "type": "object",
            "required": ["path"],
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Exact relative repository image path, e.g. godot/assets/backgrounds/base_level_1_wide.png.",
                },
                "question": {
                    "type": "string",
                    "description": "Specific visual question. Ask only what is visible; do not infer game logic.",
                },
            },
        },
    },
}

TOOLS = core.TOOLS + [IMAGE_TOOL]

BENCHMARK_REQUIRED_CODE = {
    "godot/scripts/base/base_hub.gd",
    "godot/scripts/base/base_building.gd",
    "godot/scripts/base/building_data.gd",
    "godot/scripts/base/hero_agent.gd",
}


def _request_ollama(payload: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        core.OLLAMA_CHAT_URL,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=900) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError("Cannot reach Ollama at http://localhost:11434") from exc


def chat_with_tools(model: str, messages: list[dict[str, Any]], num_ctx: int) -> dict[str, Any]:
    return _request_ollama({
        "model": model,
        "messages": messages,
        "tools": TOOLS,
        "stream": False,
        "think": False,
        "options": {"num_ctx": num_ctx, "temperature": 0.1, "num_predict": 650},
    })


def chat_no_tools(model: str, messages: list[dict[str, Any]], num_ctx: int, num_predict: int = 1050) -> dict[str, Any]:
    return _request_ollama({
        "model": model,
        "messages": messages,
        "stream": False,
        "think": False,
        "options": {"num_ctx": num_ctx, "temperature": 0.1, "num_predict": num_predict},
    })


def inspect_image(path: str, question: str, model: str, num_ctx: int) -> str:
    target = core._safe_path(path)
    if not target.is_file():
        raise ValueError(f"Not a file: {path}")
    if target.suffix.lower() not in VISION_EXTENSIONS:
        raise ValueError(f"Unsupported image extension: {target.suffix}")
    size = target.stat().st_size
    if size > MAX_IMAGE_BYTES:
        raise ValueError(f"Image too large for local inspection: {size} bytes")

    encoded = base64.b64encode(target.read_bytes()).decode("ascii")
    prompt = question.strip() if question else (
        "Inspect this game asset visually. Describe only visible evidence. Identify whether you can visibly distinguish "
        "a central open plaza, training area, lodging/dormitory, mission gate/portal, fusion/merging structure, "
        "workshop/alchemy structure, armory/forge, warehouse, and summoning area. If a facility cannot be identified "
        "confidently from appearance alone, say uncertain. Do not infer from filenames or code."
    )
    payload = {
        "model": model,
        "messages": [{
            "role": "user",
            "content": prompt,
            "images": [encoded],
        }],
        "stream": False,
        "think": False,
        "options": {"num_ctx": num_ctx, "temperature": 0.1, "num_predict": 500},
    }
    response = _request_ollama(payload)
    content = str((response.get("message") or {}).get("content") or "").strip()
    rel = target.relative_to(core.ROOT).as_posix()
    return f"VISUAL INSPECTION OF {rel}\n{content or 'NO VISUAL DESCRIPTION PRODUCED'}"


def _assistant_history(message: dict[str, Any]) -> dict[str, Any]:
    item: dict[str, Any] = {"role": "assistant", "content": message.get("content", "")}
    if message.get("tool_calls"):
        item["tool_calls"] = message["tool_calls"]
    return item


def _evidence_gap(
    read_paths: set[str],
    discovery_count: int,
    gd_read: bool,
    image_paths: set[str],
    strict_benchmark: bool,
) -> str:
    missing: list[str] = []
    docs = sorted(core.REQUIRED_DOCS - read_paths)
    if docs:
        missing.append("required docs not read: " + ", ".join(docs))
    if discovery_count < 1:
        missing.append("no repository discovery performed")
    if not gd_read:
        missing.append("no Godot .gd implementation read")
    if strict_benchmark:
        missing_code = sorted(BENCHMARK_REQUIRED_CODE - read_paths)
        if missing_code:
            missing.append("benchmark-relevant code not read: " + ", ".join(missing_code))
        if not image_paths:
            missing.append("no relevant visual asset inspected")
    return "; ".join(missing)


def _execute_tool(
    name: str,
    args: dict[str, Any],
    model: str,
    num_ctx: int,
) -> str:
    if name == "inspect_image":
        return inspect_image(
            path=str(args.get("path") or ""),
            question=str(args.get("question") or ""),
            model=model,
            num_ctx=num_ctx,
        )
    fn = core.AVAILABLE_FUNCTIONS.get(name)
    if fn is None:
        return f"ERROR: unknown tool {name}"
    try:
        return fn(**args)
    except Exception as exc:
        return f"ERROR: {type(exc).__name__}: {exc}"


def _visual_evidence(trace: list[dict[str, Any]], max_chars: int = 5500) -> str:
    chunks: list[str] = []
    used = 0
    for item in trace:
        if item.get("tool") != "inspect_image":
            continue
        result = str(item.get("result") or "")
        if result.startswith("ERROR:"):
            continue
        chunk = result[:3000]
        if used + len(chunk) > max_chars:
            chunk = chunk[: max_chars - used]
        if chunk:
            chunks.append(chunk)
            used += len(chunk)
        if used >= max_chars:
            break
    return "\n\n--- VISUAL ---\n\n".join(chunks)


def build_packet(task: str, trace: list[dict[str, Any]]) -> str:
    text_packet = v3.build_evidence_packet(
        task
        + "\ncritical terms: is_unlocked default BaseBuilding level_one_background _draw HubBackground activity_slots navigation_path _route_to _choose_destination Workshop Armory warehouse summoning",
        trace,
        budget=16500,
    )
    visual = _visual_evidence(trace)
    if visual:
        return text_packet + "\n\n=== VISUAL ASSET EVIDENCE ===\n" + visual
    return text_packet


def _gate_from_critic(text: str) -> str:
    for line in text.splitlines():
        normalized = line.strip().upper()
        if normalized == "READY_GATE: ALLOW":
            return "ALLOW"
        if normalized == "READY_GATE: BLOCK":
            return "BLOCK"
    return "UNKNOWN"


def _repair_critic_gate(model: str, critic: str, num_ctx: int) -> tuple[str, int, int]:
    response = chat_no_tools(
        model,
        [
            {"role": "system", "content": "Return the audit unchanged in meaning but ensure the final non-empty line is exactly READY_GATE: ALLOW or READY_GATE: BLOCK."},
            {"role": "user", "content": critic},
        ],
        num_ctx,
        num_predict=500,
    )
    return (
        str((response.get("message") or {}).get("content") or "").strip(),
        int(response.get("prompt_eval_count") or 0),
        int(response.get("eval_count") or 0),
    )


def run_agent_v5(
    task: str,
    model: str,
    num_ctx: int = 8192,
    max_research_rounds: int = 7,
    strict_benchmark: bool = False,
) -> dict[str, Any]:
    started = time.perf_counter()
    messages: list[dict[str, Any]] = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": task},
    ]
    read_paths: set[str] = set()
    image_paths: set[str] = set()
    discovery_count = 0
    gd_read = False
    trace: list[dict[str, Any]] = []
    seen_calls: set[str] = set()
    total_prompt = 0
    total_output = 0

    for round_no in range(1, max_research_rounds + 1):
        response = chat_with_tools(model, messages, num_ctx)
        total_prompt += int(response.get("prompt_eval_count") or 0)
        total_output += int(response.get("eval_count") or 0)
        message = response.get("message") or {}
        messages.append(_assistant_history(message))
        tool_calls = message.get("tool_calls") or []

        if not tool_calls:
            gap = _evidence_gap(read_paths, discovery_count, gd_read, image_paths, strict_benchmark)
            if not gap:
                break
            messages.append({
                "role": "user",
                "content": (
                    "RESEARCH NOT COMPLETE. Do not answer yet. Missing: " + gap + ". "
                    "Use repository tools. If a background/image path was found in code, inspect the actual image."
                ),
            })
            continue

        for call in tool_calls:
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
                try:
                    result = _execute_tool(name, args, model, num_ctx)
                except Exception as exc:
                    result = f"ERROR: {type(exc).__name__}: {exc}"

            if not result.startswith("ERROR:") and not result.startswith("DUPLICATE"):
                if name == "read_file":
                    path = str(args.get("path") or "").replace("\\", "/").lstrip("/")
                    read_paths.add(path)
                    if path.lower().endswith(".gd"):
                        gd_read = True
                elif name in {"search_text", "list_files"}:
                    discovery_count += 1
                elif name == "inspect_image":
                    path = str(args.get("path") or "").replace("\\", "/").lstrip("/")
                    image_paths.add(path)

            trace.append({"round": round_no, "tool": name, "arguments": args, "result": result})
            messages.append({"role": "tool", "tool_name": name, "content": result})

        gap = _evidence_gap(read_paths, discovery_count, gd_read, image_paths, strict_benchmark)
        if not gap:
            break

    gap = _evidence_gap(read_paths, discovery_count, gd_read, image_paths, strict_benchmark)
    packet = build_packet(task, trace) if not gap else ""
    draft = ""
    critic = ""
    ready_gate = "UNKNOWN"
    final_text = ""
    validation_error = ""

    if not gap:
        draft_response = chat_no_tools(
            model,
            [
                {"role": "system", "content": FINAL_SYSTEM},
                {"role": "user", "content": "ORIGINAL TASK:\n" + task + "\n\nEVIDENCE PACKET:\n" + packet},
            ],
            num_ctx,
            num_predict=1050,
        )
        total_prompt += int(draft_response.get("prompt_eval_count") or 0)
        total_output += int(draft_response.get("eval_count") or 0)
        draft = str((draft_response.get("message") or {}).get("content") or "").strip()

        critic_response = chat_no_tools(
            model,
            [
                {"role": "system", "content": CRITIC_SYSTEM},
                {
                    "role": "user",
                    "content": "ORIGINAL TASK:\n" + task + "\n\nDRAFT:\n" + draft + "\n\nEVIDENCE PACKET:\n" + packet,
                },
            ],
            num_ctx,
            num_predict=800,
        )
        total_prompt += int(critic_response.get("prompt_eval_count") or 0)
        total_output += int(critic_response.get("eval_count") or 0)
        critic = str((critic_response.get("message") or {}).get("content") or "").strip()
        ready_gate = _gate_from_critic(critic)
        if ready_gate == "UNKNOWN":
            critic, p, o = _repair_critic_gate(model, critic, num_ctx)
            total_prompt += p
            total_output += o
            ready_gate = _gate_from_critic(critic)

        revision_response = chat_no_tools(
            model,
            [
                {"role": "system", "content": REVISION_SYSTEM},
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
            num_predict=1100,
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
        "runtime": "v5-multimodal-critical",
        "model": model,
        "elapsed_seconds": round(elapsed, 1),
        "prompt_tokens_total_across_rounds": total_prompt,
        "output_tokens_total_across_rounds": total_output,
        "required_docs_read": sorted(core.REQUIRED_DOCS & read_paths),
        "code_files_read": sorted(path for path in read_paths if path.endswith(".gd")),
        "images_inspected": sorted(image_paths),
        "evidence_gate_remaining": gap,
        "final_validation_error": validation_error,
        "tool_calls": len(trace),
        "unique_tool_calls": len(seen_calls),
        "evidence_packet_chars": len(packet),
        "ready_gate": ready_gate,
        "critic": critic,
        "draft": draft,
        "trace": trace,
        "final": final_text or "NO FINAL ANSWER PRODUCED",
    }


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_readonly_v5_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only Agent A v5 with local multimodal asset inspection.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--benchmark", action="store_true")
    mode.add_argument("--ask", type=str)
    parser.add_argument("--model", default=core.DEFAULT_MODEL)
    parser.add_argument("--ctx", type=int, default=8192)
    parser.add_argument("--max-research-rounds", type=int, default=7)
    args = parser.parse_args()

    task = core.BENCHMARK_TASK if args.benchmark else str(args.ask)
    print("Riftward Agent A v5 - READ ONLY / MULTIMODAL CRITICAL")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print("Reads code/docs and can visually inspect real repository images before the critical gate.\n")

    try:
        result = run_agent_v5(
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
    print("\n========== CRITIC REPORT ==========")
    print(result["critic"])
    print("\n========== AGENT A FINAL ==========")
    print(result["final"])
    print("\n========== RUN DATA ==========")
    print(f"Runtime: {result['runtime']}")
    print(f"Time: {result['elapsed_seconds']} seconds")
    print(f"Tool calls: {result['tool_calls']} ({result['unique_tool_calls']} unique)")
    print(f"Prompt tokens (sum across rounds): {result['prompt_tokens_total_across_rounds']}")
    print(f"Output tokens (sum across rounds): {result['output_tokens_total_across_rounds']}")
    print(f"Evidence packet: {result['evidence_packet_chars']} chars")
    print("Images inspected: " + (", ".join(result["images_inspected"]) or "NONE"))
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
