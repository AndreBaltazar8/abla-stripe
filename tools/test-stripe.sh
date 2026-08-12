#!/usr/bin/env bash
set -euo pipefail

fixture_dir="$(mktemp -d)"
fixture_pid=""
cleanup() {
    status=$?
    if [[ -n "$fixture_pid" ]]; then
        kill "$fixture_pid" 2>/dev/null || true
        wait "$fixture_pid" 2>/dev/null || true
    fi
    if [[ $status -ne 0 && -s "$fixture_dir/error" ]]; then
        cat "$fixture_dir/error" >&2
    fi
    rm -r "$fixture_dir"
    exit "$status"
}
trap cleanup EXIT

python3 tools/stripe_mock.py >"$fixture_dir/port" 2>"$fixture_dir/error" &
fixture_pid=$!

for _ in $(seq 1 100); do
    if [[ -s "$fixture_dir/port" ]]; then break; fi
    if ! kill -0 "$fixture_pid" 2>/dev/null; then
        cat "$fixture_dir/error" >&2
        exit 1
    fi
    sleep 0.02
done

if [[ ! -s "$fixture_dir/port" ]]; then
    echo "Stripe fixture server did not publish its port" >&2
    exit 1
fi

STRIPE_MOCK_PORT="$(head -n 1 "$fixture_dir/port")" build/integration-test
wait "$fixture_pid"
fixture_pid=""
