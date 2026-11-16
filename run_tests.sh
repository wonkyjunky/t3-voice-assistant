#!/bin/bash
# Runs every test with the Python the scripts use.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
status=0
for test_file in "$HERE"/tests/test_*.py; do
  echo "== $(basename "$test_file")"
  /opt/homebrew/bin/python3 "$test_file" 2>&1 | grep -E '^(Ran|OK|FAILED|FAIL:|ERROR:)' || true
  /opt/homebrew/bin/python3 "$test_file" >/dev/null 2>&1 || status=1
done
# The Swift apps' caption, sound bar and transcript logic.
for runner in "$HERE"/tests/run_*_test.sh; do
  echo "== $(basename "$runner")"
  "$runner" 2>&1 | tail -1
  "$runner" >/dev/null 2>&1 || status=1
done
exit "$status"
