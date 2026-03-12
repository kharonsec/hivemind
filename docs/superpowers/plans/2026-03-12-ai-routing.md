# AI Routing Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable superpowers to detect available AI CLIs and route subagent tasks to the most appropriate AI based on task characteristics.

**Architecture:** Hook-based detection at session start, a new routing skill with capability map and invocation templates, optional user config with deep merge semantics.

**Tech Stack:** Bash (hook detection), Markdown (skill), JSON (config)

**Spec:** `docs/superpowers/specs/2026-03-12-ai-routing-design.md`

---

## Chunk 1: CLI Detection in Session-Start Hook

### Task 1: Verify CLI invocation flags

**Files:**
- None modified — research task only

- [ ] **Step 1: Check which AI CLIs are installed on this system**

Run:
```bash
command -v codex && codex --help 2>&1 | head -30 || echo "codex not installed"
command -v gemini && gemini --help 2>&1 | head -30 || echo "gemini not installed"
command -v vibe && vibe --help 2>&1 | head -30 || echo "vibe not installed"
```

- [ ] **Step 2: Identify the correct non-interactive flags for each installed CLI**

For each installed CLI, find the flag that:
- Accepts a prompt via stdin (piped input)
- Runs without interactive prompts
- Outputs results to stdout

Document the verified flags. If a CLI doesn't support stdin piping, document the alternative (e.g., `-p` flag for prompt argument).

- [ ] **Step 3: Record findings and update SKILL.md flags**

Create a temporary file `docs/superpowers/plans/ai-routing-cli-flags.md` with the verified flags for each CLI. These findings will be used in Task 4 Step 2 to ensure the invocation templates in the SKILL.md are correct.

### Task 2: Add CLI detection to session-start hook

**Files:**
- Modify: `hooks/session-start` (insert after `escape_for_json` function definition at line 31, before `using_superpowers_escaped` at line 33)

- [ ] **Step 1: Write a test to verify detection works**

Create a test script that mocks `command -v` and verifies the hook outputs the expected context:

```bash
#!/usr/bin/env bash
# tests/test-ai-detection.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/session-start"

# Run the hook and capture output
output=$(bash "$HOOK" 2>&1)

# Verify JSON is valid
echo "$output" | python3 -c "import sys, json; json.load(sys.stdin)" || {
    echo "FAIL: Hook output is not valid JSON"
    exit 1
}

# Verify the output contains AI CLI detection context
if echo "$output" | grep -q "Available AI CLIs"; then
    echo "PASS: AI CLI detection context found"
else
    echo "FAIL: AI CLI detection context not found"
    exit 1
fi

echo "All tests passed"

# Test negative case: hook still produces valid JSON when no CLIs detected
# (The Available AI CLIs line may or may not appear depending on what's installed,
# but the JSON must always be valid)
echo "$output" | python3 -c "import sys, json; d = json.load(sys.stdin); print('PASS: Valid JSON regardless of CLI availability')"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-ai-detection.sh`
Expected: FAIL — "AI CLI detection context not found" (detection not yet implemented)

- [ ] **Step 3: Add CLI detection logic to session-start hook**

Add the following after line 31 (after the `escape_for_json` function definition) in `hooks/session-start`. Note: `escape_for_json` is already defined in the hook — do not re-define it.

```bash
# Detect available AI CLIs
available_ais=""
for cli in codex gemini vibe; do
    if command -v "$cli" >/dev/null 2>&1; then
        if [ -n "$available_ais" ]; then
            available_ais="${available_ais}, ${cli}"
        else
            available_ais="$cli"
        fi
    fi
done

ai_detection_context=""
if [ -n "$available_ais" ]; then
    ai_detection_context="\\n\\nAvailable AI CLIs: ${available_ais}"
fi
```

Then append `${ai_detection_context}` to the `session_context` string (before the closing `</EXTREMELY_IMPORTANT>` tag):

Change the session_context line to include:
```bash
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n\n${warning_escaped}${ai_detection_context}\n</EXTREMELY_IMPORTANT>"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-ai-detection.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start tests/test-ai-detection.sh
git commit -m "feat: detect available AI CLIs at session start"
```

### Task 3: Add config file detection to session-start hook

**Files:**
- Modify: `hooks/session-start` (after CLI detection block from Task 2)

- [ ] **Step 1: Write a test for config detection**

Add to `tests/test-ai-detection.sh`:

```bash
# Test config file detection
config_dir=$(mktemp -d)
cat > "${config_dir}/ai-routing.json" <<'CONF'
{"overrides":{"mechanical":"codex"},"disabled":["gemini"],"timeout":300}
CONF

# Run hook with config path override for testing
output=$(SUPERPOWERS_AI_CONFIG="${config_dir}/ai-routing.json" bash "$HOOK" 2>&1)

if echo "$output" | grep -q "AI Routing Config"; then
    echo "PASS: Config detection found"
else
    echo "FAIL: Config detection not found"
    exit 1
fi

rm -rf "$config_dir"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-ai-detection.sh`
Expected: FAIL — "Config detection not found"

