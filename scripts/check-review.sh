#!/bin/bash
# SessionStart hook: surface a new Copilot review exactly once.
#
# Nothing can wake Claude Code from a file change while it is idle, so this
# fires at the next session start instead: it hashes the review file, compares
# against the last hash it reported, and injects a notice when they differ.
# The state file is updated on report, so a given review is announced once and
# does not nag afterwards.
set -euo pipefail

cd "$(dirname "$0")/.."

REVIEW="code-review-copilot.md"
STATE=".claude/.review-seen"

[ -f "$REVIEW" ] || exit 0

HASH=$(shasum -a 256 "$REVIEW" | cut -d' ' -f1)
PREV=$(cat "$STATE" 2>/dev/null || true)

[ "$HASH" = "$PREV" ] && exit 0

mkdir -p .claude
printf '%s' "$HASH" >"$STATE"

if [ -z "$PREV" ]; then
    MESSAGE="A Copilot code review exists at $REVIEW and has not been seen in this checkout yet. Read it before continuing milestone work."
else
    MESSAGE="$REVIEW CHANGED since the last session — Copilot has posted a new review. Read it and address the findings before starting new work. Verify each finding against the code rather than accepting it: past reviews have been right about the defect but wrong about the cause, and have missed related bugs nearby."
fi

jq -cn --arg m "$MESSAGE" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
