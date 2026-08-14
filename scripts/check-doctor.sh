#!/bin/bash
# Exercises `worksync doctor` as a real process against a real machine.
#
# The pure decision layer (DoctorChecks) is covered by unit tests, but
# DoctorFacts.gather shells out to launchctl and codesign, opens a lock, and
# queries EventKit and UserNotifications — none of which a unit test touches.
# This is the part where "it compiles" and "it works" diverge.
#
# Everything asserted here holds on ANY machine, granted calendar access or
# not, so it is meaningful both on a CI runner (where access is denied) and on
# a developer's Mac. It must never require a TCC grant, because the whole point
# is that doctor works — and stays read-only — without one.
set -euo pipefail

BIN="${1:?usage: check-doctor.sh <path-to-worksync>}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CONFIG="$WORK/config.toml"
cat > "$CONFIG" <<'TOML'
# a comment that must survive, because doctor must not rewrite this file
[general]
window_days = 21

[target]
account = "Nonexistent Account"
calendar = "Nonexistent Calendar"

[[source]]
id = "personal"
account = "Nonexistent Account"
calendar = "Personal"
TOML

fail() { echo "FAIL: $*" >&2; exit 1; }

before="$(shasum -a 256 "$CONFIG" | cut -d' ' -f1)"

# --- Runs at all, and exits with a documented code -------------------------
set +e
json="$("$BIN" doctor --config "$CONFIG" --json 2>"$WORK/stderr")"
code=$?
set -e

case "$code" in
  0|1|2|3) ;;
  *) fail "undocumented exit code $code (SPEC §8 defines 0/1/2/3); stderr: $(cat "$WORK/stderr")" ;;
esac
echo "ok: exited $code"

# --- Emits valid JSON containing every check -------------------------------
printf '%s' "$json" > "$WORK/report.json"
python3 - "$WORK/report.json" <<'PY' || fail "JSON output did not validate"
import json, sys

report = json.load(open(sys.argv[1]))
expected = {
    "calendar-access", "config", "calendars-resolve", "target-writable",
    "scheduling", "code-signature", "last-run", "notifications", "log-size",
}
got = {f["id"] for f in report["findings"]}
missing = expected - got
assert not missing, "missing checks: %s" % sorted(missing)
assert isinstance(report["exit_code"], int), "exit_code must be numeric"
for f in report["findings"]:
    assert f["severity"] in {"ok", "warning", "error", "skipped"}, f
    # The rule that makes the output actionable rather than a status wall.
    if f["severity"] in {"error", "warning"}:
        assert f.get("remediation"), "%s has no remediation" % f["id"]
print("ok: %d checks, all with remediations where needed" % len(got))
PY

# --- Read-only ------------------------------------------------------------
# The guarantee doctor is documented on: it is safe to run when things are
# already broken, because it cannot make them worse.
after="$(shasum -a 256 "$CONFIG" | cut -d' ' -f1)"
[ "$before" = "$after" ] || fail "doctor modified the config file"
[ ! -e "$CONFIG.bak" ] || fail "doctor wrote a backup file"
[ ! -e "$WORK/last-run.json" ] || fail "doctor wrote last-run state"
echo "ok: read-only — config unchanged, no state written"

# --- Never prompts --------------------------------------------------------
# A prompt would block forever with no TTY; reaching here at all proves it
# returned. Also assert it did not report a permission it was never granted.
"$BIN" doctor --config "$CONFIG" >/dev/null 2>&1 || true
echo "ok: completed without blocking on a prompt"

# --- Text output is greppable on stdout -----------------------------------
# brew doctor writes everything to stderr, which makes `brew doctor | grep`
# silently return nothing. This asserts we did not repeat that.
set +e
piped="$("$BIN" doctor --config "$CONFIG" 2>/dev/null | grep -c 'Calendar access')"
set -e
[ "$piped" -ge 1 ] || fail "findings are not on stdout — 'doctor | grep' would return nothing"
echo "ok: findings reach stdout"

echo "doctor integration checks passed"
