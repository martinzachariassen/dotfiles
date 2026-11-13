#!/usr/bin/env bats

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

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
  local src="$DOT_TMP/gone"
  echo x >"$src"
  ln -s "$src" "$HOME/f"
  rm "$src"
  run fs_classify "$src" "$HOME/f"
  [ "$output" = "broken" ]
}

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
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config"

  fs_link_tree "$m"
  DOT_N_LINKED=0 DOT_N_UNCHANGED=0
  run fs_link_tree "$m"

  [[ $output == *"all 1 already linked"* ]]

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

  says link "~/.gitconfig"
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

  [ -L "$HOME/.gitconfig" ]
  [ "$(cat "$HOME/.gitconfig")" = "from-repo" ]

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
  local m
  m=$(fixture_module hooked)
  fixture_file "$m" "target.txt" "from-repo"
  echo precious >"$HOME/target.txt"

  cat >"$DOT_TMP/hook.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
fs_link "$m/home/target.txt" "\$HOME/target.txt"
EOF
  "$BASH" "$DOT_TMP/hook.sh"

  [ "$DOT_N_BACKED_UP" -eq 0 ]
  fs_backup_used
  run fs_report
  [[ $output == *"$DOT_STATE/backups/$DOT_RUN_ID"* ]]
  [ "$(cat "$DOT_STATE/backups/$DOT_RUN_ID/target.txt")" = "precious" ]
}

@test "backup: a dry run names the directory it would have used" {
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
  says backups "${DOT_STATE/#$HOME/\~}/backups/$DOT_RUN_ID"
}

@test "backup: one run uses one directory, even across a second boundary" {
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

@test "dry run: reports the same intent a real run would, and changes nothing" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig"
  export DOT_DRY_RUN=1

  run fs_link_tree "$m"
  says link "~/.gitconfig"

  fs_link_tree "$m"
  [ ! -e "$HOME/.gitconfig" ]
  [ "$DOT_N_LINKED" -eq 1 ]
}

@test "dry run: the words are identical to the real run's" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo precious >"$HOME/.gitconfig"

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
  [ "$(cat "$HOME/.gitconfig")" = "replaced" ]
}

@test "check: a directory in the way is reported as a directory" {
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
  local m
  m=$(fixture_module many)
  fixture_file "$m" "gone.conf"
  fixture_file "$m" "dangling.conf"
  fixture_file "$m" "absent.conf"

  echo elsewhere >"$DOT_TMP/elsewhere"
  ln -s "$DOT_TMP/elsewhere" "$HOME/gone.conf"
  ln -s "$DOT_TMP/never-existed" "$HOME/dangling.conf"

  run fs_check_tree "$m"
  [ "$status" -eq 1 ]
  says "wrong target" "~/gone.conf"
  says "broken link" "~/dangling.conf"
  says "not linked" "~/absent.conf"
}

@test "check: drift in one file is drift, even with clean files around it" {
  local m
  m=$(fixture_module mixed)
  fixture_file "$m" "a.conf"
  fixture_file "$m" "b.conf"
  fixture_file "$m" "c.conf"
  fs_link_tree "$m"
  rm "$HOME/b.conf"

  run fs_check_tree "$m"
  [ "$status" -eq 1 ]
  [[ $output == *"b.conf"* ]]
}

@test "check: warnings from a doctor pass reach the tally" {
  local m before
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig"
  before=$DOT_WARNINGS

  fs_check_tree "$m" >/dev/null || true

  [ "$DOT_WARNINGS" -gt "$before" ]
}

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

@test "report: several tallies are joined with a comma AND a space" {
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
  says files "none to link"
}

@test "pairs: Finder's metadata is not a file this repo links" {
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
