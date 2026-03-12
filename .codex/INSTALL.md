# Installing Hivemind for Codex

Enable hivemind skills in Codex via native skill discovery. Just clone and symlink.

## Prerequisites

- Git

## Installation

1. **Clone the hivemind repository:**
   ```bash
   git clone https://github.com/kharonsec/hivemind.git ~/.codex/hivemind
   ```

2. **Create the skills symlink:**
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.codex/hivemind/skills ~/.agents/skills/hivemind
   ```

   **Windows (PowerShell):**
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.agents\skills"
   cmd /c mklink /J "$env:USERPROFILE\.agents\skills\hivemind" "$env:USERPROFILE\.codex\hivemind\skills"
   ```

3. **Restart Codex** (quit and relaunch the CLI) to discover the skills.

## Migrating from old bootstrap

If you installed hivemind before native skill discovery, you need to:

1. **Update the repo:**
   ```bash
   cd ~/.codex/hivemind && git pull
   ```

2. **Create the skills symlink** (step 2 above) — this is the new discovery mechanism.

3. **Remove the old bootstrap block** from `~/.codex/AGENTS.md` — any block referencing `hivemind-codex bootstrap` is no longer needed.

4. **Restart Codex.**

## Verify

```bash
ls -la ~/.agents/skills/hivemind
```

You should see a symlink (or junction on Windows) pointing to your hivemind skills directory.

## Updating

```bash
cd ~/.codex/hivemind && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.agents/skills/hivemind
```

Optionally delete the clone: `rm -rf ~/.codex/hivemind`.
