#!/usr/bin/env bash

set -euo pipefail

developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
real_clang="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
args=("$@")
is_macro_probe=0

for arg in "${args[@]}"; do
  if [[ "$arg" == "-dM" ]]; then
    is_macro_probe=1
    break
  fi
done

if [[ "$is_macro_probe" -eq 1 ]]; then
  filtered_args=()
  for arg in "${args[@]}"; do
    [[ "$arg" == "-v" ]] && continue
    filtered_args+=("$arg")
  done
  exec "$real_clang" "${filtered_args[@]}"
fi

exec "$real_clang" "${args[@]}"
