# AI Routing: Verified CLI Flags

Verified on 2026-03-12 against installed versions.

## Codex

- **Binary:** `/home/eliott/.nvm/versions/node/v24.14.0/bin/codex`
- **Non-interactive mode:** `codex exec "<prompt>"` or `codex exec -` (reads from stdin)
- **Stdin piping:** `echo "<prompt>" | codex exec -`
- **Notes:** `exec` subcommand is the correct non-interactive mode (not `--quiet`)

## Gemini

- **Binary:** `/home/eliott/.nvm/versions/node/v24.14.0/bin/gemini`
- **Non-interactive mode:** `gemini -p "<prompt>"` (headless mode)
- **Stdin piping:** Stdin content is appended to `-p` flag content. Use `echo "<prompt>" | gemini -p`
- **Notes:** `-p`/`--prompt` flag, NOT `--non-interactive`

## Vibe

- **Binary:** `/home/eliott/.local/bin/vibe`
- **Non-interactive mode:** `vibe -p "<prompt>"` (programmatic mode, auto-approves all tools)
- **Stdin piping:** `echo "<prompt>" | vibe -p`
- **Notes:** `-p`/`--prompt` flag. Already auto-approves tools in programmatic mode (no need for `--auto-approve`)

## Corrected Invocation Templates

```bash
# Codex — exec mode, read prompt from stdin
echo "<prompt>" | codex exec -

# Gemini — headless prompt mode
echo "<prompt>" | gemini -p

# Vibe — programmatic mode (auto-approves tools)
echo "<prompt>" | vibe -p
```
