#!/usr/bin/env bats
#
# The module contract and the structural limits. Walks the same glob the driver
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
  local f fm bad=()
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
      # Every git command on the machine reads this file, and a malformed line
      # makes all of them fail. doctor.sh checks the GENERATED config.local and
      # never the tracked one next to it, which is the bigger of the two.
      */git/config) git config --file "$f" --list >/dev/null 2>&1 || bad+=("$f -- git cannot parse it") ;;
      # A skill whose frontmatter does not parse is not an error anywhere: it
      # simply never appears, which is the quiet failure this test is for.
      */skills/*/SKILL.md)
        fm=$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f' "$f")
        if ! printf '%s\n' "$fm" | dasel -i yaml -o json '' >/dev/null 2>&1; then
          bad+=("$f -- frontmatter is not YAML")
        elif ! printf '%s\n' "$fm" | dasel -i yaml -o json 'keys()' 2>/dev/null | grep -q '"description"'; then
          bad+=("$f -- frontmatter has no description; the skill will not load")
        fi
        ;;
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

@test "limit: bin/dot has exactly five verbs" {
  # Raised from three, deliberately and once: `add` and `remove` are the only
  # path that switches a module OFF. `apply` walks only the enabled list and
  # `uninstall.sh` is all-or-nothing, so without them a module you stopped
  # wanting kept its defaults and generated files forever. A sixth needs the
  # same argument -- a capability no existing verb can reach.
  [ "$(grep -c '^cmd_[a-z]*() {' "$DOT_ROOT/bin/dot")" -eq 5 ]
  local verb
  for verb in apply add remove config doctor; do
    grep -q "^  $verb)" "$DOT_ROOT/bin/dot"
  done
}

@test "only lib/ui.sh emits colour or glyphs" {
  # lib/CLAUDE.md has said this since the file was written, and nothing held it.
  # A printf with an escape anywhere else is a second place that decides what
  # output looks like, and the first one to disagree with NO_COLOR or with an
  # ASCII locale. Shipped shell only: tests/ builds fixtures out of escapes.
  local file offenders=()
  while IFS= read -r file; do
    [[ $file == */lib/ui.sh ]] && continue
    if grep -q $'\033' "$file"; then offenders+=("${file#"$DOT_ROOT"/}"); fi
  done < <(find "$DOT_ROOT/lib" "$DOT_ROOT/bin" "$DOT_ROOT/core" "$DOT_ROOT/modules" \
    -type f \( -name '*.sh' -o -name dot \))

  ((${#offenders[@]} == 0)) || {
    printf 'escape sequences outside lib/ui.sh: %s\n' "${offenders[*]}"
    return 1
  }
}

@test "a transcript carries no escape sequences" {
  # lib/ui.sh settles colour while stdout is still the terminal, which is the
  # only moment it can. The transcript therefore has to strip on the way into
  # the file, or every log is unreadable in an editor -- and the log is the
  # whole point of the line that names it.
  config_generate "A" "a@b.c" ""
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\nexport DOT_ROOT="%s"\n' "$DOT_ROOT" >"$HOME/.local/bin/dot"
  chmod +x "$HOME/.local/bin/dot"

  DOT_COLOR=1 run "$DOT_ROOT/bin/dot" apply

  local log="$DOT_STATE/logs/$DOT_RUN_ID-apply.log"
  [ -f "$log" ]
  ! grep -q $'\033' "$log"
  # The tail is there too: a stripper that loses the last lines is worse than
  # none, since those are the ones naming what went wrong.
  grep -q 'Summary' "$log"
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

@test "dev-cli: doctor.sh and remove.sh resolve mise's data dir alike" {
  # mise does not expose its default data dir for scripting, so both hooks
  # rebuild it. One of them drifting is a check looking where nothing lands.
  local dir="$DOT_ROOT/modules/dev-cli"
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

# --- invariants that span files (root CLAUDE.md) -----------------------------
#
# Each of these is a rule whose whole content is "these files must agree", and
# each was on the honour system until one of them had already drifted: the
# bash-5 list said four places while uninstall.sh had quietly become a fifth.

@test "bash 5: every place that guards it is named by all the others" {
  # install.sh installs it, core/Brewfile keeps brew from cleaning it up, and
  # three scripts refuse to run without it. A new guard that no comment mentions
  # is the drift this catches; so is a comment that still says "four".
  local -a places=(install.sh uninstall.sh bin/dot lib/dot.sh core/Brewfile)
  local f found

  # Every file in the list really does guard bash 5.
  for f in "${places[@]}"; do
    case $f in
      core/Brewfile) grep -q '^brew "bash"' "$DOT_ROOT/$f" ;;
      install.sh) grep -q 'brew install bash' "$DOT_ROOT/$f" ;;
      *) grep -q 'BASH_VERSINFO\[0\] < 5' "$DOT_ROOT/$f" ;;
    esac || {
      echo "$f is named as a bash-5 place but no longer guards bash 5"
      return 1
    }
  done

  # And no OTHER shipped file has grown a guard without joining the list.
  found=$(grep -rl 'BASH_VERSINFO\[0\] < 5' \
    "$DOT_ROOT"/install.sh "$DOT_ROOT"/uninstall.sh "$DOT_ROOT"/bin/dot \
    "$DOT_ROOT"/lib "$DOT_ROOT"/core "$DOT_ROOT"/modules 2>/dev/null |
    while IFS= read -r f; do
      case ${f#"$DOT_ROOT"/} in
        install.sh | uninstall.sh | bin/dot | lib/dot.sh) ;;
        *) echo "${f#"$DOT_ROOT"/}" ;;
      esac
    done || true)
  [ -z "$found" ] || {
    echo "a bash-5 guard nothing names: $found"
    echo "add it to the list in CLAUDE.md and to this test, or remove it"
    return 1
  }

  # The prose count must match the list. A stale number reads as a check.
  grep -q 'Bash 5 in five places' "$DOT_ROOT/CLAUDE.md" || {
    echo "root CLAUDE.md does not say five places; ${#places[@]} guard it"
    return 1
  }
}

