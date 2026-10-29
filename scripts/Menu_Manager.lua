-- Menu_Manager | v1.1.0
-- v1.1.0: prefix-stable rebuild. Only the items from the first changed position on are removed and
--         re-added; the DCS handles of the items above stay. Flight 2026-10-29 #2: a COMMS rebuild
--         (label change, no press) 5 s before a press made DCS deliver "OVERLORD: feet dry" for a
--         press on "correlation > TALLY" (log: rebuild 15:08:31, press 15:08:36). The full
--         remove/re-add of v1.0.x is the suspected cause [V]; JTAC items sit on top, so changes in the
--         Comms_Director items below no longer touch them.
-- v1.0.1: logs every F10 press ("press: COMMS > <label>") and every COMMS rebuild with its labels,
--         to find the 2026-10-29 case where a press on "POINTER 11: IP INBOUND" ran
--         "OVERLORD: request picture" (no stale-press line, so DCS delivered that command).
--[[
  F10 menu owner — TRT Syria Dynamic Template (template-level module)

  One owner for the hero's F10 > Other tree. Roots are created once, in a fixed
  order, and never removed (F-key positions stay put); only their children are
  rebuilt, and only when the label set changes.

    F1  COMMS     calls valid right now (CV_Comms, Comms_Director) + "Show: next call"
    F2  INFO      "Show: comm card" (merged from every card provider) + provider items
    F3  CARRIER   trimmed AIRBOSS menu (Airboss_Start)
    F4  TRAINING  Bankler's trainer toggles (TrapTraining) — DECK only, hidden
                  otherwise (last root, so hiding it shifts nothing)

  Menu phase (TRT.Menu.Phase()):
    DECK       hero not airborne (pre-launch and after the trap)
    RECOVERY   airborne, some provider hints RECOVERY   (highest rank)
    DEPARTURE  airborne, some provider hints DEPARTURE
    MISSION    airborne, anything else (also: no hints at all)

  Also: MOOSE's per-player 'Settings "<name>"' menu is switched off
  (_SETTINGS:SetPlayerMenuOff()) — nothing in the template reads those settings.

  API — load this file right after MOOSE / MIST, before every provider:
    TRT.Menu.Register(section, owner, fn, order)    fn(phase) -> { item, ... }
        item = { "label", fn }   |   { "label", sub = { item, ... } }
    TRT.Menu.RegisterNext(owner, fn)                fn(phase) -> "text" | nil
    TRT.Menu.RegisterCard(owner, fn, order)         fn() -> { buttons = { {n=, f=, name=}, ... },
                                                              lines = { "...", ... } }
    TRT.Menu.SetHint(owner, phase | nil)            "DEPARTURE" / "MISSION" / "RECOVERY"
    TRT.Menu.Refresh()                              rebuild now (call after a phase change)
    TRT.Menu.Msg(text, dur)                         text to the hero's group
  A pressed item is looked up by its label path in the CURRENT item list, so a
  provider's closures are never stale. A pressed item triggers Refresh().
]]

_G.TRT = _G.TRT or {}
if TRT.Menu then
    env.info("Menu_Manager | already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION     = "1.1.0",
    PLAYER_UNIT = "Player_01",
    TICK        = 2,                                          -- s
    SECTIONS    = { "COMMS", "INFO", "CARRIER", "TRAINING" }, -- F1..F4, fixed order
    HIDE_EMPTY  = { TRAINING = true },                        -- only trailing roots
    RANK        = { RECOVERY = 3, DEPARTURE = 2, MISSION = 1 },
    MSG_DUR     = 10,
}

local M = {
    providers = {},      -- section -> { {owner, fn, order}, ... }
    nexts     = {},      -- { {owner, fn}, ... }
    cards     = {},      -- { {owner, fn, order}, ... }
    hints     = {},      -- owner -> phase
    gid       = nil,
    roots     = {},      -- section -> DCS path (nil = not created / hidden)
    handles   = {},      -- section -> { top-level child path, ... }
    sig       = {},      -- section -> label signature of the built children
    isig      = {},      -- section -> { per-item signature, ... } (v1.1.0)
    cur       = {},      -- section -> item list the children were built from
}
TRT.Menu = M
for _, s in ipairs(CFG.SECTIONS) do M.providers[s] = {} end

local function Log(s) env.info("Menu_Manager | " .. s) end

local function Hero()
    local u = Unit.getByName(CFG.PLAYER_UNIT)
    if u and u:isExist() then return u end
    return nil
end

function M.Msg(text, dur)
    if M.gid then
        trigger.action.outTextForGroup(M.gid, text, dur or CFG.MSG_DUR)
    else
        trigger.action.outText(text, dur or CFG.MSG_DUR)
    end
end

