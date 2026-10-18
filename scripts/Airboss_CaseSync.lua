-- Airboss_CaseSync.lua | v1.0.0
-- TRT Syria Recovery Framework - syncs TRT.Airboss recovery case to ME flag 100
--
-- LOAD ORDER: after Airboss_Start.lua (needs TRT.Airboss to exist already).
-- Loaded via: assert(loadfile("<path>/Airboss_CaseSync.lua"))()
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
-- polled on a timer -- same shape as the Radial_Flag_v1.2.0 /
-- Distance_Flag_v3.lua polling pattern, but structurally immune to their
-- resync bug class: those compared a DERIVED counter against the actual
-- sector and could drift apart; this compares the ME flag's raw value
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
  [2] = 30, -- Case II: FB 346 / Hold Fix R-195 @ 25 DME, port-aft. See note above.
  [3] = 0, -- Case III offset NOT SPECIFIED YET. Fill in before flag 100 is
           -- ever set to 3, or Case III will hold dead astern (0 offset)
           -- instead of wherever you actually want it.
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
TRT.CaseSync.lastFlag = trigger.misc.getUserFlag(100)

local function CheckFlag100(_, time)

  local current = trigger.misc.getUserFlag(100)

  if current ~= TRT.CaseSync.lastFlag then

    TRT.CaseSync.lastFlag = current

    if current == 1 or current == 2 or current == 3 then

      local offset = TRT.CaseSync.OFFSET[current]

      if DEBUG_LOG_CASE_SYNC then
        env.info(string.format("AIRBOSS CaseSync | flag 100 -> CASE %d (offset %d deg) -- rebuilding recovery window", current, offset))
      end

      TRT.Airboss:DeleteAllRecoveryWindows()
      TRT.Airboss:AddRecoveryWindow(nil, WINDOW_STOP, current, offset)

    else
      -- Flag set to something other than 1/2/3 (e.g. 0 at mission start
      -- before you've picked a case yet). Log it, don't guess -- same
      -- philosophy as DEBUG_LOG_UNATTRIBUTED_DEATHS in Core_Scoring.lua.
      env.info(string.format("AIRBOSS CaseSync | flag 100 changed to %s -- not a valid case (1/2/3), ignoring", tostring(current)))
    end

  end

  return time + 5 -- reschedule, 5s poll interval
end

timer.scheduleFunction(CheckFlag100, nil, timer.getTime() + 5)

env.info("AIRBOSS CaseSync | listening on flag 100")
