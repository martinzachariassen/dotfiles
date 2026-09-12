---
name: dotfiles-test
description: Sanity-check skill for verifying that skills symlinked in from the dotfiles repo are picked up by Claude Code. Use when the user asks to test or verify the dotfiles skill setup.
---

# Dotfiles test skill

This skill exists only to prove that a skill placed under
`modules/claude-code/home/.claude/skills/` in the dotfiles repo, then linked
into `~/.claude/skills/` by `dot apply`, is picked up by Claude Code.

When invoked, reply with exactly:

> Dotfiles skill wiring works — this file is symlinked from the dotfiles repo.

Do nothing else.
