#!/usr/bin/env bats
#
# The symlink engine: the only code that moves and deletes files in $HOME.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

# --- fs_classify ------------------------------------------------------------

@test "classify: missing when nothing is there" {
  run fs_classify /some/src "$HOME/.gitconfig"
  [ "$output" = "missing" ]
}

@test "classify: ok when the link already points at src" {
  local src="$DOT_TMP/src"
  echo hi >"$src"
  ln -s "$src" "$HOME/f"
  run fs_classify "$src" "$HOME/f"
  [ "$output" = "ok" ]
}

@test "classify: clobbered when a real file is in the way" {
  echo mine >"$HOME/f"
  run fs_classify "$DOT_TMP/src" "$HOME/f"
  [ "$output" = "clobbered" ]
}

@test "classify: wrong-target when the link points elsewhere" {
  echo a >"$DOT_TMP/a"
  echo b >"$DOT_TMP/b"
  ln -s "$DOT_TMP/b" "$HOME/f"
  run fs_classify "$DOT_TMP/a" "$HOME/f"
  [ "$output" = "wrong-target" ]
}

@test "classify: broken beats ok for a dangling link to src" {
  # The file was deleted from the repo; "ok" would hide the only interesting fact.
  local src="$DOT_TMP/gone"
  echo x >"$src"
  ln -s "$src" "$HOME/f"
  rm "$src"
  run fs_classify "$src" "$HOME/f"
  [ "$output" = "broken" ]
}

# --- fs_link ----------------------------------------------------------------

@test "link: creates the link and any missing parent directories" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config" "tracked"

  fs_link_tree "$m"

  [ -L "$HOME/.config/git/config" ]
  [ "$(cat "$HOME/.config/git/config")" = "tracked" ]
  [ "$DOT_N_LINKED" -eq 1 ]
}

@test "link: parent directories are real directories, never symlinks" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config"

  fs_link_tree "$m"

  [ -d "$HOME/.config" ]
  [ ! -L "$HOME/.config" ]
  [ ! -L "$HOME/.config/git" ]
}

@test "link: touches nothing on the second run, and says it did nothing" {
  # fs_link is silent per file; the TREE says one line so a converged module
  # does not print an empty section.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config"

  fs_link_tree "$m"
  DOT_N_LINKED=0 DOT_N_UNCHANGED=0
  run fs_link_tree "$m"

  [[ $output == *"all 1 already linked"* ]]

  # `run` is a subshell, so re-do it here for the tallies.
  DOT_N_LINKED=0 DOT_N_UNCHANGED=0
  fs_link_tree "$m"
  [ "$DOT_N_LINKED" -eq 0 ]
  [ "$DOT_N_UNCHANGED" -eq 1 ]
}

@test "link: a tree that changed something does not also claim it did not" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config"
  fixture_file "$m" ".gitconfig"

  fs_link_tree "$m"
  rm "$HOME/.gitconfig"
  run fs_link_tree "$m"

  [[ $output == *"link    ~/.gitconfig"* ]]
  [[ $output != *"already linked"* ]]
}

@test "link: a real file is moved to the backup tree, not overwritten" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo "precious" >"$HOME/.gitconfig"

  fs_link_tree "$m"

  [ -L "$HOME/.gitconfig" ]
  [ "$(cat "$HOME/.gitconfig")" = "from-repo" ]
  [ "$DOT_N_BACKED_UP" -eq 1 ]

  # The original still exists, exactly once, under the backup tree.
  run bash -c "grep -rl precious '$DOT_STATE/backups' | wc -l | tr -d ' '"
  [ "$output" = "1" ]
}

@test "link: a directory in the way is called a directory, and still moved aside" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  mkdir -p "$HOME/.gitconfig"
  printf 'mine\n' >"$HOME/.gitconfig/inside.txt"

  run fs_link_tree "$m"
  [[ $output == *"real directory in the way"* ]]
  [[ $output != *"real file in the way"* ]]

  # `run` is a subshell, but its writes to disk are real.
  [ -L "$HOME/.gitconfig" ]
  [ "$(cat "$HOME/.gitconfig")" = "from-repo" ]

  # The directory went in whole: its contents are still there, exactly once.
  run bash -c "grep -rl mine '$DOT_STATE/backups' | wc -l | tr -d ' '"
  [ "$output" = "1" ]
}

@test "backup: the run remembers where it put things" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo "precious" >"$HOME/.gitconfig"

  fs_link_tree "$m"

  fs_backup_used
  [ "$(cat "$DOT_STATE/backups/$DOT_RUN_ID/.gitconfig")" = "precious" ]
}

