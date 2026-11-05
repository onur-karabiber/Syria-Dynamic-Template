-- WingmanStrike v10
----------------------------------------------------------------
-- v10 DEGISIKLIGI: HEDEF KONUMU GUNCELLENDI
--   - Hedefler yeni konuma tasindi (STRIKE1_TRG2, 1224 ft rakim).
--   - ATTACK_HDG_DEG 77 -> 120. USE_DIRECTION kapali oldugu icin
--     bu deger su an kullanilmiyor, sadece konfigurasyonda tutuluyor.
--   - TRIGGER_NM = 20 korundu.
--   - Mantik v9 ile ayni (pushTask/popTask). Yalnizca surum etiketleri
--     (outText / env.info / init logu) v10 olarak duzeltildi.
----------------------------------------------------------------
----------------------------------------------------------------
-- v9 DEGISIKLIGI: ROTA ARTIK SILINMIYOR (pushTask / popTask)
--
-- Mission dosyasi incelemesi: Player_02'nin grubu (groupId 2322,
-- "Hornet51") rotasinin SON waypoint'i "SPLIT" zaten gemiye inis:
--     ["type"] = "Land", ["action"] = "Landing"
--     ["linkUnit"] = 2605, ["helipadId"] = 2605   (2605 = CVN, CVN_73)
-- Yani inis waypoint'i bastan dogru kurulmus.
--
-- SORUN: v8 iki yerde rotayi yok ediyordu:
--   1) giveStrikeTask() icinde task vermeden ONCE resetTask()
--   2) setTask({id="Bombing"}) - setTask grubun "Mission" task'ini,
--      yani ME rotasini KOMPLE degistirir.
-- Bu yuzden strike sonrasi Player_02'nin gidecek bir rotasi kalmiyordu;
-- resetTask() ile "rejoin" davranisina donuyor ama artik inis waypoint'i
-- olmadigi icin gemiye hic inemiyordu.
--
-- v9: pushTask ile gorev rotanin USTUNE yigiliyor, popTask ile geri
-- aliniyor. Boylece "SPLIT" inis waypoint'i hayatta kaliyor.
----------------------------------------------------------------
----------------------------------------------------------------
-- WINGMAN STRIKE MODULE v8
--
-- v7 LOG ANALIZI (dcs.log, 2026-08-17):
--   20:00:19.876  TRIGGER at 19.8 NM -> strike task
--   20:00:20.383  BOMBING TASK SET
--   20:02:36.711  Timeout -> rejoin        <-- 136 s sonra
--   Hicbir silah birakma olayi yok.
--
--   19.8 NM @ 320 kts = ~223 s ucus suresi. REJOIN_DELAY_SEC=120 idi.
--   Yani task DOGRU kuruldu, Player_02 hedefe yoneldi ("engaging primary"),
--   ama daha yolun yarisindayken v7'nin kendi timeout'u resetTask() cagirdi
--   ve saldiriyi iptal etti. Gordugun "rejoin" AI'in basarisizligi degil,
--   script'in kendi giveRejoin() cagrisiydi. Bombalarin uzerinde kalmasinin
--   sebebi buydu.
--
-- v7'den farklar:
--   1) CRITICAL FIX: Rejoin artik SUREYE degil OLAYA bagli.
--      Once muhimmat birakildi mi diye getAmmo() ile izleniyor;
--      birakildiktan sonra POST_RELEASE_SEC beklenip rejoin veriliyor.
--      Salt guvenlik amacli timeout SAFETY_TIMEOUT_SEC=600 s'ye cikarildi.
--   2) BUG FIX: Controller:getTask() DCS API'sinde YOK
--      (log: "attempt to call method 'getTask' (a nil value)", satir 143).
--      Yerine Controller:hasTask() kullaniliyor.
--   3) Teshis logu: task sonrasi Player_02'nin hedefe mesafesi, kalan
--      muhimmati ve hasTask durumu periyodik olarak yaziliyor.
--
-- NOT: weaponType=14 (GuidedBomb = LGB+TvGB+SNSGB) korundu. SNSGB
--      uydu-navigasyon guduumlu bombalari kapsar; GBU-32(V)2/B bu
--      kategoriye girer. v7'de AI'in ilk kez gorevi kabul edip hedefe
--      yonelmesi bu degerin dogru oldugunu destekliyor.
----------------------------------------------------------------

