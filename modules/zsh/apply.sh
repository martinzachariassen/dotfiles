#!/usr/bin/env bash
#
# op refuses its config dir, and with it every op:// reference, unless the mode
# is 700 -- and fs_link creates ~/.config/op, to link env, under the umask.
# doctor.sh checks the same mode.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

op_dir="$HOME/.config/op"

if [[ ! -d $op_dir ]]; then exit 0; fi

mode=$(stat -f '%Lp' "$op_dir")
if [[ $mode == 700 ]]; then exit 0; fi

info chmod "${op_dir/#$HOME/\~} $mode -> 700  (op refuses a folder others can open)"
if [[ $DOT_DRY_RUN == 1 ]]; then exit 0; fi
chmod 700 "$op_dir"
