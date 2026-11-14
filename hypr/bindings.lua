-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- My Binds
local app_map = {
  ["1"] = { name = "Firefox", cmd = "firefox" },
  ["2"] = { name = "Steam", cmd = "steam" },
  ["3"] = { name = "VSCode", cmd = "code" },
  ["4"] = { name = "OpenCode", cmd = "omarchy-launch-tui opencode" },
  ["5"] = { name = "Telegram", cmd = "Telegram" }
}

for key, app in pairs(app_map) do 
  o.bind("ALT + " .. key, app.name, app.cmd)
end

local site_map = {
  ["1"] = { name = "GitHub", url = "https://github.com" },
  ["2"] = { name = "Yandexmail", url = "https://mail.yandex.ru" }
}

for key, site in pairs(site_map) do
  o.bind("CONTROL + " .. key, site.name, { webapp = site.url })
end

hl.unbind("SUPER + SPACE")
  o.bind("SUPER + SPACE", "Terminal", { omarchy = "terminal" })
o.bind("SUPER + CONTROL + M", "Omarchy menu", "omarchy-menu toggle root")
  
hl.unbind("SUPER + W")
  o.bind("SUPER + Q", "Close window", hl.dsp.window.close())
hl.unbind("SUPER + SHIFT + F")
  o.bind("SUPER + E", "File manager", { omarchy = "nautilus" })
-- 

-- Dictation keys from before Alt + Space and Right Alt became the defaults.
-- Remove these lines to give the keys back to applications.
if o.dictation_installed and o.dictation_installed() then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")
  o.bind_hold("F9", "Start dictation (push-to-talk)", "omarchy-dictation start", "Stop dictation (push-to-talk)", "omarchy-dictation stop")
end