- [ ] **Step 3: Add config detection logic**

Add after the CLI detection block in `hooks/session-start`:

```bash
# Check for AI routing config (project-local overrides global)
ai_config=""
project_config=".hivemind/ai-routing.json"
global_config="${HOME}/.config/superpowers/ai-routing.json"
override_config="${SUPERPOWERS_AI_CONFIG:-}"

if [ -n "$override_config" ] && [ -f "$override_config" ]; then
    ai_config=$(cat "$override_config")
elif [ -f "$project_config" ]; then
    if [ -f "$global_config" ]; then
        # Deep merge: project over global (using python for JSON merge)
        ai_config=$(python3 -c "
import json, sys
g = json.load(open('$global_config'))
p = json.load(open('$project_config'))
m = {**g, **p}
if 'overrides' in g and 'overrides' in p:
    m['overrides'] = {**g['overrides'], **p['overrides']}
if 'disabled' in g and 'disabled' in p:
    m['disabled'] = list(set(g['disabled'] + p['disabled']))
print(json.dumps(m))
" 2>/dev/null || cat "$project_config")
    else
        ai_config=$(cat "$project_config")
    fi
elif [ -f "$global_config" ]; then
    ai_config=$(cat "$global_config")
fi

ai_config_context=""
if [ -n "$ai_config" ]; then
    escaped_config=$(escape_for_json "$ai_config")
    ai_config_context="\\nAI Routing Config: ${escaped_config}"
fi
```

Append `${ai_config_context}` after `${ai_detection_context}` in the session_context string.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-ai-detection.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start tests/test-ai-detection.sh
git commit -m "feat: detect and merge AI routing config at session start"
```

## Chunk 2: AI Routing Skill

### Task 4: Create the ai-routing skill

**Files:**
- Create: `skills/ai-routing/SKILL.md`

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p skills/ai-routing
```

- [ ] **Step 2: Write the SKILL.md file**

Create `skills/ai-routing/SKILL.md` with the following content:

```markdown
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
# Codex
echo "<full prompt with report format>" | codex --quiet

# Gemini
echo "<full prompt with report format>" | gemini --non-interactive

# Vibe
echo "<full prompt with report format>" | vibe --auto-approve
```

**NOTE:** The exact CLI flags above must match the installed versions. If a flag doesn't work, check `<cli> --help` for the correct non-interactive/quiet flag.

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
1. `.hivemind/ai-routing.json` (project)
2. `~/.config/hivemind/ai-routing.json` (global)

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
```

- [ ] **Step 3: Verify the skill file has valid frontmatter**

Run:
```bash
head -4 skills/ai-routing/SKILL.md
```

Expected: YAML frontmatter with `name: ai-routing` and `description:` fields.

- [ ] **Step 4: Commit**

```bash
git add skills/ai-routing/SKILL.md
git commit -m "feat: add ai-routing skill with capability map and routing logic"
```

### Task 5: Update using-superpowers to reference ai-routing

**Files:**
- Modify: `skills/using-superpowers/SKILL.md`

The using-superpowers skill should mention ai-routing so the controller knows to consult it before dispatching.

- [ ] **Step 1: Add a reference to ai-routing in the skill priority section**

After the "Skill Priority" section (around line 102), add a note:

```markdown
## AI Routing

When dispatching subagent tasks and external AI CLIs are available (check session context for `Available AI CLIs:`), consult the `ai-routing` skill to determine which AI should handle each task. This applies to both `subagent-driven-development` and `dispatching-parallel-agents` workflows.
```

- [ ] **Step 2: Verify the addition reads well in context**

Run:
```bash
sed -n '95,115p' skills/using-superpowers/SKILL.md
```

Verify the new section fits naturally between existing sections.

- [ ] **Step 3: Commit**

```bash
git add skills/using-superpowers/SKILL.md
git commit -m "feat: reference ai-routing skill from using-superpowers"
```

### Task 6: End-to-end manual test

**Files:**
- None modified — verification task only

- [ ] **Step 1: Run the session-start hook and verify full output**

```bash
bash hooks/session-start
```

Verify the JSON output contains:
- The existing using-superpowers skill content
- The `Available AI CLIs:` line (listing whichever CLIs are actually installed)
- The `AI Routing Config:` line (if a config file exists)

- [ ] **Step 2: Verify the ai-routing skill is discoverable**

```bash
ls skills/ai-routing/SKILL.md && echo "PASS: Skill file exists"
head -4 skills/ai-routing/SKILL.md
```

Expected: File exists with valid frontmatter.

- [ ] **Step 3: Run the full test suite**

```bash
bash tests/test-ai-detection.sh
```

Expected: All tests pass.

- [ ] **Step 4: Fix and commit if any step above failed**

If any verification step above failed, fix the issue and re-run that step. Commit with:
```bash
git add -A
git commit -m "fix: resolve issues found during ai-routing end-to-end test"
```

If all steps passed, skip this step — nothing to commit.