@test "backup: a hook's backup is reported by the driver that ran it" {
  # A hook is a separate process; containers/apply.sh calls fs_link directly.
  local m
  m=$(fixture_module hooked)
  fixture_file "$m" "target.txt" "from-repo"
  echo precious >"$HOME/target.txt"

  # The hook, run the way module_run_hook runs one: its own process.
  cat >"$DOT_TMP/hook.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
fs_link "$m/home/target.txt" "\$HOME/target.txt"
EOF
  "$BASH" "$DOT_TMP/hook.sh"

  # This process backed up nothing, and still knows where the file went.
  [ "$DOT_N_BACKED_UP" -eq 0 ]
  fs_backup_used
  run fs_report
  [[ $output == *"$DOT_STATE/backups/$DOT_RUN_ID"* ]]
  [ "$(cat "$DOT_STATE/backups/$DOT_RUN_ID/target.txt")" = "precious" ]
}

@test "backup: a dry run names the directory it would have used" {
  # fs_backup_used answers from the filesystem, and a dry run puts nothing
  # there; the tally half must cover it.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo precious >"$HOME/.gitconfig"
  export DOT_DRY_RUN=1

  fs_link_tree "$m"
  run fs_report

  [[ $output == *"$DOT_STATE/backups/$DOT_RUN_ID"* ]]
  [ ! -d "$DOT_STATE/backups" ]
}

@test "report: says where the replaced files went" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo "precious" >"$HOME/.gitconfig"

  fs_link_tree "$m"
  run fs_report

  [[ $output == *"1 backed up"* ]]
  [[ $output == *"Replaced files were moved to $DOT_STATE/backups/"* ]]
}

@test "backup: one run uses one directory, even across a second boundary" {
  # A per-collision `date` would scatter one run's backups across directories.
  # The sleep is the point of the test.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  fixture_file "$m" ".gitignore" "from-repo"
  echo "precious-one" >"$HOME/.gitconfig"
  echo "precious-two" >"$HOME/.gitignore"

  fs_link "$m/home/.gitconfig" "$HOME/.gitconfig"
  sleep 1.1
  fs_link "$m/home/.gitignore" "$HOME/.gitignore"

  [ "$DOT_N_BACKED_UP" -eq 2 ]
  run bash -c "find '$DOT_STATE/backups' -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '"
  [ "$output" = "1" ]
}

@test "link: replaces a wrong-target link without making a backup" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo other >"$DOT_TMP/other"
  ln -s "$DOT_TMP/other" "$HOME/.gitconfig"

  fs_link_tree "$m"

  [ "$(readlink "$HOME/.gitconfig")" = "$m/home/.gitconfig" ]
  [ "$DOT_N_RELINKED" -eq 1 ]
  [ "$DOT_N_BACKED_UP" -eq 0 ]
  [ ! -d "$DOT_STATE/backups" ]
}

@test "link: repairs a broken link" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  ln -s "$DOT_TMP/never-existed" "$HOME/.gitconfig"

  fs_link_tree "$m"

  [ -e "$HOME/.gitconfig" ]
  [ "$DOT_N_RELINKED" -eq 1 ]
}

@test "link: a clean run leaves no backup directory behind" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig"

  fs_link_tree "$m"

  [ ! -d "$DOT_STATE/backups" ]
}

@test "link: handles spaces in filenames" {
  local m
  m=$(fixture_module app)
  fixture_file "$m" ".config/some app/my config.toml" "ok"

  fs_link_tree "$m"

  [ -L "$HOME/.config/some app/my config.toml" ]
}

# --- dry run ----------------------------------------------------------------

@test "dry run: reports the same intent a real run would, and changes nothing" {
  # fs_link prints its intent BEFORE the dry-run guard; moving it below has to
  # fail here.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig"
  export DOT_DRY_RUN=1

  run fs_link_tree "$m"
  [[ $output == *"link    ~/.gitconfig"* ]]

  # `run` is a subshell, so re-do it here for the tally.
  fs_link_tree "$m"
  [ ! -e "$HOME/.gitconfig" ]
  [ "$DOT_N_LINKED" -eq 1 ]
}

@test "dry run: the words are identical to the real run's" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo precious >"$HOME/.gitconfig" # forces the noisiest branch

  DOT_DRY_RUN=1 run fs_link_tree "$m"
  local dry=$output
  DOT_DRY_RUN=0 run fs_link_tree "$m"

  [ "$dry" = "$output" ]
}

@test "dry run: does not move a real file aside" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo precious >"$HOME/.gitconfig"
  export DOT_DRY_RUN=1

  fs_link_tree "$m"

  [ ! -L "$HOME/.gitconfig" ]
  [ "$(cat "$HOME/.gitconfig")" = "precious" ]
  [ ! -d "$DOT_STATE/backups" ]
}

# --- fs_check_tree ----------------------------------------------------------