-- ══════════════════════════════════════════════════════════════
--  PHASE
-- ══════════════════════════════════════════════════════════════
function M.Phase()
    local u = Hero()
    if not u then return nil end
    if not u:inAir() then return "DECK" end
    local best, rank = "MISSION", 0
    for _, ph in pairs(M.hints) do
        local r = CFG.RANK[ph] or 0
        if r > rank then best, rank = ph, r end
    end
    return best
end

function M.SetHint(owner, phase)
    if M.hints[owner] ~= phase then
        M.hints[owner] = phase
        M.Refresh()
    end
end

-- ══════════════════════════════════════════════════════════════
--  REGISTRATION
-- ══════════════════════════════════════════════════════════════
local function SortByOrder(list)
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

function M.Register(section, owner, fn, order)
    local list = M.providers[section]
    if not list then Log("Register: unknown section '" .. tostring(section) .. "' (" .. tostring(owner) .. ")"); return end
    for i = #list, 1, -1 do if list[i].owner == owner then table.remove(list, i) end end
    list[#list + 1] = { owner = owner, fn = fn, order = order }
    SortByOrder(list)
    Log("provider " .. tostring(owner) .. " -> " .. section)
end

function M.RegisterNext(owner, fn)
    for i = #M.nexts, 1, -1 do if M.nexts[i].owner == owner then table.remove(M.nexts, i) end end
    M.nexts[#M.nexts + 1] = { owner = owner, fn = fn }
end

function M.RegisterCard(owner, fn, order)
    for i = #M.cards, 1, -1 do if M.cards[i].owner == owner then table.remove(M.cards, i) end end
    M.cards[#M.cards + 1] = { owner = owner, fn = fn, order = order }
    SortByOrder(M.cards)
end

-- ══════════════════════════════════════════════════════════════
--  BUILT-IN ITEMS
-- ══════════════════════════════════════════════════════════════
local function ShowNext()
    local ph = M.Phase()
    local txt
    -- the provider whose hint matches the current phase answers first
    for pass = 1, 2 do
        for _, p in ipairs(M.nexts) do
            if not txt and ((pass == 1 and M.hints[p.owner] == ph) or pass == 2) then
                local ok, r = pcall(p.fn, ph)
                if ok and type(r) == "string" and r ~= "" then txt = r end
                if not ok then Log("next(" .. p.owner .. "): " .. tostring(r)) end
            end
        end
    end
    M.Msg("[COMMS] " .. (txt or "No call pending."), 12)
end

local function ShowCard()
    local seen, buttons, notes = {}, {}, {}
    for _, p in ipairs(M.cards) do
        local ok, c = pcall(p.fn)
        if ok and type(c) == "table" then
            for _, b in ipairs(c.buttons or {}) do
                if b.n and not seen[b.n] then seen[b.n] = true; buttons[#buttons + 1] = b end
            end
            for _, l in ipairs(c.lines or {}) do notes[#notes + 1] = l end
        elseif not ok then
            Log("card(" .. p.owner .. "): " .. tostring(c))
        end
    end
    table.sort(buttons, function(a, b) return a.n < b.n end)
    local out = { "── COMM CARD (COMM1) ─────────────────" }
    for _, b in ipairs(buttons) do
        out[#out + 1] = string.format("BTN %-3s %-10s %s", tostring(b.n), b.f or "", b.name or "")
    end
    if #notes > 0 then out[#out + 1] = "──────────────────────────────────────" end
    for _, l in ipairs(notes) do out[#out + 1] = l end
    M.Msg(table.concat(out, "\n"), 25)
end

-- ══════════════════════════════════════════════════════════════
--  COLLECT
-- ══════════════════════════════════════════════════════════════
local function Collect(section, ph)
    local items = {}
    if section == "INFO" then items[#items + 1] = { "Show: comm card", ShowCard } end
    for _, p in ipairs(M.providers[section]) do
        local ok, r = pcall(p.fn, ph)
        if ok and type(r) == "table" then
            for _, it in ipairs(r) do items[#items + 1] = it end
        elseif not ok then
            Log(section .. "(" .. p.owner .. "): " .. tostring(r))
        end
    end
    if section == "COMMS" then items[#items + 1] = { "Show: next call", ShowNext } end
    return items
end

local function Signature(items)
    local parts = {}
    for i, it in ipairs(items) do
        parts[i] = tostring(it[1]) .. (it.sub and ("{" .. Signature(it.sub) .. "}") or "")
    end
    return table.concat(parts, "|")
end

-- ══════════════════════════════════════════════════════════════
--  BUILD
-- ══════════════════════════════════════════════════════════════
local Press

local function AddItems(gid, parent, items, section, prefix, handles)
    for _, it in ipairs(items) do
        local path = {}
        for i, l in ipairs(prefix) do path[i] = l end
        path[#path + 1] = it[1]
        local h
        if it.sub then
            h = missionCommands.addSubMenuForGroup(gid, it[1], parent)
            AddItems(gid, h, it.sub, section, path, nil)
        else
            h = missionCommands.addCommandForGroup(gid, it[1], parent, Press, { section = section, path = path })
        end
        if handles then handles[#handles + 1] = h end
    end
end

local function DropAll()
    if M.gid then
        for _, s in ipairs(CFG.SECTIONS) do
            if M.roots[s] then pcall(missionCommands.removeItemForGroup, M.gid, M.roots[s]) end
        end
    end
    M.gid, M.roots, M.handles, M.sig, M.cur, M.isig = nil, {}, {}, {}, {}, {}
end

local function Build()
    local u = Hero()
    if not u then
        if M.gid then DropAll() end
        return
    end
    local g = u:getGroup()
    local gid = g and g:getID()
    if not gid then return end
    if M.gid and M.gid ~= gid then DropAll() end
    M.gid = gid

    local ph = M.Phase()
    for _, s in ipairs(CFG.SECTIONS) do
        local items = Collect(s, ph)
        local hide = CFG.HIDE_EMPTY[s] and #items == 0
        if hide then
            if M.roots[s] then
                pcall(missionCommands.removeItemForGroup, gid, M.roots[s])
                M.roots[s], M.handles[s], M.sig[s], M.cur[s], M.isig[s] = nil, nil, nil, nil, nil
            end
        else
            if not M.roots[s] then
                M.roots[s] = missionCommands.addSubMenuForGroup(gid, s)
                M.handles[s], M.sig[s], M.isig[s] = {}, nil, nil
            end
            local sig = Signature(items)
            if sig ~= M.sig[s] then
                -- v1.1.0: keep the handles of the unchanged leading items
                local old, new = M.isig[s] or {}, {}
                for i, it in ipairs(items) do new[i] = Signature({ it }) end
                local first = 1
                while first <= #new and first <= #old and old[first] == new[first] do first = first + 1 end
                if s == "COMMS" then Log(string.format("rebuild COMMS from #%d: %s", first, sig)) end
                local hs = M.handles[s] or {}
                for i = #hs, first, -1 do
                    pcall(missionCommands.removeItemForGroup, gid, hs[i]); hs[i] = nil
                end
                local tail = {}
                for i = first, #items do tail[#tail + 1] = items[i] end
                AddItems(gid, M.roots[s], tail, s, {}, hs)
                M.handles[s], M.sig[s], M.isig[s] = hs, sig, new
            end
            M.cur[s] = items
        end
    end
end

function M.Refresh()
    local ok, err = pcall(Build)
    if not ok then Log("build error: " .. tostring(err)) end
end

-- Resolve the pressed label path against the CURRENT items (no stale closures).
local function Find(items, path, depth)
    for _, it in ipairs(items or {}) do
        if it[1] == path[depth] then
            if depth == #path then return it end
            return Find(it.sub, path, depth + 1)
        end
    end
    return nil
end

Press = function(arg)
    Log("press: " .. tostring(arg.section) .. " > " .. table.concat(arg.path or {}, " > "))   -- v1.0.1
    local it = Find(M.cur[arg.section], arg.path, 1)
    if it and it[2] then
        local ok, err = pcall(it[2])
        if not ok then Log("item '" .. table.concat(arg.path, " > ") .. "': " .. tostring(err)) end
    else
        Log("stale press ignored: " .. arg.section .. " > " .. table.concat(arg.path, " > "))
    end
    M.Refresh()
end

-- ══════════════════════════════════════════════════════════════
--  RUN
-- ══════════════════════════════════════════════════════════════
if _SETTINGS and _SETTINGS.SetPlayerMenuOff then
    _SETTINGS:SetPlayerMenuOff()
    Log("MOOSE player Settings menu off")
end

local EH = {}
function EH:onEvent(e)
    if e and e.initiator and (e.id == world.event.S_EVENT_BIRTH or e.id == world.event.S_EVENT_TAKEOFF
       or e.id == world.event.S_EVENT_LAND) then
        local ok, name = pcall(function() return e.initiator:getName() end)
        if ok and name == CFG.PLAYER_UNIT then
            if e.id == world.event.S_EVENT_BIRTH then DropAll() end
            timer.scheduleFunction(function() M.Refresh() end, nil, timer.getTime() + 0.5)
        end
    end
end
world.addEventHandler(EH)

timer.scheduleFunction(function(_, t)
    M.Refresh()
    return t + CFG.TICK
end, nil, timer.getTime() + 1)

Log("v" .. CFG.VERSION .. " loaded")
