#!/usr/bin/env bats

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
  local f fm bad=()
  while IFS= read -r f; do
    case $f in
      *.json) json_parses "$f" || bad+=("$f -- not JSON or JSONC") ;;
      *.toml | */mise.lock) taplo check "$f" >/dev/null 2>&1 || bad+=("$f -- not TOML") ;;
      *.yaml | *.yml) dasel -i yaml -o json '' <"$f" >/dev/null 2>&1 || bad+=("$f -- not YAML") ;;
      *.tsv) awk -F'\t' '/^#/ || NF == 0 { next } NF < 4 || NF > 6 { exit 1 }' "$f" || bad+=("$f -- not a 4-to-6-column TSV") ;;
      */git/config) git config --file "$f" --list >/dev/null 2>&1 || bad+=("$f -- git cannot parse it") ;;
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
  local cmd
  for cmd in eza bat rg; do
    case $cmd in rg) pkg=ripgrep ;; *) pkg=$cmd ;; esac
    grep -qE "^brew \"$pkg\"" "$DOT_ROOT/modules/zsh/Brewfile" || {
      echo "aliases.zsh uses $cmd but modules/zsh/Brewfile does not install $pkg"
      return 1
    }
  done
}

@test "limit: lib/ has exactly 7 files and no subdirectories" {
  [ "$(find "$DOT_ROOT/lib" -mindepth 1 -maxdepth 1 -type f -name '*.sh' | wc -l | tr -d ' ')" -eq 7 ]
  [ -z "$(find "$DOT_ROOT/lib" -mindepth 1 -type d)" ]
}

@test "limit: bin/dot has exactly five verbs" {
  [ "$(grep -c '^cmd_[a-z]*() {' "$DOT_ROOT/bin/dot")" -eq 5 ]
  local verb
  for verb in apply add remove config doctor; do
    grep -q "^  $verb)" "$DOT_ROOT/bin/dot"
  done
}

