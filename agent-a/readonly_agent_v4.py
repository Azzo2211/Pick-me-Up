from __future__ import annotations

import argparse
import json
import tempfile
import time
from pathlib import Path
from typing import Any

import readonly_agent as core
import readonly_agent_v2 as v2
import readonly_agent_v3 as v3


CRITIC_SYSTEM = """You are the verification pass for Agent A, an independent Senior Game Engineer.
You do not solve the task from scratch. You audit a draft answer against a persistent evidence packet gathered from the real repository.

Be adversarial and precise. Look especially for:
- claims that turn a non-exclusive design list into an exclusive list;
- conditional wording where the evidence proves a concrete fact;
- hidden defaults in data models/configuration;
- differences between logical availability, physical instantiation, interaction hotspots, and rendered/embedded artwork;
- referenced image/background/asset dependencies that were not visually inspected;
- claims that a simple flag change fixes behavior when downstream code ignores that flag;
- inaccurate descriptions of routing, occupancy, randomness, state, or filtering;
- files/functions/assets mentioned without evidence;
- a READY TO IMPLEMENT verdict despite unresolved code or asset dependencies.

READY_GATE rules:
- ALLOW only when the evidence is sufficient to identify the actual change surface and important adjacent effects with no unresolved dependency that could invalidate the plan.
- BLOCK when more repository/code/asset inspection is needed before implementation can be considered safe.
- BLOCK is not a product-design disagreement; if the missing item is a genuine product decision, say so explicitly.

Output exactly these headings:
FACT CHECK
BLIND SPOTS
DEPENDENCIES
READY_GATE: ALLOW
or
READY_GATE: BLOCK
""".strip()

REVISION_SYSTEM = """You are Agent A producing the final engineering answer after an independent verification pass.
Use only the evidence packet and the critic report. Do not invent facts.
Correct every factual overreach or missing dependency identified by the critic.
Do not treat an example/list of documented Level 1 facilities as exhaustive unless the evidence explicitly says it is exhaustive.
Distinguish data state, instantiated nodes/hotspots, and artwork embedded in background/image assets.
If an important referenced binary visual asset was not actually inspected and it can invalidate the proposed visual fix, state that limitation.
Describe movement/routing exactly as supported by code; do not imply slot occupancy/reservations unless present.

Verdict rules:
- If READY_GATE is BLOCK because more repository/code/asset evidence is needed, section 7 must be NEED MORE CODE.
- If READY_GATE is BLOCK because a genuine product decision is missing, section 7 must be NEED USER DECISION.
- READY TO IMPLEMENT is allowed only when READY_GATE is ALLOW.

Follow the ORIGINAL TASK's exact requested headings and format.
""".strip()

EXTRA_EVIDENCE_TERMS = """
Critical verification terms: HubBackground background asset image texture visual_variant level_one_background _draw is_unlocked default building_data instantiate add_child workshop alchemy armory warehouse summoning activity_slots navigation_path route_to choose_destination occupancy availability hotspot physical render.
""".strip()


def _chat(model: str, messages: list[dict[str, Any]], num_ctx: int, num_predict: int) -> dict[str, Any]:
    return v2._chat_without_tools(model=model, messages=messages, num_ctx=num_ctx, num_predict=num_predict)


def _parse_ready_gate(text: str) -> str:
    for line in text.splitlines():
        normalized = line.strip().upper()
        if normalized == "READY_GATE: ALLOW":
            return "ALLOW"
        if normalized == "READY_GATE: BLOCK":
            return "BLOCK"
    return "BLOCK"


def _quality_signals(text: str, critic: str) -> dict[str, bool]:
    folded = text.casefold()
    critic_folded = critic.casefold()
    return {
        "mentions_godot": "godot" in folded,
        "mentions_base_hub": "base_hub.gd" in folded,
        "mentions_hero_agent": "hero_agent.gd" in folded,
        "mentions_workshop": "workshop" in folded or "alchemy" in folded,
        "mentions_background_or_asset": "background" in folded or "asset" in folded or "base_level_1_wide" in folded,
        "mentions_visual_variant_or_draw": "visual_variant" in folded or "_draw" in folded,
        "mentions_is_unlocked": "is_unlocked" in folded,
        "critic_has_gate": "ready_gate:" in critic_folded,
    }


