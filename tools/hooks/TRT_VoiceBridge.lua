-- TRT_VoiceBridge | v1.0.0
--[[
  DCS GUI hook (install: Saved Games\DCS\Scripts\Hooks\TRT_VoiceBridge.lua). Not part of the .miz.

  VoiceAttack (profile Pathe_01, command "((TRT voice send))") sends one UDP datagram per voice call to
  127.0.0.1:47011:
      TRTV1 <TAB> section <TAB> key <TAB> spoken phrase
  This hook reads the datagrams every frame and runs, in the mission scripting environment,
      TRT.Menu.Voice(section, key, said)          (Menu_Manager >= v1.2.0)
  via net.dostring_in("mission", "a_do_script(...)"). A mission without TRT.Menu.Voice ignores the call.

  Single player / host only. Log lines: "TRT_VoiceBridge" in dcs.log.
]]

local VB = {
    VERSION = "1.0.0",
    HOST    = "127.0.0.1",
    PORT    = 47011,
    MAX_PER_FRAME = 4,
    MAX_LEN = 400,
}

local function L(s) log.write("TRT_VoiceBridge", log.INFO, s) end

local okSock, socket = pcall(function()
    package.path  = package.path  .. ";.\\LuaSocket\\?.lua"
    package.cpath = package.cpath .. ";.\\LuaSocket\\?.dll"
    return require("socket")
end)
if not okSock or not socket then
    L("v" .. VB.VERSION .. " LuaSocket not available: " .. tostring(socket))
    return
end

local udp = socket.udp()
local okBind, errBind = udp:setsockname(VB.HOST, VB.PORT)
if not okBind then
    L(string.format("v%s cannot bind %s:%d (%s) - voice bridge off", VB.VERSION, VB.HOST, VB.PORT, tostring(errBind)))
    pcall(function() udp:close() end)
    return
end
udp:settimeout(0)

local function Clean(s)
    s = tostring(s or ""):gsub("[%c]", " ")
    return s
end

local function Handle(msg)
    if #msg > VB.MAX_LEN then L("dropped: datagram too long"); return end
    local tag, sec, key, said = msg:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?([^\t]*)$")
    if tag ~= "TRTV1" then L("dropped: bad datagram"); return end
    sec, key, said = Clean(sec), Clean(key), Clean(said)
    if key == "" then return end
    local code = string.format(
        "if TRT and TRT.Menu and TRT.Menu.Voice then TRT.Menu.Voice(%q, %q, %q) " ..
        "else env.info('TRT_VoiceBridge | mission has no TRT.Menu.Voice (Menu_Manager < v1.2.0)') end",
        sec, key, said)
    local res, ok = net.dostring_in("mission", string.format("a_do_script(%q)", code))
    L(string.format("'%s' -> %s | %s%s", said, sec, key, (ok == false) and (" FAILED: " .. tostring(res)) or ""))
end

local cb = {}
function cb.onSimulationFrame()
    if DCS.isMultiplayer() and not DCS.isServer() then
        -- client in someone else's server: drain, do nothing
        for _ = 1, VB.MAX_PER_FRAME do if not udp:receive() then break end end
        return
    end
    for _ = 1, VB.MAX_PER_FRAME do
        local msg = udp:receive()
        if not msg then break end
        local ok, err = pcall(Handle, msg)
        if not ok then L("error: " .. tostring(err)) end
    end
end

function cb.onSimulationStop()
    while udp:receive() do end   -- calls spoken outside a mission are dropped
end

DCS.setUserCallbacks(cb)
L(string.format("v%s loaded, listening %s:%d", VB.VERSION, VB.HOST, VB.PORT))
