#!/usr/bin/env bash
# check-fixtures.sh (C11): every check in policy/ has a test file with at least one test that a
# violating fixture plan fails. `opa test policy` (run before this) proves those tests pass.
set -euo pipefail
cd "$(dirname "$0")/../policy"
missing=0
for check in c*_*.rego; do
  [[ $check == *_test.rego ]] && continue
  test=${check%.rego}_test.rego
  if [[ ! -f $test ]] || ! grep -Eq '^test_[a-z0-9_]*fails? if' "$test"; then
    echo "::error file=policy/$check::no test of $check fails on a violating fixture (C11)"
    missing=1
  else
    echo "$check: $(grep -Ec '^test_[a-z0-9_]*fails? if' "$test") failing-fixture test(s)"
  fi
done
exit "$missing"