@test "only lib/ui.sh emits colour or glyphs" {
  local file offenders=()
  while IFS= read -r file; do
    [[ $file == */lib/ui.sh ]] && continue
    if grep -qE '\\(033|e\[|x1[bB])' "$file" ||
      [[ -n $(LC_ALL=C tr -d '\11\12\40-\176' <"$file") ]]; then
      offenders+=("${file#"$DOT_ROOT"/}")
    fi
  done < <(find "$DOT_ROOT/lib" "$DOT_ROOT/bin" "$DOT_ROOT/core" "$DOT_ROOT/modules" \
    -type f \( -name '*.sh' -o -name dot \) \
    -not -path '*/home/*' -not -path '*/data/*')

  ((${#offenders[@]} == 0)) || {
    printf 'colour or glyphs outside lib/ui.sh: %s\n' "${offenders[*]}"
    return 1
  }
}

@test "the colour-and-glyph contract can actually see an offender" {
  local probe="$DOT_TMP/probe.sh"

  cat >"$probe" <<'EOF'
red=$'\033[31m'
EOF
  grep -qE '\\(033|e\[|x1[bB])' "$probe"

  cat >"$probe" <<'EOF'
printf '  ✗ broke\n'
EOF
  [ -n "$(LC_ALL=C tr -d '\11\12\40-\176' <"$probe")" ]

  cat >"$probe" <<'EOF'
printf '  x broke\n'
EOF
  ! grep -qE '\\(033|e\[|x1[bB])' "$probe"
  [ -z "$(LC_ALL=C tr -d '\11\12\40-\176' <"$probe")" ]
}

@test "nothing bin/dot runs prompts with read -p" {
  local pattern='read[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*p'
  grep -qE "$pattern" <<<'read -r -p "Write? " reply'
  grep -qE "$pattern" <<<'read -rp "Write? " reply'
  ! grep -qE "$pattern" <<<'read -r -d "" src'

  local hits
  hits=$(grep -rnE --include='*.sh' --include=dot "$pattern" \
    "$DOT_ROOT/lib" "$DOT_ROOT/bin" "$DOT_ROOT/core" "$DOT_ROOT/modules" |
    grep -vE ':[0-9]+:[[:space:]]*#' || true)
  [ -z "$hits" ] || {
    printf 'read -p under the transcript:\n%s\n' "$hits"
    return 1
  }
}

@test "a transcript carries no escape sequences" {
  config_generate "A" "a@b.c" ""
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\nexport DOT_ROOT="%s"\n' "$DOT_ROOT" >"$HOME/.local/bin/dot"
  chmod +x "$HOME/.local/bin/dot"

  DOT_COLOR=1 run "$DOT_ROOT/bin/dot" apply

  local log="$DOT_STATE/logs/$DOT_RUN_ID-apply.log"
  [ -f "$log" ]
  ! grep -q $'\033' "$log"
  grep -q 'Summary' "$log"
}

@test "a transcript keeps the lines of the run that died" {
  config_generate "A" "a@b.c" "$(printf 'git\nno-such-module\n')"

  DOT_COLOR=1 run "$DOT_ROOT/bin/dot" apply
  [ "$status" -ne 0 ]

  local log="$DOT_STATE/logs/$DOT_RUN_ID-apply.log"
  [ -f "$log" ]
  grep -q 'no-such-module' "$log"
  grep -q 'available' "$log"
  ! grep -q $'\033' "$log"
}

@test "claude-code: all three hooks derive \$want from data/settings.json alike" {
  local dir="$DOT_ROOT/modules/claude-code" key
  for key in '^data=' '^want='; do
    [ "$(grep "$key" "$dir/apply.sh")" = "$(grep "$key" "$dir/doctor.sh")" ]
    [ "$(grep "$key" "$dir/apply.sh")" = "$(grep "$key" "$dir/remove.sh")" ]
  done
  [ "$(grep 'def leaves' "$dir/doctor.sh" | tr -d ' ')" \
    = "$(grep 'def leaves' "$dir/remove.sh" | tr -d ' ')" ]

  local hook
  for hook in apply.sh doctor.sh remove.sh; do
    if ! grep -q "jq -r 'type'" "$dir/$hook"; then
      echo "$hook does not ask jq for the type of settings.json"
      return 1
    fi
    if grep -v '^[[:space:]]*#' "$dir/$hook" | grep -q 'jq -e \.'; then
      echo "$hook still uses \`jq -e .\`, which rejects null and false"
      return 1
    fi
  done
}

@test "macos-defaults: all three hooks read data/defaults.tsv alike" {
  local dir="$DOT_ROOT/modules/macos-defaults"
  [ "$(grep '^data=' "$dir/apply.sh")" = "$(grep '^data=' "$dir/doctor.sh")" ]
  [ "$(grep '^data=' "$dir/apply.sh")" = "$(grep '^data=' "$dir/remove.sh")" ]
}

@test "macos-defaults: remove.sh names no domain by hand" {
  run grep -nE '(com\.apple\.[a-zA-Z]+|NSGlobalDomain)' "$DOT_ROOT/modules/macos-defaults/remove.sh"
  [ "$status" -ne 0 ] || {
    echo "remove.sh hardcodes a domain; cut it from data/defaults.tsv instead:"
    echo "$output"
    return 1
  }
}

@test "macos-defaults: doctor.sh and remove.sh read a bool row alike" {
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
  local dir="$DOT_ROOT/modules/dev-cli"
  [ "$(grep '^mise_data=' "$dir/doctor.sh")" = "$(grep '^mise_data=' "$dir/remove.sh")" ]
}

@test "dev-cli: every sign-in row names a package this module installs" {
  local dir="$DOT_ROOT/modules/dev-cli"
  local cmd pkg rest missing=() rows=0
  while IFS=$'\t' read -r cmd pkg rest; do
    [[ -n $cmd && $cmd != '#'* ]] || continue
    ((++rows))
    grep -qE "^(brew|cask) \"$pkg\"" "$dir/Brewfile" || missing+=("$cmd -> $pkg")
  done <"$dir/data/signin.tsv"

  [ "$rows" -gt 0 ] || {
    echo 'data/signin.tsv has no rows, only comments'
    return 1
  }
  [ ${#missing[@]} -eq 0 ] || {
    printf 'signin.tsv names a package modules/dev-cli/Brewfile does not:\n'
    printf '  %s\n' "${missing[@]}"
    return 1
  }
}

@test "apps: every launch row names a cask this module installs" {
  local dir="$DOT_ROOT/modules/apps"
  local app cask rest missing=() rows=0
  while IFS=$'\t' read -r app cask rest; do
    [[ -n $app && $app != '#'* ]] || continue
    ((++rows))
    grep -qE "^cask \"$cask\"" "$dir/Brewfile" || missing+=("$app -> $cask")
  done <"$dir/data/launch.tsv"

  [ "$rows" -gt 0 ] || {
    echo 'data/launch.tsv has no rows, only comments'
    return 1
  }
  [ ${#missing[@]} -eq 0 ] || {
    printf 'launch.tsv names a cask modules/apps/Brewfile does not:\n'
    printf '  %s\n' "${missing[@]}"
    return 1
  }
}

@test "dev-cli: doctor.sh never invokes mise" {
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
  local dir="$DOT_ROOT/modules/containers" list
  list() { sed -n 's/.*for plugin in \(.*\); do.*/\1/p' "$1"; }
  [ -n "$(list "$dir/apply.sh")" ]
  [ "$(list "$dir/apply.sh")" = "$(list "$dir/remove.sh")" ]
}

@test "containers: doctor.sh and remove.sh agree on the colima VM path" {
  local dir="$DOT_ROOT/modules/containers"
  [ "$(grep -c 'HOME/\.colima/default' "$dir/doctor.sh")" -ge 1 ]
  [ "$(grep -c 'HOME/\.colima/default' "$dir/remove.sh")" -ge 1 ]
  [ -z "$(grep -oE 'HOME/\.colima[a-z/._-]*' "$dir/remove.sh" | grep -v 'HOME/\.colima/default' || true)" ]
}

op_env_bad_lines() {
  awk '/^#/ || !NF { next } !/^[A-Z][A-Z0-9_]*=op:\/\/[^ \t]+$/ { printf "%s ", NR }' "$1"
}

@test "zsh: the op env file holds references, never a value" {
  local bad
  bad=$(op_env_bad_lines "$DOT_ROOT/modules/zsh/home/.config/op/env")
  [ -z "$bad" ] || {
    printf 'op/env line %sis not NAME=op://...; the file holds references only\n' "$bad"
    return 1
  }
}

@test "zsh: the op env probe can actually see a value" {
  local f="$DOT_TMP/env"
  printf '# c\n\nOK=op://V/I/credential\nBAD=sk-abc123\n' >"$f"
  [ "$(op_env_bad_lines "$f")" = "4 " ]
}

@test "bash 5: every place that guards it is named by all the others" {
  local -a places=(install.sh uninstall.sh bin/dot lib/dot.sh core/Brewfile)
  local f found

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

  grep -q 'Bash 5 in five places' "$DOT_ROOT/CLAUDE.md" || {
    echo "root CLAUDE.md does not say five places; ${#places[@]} guard it"
    return 1
  }
}

@test "install.sh shares nothing: it runs before the repo has a library" {
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

@test "every setting a hook reads is documented where a reader looks" {
  local mod key call missing=() seen=0
  while IFS= read -r call; do
    seen=$((seen + 1))
    mod=$(awk '{print $2}' <<<"$call")
    key=$(awk '{print $3}' <<<"$call")
    grep -qF "\`$key\`" "$DOT_ROOT/modules/$mod/README.md" 2>/dev/null ||
      missing+=("modules/$mod/README.md: $key")
    grep -qF "\`$key\`" "$DOT_ROOT/docs/configuration.md" ||
      missing+=("docs/configuration.md: $key")
  done < <(grep -rhoE 'module_setting(_bool)? [a-z-]+ [a-z_]+' \
    "$DOT_ROOT"/modules/*/apply.sh "$DOT_ROOT"/modules/*/doctor.sh \
    "$DOT_ROOT"/modules/*/remove.sh 2>/dev/null | sort -u)

  [ "$seen" -gt 0 ] || {
    echo 'no module_setting call was found at all'
    return 1
  }
  [ ${#missing[@]} -eq 0 ] || {
    printf 'a setting a hook reads is named nowhere a reader would look:\n'
    printf '  %s\n' "${missing[@]}"
    return 1
  }
}

@test "no apply.sh changes anything in \$HOME under --dry-run" {
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
  local -a verbs no_usage=() no_readme=()
  mapfile -t verbs < <(sed -n 's/^cmd_\([a-z][a-z]*\)() {$/\1/p' "$DOT_ROOT/bin/dot")

  [ "${#verbs[@]}" -gt 0 ] || {
    echo 'no cmd_* functions found in bin/dot'
    return 1
  }

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

  local -a stale=() files=(bin/dot CLAUDE.md README.md uninstall.sh)
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

    while IFS= read -r claim; do
      num=$(word_num "$claim")
      ((num == n)) || stale+=("$file says 'capped at $claim'")
    done < <(grep -oiE 'capped at +(one|two|three|four|five|six|seven)' <<<"$flat" |
      awk '{print $NF}')

    while IFS= read -r claim; do
      num=$(word_num "$claim")
      ((num == n + 1)) || stale+=("$file says '$claim verb'; the next one is $((n + 1))")
    done < <(grep -oiE '(first|second|third|fourth|fifth|sixth|seventh)[^.]{0,24}verb' \
      <<<"$flat" | awk '{print $1}')

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
