-- Wheel_Bridge | v0.3.0
-- v0.3.0: TRT.Wheel.Native(name) - a mission script asks the F10 Wheel overlay to make a NATIVE DCS radio call
--         (the overlay types the radio-menu keys, mapped by name in its config.json "native"). The requests go out
--         through the same store as the tree: WHEEL_NATIVE_JSON in the GUI / mission env, last 8 kept; the hook
--         polls it. Works for any F10 press path (wheel, mouse, VoiceAttack) and for automatic triggers.
-- v0.2.0: "store" uplink. First flight 2026-11-06: push returned 'nohook' - code sent to the GUI env runs and
--         returns a value, but each hook file has its own environment, so the hook's function is not visible
--         there. The bridge now stores the tree as a global WHEEL_TREE_JSON in the GUI env (and the mission
--         env); the hook reads it back with net.dostring_in(state, "return WHEEL_TREE_JSON"). Both operations
--         were observed working in that flight (code ran in "gui", its string return value came back).
--[[
  Mission-side bridge for the F10 Wheel overlay — TRT Syria Dynamic Template.

  Mirrors Menu_Manager's CURRENT F10 > Other tree to the overlay, and presses
  items the overlay sends back. Reads only Menu_Manager's public state
  (TRT.Menu.cur / roots / Phase / Refresh); Menu_Manager itself is unchanged.

  Load order: after Menu_Manager.lua and its providers (anywhere after
  Menu_Manager works; the tree is read on a timer).

  Press semantics are Menu_Manager's own: the item is looked up by its label
  path in the CURRENT item list, so a press can never hit a stale closure.
  If Menu_Manager gains TRT.Menu.PressPath(section, path) (proposed v1.2.0),
  the bridge calls that instead, so F10, the wheel and VoiceAttack share one
  press path and one log line.

  Uplink (mission -> overlay). Which one works depends on the DCS build, so the
  bridge and the hook try all three and log which one delivered [V = verify
  in dcs.log after the first flight]:
    push    net.dostring_in("gui", ...) from this environment calls
            WheelHook_OnTree() in the hook  [V: availability of "gui" from the
            mission scripting env is not documented]
    pull    the hook runs a_do_script("return TRT.Wheel.Export()") and reads the
            return value  [V: return pass-through broken since 2.9.15.9408,
            briefly back in 2.9.18.12722 — forum reports]
    socket  direct UDP to the overlay, only if MissionScripting.lua is
            desanitized (require available); off in a stock install

  API
    TRT.Wheel.Export()           -> JSON string of the current tree ('' if none)
    TRT.Wheel.Press(section, {label, ...})
    TRT.Wheel.PushNow()          re-send the current tree (hook asks on SYNC)
]]

_G.TRT = _G.TRT or {}
if TRT.Wheel then
    env.info("Wheel_Bridge | already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION     = "0.3.0",
    TICK        = 0.5,                                        -- s, tree change check
    SECTIONS    = { "COMMS", "INFO", "CARRIER", "TRAINING" }, -- Menu_Manager root order
    MAX_BYTES   = 60000,                                      -- one UDP datagram
    SOCKET_HOST = "127.0.0.1",
    SOCKET_PORT = 47811,                                      -- overlay listen port
}

local W = {
    rev    = 0,
    sig    = nil,      -- body of the last exported tree (without rev)
    json   = nil,      -- last full tree message
    status = {},       -- uplink name -> last result (logged on change)
    udp    = nil,
    nativeSeq = 0,
    nativeQ   = {},    -- last requests {id, n}
}
TRT.Wheel = W

local function Log(s) env.info("Wheel_Bridge | " .. s) end

-- ══════════════════════════════════════════════════════════════
--  JSON (encoder only; labels are UTF-8, passed through as is)
-- ══════════════════════════════════════════════════════════════
local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function JStr(s)
    s = tostring(s):gsub('[%c"\\]', function(c)
        return ESC[c] or string.format("\\u%04x", c:byte())
    end)
    return '"' .. s .. '"'
end

local function EncItems(items)
    local out = {}
    for i, it in ipairs(items or {}) do
        if it.sub then
            out[i] = '{"l":' .. JStr(it[1]) .. ',"s":' .. EncItems(it.sub) .. '}'
        else
            out[i] = '{"l":' .. JStr(it[1]) .. '}'
        end
    end
    return "[" .. table.concat(out, ",") .. "]"
end

