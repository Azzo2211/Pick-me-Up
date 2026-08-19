# Agent A workflow smoke test

Purpose: verify that Agent A can follow the repository workflow without touching gameplay code.

Expected behavior:
- read `AGENTS.md` before acting;
- treat Godot as the only active implementation;
- understand that Riftward is a full game in continuous development, not a fixed vertical slice;
- preserve existing systems unless the user explicitly changes them;
- work on a dedicated `agent-a/...` branch;
- use pull requests for meaningful changes;
- never merge to `main` without explicit user authorization.

This file is intentionally documentation-only and may be deleted after the smoke test is reviewed.
