-- CAS_Pack | v1.3.1
-- v1.3.1 (2026-11-04 23:00, decision Onur): pool sets B / C of Pointer, Eyeball and Darknight w = 1 (DCS audit passed:
--         Tasking_Pick site check OK, JTAC post / MQ-9 LOS OK; Pointer B / C after the move) - A / B / C equal odds.
-- v1.3.0 (2026-11-04, roster P3, decisions Onur 12:41): J3 AXEMAN 11 (JTAC-8, BASE YE55 insurgents, IP JACKAL,
--         COMM1 10 / alternate 13) and J4 DARKNIGHT 11 (ground team JTAC-4, MQ-9 FAC-1 = designator, SAM BV53,
--         IP COBRA, COMM1 12 / alternate 14). jtacs[k].designator = unit that lases and observes (JTAC_Controller
--         >= v0.16.0); no op table: the JTAC stays at its ME position. order = the roster; CD.tasked = the
--         first two (Pointer 11, Eyeball 11) until P4 picks two at random.
-- v1.2.1 (2026-11-04, roster P2): jtacs[k].cn = clip name of the JTAC in OVERLORD / pilot clips (ovl_contact_<cn>_b,
--         p_ovl_off_<cn>_a); jtacs[k].injects = true: the abort / rearm / MANPADS injects belong to this JTAC
--         (Comms_Director >= v1.10.0). order = the roster (index n -> CD phase JTAC<n>).
-- v1.2.0 (2026-11-04, effects-based tasking): objective per pool entry ({ n = units to destroy, types = which ones
--         count }, JTAC_Controller >= v0.15.0) and per JTAC (default = entry A); loadout (Tasking_Pick weapons
--         check: the picked objectives together <= MAV + LGB - 2, one spare per type).
-- v1.1.0 (2026-11-04): target pool per JTAC (jtacs[k].pool, read by Tasking_Pick.lua at load). targets / ord /
--         tgt_fallback below are the defaults (= pool entry A); Tasking_Pick overwrites them with the pick.
-- Tasking pack of CAS-1: geography and comm plan in ONE place (decision Onur 2026-11-04: the pack holds what /
-- where / who / which frequency; behaviour - scenario weights, timers, scoring - stays in each module's CFG).
-- Read by Comms_Director (>= v1.9.0), JTAC_Controller (>= v0.14.0), Flight_Timeline (>= v1.3.1), and offline by
-- tools/make_kneeboard.py, tools/check_pack.py and tools/scenario_test (dcslua.parse: keep this file a plain
-- data table - no code, no functions, no locals).
-- Load: before every reader (Do Script File right after mist in the MOOSE trigger, so that a later target-pool
-- pick can run before Skynet init).
-- Voiced values: call signs, button numbers, frequencies, CP / IP names and mission numbers are also spoken in
-- the pre-rendered clips (Sounds/CAS1, tts/clips.csv). Changing one here needs the clips re-rendered;
-- tools/check_pack.py compares the voiced values with tts/pack_voiced.json (the values the clips were made with).
-- ME coupling (checked by tools/check_pack.py against src/mission): hero / group / unit names exist, cp.wp_name
-- is a CAS-1 route point at cp.pos, every btn / freq pair is a Player_01 COMM1 preset.
-- Positions: DCS world x = north (ME x), z = east (ME y), metres.

CAS_PACK = {
    version = "1.3.1",

    hero    = "Player_01",       -- unit
    group   = "CAS-1",           -- hero's ME group (route = ATO)
    cs      = "HORNET 51",
    carrier = "CVN",
    tanker  = "TANKER-1-1",      -- KC-130, Texaco 11

    cp = { name = "CP TIGER", wp_name = "Contact JTAC", pos = { x = 73640, z = -39914 } },
    hard_deck_ft = 20000,
    hold_angels  = 22,           -- scenario B hold at the CP
    loadout      = { MAV = 2, LGB = 4 },   -- hero's A/G weapons (AGM-65E, GBU-12); tools/check_pack.py checks the pylons

    -- Player_01 COMM1 presets (ch = Comms_Director voice channel of that agency)
    nets = {
        TOWER    = { btn = 1,  freq = "262.00" },                     -- carrier nets: shown on the COMM card only
        DEP      = { btn = 2,  freq = "269.00", ch = "DEPARTURE" },
        STRIKE   = { btn = 3,  freq = "265.00", ch = "STRIKE" },
        OVL      = { btn = 6,  freq = "251.10", ch = "OVERLORD", comm2 = 1 },   -- also COMM2 btn 1
        TKR      = { btn = 7,  freq = "252.10", ch = "TEXACO" },
        ARCO     = { btn = 8,  freq = "252.30" },                     -- recovery tanker TANKER-3
        APPROACH = { btn = 15, freq = "263.00" },
        MARSHAL  = { btn = 16, freq = "261.00" },
    },

    jtacs = {
        J1 = {
            cs = "POINTER 11", disp = "Pointer 11", short = "Pointer",
            group = "JTAC-1",
            btn = 4, freq = "333.30", ch = "POINTER",
            alt = { btn = 9, freq = "255.00" },      -- lost comms "tech": radio failure on primary
            vp = "pj", ck = "ptr", cn = "pointer",   -- clip prefixes: JTAC_Controller / Comms_Director / OVERLORD + pilot
            msn = "4101",
            area = "BV 62",                          -- briefed target area (kneeboard); the target comes with the 9-line
            targets = { "SAM BV51 (SA-13)-1" },
            -- Target pool (Tasking_Pick.lua). Weapons budget: Pointer entries 2 units (2x AGM-65E), Eyeball 4
            -- (4x GBU-12). w = weight of the random pick (v1.3.1: A / B / C 1 each after the DCS audit; forced picks
            -- for tests: ME flags 217 / 219 / 223 / 224 = entry index).
            pool = {
                { id = "A", name = "SHORAD site",   targets = { "SAM BV51 (SA-13)-1" },
                  statics = { "SAM BV51 (SA-13)-1-Camouflage-1" }, w = 1,
                  objective = { n = 1, types = { "Strela-10M3" } } },
                { id = "B", name = "armor section", targets = { "CAS J1-B (Armor)-1" },   w = 1,
                  objective = { n = 1, types = { "T-72B" } } },
                { id = "C", name = "SP artillery section", targets = { "CAS J1-C (Battery)-1" }, w = 1,
                  objective = { n = 1, types = { "SAU Gvozdika" } } },
            },
            ip = { name = "LYNX", mgrs = "37S BV 4071 2864" },
            egress = "north to TIGER",
            mark = { kind = "laser", code = 1688 },
            ord = "one AGM-65E",                     -- fallback only (v1.2.0: the JTAC picks the weapon by target type)
            objective = { n = 1, types = { "Strela-10M3" } },   -- default = pool entry A
            friendly_ofs = { brg = 200, m = 1200 },  -- Bravo 2-1 from the target, true deg / m
            op = { auto = true, brg = 238, m = 2500, dmin = 1500, dmax = 4000, step = 150 },   -- JTAC post search
        },
        J2 = {
            cs = "EYEBALL 11", disp = "Eyeball 11", short = "Eyeball",
            group = "JTAC-2",
            btn = 5, freq = "333.40", ch = "EYEBALL",
            alt = { btn = 11, freq = "259.00" },
            vp = "ej", ck = "eye", cn = "eyeball",
            injects = true,                          -- abort / rearm / MANPADS injects (Comms_Director)
            msn = "4102",
            area = "YE 53",
            targets = { "SAM YE53 (SA-8)-1" },
            pool = {
                { id = "A", name = "SA-8 battery",  targets = { "SAM YE53 (SA-8)-1" },
                  statics = { "SAM YE53 (Camouflage)-1", "SAM YE53 (Camouflage)-2-1", "SAM YE53 (Camouflage)-3" }, w = 1,   -- static UNIT names
                  objective = { n = 2, types = { "Osa 9A33 ln" } } },
                { id = "B", name = "armor platoon", targets = { "CAS J2-B (Armor)-1" },   w = 1,
                  objective = { n = 2, types = { "T-72B" } } },
                { id = "C", name = "SP artillery battery", targets = { "CAS J2-C (Battery)-1" }, w = 1,
                  objective = { n = 2, types = { "SAU Gvozdika" } } },
            },
            tgt_fallback = { x = 59271, z = -1176 }, -- Comms_Director: TIC geometry when the group is not readable
            ip = { name = "PUMA", mgrs = "36S YE 4714 5182" },
            egress = "northwest, feet wet",
            mark = { kind = "laser", code = 1688 },
            ord = "one GBU-12",
            objective = { n = 2, types = { "Osa 9A33 ln" } },
            friendly_ofs = { brg = 200, m = 1000 },
            op = { auto = true, brg = 250, m = 2500, dmin = 1500, dmax = 4000, step = 150 },
        },
        J3 = {                                       -- v1.3.0 (P3)
            cs = "AXEMAN 11", disp = "Axeman 11", short = "Axeman",
            group = "JTAC-8",
            btn = 10, freq = "333.50", ch = "AXEMAN",
            alt = { btn = 13, freq = "256.00" },
            vp = "aj", ck = "axe", cn = "axeman",
            msn = "4103",
            area = "YE 55",
            targets = { "BASE YE55 (Insurgent)-1" },     -- SAM YE55 (SA-8)-1 sits next to it (threat remark)
            pool = {
                { id = "A", name = "insurgent technicals", targets = { "BASE YE55 (Insurgent)-1" }, w = 1,
                  objective = { n = 2, types = { "HL_DSHK" } } },
            },
            ip = { name = "JACKAL", mgrs = "36S YE 3968 6905" },
            egress = "northwest, feet wet",
            mark = { kind = "laser", code = 1688 },
            ord = "one GBU-12",
            objective = { n = 2, types = { "HL_DSHK" } },
            friendly_ofs = { brg = 200, m = 1000 },
            op = { auto = true, brg = 250, m = 2500, dmin = 1500, dmax = 4000, step = 150 },
        },
        J4 = {
            cs = "DARKNIGHT 11", disp = "Darknight 11", short = "Darknight",
            group = "JTAC-4",                            -- ground team (tools/add_roster_jtacs.py)
            designator = "FAC-1-1",                      -- MQ-9 Reaper: lases and observes (no terrain masking)
            btn = 12, freq = "333.10", ch = "DARKNIGHT",
            alt = { btn = 14, freq = "258.00" },
            vp = "dj", ck = "dkn", cn = "darknight",
            msn = "4104",
            area = "BV 53",
            targets = { "SAM BV53 (SA-13)-1" },
            pool = {
                { id = "A", name = "SHORAD site",   targets = { "SAM BV53 (SA-13)-1" }, w = 1,
                  objective = { n = 1, types = { "Strela-10M3" } } },
                { id = "B", name = "armor section", targets = { "CAS J4-B (Armor)-1" },  w = 1,
                  objective = { n = 1, types = { "T-72B" } } },
                { id = "C", name = "supply trucks", targets = { "CAS J4-C (Trucks)-1" }, w = 1,
                  objective = { n = 1, types = { "Ural-375" } } },
            },
            ip = { name = "COBRA", mgrs = "37S BV 5620 6202" },
            egress = "west to TIGER",
            mark = { kind = "laser", code = 1688 },
            ord = "one AGM-65E",
            objective = { n = 1, types = { "Strela-10M3" } },
            friendly_ofs = { brg = 200, m = 1200 },
            -- no op: the ground team stays at its ME position (the MQ-9 observes and lases)
        },
    },
    order = { "J1", "J2", "J3", "J4" },   -- roster (index n -> CD phase JTAC<n>); CD.tasked = the first two (P2), fragged order

    friendly = { name = "Bravo 2-1", cs = "BRAVO 2-1",
                 units = { "M-2 Bradley", "M-2 Bradley", "Soldier M4", "Soldier M4", "Soldier M4" } },

    -- Abort code: challenge passed at check-in; reply = AUTH row of the challenge's first letter (kneeboard 06 AUTH,
    -- tools/make_kneeboard.py prints this table; seed 20261029 generated it).
    abort = {
        challenge = "BR",
        auth = {
            A = "BSIAZTXKDGPQVEMCNWFJYLUHOR", B = "AXYSFZJLHPVECBNDRQTWMOGIUK", C = "GDSIVRKUXELOCFHWJQBZYANMPT",
            D = "TVYMLCBUWEHRDGKAFJQZIXSNPO", E = "GWFIYONQJDATVUZCLMSBKPHEXR", F = "YBOLUVNIPHTKAFQDSRXMEGJZCW",
            G = "BFMUPEQNRLKSDZXAGVOITCHJWY", H = "MLARHQFGXKSZYIWVPJEONBCTUD", I = "LGOXJHDCEWMSYNTFARVIKBUPQZ",
            J = "MHFEZPQKCXVJRLOIYUWBNAGTDS", K = "EUQKCOBNGAYHLPTMFRWXJIZSVD", L = "THVCREZAGYBFQXIUNLOPMJDWSK",
            M = "PVJCEWGTSYHIMZONLDRQKAXUBF", N = "ATWGDVJHPBLOXMICSNUEFQKYZR", O = "UABNFJQGLPIEZTXOMVCSKYDRHW",
            P = "XMSTRKLFOGVBQWZEDUPJACHIYN", Q = "TULZBGPAXRHWFYJKSOQENVDIMC", R = "CSUIOLMHNFXQGDWZPAJETVBYRK",
            S = "FDNESUCBQIXZMVJKTWLRYHGOAP", T = "HVAJXUYTEKLWGISDOFMPQRZCBN", U = "TZGCEPRHIVAQXBFSYUJDWMLKON",
            V = "QXCGHNDVZTOJAUESBYMFPWRLIK", W = "FIZAVYBLSJQHEXMKWNPOTRUDCG", X = "XCSJZBDMTHQEAUFLRGPOINWKYV",
            Y = "MNFYBDGIUHLJZSKRPQOWCATXVE", Z = "MBSLRJTUINYWQDCXPVHEZFOKAG",
        },
    },
}