@test "check: clean tree reports no drift" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig"
  fs_link_tree "$m"

  run fs_check_tree "$m"
  [ "$status" -eq 0 ]
}

@test "check: detects a clobbered file and never repairs it" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  fs_link_tree "$m"
  rm "$HOME/.gitconfig"
  echo replaced >"$HOME/.gitconfig"

  run fs_check_tree "$m"
  [ "$status" -eq 1 ]
  # doctor is read-only: the file must be exactly as we left it
  [ "$(cat "$HOME/.gitconfig")" = "replaced" ]
}

@test "check: a directory in the way is reported as a directory" {
  # doctor has its own copy of the label, separate from fs_link's.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  mkdir -p "$HOME/.gitconfig"

  run fs_check_tree "$m"
  [ "$status" -eq 1 ]
  [[ $output == *"real directory"* ]]
  [[ $output != *"real file"* ]]
}

@test "check: an empty module is not drift" {
  local m
  m=$(fixture_module empty)
  run fs_check_tree "$m"
  [ "$status" -eq 0 ]
}

@test "check: every classify state has a report line of its own" {
  # Each of the five arms must print its own sentence, or could be deleted
  # with the suite still green.
  local m
  m=$(fixture_module many)
  fixture_file "$m" "gone.conf"     # will point elsewhere
  fixture_file "$m" "dangling.conf" # will point at nothing
  fixture_file "$m" "absent.conf"   # will not be linked at all

  echo elsewhere >"$DOT_TMP/elsewhere"
  ln -s "$DOT_TMP/elsewhere" "$HOME/gone.conf"
  ln -s "$DOT_TMP/never-existed" "$HOME/dangling.conf"

  run fs_check_tree "$m"
  [ "$status" -eq 1 ]
  [[ $output == *"wrong target    ~/gone.conf"* ]]
  [[ $output == *"broken link     ~/dangling.conf"* ]]
  [[ $output == *"not linked      ~/absent.conf"* ]]
}

@test "check: drift in one file is drift, even with clean files around it" {
  # An early `return 1` -- the obvious refactor -- would leave the remaining
  # files unreported. A single-file fixture cannot tell the two apart.
  local m
  m=$(fixture_module mixed)
  fixture_file "$m" "a.conf"
  fixture_file "$m" "b.conf"
  fixture_file "$m" "c.conf"
  fs_link_tree "$m"
  rm "$HOME/b.conf" # the middle one, so order cannot mask it

  run fs_check_tree "$m"
  [ "$status" -eq 1 ]
  [[ $output == *"b.conf"* ]]
}

@test "check: warnings from a doctor pass reach the tally" {
  # Deliberately not `run`: a subshell would throw the counter away.
  local m before
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig"
  before=$DOT_WARNINGS

  fs_check_tree "$m" >/dev/null || true

  [ "$DOT_WARNINGS" -gt "$before" ]
}

# --- fs_pairs ---------------------------------------------------------------

@test "pairs: maps home/ onto \$HOME literally" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config"

  run fs_pairs "$m"
  [ "$output" = "$m/home/.config/git/config	$HOME/.config/git/config" ]
}

@test "pairs: a module with no home/ yields nothing" {
  local dir="$DOT_TMP/modules/macos"
  mkdir -p "$dir"
  run fs_pairs "$dir"
  [ -z "$output" ]
}

# --- fs_report --------------------------------------------------------------

@test "report: several tallies are joined with a comma AND a space" {
  # ${arr[*]} joins on only the FIRST character of IFS.
  DOT_N_LINKED=3
  DOT_N_BACKED_UP=2
  run fs_report
  [[ $output == *"3 linked, 2 backed up"* ]]
}

@test "report: a single tally gets no separator" {
  DOT_N_LINKED=1
  run fs_report
  [[ $output == *"1 linked"* ]]
  [[ $output != *","* ]]
}

@test "report: nothing done says so" {
  run fs_report
  [[ $output == *"No files to link."* ]]
}

@test "pairs: Finder's metadata is not a file this repo links" {
  # .DS_Store is gitignored, so CI never sees one; Finder writes it into any
  # module home/ you open. Without the filter `dot apply` linked it into $HOME.
  local dir
  dir=$(fixture_module one)
  fixture_file "$dir" '.config/real.conf'
  fixture_file "$dir" '.config/.DS_Store' 'finder'
  fixture_file "$dir" '.config/._real.conf' 'appledouble'

  run fs_pairs "$dir"
  [ "${#lines[@]}" -eq 1 ]
  [[ ${lines[0]} == *"/.config/real.conf" ]]

  fs_link_tree "$dir"
  [ -L "$HOME/.config/real.conf" ]
  [ ! -e "$HOME/.config/.DS_Store" ]
  [ ! -e "$HOME/.config/._real.conf" ]
}
