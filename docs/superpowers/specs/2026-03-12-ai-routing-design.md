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

**Config file check:** The hook also looks for an optional config file (see Component 4). If found, it serializes the config into the session context as a structured block:

```
AI Routing Config: {"overrides":{"mechanical":"codex"},"disabled":["gemini"],"timeout":300}
```

This is appended as a separate line after the `Available AI CLIs:` line. The routing skill parses both lines to determine available AIs and any user overrides.

### Component 2: Routing Skill (skills/ai-routing/SKILL.md)

A new skill that the controller consults when dispatching subagents. Contains the capability map and routing logic.

**Task categories (canonical list):**

| Category | Description | Default AI |
|----------|-------------|------------|
| `ui-design` | UI components, pages, visual layouts, frontend design | Gemini |
| `research` | Large codebase analysis, documentation, research tasks | Gemini |
| `implementation` | Multi-file implementation, repo-scale refactoring, heavy execution | Codex |
| `mechanical` | Boilerplate, simple bug fixes, repetitive refactors, test scaffolding, renaming | Vibe |
| `review` | Spec compliance, code quality, architecture review | Claude |
| `debugging` | Root cause analysis, complex debugging, investigation | Claude |
| `architecture` | Design decisions, complex reasoning, long-context work | Claude |

This canonical list is the single source of truth. Both the routing logic and the user config schema reference these exact category slugs.

**How the controller classifies tasks:** The controller reads the task description and matches it against the category definitions above. This is a judgment call by the controller — it reasons about the task's characteristics (file count, complexity, whether it's creative vs. mechanical, whether it requires deep understanding) and picks the best-fit category. The skill provides examples to guide this judgment:

- "Rename all occurrences of X to Y" → `mechanical`
- "Build a settings page with tabs and form validation" → `ui-design`
- "Refactor auth into 3 microservices" → `implementation`
- "Why does the server crash under load?" → `debugging`
- "Review this PR for quality" → `review`

**Capability map:**

| AI | Categories | Invoke via |
|----|-----------|------------|
| Claude (default) | `review`, `debugging`, `architecture` | Native Task tool (no change) |
| Gemini | `ui-design`, `research` | Bash (see Component 3) |
| Codex | `implementation` | Bash (see Component 3) |
| Vibe | `mechanical` | Bash (see Component 3) |

**Routing decision flow:**

1. Classify the task into a category (controller judgment, guided by examples above)
2. Does the user config override routing for this category? → use override
3. Is the default AI for this category available? (check session context from hook)
4. If available → route to that AI
5. If not available → fall back to Claude (native Task tool)
6. If chosen AI is Claude → dispatch via native Task tool (unchanged)
7. If chosen AI is external → invoke via Bash with task prompt
8. If external AI fails → fall back to native Task tool

**Scope constraint:** Only tasks in categories defaulting to an external AI (`ui-design`, `research`, `implementation`, `mechanical`) get routed externally. Tasks in categories defaulting to Claude (`review`, `debugging`, `architecture`) always stay with Claude via native Task tool. This ensures reviews and complex reasoning use Claude's strengths — nuanced judgment, signaling when stuck, and reliable spec compliance.

### Component 3: External AI Invocation

When the controller routes a task to an external CLI, it invokes it via Bash and captures the result.

**Invocation templates:**

```bash
# All CLIs receive prompts via stdin to avoid shell argument length limits
echo "<prompt>" | codex exec -
echo "<prompt>" | gemini -p
echo "<prompt>" | vibe -p
```

**Flags verified on 2026-03-12** against installed CLI versions. If a CLI updates its flags later, only the skill file needs updating.

**Prompt construction:** The controller builds the same prompt structure it would for a native Task subagent (using the existing `implementer-prompt.md`, etc.), but appends a **report format instruction** at the end:

```
## IMPORTANT: Report Format

When you are done, you MUST end your response with a report in this exact format:

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
- What you implemented (or what you attempted, if blocked)
- What you tested and test results
- Files changed
- Any issues or concerns
```

This instruction is appended only when dispatching to external CLIs — native Task subagents already understand the protocol from the prompt templates. External AIs follow instructions well enough that explicitly requesting the format produces parseable output.

**Output capture:** The controller reads stdout from the Bash call and parses the response looking for the standard report format (Status: DONE/BLOCKED/NEEDS_CONTEXT/DONE_WITH_CONCERNS). Since external AIs are explicitly instructed to use this format, output is reliably parseable.

**Failure detection:**

- Non-zero exit code → failure
- Timeout (configurable, default 5 minutes) → failure
- No recognizable status in output → treat as DONE_WITH_CONCERNS, let review stage catch issues

**On failure:** Controller logs which AI failed and why, then re-dispatches the same prompt via native Task tool (Claude). No retry with the same external AI.

**Working directory:** External CLIs run in the same project directory, matching existing behavior where native subagents work in the same directory.

### Component 4: User Configuration

An optional config file lets users override routing defaults. Project-local takes precedence over global.

**Locations:**

1. `.superpowers/ai-routing.json` (project-local — takes precedence)
2. `~/.config/superpowers/ai-routing.json` (global)

**Merge semantics:** If both files exist, the project-local config is a deep merge over the global config:
- `overrides`: project keys override matching global keys; unmatched global keys are preserved
- `disabled`: arrays are concatenated (union of both lists)
- `timeout`: project value wins if present, else global value, else default (300)

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
  "timeout": 300
}
```

**Fields (all optional):**

- `overrides` — map task categories to preferred AI. Categories are the canonical list from Component 2: `ui-design`, `research`, `implementation`, `mechanical`, `review`, `debugging`, `architecture`
- `disabled` — AIs to never use, even if detected
- `timeout` — seconds before an external CLI call is considered failed (default 300). Note: repo-scale tasks routed to Codex may need longer timeouts — users should increase this for large projects

Missing config = pure automatic routing. Conversational overrides ("use Gemini for this one") always take precedence over config — including the `disabled` list. If a user explicitly asks for an AI, honor it even if it's disabled in config.

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
