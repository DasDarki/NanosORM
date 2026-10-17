#!/usr/bin/env bash
set -u
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$TESTS_DIR")"
FILTER="${1:-}"
LUA="${LUA:-lua5.4}"

(cd "$ROOT_DIR" && nebra build > /dev/null) || { echo "build failed"; exit 1; }

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

passed=0
failed=0
for suite in "$TESTS_DIR"/unit/*.lua; do
    name="$(basename "$suite" .lua)"
    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
        continue
    fi

    output="$(cd "$WORK_DIR" && "$LUA" -e "ROOT = '$ROOT_DIR/out'; dofile('$TESTS_DIR/harness.lua')" "$suite" 2>&1)"
    ok=$(grep -c '^OK' <<< "$output")
    bad=$(grep -c -E '^FAIL|^lua' <<< "$output")
    passed=$((passed + ok))
    failed=$((failed + bad))
    if [ "$bad" -gt 0 ]; then
        echo "FAIL $name ($ok passed, $bad failed)"
        grep -E '^FAIL|^lua|^\s+\[' <<< "$output" | sed 's/^/     /'
    else
        echo "ok   $name ($ok passed)"
    fi
done

if [ -z "$FILTER" ] || [[ "nebra" == *"$FILTER"* ]]; then
    if [ ! -d "$TESTS_DIR/nebra/nebra_modules" ]; then
        (cd "$TESTS_DIR/nebra" && nebra install > /dev/null) || { echo "install of the nebra tests failed"; exit 1; }
    fi

    (cd "$TESTS_DIR/nebra" && nebra build > /dev/null) || { echo "build of the nebra tests failed"; exit 1; }
    output="$(cd "$WORK_DIR" && "$LUA" -e "ROOT = '$ROOT_DIR/out'; NEBRA_OUT = '$TESTS_DIR/nebra/out'; dofile('$TESTS_DIR/harness.lua')" "$TESTS_DIR/nebra/run.lua" 2>&1)"
    ok=$(grep -c '^OK' <<< "$output")
    bad=$(grep -c -E '^FAIL|^lua' <<< "$output")
    passed=$((passed + ok))
    failed=$((failed + bad))
    if [ "$bad" -gt 0 ]; then
        echo "FAIL nebra ($ok passed, $bad failed)"
        grep -E '^FAIL|^lua|^\s+\[' <<< "$output" | sed 's/^/     /'
    else
        echo "ok   nebra ($ok passed)"
    fi
fi

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
