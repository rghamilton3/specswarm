#!/bin/bash
# SpecSwarm v7.11.0 agnosticism test suite.
#
# Every fix landed in v7.11.0 is exercised here against SYNTHETIC, generic
# inputs that share NOTHING with the customcult-v3 project the source
# interventions came from. Stacks used: a Go module, a Python/pip project,
# a Rust crate — none of them TypeScript/React-Router/Drizzle/pnpm.
#
# Run:  bash plugins/ss/test-fixtures/v7.11-agnosticism.sh
# Exit: 0 if all assertions pass, 1 otherwise.

set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKS="${PLUGIN_DIR}/lib/preflight/checks"
PASS=0
FAIL=0
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

# assert_status <expected PASS|WARN|FAIL> <actual-first-line> <label>
assert_status() {
  local want="$1" line="$2" label="$3"
  local got; got=$(echo "$line" | awk '{print $1}')
  if [ "$got" = "$want" ]; then ok "$label (=$got)"; else bad "$label — wanted $want got '$got' :: $line"; fi
}

mk_repo() {
  local d="$TMPROOT/$1"; mkdir -p "$d/.specswarm/features/001-x"; ( cd "$d" && git init -q ); echo "$d"
}

echo "━━━ v7.11.0 agnosticism suite (synthetic, non-customcult fixtures) ━━━"

# ─────────────────────────────────────────────────────────────────────────
echo "[A] Canonical-checkbox detector is language-agnostic (3b)"
# tasks.md with Go + Python task descriptions — proves the detector keys off
# the "- [X] T###" shape only, never on language/file conventions.
A_REPO=$(mk_repo go-py)
A_TASKS="$A_REPO/.specswarm/features/001-x/tasks.md"
cat > "$A_TASKS" <<'EOF'
# Tasks: data pipeline

## Phase 1
- [ ] T001 [P] Implement `pkg/ingest/reader.go` Reader.ReadBatch()
- [ ] T002 Write pytest suite in tests/test_transform.py
- [ ] T003 Add Cargo feature flag `parallel` to crate root
EOF
( cd "$A_REPO" && git add -A && git commit -qm init )
# Flip T001 and T002 (Go + Python tasks), leave T003
sed -i 's/- \[ \] T001/- [X] T001/; s/- \[ \] T002/- [x] T002/' "$A_TASKS"
NEW=$(bash "${PLUGIN_DIR}/lib/verify/detect-completion.sh" >/dev/null 2>&1; \
      source "${PLUGIN_DIR}/lib/verify/detect-completion.sh"; ss_detect_newly_checked "$A_TASKS" | tr '\n' ' ')
NEW=$(echo "$NEW" | xargs)
if [ "$NEW" = "T001 T002" ]; then ok "detected Go+Python checkbox flips: '$NEW'"; else bad "expected 'T001 T002' got '$NEW'"; fi

# ─────────────────────────────────────────────────────────────────────────
echo "[B] memory-coverage backtick extractor across all 5 prefixes (4c) + non-customcult memory layout"
B_REPO=$(mk_repo rust-mem)
B_MEM="$B_REPO/sresearch-notes"   # deliberately NOT named 'memory'
mkdir -p "$B_MEM"
cat > "$B_REPO/.specswarm/references.md" <<EOF
# References

## Memory directories

- path: $B_MEM
EOF
for n in feedback_rust_edition project_crate_layout reference_upstream_issue user_maintainer_profile intervention_clippy_drift; do
  echo "# $n" > "$B_MEM/$n.md"
done
cat > "$B_MEM/MEMORY.md" <<'EOF'
# Index
- [a](feedback_rust_edition.md)
- [b](project_crate_layout.md)
- [c](reference_upstream_issue.md)
- [d](user_maintainer_profile.md)
- [e](intervention_clippy_drift.md)
EOF
# plan citing memory ONLY via backticks (the old blind spot), all 5 prefixes
cat > "$B_REPO/.specswarm/features/001-x/plan.md" <<'EOF'
# Plan — rust crate refactor
Honoring `feedback_rust_edition`, `project_crate_layout`, `reference_upstream_issue`,
`user_maintainer_profile`, and `intervention_clippy_drift`.
EOF
LINE=$( cd "$B_REPO" && bash "$CHECKS/memory-coverage.sh" "$B_REPO/.specswarm/features/001-x/plan.md" | head -1 )
assert_status PASS "$LINE" "5 backtick refs (all prefixes) verified"
echo "$LINE" | grep -q "5 memory reference" && ok "counted 5 refs" || bad "ref count wrong :: $LINE"

# Backtick ref to a NON-EXISTENT memory file must now FAIL (was 0/0 PASS pre-fix)
echo 'Per `feedback_does_not_exist` we proceed.' > "$B_REPO/.specswarm/features/001-x/plan_bad.md"
LINE=$( cd "$B_REPO" && bash "$CHECKS/memory-coverage.sh" "$B_REPO/.specswarm/features/001-x/plan_bad.md" | head -1 )
assert_status FAIL "$LINE" "backtick ref to missing memory file → FAIL (not silent PASS)"

# ─────────────────────────────────────────────────────────────────────────
echo "[C] WARN-on-zero fires generically for each gate (3a)"

# C1 memory-coverage: dirs declared, plan cites nothing → WARN
echo "# Plan with zero memory refs" > "$B_REPO/.specswarm/features/001-x/plan_empty.md"
LINE=$( cd "$B_REPO" && bash "$CHECKS/memory-coverage.sh" "$B_REPO/.specswarm/features/001-x/plan_empty.md" | head -1 )
assert_status WARN "$LINE" "memory-coverage: dirs present, 0 refs → WARN"