local CFG = {
    PLAYER_UNIT        = "Player_01",
    AI_UNIT            = "Player_02",
    GROUP_NAME         = "HORNET-5",   -- P1 2026-11-05: group renamed (CAS-1 -> HORNET-5)
    TARGET_STATIC      = "STRIKE1_TRG2",
    TRIGGER_NM         = 20,
    ATTACK_ALT_M       = 6705,      -- 22000 ft
    ATTACK_HDG_DEG     = 120,       -- v10: 77 -> 120 (USE_DIRECTION kapaliyken kullanilmaz)
    USE_DIRECTION      = false,     -- v8: varsayilan KAPALI (bkz. not asagida)
    WEAPON_TYPE        = 14,        -- GuidedBomb (LGB + TvGB + SNSGB)
    WEAPON_EXPEND      = "Two",
    ATTACK_QTY         = 1,
    TARGET_DEAD_FLAG   = 2542,      -- Flaggers_v1: FLAG_TRG2_DEAD
    POST_RELEASE_SEC   = 75,        -- bomba birakildiktan sonra rejoin gecikmesi
    SAFETY_TIMEOUT_SEC = 600,       -- sadece emniyet subabi
    POLL_RATE          = 2,
    STATUS_EVERY_SEC   = 15,        -- teshis logu araligi
    DEBUG              = false,      -- TRIGGER/TASK SET/STATUS/REJOIN vb.
    SHOW_DIST_PING     = false,     -- 10sn'lik "Dist to ..." mesafe pingi
}
-- USE_DIRECTION notu: sabit run-in acisi AI'i hedefe varmadan once
-- hizalanmak icin ekstra manevraya zorlar ve ingress suresini uzatir.
-- v8'den beri kapali. true yapilirsa ATTACK_HDG_DEG (v10: 120) kullanilir.

env.info("WingmanStrike v10: LOADED")   -- P1 2026-11-05: dcs.log only (no banner)

local WS = {
    taskGiven    = false,
    taskTime     = nil,
    released     = false,   -- muhimmat birakildi mi
    releaseTime  = nil,
    done         = false,
    startAmmo    = nil,
}
local cachedTgt     = nil
local lastDistPrint = 0
local lastStatus    = 0

local function dbg(msg)
    if CFG.DEBUG then trigger.action.outText("[WS] " .. tostring(msg), 7) end
    env.info("[WingmanStrike v10] " .. tostring(msg))
end

-- Sadece 10sn'lik mesafe pingi icin. CFG.DEBUG'dan bagimsiz calisir;
-- ekrana/loga basip basmayacagini yalniz CFG.SHOW_DIST_PING belirler.
local function dbgDist(msg)
    if CFG.SHOW_DIST_PING then trigger.action.outText("[WS] " .. tostring(msg), 7) end
    -- log dosyasina her zaman yazilir (susturulan sadece ekran), istersen
    -- bu satiri da SHOW_DIST_PING sartina bagla.
    env.info("[WingmanStrike v10] " .. tostring(msg))
end

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function getTargetPoint()
    local s = StaticObject.getByName(CFG.TARGET_STATIC)
    if not s then
        dbg("ERROR: StaticObject '" .. CFG.TARGET_STATIC .. "' not found!")
        return nil
    end
    local p = s:getPoint()
    if not p then
        dbg("ERROR: getPoint() nil for " .. CFG.TARGET_STATIC)
        return nil
    end
    return { x = p.x, y = p.z }   -- 2D: x = DCS_X, y = DCS_Z
end

local function getPlayerPos()
    local u = Unit.getByName(CFG.PLAYER_UNIT)
    if u and u:isExist() then return u:getPoint() end
    return nil
end

local function getAIUnit()
    local u = Unit.getByName(CFG.AI_UNIT)
    if u and u:isExist() then return u end
    return nil
end

local function dist2D_NM(p1, tgt)
    local dx = p1.x - tgt.x
    local dz = p1.z - tgt.y
    return math.sqrt(dx * dx + dz * dz) / 1852
end

-- Player_02 uzerindeki toplam bomba sayisi.
-- getAmmo() nil donebilir (hic muhimmat yoksa), o yuzden korumali.
local function getBombCount()
    local u = getAIUnit()
    if not u then return nil end

    local ok, ammo = pcall(function() return u:getAmmo() end)
    if not ok or not ammo then return 0 end

    local bombs = 0
    for _, entry in pairs(ammo) do
        if entry and entry.count and entry.desc then
            local isBomb = false
            if Weapon and Weapon.Category and entry.desc.category ~= nil then
                isBomb = (entry.desc.category == Weapon.Category.BOMB)
            else
                -- Weapon.Category yoksa isim uzerinden kaba filtre
                local dn = tostring(entry.desc.displayName or "")
                isBomb = (string.find(dn, "GBU") ~= nil) or (string.find(dn, "Mk%-8") ~= nil)
            end
            if isBomb then bombs = bombs + entry.count end
        end
    end
    return bombs
