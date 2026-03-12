---
name: ai-routing
description: "Use when dispatching subagent tasks to determine which AI CLI should handle the task. Consult this skill before every subagent dispatch to route tasks to the most capable available AI."
---

# AI Routing

Route subagent tasks to the most appropriate available AI CLI based on task characteristics. The controller (Claude) remains the orchestrator — it delegates tasks to external AIs when they're better suited, while keeping reviews and complex reasoning for itself.

## Available AIs

Check your session context for the `Available AI CLIs:` line injected at session start. Only route to AIs that appear in that list. If no external AIs are available, all tasks use native Task tool (Claude).

## Task Categories

Classify each task into one of these categories before dispatching:

| Category | Description | Default AI | Why |
|----------|-------------|------------|-----|
| `ui-design` | UI components, pages, visual layouts, frontend design | Gemini | Best at design, 1M context for understanding large frontends |
| `research` | Large codebase analysis, documentation, research tasks | Gemini | 1M context window, strong factual accuracy, Google Search grounding |
| `implementation` | Multi-file implementation, repo-scale refactoring, heavy execution | Codex | Execution thoroughness, multi-file coordination |
| `mechanical` | Boilerplate, simple bug fixes, repetitive refactors, test scaffolding, renaming | Vibe | 7x cheaper than Claude, fast inference, handles mechanical work well |
| `review` | Spec compliance, code quality, architecture review | Claude | Nuanced judgment, signals when stuck, reliable spec compliance |
| `debugging` | Root cause analysis, complex debugging, investigation | Claude | Deep reasoning, long-context coherence |
| `architecture` | Design decisions, complex reasoning, long-context work | Claude | Architectural thinking, maintains context over long conversations |

## Classification Examples

- "Rename all occurrences of X to Y" → `mechanical` → Vibe
- "Build a settings page with tabs and form validation" → `ui-design` → Gemini
- "Refactor auth into 3 microservices" → `implementation` → Codex
- "Why does the server crash under load?" → `debugging` → Claude
- "Review this PR for quality" → `review` → Claude
- "Document the API endpoints" → `research` → Gemini
- "Add error handling to all API routes" → `mechanical` → Vibe
- "Design the plugin architecture" → `architecture` → Claude

When a task could fit multiple categories, pick the one that best matches the task's primary challenge. "Build a settings page" is primarily a UI design challenge, not a mechanical task, even though it involves writing code.

## Routing Decision Flow

1. **Classify** the task into a category using the table and examples above
2. **Check config overrides** — does the user config remap this category to a different AI?
3. **Check availability** — is the target AI in the `Available AI CLIs:` list?
4. **Route:**
   - If target AI is Claude → dispatch via native Task tool (no change to existing workflow)
   - If target AI is external and available → invoke via Bash (see Invoking External AIs below)
   - If target AI is external but unavailable → fall back to native Task tool (Claude)
5. **On failure** — if external AI errors out or times out, fall back to native Task tool. Do not retry the same external AI.

**Announce your routing decision:** Before dispatching, briefly state which AI you're routing to and why. Example: "Routing to Vibe — this is a mechanical rename task."

## Invoking External AIs

Build the same prompt you would for a native Task subagent (using the standard prompt templates from subagent-driven-development), then append this report format instruction:

~~~
## IMPORTANT: Report Format

When you are done, you MUST end your response with a report in this exact format:

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
- What you implemented (or what you attempted, if blocked)
- What you tested and test results
- Files changed
- Any issues or concerns
~~~

Invoke via Bash, piping the full prompt via stdin:

```bash
# Codex — exec mode, read prompt from stdin
echo "<full prompt with report format>" | codex exec -

# Gemini — headless prompt mode
echo "<full prompt with report format>" | gemini -p

# Vibe — programmatic mode (auto-approves tools)
echo "<full prompt with report format>" | vibe -p
```

**NOTE:** The exact CLI flags above were verified against installed versions on 2026-03-12. If a flag doesn't work after a CLI update, check `<cli> --help` for the correct non-interactive flag.

Parse the stdout for the Status line. If no recognizable status is found, treat the result as DONE_WITH_CONCERNS and let the review stage catch any issues.

## Failure Handling

| Failure | Detection | Action |
|---------|-----------|--------|
| CLI not found | Non-zero exit, "command not found" | Fall back to Claude |
| CLI error | Non-zero exit code | Log error, fall back to Claude |
| Timeout | No response within configured timeout (default 300s) | Kill process, fall back to Claude |
| Unparseable output | No Status line in stdout | Treat as DONE_WITH_CONCERNS |

**Never** retry the same external AI after failure. Fall back to Claude and move on.

## Scope Constraints

- **Only implementation tasks** (categories: `ui-design`, `research`, `implementation`, `mechanical`) get routed externally
- **Reviews always stay with Claude** — spec compliance and code quality reviews use native Task tool regardless of config
- The controller never delegates itself — architecture, debugging, and review stay with Claude

## User Configuration

Users can override routing defaults via an optional config file. Check your session context for the `AI Routing Config:` line.

**Config locations** (project-local takes precedence, deep merged over global):
1. `.superpowers/ai-routing.json` (project)
2. `~/.config/superpowers/ai-routing.json` (global)

**Format:**

```json
{
  "overrides": {
    "mechanical": "codex",
    "ui-design": "claude"
  },
  "disabled": ["gemini"],
  "timeout": 600
}
```

- `overrides` — remap categories to different AIs
- `disabled` — never use these AIs, even if detected
- `timeout` — seconds before external CLI call is killed (default 300)

**Conversational overrides always win.** If the user says "use Gemini for this," honor it even if Gemini is in the `disabled` list.
