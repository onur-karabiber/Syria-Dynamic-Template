-- JTAC_LOS_Audit | v1.0.0
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

local CFG = {
    delaySec             = 15,    -- mission basladiktan sonra kontrol gecikmesi
    EYE_OBSERVER_M       = 2.5,   -- JTAC birimi ustu gozlem yuksekligi (varsayim)
    EYE_TARGET_M         = 2.5,   -- hedef birimi ustu yukseklik (varsayim)
    MARGINAL_CLEARANCE_M = 1.0,   -- LOS var ama clearance bunun altindaysa MARGINAL
    PROFILE_SAMPLES      = 20,    -- clearance icin hat uzerindeki ornek sayisi
    SWEEP_M              = { 5, 10, 20, 50 }, -- BLOCKED icin "LOS su gozlemci yuksekliginde acilir"
    OUT_TEXT             = false, -- true: BLOCKED/MARGINAL icin ekrana da yazar
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
    elseif worstC < CFG.MARGINAL_CLEARANCE_M then
        logWarn("MARGINAL " .. summary)
        if CFG.OUT_TEXT then trigger.action.outText("[JTAC_LOS] MARGINAL " .. j.name .. " -> " .. tName, 15) end
    else
        logInfo("OK      " .. summary)
    end
end

local function run()
    local ok, err = pcall(function()
        local jtacs, idToName = scanMission()
        logInfo(string.format("v1.0.0 | %d JTAC grubu bulundu (FAC_AttackGroup) | eye obs=%.1f m tgt=%.1f m marginal<%.1f m",
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
