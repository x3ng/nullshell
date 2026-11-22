-- Exercise the compositor-owned watchdog without touching a running desktop.
local timers = {}
local reloads = 0
hl = {
  timer = function(callback, options)
    assert(options.type == "oneshot" and options.timeout == 15000)
    local timer = { fire = callback }
    timers[#timers + 1] = timer
    return timer
  end,
  exec_cmd = function(command)
    assert(command == "hyprctl reload")
    reloads = reloads + 1
  end,
}

local trial = dofile(arg[1])
local path = os.tmpname()
os.remove(path)
local record = path .. ".v1-deadbeef.lua"
assert(not pcall(trial.start, "1-1", "layout-a", "deadbeef", "loader", "saved", function() end))
_G.nullshellDisplayStore = path
local applied = false
trial.start("1-1", "layout-a", "deadbeef", "loader", "saved", function() applied = true end)
assert(applied and #timers == 1)
assert(not io.open(path) and not io.open(record), "Trial must not write files")
assert(not pcall(trial.start, "2-1", "layout-b", "deadbeef", "loader", "changed", function() error("not reached") end))
assert(not pcall(trial.confirm, "wrong"))
trial.confirm("1-1")
assert(pcall(trial.is_active, "layout-a") and not pcall(trial.is_active, "layout-b"))
local function contents(file)
  local f = assert(io.open(file, "rb"))
  local result = f:read("*a")
  f:close()
  return result
end
assert(contents(path) == "loader" and contents(record) == "saved")
timers[1].fire()
assert(reloads == 1)

assert(not pcall(trial.start, "2-1", "layout-b", "deadbeef", "loader", "changed", function() error("invalid layout") end))
timers[2].fire()
assert(reloads == 2 and not pcall(trial.confirm, "2-1") and contents(record) == "saved")

trial.start("3-1", "layout-c", "deadbeef", "loader", "changed", function() end)
timers[3].fire()
assert(reloads == 3 and contents(record) == "saved")

_G.nullshellDisplayStore = path .. "/bad-path"
trial.start("4-1", "layout-d", "deadbeef", "loader", "changed", function() end)
assert(not pcall(trial.confirm, "4-1") and contents(record) == "saved")
timers[4].fire()
assert(reloads == 4)
os.remove(record)
os.remove(path)
print("Display trial: only confirmation writes, failure and timeout preserve the previous layout")
