-- Airboss_CaseSync.lua | v1.1.0
-- v1.1.0 (2026-11-05, Into The Grey P1): optional fixed hold radial. When a mission pack sets
--   TRT.HOLD_RADIAL_MAG (magnetic, e.g. ITG 195), the CASE II / III holding offset is computed from the LIVE
--   carrier heading instead of the OFFSET table: CASE III baseline = final bearing (mag) - 180, CASE II =
--   BRC (mag) - 180 (AIRBOSS:GetRadial), offset = radial - baseline (-180..180). The ITG carrier changes
--   course on its route (legs 000 / 082 / 209 / 267 T), so a fixed offset would move the hold with the ship.
--   Re-aligned (window rebuilt) while recovery is not armed (flag 101) whenever the hold radial is more than
--   TRT.HOLD_RADIAL_TOL (default 2) deg off, and once more when recovery arms; never after that (a rebuild
--   with the hero in the stack would reset AIRBOSS's queue). TRT.HOLD_RADIAL_MAG nil (SDT / SEA2STEEL): no change.
-- v1.0.9: comment only - polling-pattern reference now names Carrier_Geometry
--   (merged Distance_Flag_v3 / Radial_Flag_v1) instead of the unloaded Radial_Flag_v1.2.0.
-- TRT Syria Recovery Framework - syncs TRT.Airboss recovery case to ME flag 100
--
-- v1.0.8: global SetSuperCarrier() stub until TrapTraining.lua defines the real one. The ME trigger
--   "SetSuperCarrier" (a_do_script "SetSuperCarrier(true)") fired ~6 s after birth in CAS (L)
--   2026-11-02, before TrapTraining was loaded: "attempt to call global 'SetSuperCarrier' (a nil
--   value)". The stub does what Bankler's does (carrierTCN 72X / 74X); this file already forces 72X
--   for Bankler, so the trigger is redundant either way. TrapTraining overwrites the stub on load.
-- v1.0.7: ApplyRecoveryCase exported as TRT.CaseSync.ApplyRecoveryCase (idempotent);
--   Recovery_Approach v1.0.4 calls it when it arms, before announcing the case.
-- v1.0.6: departure and recovery case are both planned in the ME:
--   flag 100 = active case; set in the ME "CASE SELECTOR" = DEPARTURE case.
--   flag 102 = RECOVERY case (1/2/3), also set in the ME at mission start.
--   When recovery arms (flag 101, ME "Commence Recovery", ~51 NM inbound) this
--   script copies flag 102 into flag 100 once. The usual rebuild below then
--   moves AIRBOSS, Bankler and scoring to the recovery case, and CV_Comms
--   v1.5.1 has Marshal announce it ("99, Mother is now CASE N recovery ...").
--   Flag 102 unset / 0 -> recovery case = departure case (no change).
-- v1.0.5: TRT.CaseSync.tRebuild = timer.getTime() at each window rebuild; CV_Comms
--   v1.5.0 keeps AIRBOSS's "recovery stopped, deck closed" call silent right after a
--   case change (the deck is not closing, the window is being replaced).
-- v1.0.4: Bankler identity: its PlayerData uses fixed per-slot tables (Player_01 ->
--   modex 200, "Chevy11"). Each poll now overwrites pd.modex with the unit's real
--   onboard number (467) and pd.fixedCallsign with the DCS group callsign
--   ("Enfield 1-1" style). The player name shown first is the DCS profile name.
-- LOAD ORDER: after Airboss_Start.lua (needs TRT.Airboss to exist already).
-- Loaded via: ME "Do Script File" (ResKey_Action_302), embedded by build.py.
--
-- v1.0.3: Bankler's CASE I trainer (TrapTraining.lua) follows flag 100 too:
--   active in CASE I and CASE II, OFF in CASE III (its break / downwind / score
--   messages are meaningless on a CASE III straight-in). Done by wrapping its
--   global Init() (round start) once it exists, and ending any running round when
--   the case becomes III. Also feeds Bankler the real TACAN (72X) and live BRC
--   (its file hard-codes 74X / 353). Bankler's own file is untouched.
-- v1.0.2: OFFSET CASE II 30 -> 21, CASE III 0 -> 30: both cases hold on the
--   TRT chart fix R-196 (angels 10 / 25 DME via Airboss_Start v1.0.3). CASE II radial =
--   BRC(mag 355) - 180 + 21; CASE III radial = FB(mag ~346) - 180 + 30.
-- v1.0.1: FIX — flag 100 set at mission start was never applied. The ME
--   "CASE SELECTOR" trigger (trigrules[1], triggerStart) sets flag 100 BEFORE
--   this file loads, so the old baseline read (lastFlag = flag 100) saw no
--   change and AIRBOSS stayed on Airboss_Start's hardcoded CASE II -- e.g.
--   CASE II Marshal instructions at night with flag 100 = 3. Baseline is now
--   nil: the first poll always (re)builds the window from flag 100.
--
-- PURPOSE: Core_Scoring.lua grades against ME flag 100. Airboss_Start.lua
-- sets TRT.Airboss's recovery case independently, once, at load time. This
-- script is the one place that keeps the two in sync afterward: if flag 100
-- changes mid-mission, TRT.Airboss's actual Marshal/ICLS/LSO behavior
-- switches to match, using the only runtime case-switch mechanism this
-- class actually exposes.
--
-- CONFIRMED FROM Airboss.lua SOURCE (not assumed):
--   - AIRBOSS:SetRecoveryCase() only writes self.defaultcase / self.case.
--     It does NOT touch the active recovery window's CASE/OFFSET fields and
--     does NOT reopen/close anything. Calling it after :Start() silently
--     desyncs the class's internal "current case" flag from what the
--     Marshal stack and pattern are actually doing. Do not use it here.
--   - The documented, working mechanism is: delete existing recovery
--     windows, then AIRBOSS:AddRecoveryWindow() a new one with the new
--     case. That's what this script does.
--
-- Edge-detects on the RAW ME flag value via trigger.misc.getUserFlag(100)
-- polled on a timer -- same shape as the Carrier_Geometry.lua polling
-- pattern (merged Distance_Flag_v3 / Radial_Flag_v1), but structurally immune
-- to its resync bug class: it compares a DERIVED counter against the actual
-- sector and can drift apart (see Carrier_Geometry v1.1.3); this compares the ME flag's raw value
-- directly every poll, so there's nothing to drift from.

