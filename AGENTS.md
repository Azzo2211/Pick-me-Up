# AGENTS.md — Riftward Repository Instructions

## Purpose
These are the shared engineering instructions for **Riftward: The Last Ascent**. They apply to any coding agent or developer working in this repository, including Codex and Agent A.

## Core operating rules
1. This is an existing project. Inspect the current implementation before changing anything.
2. Prefer modifying and extending working systems over rewriting them from scratch.
3. The Godot project under `godot/` is the **only active game implementation**. Do not develop the old web version unless the user explicitly asks you to inspect historical code for reference.
4. Read the relevant project documentation in `docs/` before making changes that affect game design, progression, art direction, facilities, combat, economy, or UX.
5. The user's newest explicit instruction has priority over older documentation and code assumptions.
6. The project documentation is a living source of truth, not an immutable specification. The user may add, remove, replace, or redesign systems during development.
7. When a new user decision materially changes product direction, gameplay rules, art direction, architecture, or documented current state, update the relevant file in `docs/` when appropriate.
8. Do not invent design requirements when the repository or project docs can answer them.
9. If a request is technically clear enough to implement, do not block on unnecessary questions. Inspect the code and proceed.
10. Keep changes scoped. Do not refactor unrelated systems unless required for correctness.
11. Preserve existing save/data compatibility whenever reasonably possible. If a migration is required, explain it.
12. Run relevant Godot tests or smoke checks after changes. If a test cannot be run, state why.
13. Do not silently remove working features.
14. Commit directly to `main` (user decision, 2026-11-04). Stay inside your department's folders as listed in `REPARTI.md`.
15. Treat the current content as the present state of a game in continuous development, **not as a fixed vertical slice or final scope**.

## Git workflow
- Work directly on `main`: no feature branches or pull requests unless the user asks for one.
- Read `REPARTI.md` first and touch only the folders and files your department owns. Ask the owning department for changes elsewhere.
- Always `git pull origin main` before committing, then commit and push. If a pull conflicts in a file you do not own, stop and ask instead of resolving it.
- Before editing, inspect recent relevant files and recent commits on `main`, and read `docs/DIARIO.md` (shared work journal, in Italian).
- When you start and when you finish a piece of work, add or update your entry at the top of `docs/DIARIO.md` (owner request, 2026-11-05), so the other agents see what you are doing.
- After implementation, summarize changed files, tests run, known risks, and follow-up work.
- Never use destructive Git operations such as hard resets or cleaning untracked files unless the user explicitly authorizes them and the consequences are understood.

## Design priority order
When sources conflict, use this order:
1. Newest explicit user instruction
2. `docs/GAME_VISION.md`
3. `docs/GAME_SYSTEMS.md`
4. `docs/ART_DIRECTION.md`
5. `docs/DEVELOPMENT_RULES.md`
6. `docs/CURRENT_STATE.md`
7. Existing code and legacy documentation
8. Your own assumptions

## Project identity and originality
Riftward is an original game inspired by the **systemic feel** of autonomous squad-management/gacha tower-climb fiction, including the reference concept the user calls “Pick Me Up”.
Do not copy protected characters, names, lore, dialogue, UI, logos, exact visual compositions, or proprietary assets from another work.
Preserve the desired design DNA while keeping implementation, world, terminology, UI, assets, and content original.

## Implementation style
- Favor clear, maintainable GDScript and small composable systems.
- Reuse existing classes, data structures, signals, and conventions.
- Avoid speculative abstractions that are not needed by the requested feature.
- Protect deterministic systems, permadeath behavior, save integrity, and progression rules from regressions.
- For visual hub work, treat buildings, paths, heroes, and facilities as a coherent physical space rather than an abstract menu.
- Prioritize the Godot architecture when moving or consolidating old logic.

## Before declaring a task complete
Check:
- Does it satisfy the user's request?
- Did it preserve unrelated working behavior?
- Did it follow the project docs?
- If the task materially changed the design, are the relevant docs still accurate?
- Did relevant tests pass?
- Is the change understandable to the next engineer?

## Role-specific instructions
Shared repository rules live here. Role-specific behavior belongs in separate documents, for example `docs/AGENT_A.md`. A role-specific document may add responsibilities or workflow preferences, but it must not weaken these shared project protections.
