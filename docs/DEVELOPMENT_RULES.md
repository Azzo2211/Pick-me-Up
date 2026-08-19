# DEVELOPMENT_RULES.md

## Primary implementation
The Godot project under `godot/` is the active implementation target. The historical web code is reference material only unless the user explicitly asks for inspection or migration work.

## Change discipline
- Inspect before editing.
- Prefer the smallest change that fully solves the request.
- Reuse current signals, resources, data models, helpers, and naming conventions.
- Do not rewrite working systems merely to make them stylistically different.
- Keep unrelated refactors out of feature work.
- Preserve backward compatibility for saves/data where practical.

## Testing
For historical web/core regression checks, the repository currently exposes:

```powershell
node tests/core.test.js
```

Do not treat those web tests as proof that the active Godot game is working.

For active Godot work, use the existing test/runner scripts under `godot/tests/` when relevant and run a project smoke test when the environment supports Godot.

When a requested change touches deterministic generation, summon, permadeath, economy, save state, or progression, add or run focused regression checks.

## Branching
Use a dedicated branch for meaningful work. Role-specific conventions may refine the prefix; for example Agent A prefers:

```text
agent-a/<short-feature-name>
```

Do not merge directly to `main` without explicit user authorization.

## Completion report
At the end of meaningful work, report:
1. what changed;
2. files changed;
3. tests/checks run and their result;
4. known risks or limitations;
5. whether a PR is ready for review.

## Ambiguity handling
Do not ask the user to make technical decisions that can be resolved safely by inspecting the repository.
Ask only when the answer materially changes product behavior, could destroy data/working behavior, or involves a genuine design choice not resolved by the docs.

## Living documentation
The Game Bible is expected to evolve. If the user's newest instruction materially changes a documented rule, system, art direction, architecture, or current-state statement, update the relevant documentation as part of the same meaningful change when appropriate. Small implementation details do not require Game Bible edits.

## Protected design behavior
Treat the following as regression-sensitive unless explicitly changed:
- indirect Master control;
- autonomous hero behavior;
- party size and formation rules;
- deterministic stage behavior;
- permadeath and persistent consequences;
- existing summon/economy locks;
- hero identity uniqueness;
- save integrity;
- physical hub philosophy.

## Reference IP boundary
Use external inspiration only at the level of mechanics, pacing, atmosphere, or design principles. Never implement protected names, characters, lore, dialogue, exact UI, copied assets, or near-identical visual layouts from another work.