TRT = TRT or {}
TRT.CaseSync = TRT.CaseSync or {}

-- Holding offset per case, degrees -- passed straight to
-- AIRBOSS:AddRecoveryWindow's holdingoffset param.
--
-- SIGN: confirmed from source (AIRBOSS:GetRadial, case 2/3:
-- radial = baseline + holdingoffset; and the ARC-IN turn hint uses
-- "holdingoffset < 0 -> turn left"). Positive offset places the hold
-- aft-and-to-PORT of the ship; negative places it aft-and-to-STARBOARD.
-- +30 below is therefore the correct sign for a port-side hold.
--
-- MAGNITUDE: NOT independently verified for your ship. Case II baseline
-- (0 offset) radial = BRC - 180, then + your offset. With FB 346 and a
-- Nimitz-class DCS Supercarrier hull (rwyangle -9.1359 deg in the Airboss
-- source), BRC = FB + ~9.14 = ~355, so radial = 355-180+30 = ~205, i.e.
-- R-205 -- not R-195. If your "CVN" unit's rwyangle is closer to 0 (older,
-- non-Supercarrier hull), BRC ~= FB and 30 deg lands within ~1 deg of
-- R-195. Which one is true depends on which underlying DCS carrier module
-- "CVN" actually is, which I don't have. VERIFY before a graded flight:
-- F10 -> Airboss -> Kneeboard -> Carrier Info shows live BRC; radial =
-- BRC - 180 + 30 should read ~195. If it reads ~205 instead, your hull has
-- the angled-deck correction and you may want offset = 30 - 9 = ~21 to hit
-- R-195 on the nose, or accept R-205 if 30 was chosen deliberately for
-- some other reason (e.g. matching a real-world NATOPS reference number
-- rather than this specific DME/radial fix).
TRT.CaseSync.OFFSET = {
  [1] = 0, -- Case I: AddRecoveryWindow forces this to 0 internally regardless.
  [2] = 21, -- Case II : BRC 355 - 180 + 21 = R-196 (v1.0.2)
  [3] = 30, -- Case III: FB ~346 - 180 + 30 = R-196 (v1.0.2)
}

-- How long the replacement window stays open once (re)opened. Matches
-- Airboss_Start.lua's own indefinite-window choice for a training sandbox.
local WINDOW_STOP = "23:59:00+3"

local DEBUG_LOG_CASE_SYNC = true

