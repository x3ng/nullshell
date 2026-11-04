-- Hyprland-only palette adapter. Quickshell saves the last observed Darkman mode.
-- Palette sync: the shell palette lives in qml/Theme.qml. Panel,
-- selection and text colours are mirrored here (202328/f4f4f2, 3a4545/dce6e1,
-- f0f1f3/24272d, e4bb80/805313). The window and groupbar borders are tuned for
-- visibility on top of that palette instead of copied verbatim: the dark
-- active border (649486) is darker than the dark shell accent (79ad9d), the
-- light one (67b99a) is lighter than the light accent (1c7057), and the light
-- inactive border uses 7c8390 where Theme's outline uses c1cbc5. Change both
-- files together.
local M = {}

function M.apply(mode)
  if not mode then
    local state = os.getenv("XDG_STATE_HOME")
    if not state or state == "" then state = os.getenv("HOME") .. "/.local/state" end
    local file = io.open(state .. "/nullshell/appearance-mode", "r")
    if file then
      mode = file:read("*a"):match("^%s*(.-)%s*$")
      file:close()
    end
    -- A missing, empty or damaged saved snapshot must still apply a complete palette.
    if mode ~= "dark" and mode ~= "light" then mode = "dark" end
  end
  if mode ~= "dark" and mode ~= "light" then return end

  local dark = mode == "dark"
  local active = dark and "rgba(649486ff)" or "rgba(67b99aff)"
  local inactive = dark and "rgba(4a535c80)" or "rgba(7c839080)"
  local locked = dark and "rgba(e4bb80ff)" or "rgba(805313ff)"
  hl.config({
    general = {
      ["col.active_border"] = active,
      ["col.inactive_border"] = inactive,
    },
    decoration = {
      shadow = { color = dark and "rgba(00000066)" or "rgba(24272d20)" },
    },
    group = {
      ["col.border_active"] = active,
      ["col.border_inactive"] = inactive,
      ["col.border_locked_active"] = locked,
      ["col.border_locked_inactive"] = dark and "rgba(69717eff)" or "rgba(7c839080)",
      groupbar = {
        text_color = dark and "rgba(f0f1f3ff)" or "rgba(24272dff)",
        ["col.active"] = dark and "rgba(3a4545ff)" or "rgba(dce6e1ff)",
        ["col.inactive"] = dark and "rgba(202328f5)" or "rgba(f4f4f2fa)",
        ["col.locked_active"] = dark and "rgba(51432dff)" or "rgba(f0e3cdff)",
        ["col.locked_inactive"] = dark and "rgba(292d33ff)" or "rgba(e7eae8ff)",
      },
    },
  })
end

local layouts = { dwindle = true, master = true, scrolling = true, monocle = true }
function M.is_layout(layout) return layouts[layout] == true end

function M.set_layout(workspace, layout)
  if not M.is_layout(layout) then return false, "Unknown workspace layout" end
  local name = workspace and workspace.addressable_name
  if type(name) ~= "string" or name == "" then return false, "Workspace no longer exists" end

  -- Workspace rules refresh persistent monitor placement too. Preserve manual
  -- moves until reload, when hyprmoncfg's configured assignments take precedence.
  for _, existing in ipairs(hl.get_workspaces()) do
    local monitor = existing.monitor
    if existing.is_persistent and monitor then
      hl.workspace_rule({ workspace = existing.addressable_name, monitor = monitor.name })
    end
  end
  hl.workspace_rule({ workspace = name, layout = layout })
  return true
end

return M