@test "install.sh shares nothing: it runs before the repo has a library" {
  # Phase 0 is fetched by curl and runs before the clone exists. A `source` of
  # anything under lib/ would work on the developer's machine and fail on every
  # fresh one -- the single case CI cannot reproduce.
  # Comments stripped: they are allowed to NAME the library, and one of them
  # has to -- the bash-5 sibling list above is written in exactly these files.
  local code
  code=$(grep -vE '^[[:space:]]*#' "$DOT_ROOT/install.sh")

  run grep -nE '^[[:space:]]*(\.|source)[[:space:]]' <<<"$code"
  [ "$status" -ne 0 ] || {
    echo "install.sh sources a file; it runs before the repo exists:"
    echo "$output"
    return 1
  }
  run grep -n 'lib/dot\.sh\|DOT_ROOT' <<<"$code"
  [ "$status" -ne 0 ] || {
    echo "install.sh reaches into the library:"
    echo "$output"
    return 1
  }
}

@test "CI installs every quality gate, and nothing this repo does not declare" {
  # Two sets have to be there. modules/dotfiles-dev/Brewfile says it must stay
  # in step with ci.yml -- a gate CI omits is a suite that only runs where
  # someone happened to have the tool. And core/Brewfile, because the suite
  # runs `dot doctor`, which checks core's packages: CI was red for weeks over
  # a missing fzf, and nothing here said which package or why.
  local ci="$DOT_ROOT/.github/workflows/ci.yml" f missing=() undeclared=()
  local -a installed declared

  mapfile -t installed < <(sed -n 's/^[[:space:]]*run: brew install //p' "$ci" | tr ' ' '\n' | sort -u)
  [ "${#installed[@]}" -gt 0 ] || {
    echo "no 'brew install' line found in ci.yml"
    return 1
  }

  mapfile -t declared < <(sed -n 's/^brew "\([^"]*\)".*/\1/p' \
    "$DOT_ROOT"/core/Brewfile "$DOT_ROOT"/modules/*/Brewfile | sort -u)

  while IFS= read -r f; do
    printf '%s\n' "${installed[@]}" | grep -qxF "$f" || missing+=("$f")
  done < <(sed -n 's/^brew "\([^"]*\)".*/\1/p' \
    "$DOT_ROOT/modules/dotfiles-dev/Brewfile" "$DOT_ROOT/core/Brewfile" | sort -u)

  for f in "${installed[@]}"; do
    printf '%s\n' "${declared[@]}" | grep -qxF "$f" || undeclared+=("$f")
  done

  [ ${#missing[@]} -eq 0 ] || {
    echo "ci.yml does not install: ${missing[*]}"
    return 1
  }
  [ ${#undeclared[@]} -eq 0 ] || {
    echo "ci.yml installs what no Brewfile here declares: ${undeclared[*]}"
    return 1
  }
}

@test "the Makefile is the only copy of the check commands" {
  # CI, the README and CLAUDE.md all say `make check`. A workflow that inlined
  # `shellcheck ...` would be a second copy, free to disagree with the first.
  local found
  found=$(grep -rnE '^[[:space:]-]*(run:)?[[:space:]]*(shellcheck|shfmt|bats)[[:space:]]' \
    "$DOT_ROOT/.github/workflows" || true)
  [ -z "$found" ] || {
    echo "a workflow runs a check command directly; call make instead:"
    echo "$found"
    return 1
  }
}

@test "the README names every module" {
  # Two hand-maintained tables enumerate the modules, and nothing kept them in
  # step with the directory listing: adding modules/dotfiles-dev left both
  # stale, and only a reader would ever have noticed. The registry is the
  # filesystem; this is the one place that has to be told about it.
  local name missing=()
  while IFS= read -r name; do
    grep -qF "\`$name\`" "$DOT_ROOT/README.md" || missing+=("$name")
  done < <(modules_all)

  [ ${#missing[@]} -eq 0 ] || {
    printf 'the README does not mention: %s\n' "${missing[*]}"
    printf 'add it to the tool-module or package-set table under "## Modules"\n'
    return 1
  }
}

@test "no apply.sh changes anything in \$HOME under --dry-run" {
  # The counterpart to the remove.sh snapshot above, and the more important
  # half: apply.sh is the hook that WRITES. Every one of them gates on
  # DOT_DRY_RUN or delegates to fs_link, which does -- but "or a preview
  # becomes a run" (modules/CLAUDE.md) was a rule only remove.sh had a
  # generic test for.
  local name before after
  before=$(home_snapshot)
  while IFS= read -r name; do
    [ -f "$DOT_ROOT/modules/$name/apply.sh" ] || continue
    run env DOT_DRY_RUN=1 DOT_MODULE="$name" DOT_MODULE_DIR="$DOT_ROOT/modules/$name" \
      bash "$DOT_ROOT/modules/$name/apply.sh"
  done < <(modules_all)
  run env DOT_DRY_RUN=1 bash "$DOT_ROOT/core/apply.sh"
  after=$(home_snapshot)

  [ "$before" = "$after" ] || {
    echo "an apply.sh wrote to \$HOME during a dry run:"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    return 1
  }
}

@test "dry run: a hook that MERGES into an existing file still writes nothing" {
  # The generic snapshots above run against an empty sandbox $HOME, so every
  # hook that starts with `[[ -f $dest ]] || exit 0` returns before it reaches
  # the code that writes. claude-code is the one that rewrites a file already
  # there -- the case the dry-run rule exists for -- so it gets the file.
  command -v jq >/dev/null 2>&1 || skip 'no jq on this machine'

  local dest="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"
  printf '{"theme":"mine","permissions":{"defaultMode":"auto"}}\n' >"$dest"

  local before after hook
  before=$(home_snapshot)
  for hook in apply.sh remove.sh; do
    run env DOT_DRY_RUN=1 DOT_MODULE=claude-code \
      DOT_MODULE_DIR="$DOT_ROOT/modules/claude-code" \
      bash "$DOT_ROOT/modules/claude-code/$hook"
  done
  after=$(home_snapshot)

  [ "$before" = "$after" ] || {
    echo "a claude-code hook rewrote settings.json during a dry run:"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    return 1
  }
}

@test "home_snapshot sees an in-place rewrite, not just a new path" {
  # The guard on the guard. Every dry-run and read-only test above is only as
  # strong as this: a path listing alone called an overwritten settings.json
  # unchanged, which is how the rewrite it was written to catch got through.
  local before after
  mkdir -p "$HOME/.claude"
  printf '{"a":1}\n' >"$HOME/.claude/settings.json"
  before=$(home_snapshot)
  printf '{"a":2}\n' >"$HOME/.claude/settings.json"
  after=$(home_snapshot)

  [ "$before" != "$after" ] || {
    echo "home_snapshot cannot see a file's contents change"
    return 1
  }
}

@test "every verb is named in the usage text and in the README" {
  # bin/dot's dispatch is the one truth; the usage heredoc and the README only
  # describe it, and nothing stopped them drifting from it. When `add` and
  # `remove` arrived, five places still said "three verbs" and every one of
  # them had to be found by hand. This is the guard that would have found them.
  local -a verbs no_usage=() no_readme=()
  mapfile -t verbs < <(sed -n 's/^cmd_\([a-z][a-z]*\)() {$/\1/p' "$DOT_ROOT/bin/dot")

  # Non-empty first, or a rename makes this pass over nothing forever.
  [ "${#verbs[@]}" -gt 0 ] || {
    echo 'no cmd_* functions found in bin/dot'
    return 1
  }

  # The usage function alone, not the whole file: `cmd_add`'s own comments say
  # "add", and matching those would let a verb usage never lists slip through.
  # The verb is the label argument, which is what puts it in the column.
  local usage verb
  usage=$(sed -n '/^usage() {$/,/^}$/p' "$DOT_ROOT/bin/dot")

  for verb in "${verbs[@]}"; do
    grep -qE "^  say $verb " <<<"$usage" || no_usage+=("$verb")
    grep -qE "^dot $verb( |$)" "$DOT_ROOT/README.md" || no_readme+=("$verb")
  done

  if ((${#no_usage[@]} || ${#no_readme[@]})); then
    printf 'dispatch has: %s\n' "${verbs[*]}"
    ((${#no_usage[@]} == 0)) || printf 'usage() never lists: %s\n' "${no_usage[*]}"
    ((${#no_readme[@]} == 0)) || printf 'the README never shows: %s\n' "${no_readme[*]}"
    return 1
  fi
}

@test "the verb count in the docs is the count bin/dot actually has" {
  # The other half of the same drift: prose that names a NUMBER. Several files
  # say it one way or another, and a fifth verb made four of them wrong at once.
  # docs/ is globbed rather than listed: a new page there must be covered by
  # this the day it is written, not the day someone remembers to add it.
  #
  # The map runs word -> number, never the reverse: asked to find the word for
  # a count it does not know, this would have to skip, and a guard that skips
  # on the very change it exists to catch is not one.
  local n
  n=$(grep -c '^cmd_[a-z]*() {' "$DOT_ROOT/bin/dot")

  word_num() {
    case ${1,,} in
      one | first) printf 1 ;;
      two | second) printf 2 ;;
      three | third) printf 3 ;;
      four | fourth) printf 4 ;;
      five | fifth) printf 5 ;;
      six | sixth) printf 6 ;;
      seven | seventh) printf 7 ;;
      *) printf 0 ;;
    esac
  }

  # Newlines collapsed: prose wraps, and "Not a sixth\n  verb" is the same claim
  # as "not a sixth verb". `[^.]` keeps a match from spanning two sentences.
  local -a stale=() files=(bin/dot bin/CLAUDE.md CLAUDE.md README.md uninstall.sh)
  local file claim num flat doc
  while IFS= read -r doc; do
    files+=("${doc#"$DOT_ROOT"/}")
  done < <(find "$DOT_ROOT/docs" -maxdepth 1 -type f -name '*.md' | sort)

  for file in "${files[@]}"; do
    flat=$(tr '\n' ' ' <"$DOT_ROOT/$file")

    while IFS= read -r claim; do
      num=$(word_num "$claim")
      ((num == n)) || stale+=("$file says '$claim verbs'")
    done < <(grep -oiE '(one|two|three|four|five|six|seven) verbs' <<<"$flat" |
      awk '{print $1}')

    # "capped at three" -- the same claim without the word `verbs` after it,
    # which is how README.md kept saying three long after there were five.
    while IFS= read -r claim; do
      num=$(word_num "$claim")
      ((num == n)) || stale+=("$file says 'capped at $claim'")
    done < <(grep -oiE 'capped at +(one|two|three|four|five|six|seven)' <<<"$flat" |
      awk '{print $NF}')

    # And an ORDINAL naming the next verb that does not exist -- "a fourth
    # verb", "not a sixth verb". That one has to be n+1, not n.
    while IFS= read -r claim; do
      num=$(word_num "$claim")
      ((num == n + 1)) || stale+=("$file says '$claim verb'; the next one is $((n + 1))")
    done < <(grep -oiE '(first|second|third|fourth|fifth|sixth|seventh)[^.]{0,24}verb' \
      <<<"$flat" | awk '{print $1}')

    # And the digit in the limits table.
    while IFS= read -r claim; do
      ((claim == n)) || stale+=("$file says 'bin/dot | $claim verbs'")
    done < <(sed -n 's/.*| `bin\/dot` | \([0-9][0-9]*\) verbs.*/\1/p' "$DOT_ROOT/$file")
  done

  if ((${#stale[@]})); then
    printf 'bin/dot has %s verbs, but:\n' "$n"
    printf '  %s\n' "${stale[@]}"
    return 1
  fi
}
