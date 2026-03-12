# AI Routing: Cross-CLI Detection and Intelligent Task Routing

## Summary

Add the ability for superpowers to detect which AI coding CLIs are available on the system (Codex, Gemini, Vibe) and route subagent tasks to the most appropriate AI based on task characteristics. The controller AI (Claude) remains the orchestrator — it delegates specific implementation tasks to external AIs via Bash when they're better suited, while keeping reviews and complex reasoning for itself.

## Motivation

Currently, superpowers dispatches all subagents via the host platform's native mechanism. If you're in Claude Code, every subagent is Claude. But different AIs have different strengths:

- **Gemini** excels at UI design, large codebase comprehension (1M context), research/documentation
- **Codex** excels at execution thoroughness, repo-scale refactoring, multi-file implementation
- **Vibe** excels at fast mechanical tasks, boilerplate, repetitive refactors — at 7x cheaper than Claude

By routing tasks to the most capable (or most cost-effective) AI, we get better results and lower costs without changing the existing dispatch workflow.

## Architecture

### Component 1: Detection Layer (session-start hook)

The existing `session-start` hook is extended with CLI detection. After reading the `using-superpowers` skill content, it checks for available AI CLIs and injects the results into the session context.

**Detection:**

```bash
command -v codex   → codex available (yes/no)
command -v gemini  → gemini available (yes/no)
command -v vibe    → vibe available (yes/no)
```

**Context injection:** A line is appended to the existing `session_context` string:

```
Available AI CLIs: codex, gemini, vibe
```

No structural changes to the hook's JSON output format. The detection adds ~15 lines of bash to the existing hook.

**Config file check:** The hook also looks for an optional config file (see Component 4) and includes any overrides in the context.

### Component 2: Routing Skill (skills/ai-routing/SKILL.md)

A new skill that the controller consults when dispatching subagents. Contains the capability map and routing logic.

**Capability map:**

| AI | Route when task is... | Invoke via |
|----|----------------------|------------|
| Claude (default) | Architecture, debugging, code review, complex reasoning, long-context work | Native Task tool (no change) |
| Gemini | UI design, large codebase analysis, research/documentation, visual tasks | `Bash: gemini --non-interactive "<prompt>"` |
| Codex | Repo-scale refactoring, multi-file implementation, heavy execution tasks | `Bash: echo "<prompt>" \| codex --quiet --model gpt-5.4` |
| Vibe | Mechanical/boilerplate, simple bug fixes, repetitive refactors, test scaffolding | `Bash: vibe --auto-approve "<prompt>"` |

**Routing decision flow:**

1. Is this AI available? (check session context from hook)
2. Does the user config override routing for this task type? → use override
3. Match task characteristics to capability map → pick best available AI
4. If chosen AI is Claude → dispatch via native Task tool (unchanged)
5. If chosen AI is external → invoke via Bash with task prompt
6. If external AI fails → fall back to native Task tool

**Scope constraint:** Only implementation tasks get routed externally. Spec reviews and code quality reviews always stay with Claude (native Task tool). Reviews require careful reasoning that Claude excels at.

### Component 3: External AI Invocation

When the controller routes a task to an external CLI, it invokes it via Bash and captures the result.

**Invocation templates:**

```bash
# Codex — quiet mode, pipe prompt via stdin
echo "<prompt>" | codex --quiet --model gpt-5.4

# Gemini — non-interactive, prompt as argument
gemini --non-interactive "<prompt>"

# Vibe — auto-approve tools, prompt as argument
vibe --auto-approve "<prompt>"
```

**Prompt construction:** The controller builds the exact same prompt it would for a native Task subagent (using the existing `implementer-prompt.md`, `spec-reviewer-prompt.md`, etc.). The prompt content doesn't change — only the delivery mechanism.

**Output capture:** The controller reads stdout from the Bash call and parses the response looking for the standard report format (Status: DONE/BLOCKED/NEEDS_CONTEXT/DONE_WITH_CONCERNS).

**Failure detection:**

- Non-zero exit code → failure
- Timeout (configurable, default 5 minutes) → failure
- No recognizable status in output → treat as DONE_WITH_CONCERNS, let review stage catch issues

**On failure:** Controller logs which AI failed and why, then re-dispatches the same prompt via native Task tool (Claude). No retry with the same external AI.

**Working directory:** External CLIs run in the same project directory, matching existing behavior where native subagents work in the same directory.

### Component 4: User Configuration

An optional config file lets users override routing defaults. Project-local takes precedence over global.

**Locations:**

1. `.superpowers/ai-routing.json` (project-local)
2. `~/.config/superpowers/ai-routing.json` (global)

**Format:**

```json
{
  "overrides": {
    "ui-design": "gemini",
    "mechanical": "vibe",
    "implementation": "codex",
    "review": "claude"
  },
  "disabled": ["codex"],
  "timeout": 300,
  "fallback": "claude"
}
```

**Fields (all optional):**

- `overrides` — map task categories to preferred AI. Categories: `ui-design`, `research`, `implementation`, `mechanical`, `review`, `debugging`, `architecture`
- `disabled` — AIs to never use, even if detected
- `timeout` — seconds before an external CLI call is considered failed (default 300)
- `fallback` — which AI to fall back to on failure (default `claude`)

Missing config = pure automatic routing. Conversational overrides ("use Claude for this one") always take precedence over config.

### Component 5: Integration with Existing Skills

**What changes:**

- `hooks/session-start` — extended with CLI detection (~15 lines of bash)
- `skills/ai-routing/SKILL.md` — new skill with capability map, routing logic, invocation templates, config format documentation

**What does NOT change:**

- `skills/subagent-driven-development/SKILL.md`
- `skills/dispatching-parallel-agents/SKILL.md`
- `skills/executing-plans/SKILL.md`
- `implementer-prompt.md`, `spec-reviewer-prompt.md`, `code-quality-reviewer-prompt.md`
- `agents/code-reviewer.md`
- `hooks/hooks.json`

## Task Routing Examples

**Example 1: "Add a dashboard page with charts"**
→ UI design task → routed to Gemini (if available), else Claude

**Example 2: "Rename userId to user_id across the entire codebase"**
→ Mechanical refactor → routed to Vibe (cheapest/fastest), else Claude

**Example 3: "Refactor the auth module into 3 separate services"**
→ Multi-file implementation with architectural concerns → routed to Codex for implementation, Claude for review

**Example 4: "Debug why the WebSocket server drops connections after 30min"**
→ Complex debugging → stays with Claude (controller handles directly)

## Design Decisions

**Why reviews stay with Claude:** Reviews require nuanced judgment about spec compliance, architecture quality, and code standards. External AIs may quietly go off-script (Codex) or rush without reasoning (Gemini). Claude signals when something is wrong — essential for review gates.

**Why no changes to dispatch skills:** The routing decision is orthogonal to the dispatch process. Subagent-driven-development defines *what* to dispatch (implementer, then spec review, then code review). AI-routing defines *where* to dispatch it. Keeping them separate means either can evolve independently.

**Why fallback to Claude on failure:** External CLIs can fail for many reasons (auth issues, rate limits, network). Blocking progress on an external tool failure would be worse than using a slightly less optimal AI. Claude is always available as the host platform.

**Why config is optional:** Smart defaults should work for most users. Config exists for power users who know their preferences or have cost constraints.
