-- Loaded only by the opted-in desktop. The timeout belongs to Hyprland so a
-- shell crash or an invisible confirmation window cannot strand a trial.
local M = {}

function M.start(token, fingerprint, code)
  assert(not _G.nullshellDisplayTrial, "A display trial is already pending")
  local trial = { token = token, fingerprint = fingerprint }
  hl.timer(function()
    if _G.nullshellDisplayTrial ~= trial then return end
    _G.nullshellDisplayTrial = nil
    hl.exec_cmd("hyprctl reload")
  end, { timeout = 15000, type = "oneshot" })
  _G.nullshellDisplayTrial = trial
  code()
end

function M.confirm(token)
  assert(_G.nullshellDisplayTrial and _G.nullshellDisplayTrial.token == token,
    "Display trial expired or was reset")
  -- The one-shot callback becomes a no-op after confirmation.
  _G.nullshellDisplayActive = _G.nullshellDisplayTrial.fingerprint
  _G.nullshellDisplayTrial = nil
end

function M.is_active(fingerprint)
  assert(not _G.nullshellDisplayTrial and _G.nullshellDisplayActive == fingerprint,
    "The requested display profile is not yet active")
end

return M
