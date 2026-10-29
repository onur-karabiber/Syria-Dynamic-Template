-- SAM_FireGate | v1.5.3
-- Belirtilen SAM gruplarinin ROE'sini (WEAPON_HOLD / WEAPON_FREE) kurala gore yonetir.
-- Radar/lock davranisina dokunmaz; sadece atis iznini kontrol eder.
--
-- Iki kural tipi (grup basina):
--   mode = "distance": en yakin mavi ucak gateNM icine girene kadar HOLD.
--   mode = "ceiling" : menzil (rangeNM) icinde irtifasi ceilingFt veya altinda
--                      en az bir mavi ucak yoksa HOLD. Menzil icindeki tum mavi
--                      ucaklar ceilingFt ustundeyse SAM atis yapmaz.
--
-- v1.5.3:
--  * Hard deck 23,000 -> 20,000 ft MSL (Comms_Director v1.6.3): the three ceiling groups
--    (YE53 SA-3, BV22 SA-6, HS02 SA-6) 22000 -> 19000 ft, i.e. 1,000 ft below the deck (+500 ft
--    hysteresis while FREE). Config only.
--
-- v1.5.2:
--  * "SAM HS02 (SA-6)-1" icin ceiling kurali eklendi (22000 ft, highVeto="players").
--    Kod degisikligi yok, sadece FIRE_GATE.groups girdisi. Sebep: dcs.log 10:27 testinde
--    HS02 SA-6 grubu (kapi tanimsiz, "SHOT (ungated)") 23517 ft ve 18013 ft'teki
--    oyuncuya iki fuze atti ve vurdu. Radar kapisi (radarGateNM) eklenmedi; yalnizca
--    atis izni (ROE) kontrol edilir, YE53 (SA-3) ile ayni desen.
--
-- v1.5.1:
--  * Teshis: kapi tanimli OLMAYAN kirmizi yer birimlerinin fuze atislari da loglanir
--    (logUngatedShots): "SHOT (ungated) by ... group ... weapon ... target ... ft".
--    Sebep: dcs.log 19:36-19:37 testinde oyuncuya atis yapan SA-6'nin hangisi
--    oldugu atfedilemiyordu (BV22'den SHOT satiri yok; myIADS pop-up SA-6'lari
--    FireGate'te tanimli degil). Davranis degisikligi yok.
--
-- v1.5.0:
--  * highVeto (ceiling modu): rangeNM icinde ceilingFt USTUNDE bir oyuncu
--    ("players") veya herhangi bir mavi ucak ("any") varsa, alcaktaki AI ucaklar
--    olsa bile ROE = HOLD ve radar = DARK. Sebep (dcs.log 19:06-19:11): AI mavi
--    ucaklar (FAC-1-1 21930 ft, INTER-2-4 8120 ft) kapiyi ve radari acti,
--    SA-6 23560 ft'teki oyuncuya atis yapti. highVeto yoksa eski davranis.
--    Bedel: yuksek bir oyuncu menzildeyken SAM alcak AI ucaklara da atis yapmaz.
--
-- v1.4.0:
--  * Radar kapisi (grup basina, opsiyonel): radarGateNM tanimli gruplarda Skynet
--    goLive() cagrilari VETO edilir; radar yalnizca uygun hedef radarGateNM
--    icindeyken acilir, radarGateNM + radarHysteresisNM disina cikinca kapanir
--    (goDark). radarTargets="low": sadece ceilingFt altindaki ucaklar radari
--    acar ("any": tum mavi ucaklar). Gate kapaliyken myIADS pop-up'i dahil hicbir
--    goLive radari acamaz. Otonom davranis DARK'a sabitlenir.
--  * "SAM BV22 (SA-6)-1" icin ceiling (22000 ft) + radar gate (10 NM) kurali.
--
-- v1.3.1:
--  * "SAM BV22 (SA-6)-1" icin ceiling kurali eklendi (22000 ft). Kod degisikligi yok,
--    sadece FIRE_GATE.groups girdisi.
--
-- v1.3.0:
--  * Grup basina kural yapisi (FIRE_GATE.groups artik tablo listesi).
--  * Yeni "ceiling" modu (SAM YE53 (SA-3)-1 icin, 22000 ft).
--  * playersOnly artik grup basina.
--  * SHOT logu hedefin adini ve irtifasini da yaziyor (weapon:getTarget).
--  * Opsiyonel filterShots (ceiling modu, varsayilan KAPALI): ceilingFt ustundeki
--    hedefe atilan fuzeyi yok eder. Karisik durum (alcak + yuksek ucak ayni
--    anda menzilde) icin yedek; ROE grup duzeyinde oldugu icin tek basina
--    hedef bazli ayirim yapamaz.
--
-- v1.2.0: playersOnly=true varsayilan, SHOT teshis logu.
-- v1.1.0: AI.Option.Air ROE sabitleri, Skynet goLive() sarmalama.

local FIRE_GATE = {
    pollInterval       = 1,      -- saniye
    includeHelicopters = true,
    airborneOnly       = true,   -- yerdeki ucaklar sayilmaz
    hookRetrySeconds   = 60,     -- redIADS / site hazir olana kadar bekleme suresi
    logShots           = true,
    logUngatedShots    = true,   -- kapi tanimsiz kirmizi birimlerin fuze atislarini da logla (sadece teshis)
    reassertSeconds    = 2,      -- radar gate durumunu bu aralikla yeniden uygula

    groups = {
        {
            name         = "SAM YD67 (SA-10)-1",
            mode         = "distance",
            gateNM       = 30,    -- bu mesafede veya icinde WEAPON_FREE
            hysteresisNM = 2,     -- HOLD'a donmek icin gateNM + hysteresisNM asilmali
            playersOnly  = true,
        },
        {
            name         = "SAM YE53 (SA-3)-1",
            mode         = "ceiling",
            ceilingFt    = 19000, -- MSL; bu irtifa ve altindaki ucak kapiyi acar
            hysteresisFt = 500,   -- FREE'de ceilingFt + hysteresisFt'e kadar tolerans
            rangeNM      = 25,    -- bu yaricap icindeki ucaklar degerlendirilir
            playersOnly  = false, -- AI mavi ucaklar da sayilir
            filterShots  = false, -- true: ceilingFt ustu hedefe giden fuzeyi yok et
            highVeto     = "players", -- "players" | "any" | false: yuksek ucak varsa HOLD (bkz. v1.5.0)
        },
        {
            name         = "SAM BV22 (SA-6)-1",
            mode         = "ceiling",
            ceilingFt    = 19000,
            hysteresisFt = 500,
            rangeNM      = 20,    -- TAHMIN: SA-6'nin DCS menzili dogrulanmadi; SHOT logundan ayarla
            playersOnly  = false,
            filterShots  = false,
            highVeto     = "players",
            radarGateNM       = 10,     -- radar bu mesafeden once acilmaz
            radarHysteresisNM = 2,      -- radar radarGateNM + 2 NM disinda kapanir
            radarTargets      = "low",  -- "low": sadece ceilingFt altindaki ucaklar radari acar; "any": hepsi
        },
        {
            name         = "SAM HS02 (SA-6)-1",
            mode         = "ceiling",
            ceilingFt    = 19000,
            hysteresisFt = 500,
            rangeNM      = 20,    -- TAHMIN: BV22 ile ayni; SA-6 menzili dogrulanmadi, SHOT logundan ayarla
            playersOnly  = false,
            filterShots  = false,
            highVeto     = "players",
        },
    },
}

local NM_TO_M = 1852
local FT_TO_M = 0.3048

-- Skynet ile ayni sabitler (Skynet bu degerlerle SAM controller'ini yonetiyor)
local ROE_ID   = AI.Option.Air.id.ROE
local ROE_HOLD = AI.Option.Air.val.ROE.WEAPON_HOLD
local ROE_FREE = AI.Option.Air.val.ROE.WEAPON_FREE

local gateState = {}  -- groupName -> "HOLD" | "FREE"
local byName    = {}  -- groupName -> cfg

for _, cfg in ipairs(FIRE_GATE.groups) do
    byName[cfg.name] = cfg
    if cfg.mode == "distance" then
        cfg.gateM    = cfg.gateNM * NM_TO_M
        cfg.releaseM = (cfg.gateNM + (cfg.hysteresisNM or 0)) * NM_TO_M
    elseif cfg.mode == "ceiling" then
        cfg.ceilingM = cfg.ceilingFt * FT_TO_M
        cfg.hystM    = (cfg.hysteresisFt or 0) * FT_TO_M
        cfg.rangeM   = cfg.rangeNM * NM_TO_M
    else
        env.info("[FIREGATE] unknown mode for '" .. tostring(cfg.name) .. "': " .. tostring(cfg.mode))
    end
    if cfg.radarGateNM then
        cfg.radarGateM    = cfg.radarGateNM * NM_TO_M
        cfg.radarReleaseM = (cfg.radarGateNM + (cfg.radarHysteresisNM or 0)) * NM_TO_M
        cfg.radarTargets  = cfg.radarTargets or "low"
    end
end

local radarState = {}  -- groupName -> "LIVE" | "DARK" (sadece radar gate'li gruplar)

----------------------------------------------------------------
-- Yardimcilar
----------------------------------------------------------------
local function toFt(m) return math.floor(m / FT_TO_M + 0.5) end

-- Havadaki tum mavi ucaklar (filtre grup basina uygulanir)
local function collectBlueAir()
    local pts = {}
    local cats = { Group.Category.AIRPLANE }
    if FIRE_GATE.includeHelicopters then
        table.insert(cats, Group.Category.HELICOPTER)
    end
    for _, cat in ipairs(cats) do
        local groups = coalition.getGroups(coalition.side.BLUE, cat) or {}
        for _, g in ipairs(groups) do
            local units = g:getUnits() or {}
            for _, u in ipairs(units) do
                if u:isExist() and u:isActive()
                   and (not FIRE_GATE.airborneOnly or u:inAir()) then
                    local p = u:getPoint()
                    pts[#pts + 1] = {
                        x = p.x, y = p.y, z = p.z,   -- y = MSL (m)
                        name = u:getName(),
                        player = u:getPlayerName(),
                    }
                end
            end
        end
    end
    return pts
end

local function filtered(pts, playersOnly)
    if not playersOnly then return pts end
    local out = {}
    for i = 1, #pts do
        if pts[i].player then out[#out + 1] = pts[i] end
    end
    return out
end

local function groupAnchor(group)
    local units = group:getUnits() or {}
    for _, u in ipairs(units) do
        if u:isExist() then
            return u:getPoint()
        end
    end
    return nil
end

local function horizDist(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- en yakin noktayi ve mesafeyi dondurur
local function nearest(anchor, pts)
    local best, bestPt = math.huge, nil
    for i = 1, #pts do
        local d = horizDist(pts[i], anchor)
        if d < best then best, bestPt = d, pts[i] end
    end
    return best, bestPt
end

local function describe(pt)
    if not pt then return "none" end
    return string.format("%s%s %d ft", tostring(pt.name),
        pt.player and (" [player: " .. tostring(pt.player) .. "]") or " [AI]",
        toFt(pt.y))
end

local function setROE(controller, state)
    controller:setOption(ROE_ID, (state == "HOLD") and ROE_HOLD or ROE_FREE)
end

----------------------------------------------------------------
-- Kararlar
----------------------------------------------------------------
local function decideDistance(cfg, anchor, pts, prev)
    local dist, near = nearest(anchor, filtered(pts, cfg.playersOnly))
    local new = prev
    if prev == "HOLD" and dist <= cfg.gateM then
        new = "FREE"
    elseif prev == "FREE" and dist > cfg.releaseM then
        new = "HOLD"
    end
    return new, string.format("nearest %.1f NM: %s", dist / NM_TO_M, describe(near))
end

-- thr ustundeki, rangeM icindeki veto edici ucak (playersOnly'den bagimsiz).
-- cfg.highVeto: "players" -> sadece oyuncu, "any" -> hepsi, nil/false -> veto yok.
local function highVetoTarget(cfg, anchor, pts, thr)
    if not cfg.highVeto then return nil end
    local best, bestD
    for i = 1, #pts do
        local a = pts[i]
        if a.y > thr and (cfg.highVeto == "any" or a.player) then
            local d = horizDist(a, anchor)
            if d <= cfg.rangeM and (not bestD or d < bestD) then best, bestD = a, d end
        end
    end
    return best, bestD
end

local function decideCeiling(cfg, anchor, pts, prev)
    local thr = cfg.ceilingM + ((prev == "FREE") and cfg.hystM or 0)
    local vt, vd = highVetoTarget(cfg, anchor, pts, thr)
    if vt then
        return "HOLD", string.format("VETO high %.1f NM: %s", vd / NM_TO_M, describe(vt))
    end
    local inRange, lowest, lowTarget, lowDist = 0, nil, nil, nil
    local list = filtered(pts, cfg.playersOnly)
    for i = 1, #list do
        local d = horizDist(list[i], anchor)
        if d <= cfg.rangeM then
            inRange = inRange + 1
            if not lowest or list[i].y < lowest.y then lowest = list[i] end
            if list[i].y <= thr and (not lowTarget or list[i].y < lowTarget.y) then
                lowTarget, lowDist = list[i], d
            end
        end
    end
    if lowTarget then
        return "FREE", string.format("low target %.1f NM: %s | %d in range",
            lowDist / NM_TO_M, describe(lowTarget), inRange)
    end
    if inRange == 0 then
        return "HOLD", "no blue aircraft in range"
    end
    return "HOLD", string.format("%d in range, all above %d ft, lowest: %s",
        inRange, cfg.ceilingFt, describe(lowest))
end

----------------------------------------------------------------
-- Radar kapisi
----------------------------------------------------------------
local function decideRadar(cfg, anchor, pts, prev)
    if cfg.ceilingM then
        local vthr = cfg.ceilingM + ((prev == "LIVE") and cfg.hystM or 0)
        local vt, vd = highVetoTarget(cfg, anchor, pts, vthr)
        if vt then
            return "DARK", string.format("VETO high %.1f NM: %s", vd / NM_TO_M, describe(vt))
        end
    end
    local thr = math.huge
    if cfg.radarTargets == "low" and cfg.ceilingM then
        thr = cfg.ceilingM + ((prev == "LIVE") and cfg.hystM or 0)
    end
    local limit = (prev == "LIVE") and cfg.radarReleaseM or cfg.radarGateM
    local list = filtered(pts, cfg.playersOnly)
    local best, bestD
    for i = 1, #list do
        local d = horizDist(list[i], anchor)
        if d <= limit and list[i].y <= thr and (not bestD or d < bestD) then
            best, bestD = list[i], d
        end
    end
    if best then
        return "LIVE", string.format("target %.1f NM: %s", bestD / NM_TO_M, describe(best))
    end
    return "DARK", string.format("no %s target within %.1f NM",
        (cfg.radarTargets == "low") and "eligible" or "blue", limit / NM_TO_M)
end

local function applyRadar(cfg, state)
    local site = cfg.site
    if not site or site:isDestroyed() then return end
    if state == "LIVE" then
        if cfg.origGoLive then cfg.origGoLive(site) end
    else
        site:goDark()
    end
end

local function evaluateRadar(cfg, anchor, pts)
    local name  = cfg.name
    local firstR = (radarState[name] == nil)
    local prevR = radarState[name] or "DARK"
    local newR, info = decideRadar(cfg, anchor, pts, prevR)
    local now = timer.getTime()

    if cfg.site and (newR ~= prevR or cfg.lastAssert == nil
                     or now - cfg.lastAssert >= FIRE_GATE.reassertSeconds) then
        local ok, err = pcall(applyRadar, cfg, newR)
        if not ok then env.info("[FIREGATE] radar apply error: " .. tostring(err)) end
        cfg.lastAssert = now
    end

    if firstR then
        env.info(string.format("[FIREGATE] '%s' RADAR init %s (%s)", name, newR, info))
    elseif newR ~= prevR then
        env.info(string.format("[FIREGATE] '%s' RADAR -> %s (%s)", name, newR, info))
    end
    radarState[name] = newR
end

-- force=true: durumdan bagimsiz ROE'yi yeniden yaz (goLive hook'u icin)
local function evaluate(cfg, pts, force)
    local name = cfg.name
    local group = Group.getByName(name)
    if not (group and group:isExist()) then return end
    local anchor = groupAnchor(group)
    local controller = group:getController()
    if not (anchor and controller) then return end

    local first = (gateState[name] == nil)
    local prev  = gateState[name] or "HOLD"
    local new, info
    if cfg.mode == "ceiling" then
        new, info = decideCeiling(cfg, anchor, pts, prev)
    else
        new, info = decideDistance(cfg, anchor, pts, prev)
    end

    -- HOLD'da her tick yeniden yaz: baska bir kod ROE'yi bozarsa en gec
    -- pollInterval icinde geri alinir. FREE'ye sadece gecis/force'ta yazilir.
    if force or new == "HOLD" or new ~= prev then
        setROE(controller, new)
    end

    if first then
        env.info(string.format("[FIREGATE] '%s' init state %s (%s)", name, new, info))
    elseif new ~= prev then
        env.info(string.format("[FIREGATE] '%s' -> %s (%s)", name, new, info))
    end
    gateState[name] = new

    if cfg.radarGateM then
        evaluateRadar(cfg, anchor, pts)
    end
end

----------------------------------------------------------------
-- Tick (geri plan)
----------------------------------------------------------------
local function gateTick()
    local pts = collectBlueAir()
    for _, cfg in ipairs(FIRE_GATE.groups) do
        evaluate(cfg, pts, false)
    end
end

local function gateLoop(_, t)
    local ok, err = pcall(gateTick)
    if not ok then
        env.info("[FIREGATE] tick error: " .. tostring(err))
    end
    return t + FIRE_GATE.pollInterval
end

timer.scheduleFunction(gateLoop, nil, timer.getTime() + 1)

----------------------------------------------------------------
-- SHOT teshis event'i (+ opsiyonel fuze filtresi)
----------------------------------------------------------------
local function weaponTarget(w)
    local ok, nm, y = pcall(function()
        local t = w:getTarget()
        if not t then return nil end
        return t:getName(), t:getPoint().y
    end)
    if ok then return nm, y end
    return nil
end

if FIRE_GATE.logShots then
    local handler = {}
    function handler:onEvent(e)
        local ok, err = pcall(function()
            if e.id ~= world.event.S_EVENT_SHOT then return end
            local ini = e.initiator
            if not ini then return end
            local grp = ini:getGroup()
            if not grp then return end
            local gname = grp:getName()
            local cfg = byName[gname]
            if not cfg then
                if FIRE_GATE.logUngatedShots and e.weapon
                   and ini:getCoalition() == coalition.side.RED then
                    local isMsl = false
                    pcall(function()
                        isMsl = (e.weapon:getDesc().category == Weapon.Category.MISSILE)
                    end)
                    if isMsl then
                        local okw, tn = pcall(function() return e.weapon:getTypeName() end)
                        local tname, talt = weaponTarget(e.weapon)
                        env.info(string.format(
                            "[FIREGATE] SHOT (ungated) by '%s' (group '%s') weapon=%s | target=%s %s",
                            ini:getName(), gname, okw and tostring(tn) or "?",
                            tostring(tname), talt and (toFt(talt) .. " ft") or "(alt n/a)"))
                    end
                end
                return
            end

            local p = ini:getPoint()
            local dist, near = nearest({ x = p.x, z = p.z },
                filtered(collectBlueAir(), cfg.playersOnly))

            local wname, tname, talt = "?", nil, nil
            if e.weapon then
                local okw, tn = pcall(function() return e.weapon:getTypeName() end)
                if okw then wname = tostring(tn) end
                tname, talt = weaponTarget(e.weapon)
            end

            env.info(string.format(
                "[FIREGATE] SHOT by '%s' (group '%s') weapon=%s | gate=%s radar=%s | target=%s %s | nearest %.1f NM: %s",
                ini:getName(), gname, wname, tostring(gateState[gname]), tostring(radarState[gname]),
                tostring(tname), talt and (toFt(talt) .. " ft") or "(alt n/a)",
                dist / NM_TO_M, describe(near)))

            if cfg.mode == "ceiling" and cfg.filterShots and e.weapon and talt
               and talt > cfg.ceilingM then
                local okd, derr = pcall(function() e.weapon:destroy() end)
                env.info(string.format("[FIREGATE] FILTER: weapon on '%s' (%d ft > %d ft) destroyed=%s",
                    tostring(tname), toFt(talt), cfg.ceilingFt, tostring(okd)))
                if not okd then env.info("[FIREGATE] destroy error: " .. tostring(derr)) end
            end
        end)
        if not ok then
            env.info("[FIREGATE] shot handler error: " .. tostring(err))
        end
    end
    world.addEventHandler(handler)
end

----------------------------------------------------------------
-- Skynet goLive hook
-- Skynet goLive() ROE'yi WEAPON_FREE yapiyor; hemen ardindan kurali uygula.
----------------------------------------------------------------
local pending = {}
for _, cfg in ipairs(FIRE_GATE.groups) do pending[cfg.name] = cfg end
local hookStart = nil

local function installHooks()
    hookStart = hookStart or timer.getTime()
    local timedOut = (timer.getTime() - hookStart) > FIRE_GATE.hookRetrySeconds

    if redIADS and redIADS.getSAMSiteByGroupName then
        for name, cfg in pairs(pending) do
            local site = redIADS:getSAMSiteByGroupName(name)
            if site and site.goLive then
                local orig = site.goLive
                cfg.site, cfg.origGoLive = site, orig
                site.goLive = function(self, ...)
                    -- once durumu tazele (radar gate karari guncel olsun)
                    pcall(evaluate, cfg, collectBlueAir(), false)
                    if cfg.radarGateM and radarState[name] ~= "LIVE" then
                        local now = timer.getTime()
                        if now - (cfg.lastVeto or -1e9) >= 30 then
                            cfg.lastVeto = now
                            env.info("[FIREGATE] '" .. name .. "' goLive VETO (radar gate closed)")
                        end
                        return
                    end
                    local r = orig(self, ...)
                    local ok, err = pcall(evaluate, cfg, collectBlueAir(), true)
                    if not ok then
                        env.info("[FIREGATE] hook error: " .. tostring(err))
                    end
                    return r
                end
                if cfg.radarGateM then
                    -- Baglanti kesilince Skynet'in kendi otonom (radari acan) davranisina dusmesin
                    pcall(function()
                        site:setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
                    end)
                end
                pending[name] = nil
                env.info("[FIREGATE] goLive hooked for '" .. name .. "'"
                    .. (cfg.radarGateM and " (radar gate ON)" or ""))
            end
        end
    elseif timedOut then
        env.info("[FIREGATE] redIADS:getSAMSiteByGroupName unavailable - tick only")
        return nil
    end

    if next(pending) == nil then return nil end
    if timedOut then
        for name in pairs(pending) do
            env.info("[FIREGATE] site not found, hook skipped (tick only): '" .. name .. "'")
        end
        return nil
    end
    return timer.getTime() + 1
end

timer.scheduleFunction(function(_, t)
    local ok, res = pcall(installHooks)
    if not ok then
        env.info("[FIREGATE] installHooks error: " .. tostring(res))
        return nil
    end
    return res
end, nil, timer.getTime() + 2)

env.info("[FIREGATE] v1.5.3 initialized for " .. #FIRE_GATE.groups .. " group(s)")
