# Every check this repo runs. CI, README and CLAUDE.md all say `make check`;
# the commands live here and nowhere else. Logic belongs in lib/, not here.
#
#   make check       lint, fmt-check, test, size (what CI runs)
#   make fmt         rewrite files to the project's formatting
#   make brew-audit  ask Homebrew whether the Brewfiles still resolve

SHIPPED := install.sh uninstall.sh bin/dot lib/*.sh core/*.sh \
	modules/*/apply.sh modules/*/doctor.sh modules/*/remove.sh
FORMATTED := install.sh uninstall.sh bin/dot lib/*.sh core/*.sh modules/*/*.sh tests/helper.bash

SHFMT_FLAGS := -i 2 -ci

# Two budgets. The engine is the part v1 rotted in; the number tracks what the
# engine is FOR, never what it weighs this week. Modules are the growth axis:
# each capped on its own, the sum is not. Tests are reported, never capped.
ENGINE_BUDGET := 2500
MODULE_BUDGET := 150

# Listed, not found: adding an engine file is a decision made here in the open.
ENGINE := install.sh uninstall.sh bin/dot lib/*.sh core/*.sh

.PHONY: check lint fmt fmt-check test size brew-audit

check: lint fmt-check test size

lint:
	@echo "==> shellcheck"
	@shellcheck -x $(SHIPPED)

fmt:
	@echo "==> shfmt (writing)"
	@shfmt -w $(SHFMT_FLAGS) $(FORMATTED)

fmt-check:
	@echo "==> shfmt"
	@shfmt -d $(SHFMT_FLAGS) $(FORMATTED)

test:
	@echo "==> bats"
	@bats tests/

# Deliberately NOT part of `check`: it needs the network and its verdict
# changes when Homebrew changes, so it must not fail a pull request about
# something else. CI runs it on a schedule instead.
brew-audit:
	@echo "==> brew audit"
	@DOT_BREW_AUDIT=1 bats tests/brewfiles.bats

size:
	@echo "==> size"
	@over=0; \
	engine=$$(wc -l $(ENGINE) | tail -1 | awk '{print $$1}'); \
	if [ "$$engine" -gt $(ENGINE_BUDGET) ]; then \
	  echo "    engine:   $$engine lines -- OVER the $(ENGINE_BUDGET)-line budget" >&2; \
	  over=1; \
	else \
	  echo "    engine:   $$engine lines (budget $(ENGINE_BUDGET))"; \
	fi; \
	modules=0; \
	for dir in modules/*/; do \
	  name=$$(basename "$$dir"); \
	  n=$$(cat "$$dir"*.sh 2>/dev/null | wc -l | tr -d ' '); \
	  modules=$$((modules + n)); \
	  if [ "$$n" -gt $(MODULE_BUDGET) ]; then \
	    echo "      $$name: $$n lines -- OVER the $(MODULE_BUDGET)-line cap" >&2; \
	    over=1; \
	  elif [ "$$n" -gt 0 ]; then \
	    echo "      $$name: $$n"; \
	  fi; \
	done; \
	echo "    modules:  $$modules lines (each capped at $(MODULE_BUDGET); the sum is not)"; \
	tests=$$(find tests -type f | xargs wc -l | tail -1 | awk '{print $$1}'); \
	echo "    tests:    $$tests lines (uncapped)"; \
	if [ "$$over" -ne 0 ]; then \
	  echo "    cut something, or move it -- do not raise the number." >&2; \
	  exit 1; \
	fi
