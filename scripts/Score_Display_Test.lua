-- Score_Display_Test | v0.1.0
--[[
  Feasibility test for picture-based score cards (CAS (L) only, test copy).
  NOT part of the template build: build.py only embeds scripts named in
  src/l10n/DEFAULT/mapResource, and this one is not.

  What it answers (F10 > Other > INFO > Score card test):
    Paths   P1..P4  which file-name form outPicture resolves
                    P1 "ScoreCards/sc_test_root.png"        (.miz root folder)
                    P2 "l10n/DEFAULT/sc_test_l10n.png"      (full l10n path)
                    P3 "sc_test_l10n.png"                   (bare name)
                    P4 "ResKey_SCT_Pic"                     (mapResource key)
    Stack   S1      frame + 2 digit layers (clearView=false on layers)
            S2      same, call order reversed (is the last call on top?)
            S3      8 pictures at once (frame + "-123" + "-15")
            S4      does clearView=true also wipe outText messages?
    Sound           reward / penalty / mission_end via outSoundForCoalition,
                    plus one plain outSound
    Demo            the real presenter: CRT card on every change (aggregated
                    over CFG.AGG s), medal card at mission end
    Layout          cycle position / size / size units, toggle live hook,
                    API report

  Live hook (CFG.LIVE, default on): wraps TRT.addScore so real scoring
  events also raise the CRT card. Original text messages stay as they are.
  Only callers that go through TRT.addScore(...) are seen (all current
  modules do; a module caching `local f = TRT.addScore` would bypass it).

  outPicture* signature used:
    (..., file, duration, clearView, startDelay, hAlign, vAlign, size, sizeUnits)
    hAlign 0 left 1 centre 2 right | vAlign 0 top 1 centre 2 bottom
    sizeUnits 0 = % of original image, 1 = % of window
  Every layer has the frame's pixel size, so identical align/size arguments
  should overlay them exactly - that is what S1..S3 verify.
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT

local VERSION = "0.1.0"

local CFG = {
    DIR        = "ScoreCards/",
    SND_DIR    = "Sounds/SCORE/",
    FLAG_SCORE = 1908,                  -- Core_Scoring FLAG_SCORE
    SIDE       = coalition.side.BLUE,
    AGG        = 1.2,                   -- s, deltas inside this window -> one card
    LIVE       = true,
    MENU_ORDER = 90,
    CRT        = { dur = 6,  h = 2, v = 0, size = 22, units = 1 },
    MED        = { dur = 12, h = 1, v = 1, size = 50, units = 1 },
    PROBE      = { dur = 6,  h = 1, v = 1, size = 30, units = 1 },
}

local POS   = { { "TOP-RIGHT", 2, 0 }, { "TOP-LEFT", 0, 0 }, { "CENTRE", 1, 1 }, { "BOTTOM-RIGHT", 2, 2 } }
local SIZES = { 15, 22, 30, 40 }
local L = { pos = 1, size = 2 }

local A = trigger.action

local function log(s) env.info("Score_Display_Test | " .. s) end
local function msg(s, d) A.outTextForCoalition(CFG.SIDE, s, d or 10, false) end

----------------------------------------------------------------
-- LOW LEVEL
----------------------------------------------------------------
local function picAll(file, lay, clear)
    local ok, err = pcall(A.outPicture, file, lay.dur, clear, 0, lay.h, lay.v, lay.size, lay.units)
    if not ok then log("outPicture '" .. file .. "': " .. tostring(err)) end
    return ok
end

local function pic(file, lay, clear)
    local ok, err = pcall(A.outPictureForCoalition, CFG.SIDE, file, lay.dur, clear, 0,
        lay.h, lay.v, lay.size, lay.units)
    if not ok then log("outPictureForCoalition '" .. file .. "': " .. tostring(err)) end
    return ok
end

local function sound(name)
    local f = CFG.SND_DIR .. name .. ".ogg"
    local ok, err = pcall(A.outSoundForCoalition, CFG.SIDE, f)
    if not ok then log("outSoundForCoalition '" .. f .. "': " .. tostring(err)) end
end

local GL = { ["+"] = "p", ["-"] = "m" }

-- string -> layer files, centred: char i of L uses slot 2(i-1)-(L-1)+3 (0..6)
local function layerFiles(set, text, out)
    local n = #text
    for i = 1, n do
        local ch = text:sub(i, i)
        local slot = 2 * (i - 1) - (n - 1) + 3
        out[#out + 1] = string.format("%s%s_%s_%d.png", CFG.DIR, set, GL[ch] or ch, slot)
    end
    return out
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function fmtTotal(v) return tostring(clamp(math.floor(v + 0.5), -999, 9999)) end
local function fmtDelta(v)
    local d = clamp(math.floor(v + 0.5), -999, 999)
    return (d >= 0) and ("+" .. d) or tostring(d)
end

local function crtLayout()
    local p = POS[L.pos]
    CFG.CRT.h, CFG.CRT.v, CFG.CRT.size = p[2], p[3], SIZES[L.size]
end

----------------------------------------------------------------
-- PRESENTER
----------------------------------------------------------------
local function showCrt(total, delta)
    local files = { CFG.DIR .. "crt_frame.png" }
    layerFiles("crt_t", fmtTotal(total), files)
    if delta and delta ~= 0 then
        layerFiles(delta > 0 and "crt_dp" or "crt_dn", fmtDelta(delta), files)
    end
    for i, f in ipairs(files) do pic(f, CFG.CRT, i == 1) end
    log(string.format("CRT total=%s delta=%s layers=%d", fmtTotal(total),
        delta and fmtDelta(delta) or "-", #files))
end

local function showMedal(total)
    local files = layerFiles("med_t", fmtTotal(total), { CFG.DIR .. "med_frame.png" })
    for i, f in ipairs(files) do pic(f, CFG.MED, i == 1) end
    sound("mission_end")
    log(string.format("MEDAL total=%s layers=%d", fmtTotal(total), #files))
end

local P = { pending = 0, total = 0, armed = false }

local function flush()
    P.armed = false
    local d = P.pending
    P.pending = 0
    showCrt(P.total, d)
    if d > 0 then sound("reward") elseif d < 0 then sound("penalty") end
    return nil
end

local function push(delta, total)
    P.pending = P.pending + delta
    P.total = total
    if not P.armed then
        P.armed = true
        timer.scheduleFunction(flush, nil, timer.getTime() + CFG.AGG)
    end
end

----------------------------------------------------------------
-- LIVE HOOK
----------------------------------------------------------------
if type(TRT.addScore) == "function" and not TRT._SDT_wrapped then
    local orig = TRT.addScore
    TRT.addScore = function(delta, reason)
        orig(delta, reason)
        if not CFG.LIVE then return end
        local ok, err = pcall(function()
            local t = trigger.misc.getUserFlag(CFG.FLAG_SCORE)
            push(tonumber(delta) or 0, tonumber(t) or 0)
        end)
        if not ok then log("live hook: " .. tostring(err)) end
    end
    TRT._SDT_wrapped = true
    log("TRT.addScore wrapped (live hook)")
else
    log("TRT.addScore missing or already wrapped -> live hook not installed")
end

----------------------------------------------------------------
-- TESTS
----------------------------------------------------------------
local demo = 0

local function probe(tag, file)
    msg(string.format("%s sent: \"%s\"\nCard visible = this form works. Wait %ds before the next probe.",
        tag, file, CFG.PROBE.dur), CFG.PROBE.dur)
    local ok = picAll(file, CFG.PROBE, true)
    log(string.format("%s file=%s call_ok=%s", tag, file, tostring(ok)))
end

local function stack(text, dtext, reversed)
    local files = { CFG.DIR .. "crt_frame.png" }
    layerFiles("crt_t", text, files)
    if dtext then layerFiles(dtext:sub(1, 1) == "-" and "crt_dn" or "crt_dp", dtext, files) end
    if reversed then
        local r = {}
        for i = #files, 1, -1 do r[#r + 1] = files[i] end
        files = r
    end
    for i, f in ipairs(files) do pic(f, CFG.CRT, i == 1) end
    msg(string.format("Stack: %d pictures, %s order. Expected: %s%s",
        #files, reversed and "REVERSED" or "normal", text, dtext and (" / " .. dtext) or ""), CFG.CRT.dur)
end

local function apiReport()
    local names = { "outPicture", "outPictureForCoalition", "outPictureForGroup",
                    "outPictureForUnit", "outSound", "outSoundForCoalition", "outSoundForGroup" }
    local lines = { "Score_Display_Test v" .. VERSION .. " API:" }
    for _, n in ipairs(names) do
        lines[#lines + 1] = string.format("  %-24s %s", n, type(A[n]) == "function" and "yes" or "NO")
    end
    lines[#lines + 1] = string.format("Layout: %s, size %d%%, units %s | live hook %s",
        POS[L.pos][1], CFG.CRT.size, CFG.CRT.units == 1 and "window" or "image",
        CFG.LIVE and "ON" or "OFF")
    local s = table.concat(lines, "\n")
    msg(s, 15)
    log(s)
end

local ITEMS = {
    { "Score card test", sub = {
        { "Paths", sub = {
            { "P1 root ScoreCards/", function() probe("P1", CFG.DIR .. "sc_test_root.png") end },
            { "P2 l10n/DEFAULT/ path", function() probe("P2", "l10n/DEFAULT/sc_test_l10n.png") end },
            { "P3 bare file name", function() probe("P3", "sc_test_l10n.png") end },
            { "P4 ResKey", function() probe("P4", "ResKey_SCT_Pic") end },
        } },
        { "Stack", sub = {
            { "S1 frame + 2 layers", function() stack("42", nil, false) end },
            { "S2 reversed order", function() stack("42", nil, true) end },
            { "S3 8 pictures", function() stack("-123", "-15", false) end },
            { "S4 clearView vs text", function()
                msg("S4 TEXT PROBE: if this line vanishes when the card appears (2 s), clearView also clears messages.", 20)
                timer.scheduleFunction(function()
                    showCrt(demo, nil)
                    return nil
                end, nil, timer.getTime() + 2)
            end },
        } },
        { "Sound", sub = {
            { "reward", function() sound("reward") end },
            { "penalty", function() sound("penalty") end },
            { "mission end", function() sound("mission_end") end },
            { "plain outSound (all)", function()
                local ok, err = pcall(A.outSound, CFG.SND_DIR .. "reward.ogg")
                if not ok then log("outSound: " .. tostring(err)) end
            end },
        } },
        { "Demo", sub = {
            { "+5", function() demo = demo + 5; push(5, demo) end },
            { "-5", function() demo = demo - 5; push(-5, demo) end },
            { "+12", function() demo = demo + 12; push(12, demo) end },
            { "burst +3 +3 +4", function()
                for i, d in ipairs({ 3, 3, 4 }) do
                    timer.scheduleFunction(function()
                        demo = demo + d
                        push(d, demo)
                        return nil
                    end, nil, timer.getTime() + 0.3 * (i - 1))
                end
            end },
            { "mission end (medal)", function() showMedal(demo) end },
            { "reset demo total", function() demo = 0; msg("Demo total = 0", 5) end },
        } },
        { "Layout", sub = {
            { "cycle position", function()
                L.pos = L.pos % #POS + 1; crtLayout(); showCrt(demo, nil); apiReport()
            end },
            { "cycle size", function()
                L.size = L.size % #SIZES + 1; crtLayout(); showCrt(demo, nil); apiReport()
            end },
            { "toggle size units", function()
                CFG.CRT.units = 1 - CFG.CRT.units; showCrt(demo, nil); apiReport()
            end },
            { "toggle live hook", function() CFG.LIVE = not CFG.LIVE; apiReport() end },
            { "API report", apiReport },
        } },
    } },
}

-- fallback F10 builder (all players) when Menu_Manager is not loaded
local function addAll(items, parent)
    for _, it in ipairs(items) do
        if it.sub then
            addAll(it.sub, missionCommands.addSubMenu(it[1], parent))
        else
            local fn = it[2]
            missionCommands.addCommand(it[1], parent, function()
                local ok, err = pcall(fn)
                if not ok then log("item '" .. it[1] .. "': " .. tostring(err)) end
            end)
        end
    end
end

if TRT.Menu and TRT.Menu.Register then
    TRT.Menu.Register("INFO", "SDT", function() return ITEMS end, CFG.MENU_ORDER)
    log("menu registered under INFO")
else
    addAll(ITEMS, nil)
    log("TRT.Menu missing -> fallback F10 menu (all players)")
end

crtLayout()
timer.scheduleFunction(function() apiReport(); return nil end, nil, timer.getTime() + 5)
log("v" .. VERSION .. " loaded")
