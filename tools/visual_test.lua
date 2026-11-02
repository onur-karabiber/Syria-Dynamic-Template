-- Visual_Test | v1.0.0
-- Injected by tools/make_test_variant.py (--start VIS) as a "triggerOnce" DO SCRIPT. NOT part of the template
-- build. Draws the new pictures with sample values so their look, size and layering can be checked in DCS
-- (Onur 2026-11-02): scoreboard (Score_Display v0.3.0 art) and the report card (FlightReport v1.4.1 layers).
--   T+30 s  scoreboard  42 / +5
--   T+38 s  scoreboard  27 / -15
--   T+46 s  scoreboard 147 / +120
--   T+54 s  report card A (SAT, long LSO grade, ROE stamp 1, 5 badges)
-- F10 > Other > VISUAL TEST: cards A / B (UNSAT, CUT, 3-row long grade, stamp 3, 8 badges) / C (SIERRA HOTEL,
-- field divert, 1 badge), the real card from the current data (Flight_Report), the three scoreboards, clear.
-- Every call is logged as "[VTEST] ..." (layer count, failed pictures) for the dcs.log check.
do
    local TRT = _G.TRT or {}
    local FR = TRT.FlightReport
    local LAY = (FR and FR.CFG and FR.CFG.LAY) or { dur = 90, h = 1, v = 1, size = 82, units = 1 }
    local FIELDS = (FR and FR.CFG and FR.CFG.FIELDS) or { tot = 5, earn = 4, pen = 4, loss = 4, lsopts = 3,
        wire = 1, tgr = 4, bk = 2, bkmax = 2, bkpct = 3 }
    local DIR, DUR, LX_ROWS, LX_COLS, BADGE_SLOTS = "FlightReport/", 60, 3, 34, 8
    local LX = {}
    for c in ("ABCDEFGHIKLMNOPRSTUVWXY"):gmatch(".") do LX[c] = c end
    LX["("], LX[")"], LX["_"], LX["/"], LX["\\"], LX["-"], LX["."] = "lp", "rp", "us", "sl", "bs", "dash", "dot"

    local function log(s) env.info("[VTEST] " .. s) end
    log("Visual_Test v1.0.0 loaded; Flight_Report " .. (FR and tostring(FR.version) or "MISSING")
        .. ", Score_Display " .. ((TRT.ScoreDisplay and TRT.ScoreDisplay.version) and tostring(TRT.ScoreDisplay.version)
        or (TRT.ScoreDisplay and "present" or "MISSING")))

    local function pic(file, clear, dur)
        local code = string.format('a_out_picture_s(%q, %q, %d, %s, 0, "%d", "%d", %d, "%d")', "blue", file,
            dur or DUR, clear and "true" or "false", LAY.h, LAY.v, LAY.size, LAY.units)
        local ok, res, okd = pcall(net.dostring_in, "mission", code)
        if not ok or okd == false then log("picture failed: " .. tostring(res) .. " | " .. code); return false end
        return true
    end

    local function field(f, name, str)
        local slots = FIELDS[name] or 4
        if #str > slots then str = str:sub(#str - slots + 1) end
        for i = 1, #str do
            local ch = str:sub(i, i)
            local g = (ch == "+" and "p") or (ch == "-" and "m") or (ch == "." and "d") or ch
            f[#f + 1] = string.format("%s_%s_%d.png", name, g, slots - #str + i - 1)
        end
    end

    local function longGrade(f, text)
        local rows, cur = {}, ""
        for word in text:upper():gmatch("%S+") do
            local tok = word
            while #tok > LX_COLS do
                if cur ~= "" then rows[#rows + 1] = cur; cur = "" end
                rows[#rows + 1] = tok:sub(1, LX_COLS); tok = tok:sub(LX_COLS + 1)
            end
            if cur == "" then cur = tok
            elseif #cur + 1 + #tok <= LX_COLS then cur = cur .. " " .. tok
            else rows[#rows + 1] = cur; cur = tok end
        end
        if cur ~= "" then rows[#rows + 1] = cur end
        for r = 1, math.min(#rows, LX_ROWS) do
            for c = 1, #rows[r] do
                local g = LX[rows[r]:sub(c, c)]
                if g then f[#f + 1] = string.format("lx_%s_%d.png", g, (r - 1) * LX_COLS + c - 1) end
            end
        end
    end

    local SAMPLES = {
        A = { grade = "SAT", tot = "41", earn = "+87", pen = "-46", loss = "0",
              groups = { { "+10", "0" }, { "+5", "-1" }, { "+13", "-3" }, { "0", "0" }, { "+42", "0" }, { "0", "0" },
                         { "0", "-15" }, { "+10", "-19" }, { "+7", "-5" }, { "0", "0" }, { "0", "0" } },
              lso = "OK", lsopts = "4.0", long = "(LUL)X (F)IM (LO)IC _LUL_AR (LLWD)IW (LIG)", wire = "2",
              tgr = "20.9", bk = { "60", "75", "80" }, stamp = 1,
              badges = { "READBACK_ACE", "FIRST_PLUG", "PARKING_PRO", "HEAVY", "SPEED_DEMON" } },
        B = { grade = "UNSAT", tot = "-212", earn = "+35", pen = "-247", loss = "-50",
              groups = { { "+10", "0" }, { "0", "-6" }, { "+5", "-10" }, { "0", "-4" }, { "+20", "-50" },
                         { "0", "-20" }, { "0", "-100" }, { "0", "-40" }, { "0", "-17" }, { "0", "0" }, { "0", "0" } },
              lso = "C", lsopts = "0.0", long = "_LUL_X _SLO__LO_IM (F)(LUL)IC _LO__LUR_AR (LLWD)IW _LIG_ (DL)(AA)X \\IM /IC WU AFU",
              tgr = "27.4", stamp = 3,
              badges = { "DEFENSIVE_ACE", "TIC_RESPONSE", "READBACK_ACE", "GHOST",
                         "BLUE_ON_BLUE", "COWBOY", "BOLTER_CLUB", "FUMES" } },
        C = { grade = "SH", tot = "118", earn = "+120", pen = "-2", loss = "0",
              groups = { { "+10", "0" }, { "+12", "0" }, { "+13", "0" }, { "+8", "0" }, { "+60", "0" }, { "+5", "0" },
                         { "0", "0" }, { "+7", "-2" }, { "+5", "0" }, { "0", "0" }, { "0", "0" } },
              lso = "DIV", badges = { "CLEAN_ROE" } },
    }
    local LSO_FILE = { OK = "lso_OK.png", C = "lso_C.png", DIV = "lso_DIV.png" }

    local function card(key)
        local S, f = SAMPLES[key], {}
        f[#f + 1] = "grade_" .. S.grade .. ".png"
        field(f, "tot", S.tot); field(f, "earn", S.earn); field(f, "pen", S.pen); field(f, "loss", S.loss)
        for i, g in ipairs(S.groups) do field(f, "g" .. i .. "e", g[1]); field(f, "g" .. i .. "p", g[2]) end
        f[#f + 1] = LSO_FILE[S.lso]
        if S.long then longGrade(f, S.long) end
        if S.lsopts then field(f, "lsopts", S.lsopts) end
        if S.wire then field(f, "wire", S.wire) end
        if S.tgr then field(f, "tgr", S.tgr) end
        if S.bk then field(f, "bk", S.bk[1]); field(f, "bkmax", S.bk[2]); field(f, "bkpct", S.bk[3]) end
        if S.stamp then f[#f + 1] = "stamp_" .. S.stamp .. ".png" end
        local n = math.min(#S.badges, BADGE_SLOTS)
        for i = 1, n do f[#f + 1] = string.format("badge_%s_%d.png", S.badges[i], BADGE_SLOTS - n + 2 * (i - 1)) end
        local fails = 0
        if not pic(DIR .. "frame.png", true) then fails = fails + 1 end
        for _, x in ipairs(f) do if not pic(DIR .. x, false) then fails = fails + 1 end end
        log(string.format("card %s: %d layers (frame + %d), failed %d", key, #f + 1, #f, fails))
    end

    local function board(a)
        local total, delta = a[1], a[2]
        if TRT.ScoreDisplay and TRT.ScoreDisplay.crt then
            local ok, err = pcall(TRT.ScoreDisplay.crt, total, delta)
            log(string.format("scoreboard %d / %+d %s", total, delta, ok and "ok" or ("ERROR " .. tostring(err))))
        else
            log("scoreboard: TRT.ScoreDisplay missing")
        end
    end

    local function clear()
        pic("PlaneCaptain/blank.png", true, 1)
        log("cleared")
    end

    local function real()
        if FR and FR.show then
            local ok, err = pcall(FR.show, "visual test")
            log("real card (Flight_Report.show): " .. (ok and "ok" or ("ERROR " .. tostring(err))))
        else
            log("real card: TRT.FlightReport missing")
        end
    end

    local now = timer.getTime()
    timer.scheduleFunction(function() board({ 42, 5 }) end, nil, now + 30)
    timer.scheduleFunction(function() board({ 27, -15 }) end, nil, now + 38)
    timer.scheduleFunction(function() board({ 147, 120 }) end, nil, now + 46)
    timer.scheduleFunction(function() card("A") end, nil, now + 54)

    local m = missionCommands.addSubMenu("VISUAL TEST")
    missionCommands.addCommand("Card A (SAT, long grade, 5 badges)", m, card, "A")
    missionCommands.addCommand("Card B (UNSAT, CUT, 8 badges)", m, card, "B")
    missionCommands.addCommand("Card C (SIERRA HOTEL, divert, 1 badge)", m, card, "C")
    missionCommands.addCommand("Real card (current data)", m, real)
    missionCommands.addCommand("Scoreboard 42 / +5", m, board, { 42, 5 })
    missionCommands.addCommand("Scoreboard 27 / -15", m, board, { 27, -15 })
    missionCommands.addCommand("Scoreboard 147 / +120", m, board, { 147, 120 })
    missionCommands.addCommand("Clear pictures", m, clear)
end
