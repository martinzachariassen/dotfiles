# shellcheck shell=bash

DOT_N_LINKED=0
DOT_N_RELINKED=0
DOT_N_BACKED_UP=0
DOT_N_UNCHANGED=0

fs_backup_dir() {
  local dir="$DOT_STATE/backups/$DOT_RUN_ID"
  [[ $DOT_DRY_RUN == 1 ]] || mkdir -p "$dir"
  printf '%s\n' "$dir"
}

fs_backup_used() {
  ((DOT_N_BACKED_UP)) || [[ -d "$DOT_STATE/backups/$DOT_RUN_ID" ]]
}

fs_pairs() {
  local dir=$1 home="$1/home" src rel
  [[ -d $home ]] || return 0
  while IFS= read -r -d '' src; do
    rel=${src#"$home"/}
    printf '%s\t%s\n' "$src" "$HOME/$rel"
  done < <(find "$home" -type f ! -name '.DS_Store' ! -name '._*' -print0 | sort -z)
}

# Dangling is tested before target equality: a link to a file the repo deleted
# is not ok.
fs_classify() {
  local src=$1 dst=$2
  if [[ -L $dst ]]; then
    if [[ ! -e $dst ]]; then
      printf 'broken\n'
    elif [[ $(readlink "$dst") == "$src" ]]; then
      printf 'ok\n'
    else
      printf 'wrong-target\n'
    fi
  elif [[ -e $dst ]]; then
    printf 'clobbered\n'
  else
    printf 'missing\n'
  fi
}

fs_link() {
  local src=$1 dst=$2 rel=${2#"$HOME"/} short=${2/#$HOME/\~} state backup what

  state=$(fs_classify "$src" "$dst")

  if [[ $state == ok ]]; then
    DOT_N_UNCHANGED=$((DOT_N_UNCHANGED + 1))
    return 0
  fi

  case $state in
    missing) info link "$short" ;;
    wrong-target | broken) info relink "$short" ;;
    clobbered)
      if [[ -d $dst ]]; then what='directory'; else what='file'; fi
      info backup "$short  (real $what in the way)"
      ;;
  esac
  [[ $DOT_DRY_RUN == 1 ]] || {
    if [[ $state == clobbered ]]; then
      backup="$(fs_backup_dir)/$rel"
      mkdir -p "$(dirname "$backup")"
      mv "$dst" "$backup"
    else
      rm -f "$dst"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
  }

  case $state in
    missing) DOT_N_LINKED=$((DOT_N_LINKED + 1)) ;;
    wrong-target | broken) DOT_N_RELINKED=$((DOT_N_RELINKED + 1)) ;;
    clobbered) DOT_N_BACKED_UP=$((DOT_N_BACKED_UP + 1)) ;;
  esac
}

fs_link_tree() {
  local src dst n=0 before=$DOT_N_UNCHANGED
  while IFS=$'\t' read -r src dst; do
    fs_link "$src" "$dst"
    n=$((n + 1))
  done < <(fs_pairs "$1")

  if ((n > 0 && DOT_N_UNCHANGED - before == n)); then
    ok files "all $n already linked"
  fi
}

fs_unlink() {
  local dst=$1
  [[ -L $dst ]] || return 0
  info unlink "${dst/#$HOME/\~}"
  [[ $DOT_DRY_RUN == 1 ]] || rm -f "$dst"
}

fs_discard() {
  local dst=$1
  [[ -f $dst ]] || return 0
  info remove "${dst/#$HOME/\~}"
  [[ $DOT_DRY_RUN == 1 ]] || rm -f "$dst"
}

fs_check_tree() {
  local src dst short state drift=0
  while IFS=$'\t' read -r src dst; do
    state=$(fs_classify "$src" "$dst")
    short=${dst/#$HOME/\~}
    case $state in
      ok) ;;
      missing) warn 'not linked' "$short" ;;
      wrong-target) warn 'wrong target' "$short" ;;
      clobbered)
        if [[ -d $dst ]]; then
          warn 'real directory' "$short"
        else
          warn 'real file' "$short"
        fi
        ;;
      broken) warn 'broken link' "$short" ;;
    esac
    [[ $state == ok ]] || drift=1
  done < <(fs_pairs "$1")
  return $drift
}

fs_report() {
  local parts=() summary
  ((DOT_N_LINKED)) && parts+=("$DOT_N_LINKED linked")
  ((DOT_N_RELINKED)) && parts+=("$DOT_N_RELINKED relinked")
  ((DOT_N_BACKED_UP)) && parts+=("$DOT_N_BACKED_UP backed up")
  ((DOT_N_UNCHANGED)) && parts+=("$DOT_N_UNCHANGED unchanged")

  if ((${#parts[@]} == 0)); then
    say files 'none to link'
  else
    # printf, not IFS + "${parts[*]}": that joins on the first char of IFS only.
    summary=$(printf ', %s' "${parts[@]}")
    say files "${summary:2}"
  fi

  if fs_backup_used; then
    say backups "${DOT_STATE/#$HOME/\~}/backups/$DOT_RUN_ID"
    dim 'Files that were in the way. Nothing else has a copy of them.'
  fi
}

fs_repo_links() {
  local -A roots=() seen=()
  local dir src dst link target depth
  local -a scan

  while IFS= read -r dir; do
    while IFS=$'\t' read -r src dst; do
      dst=${dst%/*}
      while [[ $dst == "$HOME"/* ]]; do
        roots[$dst]=1
        dst=${dst%/*}
      done
      roots[$HOME]=1
    done < <(fs_pairs "$dir")
  done < <(
    modules_all_dirs
    printf '%s\n' "$DOT_ROOT/core"
  )

  ((${#roots[@]})) || return 0

  mapfile -t scan < <(printf '%s\n' "${!roots[@]}" | sort)

  for dir in "${scan[@]}"; do
    [[ -d $dir ]] || continue
    # Depth 2 reaches a directory no longer declared; $HOME's children are every
    # tool's, so it stays at 1.
    if [[ $dir == "$HOME" ]]; then depth=1; else depth=2; fi
    while IFS= read -r -d '' link; do
      target=$(readlink "$link") || continue
      [[ $target == "$DOT_ROOT"/* ]] || continue
      [[ -z ${seen[$link]:-} ]] || continue
      seen[$link]=1
      printf '%s\n' "$link"
    done < <(find "$dir" -maxdepth "$depth" -type l -print0 2>/dev/null)
  done
}

# The module column goes last: tab is IFS whitespace, and `read` skips a
# leading empty field.
fs_orphans() {
  # Two maps: with two modules shipping one path, a disabled one would otherwise
  # overwrite the enabled one's claim.
  local -A claimed=() owner=()
  local dir src dst link

  while IFS= read -r dir; do
    while IFS=$'\t' read -r src dst; do
      claimed[$dst]=1
    done < <(fs_pairs "$dir")
  done < <(
    modules_enabled_dirs
    printf '%s\n' "$DOT_ROOT/core"
  )

  while IFS= read -r dir; do
    while IFS=$'\t' read -r src dst; do
      owner[$dst]=${dir##*/}
    done < <(fs_pairs "$dir")
  done < <(modules_all_dirs)

  while IFS= read -r link; do
    [[ -n ${claimed[$link]:-} ]] ||
      printf '%s\t%s\n' "$link" "${owner[$link]:-}"
  done < <(fs_repo_links)
}
