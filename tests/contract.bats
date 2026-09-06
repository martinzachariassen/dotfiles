#!/usr/bin/env bats
#
# The module contract and the hard limits. Walks the same glob the driver
# walks, so no module is exempt. Changing a limit means editing this file.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "there is at least one module" {
  run modules_all
  [ "${#lines[@]}" -gt 0 ]
}

@test "every module has a parseable manifest with its one field" {
  local name manifest
  while IFS= read -r name; do
    manifest="$DOT_ROOT/modules/$name/module.toml"
    run dasel -i toml -o yaml description <"$manifest"
    [ "$status" -eq 0 ] || {
      echo "module '$name' is missing field 'description'"
      return 1
    }
  done < <(modules_all)
}

@test "module names are lowercase, and match their directory" {
  local name
  while IFS= read -r name; do
    [[ $name =~ ^[a-z][a-z0-9-]*$ ]] || {
      echo "bad module name: '$name'"
      return 1
    }
  done < <(modules_all)
}

@test "manifests carry no second field" {
  local name keys
  while IFS= read -r name; do
    keys=$(dasel -i toml -o yaml 'keys()' <"$(module_manifest "$name")" | sed 's/^- //' | sort | tr '\n' ' ')
    [ "$keys" = "description " ] || {
      echo "$name has unexpected manifest fields: $keys"
      return 1
    }
  done < <(modules_all)
}

@test "home/ contains no symlinks" {
  # A committed symlink would be linked to: a link to a link.
  local name found
  while IFS= read -r name; do
    found=$(find "$DOT_ROOT/modules/$name" -path '*/home/*' -type l 2>/dev/null)
    [ -z "$found" ] || {
      echo "$name has symlinks under home/: $found"
      return 1
    }
  done < <(modules_all)
}

@test "hooks source the library and are shellcheck-clean" {
  local name hook path
  while IFS= read -r name; do
    for hook in apply.sh doctor.sh remove.sh; do
      path="$DOT_ROOT/modules/$name/$hook"
      [ -f "$path" ] || continue
      grep -q 'lib/dot.sh' "$path" || {
        echo "$name/$hook does not source lib/dot.sh"
        return 1
      }
      run shellcheck -x "$path"
      [ "$status" -eq 0 ] || {
        echo "$name/$hook fails shellcheck"
        echo "$output"
        return 1
      }
    done
  done < <(modules_all)
}

@test "no doctor.sh changes anything in \$HOME" {
  # `colima status` created ~/.colima/_lima just by being asked. Snapshotting
  # around every hook is the only way this stays caught generically.
  local name before after
  before=$(home_snapshot)
  while IFS= read -r name; do
    [ -f "$DOT_ROOT/modules/$name/doctor.sh" ] || continue
    run env DOT_MODULE="$name" DOT_MODULE_DIR="$DOT_ROOT/modules/$name" \
      bash "$DOT_ROOT/modules/$name/doctor.sh"
  done < <(modules_all)
  after=$(home_snapshot)

  [ "$before" = "$after" ] || {
    echo "a doctor.sh wrote to \$HOME:"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    return 1
  }
}

@test "every profile refers only to modules that exist" {
  local profile name
  while IFS= read -r profile; do
    while IFS= read -r name; do
      module_exists "$name" || {
        echo "profile '$profile' lists unknown module '$name'"
        return 1
      }
    done < <(toml_list "$DOT_ROOT/profiles.toml" "profiles[\"$profile\"]")
  done < <(toml_list "$DOT_ROOT/profiles.toml" 'profiles.keys()')
}

@test "every script with a shebang is executable" {
  # The shim exec's bin/dot directly; a missing +x reads as a shim error.
  local found
  found=$(find "$DOT_ROOT" -path "$DOT_ROOT/.git" -prune -o \
    \( -name '*.sh' -o -name 'dot' \) -type f -print |
    while IFS= read -r f; do
      if head -1 "$f" | grep -q '^#!' && [ ! -x "$f" ]; then echo "$f"; fi
    done || true)
  [ -z "$found" ] || {
    echo "not executable: $found"
    return 1
  }
}

@test "Brewfiles exist only in core/ and modules/" {
  run bash -c "find '$DOT_ROOT' -name 'Brewfile*' -not -path '*/.git/*' | grep -cv -e '/core/' -e '/modules/'"
  [ "$output" = "0" ]
}

@test "a module contains no file the driver would ignore" {
  # modules/ssh/config once sat outside home/: looked installed, was inert,
  # and nothing caught it. The names below are the whole vocabulary.
  local stray=()
  for path in "$DOT_ROOT"/modules/*/*; do
    case ${path##*/} in
      module.toml | Brewfile | README.md) ;;
      apply.sh | doctor.sh | remove.sh) ;;
      home | data) [[ -d $path ]] || stray+=("${path#"$DOT_ROOT"/}") ;;
      *) stray+=("${path#"$DOT_ROOT"/}") ;;
    esac
  done

  [ ${#stray[@]} -eq 0 ] || {
    printf 'the driver reads none of these:\n'
    printf '  %s\n' "${stray[@]}"
    printf 'a config file belongs under the module home/, at its path in $HOME\n'
    return 1
  }
}

