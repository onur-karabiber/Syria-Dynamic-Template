-- Airboss_Start.lua | v1.0.5
-- TRT Syria Recovery Framework - MOOSE AIRBOSS bootstrap
-- Carrier unit (ME): "CVN"
-- Recovery ops: CASE II
--
-- LOAD ORDER: after MOOSE / mist / Skynet, before the four TRT scoring scripts.
-- Loaded via: ME "Do Script File" (ResKey_Action_301), embedded by build.py.
--
-- v1.0.5: TACAN / ICLS morse ident CVN -> WSH, same as the ME beacon on the CVN
--   unit (ActivateBeacon 72X "WSH"). Before, two 72X beacons with different
--   idents were active and the audible ident depended on which one ran last.
-- v1.0.4: FIX Moose bug in AIRBOSS:_GetOnboardNumbers (operator precedence:
--   `playeronly and skill=="Client" or skill=="Player"`). For a unit with skill
--   "Player" (Player_01) it returned the modex STRING instead of the table, so
--   flight.onboardnumbers = "467". Effects seen in dcs.log 2026-10-22:
--   _IsOnboard -> pairs(string) error in _DirtyUp (AIRBOSS step froze at Dirty Up:
--   no needles calls, no groove / LSO calls, pass INVALID) and _PrintQueue
--   format(nil) errors in _CheckQueue (element.onboard = nil). Instance override
--   below with the parentheses fixed.
-- v1.0.3: v1.0.2 replaced. Stack 1 now holds at ANGELS 10 (TRT.HOLD_ANGELS0)
--   and keeps NATOPS distance = angels + 15 -> 25 DME. Matches the TRT chart
--   (R-196 / 25 DME / angels 10) and Recovery_Approach's IF-fix altitude window.
-- v1.0.2 (superseded): CASE II/III marshal fix distance = angels + TRT.HOLD_DME_BASE (19) ->
--   stack 1 / angels 6 holds at 25 DME (TRT chart: R-196 / 25 DME), instead of
--   AIRBOSS's NATOPS angels + 15 (21 DME). Instance override of
--   _GetMarshalAltitude below; Moose file untouched. Radial comes from
--   Airboss_CaseSync OFFSET (CASE II 21, CASE III 30 -> R-196).
-- v1.0.1: radios moved to the CV button plan (all AM, CV_Comms.lua):
--   Marshal 305 FM -> 261.00 AM (btn 16; 305 AM is the flight freq of 24 groups)
--   LSO     264 FM -> 262.00 AM (btn 1, CASE I/II). CV_Comms moves the LSO radio
--   to 263.00 AM (APPROACH, btn 15) for CASE III at the Marshal reply.
--
-- NOTE: this script owns the AIRBOSS *pattern/LSO simulation* (marshal, ICLS,
-- TACAN, LSO grading). It does NOT set ME flag 100. Flag 100 remains the
-- source of truth for TRT.Core_Scoring's case-dependent scoring logic.
-- SetRecoveryCase below is hardcoded to 2 to match this request. If flag 100
-- ever gets flipped to a different case at runtime, this object will NOT
-- follow it automatically -- see the sync note at the bottom of this file.

TRT = TRT or {}

-- Carrier object. Alias kept identical to unit name; change alias if you want
-- a different F10 menu label than the ME unit name.
TRT.Airboss = AIRBOSS:New("CVN", "CVN")

-- TACAN 72X (channel, mode, morse ident). Ident "WSH" = ME beacon on the CVN
-- unit (ActivateBeacon 72X WSH); keep both identical (v1.0.5).
TRT.Airboss:SetTACAN(72, "X", "WSH")

-- ICLS channel 12, ident WSH (v1.0.5).
TRT.Airboss:SetICLS(12, "WSH")

-- LSO / Marshal radio -- CV button plan (see CV_Comms.lua header). AM to match
-- the Player_01 COMM1 presets (ME presets are AM).
TRT.Airboss:SetLSORadio(262, "AM")
TRT.Airboss:SetMarshalRadio(261, "AM")

-- Default recovery case = II. This governs the Marshal holding geometry
-- (Case III-style stack collapsing into the Case I pattern at Initial) and
-- the ICLS "follow the needles" cueing behavior in the groove.
TRT.Airboss:SetRecoveryCase(2)

-- Carrier Controlled Area, NM. 50 is the MOOSE default; adjust if your
-- Syria template places bandit/CAP activity closer than that.
TRT.Airboss:SetCarrierControlledArea(50)

-- Recovery window: opens immediately (nil start = ASAP), Case II, 0 deg
-- holding offset (adjust to +-15 / +-30 if you want an offset holding
-- pattern). Stop time is pushed out 3 days so the window doesn't silently
-- expire mid-training-session -- this is a sandbox template, not a scripted
-- strike package with a fixed recovery slot.
TRT.Airboss:AddRecoveryWindow(nil, "23:59:00+3", 2, 0)

-- Single-carrier menu simplification (one carrier in this template).
TRT.Airboss:SetMenuSingleCarrier()

