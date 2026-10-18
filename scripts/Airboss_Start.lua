-- Airboss_Start.lua | v1.0.0
-- TRT Syria Recovery Framework - MOOSE AIRBOSS bootstrap
-- Carrier unit (ME): "CVN"
-- Recovery ops: CASE II
--
-- LOAD ORDER: after MOOSE / mist / Skynet, before the four TRT scoring scripts.
-- Loaded via: assert(loadfile("<path>/Airboss_Start.lua"))()
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

-- TACAN 72X (channel, mode, morse ident).
-- Morse ident "CVN" is a placeholder derived from the carrier unit name --
-- swap it for whatever 3-letter ident you actually want broadcast.
TRT.Airboss:SetTACAN(72, "X", "CVN")

-- ICLS channel 12, same placeholder morse ident.
TRT.Airboss:SetICLS(12, "CVN")

-- LSO / Marshal radio -- MOOSE defaults (264 FM / 305 FM). Left explicit so
-- they're not buried in AIRBOSS's internal defaults; change if you need
-- specific frequencies for SRS/radio relay routing.
TRT.Airboss:SetLSORadio(264, "FM")
TRT.Airboss:SetMarshalRadio(305, "FM")

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

-- Start the FSM.
TRT.Airboss:Start()

env.info(string.format("AIRBOSS | CVN | CASE %d | TACAN 72X | ICLS 12 initialized", 2))

-- ============================================================================
-- SYNC NOTE: Airboss_CaseSync.lua (load AFTER this file) listens on flag 100
-- and rebuilds this object's recovery window whenever it changes, so this
-- hardcoded SetRecoveryCase(2) above only matters as the INITIAL case. If
-- Airboss_CaseSync.lua is not loaded, flag 100 changes mid-mission will NOT
-- propagate here and AIRBOSS's pilot-facing behavior will silently disagree
-- with whatever Core_Scoring.lua is grading against.
-- ============================================================================
