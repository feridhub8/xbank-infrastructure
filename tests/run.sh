#!/bin/sh
# Runs every test file and fails when any test fails.
set -u
cd /tests
. ./lib.sh
trap 'eval "$CLEANUP"' EXIT

for file in smoke.sh keycloak.sh vault.sh; do
  [ -f "$file" ] || continue
  echo "== $file"
  . "./$file"
done

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
