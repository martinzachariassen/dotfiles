#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

op_dir="$HOME/.config/op"

if [[ ! -d $op_dir ]]; then exit 0; fi

mode=$(stat -f '%Lp' "$op_dir")
if [[ $mode == 700 ]]; then exit 0; fi

info chmod "${op_dir/#$HOME/\~} $mode -> 700  (op refuses a folder others can open)"
if [[ $DOT_DRY_RUN == 1 ]]; then exit 0; fi
# op refuses its config dir, and every op:// reference, unless it is 700.
chmod 700 "$op_dir"
