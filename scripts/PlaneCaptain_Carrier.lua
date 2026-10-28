-- PlaneCaptain_Carrier | v1.3.2
--[[
  v1.3.2: phase-end cards S_END (engines running, held until Ready for checks) and C_END
          (stands by for the director, CFG.MSG_END s) when Score_Display has them; text otherwise.
  v1.3.1: a step closed by the aircraft itself (reason "condition", wait type arg / argDelta /
          argNear / range / span / engineIdle) calls TRT.ScoreDisplay.pcOk() -> short sound.
          Not for plane-captain timers, Done steps or skipped steps. No-op without Score_Display.
  v1.3.0: picture cards per step when Score_Display (CAS (L) only) offers them:
          TRT.ScoreDisplay.pcHas(id) / pcCard(id) / pcClear(). A step with a card clears the
          previous step text and shows the card instead of the step text; steps without a card,
          the phase-end messages, notes and aborts stay text. Every replacing text (clearview)
          first removes the card. Without Score_Display (template) behaviour is unchanged.
          RPM unreadable on an engine step with a card -> the "At idle: Done" line is added as
          text under the card.
  v1.2.2: PC.milestones = { START = t, CHECKS = t } (timer.getTime() when each phase first completes),
          read by Flight_Timeline v1.0.0 (M1 engines running, M2 checks done). No behaviour change.

  Plane captain ground checks on the carrier - text (picture cards only via Score_Display, v1.3.0),
  no units, no statics.
  Carrier version of the Animated Ground Crew flow, for group "CAS-1", unit "Player_01" (F/A-18C).

  Sources (v1.2.0): F/A-18 NATOPS pocket checklist A1-F18AC-NFM-500 (BEFORE TAXI), hand signals
  from NAVAIR 00-80T-113 Aircraft Signals NATOPS (Fig. 2-1, launch bar Fig. 4-1), deck flow from
  Speed & Angels "Aircraft Carrier Operating Procedures for DCS" v01.8.

  Two phases, each opened by the pilot from the F10 menu:
    Ready to start   -> OK; APU; engine 2; engine 1
    Ready for checks -> BEFORE TAXI order:
                        spread wings (item 4) -> Controls - CHECK: control stick - CYCLE (13a),
                        flaps - HALF (13b, plane captain signal), rudder pedals - CYCLE (13c)
                        -> probe, speed brake, launch bar, hook - CYCLE (15) -> fold wings for
                        taxi (spread again at the catapult on the director's signal)
                        -> your thumbs-up to the plane captain: ready, wait for the director.
    Stick and rudder are pilot checklist items (values read on the FCS page); 00-80T-113 has no
    per-direction signal for them, so they are shown as checklist items, not as signals, and
    close when every movement has been seen, in any order. Flaps stay HALF.
    FCS RESET / IBIT / trim are cockpit-only and are not part of this flow.

  How a step advances:
    * action steps: only when the aircraft does it (external-model draw arguments), or on
      "Skip step". No timeout.
    * engine steps: engine RPM >= idle (export environment). "Done" only if RPM cannot be read.
    * pilot-signal steps: "Done (pilot signal)".
    * plane-captain-only signals (OK, START APU): a short timer.
  Launch bar: F/A-18C external-model argument 85 (v1.2.1, found with the calibration mode in
  the 2026-10-26 test flight: 0 up, max 0.837 down). The two launch bar steps close on the
  argument. With CFG.LAUNCHBAR_ARG = nil they run in calibration mode again: they close on
  "Done (pilot signal)" and the script logs every argument that moved ("LBAR calibration").

  Messages: one message per step, held on screen until the step changes; the next step replaces
  it (clearview). No repeats. Short notes are added without clearview.

  Abort: F10 "Abort checks" while a phase is running or waiting; automatic abort when the
  aircraft moves more than MOVE_DIST on the deck (measured in the carrier's frame, so the
  carrier's own speed and turns do not count). After an abort the flow can be opened again.

  Menu: registers with TRT.Menu (Menu_Manager) under F10 > CARRIER > Plane captain while the
  aircraft is on deck; without Menu_Manager it builds its own group menu "Plane captain".
  Load after Menu_Manager.lua.
]]

_G.TRT = _G.TRT or {}
if TRT.PlaneCaptain then
  env.info("PlaneCaptain | already loaded, second copy ignored")
  return
end

local CFG = {
  VERSION       = "1.3.2",
  PLAYER_UNIT   = "Player_01",
  PLAYER_GROUP  = "CAS-1",
  CARRIER_UNIT  = "CVN",       -- movement is measured relative to this unit (deck is moving)
  MENU_SECTION  = "CARRIER",   -- Menu_Manager section
  MENU_ORDER    = 5,           -- before the AIRBOSS items
  POLL          = 0.25,        -- s
  STEP_GAP      = 1.5,         -- pause between steps (s)
  MSG_HOLD      = 600,         -- step message stays this long unless replaced (s)
  MSG_END       = 15,          -- final / abort message (s)
  MSG_NOTE      = 6,           -- short notes, added without clearview (s)
  LAUNCHBAR_ARG = 85,          -- F/A-18C external-model launch bar argument (calibrated 2026-10-26:
                               -- 0 up, ~0.84 down); nil = calibration mode
  SCAN_MAX      = 999,         -- calibration: arguments 0..SCAN_MAX are watched
  MOVE_DIST     = 3.0,         -- m moved on the deck (carrier frame) since the phase opened -> auto abort
  OPTIONAL = {
    extpower = false,          -- connect/disconnect external power
    apustop  = false,          -- STOP APU signal (the F/A-18C shuts the APU down by itself)
  },
}

----------------------------------------------------------------------
-- SIGNALS (NAVAIR 00-80T-113 Chart 1 wording, shortened)
-- Engine/APU finger counts follow the project convention: 3 = APU, 2 = engine 2, 1 = engine 1.
----------------------------------------------------------------------
local SIGNALS = {
  EXT_POWER_ON  = { "CONNECT EXTERNAL POWER", "Two fingers of the right hand inserted into a circle made by the left hand" },
  EXT_POWER_OFF = { "DISCONNECT EXTERNAL POWER", "Two fingers of the right hand withdrawn from the circle made by the left hand" },
  ACK           = { "ACKNOWLEDGED (OK)", "Hand raised, thumb up" },
  APU_START     = { "START APU", "Left hand points to the APU; right hand moves in a horizontal circle, index and middle finger pointing down" },
  ENG2_START    = { "START ENGINE 2 (RIGHT)", "Left hand overhead, two fingers extended; right hand circling at head level" },
  ENG1_START    = { "START ENGINE 1 (LEFT)", "Left hand overhead, one finger extended; right hand circling at head level" },
  APU_STOP      = { "STOP APU", "Throat-cutting action with the left hand; right hand moves in a horizontal circle" },
  WINGS_SPREAD  = { "SPREAD WINGS", "Arms hugged around the shoulders, then swept straight out to the sides" },
  WINGS_FOLD    = { "FOLD WINGS", "Arms straight out at the sides, then swept forward and hugged around the shoulders" },
  FLAPS_LOWER   = { "LOWER FLAPS", "Hands in front, palms together horizontally, then opened from the wrists crocodile-mouth fashion" },
  PROBE_EXT     = { "EXTEND REFUELING PROBE", "Arm straight ahead, fist clenched, swung 90 degrees to the side" },
  PROBE_RET     = { "RETRACT REFUELING PROBE", "Arm out to the side, fist clenched, swung back to straight ahead" },
  SB_OPEN       = { "OPEN SPEEDBRAKE", "Hands in front, palms together vertically, then opened from the wrists crocodile-mouth fashion" },
  SB_CLOSE      = { "CLOSE SPEEDBRAKE", "Hands in front vertically, palms open from the wrists, then suddenly closed" },
  LBAR_LOWER    = { "LOWER LAUNCH BAR", "Right elbow resting in the left palm at waist level, right hand brought down to horizontal" },
  LBAR_RAISE    = { "RAISE LAUNCH BAR", "Right elbow resting in the left palm at waist level, right forearm horizontal, right hand brought up to shoulder level" },
  HOOK_DOWN     = { "LOWER HOOK", "Right fist, thumb down, lowered suddenly to meet the horizontal palm of the left hand" },
  HOOK_UP       = { "RAISE HOOK", "Right fist, thumb up, raised suddenly to meet the horizontal palm of the left hand" },
  -- pilot's own signals (sent with "Done (pilot signal)")
  P_OK          = { "READY TO START (OK)", "Thumbs up" },
  P_READY_START = { "READY FOR START (APU)", "Three fingers up" },
  P_READY_ENG2  = { "READY FOR ENGINE 2", "Two fingers up" },
  P_READY_ENG1  = { "READY FOR ENGINE 1", "One finger up" },
  P_READY_GO    = { "READY TO GO FLYING", "Thumbs up to the plane captain" },
}

-- what the pilot is asked to do, shown under the plane captain's signal
local ASK = {
  WINGS_SPREAD = "Spread the wings.",
  WINGS_FOLD   = "Fold the wings for taxi (spread again at the catapult on the director's signal).",
  FLAPS_LOWER  = "13b. Flaps - HALF (they stay HALF).",
  PROBE_EXT    = "Extend the refueling probe.",
  PROBE_RET    = "Retract the refueling probe.",
  SB_OPEN      = "Open the speedbrake.",
  SB_CLOSE     = "Close the speedbrake.",
  LBAR_LOWER   = "Launch bar switch - EXTEND.",
  LBAR_RAISE   = "Launch bar switch - RETRACT.",
  HOOK_DOWN    = "Lower the hook.",
  HOOK_UP      = "Raise the hook.",
}

----------------------------------------------------------------------
-- STEPS
-- wait / skipIf: timer, ack (Done only), engineIdle (RPM, Done only if RPM unreadable),
--                arg, argDelta, argNear (back to a value remembered by another step), range, span
-- timeout: only on plane-captain-only timer steps; action steps never time out.
----------------------------------------------------------------------
local PHASES = { "START", "CHECKS" }
local GATE_PILOT = { START = "P_OK" }      -- pilot signal shown when the phase is opened
local STEPS = {
  -- START
  { id = "S00", phase = "START", signal = "ACK", wait = { type = "timer", t = 3 } },
  { id = "S1", phase = "START", signal = "EXT_POWER_ON", opt = "extpower", wait = { type = "timer", t = 8 } },
  { id = "S0P", phase = "START", wait = { type = "ack" }, pilotOnDone = "P_READY_START",
    hint = "Give your APU start signal: Plane captain > Done (pilot signal)" },
  { id = "S2", phase = "START", signal = "APU_START", wait = { type = "timer", t = 6 } },
  { id = "S2W", phase = "START", wait = { type = "ack" }, pilotOnDone = "P_READY_ENG2",
    hint = "APU READY light on? Give your engine 2 start signal: Plane captain > Done (pilot signal)" },
  { id = "S3", phase = "START", signal = "ENG2_START", wait = { type = "engineIdle", eng = "right", rpm = 60 } },
  { id = "S3W", phase = "START", wait = { type = "ack" }, pilotOnDone = "P_READY_ENG1",
    hint = "Engine 2 at idle. Give your engine 1 start signal: Plane captain > Done (pilot signal)" },
  { id = "S4", phase = "START", signal = "ENG1_START", wait = { type = "engineIdle", eng = "left", rpm = 60 } },
  { id = "S5", phase = "START", signal = "EXT_POWER_OFF", opt = "extpower", wait = { type = "timer", t = 8 } },
  { id = "S6", phase = "START", signal = "APU_STOP", opt = "apustop", wait = { type = "timer", t = 8 } },
  -- CHECKS, NATOPS BEFORE TAXI order. F/A-18C draw arguments: wings 8 (0 spread, 1 folded),
  -- flaps 9, control stick 395 (pitch) / 396 (roll) (Cockpit/Scripts/mainpanel_init.lua), rudders
  -- 17/18, probe 22, speedbrake 21, hook 25, launch bar CFG.LAUNCHBAR_ARG
  { id = "C1", phase = "CHECKS", signal = "WINGS_SPREAD", wait = { type = "arg", arg = 8, op = "<", v = 0.05 },
    skipIf = { type = "arg", arg = 8, op = "<", v = 0.05 } },
  { id = "C2", phase = "CHECKS", check = { "13. Controls - CHECK",
      "a. Control stick - CYCLE: full aft, full forward, full left, full right (any order)" },
    wait = { type = "range", args = { { 395, 0.7, -0.5 }, { 396, 0.7, -0.7 } } } },
  { id = "C3", phase = "CHECKS", signal = "FLAPS_LOWER", wait = { type = "argDelta", arg = 9, d = 0.1 } },
  { id = "C4", phase = "CHECKS", check = { "13. Controls - CHECK",
      "c. Rudder pedals - CYCLE 30 degrees left and right (any order)" },
    wait = { type = "span", args = { 17, 18 }, d = 0.8 } },
  { id = "C5", phase = "CHECKS", signal = "PROBE_EXT", wait = { type = "arg", arg = 22, op = ">", v = 0.9 } },
  { id = "C6", phase = "CHECKS", signal = "PROBE_RET", wait = { type = "arg", arg = 22, op = "<", v = 0.1 },
    skipIf = { type = "arg", arg = 22, op = "<", v = 0.1 } },
  { id = "C7", phase = "CHECKS", signal = "SB_OPEN", wait = { type = "arg", arg = 21, op = ">", v = 0.9 } },
  { id = "C8", phase = "CHECKS", signal = "SB_CLOSE", wait = { type = "arg", arg = 21, op = "<", v = 0.1 },
    skipIf = { type = "arg", arg = 21, op = "<", v = 0.1 } },
  { id = "C9", phase = "CHECKS", signal = "LBAR_LOWER", lbar = "lower" },
  { id = "C10", phase = "CHECKS", signal = "LBAR_RAISE", lbar = "raise" },
  { id = "C11", phase = "CHECKS", signal = "HOOK_DOWN", wait = { type = "arg", arg = 25, op = ">", v = 0.6 } },
  { id = "C12", phase = "CHECKS", signal = "HOOK_UP", wait = { type = "arg", arg = 25, op = "<", v = 0.1 },
    skipIf = { type = "arg", arg = 25, op = "<", v = 0.1 } },
  { id = "C13", phase = "CHECKS", signal = "WINGS_FOLD", wait = { type = "arg", arg = 8, op = ">", v = 0.95 },
    skipIf = { type = "arg", arg = 8, op = ">", v = 0.95 } },
  { id = "C14", phase = "CHECKS", wait = { type = "ack" }, pilotOnDone = "P_READY_GO",
    hint = "Checks complete. When ready to go flying, give the plane captain a thumbs up: Plane captain > Done (pilot signal)" },
}

-- launch bar: automatic with a known argument, calibration (Done + logging) without one
for _, st in ipairs(STEPS) do
  if st.lbar then
    if CFG.LAUNCHBAR_ARG then
      if st.lbar == "lower" then
        st.wait = { type = "argDelta", arg = CFG.LAUNCHBAR_ARG, d = 0.5 }
        st.remember = { key = "lbarUp", arg = CFG.LAUNCHBAR_ARG }
      else
        st.wait = { type = "argNear", arg = CFG.LAUNCHBAR_ARG, key = "lbarUp", tol = 0.1, fallback = 0.1 }
      end
    else
      st.wait = { type = "calib" }
      st.hint = "Calibration: when the launch bar has moved, Plane captain > Done (pilot signal)"
    end
  end
end

----------------------------------------------------------------------
-- STATE / HELPERS
----------------------------------------------------------------------
local PC = {
  flow = { phase = "IDLE", step = nil, idx = nil, t0 = 0, base = {}, seen = {}, mem = {}, ending = false, gen = 0 },
  rpm = { available = nil, left = nil, right = nil, t = 0 },
  move = { anchor = nil },
  calib = nil,                 -- launch bar calibration: { base = {}, mn = {}, mx = {}, cur = {} }
  gid = nil,
  ownMenu = nil,
  milestones = {},            -- v1.2.2: phase -> first completion time (Flight_Timeline)
}
TRT.PlaneCaptain = PC

local function now() return timer.getTime() end
local function log(s) env.info("PlaneCaptain | " .. s) end

local function hero()
  local u = Unit.getByName(CFG.PLAYER_UNIT)
  if not (u and u:isExist()) then return nil end
  local g = u:getGroup()
  if not g or g:getName() ~= CFG.PLAYER_GROUP then return nil end
  return u
end

local function groupId()
  local u = hero()
  local g = u and u:getGroup()
  return g and g:getID() or nil
end

-- replace = true: clears the screen first (step messages); false: added under what is shown
local function say(text, dur, replace)
  local SD = TRT.ScoreDisplay                                  -- v1.3.0: replacing text drops the card
  if replace == true and SD and SD.pcClear then pcall(SD.pcClear) end
  local gid = groupId()
  if gid then trigger.action.outTextForGroup(gid, text, dur, replace == true)
  else trigger.action.outText(text, dur, replace == true) end
end

-- v1.3.0: Score_Display picture card for this step id, if it has one
local function cardFor(id)
  local SD = TRT.ScoreDisplay
  if not (SD and SD.pcHas and SD.pcCard) then return nil end
  local ok, has = pcall(SD.pcHas, id)
  return (ok and has) and SD or nil
end

-- v1.3.2: phase-end card (S_END / C_END); false -> caller shows the text
local function endCard(id, dur)
  local SD = cardFor(id)
  if not SD then return false end
  say("", 1, true)
  local ok, shown = pcall(SD.pcCard, id, dur)
  if ok and shown then log("card " .. id) return true end
  log("card " .. id .. " failed -> text")
  return false
end

local function note(text) say("[PLANE CAPTAIN] " .. text, CFG.MSG_NOTE, false) end

local function argValue(u, a)
  local ok, v = pcall(u.getDrawArgumentValue, u, a)
  if ok and type(v) == "number" then return v end
  return nil
end

-- Engine RPM: the mission environment has no engine RPM; read it from the export environment.
-- If that is not allowed, the engine steps fall back to "Done".
local RPM_CODE = 'local e = LoGetEngineInfo and LoGetEngineInfo() ' ..
                 'if e and e.RPM then return string.format("%.1f,%.1f", e.RPM.left or -1, e.RPM.right or -1) end return ""'
function PC.readRPM()
  local R = PC.rpm
  if R.available == false then return nil end
  if now() - R.t < 0.2 then return R.left, R.right end
  R.t = now()
  local ok, res = pcall(function()
    if type(net) ~= "table" or type(net.dostring_in) ~= "function" then error("net.dostring_in not available") end
    return net.dostring_in("export", RPM_CODE)
  end)
  if ok and type(res) == "string" and res ~= "" then
    local l, r = string.match(res, "([%-%d%.]+),([%-%d%.]+)")
    l, r = tonumber(l), tonumber(r)
    if l and r and l >= 0 and r >= 0 then
      if R.available ~= true then log(string.format("RPM probe: available (L=%.1f R=%.1f)", l, r)) end
      R.available, R.left, R.right = true, l, r
      return l, r
    end
  end
  if R.available == nil then log("RPM probe: not available (" .. tostring(res) .. ")") end
  R.available = false
  return nil
end

-- aircraft position in the carrier's own frame (forward, right), so that the carrier's speed and
-- turns do not count as movement; world x/z if the carrier is not found
local function deckPos(u)
  local ok, p = pcall(u.getPoint, u)
  if not ok or type(p) ~= "table" then return nil end
  local c = Unit.getByName(CFG.CARRIER_UNIT)
  if c and c:isExist() then
    local okc, cp = pcall(c.getPosition, c)
    if okc and type(cp) == "table" and cp.p and cp.x and cp.z then
      local dx, dy, dz = p.x - cp.p.x, p.y - cp.p.y, p.z - cp.p.z
      return dx * cp.x.x + dy * cp.x.y + dz * cp.x.z, dx * cp.z.x + dy * cp.z.y + dz * cp.z.z
    end
  end
  return p.x, p.z
end

-- metres moved on the deck since the anchor was set (the anchor is set on the first call)
local function deckMoved(u)
  local a, b = deckPos(u)
  if not a then return 0 end
  local M = PC.move
  if not M.anchor then M.anchor = { a, b }; return 0 end
  local da, db = a - M.anchor[1], b - M.anchor[2]
  return math.sqrt(da * da + db * db)
end

-- launch bar calibration: arguments that are already explained are not reported
local CALIB_SKIP = { [8] = true, [9] = true, [10] = true, [17] = true, [18] = true, [21] = true, [22] = true,
  [25] = true, [38] = true, [39] = true, [99] = true, [395] = true, [396] = true }
for a = 499, 536 do CALIB_SKIP[a] = true end      -- pilot body / stick / throttle / rudder animation

local function calibScan(u)
  local C = PC.calib
  if not C then return end
  for a = 0, CFG.SCAN_MAX do
    local v = argValue(u, a)
    if v then
      if C.base[a] == nil then C.base[a] = v end
      if not C.mn[a] or v < C.mn[a] then C.mn[a] = v end
      if not C.mx[a] or v > C.mx[a] then C.mx[a] = v end
      C.cur[a] = v
    end
  end
end

local function calibReport()
  local C = PC.calib
  if not C then return end
  local found = 0
  for a = 0, CFG.SCAN_MAX do
    local b, mn, mx, cur = C.base[a], C.mn[a], C.mx[a], C.cur[a]
    if b and mn and mx and not CALIB_SKIP[a] and (mx - mn) >= 0.3 then
      local back = math.abs(cur - b) <= 0.1
      log(string.format("LBAR calibration: arg %d base=%.3f min=%.3f max=%.3f now=%.3f %s",
        a, b, mn, mx, cur, back and "<- moved and came back" or "(did not come back)"))
      found = found + 1
    end
  end
  if found == 0 then log("LBAR calibration: no argument moved >= 0.3 (launch bar not cycled?)") end
  PC.calib = nil
end

----------------------------------------------------------------------
-- MESSAGES
----------------------------------------------------------------------
local function sigLine(who, key)
  local s = SIGNALS[key]
  if not s then return nil end
  return string.format("%s: %s\n      %s", who, s[1], s[2])
end

-- one message per step: pilot's signal (optional), plane captain's signal, what to do; held on
-- screen until the next step replaces it
local function showStep(s, pilotKey)
  local lines = { s.check and "[BEFORE TAXI CHECK]" or "[PLANE CAPTAIN]" }
  local pl = pilotKey and sigLine("You", pilotKey)
  if pl then lines[#lines + 1] = pl end
  local cl = s.signal and sigLine("Plane captain", s.signal)
  if cl then lines[#lines + 1] = cl end
  if s.check then for _, l in ipairs(s.check) do lines[#lines + 1] = l end end
  if s.signal and ASK[s.signal] then lines[#lines + 1] = ">> " .. ASK[s.signal] end
  if s.wait and s.wait.type == "engineIdle" then
    local n = (s.wait.eng == "left") and "1" or "2"
    if PC.rpm.available == true then
      lines[#lines + 1] = string.format(">> Start engine %s. The step closes by itself at idle (%d %% RPM).", n, s.wait.rpm)
    else
      lines[#lines + 1] = string.format(">> Start engine %s. At idle: Plane captain > Done (pilot signal)", n)
    end
  end
  if s.hint then lines[#lines + 1] = ">> " .. s.hint end
  if #lines == 1 then return end
  local SD = cardFor(s.id)                                     -- v1.3.0
  if SD then
    say("", 1, true)                                           -- clear the previous step (text + card)
    local ok, shown = pcall(SD.pcCard, s.id)
    if ok and shown then
      if s.wait and s.wait.type == "engineIdle" and PC.rpm.available ~= true then
        say(string.format("[PLANE CAPTAIN] Engine %s at idle: Plane captain > Done (pilot signal)",
          (s.wait.eng == "left") and "1" or "2"), CFG.MSG_HOLD, false)
      end
      log("card " .. s.id)
      return
    end
    log("card " .. s.id .. " failed -> text")
  end
  say(table.concat(lines, "\n"), CFG.MSG_HOLD, true)
  log("show " .. s.id .. ": " .. string.gsub(table.concat(lines, " | ", 2), "\n%s*", " / "))
end

----------------------------------------------------------------------
-- FLOW ENGINE
----------------------------------------------------------------------
local function stepEnabled(s) return not s.opt or CFG.OPTIONAL[s.opt] end
local function firstStepOf(phase)
  for i, s in ipairs(STEPS) do if s.phase == phase and stepEnabled(s) then return i end end
end
local function nextEnabled(i)
  local j = i + 1
  while STEPS[j] and not stepEnabled(STEPS[j]) do j = j + 1 end
  return STEPS[j] and j or nil
end
local function phaseIndex(name)
  for i, p in ipairs(PHASES) do if p == name then return i end end
end

local function evalCond(c, u, F)
  if not c then return false end
  local t = c.type
  if t == "timer" then return (now() - F.t0) >= c.t
  elseif t == "ack" or t == "calib" then return false
  elseif t == "engineIdle" then
    local l, r = PC.readRPM()
    if not l then return false end
    return ((c.eng == "left") and l or r) >= c.rpm
  elseif t == "arg" then
    local v = argValue(u, c.arg)
    if not v then return false end
    if c.op == ">" then return v > c.v else return v < c.v end
  elseif t == "argDelta" then
    local v, b = argValue(u, c.arg), F.base[c.arg]
    return v ~= nil and b ~= nil and math.abs(v - b) >= c.d
  elseif t == "argNear" then
    local v = argValue(u, c.arg)
    if not v then return false end
    local ref = F.mem[c.key]
    if ref == nil then return v < c.fallback end
    return math.abs(v - ref) <= c.tol
  elseif t == "range" then
    local all = true
    for _, r in ipairs(c.args) do
      local a, hi, lo = r[1], r[2], r[3]
      local v = argValue(u, a)
      F.seen[a] = F.seen[a] or {}
      if v then
        if v >= hi then F.seen[a].hi = true end
        if v <= lo then F.seen[a].lo = true end
      end
      if not (F.seen[a].hi and F.seen[a].lo) then all = false end
    end
    return all
  elseif t == "span" then
    -- every argument must sweep at least d since the step started (rudders toe in with the flaps down)
    local all = true
    for _, a in ipairs(c.args) do
      local v = argValue(u, a)
      local sn = F.seen[a]
      if not sn then sn = { mn = F.base[a] or v, mx = F.base[a] or v }; F.seen[a] = sn end
      if v then
        if not sn.mn or v < sn.mn then sn.mn = v end
        if not sn.mx or v > sn.mx then sn.mx = v end
      end
      if not (sn.mn and sn.mx and sn.mx - sn.mn >= c.d) then all = false end
    end
    return all
  end
  return false
end

local function condArgs(c, out)
  if not c then return end
  if c.arg then out[#out + 1] = c.arg end
  if c.args then for _, r in ipairs(c.args) do out[#out + 1] = (type(r) == "table") and r[1] or r end end
end

-- "Done (pilot signal)" counts only where the pilot gives a signal, or where the engine
-- state cannot be read
local function doneAccepted(s)
  if not s or not s.wait then return false end
  if s.wait.type == "ack" or s.wait.type == "calib" then return true end
  if s.wait.type == "engineIdle" then return PC.rpm.available ~= true end
  return false
end

local function refreshMenu()
  if TRT.Menu and TRT.Menu.Refresh then TRT.Menu.Refresh() end
end

local enterStep

-- v1.3.1: wait types where "condition" means the aircraft did it (pcOk sound)
local OK_WAITS = { arg = true, argDelta = true, argNear = true, range = true, span = true, engineIdle = true }

local function completeStep(reason)
  local F = PC.flow
  local s = F.step
  if not s or F.ending then return end
  F.ending = true
  log(string.format("step %s done (%s) after %.1f s", s.id, reason, now() - F.t0))
  if reason == "condition" and s.wait and OK_WAITS[s.wait.type] then      -- v1.3.1
    local SD = TRT.ScoreDisplay
    if SD and SD.pcOk then pcall(SD.pcOk) end
  end
  if s.lbar == "raise" and PC.calib then calibReport() end
  if reason ~= "condition" then
    for a, sn in pairs(F.seen) do
      log(string.format("  arg %s seen: min=%s max=%s hi=%s lo=%s base=%s", tostring(a), tostring(sn.mn), tostring(sn.mx),
        tostring(sn.hi), tostring(sn.lo), tostring(F.base[a])))
    end
  end
  local pilotNext = (reason == "pilot done") and s.pilotOnDone or nil
  local nxt = nextEnabled(F.idx)
  local curPhase, gen = s.phase, F.gen
  timer.scheduleFunction(function()
    if F.gen ~= gen then return end
    F.ending = false
    if not hero() then return end
    if nxt and STEPS[nxt].phase == curPhase then
      enterStep(nxt, pilotNext)
    else
      F.step, F.idx = nil, nil
      local np = PHASES[(phaseIndex(curPhase) or 0) + 1]
      if not PC.milestones[curPhase] then                      -- v1.2.2
        PC.milestones[curPhase] = now()
        log(string.format("milestone %s complete t=%.1f", curPhase, PC.milestones[curPhase]))
      end
      if np then
        F.phase = "WAIT_" .. np
        if not endCard("S_END", CFG.MSG_HOLD) then                 -- v1.3.2
          say("[PLANE CAPTAIN] Engines running.\n>> When ready: Plane captain > Ready for checks", CFG.MSG_HOLD, true)
        end
      else
        F.phase = "DONE"
        local lines = { "[PLANE CAPTAIN]" }
        local pl = pilotNext and sigLine("You", pilotNext)
        if pl then lines[#lines + 1] = pl end
        lines[#lines + 1] = ">> Plane captain stands by with you until the director (yellow shirt) takes the aircraft."
        if not endCard("C_END", CFG.MSG_END) then                  -- v1.3.2
          say(table.concat(lines, "\n"), CFG.MSG_END, true)
        end
      end
      log("phase -> " .. F.phase)
      refreshMenu()
    end
  end, nil, now() + CFG.STEP_GAP)
end

enterStep = function(i, pilotKey)
  local F = PC.flow
  local s = STEPS[i]
  local u = hero()
  F.idx, F.step, F.t0, F.base, F.seen, F.ending = i, s, now(), {}, {}, false
  F.phase = s.phase
  log(string.format("step %s enter (%s) t=%.2f", s.id, s.signal or "-", F.t0))
  if s.lbar == "lower" and s.wait.type == "calib" then
    PC.calib = { base = {}, mn = {}, mx = {}, cur = {} }
    log("LBAR calibration: scanning arguments 0.." .. CFG.SCAN_MAX)
  end
  if u then
    local args = {}
    condArgs(s.wait, args); condArgs(s.skipIf, args)
    for _, a in ipairs(args) do F.base[a] = argValue(u, a) end
    if s.remember then
      F.mem[s.remember.key] = argValue(u, s.remember.arg)
      log(string.format("  remember %s = %s", s.remember.key, tostring(F.mem[s.remember.key])))
    end
    if s.skipIf and evalCond(s.skipIf, u, F) then
      log("step " .. s.id .. " skipped: already done")
      completeStep("already done")
      return
    end
  end
  showStep(s, pilotKey)
  refreshMenu()
end

function PC.gate(phase)
  local F = PC.flow
  local u = hero()
  if not u then return end
  if u:inAir() then note("Not available in the air."); return end
  local target = phaseIndex(phase)
  local curIdx = phaseIndex((string.gsub(F.phase, "^WAIT_", "")))
  if F.phase == "DONE" or (curIdx and curIdx > target) then note(phase .. " already done."); return end
  if F.step and F.step.phase == phase then note(phase .. " is already running."); return end
  local i = firstStepOf(phase)
  if not i then return end
  log("gate " .. phase .. " opened")
  F.gen = F.gen + 1
  F.step, F.ending = nil, false
  if phase == "START" then F.mem = {} end
  PC.move.anchor = nil
  enterStep(i, GATE_PILOT[phase])
end

function PC.manualAdvance(reason)
  local F = PC.flow
  local s = F.step
  if not s or F.ending then note("No check is running."); return end
  if reason == "pilot done" and not doneAccepted(s) then
    if s.wait and s.wait.type == "engineIdle" then
      local l, r = PC.readRPM()
      local v = (s.wait.eng == "left") and l or r
      note(string.format("Engine not at idle yet (%s %% RPM). The step closes by itself at %d %%.",
        v and string.format("%.0f", v) or "?", s.wait.rpm))
    elseif s.wait and s.wait.type == "timer" then
      note("Wait for the plane captain's signal.")
    else
      note("Waiting for the aircraft. Do what the plane captain signals, or Skip step.")
    end
    log("step " .. s.id .. ": Done refused")
    return
  end
  completeStep(reason)
end

-- why: shown to the pilot (nil = silent)
function PC.abort(reason, why)
  local F = PC.flow
  if F.phase == "IDLE" or F.phase == "DONE" then return end
  F.gen = F.gen + 1
  F.step, F.idx, F.ending = nil, nil, false
  F.phase = "IDLE"
  PC.move.anchor = nil
  PC.calib = nil
  log("flow aborted: " .. reason)
  if why then say("[PLANE CAPTAIN] " .. why, CFG.MSG_END, true) end
  refreshMenu()
end

function PC.stop(reason)
  local F = PC.flow
  if F.phase == "IDLE" and not F.step then return end
  F.gen = F.gen + 1
  F.step, F.idx, F.ending = nil, nil, false
  F.phase = "DONE"
  log("flow stopped: " .. reason)
  refreshMenu()
end

function PC.reset()
  local F = PC.flow
  F.gen = F.gen + 1
  F.phase, F.step, F.idx, F.ending, F.mem = "IDLE", nil, nil, false, {}
  PC.move.anchor = nil
  PC.calib = nil
  log("flow reset")
end

local function flowActive()
  local p = PC.flow.phase
  return p ~= "IDLE" and p ~= "DONE"
end

local function flowTick(u)
  local F = PC.flow
  if not flowActive() then PC.move.anchor = nil; return end
  -- taxi (movement on the deck) aborts the checks
  local moved = deckMoved(u)
  if moved > CFG.MOVE_DIST then
    PC.abort(string.format("aircraft moved %.1f m on deck", moved), "Aircraft moving - ground checks aborted.")
    return
  end
  local s = F.step
  if PC.calib then calibScan(u) end
  if not s or F.ending then return end
  if evalCond(s.wait, u, F) then completeStep("condition"); return end
  if s.timeout and (now() - F.t0) >= s.timeout then completeStep("timeout") end
end

----------------------------------------------------------------------
-- MENU
----------------------------------------------------------------------
local function abortItem()
  return { "Abort checks", function() PC.abort("pilot", "Ground checks aborted.") end }
end

local function menuItems()
  local F = PC.flow
  local items = {}
  if F.phase == "IDLE" then
    items[#items + 1] = { "Ready to start", function() PC.gate("START") end }
    items[#items + 1] = { "Ready for checks (engines running)", function() PC.gate("CHECKS") end }
  elseif F.phase == "WAIT_CHECKS" then
    items[#items + 1] = { "Ready for checks", function() PC.gate("CHECKS") end }
    items[#items + 1] = abortItem()
  elseif F.step then
    if doneAccepted(F.step) then
      items[#items + 1] = { "Done (pilot signal)", function() PC.manualAdvance("pilot done") end }
    end
    items[#items + 1] = { "Skip step", function() PC.manualAdvance("pilot skip") end }
    items[#items + 1] = abortItem()
  end
  return items
end

if TRT.Menu and TRT.Menu.Register then
  TRT.Menu.Register(CFG.MENU_SECTION, "PLANECAPTAIN", function(ph)
    if ph ~= "DECK" then return {} end
    local items = menuItems()
    if #items == 0 then return {} end
    return { { "Plane captain", sub = items } }
  end, CFG.MENU_ORDER)
  log("menu: F10 > " .. CFG.MENU_SECTION .. " > Plane captain (Menu_Manager)")
else
  -- fallback: own group menu with fixed items (Done is still refused where it does not apply)
  function PC.buildOwnMenu()
    local gid = groupId()
    if not gid or PC.ownMenu == gid then return end
    pcall(missionCommands.removeItemForGroup, gid, { "Plane captain" })
    local root = missionCommands.addSubMenuForGroup(gid, "Plane captain")
    missionCommands.addCommandForGroup(gid, "Ready to start", root, function() PC.gate("START") end)
    missionCommands.addCommandForGroup(gid, "Ready for checks", root, function() PC.gate("CHECKS") end)
    missionCommands.addCommandForGroup(gid, "Done (pilot signal)", root, function() PC.manualAdvance("pilot done") end)
    missionCommands.addCommandForGroup(gid, "Skip step", root, function() PC.manualAdvance("pilot skip") end)
    missionCommands.addCommandForGroup(gid, "Abort checks", root, function() PC.abort("pilot", "Ground checks aborted.") end)
    PC.ownMenu = gid
    log("menu: F10 > Plane captain (own group menu)")
  end
end

----------------------------------------------------------------------
-- EVENTS / POLL
----------------------------------------------------------------------
local EH = {}
function EH:onEvent(e)
  if not e or not e.initiator then return end
  local ok, name = pcall(function() return e.initiator:getName() end)
  if not ok or name ~= CFG.PLAYER_UNIT then return end
  if e.id == world.event.S_EVENT_BIRTH then
    PC.reset()
    PC.ownMenu = nil
    timer.scheduleFunction(function() if PC.buildOwnMenu then PC.buildOwnMenu() end; refreshMenu() end, nil, now() + 1)
  elseif e.id == world.event.S_EVENT_TAKEOFF then
    PC.stop("takeoff")
  end
end
world.addEventHandler(EH)

timer.scheduleFunction(function(_, t)
  local ok, err = pcall(function()
    local u = hero()
    if u then
      if PC.buildOwnMenu then PC.buildOwnMenu() end
      flowTick(u)
    end
  end)
  if not ok then log("poll error: " .. tostring(err)) end
  return t + CFG.POLL
end, nil, now() + 1)

timer.scheduleFunction(function() PC.readRPM() end, nil, now() + 2)   -- log whether RPM can be read
log("v" .. CFG.VERSION .. " loaded for " .. CFG.PLAYER_GROUP .. " / " .. CFG.PLAYER_UNIT)
