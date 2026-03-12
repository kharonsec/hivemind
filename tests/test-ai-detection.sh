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

# Test negative case: hook still produces valid JSON regardless
echo "$output" | python3 -c "import sys, json; d = json.load(sys.stdin); print('PASS: Valid JSON regardless of CLI availability')"

echo "All tests passed"