-- Baseline read. Deliberately does NOT trigger a switch on load --
-- Airboss_Start.lua already opened the initial window for whatever case it
-- was set to. This just establishes "last known" flag 100 so the first
-- poll doesn't fire a redundant rebuild. If flag 100 hasn't been set by
-- your flag-100-setter trigger yet when this script loads, that's fine --
-- the first real assignment will still be caught as a change on a later
-- poll, whenever that trigger fires.
TRT.CaseSync.lastFlag = nil   -- v1.0.1: first poll applies flag 100 (see header)

-- Bankler gate (v1.0.3) ------------------------------------------------------
TRT.CaseSync.BANKLER_CASES = { [1] = true, [2] = true }   -- Bankler runs in these
local banklerWrapped = false

-- v1.0.4: real onboard number and DCS callsign instead of Bankler's slot tables.
local function BanklerIdentity(pd)
  if type(pd) ~= "table" or not pd.unit or pd.trtIdentity then return end
  local u = pd.unit.GetDCSObject and pd.unit:GetDCSObject()
  if not (u and u:isExist()) then return end
  local n = tonumber(pd.unit.onboardnum or "")
  if not n then
    local okt, tpl = pcall(function() return pd.unit:GetTemplate() end)
    n = okt and tpl and tonumber(tpl.onboard_num or "")
  end
  if n then pd.modex = n end
  local okc, cs = pcall(u.getCallsign, u)
  if okc and type(cs) == "string" and cs ~= "" then
    local name, a, b = cs:match("^(%a+)%s*(%d)%D?(%d)$")
    pd.fixedCallsign = name and (name .. " " .. a .. "-" .. b) or cs
  end
  pd.trtIdentity = true
end

local function BanklerSync(case)
  if type(_G.Init) ~= "function" or type(_G.SetBRC) ~= "function" then return end  -- not loaded yet
  if not banklerWrapped then
    local origInit = _G.Init
    _G.Init = function(id, patternModeZone)
      if not TRT.CaseSync.BANKLER_CASES[TRT.CaseSync.lastFlag or 0] then return end
      return origInit(id, patternModeZone)
    end
    if type(_G.PlayerData) == "table" and type(_G.PlayerData.New) == "function" then
      local origNew = _G.PlayerData.New
      _G.PlayerData.New = function(...)
        local pd = origNew(...)
        pcall(BanklerIdentity, pd)
        return pd
      end
    end
    banklerWrapped = true
    env.info("Airboss_CaseSync | Bankler Init gated on flag 100")
  end
  _G.carrierTCN = "72X"
  local ok, brc = pcall(function() return TRT.Airboss:GetBRC() end)
  if ok and brc then pcall(_G.SetBRC, math.floor(brc + 0.5) % 360) end
  if type(_G.playerDatas) == "table" then                -- v1.0.4: real modex / callsign
    for _, pd in pairs(_G.playerDatas) do pcall(BanklerIdentity, pd) end
  end
  if not TRT.CaseSync.BANKLER_CASES[case or 0] and type(_G.playerDatas) == "table" then
    for _, pd in pairs(_G.playerDatas) do
      if type(pd) == "table" and pd.step and pd.step > 0 then pd.step = 0 end
    end
  end
end

-- v1.0.6: recovery case (flag 102) applied once when recovery arms (flag 101)
TRT.CaseSync.RECOVERY_CASE_FLAG = 102
TRT.CaseSync.COMMENCE_FLAG      = 101
local recoveryCaseApplied = false

local function ApplyRecoveryCase()
  if recoveryCaseApplied then return end
  local arm = trigger.misc.getUserFlag(TRT.CaseSync.COMMENCE_FLAG)
  if not (arm == true or (type(arm) == "number" and arm ~= 0)) then return end
  recoveryCaseApplied = true
  local r, cur = trigger.misc.getUserFlag(TRT.CaseSync.RECOVERY_CASE_FLAG), trigger.misc.getUserFlag(100)
  if r == 1 or r == 2 or r == 3 then
    if r ~= cur then
      env.info(string.format("Airboss_CaseSync | recovery armed: flag 100 %s -> %d (recovery case, flag 102)", tostring(cur), r))
      trigger.action.setUserFlag(100, r)
    else
      env.info(string.format("Airboss_CaseSync | recovery armed: recovery case %d = departure case", r))
    end
  else
    env.info(string.format("Airboss_CaseSync | recovery armed: flag 102 = %s (unset) -> recovery case stays %s", tostring(r), tostring(cur)))
  end
