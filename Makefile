# Every check this repo runs. The commands live here and nowhere else, so a
# workflow cannot grow a second copy free to disagree; contract.bats holds
# that. Logic belongs in lib/, not here.
#
#   make check       lint, fmt-check, test (what CI runs)
#   make fmt         rewrite files to the project's formatting
#   make brew-audit  ask Homebrew whether the Brewfiles still resolve

SHIPPED := install.sh uninstall.sh bin/dot lib/*.sh core/*.sh \
	modules/*/apply.sh modules/*/doctor.sh modules/*/remove.sh
FORMATTED := install.sh uninstall.sh bin/dot lib/*.sh core/*.sh modules/*/*.sh tests/helper.bash

SHFMT_FLAGS := -i 2 -ci

.PHONY: check lint fmt fmt-check test brew-audit

check: lint fmt-check test

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
# changes when Homebrew does. See docs/development.md.
brew-audit:
	@echo "==> brew audit"
	@DOT_BREW_AUDIT=1 bats tests/brewfiles.bats
