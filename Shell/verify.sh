#!/usr/bin/env bash
# =============================================================================
#  verify.sh
#
#  Проверяет состояние системы после запуска setup.sh.
#  В setup.sh намеренно не включён — запускается отдельно:
#
#      make verify
#      ./Shell/verify.sh
#
#  Код возврата: 0 — ошибок нет, 1 — есть ошибки.
#  Предупреждения не влияют на код возврата.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/system-setup"
OMARCHY_STATE="$HOME/.local/state/omarchy"
CURRENT_NAME_FILE="$OMARCHY_STATE/current/theme.name"
CURRENT_THEME_DIR="$OMARCHY_STATE/current/theme"
EXPECTED_THEME="fjord-frost"

PASS=0
WARN=0
ERRORS=0

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'
  C_RESET=$'\033[0m'
else
  C_BLUE=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
  C_RESET=''
fi

section() { printf '\n%s== %s ==%s\n' "$C_BLUE" "$*" "$C_RESET"; }
pass()    { PASS=$((PASS + 1)); printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { WARN=$((WARN + 1)); printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail()    { ERRORS=$((ERRORS + 1)); printf '%s  ✗%s %s\n' "$C_RED" "$C_RESET" "$*"; }
info()    { printf '    %s\n' "$*"; }

# ----------------------------- Репозиторий ----------------------------------

section "Репозиторий"

missing=()
for file in \
  setup.sh \
  Shell/verify.sh \
  Shell/install_packages.sh \
  Shell/ohmyzsh-setup.sh \
  Shell/services.sh \
  Shell/theme.sh \
  hypr/bindings.lua \
  hypr/input.lua \
  hypr/looknfeel.lua \
  ghostty/config \
  theme/fjord-frost/colors.toml; do
  [[ -f "$ROOT/$file" ]] || missing+=("$file")
done

if (( ${#missing[@]} == 0 )); then
  pass "все ожидаемые файлы репозитория на месте"
else
  fail "отсутствуют файлы: ${missing[*]}"
fi

for file in setup.sh Shell/install_packages.sh Shell/ohmyzsh-setup.sh Shell/services.sh Shell/theme.sh Shell/verify.sh; do
  if [[ -x "$ROOT/$file" ]]; then
    pass "$file исполняемый"
  else
    warn "$file не исполняемый (chmod +x)"
  fi
done

# -------------------------------- Система -----------------------------------

section "Система"

if (( EUID != 0 )); then
  pass "скрипт запущен обычным пользователем"
else
  warn "скрипт запущен от root"
fi

if command -v omarchy >/dev/null 2>&1; then
  pass "omarchy: $(omarchy version 2>/dev/null | head -n1)"
else
  fail "команда omarchy не найдена"
fi

if command -v pacman >/dev/null 2>&1; then
  pass "pacman доступен"
else
  fail "pacman не найден — это не Arch/Omarchy"
fi

if command -v git >/dev/null 2>&1; then
  pass "git доступен"
else
  warn "git не установлен"
fi

# --------------------------- Пользовательские конфиги -----------------------

section "Пользовательские конфиги"

missing=()
for file in \
  "$CONFIG_DIR/hypr/bindings.lua" \
  "$CONFIG_DIR/hypr/input.lua" \
  "$CONFIG_DIR/hypr/looknfeel.lua" \
  "$CONFIG_DIR/ghostty/config"; do
  [[ -f "$file" ]] || missing+=("${file#"$HOME"/}")
done

if (( ${#missing[@]} == 0 )); then
  pass "конфиги Hyprland и Ghostty на месте"
else
  fail "не найдены конфиги: ${missing[*]}"
fi

# ---------------------------------- Тема ------------------------------------

section "Тема"

if [[ -f "$CONFIG_DIR/omarchy/themes/fjord-frost/colors.toml" ]]; then
  pass "исходники темы Fjord Frost установлены"
else
  fail "нет ~/.config/omarchy/themes/fjord-frost/colors.toml"
fi

current_theme=""
if [[ -f "$CURRENT_NAME_FILE" ]]; then
  current_theme="$(<"$CURRENT_NAME_FILE")"
fi

if [[ "$current_theme" == "$EXPECTED_THEME" ]]; then
  pass "текущая тема: Fjord Frost ($EXPECTED_THEME)"
else
  warn "текущая тема: ${current_theme:-не определена}, ожидалась $EXPECTED_THEME"
fi

if [[ -d "$CURRENT_THEME_DIR" ]]; then
  missing=()
  for file in colors.toml ghostty.conf alacritty.toml foot.ini kitty.conf \
              btop.theme hyprland.lua shell.toml; do
    [[ -f "$CURRENT_THEME_DIR/$file" ]] || missing+=("$file")
  done

  if (( ${#missing[@]} == 0 )); then
    pass "сгенерированные конфиги темы на месте"
  else
    fail "тема не разложила конфиги: ${missing[*]}"
  fi
else
  fail "нет каталога текущей темы: $CURRENT_THEME_DIR"
fi

# --------------------------------- Hyprland ---------------------------------

section "Hyprland"

if ! command -v hyprctl >/dev/null 2>&1; then
  warn "hyprctl не найден — проверка Hyprland пропущена"
elif [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  warn "Hyprland не запущен — проверка configerrors пропущена"
else
  hypr_errors="$(hyprctl configerrors 2>&1)" || true
  if [[ -n "${hypr_errors//[[:space:]]/}" ]]; then
    fail "hyprctl configerrors: $hypr_errors"
  else
    pass "hyprctl configerrors — ошибок нет"
  fi
fi

# --------------------------------- Ghostty ----------------------------------

section "Ghostty"

if command -v ghostty >/dev/null 2>&1; then
  if ghostty +validate-config >/dev/null 2>&1; then
    pass "ghostty +validate-config — конфиг валиден"
  else
    fail "ghostty +validate-config вернул ошибку"
  fi
else
  warn "ghostty не установлен — проверка конфига пропущена"
fi

# ----------------------------------- Zsh ------------------------------------

section "Zsh"

if command -v zsh >/dev/null 2>&1; then
  pass "zsh установлен"
else
  fail "zsh не установлен"
fi

if [[ -f "$HOME/.zshrc" ]]; then
  if zsh -n "$HOME/.zshrc" >/dev/null 2>&1; then
    pass "$HOME/.zshrc синтаксически корректен"
  else
    fail "в ~/.zshrc есть синтаксическая ошибка"
  fi
else
  warn "$HOME/.zshrc не найден"
fi

current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
if [[ "$current_shell" == *zsh ]]; then
  pass "shell по умолчанию: $current_shell"
else
  warn "shell по умолчанию: ${current_shell:-неизвестен} (ожидался zsh)"
fi

# ---------------------------------- Шрифты ----------------------------------

section "Шрифты"

if command -v fc-list >/dev/null 2>&1; then
  # Без grep -q: иначе grep завершается раньше fc-list, pipefail ловит SIGPIPE.
  if fc-list 2>/dev/null | grep -i 'JetBrainsMono Nerd Font' >/dev/null 2>&1; then
    pass "JetBrainsMono Nerd Font найден"
  else
    warn "JetBrainsMono Nerd Font не найден"
  fi
else
  warn "fc-list не найден — проверка шрифтов пропущена"
fi

# ---------------------------------- Пакеты ----------------------------------

section "Пакеты"

for pkg in ghostty zsh git omarchy; do
  if pacman -Q "$pkg" >/dev/null 2>&1; then
    pass "пакет установлен: $pkg"
  else
    warn "пакет не установлен: $pkg"
  fi
done

if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
  pass "AUR-хелпер доступен"
else
  warn "yay/paru не найдены — AUR-пакеты установить не получится"
fi

if command -v shellcheck >/dev/null 2>&1; then
  pass "shellcheck доступен"
else
  warn "shellcheck не установлен — make check не сможет проверить скрипты"
fi

if grep -q '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then
  pass "репозиторий multilib включён"
else
  warn "репозиторий multilib не включён (нужен для Steam/Wine)"
fi

# --------------------------------- Сервисы ----------------------------------

section "Сервисы"

for service in docker bluetooth fstrim.timer; do
  if systemctl is-active --quiet "$service" 2>/dev/null; then
    pass "служба $service активна"
  else
    warn "служба $service не активна"
  fi
done

if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -x docker >/dev/null 2>&1; then
  pass "пользователь входит в группу docker"
else
  warn "пользователь не входит в группу docker"
fi

# ------------------------------ Состояние setup -----------------------------

section "Состояние установки"

if [[ -d "$STATE_DIR" ]]; then
  pass "каталог состояния: $STATE_DIR"
  stamps=$(find "$STATE_DIR/applied" "$STATE_DIR/scripts" "$STATE_DIR/themes" \
    -type f 2>/dev/null | wc -l)
  info "сохранённых отметок: $stamps"

  if [[ -d "$STATE_DIR/backups" ]]; then
    latest_backup="$(find "$STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      | sort | tail -n1)"
    [[ -n "$latest_backup" ]] && info "последний бэкап: $latest_backup"
  fi
else
  warn "каталог состояния не найден — setup.sh ещё не запускался"
fi

# --------------------------------- Итог -------------------------------------

printf '\n'
if (( ERRORS > 0 )); then
  printf '%sПроверка не пройдена:%s ошибок — %d, предупреждений — %d, успешно — %d\n' \
    "$C_RED" "$C_RESET" "$ERRORS" "$WARN" "$PASS"
  exit 1
fi

printf '%sПроверка пройдена:%s ошибок — 0, предупреждений — %d, успешно — %d\n' \
  "$C_GREEN" "$C_RESET" "$WARN" "$PASS"
exit 0