end

TRT.CaseSync.ApplyRecoveryCase = ApplyRecoveryCase   -- v1.0.7

-- v1.1.0: fixed hold radial (TRT.HOLD_RADIAL_MAG) -------------------------------------------------------
local function norm180(a) return ((a + 180) % 360) - 180 end
local function armed()
  local a = trigger.misc.getUserFlag(TRT.CaseSync.COMMENCE_FLAG)
  return a == true or (type(a) == "number" and a ~= 0)
end
--- Offset (deg) that puts the CASE II / III hold on TRT.HOLD_RADIAL_MAG, or nil (not set / no carrier).
function TRT.CaseSync.HoldOffset(case)
  if not TRT.HOLD_RADIAL_MAG or (case ~= 2 and case ~= 3) then return nil end
  local ok, base = pcall(function()
    if case == 3 then return TRT.Airboss:GetFinalBearing(true) end
    return TRT.Airboss:GetBRC()
  end)
  if not ok or type(base) ~= "number" then return nil end
  return math.floor(norm180(TRT.HOLD_RADIAL_MAG - (base - 180)) + 0.5)
end
local alignedOffset, alignedArmed = nil, false

local function CheckFlag100(_, time)
  pcall(ApplyRecoveryCase)
  pcall(BanklerSync, trigger.misc.getUserFlag(100))

  local current = trigger.misc.getUserFlag(100)

  if current ~= TRT.CaseSync.lastFlag then

    TRT.CaseSync.lastFlag = current

    if current == 1 or current == 2 or current == 3 then

      local offset = TRT.CaseSync.HoldOffset(current) or TRT.CaseSync.OFFSET[current]   -- v1.1.0
      alignedOffset, alignedArmed = offset, armed()

      if DEBUG_LOG_CASE_SYNC then
        env.info(string.format("AIRBOSS CaseSync | flag 100 -> CASE %d (offset %d deg) -- rebuilding recovery window", current, offset))
      end

      TRT.CaseSync.tRebuild = timer.getTime()   -- v1.0.5
      TRT.Airboss:DeleteAllRecoveryWindows()
      TRT.Airboss:AddRecoveryWindow(nil, WINDOW_STOP, current, offset)

    else
      -- Flag set to something other than 1/2/3 (e.g. 0 at mission start
      -- before you've picked a case yet). Log it, don't guess -- same
      -- philosophy as DEBUG_LOG_UNATTRIBUTED_DEATHS in Core_Scoring.lua.
      env.info(string.format("AIRBOSS CaseSync | flag 100 changed to %s -- not a valid case (1/2/3), ignoring", tostring(current)))
    end

  end

  -- v1.1.0: keep a fixed hold radial on the live carrier heading (see header)
  if TRT.HOLD_RADIAL_MAG and (current == 2 or current == 3) and alignedOffset and not alignedArmed then
    local want = TRT.CaseSync.HoldOffset(current)
    local nowArmed = armed()
    if want and (nowArmed or math.abs(norm180(want - alignedOffset)) > (TRT.HOLD_RADIAL_TOL or 2)) then
      env.info(string.format("AIRBOSS CaseSync | hold R-%03d: offset %d -> %d deg%s -- rebuilding recovery window",
        TRT.HOLD_RADIAL_MAG, alignedOffset, want, nowArmed and " (recovery armed, final)" or ""))
      TRT.CaseSync.tRebuild = timer.getTime()
      TRT.Airboss:DeleteAllRecoveryWindows()
      TRT.Airboss:AddRecoveryWindow(nil, WINDOW_STOP, current, want)
      alignedOffset, alignedArmed = want, nowArmed
    elseif nowArmed then
      alignedArmed = true
      env.info(string.format("AIRBOSS CaseSync | hold R-%03d: recovery armed, offset %d deg kept", TRT.HOLD_RADIAL_MAG, alignedOffset))
    end
  end

  return time + 5 -- reschedule, 5s poll interval
end

timer.scheduleFunction(CheckFlag100, nil, timer.getTime() + 5)

if type(_G.SetSuperCarrier) ~= "function" then   -- v1.0.8
  function _G.SetSuperCarrier(enabled) _G.carrierTCN = enabled and "72X" or "74X" end
end
env.info("Airboss_CaseSync | v1.1.0 | listening on flag 100" .. (TRT.HOLD_RADIAL_MAG and string.format(" | hold R-%03d", TRT.HOLD_RADIAL_MAG) or ""))