# C2 memory-coverage NOT-APPLICABLE (no dirs declared) → stays PASS-skip
C2_REPO=$(mk_repo no-mem)
echo "# References" > "$C2_REPO/.specswarm/references.md"
echo "# Plan" > "$C2_REPO/.specswarm/features/001-x/plan.md"
LINE=$( cd "$C2_REPO" && bash "$CHECKS/memory-coverage.sh" "$C2_REPO/.specswarm/features/001-x/plan.md" | head -1 )
assert_status PASS "$LINE" "memory-coverage: no dirs declared → clean PASS-skip"

# C3 version-currency: Go module present, plan pins nothing → WARN
C3_REPO=$(mk_repo go-noversions)
cat > "$C3_REPO/go.mod" <<'EOF'
module example.com/widget
go 1.22
EOF
echo "# Plan with no version pins" > "$C3_REPO/.specswarm/features/001-x/plan.md"
LINE=$( cd "$C3_REPO" && bash "$CHECKS/version-currency.sh" "$C3_REPO/.specswarm/features/001-x/plan.md" | head -1 )
assert_status WARN "$LINE" "version-currency: package mgr present, 0 pins → WARN"

# C4 version-currency NOT-APPLICABLE (no package manager) → PASS-skip
C4_REPO=$(mk_repo bare)
echo "# Plan" > "$C4_REPO/.specswarm/features/001-x/plan.md"
LINE=$( cd "$C4_REPO" && bash "$CHECKS/version-currency.sh" "$C4_REPO/.specswarm/features/001-x/plan.md" | head -1 )
assert_status PASS "$LINE" "version-currency: no package mgr → clean PASS-skip"

# C5 spec-section-existence: corpus declared, plan cites zero § → WARN
C5_REPO=$(mk_repo gospec)
mkdir -p "$C5_REPO/docs"
cat > "$C5_REPO/docs/SPEC.md" <<'EOF'
# Spec
## §1.1 Reader
content
EOF
cat > "$C5_REPO/.specswarm/references.md" <<EOF
# References

## Spec corpus

- path: docs/SPEC.md
EOF
echo "# Plan with no section refs" > "$C5_REPO/.specswarm/features/001-x/plan.md"
LINE=$( cd "$C5_REPO" && bash "$CHECKS/spec-section-existence.sh" "$C5_REPO/.specswarm/features/001-x/plan.md" | head -1 )
assert_status WARN "$LINE" "spec-section-existence: corpus present, 0 § refs → WARN"

# C6 grep-word-boundary: zero grep invocations → WARN
echo "# Plan with no grep commands" > "$C5_REPO/.specswarm/features/001-x/plan_nogrep.md"
LINE=$( cd "$C5_REPO" && bash "$CHECKS/grep-word-boundary.sh" "$C5_REPO/.specswarm/features/001-x/plan_nogrep.md" | head -1 )
assert_status WARN "$LINE" "grep-word-boundary: 0 invocations → WARN"

# C7 heading-fidelity: corpus declared, zero quoted headings → WARN
LINE=$( cd "$C5_REPO" && bash "$CHECKS/heading-fidelity.sh" "$C5_REPO/.specswarm/features/001-x/plan.md" | head -1 )
assert_status WARN "$LINE" "heading-fidelity: corpus present, 0 quoted headings → WARN"

# C8 heading-fidelity NOT-APPLICABLE (no corpus) → PASS-skip
LINE=$( cd "$C4_REPO" && bash "$CHECKS/heading-fidelity.sh" "$C4_REPO/.specswarm/features/001-x/plan.md" | head -1 )
assert_status PASS "$LINE" "heading-fidelity: no corpus declared → clean PASS-skip"

# ─────────────────────────────────────────────────────────────────────────
echo "[D] verify-queue add → list → resolve drain cycle is path-agnostic (3c)"
D_REPO=$(mk_repo drain); cd "$D_REPO"
source "${PLUGIN_DIR}/lib/verify/queue.sh"
ss_verify_queue_add T010 "$D_REPO/.specswarm/features/001-x" "$D_REPO/.specswarm/features/001-x/tasks.md" "go reader" "FR1"
ss_verify_queue_add T011 "$D_REPO/.specswarm/features/001-x" "$D_REPO/.specswarm/features/001-x/tasks.md" "py transform" "FR2"
PEND=$(ss_verify_queue_count pending)
[ "$PEND" = "2" ] && ok "2 markers queued" || bad "expected 2 pending got $PEND"
ss_verify_queue_resolve T010 PASS "looks good"
ss_verify_queue_resolve T011 DRIFT "ordering bug"
PEND=$(ss_verify_queue_count pending); VER=$(ss_verify_queue_count verified); FLG=$(ss_verify_queue_count flagged)
if [ "$PEND" = "0" ] && [ "$VER" = "1" ] && [ "$FLG" = "1" ]; then
  ok "drained: pending=0 verified=1 flagged=1"
else
  bad "drain wrong: pending=$PEND verified=$VER flagged=$FLG"
fi
cd - >/dev/null

# ─────────────────────────────────────────────────────────────────────────
echo "[E] ship verify-queue precondition count logic (4b) — completed tasks vs empty queue"
E_TASKS="$A_REPO/.specswarm/features/001-x/tasks.md"  # T001/T002 are [X]/[x]
COMPLETED=$(grep -cE '^[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]+T[0-9]+' "$E_TASKS")
[ "$COMPLETED" = "2" ] && ok "counted 2 completed checkboxes (mixed [X]/[x])" || bad "expected 2 got $COMPLETED"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
