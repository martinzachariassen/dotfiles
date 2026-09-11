# shellcheck shell=bash
#
# The symlink engine. A bug in here loses files. Two rules:
#
#   1. Directories are never symlinked, only traversed.
#   2. A real file is never destroyed; it is moved to the backup tree.

# The driver's own tallies, and only those: a hook is a separate process, so
# fs_report undercounts by whatever the hooks did. Adding up across processes
# would need a state file, which this repo derives instead.
DOT_N_LINKED=0
DOT_N_RELINKED=0
DOT_N_BACKED_UP=0
DOT_N_UNCHANGED=0

# Derived from the exported DOT_RUN_ID, never memoised: a value set here would
# not survive `$(fs_backup_dir)` nor reach a hook's process.
fs_backup_dir() {
  local dir="$DOT_STATE/backups/$DOT_RUN_ID"
  [[ $DOT_DRY_RUN == 1 ]] || mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# The directory on disk is the only evidence that crosses the process boundary;
# the tally covers a dry run, where there is none.
fs_backup_used() {
  ((DOT_N_BACKED_UP)) || [[ -d "$DOT_STATE/backups/$DOT_RUN_ID" ]]
}

# fs_pairs DIR -- "src<TAB>dst" for every leaf file under DIR/home. The single
# place that maps a module's home/ onto $HOME. Finder's metadata is filtered
# here rather than by a test: Finder writes it into the checkout behind your
# back, and the engine has to be immune.
fs_pairs() {
  local dir=$1 home="$1/home" src rel
  [[ -d $home ]] || return 0
  while IFS= read -r -d '' src; do
    rel=${src#"$home"/}
    printf '%s\t%s\n' "$src" "$HOME/$rel"
  done < <(find "$home" -type f ! -name '.DS_Store' ! -name '._*' -print0 | sort -z)
}

# fs_classify SRC DST -- ok | missing | wrong-target | clobbered | broken.
# Dangling is checked before target equality: a link at SRC whose file was
# deleted from the repo must not read as ok.
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

# fs_link SRC DST -- idempotent; an already-correct link prints nothing.
fs_link() {
  local src=$1 dst=$2 rel=${2#"$HOME"/} short=${2/#$HOME/\~} state backup what

  state=$(fs_classify "$src" "$dst")

  if [[ $state == ok ]]; then
    DOT_N_UNCHANGED=$((DOT_N_UNCHANGED + 1))
    return 0
  fi

  # Intent is announced before acting, so a dry run and a real run use the same
  # words (tests/fs.bats pins this).
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

# fs_link_tree DIR -- speaks only when nothing changed, so a converged module
# does not print an empty section. Phrased from the pre-state so a dry run and
# a real run agree.
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

# --- Removal ----------------------------------------------------------------
#
# Two helpers, not one "delete this path": a link is recognised by where it
# points, a generated file by its header. The guard lives here, not the caller.

# fs_unlink DST -- symlinks only. A real file at a path we once owned stays.
fs_unlink() {
  local dst=$1
  [[ -L $dst ]] || return 0
  info unlink "${dst/#$HOME/\~}"
  [[ $DOT_DRY_RUN == 1 ]] || rm -f "$dst"
}

# fs_discard DST -- a real file this repo generated. Callers prove ownership
# first (the shim's DOT_ROOT line, config.local's header).
fs_discard() {
  local dst=$1
  [[ -f $dst ]] || return 0
  info remove "${dst/#$HOME/\~}"
  [[ $DOT_DRY_RUN == 1 ]] || rm -f "$dst"
}

# fs_check_tree DIR -- read-only drift report. Returns 1 on any drift.
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
    # printf, not IFS + "${parts[*]}": that joins on the FIRST char of IFS only.
    summary=$(printf ', %s' "${parts[@]}")
    say files "${summary:2}"
  fi

  if fs_backup_used; then
    say backups "${DOT_STATE/#$HOME/\~}/backups/$DOT_RUN_ID"
    dim 'Files that were in the way. Nothing else has a copy of them.'
  fi
}

# fs_repo_links -- every symlink under $HOME that points into this repo. The
# shared walk for doctor (fs_orphans) and uninstall.sh, so neither gets its own
# idea of which links are ours. EVERY module, not just enabled ones: a link left
# by a disabled module is the main thing to find. "Points into $DOT_ROOT" is
# what makes it safe to delete from; links elsewhere need a remove.sh.
fs_repo_links() {
  local -A roots=() seen=()
  local dir src dst link target depth
  local -a scan

  # Every directory ON THE PATH to a declared file, not just the leaf's own. A
  # file deleted from the repo takes its directory out of the declared set with
  # it, and the link it left would then sit where nothing scans.
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

  # -maxdepth 2, so a directory that STOPPED being declared is still reached
  # from the parent an ancestor keeps in the set. $HOME is the exception at 1:
  # its children belong to every tool on the machine. The residual is pinned in
  # tests/orphans.bats; walking all of $HOME stays rejected, on cost.
  for dir in "${scan[@]}"; do
    [[ -d $dir ]] || continue
    if [[ $dir == "$HOME" ]]; then depth=1; else depth=2; fi
    while IFS= read -r -d '' link; do
      target=$(readlink "$link") || continue
      [[ $target == "$DOT_ROOT"/* ]] || continue
      # Overlapping scans: a link is reached from its own directory and again
      # from that directory's parent.
      [[ -z ${seen[$link]:-} ]] || continue
      seen[$link]=1
      printf '%s\n' "$link"
    done < <(find "$dir" -maxdepth "$depth" -type l -print0 2>/dev/null)
  done
}

# fs_orphans -- repo links no ENABLED module claims, as "path<TAB>module". The
# claim stays narrow: letting a disabled module claim its files would hide every
# orphan the wide scan exists to expose. The name is attribution, not a claim --
# which module SHIPS the path, so the caller can name its remove.sh -- and is
# empty when none does, where removing the link is the whole fix.
#
# The empty field goes LAST, and that is load-bearing: tab is IFS whitespace, so
# `read -r a b` on "<TAB>path" would skip a leading empty field and put the path
# in $a. Trailing, it reads as the empty string it is.
fs_orphans() {
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

  # A second pass, over ALL modules this time, not one map doing both jobs: with
  # two modules shipping one path, a disabled one would overwrite the enabled
  # one's claim and the file would read as an orphan.
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