@test "data/ is module-private: nothing links it into \$HOME" {
  # The whole point of the directory. A config file for the USER goes under
  # home/ at its path in $HOME; data/ is what a module's own hooks read.
  local name found
  while IFS= read -r name; do
    [ -d "$DOT_ROOT/modules/$name/data" ] || continue
    found=$(fs_pairs "$DOT_ROOT/modules/$name" | grep -F "/data/" || true)
    [ -z "$found" ] || {
      echo "$name: data/ reached fs_pairs: $found"
      return 1
    }
  done < <(modules_all)
}

@test "every shipped config file parses" {
  # starship.toml, the mise config, cmux.json and the theme had no check of any
  # kind: linked into $HOME and read by a tool that fails quietly. zsh.bats and
  # ssh.bats do this for their own files; doing it generically here is what
  # stops the next module from shipping an unparseable one.
  local f bad=()
  while IFS= read -r f; do
    case $f in
      *.json) json_parses "$f" || bad+=("$f -- not JSON or JSONC") ;;
      # taplo, not dasel: dasel stops at a malformed line, keeps what it read
      # and exits 0 -- the exact reason cfg_parse_problems exists.
      *.toml) taplo check "$f" >/dev/null 2>&1 || bad+=("$f -- not TOML") ;;
      *.yaml | *.yml) dasel -i yaml -o json '' <"$f" >/dev/null 2>&1 || bad+=("$f -- not YAML") ;;
      *.sh) shellcheck "$f" >/dev/null 2>&1 || bad+=("$f -- shellcheck") ;;
      *.zsh | */.zshrc | */.zshenv | */.zprofile) zsh -n "$f" 2>/dev/null || bad+=("$f -- zsh -n") ;;
    esac
  done < <(find "$DOT_ROOT/modules" \( -path '*/home/*' -o -path '*/data/*' \) -type f)

  [ ${#bad[@]} -eq 0 ] || {
    printf 'shipped file does not parse:\n'
    printf '  %s\n' "${bad[@]}"
    return 1
  }
}

@test "no remove.sh changes anything in \$HOME under --dry-run" {
  # claude-code/remove.sh rewrote settings.json during `uninstall.sh --dry-run`,
  # so the preview mutated the thing it was previewing. Snapshotting around
  # every hook is the only way this stays caught generically.
  local name before after
  before=$(home_snapshot)
  while IFS= read -r name; do
    [ -f "$DOT_ROOT/modules/$name/remove.sh" ] || continue
    run env DOT_DRY_RUN=1 DOT_MODULE="$name" DOT_MODULE_DIR="$DOT_ROOT/modules/$name" \
      bash "$DOT_ROOT/modules/$name/remove.sh"
  done < <(modules_all)
  after=$(home_snapshot)

  [ "$before" = "$after" ] || {
    echo "a remove.sh wrote to \$HOME during a dry run:"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    return 1
  }
}

@test "every alias replacement is installed by the zsh module" {
  # `alias ls=eza` with no eza is a shell where ls is command-not-found.
  local cmd
  for cmd in eza bat rg; do
    case $cmd in rg) pkg=ripgrep ;; *) pkg=$cmd ;; esac
    grep -qE "^brew \"$pkg\"" "$DOT_ROOT/modules/zsh/Brewfile" || {
      echo "aliases.zsh uses $cmd but modules/zsh/Brewfile does not install $pkg"
      return 1
    }
  done
}

# --- hard limits (root CLAUDE.md) --------------------------------------------

@test "limit: lib/ has exactly 7 files and no subdirectories" {
  [ "$(find "$DOT_ROOT/lib" -mindepth 1 -maxdepth 1 -type f -name '*.sh' | wc -l | tr -d ' ')" -eq 7 ]
  [ -z "$(find "$DOT_ROOT/lib" -mindepth 1 -type d)" ]
}

@test "limit: lib/wizard.sh is at most 60 lines of code" {
  local n
  n=$(grep -cvE '^[[:space:]]*(#|$)' "$DOT_ROOT/lib/wizard.sh")
  [ "$n" -le 60 ] || {
    echo "lib/wizard.sh has $n lines of code; the cap is 60"
    return 1
  }
}

@test "limit: bin/dot has exactly three verbs" {
  [ "$(grep -c '^cmd_[a-z]*() {' "$DOT_ROOT/bin/dot")" -eq 3 ]
  local verb
  for verb in apply config doctor; do
    grep -q "^  $verb)" "$DOT_ROOT/bin/dot"
  done
}

@test "claude-code: all three hooks derive \$want from data/settings.json alike" {
  # Replaces the old allow/deny literal check: the literals are gone, and the
  # only thing left to keep in step is how each hook reads the data file.
  local dir="$DOT_ROOT/modules/claude-code" key
  for key in '^data=' '^want='; do
    [ "$(grep "$key" "$dir/apply.sh")" = "$(grep "$key" "$dir/doctor.sh")" ]
    [ "$(grep "$key" "$dir/apply.sh")" = "$(grep "$key" "$dir/remove.sh")" ]
  done
  # doctor reports the leaves remove deletes; a drifted definition would let
  # doctor call a machine clean that remove would then not clean up.
  [ "$(grep 'def leaves' "$dir/doctor.sh" | tr -d ' ')" \
    = "$(grep 'def leaves' "$dir/remove.sh" | tr -d ' ')" ]
}
