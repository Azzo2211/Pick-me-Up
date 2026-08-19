# Agent A — Local Read-Only Runtime

This folder contains the first executable local prototype of **Agent A**, the independent second Senior Game Engineer defined in `docs/AGENT_A.md`.

## Current scope

This prototype is deliberately **read-only**. It can:

- read the shared repository instructions and Agent A role;
- list real files in the repository;
- search literal text across real repository files;
- read real text/code files with line numbers;
- use those tools in an autonomous multi-turn loop through local Ollama;
- refuse to finish the standard benchmark until it has read the required project documents, searched the repository, and inspected at least one real Godot `.gd` file;
- save a JSON trace of the run in the Windows temporary folder.

It cannot currently:

- edit files;
- run shell commands;
- launch Godot;
- run tests;
- use Git for writes/branches/commits;
- create pull requests.

Those capabilities are intentionally excluded from this first benchmark. We first need to measure whether repository tools materially improve the local model's engineering judgment before giving it write access.

## Requirements

- Windows, macOS, or Linux with Python 3.10+.
- Ollama running locally.
- The desired Ollama model already downloaded.

The default model is:

```text
qwen3.5:9b
```

No OpenAI API key is used by this prototype.

## Standard benchmark

From the repository root:

```powershell
python .\agent-a\readonly_agent.py --benchmark
```

If `python` is not available but the Windows Python launcher is:

```powershell
py -3 .\agent-a\readonly_agent.py --benchmark
```

The agent will print each repository tool call, followed by its final answer and run statistics.

The complete trace is written outside the repository to:

```text
%TEMP%\riftward_agent_a_readonly_result.json
```

This avoids creating benchmark noise in the worktree.

## Custom read-only question

Example:

```powershell
python .\agent-a\readonly_agent.py --ask "Analizza il sistema di evocazione attuale e indicami i principali rischi di regressione. Non modificare nulla."
```

## Context size

The default context is 8192 tokens because the current local hardware test uses a 6 GB laptop GPU and 16 GB system RAM. It can be changed explicitly:

```powershell
python .\agent-a\readonly_agent.py --benchmark --ctx 8192
```

Increasing context can increase memory use and execution time.

## Safety design

All repository paths are resolved and checked to remain inside the Riftward repository. The runtime exposes only three tools to the model:

```text
list_files
read_file
search_text
```

There is no generic shell tool and no write tool in this version.

## Next gate

Do not add editing/shell/Git capabilities merely because this prototype runs. First compare the read-only benchmark result with the earlier prompt-only baseline. If repository-grounded analysis improves enough, the next phase can add controlled engineering tools with explicit safety gates.
