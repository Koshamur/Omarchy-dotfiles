# Omarchy-dotfiles
This repository contains a set of configs and scripts needed to automate the setup of Omarchy Linux.

Набор личных конфигов и скриптов для быстрого развёртывания окружения
на Omarchy (Arch Linux).

## Состав

| Путь | Назначение |
|---|---|
| `hypr/bindings.lua` | Горячие клавиши Hyprland: приложения, терминал, меню, окна |
| `hypr/input.lua` | Раскладка `us,ru`, переключение `Alt+Shift`, настройки ввода |
| `hypr/looknfeel.lua` | Внешний вид: отступы, рамки, скругления, затемнение окон |
| `ghostty/config` | Настройки терминала Ghostty: шрифт, цвета, прозрачность, клавиши |
| `install_packages.sh` | Установка пакетов из репозиториев Arch, AUR и Flatpak |
| `ohmyzsh-setup.sh` | Установка Zsh, Oh My Zsh, Powerlevel10k и плагинов |
| `setup.sh` | Копирует конфиги в `~/.config` и запускает остальные скрипты |

## Быстрый запуск

```bash
git clone https://github.com/Koshamur/Omarchy-dotfiles.git
cd Omarchy-dotfiles
./setup.sh
```

*Параметры:*
`./setup.sh --configs-only   # только скопировать hypr/ и ghostty/ в ~/.config`
`./setup.sh --scripts-only   # только выполнить установочные скрипты`
`./setup.sh --force          # повторить копирование и выполнение`
`./setup.sh --help           # справка`

*При первом запуске setup.sh:*
1. создаёт резервную копию текущих конфигов;
2. копирует hypr/ и ghostty/ в ~/.config;
3. по очереди запускает install_packages.sh и ohmyzsh-setup.sh.
Повторные запуски пропускают уже выполненную работу, пока исходные файлы
не изменились. Отметки хранятся в ~/.local/state/system-setup/.

*Примечание*
hypr/*.lua рассчитаны на Omarchy. На чистом Arch без Omarchy
bindings.lua не заработает, а input.lua и looknfeel.lua потребуют
подключения в собственном Lua-конфиге Hyprland
`
