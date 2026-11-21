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
local applied = false
trial.start("first", "layout-a", function() applied = true end)
assert(applied and #timers == 1)
assert(not pcall(trial.start, "duplicate", "layout-b", function() error("not reached") end))
assert(not pcall(trial.confirm, "wrong"))
trial.confirm("first")
assert(pcall(trial.is_active, "layout-a") and not pcall(trial.is_active, "layout-b"))
timers[1].fire()
assert(reloads == 0)

assert(not pcall(trial.start, "failed", "layout-b", function() error("invalid layout") end))
timers[2].fire()
assert(reloads == 1 and not pcall(trial.confirm, "failed"))

trial.start("shell-disconnected", "layout-c", function() end)
timers[3].fire()
assert(reloads == 2)
print("Display trial: confirmation, conflicting trials, failed apply and shell disconnect passed")
