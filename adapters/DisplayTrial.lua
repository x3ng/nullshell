-- Loaded only by the opted-in desktop. The timeout belongs to Hyprland so a
-- shell crash or an invisible confirmation window cannot strand a trial.
local M = {}

function M.start(token, fingerprint, key, loader, restore, code)
  assert(not _G.nullshellDisplayTrial, "A display trial is already pending")
  assert(type(_G.nullshellDisplayStore) == "string" and _G.nullshellDisplayStore ~= "",
    "Configure Hyprland's nullshell display include before applying a profile")
  assert(token:match("^%d+%-%d+$"), "Invalid display trial token")
  assert(key:match("^[0-9a-f]+$") and #key == 8, "Invalid display topology key")
  local trial = { token = token, fingerprint = fingerprint, key = key, loader = loader,
    restore = restore, path = _G.nullshellDisplayStore }
  hl.timer(function()
    if _G.nullshellDisplayTrial ~= trial then return end
    _G.nullshellDisplayTrial = nil
    hl.exec_cmd("hyprctl reload")
  end, { timeout = 15000, type = "oneshot" })
  _G.nullshellDisplayTrial = trial
  code()
end

local function publish(path, token, contents)
  local temp = path .. ".tmp-" .. token
  local file, err = io.open(temp, "wb")
  assert(file, err)
  local written, write_error = file:write(contents)
  local closed, close_error = file:close()
  if not written or not closed then
    os.remove(temp)
    error(write_error or close_error or "Could not write confirmed layout")
  end
  local renamed, rename_error = os.rename(temp, path)
  if not renamed then
    os.remove(temp)
    error(rename_error or "Could not publish confirmed layout")
  end
end

function M.confirm(token)
  local trial = _G.nullshellDisplayTrial
  assert(trial and trial.token == token, "Display trial expired or was reset")
  -- Install the loader first. If either atomic write fails, existing records
  -- are still readable and the watchdog can reload them.
  local loader = io.open(trial.path, "rb")
  if loader then loader:close() else publish(trial.path, token, trial.loader) end
  publish(trial.path .. ".v1-" .. trial.key .. ".lua", token, trial.restore)
  -- From this point the compositor can restore the new layout without the shell.
  _G.nullshellDisplayActive = trial.fingerprint
  _G.nullshellDisplayTrial = nil
  -- Also clear previous workspace rules. Trial changes apply only to outputs.
  hl.exec_cmd("hyprctl reload")
end

function M.is_active(fingerprint)
  assert(not _G.nullshellDisplayTrial and _G.nullshellDisplayActive == fingerprint,
    "The requested display profile is not yet active")
end

return M
