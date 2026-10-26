-- JTAC_LOS_Audit | v1.1.0
-- Mission baslangicinda her AI JTAC (route icinde FAC_AttackGroup gorevi olan grup)
-- ile hedef grubu arasindaki ARAZI gorus hattini (LOS) kontrol eder ve dcs.log'a yazar.
-- Sadece log: oyuna mudahale etmez, birim tasimaz, menu eklemez.
--
-- Neden: dcs.log testlerinde (2026-10) JTAC'in lazer tutmasi ile JTAC->hedef arazi LOS'unun
-- birlikte degistigi gozlendi (LOS yok: lazer yok, type-3, menuda "Repeat brief";
-- LOS var: lazer, type-2, "IP INBOUND"). Engel 0.4-0.7 m'lik bir arazi kabarikligi kadar
-- kucuk olabiliyor. Bu bir gozlem; DCS'in dahili tespit mantigi belgelenmis degil.
--
-- Log etiketi: [JTAC_LOS]
--   OK        tum hedef birimleri icin LOS var, min. clearance >= MARGINAL_CLEARANCE_M
--   MARGINAL  LOS var ama clearance MARGINAL_CLEARANCE_M altinda (goz yuksekligi varsayimi
--             hatasina acik)
--   BLOCKED   en az bir hedef biriminde arazi LOS'u yok (env.warning ile yazilir)
--   SKIP      JTAC veya hedef grubu bu anda sahada yok (late activated vb.)
--
-- Sinirlar (bilinen):
--   * land.isVisible yalnizca araziyi dikkate alir; bina/agac/tasitin JTAC tespitine etkisi
--     dogrulanmadi ve bu script onlari olcmez.
--   * Goz yuksekligi varsayimi: EYE_OBSERVER_M / EYE_TARGET_M (dogrulanmis DCS degeri degil).
--   * Tek seferlik kontrol (baslangic + CFG.delaySec). Hedef sonradan tasinirsa tekrar bakmaz.
--
-- v1.1.0 - konum arama (CFG.SEARCH): BLOCKED / MARGINAL her JTAC icin, mevcut konumun
-- etrafindaki halkalarda aday noktalar taranir. Aday kosullari: kara veya yol yuzeyi, egim
-- siniri, her hedef birimine LOS ve en az CFG.MIN_TARGET_M uzaklik, hedef merkezine
-- CFG.RANGE_M araliginda mesafe. Siralama: once tum birimlerde clearance >= MARGINAL olanlar,
-- sonra mevcut konuma en yakin olan. En iyi CFG.TOP_N aday "CANDIDATE" satiri olarak yazilir
-- (ME koordinati x / y, MGRS, LL). Sadece log; JTAC'i tasimaz - konum ME'de degistirilir.

local CFG = {
    delaySec             = 15,    -- mission basladiktan sonra kontrol gecikmesi
    EYE_OBSERVER_M       = 2.5,   -- JTAC birimi ustu gozlem yuksekligi (varsayim)
    EYE_TARGET_M         = 2.5,   -- hedef birimi ustu yukseklik (varsayim)
    MARGINAL_CLEARANCE_M = 1.0,   -- LOS var ama clearance bunun altindaysa MARGINAL
    PROFILE_SAMPLES      = 20,    -- clearance icin hat uzerindeki ornek sayisi
    SWEEP_M              = { 5, 10, 20, 50 }, -- BLOCKED icin "LOS su gozlemci yuksekliginde acilir"
    OUT_TEXT             = false, -- true: BLOCKED/MARGINAL icin ekrana da yazar
    -- v1.1.0 konum arama
    SEARCH               = true,
    RING_STEP_M          = 25,    -- halka araligi
    RING_MAX_M           = 400,   -- mevcut konumdan en fazla bu kadar uzak aday
    ANGLE_STEP_DEG       = 10,
    RANGE_M              = { 300, 1500 }, -- aday ile hedef merkezi arasi mesafe araligi
    MIN_TARGET_M         = 250,   -- her hedef birimine en az bu kadar uzak
    MAX_SLOPE_M          = 1.5,   -- 5 m mesafedeki dort komsu noktayla yukseklik farki siniri
    TOP_N                = 3,
}

local function logInfo(msg)  env.info("[JTAC_LOS] " .. msg) end
local function logWarn(msg)  env.warning("[JTAC_LOS] " .. msg) end

----------------------------------------------------------------
-- Mission tablosundan JTAC gruplari ve groupId -> ad esleme
----------------------------------------------------------------
local function findFacParams(t, depth)
    if type(t) ~= "table" or depth > 12 then return nil end
    if t.id == "FAC_AttackGroup" and type(t.params) == "table" then
        return t.params
    end
    for _, v in pairs(t) do
        if type(v) == "table" then
            local r = findFacParams(v, depth + 1)
            if r then return r end
        end
    end
    return nil
end

