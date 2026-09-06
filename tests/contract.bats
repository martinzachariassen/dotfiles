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
      # A row that lost its tabs reads as a domain with no key: `defaults write`
      # would then be called with too few arguments, or the wrong ones.
      *.tsv) awk -F'\t' '/^#/ || NF == 0 { next } NF < 4 || NF > 5 { exit 1 }' "$f" || bad+=("$f -- not a 4/5-column TSV") ;;
      # Every line is an argument to `go install`: module path, then @version.
      */go-tools.txt) awk '/^[[:space:]]*(#|$)/ { next } !/^[a-z0-9._\/-]+@[a-zA-Z0-9._-]+$/ { exit 1 }' "$f" || bad+=("$f -- not one go module path per line") ;;
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

  # And all three agree on what an acceptable settings.json IS. One hook left
  # on `jq -e .` would go back to calling `null` a syntax error, or would let
  # apply merge into an array that remove then cannot take its keys back out of.
  local hook
  for hook in apply.sh doctor.sh remove.sh; do
    if ! grep -q "jq -r 'type'" "$dir/$hook"; then
      echo "$hook does not ask jq for the type of settings.json"
      return 1
    fi
    # Comments stripped: apply.sh's own comment explains why `jq -e .` is wrong.
    # `if`, not `grep && return`: a false last test is a failing test (tests/CLAUDE.md).
    if grep -v '^[[:space:]]*#' "$dir/$hook" | grep -q 'jq -e \.'; then
      echo "$hook still uses \`jq -e .\`, which rejects null and false"
      return 1
    fi
  done
}

@test "macos-defaults: all three hooks read data/defaults.tsv alike" {
  # apply writes every row, doctor compares every row, remove warns about the
  # domains in column 1. Pointing one of them somewhere else would let doctor
  # call a machine clean that apply never wrote to.
  local dir="$DOT_ROOT/modules/macos-defaults"
  [ "$(grep '^data=' "$dir/apply.sh")" = "$(grep '^data=' "$dir/doctor.sh")" ]
  [ "$(grep '^data=' "$dir/apply.sh")" = "$(grep '^data=' "$dir/remove.sh")" ]
}

@test "macos-defaults: remove.sh names no domain by hand" {
  # The list is what the user is told was changed irreversibly. Typed out, it
  # goes stale the first time apply.sh gains a domain, and nothing says so.
  run grep -nE '(com\.apple\.[a-zA-Z]+|NSGlobalDomain)' "$DOT_ROOT/modules/macos-defaults/remove.sh"
  [ "$status" -ne 0 ] || {
    echo "remove.sh hardcodes a domain; cut it from data/defaults.tsv instead:"
    echo "$output"
    return 1
  }
}

@test "macos-defaults: doctor.sh and remove.sh read a bool row alike" {
  # The TSV writes true/false; `defaults read` prints 1/0. Two hooks compare
  # against that column now, and one of them drifting is either a doctor that
  # reports drift on a clean Mac or a remove.sh that stays silent about a
  # machine it did change irreversibly.
  local dir="$DOT_ROOT/modules/macos-defaults" f
  for f in doctor.sh remove.sh; do
    grep -qE 'bool:true\)[^;]*=1 ;;' "$dir/$f" || {
      echo "$f does not map a bool true to 1"
      return 1
    }
    grep -qE 'bool:false\)[^;]*=0 ;;' "$dir/$f" || {
      echo "$f does not map a bool false to 0"
      return 1
    }
  done
}

@test "dev-cli: the hooks read data/go-tools.txt and mise's data dir alike" {
  # apply installs every line, doctor looks for the binary each line names.
  # Pointing one of them elsewhere would let doctor call a machine clean that
  # apply never installed to.
  local dir="$DOT_ROOT/modules/dev-cli"
  [ "$(grep '^data=' "$dir/apply.sh")" = "$(grep '^data=' "$dir/doctor.sh")" ]
  # mise does not expose its default data dir for scripting, so both hooks
  # rebuild it. One of them drifting is a check looking where nothing lands.
  [ "$(grep '^mise_data=' "$dir/doctor.sh")" = "$(grep '^mise_data=' "$dir/remove.sh")" ]
}

@test "dev-cli: doctor.sh never invokes mise" {
  # `mise ls` CREATES ~/.local/share/mise and ~/.local/state/mise on a machine
  # that has neither -- the check would write to the $HOME it is checking, the
  # same trap `colima status` set in modules/containers. The generic doctor.sh
  # snapshot above only catches this on a machine that HAS mise, and CI has none.
  #
  # A stub rather than a grep: the question is whether the hook RUNS mise, and
  # a grep also hits the word inside its own output strings. `command -v` only
  # resolves the file, so a passing hook never executes this.
  # The stub records to a FILE, not stderr: `mise ls >/dev/null 2>&1` would
  # swallow anything it printed, and that is exactly the call being guarded.
  local stub="$DOT_TMP/bin" ran="$DOT_TMP/mise_ran"
  mkdir -p "$stub"
  cat >"$stub/mise" <<EOF
#!/bin/sh
echo "mise \$*" >>"$ran"
exit 1
EOF
  chmod +x "$stub/mise"

  PATH="$stub:$PATH" run env DOT_ROOT="$DOT_ROOT" DOT_MODULE=dev-cli \
    DOT_MODULE_DIR="$DOT_ROOT/modules/dev-cli" bash "$DOT_ROOT/modules/dev-cli/doctor.sh"

  [ ! -f "$ran" ] || {
    echo "doctor.sh invoked mise; read the install tree instead:"
    cat "$ran"
    return 1
  }
}

@test "containers: apply.sh and remove.sh agree on the docker plugins" {
  # remove.sh only unlinks what it names, so a plugin apply.sh gains and this
  # list does not is a link left behind in a $HOME the sweep cannot see. The
  # whole list, not a substring: appending a name has to be what fails.
  local dir="$DOT_ROOT/modules/containers" list
  list() { sed -n 's/.*for plugin in \(.*\); do.*/\1/p' "$1"; }
  [ -n "$(list "$dir/apply.sh")" ]
  [ "$(list "$dir/apply.sh")" = "$(list "$dir/remove.sh")" ]
}

@test "containers: doctor.sh and remove.sh agree on the colima VM path" {
  # ~/.colima, not ~/.colima/default, and `colima status` creates the VM
  # directory it was asked about. Both hooks say so in a comment; this is the
  # check the comments promise.
  local dir="$DOT_ROOT/modules/containers"
  [ "$(grep -c 'HOME/\.colima/default' "$dir/doctor.sh")" -ge 1 ]
  [ "$(grep -c 'HOME/\.colima/default' "$dir/remove.sh")" -ge 1 ]
  [ -z "$(grep -oE 'HOME/\.colima[a-z/._-]*' "$dir/remove.sh" | grep -v 'HOME/\.colima/default' || true)" ]
}
