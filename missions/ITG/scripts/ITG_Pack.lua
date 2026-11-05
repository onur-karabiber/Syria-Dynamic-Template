-- ITG_Pack | v0.1.0
--[[
  Into The Grey mission pack (P1, 2026-11-05; plan: project doc claude/itg-s2s-migration-plan-2026-11-05.md).
  The only place where ITG differs from the shared template modules: names, frequencies and the hold fix.
  Behaviour stays in each module. Load right after mist in the MOOSE trigger, before every shared module.

  Sets (read by the shared modules; nil in SDT / SEA2STEEL = their defaults):
    TRT.PLAYER_NAME      hero unit                                  (Core_Scoring and the rest)
    TRT.HERO_GROUP       hero ME group "HORNET-5"                   (PlaneCaptain_Carrier >= v1.3.3)
    TRT.HOLD_RADIAL_MAG  CASE II/III hold radial, magnetic: 195     (Airboss_CaseSync >= v1.1.0, live offset)
    TRT.CFG_OVERRIDE     per-module CFG keys                        (CV_Comms >= v1.8.0, AAR_Monitor >= v1.1.6)

  ITG comm plan (Player_01, ME presets; CV button plan = SEA2STEEL, so CV_Comms' voiced "button N" fits):
    COMM1  1 TOWER 262.00 | 2 DEPARTURE 269.00 | 3 WASHINGTON 127.60 (CVN native ATC) | 6 OVERLORD 251.10
           7 MAGIC 251.20 | 8 ARCO 51 252.50 | 10 STROKE 3 266.60 | 13 TEXACO 11 252.10 | 15 APPROACH 263.00
           16 MARSHAL 261.00
    COMM2  1 HORNET 5 intra-flight 305.00
  Tankers: Texaco 11 = TANKER-1-1 (KC-135 MPRS, 252.10, 21Y); Arco 51 = ARCO-5-1 (S-3B, 252.50, 25Y, recovery,
  late activated by the ME trigger "Recovery Tanker Activation").
  The voiced CV clips name "Arco three one": those two clips are dropped for ITG (text only) until ITG clips are
  rendered (P3).
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.ITG_PACK then env.info("ITG_Pack | already loaded, second copy ignored") return end

TRT.MISSION         = "ITG"
TRT.PLAYER_NAME     = TRT.PLAYER_NAME or "Player_01"
TRT.HERO_GROUP      = "HORNET-5"
TRT.HOLD_RADIAL_MAG = 195          -- Onur 2026-11-05: R195 +/-5
TRT.HOLD_RADIAL_TOL = 2

TRT.CFG_OVERRIDE = TRT.CFG_OVERRIDE or {}
TRT.CFG_OVERRIDE.CV_Comms = {
    RTANKER = { unit = "ARCO-5-1", cs = "Arco 51", btn = 8, freq = "252.50 AM", tacan = "25Y",
                ABOVE_TANK_LB = 1000, MIN_GIVE_LB = 500, ABOVE_TRAP_LB = 500 },
    AUDIO   = { a_arco_a = false, d_arco_bears = false },   -- "Arco three one ..." clips
}
TRT.CFG_OVERRIDE.AAR_Monitor = {
    TANKERS = { "TANKER-1-1", { unit = "ARCO-5-1", kind = "RECOVERY" } },
}

TRT.ITG_PACK = {
    version = "0.1.0",
    hero    = { unit = "Player_01", wingman = "Player_02", group = "HORNET-5", cs = "HORNET 51", modex = "467" },
    nets    = {
        TOWER      = { btn = 1,  mhz = 262.00 },
        DEPARTURE  = { btn = 2,  mhz = 269.00 },
        WASHINGTON = { btn = 3,  mhz = 127.60 },
        OVERLORD   = { btn = 6,  mhz = 251.10, unit = "OVERLORD-1-1", cs = "Overlord 11" },
        MAGIC      = { btn = 7,  mhz = 251.20, unit = "MAGIC-2-1",    cs = "Magic 21" },
        ARCO       = { btn = 8,  mhz = 252.50, unit = "ARCO-5-1",     cs = "Arco 51", tacan = "25Y" },
        STROKE     = { btn = 10, mhz = 266.60, cs = "Stroke 3" },
        TEXACO     = { btn = 13, mhz = 252.10, unit = "TANKER-1-1",   cs = "Texaco 11", tacan = "21Y" },
        APPROACH   = { btn = 15, mhz = 263.00 },
        MARSHAL    = { btn = 16, mhz = 261.00 },
        FLIGHT     = { radio = 2, btn = 1, mhz = 305.00 },
    },
    targets = { "STRIKE1_TRG1", "STRIKE1_TRG2" },
}

env.info(string.format("ITG_Pack | v%s | hero %s / %s | hold R-%03d", TRT.ITG_PACK.version, TRT.PLAYER_NAME,
    TRT.HERO_GROUP, TRT.HOLD_RADIAL_MAG))