-- SOUND FILES. Root folder "Sounds/" is a NEW top-level folder embedded at
-- the .miz's root (sibling of l10n/, mission, options, warehouses) -- see
-- delivery notes for why it must NOT go under l10n/DEFAULT/.
--
-- SetSoundfilesFolder() sets the GENERAL fallback folder (self.soundfolder)
-- used for any radio call whose filename isn't LSO-*/MARSHAL-* prefixed.
-- SetVoiceOversLSOByRaynor()/SetVoiceOversMarshalByRaynor() additionally
-- redirect the LSO-*/MARSHAL-* lookups (self.soundfolderLSO/soundfolderMSH)
-- to their OWN folders -- confirmed from source (AIRBOSS:_RadioFilename,
-- Airboss.lua) these do NOT fall back to the general folder once the pack
-- setter is called WITH a folder argument, so this is not optional: the
-- actual Raynor LSO/Marshal .ogg files live in their own Soundpack
-- sub-folders, not in "Airboss Soundfiles" itself.
--
-- Raynor is used for both here because it's the class's own built-in
-- default (New() already calls both setters with no folder arg). Swap to
-- SetVoiceOversLSOByFF(...) and/or SetVoiceOversMarshalByGabriella(...) /
-- SetVoiceOversMarshalByFF(...) -- pointed at the matching Soundpack
-- folder -- if you want a different combo. Only embed the Soundpack
-- folders you actually reference below; the unused ones are pure .miz
-- bloat (same reasoning as dropping 12NMb_Zone).
TRT.Airboss:SetSoundfilesFolder("Sounds/AIRBOSS/Airboss Soundfiles/")
TRT.Airboss:SetVoiceOversLSOByRaynor("Sounds/AIRBOSS/Airboss Soundpack LSO Raynor/")
TRT.Airboss:SetVoiceOversMarshalByRaynor("Sounds/AIRBOSS/Airboss Soundpack Marshal Raynor/")

-- CASE II/III marshal stack (v1.0.3). AIRBOSS hard-codes stack 1 = angels 6,
-- Dist = (stack-1) + 6 + 15 NM. TRT: stack 1 = angels 10 (TRT.HOLD_ANGELS0),
-- distance stays NATOPS angels + 15 (TRT.HOLD_DME_BASE) -> 25 DME, TRT chart.
-- Copy of AIRBOSS:_GetMarshalAltitude (Moose 2026-06-14) with angels0 replaced;
-- CASE I path delegated to the original. Re-check against the Moose source
-- when Moose is updated.
TRT.HOLD_ANGELS0  = 10
TRT.HOLD_DME_BASE = 15
do
  local orig = TRT.Airboss._GetMarshalAltitude
  TRT.Airboss._GetMarshalAltitude = function(self, stack, case)
    case = case or self.case
    if stack <= 0 or case == 1 then return orig(self, stack, case) end
    local Carrier = self:GetCoordinate()
    local nstack  = stack - 1
    local angels0 = TRT.HOLD_ANGELS0
    local Dist    = UTILS.NMToMeters(nstack + angels0 + TRT.HOLD_DME_BASE)
    local radial  = self:GetRadial(case, false, true)
    local l       = UTILS.NMToMeters(10)
    local p1 = Carrier:Translate(Dist + l, radial)
    local p2 = Carrier:Translate(Dist, radial)
    local altitude = UTILS.FeetToMeters((nstack + angels0) * 1000)
    p1:SetAltitude(altitude, true)
    p2:SetAltitude(altitude, true)
    return altitude, p1, p2
  end
end

-- Moose bug fix (v1.0.4): copy of AIRBOSS:_GetOnboardNumbers (Moose 2026-06-14)
-- with `playeronly and (skill=="Client" or skill=="Player")`. Must be installed
-- before any flight group is created (i.e. before Start / player birth).
TRT.Airboss._GetOnboardNumbers = function(self, group, playeronly)
  local template = group:GetTemplate()
  local numbers = {}
  if template then
    for _, unit in pairs(template.units) do
      local n = tostring(unit.onboard_num)
      local skill = unit.skill or "Unknown"
      if playeronly and (skill == "Client" or skill == "Player") then
        return n
      end
      numbers[unit.name] = n
    end
  else
    if playeronly then
      return 101
    else
      for i, _unit in pairs(group:GetUnits()) do
        numbers[_unit:GetName()] = 100 + i
      end
    end
  end
  return numbers
end

-- Start the FSM.
TRT.Airboss:Start()

env.info(string.format("Airboss_Start | v1.0.5 | TACAN/ICLS WSH | onboard-number fix | HOLD stack1 angels 10 / 25 DME | CVN | CASE %d | TACAN 72X | ICLS 12 | MARSHAL 261.00 AM | LSO 262.00 AM", 2))

-- ============================================================================
-- SYNC NOTE: Airboss_CaseSync.lua (load AFTER this file) listens on flag 100
-- and rebuilds this object's recovery window whenever it changes, so this
-- hardcoded SetRecoveryCase(2) above only matters as the INITIAL case. If
-- Airboss_CaseSync.lua is not loaded, flag 100 changes mid-mission will NOT
-- propagate here and AIRBOSS's pilot-facing behavior will silently disagree
-- with whatever Core_Scoring.lua is grading against.
-- ============================================================================