local function Body()
    local M = TRT.Menu
    if not (M and M.cur and M.roots) then return nil end
    local secs = {}
    for _, s in ipairs(CFG.SECTIONS) do
        if M.roots[s] and M.cur[s] then
            secs[#secs + 1] = '{"name":' .. JStr(s) .. ',"items":' .. EncItems(M.cur[s]) .. '}'
        end
    end
    local ok, ph = pcall(function() return M.Phase and M.Phase() end)
    return '"phase":' .. JStr((ok and ph) or "NONE") .. ',"sections":[' .. table.concat(secs, ",") .. ']'
end

-- ══════════════════════════════════════════════════════════════
--  UPLINKS
-- ══════════════════════════════════════════════════════════════
local function Note(name, result)
    if W.status[name] ~= result then
        W.status[name] = result
        Log("uplink " .. name .. ": " .. result)
    end
end

local function PushGui(json)
    if not (net and net.dostring_in) then Note("push", "no net.dostring_in here"); return false end
    local code = "if WheelHook_OnTree then WheelHook_OnTree(" .. string.format("%q", json) ..
                 ") return 'ok' end return 'nohook'"
    local okCall, res, ok = pcall(net.dostring_in, "gui", code)
    if not okCall or ok == false then Note("push", "error: " .. tostring(res)); return false end
    Note("push", tostring(res))
    return res == "ok"
end

local function PushSocket(json)
    if not W.udp then return false end
    local ok, err = pcall(function() W.udp:send(json) end)
    Note("socket", ok and "ok" or ("error: " .. tostring(err)))
    return ok
end

-- Store the tree as a global in another environment; the hook polls it there.
local function Store(state, json)
    if not (net and net.dostring_in) then Note("store-" .. state, "no net.dostring_in here"); return false end
    local code = "WHEEL_TREE_JSON = " .. string.format("%q", json) .. " return 'ok'"
    local okCall, res, ok = pcall(net.dostring_in, state, code)
    if not okCall or ok == false then Note("store-" .. state, "error: " .. tostring(res)); return false end
    Note("store-" .. state, tostring(res))
    return res == "ok"
end

local function Push()
    if not W.json then return end
    local a = Store("gui", W.json)
    local b = Store("mission", W.json)
    local c = PushGui(W.json)
    if not (a or b or c) then PushSocket(W.json) end
end

do  -- direct socket only when the environment is desanitized (require present)
    local ok, socket = pcall(function() return require and require("socket") end)
    if ok and socket then
        W.udp = socket.udp()
        W.udp:setpeername(CFG.SOCKET_HOST, CFG.SOCKET_PORT)
        Note("socket", "available (desanitized environment)")
    else
        Note("socket", "unavailable (sanitized environment, expected)")
    end
end

-- ══════════════════════════════════════════════════════════════
--  TREE
-- ══════════════════════════════════════════════════════════════
-- noPush: build only. Used when the call comes from the hook (pull / press /
-- PushNow): pushing from inside a net.dostring_in call that the GUI env made
-- would re-enter the GUI Lua state, so those paths defer the push to a timer.
function W.Tick(noPush)
    local body = Body()
    if not body or body == W.sig then return end
    W.sig = body
    W.rev = W.rev + 1
    local json = '{"t":"tree","rev":' .. W.rev .. ',' .. body .. '}'
    if #json > CFG.MAX_BYTES then
        Log(string.format("tree rev %d is %d bytes (> %d), not sent", W.rev, #json, CFG.MAX_BYTES))
        return
    end
    W.json = json
    if not noPush then Push() end
end

local function Later(fn)
    timer.scheduleFunction(function() local ok, e = pcall(fn); if not ok then Log("deferred: " .. tostring(e)) end end,
        nil, timer.getTime() + 0.05)
end

function W.Export()
    W.Tick(true)
    return W.json or ""
end

function W.PushNow()
    Later(function() W.Tick(true); Push() end)
end

-- ══════════════════════════════════════════════════════════════
--  PRESS
-- ══════════════════════════════════════════════════════════════
local function Find(items, path, depth)
    for _, it in ipairs(items or {}) do
        if it[1] == path[depth] then
            if depth == #path then return it end
            return Find(it.sub, path, depth + 1)
        end
    end
    return nil
end

function W.Press(section, path)
    local M = TRT.Menu
    local txt = tostring(section) .. " > " .. table.concat(path or {}, " > ")
    if not M then Log("press ignored (no Menu_Manager): " .. txt); return end
    if M.PressPath then
        M.PressPath(section, path)
    else
        Log("press(wheel): " .. txt)
        local it = Find(M.cur and M.cur[section], path or {}, 1)
        if it and it[2] then
            local ok, err = pcall(it[2])
            if not ok then Log("item '" .. txt .. "': " .. tostring(err)) end
        else
            Log("stale press ignored: " .. txt)
        end
        M.Refresh()
    end
    Later(W.Tick)
end

-- ══════════════════════════════════════════════════════════════
--  NATIVE DCS RADIO CALL REQUESTS (v0.3.0)
-- ══════════════════════════════════════════════════════════════
local function StoreNative()
    local parts = {}
    for i, r in ipairs(W.nativeQ) do parts[i] = '{"id":' .. r.id .. ',"n":' .. JStr(r.n) .. '}' end
    local json = "[" .. table.concat(parts, ",") .. "]"
    for _, state in ipairs({ "gui", "mission" }) do
        if net and net.dostring_in then
            local okCall, res, ok = pcall(net.dostring_in, state,
                "WHEEL_NATIVE_JSON = " .. string.format("%q", json) .. " return 'ok'")
            if not okCall or ok == false then Note("native-" .. state, "error: " .. tostring(res)) end
        end
    end
end

--- Ask the overlay for a native DCS radio call (name = key of the overlay's config.json "native" map).
--- Returns the request id. Without the overlay running nothing happens (the log line says so).
function W.Native(name)
    W.nativeSeq = W.nativeSeq + 1
    W.nativeQ[#W.nativeQ + 1] = { id = W.nativeSeq, n = tostring(name) }
    while #W.nativeQ > 8 do table.remove(W.nativeQ, 1) end
    Log(string.format("native request #%d %s (made by the F10 Wheel overlay if it runs)", W.nativeSeq, tostring(name)))
    Later(StoreNative)                 -- deferred: may be called inside a hook -> mission call (Press)
    return W.nativeSeq
end

-- ══════════════════════════════════════════════════════════════
--  RUN
-- ══════════════════════════════════════════════════════════════
timer.scheduleFunction(function(_, t)
    local ok, err = pcall(W.Tick)
    if not ok then Log("tick error: " .. tostring(err)) end
    return t + CFG.TICK
end, nil, timer.getTime() + 1)

Log("v" .. CFG.VERSION .. " loaded" .. (TRT.Menu and "" or " (Menu_Manager not loaded yet)"))
