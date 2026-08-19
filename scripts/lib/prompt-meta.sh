#!/usr/bin/env bash
# prompt-meta.sh — read prompt metadata out of .chezmoi.toml.tmpl so callers pass
# chezmoi's non-interactive --prompt* flags without hardcoding the question text
# (chezmoi keys those flags by the prompt message, not the data key).
# Callers must set $TMPL to the .chezmoi.toml.tmpl path before calling.
# shellcheck disable=SC2034

[ -n "${__DOTFILES_PROMPT_META_SH:-}" ] && return 0
__DOTFILES_PROMPT_META_SH=1

# prompt_msg KEY — the message chezmoi shows for a prompt*Once KEY; reading it
# here (vs. hardcoding) keeps the flag text and the template in sync.
prompt_msg() {
    sed -nE "s/.*prompt(String|Choice|Multichoice)Once \. \"$1\"[[:space:]]+\"([^\"]*)\".*/\2/p" \
        "$TMPL" | head -n1
}

# prompt_choices KEY — the (list "a" "b" ...) options for a promptChoiceOnce KEY.
prompt_choices() {
    sed -nE "s/.*promptChoiceOnce \. \"$1\"[[:space:]]+\"[^\"]*\"[[:space:]]+\(list ([^)]*)\).*/\1/p" \
        "$TMPL" | head -n1 | grep -oE '"[^"]+"' | tr -d '"'
}
