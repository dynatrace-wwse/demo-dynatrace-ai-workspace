#!/usr/bin/env bash
# Validate synthetic ZIA logs are arriving in Dynatrace.
# Usage: ./scripts/validate-zia-logs.sh [window]
# Example: ./scripts/validate-zia-logs.sh 30m

set -euo pipefail

WINDOW="${1:-30m}"
FALLBACK_WINDOW="${2:-2h}"

if ! command -v dtctl >/dev/null 2>&1; then
  echo "dtctl not found" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found" >&2
  exit 1
fi

run_query() {
  local window="$1"
  local query
  query="fetch logs, from:now()-${window} | filter log.source == \"zscaler.zia.synthetic\" | summarize total = count(), errors = countIf(loglevel == \"ERROR\"), warns = countIf(loglevel == \"WARN\"), sites = countDistinct(site), nodes = countDistinct(zia_node), actions = countDistinct(policy_action), levels = countDistinct(loglevel)"
  dtctl query "$query" -o json --plain
}

OUT="$(run_query "$WINDOW")"
TOTAL="$(printf '%s' "$OUT" | jq -r '.result.records[0].total // 0')"
ERRORS="$(printf '%s' "$OUT" | jq -r '.result.records[0].errors // 0')"
WARNS="$(printf '%s' "$OUT" | jq -r '.result.records[0].warns // 0')"
SITES="$(printf '%s' "$OUT" | jq -r '.result.records[0].sites // 0')"
NODES="$(printf '%s' "$OUT" | jq -r '.result.records[0].nodes // 0')"
ACTIONS="$(printf '%s' "$OUT" | jq -r '.result.records[0].actions // 0')"
LEVELS="$(printf '%s' "$OUT" | jq -r '.result.records[0].levels // 0')"

echo "window=${WINDOW} total=${TOTAL} warns=${WARNS} errors=${ERRORS} sites=${SITES} nodes=${NODES} actions=${ACTIONS} levels=${LEVELS}"

if [ "$TOTAL" = "0" ]; then
  OUT="$(run_query "$FALLBACK_WINDOW")"
  TOTAL="$(printf '%s' "$OUT" | jq -r '.result.records[0].total // 0')"
  ERRORS="$(printf '%s' "$OUT" | jq -r '.result.records[0].errors // 0')"
  WARNS="$(printf '%s' "$OUT" | jq -r '.result.records[0].warns // 0')"
  SITES="$(printf '%s' "$OUT" | jq -r '.result.records[0].sites // 0')"
  NODES="$(printf '%s' "$OUT" | jq -r '.result.records[0].nodes // 0')"
  ACTIONS="$(printf '%s' "$OUT" | jq -r '.result.records[0].actions // 0')"
  LEVELS="$(printf '%s' "$OUT" | jq -r '.result.records[0].levels // 0')"
  echo "fallback_window=${FALLBACK_WINDOW} total=${TOTAL} warns=${WARNS} errors=${ERRORS} sites=${SITES} nodes=${NODES} actions=${ACTIONS} levels=${LEVELS}"

  if [ "$TOTAL" = "0" ]; then
    echo "Validation failed: no logs found for log.source=zscaler.zia.synthetic" >&2
    exit 1
  fi
fi

if [ "$SITES" = "0" ] || [ "$NODES" = "0" ] || [ "$ACTIONS" = "0" ] || [ "$LEVELS" = "0" ]; then
  echo "Validation failed: required fields site, zia_node, policy_action, or loglevel are missing" >&2
  exit 1
fi

echo "Validation passed: synthetic ZIA logs are present."
