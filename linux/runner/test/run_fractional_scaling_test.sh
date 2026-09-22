#!/usr/bin/env bash
set -euo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
runner_dir=$(cd -- "$test_dir/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -Wpedantic \
  "$test_dir/fractional_scaling_test.cc" \
  "$runner_dir/fractional_scaling.cc" \
  $(pkg-config --cflags --libs gio-2.0 glib-2.0) \
  -o "$fixture_dir/fractional_scaling_test"
"$fixture_dir/fractional_scaling_test"
