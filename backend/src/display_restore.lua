-- Generated Hyprland loader. Layout records are written only after confirmation.
-- No Quickshell process, IPC client or profile JSON is needed for restoration.
local store = assert(_G.nullshellDisplayStore)

local function topology_key(monitors)
  table.sort(monitors, function(a, b) return a.name < b.name end)
  local hash = 5381
  for _, monitor in ipairs(monitors) do
    for _, field in ipairs({ monitor.name, monitor.description, monitor.serial }) do
      for i = 1, #field do hash = (hash * 33 + field:byte(i)) % 4294967296 end
      hash = (hash * 33) % 4294967296
    end
  end
  return string.format("%08x", hash)
end

local function same_outputs(saved, monitors)
  if #monitors ~= saved.count or type(saved.outputs) ~= "table"
    or type(saved.fingerprint) ~= "string" or type(saved.apply) ~= "function" then return false end
  for _, monitor in ipairs(monitors) do
    local output = saved.outputs[monitor.name]
    if type(output) ~= "table" or monitor.description ~= output.description or monitor.serial ~= output.serial then
      return false
    end
    if type(output.mode) == "table" then
      local modes, available = monitor.available_modes, false
      if modes and #modes > 0 then
        for _, mode in ipairs(modes) do
          if mode.width == output.mode[1] and mode.height == output.mode[2]
            and math.abs(mode.refresh_rate - output.mode[3]) <= 0.15 then
            available = true
            break
          end
        end
      end
      if not available then return false end
    end
  end
  return true
end

local generation = 0
local function reconcile()
  if _G.nullshellDisplayTrial then return end
  local monitors = hl.get_monitors({ all = true })
  if #monitors == 0 then return end
  local file = loadfile(store .. ".v1-" .. topology_key(monitors) .. ".lua")
  local ok, saved = false, nil
  if file then ok, saved = pcall(file) end
  if not ok or type(saved) ~= "table" or saved.version ~= 1 or not same_outputs(saved, monitors) then saved = nil end
  if saved and _G.nullshellDisplayActive == saved.fingerprint then return end
  if _G.nullshellDisplayActive then
    -- Clear old workspace and output overrides before applying a different
    -- confirmed plan or falling back to the native configuration.
    _G.nullshellDisplayActive = nil
    hl.exec_cmd("hyprctl reload")
  elseif saved then
    saved.apply()
    _G.nullshellDisplayActive = saved.fingerprint
  end
end

local function schedule()
  generation = generation + 1
  local queued = generation
  hl.timer(function()
    if queued == generation then reconcile() end
  end, { timeout = 250, type = "oneshot" })
end

-- Existing outputs can already be queried during a config reload. At initial
-- startup they may not be present yet, so also reconcile from compositor events.
reconcile()
hl.on("hyprland.start", schedule)
hl.on("monitor.added", schedule)
hl.on("monitor.removed", schedule)