end

----------------------------------------------------------------
-- STRIKE TASK (UNIT controller only)
----------------------------------------------------------------
local function giveStrikeTask()
    if not cachedTgt then dbg("ERROR: no target point"); return end

    local aiUnit = getAIUnit()
    if not aiUnit then dbg("ERROR: " .. CFG.AI_UNIT .. " not found"); return end

    WS.startAmmo = getBombCount()
    dbg(string.format("Strike task | tgt x=%.0f y=%.0f | weaponType=%d | bombs onboard=%s",
        cachedTgt.x, cachedTgt.y, CFG.WEAPON_TYPE, tostring(WS.startAmmo)))

    -- v9: resetTask() KALDIRILDI. Rotayi siliyordu ve pushTask icin
    -- gereksiz. Task zaten rotanin ustune yiginacak.

    timer.scheduleFunction(function()
        local u = Unit.getByName(CFG.AI_UNIT)
        if not u or not u:isExist() then
            dbg("ERROR: " .. CFG.AI_UNIT .. " lost after reset")
            return nil
        end

        local params = {
            point           = { x = cachedTgt.x, y = cachedTgt.y },
            weaponType      = CFG.WEAPON_TYPE,
            expend          = CFG.WEAPON_EXPEND,
            attackQtyLimit  = true,
            attackQty       = CFG.ATTACK_QTY,
            altitudeEnabled = true,
            altitude        = CFG.ATTACK_ALT_M,
            groupAttack     = false,
        }

        if CFG.USE_DIRECTION then
            params.directionEnabled = true
            params.direction        = math.rad(CFG.ATTACK_HDG_DEG)
        else
            params.directionEnabled = false
        end

        -- v9: setTask DEGIL pushTask. setTask ME rotasini (ve icindeki
        -- "SPLIT" inis waypoint'ini) silerdi.
        u:getController():pushTask({ id = "Bombing", params = params })

        WS.taskGiven = true
        WS.taskTime  = timer.getTime()

        dbg(string.format("BOMBING TASK SET | %s | expend=%s qty=%d | %.0f ft | hdg=%s",
            CFG.TARGET_STATIC, CFG.WEAPON_EXPEND, CFG.ATTACK_QTY,
            CFG.ATTACK_ALT_M * 3.28084,
            CFG.USE_DIRECTION and tostring(CFG.ATTACK_HDG_DEG) or "AI-secer"))
        trigger.action.outText("WINGMAN: " .. CFG.AI_UNIT .. " tasked -> " .. CFG.TARGET_STATIC, 10)

        -- Verify: getTask() DCS'te YOK, hasTask() var.
        timer.scheduleFunction(function()
            local u2 = Unit.getByName(CFG.AI_UNIT)
            if u2 and u2:isExist() then
                local ok, has = pcall(function() return u2:getController():hasTask() end)
                if ok then
                    dbg("Task verify: hasTask=" .. tostring(has))
                else
                    dbg("Task verify: hasTask() call failed")
                end
            end
            return nil
        end, nil, timer.getTime() + 1)

        return nil
    end, nil, timer.getTime() + 0.5)
end

----------------------------------------------------------------
-- REJOIN
----------------------------------------------------------------
local function giveRejoin(reason)
    -- v9: resetTask() DEGIL popTask(). popTask sadece pushTask ile
    -- yiglanan Bombing gorevini kaldirir, altindaki ME rotasi (ve
    -- "SPLIT" inis waypoint'i) yerinde kalir.
    local u = getAIUnit()
    if u then
        local ok, err = pcall(function() u:getController():popTask() end)
        if not ok then
            env.warning("[WingmanStrike v10] popTask basarisiz: " .. tostring(err))
        end
    end
    WS.done = true
    dbg("REJOIN (" .. tostring(reason) .. "): " .. CFG.AI_UNIT .. " released to own navigation")
    trigger.action.outText("WINGMAN: " .. CFG.AI_UNIT .. " rejoin", 8)
end

----------------------------------------------------------------
-- SHOT EVENT (ikincil tespit yolu)
----------------------------------------------------------------
local ShotHandler = {}
function ShotHandler:onEvent(e)
    if not e or not e.id then return end
    if e.id ~= world.event.S_EVENT_SHOT then return end
    if not e.initiator or not e.initiator.getName then return end

    local ok, nm = pcall(function() return e.initiator:getName() end)
    if not ok or nm ~= CFG.AI_UNIT then return end

    if WS.taskGiven and not WS.released then
        WS.released    = true
        WS.releaseTime = timer.getTime()
        dbg("WEAPON RELEASE detected (S_EVENT_SHOT) by " .. CFG.AI_UNIT)
    end
end
world.addEventHandler(ShotHandler)

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
local function mainLoop()
    if WS.done then return nil end

    if not cachedTgt then
        cachedTgt = getTargetPoint()
        if not cachedTgt then return timer.getTime() + CFG.POLL_RATE end
        dbg(string.format("Target cached: x=%.0f y=%.0f", cachedTgt.x, cachedTgt.y))
    end

    ----------------------------------------------------------------
    -- TASK VERILDIKTEN SONRAKI FAZ
    ----------------------------------------------------------------
    if WS.taskGiven then
        local now = timer.getTime()

        -- 1) Hedef olduyse hemen rejoin
        if trigger.misc.getUserFlag(CFG.TARGET_DEAD_FLAG) == 1 then
            giveRejoin("target dead")
            return nil
        end

        -- 2) Muhimmat birakildi mi? (getAmmo farki)
        if not WS.released and WS.startAmmo then
            local nowAmmo = getBombCount()
            if nowAmmo and nowAmmo < WS.startAmmo then
                WS.released    = true
                WS.releaseTime = now
                dbg(string.format("WEAPON RELEASE detected (ammo %d -> %d)", WS.startAmmo, nowAmmo))
            end
        end

        -- 3) Birakildiysa: bombanin dusmesini bekle, sonra rejoin
        if WS.released and (now - WS.releaseTime) >= CFG.POST_RELEASE_SEC then
            giveRejoin("post-release delay elapsed")
            return nil
        end

        -- 4) Emniyet subabi
        if (now - WS.taskTime) >= CFG.SAFETY_TIMEOUT_SEC then
            giveRejoin("SAFETY timeout " .. CFG.SAFETY_TIMEOUT_SEC .. "s")
            return nil
        end

        -- 5) Teshis logu
        if (now - lastStatus) >= CFG.STATUS_EVERY_SEC then
            lastStatus = now
            local u = getAIUnit()
            local dTxt, hTxt = "n/a", "n/a"
            if u then
                local p = u:getPoint()
                if p then dTxt = string.format("%.1f NM", dist2D_NM(p, cachedTgt)) end
                local ok, has = pcall(function() return u:getController():hasTask() end)
                if ok then hTxt = tostring(has) end
            end
            dbg(string.format("STATUS t+%.0fs | %s->tgt %s | hasTask=%s | bombs=%s | released=%s",
                now - WS.taskTime, CFG.AI_UNIT, dTxt, hTxt,
                tostring(getBombCount()), tostring(WS.released)))
        end

        return timer.getTime() + CFG.POLL_RATE
    end

    ----------------------------------------------------------------
    -- TETIK FAZI
    ----------------------------------------------------------------
    local pPos = getPlayerPos()
    if not pPos then return timer.getTime() + CFG.POLL_RATE end

    local dist = dist2D_NM(pPos, cachedTgt)

    local now = timer.getTime()
    if (now - lastDistPrint) >= 10 then
        lastDistPrint = now
        dbgDist(string.format("Dist to %s: %.1f NM (trigger: %.0f NM)",
            CFG.TARGET_STATIC, dist, CFG.TRIGGER_NM))
    end

    if dist <= CFG.TRIGGER_NM then
        dbg(string.format("TRIGGER at %.1f NM -> strike task", dist))
        giveStrikeTask()
    end

    return timer.getTime() + CFG.POLL_RATE
end

----------------------------------------------------------------
-- INIT
----------------------------------------------------------------
timer.scheduleFunction(function()
    dbg(string.format("v10 ACTIVE | unit-controller | weaponType=%d | trigger=%d NM | "
        .. "post-release=%ds | safety=%ds",
        CFG.WEAPON_TYPE, CFG.TRIGGER_NM, CFG.POST_RELEASE_SEC, CFG.SAFETY_TIMEOUT_SEC))
    cachedTgt = getTargetPoint()
    if cachedTgt then
        dbg(string.format("Target point OK: x=%.0f y=%.0f", cachedTgt.x, cachedTgt.y))
    else
        dbg("Target not ready at init, will retry in loop")
    end
    timer.scheduleFunction(function()
        return mainLoop()
    end, nil, timer.getTime() + 1)
    return nil
end, nil, timer.getTime() + 1)