local function scanMission()
    local jtacs, idToName = {}, {}
    local coal = env.mission and env.mission.coalition
    if not coal then return jtacs, idToName end
    for _, side in pairs(coal) do
        for _, country in pairs(side.country or {}) do
            for cat, list in pairs(country) do
                if type(list) == "table" and type(list.group) == "table" then
                    for _, grp in pairs(list.group) do
                        if grp.groupId and grp.name then
                            idToName[grp.groupId] = grp.name
                        end
                        if cat == "vehicle" and grp.route then
                            local p = findFacParams(grp.route, 0)
                            if p and p.groupId then
                                jtacs[#jtacs + 1] = { name = grp.name, targetGroupId = p.groupId }
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(jtacs, function(a, b) return a.name < b.name end)
    return jtacs, idToName
end

----------------------------------------------------------------
-- Geometri
----------------------------------------------------------------
local function aliveUnits(group)
    local out = {}
    if not group then return out end
    local ok, us = pcall(function() return group:getUnits() end)
    if not ok or not us then return out end
    for _, u in ipairs(us) do
        if u and u:isExist() then out[#out + 1] = u end
    end
    return out
end

-- Gorus cizgisi ile arazi arasindaki en kucuk dikey bosluk (m); negatif = arazi cizgiyi kesiyor.
local function minClearance(jp, tp)
    local n = CFG.PROFILE_SAMPLES
    local minC = math.huge
    local y1, y2 = jp.y + CFG.EYE_OBSERVER_M, tp.y + CFG.EYE_TARGET_M
    for i = 1, n - 1 do
        local f = i / n
        local x = jp.x + (tp.x - jp.x) * f
        local z = jp.z + (tp.z - jp.z) * f
        local h = land.getHeight({ x = x, y = z })
        local c = (y1 + (y2 - y1) * f) - h
        if c < minC then minC = c end
    end
    return minC
end

local function losAt(jp, tp, obsOffset)
    return land.isVisible(
        { x = jp.x, y = jp.y + obsOffset, z = jp.z },
        { x = tp.x, y = tp.y + CFG.EYE_TARGET_M, z = tp.z })
end


----------------------------------------------------------------
-- v1.1.0: konum arama
----------------------------------------------------------------
local function groundOK(x, z)
    local okS, st = pcall(land.getSurfaceType, { x = x, y = z })
    if not okS then return false end
    if st ~= land.SurfaceType.LAND and st ~= land.SurfaceType.ROAD then return false end
    local h = land.getHeight({ x = x, y = z })
    for _, d in ipairs({ { 5, 0 }, { -5, 0 }, { 0, 5 }, { 0, -5 } }) do
        if math.abs(land.getHeight({ x = x + d[1], y = z + d[2] }) - h) > CFG.MAX_SLOPE_M then return false end
    end
    return true, h
end

local function fmtPos(x, y, z)
    local okL, lat, lon = pcall(coord.LOtoLL, { x = x, y = y, z = z })
    if not okL or not lat then return "" end
    local mg = ""
    local okM, m = pcall(coord.LLtoMGRS, lat, lon)
    if okM and type(m) == "table" then
        mg = string.format("%s %s %05d %05d", tostring(m.UTMZone), tostring(m.MGRSDigraph),
            math.floor((m.Easting or 0) + 0.5), math.floor((m.Northing or 0) + 0.5))
    end
    return string.format("MGRS %s | LL %.5f %.5f", mg, lat, lon)
end

local function searchPositions(j, tName, jp, tus)
    local tps = {}
    local cx, cz = 0, 0
    for _, tu in ipairs(tus) do
        local tp = tu:getPoint()
        tps[#tps + 1] = tp
        cx, cz = cx + tp.x, cz + tp.z
    end
    cx, cz = cx / #tps, cz / #tps
    local found, tested = {}, 0
    for r = CFG.RING_STEP_M, CFG.RING_MAX_M, CFG.RING_STEP_M do
        for a = 0, 359, CFG.ANGLE_STEP_DEG do
            local rad = math.rad(a)
            local x, z = jp.x + math.cos(rad) * r, jp.z + math.sin(rad) * r
            local dc = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
            if dc >= CFG.RANGE_M[1] and dc <= CFG.RANGE_M[2] then
                local ok, h = groundOK(x, z)
                if ok then
                    tested = tested + 1
                    local cp = { x = x, y = h, z = z }
                    local allVis, minC, tooClose = true, math.huge, false
                    for _, tp in ipairs(tps) do
                        if math.sqrt((tp.x - x) ^ 2 + (tp.z - z) ^ 2) < CFG.MIN_TARGET_M then tooClose = true break end
                        if not losAt(cp, tp, CFG.EYE_OBSERVER_M) then allVis = false break end
                        local c = minClearance(cp, tp)
                        if c < minC then minC = c end
                    end
                    if allVis and not tooClose then
                        found[#found + 1] = { x = x, y = h, z = z, r = r, brg = a, dc = dc, c = minC,
                            good = minC >= CFG.MARGINAL_CLEARANCE_M }
                    end
                end
            end
        end
    end
    table.sort(found, function(p, q)
        if p.good ~= q.good then return p.good end
        if p.r ~= q.r then return p.r < q.r end
        return p.c > q.c
    end)
    if #found == 0 then
        logWarn(string.format("SEARCH  %s -> %s: %d aday denendi, hepsini goren nokta yok (halka <= %d m)",
            j.name, tName, tested, CFG.RING_MAX_M))
        return
    end
    logInfo(string.format("SEARCH  %s -> %s: %d aday denendi, %d uygun; en iyi %d:", j.name, tName, tested, #found,
        math.min(CFG.TOP_N, #found)))
    for i = 1, math.min(CFG.TOP_N, #found) do
        local f = found[i]
        logInfo(string.format("CANDIDATE %s #%d: ME x=%.0f y=%.0f alt=%.0f m | mevcut konumdan %d m, yon %03d (grid) | hedef merkezine %.0f m | min clearance %+.1f m%s | %s",
            j.name, i, f.x, f.z, f.y, f.r, f.brg, f.dc, f.c, f.good and "" or " (MARGINAL)", fmtPos(f.x, f.y, f.z)))
    end
end

local function auditOne(j, idToName)
    local tName = idToName[j.targetGroupId]
    if not tName then
        logWarn(string.format("SKIP    %s -> groupId %s: hedef grubu mission'da bulunamadi", j.name, tostring(j.targetGroupId)))
        return
    end
    local jg, tg = Group.getByName(j.name), Group.getByName(tName)
    local ju, tus = aliveUnits(jg), aliveUnits(tg)
    if #ju == 0 or #tus == 0 then
        logInfo(string.format("SKIP    %s -> %s: JTAC birimi=%d, hedef birimi=%d (saha disi / late activated?)", j.name, tName, #ju, #tus))
        return
    end
    local jp = ju[1]:getPoint()

    local blocked, worstC, worstDist, visCount = {}, math.huge, 0, 0
    local needsHeight
    for _, tu in ipairs(tus) do
        local tp = tu:getPoint()
        local dist = math.sqrt((tp.x - jp.x) ^ 2 + (tp.z - jp.z) ^ 2)
        local vis = losAt(jp, tp, CFG.EYE_OBSERVER_M)
        local c = minClearance(jp, tp)
        if vis then visCount = visCount + 1 else blocked[#blocked + 1] = tu:getName() end
        if c < worstC then worstC, worstDist = c, dist end
        if not vis and not needsHeight then
            for _, off in ipairs(CFG.SWEEP_M) do
                if losAt(jp, tp, off) then needsHeight = off break end
            end
        end
    end

    local summary = string.format("%s -> %s: LOS %d/%d birim, mesafe=%.0f m (en dar clearance'li birim), min clearance=%+.1f m",
        j.name, tName, visCount, #tus, worstDist, worstC)

    if visCount < #tus then
        local extra = needsHeight
            and string.format(" | gozlemci +%s m olsaydi LOS acilirdi", tostring(needsHeight))
            or  string.format(" | gozlemci +%s m'de bile LOS yok", tostring(CFG.SWEEP_M[#CFG.SWEEP_M]))
        logWarn("BLOCKED " .. summary .. extra .. " | engelli birimler: " .. table.concat(blocked, ", "))
        if CFG.OUT_TEXT then trigger.action.outText("[JTAC_LOS] BLOCKED " .. j.name .. " -> " .. tName, 15) end
        if CFG.SEARCH then searchPositions(j, tName, jp, tus) end
    elseif worstC < CFG.MARGINAL_CLEARANCE_M then
        logWarn("MARGINAL " .. summary)
        if CFG.OUT_TEXT then trigger.action.outText("[JTAC_LOS] MARGINAL " .. j.name .. " -> " .. tName, 15) end
        if CFG.SEARCH then searchPositions(j, tName, jp, tus) end
    else
        logInfo("OK      " .. summary)
    end
end

local function run()
    local ok, err = pcall(function()
        local jtacs, idToName = scanMission()
        logInfo(string.format("v1.1.0 | %d JTAC grubu bulundu (FAC_AttackGroup) | eye obs=%.1f m tgt=%.1f m marginal<%.1f m",
            #jtacs, CFG.EYE_OBSERVER_M, CFG.EYE_TARGET_M, CFG.MARGINAL_CLEARANCE_M))
        for _, j in ipairs(jtacs) do
            local ok2, e2 = pcall(auditOne, j, idToName)
            if not ok2 then logWarn("hata " .. tostring(j.name) .. ": " .. tostring(e2)) end
        end
    end)
    if not ok then logWarn("audit basarisiz: " .. tostring(err)) end
    return nil
end

timer.scheduleFunction(run, nil, timer.getTime() + CFG.delaySec)
