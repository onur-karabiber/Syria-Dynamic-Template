-- test_voice | v1.0.0
-- Headless check: every key in voice_keys_test.json (make_vap.py) presses the expected F10 item when ALL
-- known labels are offered at once (stricter than any real phase), through the real hook -> a_do_script ->
-- Menu_Manager path. Run from the repo root:  lua5.4 tools/voiceattack/test_voice.lua
local ROOT = "./"

-- ── DCS stubs ──────────────────────────────────────────────────────────────
local now, sched, msgs, logs = 0, {}, {}, {}
env = { info = function(s) logs[#logs + 1] = s end }
timer = { getTime = function() return now end,
          scheduleFunction = function(f, a, t) sched[#sched + 1] = { f = f, a = a, t = t } end }
trigger = { action = { outTextForGroup = function(_, t) msgs[#msgs + 1] = t end, outText = function(t) msgs[#msgs + 1] = t end },
            misc = { getUserFlag = function() return 0 end } }
local hid = 0
missionCommands = {
    addSubMenuForGroup = function() hid = hid + 1; return { hid } end,
    addCommandForGroup = function() hid = hid + 1; return { hid } end,
    removeItemForGroup = function() end }
world = { event = { S_EVENT_BIRTH = 15, S_EVENT_TAKEOFF = 3, S_EVENT_LAND = 4 }, addEventHandler = function() end }
local hero = { isExist = function() return true end, inAir = function() return true end,
               getGroup = function() return { getID = function() return 7 end } end }
Unit = { getByName = function(n) return n == "Player_01" and hero or nil end }

dofile(ROOT .. "scripts/Menu_Manager.lua")

-- ── every label the providers can show (abridged to one instance per label shape) ──
local pressed
local function L(label) return { label, function() pressed = label end } end
local function S(label, subs)
    local t = {}
    for _, s in ipairs(subs) do t[#t + 1] = { s, function() pressed = label .. " > " .. s end } end
    return { label, sub = t }
end
local COMMS = {
    L("MARSHAL: check in 264.00 (#16)"), L("MARSHAL: readback"), L("MARSHAL: established"),
    L("MARSHAL: commencing (EAT :25, T-1:30)"), L("MARSHAL: see you at 10"),
    L("APPROACH: check in 271.00 (#15)"), L("APPROACH: platform"), L("APPROACH: see you at 10"),
    L("APPROACH: needles up and on"), L("APPROACH: needles negative"),
    L("DEPARTURE: tanking complete (state) 251.00 (#2)"), L("PADDLES: ball (Hornet ball, state)"), L("PADDLES: Clara"),
    L("DEPARTURE: Popeye, angels 5"), L("DEPARTURE: on top, angels 7"),
    L("ANKARA: check in (357.5)"), L("TOWER: check in (360.1)"), L("GROUND: request taxi (250.0)"),
    L("POINTER 11: check in (btn 4)"), L("POINTER 11: how copy? (no answer)"), L("POINTER 11: ready for game plan"),
    L("POINTER 11: ready for 9-line"), L("POINTER 11: ready for remarks"),
    S("POINTER 11: READBACK 1/3: Line 4", { "2,340 feet", "2,430 feet", "713 meters", "2,350 feet" }),
    L("POINTER 11: ABORTING"), L("POINTER 11: AUTHENTICATE"), L("POINTER 11: OFF"),
    L("POINTER 11: IP INBOUND"), L("POINTER 11: IN (direction auto)"), L("POINTER 11: TEN SECONDS"),
    L("POINTER 11: LASER ON"), L("POINTER 11: SHIFT (laser to next target)"), L("POINTER 11: SPOT"),
    L("POINTER 11: NEGATIVE LASER"), L("POINTER 11: CEASE LASER"),
    S("POINTER 11: correlation", { "TALLY", "CAPTURED", "NO JOY" }), L("POINTER 11: WINCHESTER (check out)"),
    L("STRIKE: check in (btn 6)"), L("OVERLORD: check in (btn 3)"),
    L("OVERLORD: off Pointer 11, ready for retasking"), L("OVERLORD: off Eyeball 11, ready for retasking"),
    L("OVERLORD: off Axeman 11, ready for retasking"), L("OVERLORD: off Darknight 11, ready for retasking"),
    L("OVERLORD: INFLTREP"),
    L("OVERLORD: unable contact Pointer 11"), L("OVERLORD: unable contact Eyeball 11"),
    L("OVERLORD: unable contact Axeman 11"), L("OVERLORD: unable contact Darknight 11"),
    L("OVERLORD: wilco divert (Eyeball 11)"), L("OVERLORD: unable divert, state 6.2"),
    L("OVERLORD: continuing mission, no tanker"), L("OVERLORD: RTB (mission abort)"), L("OVERLORD: RTB"),
    L("OVERLORD: RTB (no tanker)"),
    L("OVERLORD: request Texaco (AR1 top-off)"), L("OVERLORD: skip AR1 (no top-off)"), L("TEXACO: RV initial (btn 7)"),
    L("OVERLORD: Judy (tanker visual)"), L("TEXACO: state"), L("OVERLORD: off Texaco, proceeding TIGER"),
    L("TEXACO: execute overrun"), L("TEXACO: breakaway (emergency)"), L("TEXACO: spokes (drogue damaged)"),
    L("STRIKE: check in inbound (btn 6)"), L("POINTER 11: 9-line readback (4/6/8)"),
    L("OVERLORD: bingo / divert (nearest field)"), L("OVERLORD: feet dry"), L("OVERLORD: feet wet"),
    L("OVERLORD: request picture"),
}
local CARRIER = {
    S("Plane captain", { "Ready to start", "Ready for checks (engines running)", "Done (pilot signal)", "Skip step", "Abort checks" }),
    S("Results", { "Greenie board", "My LSO grades", "Last debrief" }),
    L("My status"), L("Attitude monitor"), L("Carrier info"), L("Weather report"), L("Spinning"), L("Emergency landing"),
}
local INFO = {
    L("Show: hard deck"), L("Show: divert summary"), L("FLIGHT REPORT: end sortie (show report)"),
    L("FLIGHT REPORT: score detail"), L("FLIGHT REPORT: text report"), L("Show: flight card"), L("Show: timeline"),
    L("Show: ELINT picture"),
}
TRT.Menu.Register("COMMS", "T", function() return COMMS end)
TRT.Menu.Register("CARRIER", "T", function() return CARRIER end)
TRT.Menu.Register("INFO", "T", function() return INFO end)
-- built-ins: Show: comm card / Show: next call -> wrap to record
TRT.Menu.RegisterNext("T", function() pressed = "Show: next call"; return "x" end)
TRT.Menu.RegisterCard("T", function() pressed = "Show: comm card"; return { buttons = {}, lines = {} } end)

-- ── hook path: load the real hook with socket / DCS stubs, feed datagrams ──
local queue = {}
package.preload["socket"] = function()
    return { udp = function() return {
        setsockname = function() return 1 end, settimeout = function() end, close = function() end,
        receive = function() return table.remove(queue, 1) end } end }
end
log = { INFO = 0, write = function(_, _, s) logs[#logs + 1] = "HOOK " .. s end }
local cbs
DCS = { setUserCallbacks = function(t) cbs = t end, isMultiplayer = function() return false end,
        isServer = function() return true end }
function a_do_script(code) local f = assert(load(code)); f() end
net = { dostring_in = function(envName, code)
    assert(envName == "mission"); local f = assert(load(code)); f(); return "", true end }
dofile(ROOT .. "tools/hooks/TRT_VoiceBridge.lua")
assert(cbs and cbs.onSimulationFrame, "hook did not register callbacks")

local function send(sec, key, said)
    pressed = nil
    queue[#queue + 1] = "TRTV1\t" .. sec .. "\t" .. key .. "\t" .. (said or key)
    cbs.onSimulationFrame()
    return pressed
end

-- ── run ──
local f = assert(io.open(ROOT .. "tools/voiceattack/voice_keys_test.json")); local js = f:read("a"); f:close()
local fails, n = 0, 0
local function check(sec, key, want, what)
    n = n + 1
    local got = send(sec, key, what)
    if got ~= want then fails = fails + 1; print(string.format("FAIL %-55s %s | %s -> %s", what, sec, key, tostring(got))) end
end
-- minimal JSON walk (the file is generated, flat objects)
for obj in js:match('"suffix": %[(.-)%],%s*"full"'):gmatch('{(.-"expect": %[.-%]%s*)}') do
    local phrase = obj:match('"phrase": "(.-)"'); local key = obj:match('"key": "(.-)"')
    for ag, lab in obj:match('"expect": %[(.*)%]'):gmatch('%[%s*"(.-)",%s*"(.-)"%s*%]') do
        check("COMMS", key:gsub("@ag", ag), lab, ag .. " + " .. phrase)
    end
end
for obj in js:match('"full": %[(.*)%]'):gmatch('{(.-)}') do
    local phrase = obj:match('"phrase": "(.-)"'); local sec = obj:match('"section": "(.-)"')
    local key = obj:match('"key": "(.-)"'); local exp = obj:match('"expect": "(.-)"')
    exp = exp:gsub(" > #(%d)", function(i)
        for _, it in ipairs(COMMS) do if it[1] == "POINTER 11: READBACK 1/3: Line 4" then return " > " .. it.sub[tonumber(i)][1] end end
    end)
    check(sec, key, exp, phrase)
end
-- negative cases: nothing pressed, "[VOICE] not available" after VOICE_WAIT
local before = #msgs
check("COMMS", "overlord: nonsense call", nil, "unknown call")
for _ = 1, 20 do now = now + 0.5; local s = sched; sched = {}
    for _, e in ipairs(s) do local r = e.f(e.a, now); if r then sched[#sched + 1] = { f = e.f, a = e.a, t = r } end end end
assert(msgs[#msgs] and msgs[#msgs]:find("not available"), "no 'not available' message")
-- submenu named without an item -> list
send("COMMS", "*: correlation", "correlation"); assert(msgs[#msgs]:find("1  TALLY"), "submenu not listed")
-- bad datagrams are dropped
queue[#queue + 1] = "garbage"; cbs.onSimulationFrame()
print(string.format("%d checks, %d failures", n, fails))
os.exit(fails == 0 and 0 or 1)
