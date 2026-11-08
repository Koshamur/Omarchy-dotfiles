SHELL := /bin/bash

.DEFAULT_GOAL := help

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SCRIPTS := setup.sh $(wildcard Shell/*.sh)

.PHONY: help install configs scripts theme force check syntax shellcheck verify update

help:
	@echo "Omarchy dotfiles — доступные команды:"
	@echo ""
	@echo "  make install     применить конфиги и выполнить скрипты из Shell/"
	@echo "  make configs     только скопировать конфиги (hypr, ghostty)"
	@echo "  make scripts     только выполнить скрипты из Shell/"
	@echo "  make theme       установить и применить тему Fjord Frost"
	@echo "  make force       скопировать и выполнить всё заново"
	@echo "  make check       bash -n + shellcheck для всех скриптов"
	@echo "  make syntax      только проверка синтаксиса bash -n"
	@echo "  make shellcheck  только shellcheck"
	@echo "  make verify      проверить состояние системы (в setup.sh не входит)"
	@echo "  make update      git pull --ff-only и повторное применение"
	@echo ""

install:
	cd "$(ROOT)" && ./setup.sh

configs:
	cd "$(ROOT)" && ./setup.sh --configs-only

scripts:
	cd "$(ROOT)" && ./setup.sh --scripts-only

theme:
	cd "$(ROOT)" && ./Shell/theme.sh

force:
	cd "$(ROOT)" && ./setup.sh --force

check: syntax shellcheck

syntax:
	@cd "$(ROOT)" && for f in $(SCRIPTS); do \
		printf 'bash -n %s\n' "$$f"; \
		bash -n "$$f" || exit 1; \
	done

shellcheck:
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "shellcheck не установлен: sudo pacman -S shellcheck" >&2; \
		exit 1; \
	}
	@cd "$(ROOT)" && shellcheck -S warning $(SCRIPTS)

verify:
	cd "$(ROOT)" && ./Shell/verify.sh

update:
	@if git -C "$(ROOT)" rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		git -C "$(ROOT)" pull --ff-only; \
	else \
		echo "Это не git-репозиторий — git pull пропущен"; \
	fi
	cd "$(ROOT)" && ./setup.sh
