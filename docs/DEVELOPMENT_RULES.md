# DEVELOPMENT_RULES.md

## Primary implementation
The Godot project under `godot/` is the primary implementation target unless the user explicitly asks for legacy web work.

## Change discipline
- Inspect before editing.
- Prefer the smallest change that fully solves the request.
- Reuse current signals, resources, data models, helpers, and naming conventions.
- Do not rewrite working systems merely to make them stylistically different.
- Keep unrelated refactors out of feature work.
- Preserve backward compatibility for saves/data where practical.

## Testing
For web/core regressions, the repository currently exposes:

```powershell
node tests/core.test.js
```

For Godot work, use the existing test/runner scripts under `godot/tests/` when relevant and run a project smoke test when the environment supports Godot.

When a requested change touches deterministic generation, summon, permadeath, economy, save state, or progression, add or run focused regression checks.

## Branching
Default branch naming for Agent A:

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