def run_agent_v4(
    task: str,
    model: str,
    num_ctx: int = 8192,
    max_research_rounds: int = 5,
    strict_benchmark: bool = False,
) -> dict[str, Any]:
    started = time.perf_counter()

    # Stage 1: use the proven v3 research loop and persistent-evidence draft.
    draft_result = v3.run_agent_v3(
        task=task,
        model=model,
        num_ctx=num_ctx,
        max_research_rounds=max_research_rounds,
        strict_benchmark=strict_benchmark,
    )

    total_prompt_tokens = int(draft_result.get("prompt_tokens_total_across_rounds") or 0)
    total_output_tokens = int(draft_result.get("output_tokens_total_across_rounds") or 0)
    gap = str(draft_result.get("evidence_gate_remaining") or "")
    draft = str(draft_result.get("final") or "")
    trace = list(draft_result.get("trace") or [])

    critic = ""
    ready_gate = "BLOCK"
    final_text = draft
    validation_error = str(draft_result.get("final_validation_error") or "")
    packet = ""

    if not gap and draft and draft != "NO FINAL ANSWER PRODUCED":
        # Rebuild a broader evidence packet for the critic/final pass. The extra
        # generic terms force preservation of rendering/assets/defaults and
        # downstream behavior that can invalidate an apparently simple fix.
        packet = v3.build_evidence_packet(task + "\n" + EXTRA_EVIDENCE_TERMS, trace)

        critic_messages = [
            {"role": "system", "content": CRITIC_SYSTEM},
            {
                "role": "user",
                "content": (
                    "ORIGINAL TASK:\n"
                    + task
                    + "\n\nDRAFT ANSWER TO AUDIT:\n"
                    + draft
                    + "\n\nPERSISTENT EVIDENCE PACKET:\n"
                    + packet
                ),
            },
        ]
        critic_response = _chat(model=model, messages=critic_messages, num_ctx=num_ctx, num_predict=850)
        total_prompt_tokens += int(critic_response.get("prompt_eval_count") or 0)
        total_output_tokens += int(critic_response.get("eval_count") or 0)
        critic = str((critic_response.get("message") or {}).get("content") or "").strip()
        ready_gate = _parse_ready_gate(critic)

        revision_messages = [
            {"role": "system", "content": REVISION_SYSTEM},
            {
                "role": "user",
                "content": (
                    "ORIGINAL TASK:\n"
                    + task
                    + "\n\nPERSISTENT EVIDENCE PACKET:\n"
                    + packet
                    + "\n\nINDEPENDENT CRITIC REPORT:\n"
                    + critic
                    + "\n\nDRAFT TO CORRECT:\n"
                    + draft
                ),
            },
        ]
        revision_response = _chat(model=model, messages=revision_messages, num_ctx=num_ctx, num_predict=1100)
        total_prompt_tokens += int(revision_response.get("prompt_eval_count") or 0)
        total_output_tokens += int(revision_response.get("eval_count") or 0)
        final_text = str((revision_response.get("message") or {}).get("content") or "").strip()

        if strict_benchmark:
            validation_error = v2._benchmark_validation_error(final_text)
            if not validation_error and ready_gate == "BLOCK" and "READY TO IMPLEMENT" in final_text.split("7. VERDETTO", 1)[-1]:
                validation_error = "critic blocked READY but final answer still used READY TO IMPLEMENT"

            if validation_error:
                retry_messages = revision_messages + [
                    {"role": "assistant", "content": final_text},
                    {
                        "role": "user",
                        "content": (
                            "FINAL ANSWER REJECTED: "
                            + validation_error
                            + ". Rewrite once. Preserve evidence corrections and the READY_GATE rule. "
                            "Use all seven exact headings and exactly one allowed verdict."
                        ),
                    },
                ]
                retry = _chat(model=model, messages=retry_messages, num_ctx=num_ctx, num_predict=1100)
                total_prompt_tokens += int(retry.get("prompt_eval_count") or 0)
                total_output_tokens += int(retry.get("eval_count") or 0)
                final_text = str((retry.get("message") or {}).get("content") or "").strip()
                validation_error = v2._benchmark_validation_error(final_text)
                if not validation_error and ready_gate == "BLOCK" and "READY TO IMPLEMENT" in final_text.split("7. VERDETTO", 1)[-1]:
                    validation_error = "critic blocked READY but final answer still used READY TO IMPLEMENT"

    elapsed = time.perf_counter() - started
    return {
        "runtime": "v4-critical-gate",
        "model": model,
        "elapsed_seconds": round(elapsed, 1),
        "prompt_tokens_total_across_rounds": total_prompt_tokens,
        "output_tokens_total_across_rounds": total_output_tokens,
        "required_docs_read": draft_result.get("required_docs_read", []),
        "evidence_gate_remaining": gap,
        "final_validation_error": validation_error,
        "tool_calls": int(draft_result.get("tool_calls") or 0),
        "unique_tool_calls": int(draft_result.get("unique_tool_calls") or 0),
        "evidence_packet_chars": len(packet),
        "ready_gate": ready_gate,
        "critic": critic,
        "draft": draft,
        "quality_signals": _quality_signals(final_text, critic),
        "trace": trace,
        "final": final_text or "NO FINAL ANSWER PRODUCED",
    }


def save_result(result: dict[str, Any]) -> Path:
    target = Path(tempfile.gettempdir()) / "riftward_agent_a_readonly_v4_result.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only Agent A v4 with independent critical verification gate.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--benchmark", action="store_true")
    mode.add_argument("--ask", type=str)
    parser.add_argument("--model", default=core.DEFAULT_MODEL)
    parser.add_argument("--ctx", type=int, default=8192)
    parser.add_argument("--max-research-rounds", type=int, default=5)
    args = parser.parse_args()

    task = core.BENCHMARK_TASK if args.benchmark else str(args.ask)
    print("Riftward Agent A v4 - READ ONLY / CRITICAL GATE")
    print(f"Repository: {core.ROOT}")
    print(f"Model: {args.model}")
    print("Research -> persistent evidence -> independent critic -> corrected final answer.\n")

    try:
        result = run_agent_v4(
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
    print(f"Evidence gate remaining: {result['evidence_gate_remaining'] or 'NONE'}")
    print(f"Critical READY gate: {result['ready_gate']}")
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
