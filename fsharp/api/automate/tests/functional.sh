#!/usr/bin/env sh
set -e

API_ROOT="${1:-http://api-debug:8080}"

test() {
  path="${1:?path required}"
  shift
  method="GET"
  if [ "${1:-SENTINEL}" != "SENTINEL" ]; then
    method="$1"
    shift
  fi
  url="${API_ROOT}/${path#/}"
  echo "================"
  echo "Testing $method $url with $*"
  echo
  http --check-status --ignore-stdin "${method}" "${url}" "$@"
  echo
  echo "================"
  echo
}

test "/-/startup"
test "/-/readiness"
test "/-/liveness"
test "/-/debug"
test "/-/debug" POST foo=bar

sleep 2
