#!/usr/bin/env bash

set -euo pipefail

developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
real_clang="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
args=("$@")
has_preprocess=0
has_macro_dump=0
has_null_input=0

for arg in "${args[@]}"; do
  [[ "$arg" == "-E" ]] && has_preprocess=1
  [[ "$arg" == "-dM" ]] && has_macro_dump=1
  [[ "$arg" == "/dev/null" ]] && has_null_input=1
done

# Xcode's compiler-identification probe is the only invocation altered here.
# Real compilations and developer-requested macro dumps keep their full flags.
if [[ "$has_preprocess" -eq 1 && "$has_macro_dump" -eq 1 && "$has_null_input" -eq 1 ]]; then
  filtered_args=()
  for arg in "${args[@]}"; do
    [[ "$arg" == "-v" ]] && continue
    filtered_args+=("$arg")
  done
  exec "$real_clang" "${filtered_args[@]}"
fi

exec "$real_clang" "${args[@]}"
