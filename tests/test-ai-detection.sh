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

# Check if any AI CLIs are actually installed
has_cli=false
for cli in codex gemini vibe; do
    if command -v "$cli" >/dev/null 2>&1; then
        has_cli=true
        break
    fi
done

# If CLIs are installed, the detection line should appear
# If no CLIs are installed, the hook should still produce valid JSON (graceful no-op)
if [ "$has_cli" = true ]; then
    if echo "$output" | grep -q "Available AI CLIs"; then
        echo "PASS: AI CLI detection context found (CLIs are installed)"
    else
        echo "FAIL: AI CLI detection context not found despite CLIs being installed"
        exit 1
    fi
else
    if echo "$output" | grep -q "Available AI CLIs"; then
        echo "FAIL: AI CLI detection context found but no CLIs are installed"
        exit 1
    else
        echo "PASS: No AI CLI detection context (no CLIs installed, graceful no-op)"
    fi
fi

# Verify JSON is always valid regardless of CLI availability
echo "$output" | python3 -c "import sys, json; d = json.load(sys.stdin); print('PASS: Valid JSON regardless of CLI availability')"

# Test config file detection
config_dir=$(mktemp -d)
cat > "${config_dir}/ai-routing.json" <<'CONF'
{"overrides":{"mechanical":"codex"},"disabled":["gemini"],"timeout":300}
CONF

# Run hook with config path override for testing
output_config=$(HIVEMIND_AI_CONFIG="${config_dir}/ai-routing.json" bash "$HOOK" 2>&1)

if echo "$output_config" | grep -q "AI Routing Config"; then
    echo "PASS: Config detection found"
else
    echo "FAIL: Config detection not found"
    exit 1
fi

# Verify config output is still valid JSON
echo "$output_config" | python3 -c "import sys, json; json.load(sys.stdin)" || {
    echo "FAIL: Hook output with config is not valid JSON"
    exit 1
}
echo "PASS: Valid JSON with config"

rm -rf "$config_dir"

echo "All tests passed"
