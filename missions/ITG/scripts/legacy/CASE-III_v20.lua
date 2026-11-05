-- DEBUG: script load check
trigger.action.outText("CASE III v20 script loaded", 5)

----------------------------------------------------------------
-- TRT SYRIA RECOVERY FRAMEWORK
-- CASE I / CASE II / CASE III (Single Script)
-- v7 FIXED: Explicit 60NM activation (no airborne auto-start)
-- v16: IF alt/spd gate -> HOLD FIX geometri gate (DME/radyal), holding 90 s
--      kesintisiz + erken cikis cezasi, 12NM 1200 ft / 250 kts, inis cezasi.
----------------------------------------------------------------

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local PLAYER_NAME   = "Player_01"
local CARRIER       = "CVN"
local FLAG          = 1908
-- Players who can earn landing points (unit names in ME)
local PLAYER_NAMES = {
    "Player_01",
    "Player_02",
}


----------------------------------------------------------------
-- FLAG EVENTS (Refuel / Landing / Zones / Targets)
----------------------------------------------------------------
local FLAG_REFUEL_P1   = 2341
local FLAG_REFUEL_P2   = 2342
local FLAG_LAND_P1     = 2343
local FLAG_LAND_P2     = 2344

local FLAG_CONV3_P1    = 2443
local FLAG_CONV3_P2    = 2444
local FLAG_CONV6_P1    = 2446
local FLAG_CONV6_P2    = 2447

local FLAG_TRG1_DEAD   = 2541 -- STRIKE1_TRG1
local FLAG_TRG2_DEAD   = 2542 -- STRIKE1_TRG2

local function setFlagON(flagNum)
    trigger.action.setUserFlag(flagNum, 1)
end
-- Zones (Mission Editor'da AYNEN bu isimlerle olmalı)
local IF_ZONE          = "InitialFix_Zone"
local HOLD_ZONE        = "Holding_Zone"
local ZONE_12NM_CASE2  = "12NMa_Zone"
-- !! DIKKAT (v16): 12NM gate icin talep edilen zone "12NMa_Zone" idi, ama
-- CASE III bu satirdaki degeri kullaniyor. ME'de hangisi 346 radyalinda /
-- 12 NM'de duruyorsa onu yaz. Su an v15'teki deger korunuyor.
local ZONE_12NM_CASE3  = "12NMb_Zone"
local ZONE_10NM        = "10NM_Zone"
local DEP_7NM_ZONE     = "7NM_Departure_Zone" -- sadece görsel, logic mesafe bazlı

-- CASE PROFILE SELECTOR (ONLY ONE TRUE)
local CASE_I_ENABLED   = false
local CASE_II_ENABLED  = false
local CASE_III_ENABLED = true

----------------------------------------------------------------
-- GLOBAL STATE
----------------------------------------------------------------
RECOVERY_ACTIVE = false
CASE_PHASE      = "NONE"     -- "NONE","ACTIVE","DEPARTURE","IF","HOLD","ARC12","TEN","FB","GROOVE","DONE"
BANKLER_MERGED  = false

----------------------------------------------------------------
-- SAFETY: ensure exactly one CASE enabled
----------------------------------------------------------------
do
    local n = 0
    if CASE_I_ENABLED then n = n + 1 end
    if CASE_II_ENABLED then n = n + 1 end
    if CASE_III_ENABLED then n = n + 1 end
    if n ~= 1 then
        trigger.action.outText("CASE CONFIG ERROR: enable exactly ONE of CASE I/II/III", 30, true)
    end
end

----------------------------------------------------------------
-- SCORE
----------------------------------------------------------------
-- v18: her puan degisiminde tek tip, Ingilizce bilgi mesaji.
-- Format:  SCORE +5  |  <reason>  |  TOTAL: 42
local SCORE_MSG_SEC = 10

local function addScore(delta, reason)
    local cur = trigger.misc.getUserFlag(FLAG) or 0
    local new = cur + delta
    trigger.action.setUserFlag(FLAG, new)

    local sign = (delta >= 0) and string.format("+%d", delta) or string.format("%d", delta)
    trigger.action.outText(
        string.format("SCORE %s  |  %s  |  TOTAL: %d", sign, tostring(reason), new),
        SCORE_MSG_SEC
    )
    env.info(string.format("[CASE-III v18] SCORE %s | %s | TOTAL %d", sign, tostring(reason), new))
end

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
local function uPlayer()
    return Unit.getByName(PLAYER_NAME)
end

local function uCarrier()
    return Unit.getByName(CARRIER)
end

local function isTrackedPlayer(name)
    for _, n in ipairs(PLAYER_NAMES) do
        if name == n then return true end
    end
    return false
end

local function altFt(u)
    if not u or not u:isExist() then return 0 end
    local p = u:getPoint()
    return (p and p.y or 0) * 3.28084
end

-- Horizontal ground speed (X/Z only)
local function spdKts(u)
    if not u or not u:isExist() then return 0 end
    local v = u:getVelocity()
    if not v then return 0 end
    return math.sqrt((v.x or 0)^2 + (v.z or 0)^2) * 1.94384
end

----------------------------------------------------------------
-- ZONE MEMBERSHIP HELPER
-- v15 FIX: Bu fonksiyon v14'te HIC TANIMLI DEGILDI ama 7 yerde
-- cagriliyordu (v14 satirlari: 141, 151, 305, 529, 548, 576, 673).
-- Lua'da tanimsiz global cagirmak
--   "attempt to call global 'inZone' (a nil value)"
-- hatasi firlatir. Hata bir timer.scheduleFunction zinciri icinde
-- olustugu icin fonksiyon bir sonraki calisma zamanini donduremeden
-- oluyordu ve O ZINCIR BIR DAHA HIC CALISMIYORDU.
--
--   dcs.log kaniti:
--     10:17:01  CASE-III_v14.lua:305  (inAnyRefuelZone <- updatePlayerZoneRefuel)
--     10:27:01  CASE-III_v14.lua:305  (mission restart, ayni yer)
--     10:45:23  CASE-III_v14.lua:529  (updateCASEII)
--   305 mission basinda patliyordu -> refuel puanlamasi hic calismadi.
--
-- Imza (u, zoneName) seklinde; tum mevcut cagrilar buna uyuyor.
-- (Flaggers_v1.lua'daki pointInZone(point, zone) farkli imzaya sahip
--  oldugu icin dogrudan kopyalanamazdi.)
----------------------------------------------------------------
local warnedZones = {}

local function inZone(u, zoneName)
    if not u or not u:isExist() then return false end
    if not zoneName then return false end

    local z = trigger.misc.getZone(zoneName)
    if not z or not z.point or not z.radius then
        -- Zone ME'de yoksa / isim yanlissa: false don, ama zone basina bir kez uyar.
        if not warnedZones[zoneName] then
            warnedZones[zoneName] = true
            env.warning("[CASE-III v15] inZone: zone bulunamadi -> " .. tostring(zoneName))
        end
        return false
    end

    local p = u:getPoint()
    if not p then return false end

    local dx = p.x - z.point.x
    local dz = p.z - z.point.z
    return (dx * dx + dz * dz) <= (z.radius * z.radius)
end

local PLAYER_NAMES = {
    "Player_01",
    "Player_02",
}


----------------------------------------------------------------
-- ZONE ENTRY FLAGS (Conversation_3 / Conversation_6)
----------------------------------------------------------------
local zoneFlagDone = {
    ["Player_01"] = { conv3 = false, conv6 = false },
    ["Player_02"] = { conv3 = false, conv6 = false },
}

local function updateConversationZoneFlags()
    for _, pname in ipairs(PLAYER_NAMES) do
        local u = Unit.getByName(pname)
        if u and u:isExist() then
            -- Conversation_3
            if not zoneFlagDone[pname].conv3 and inZone(u, "Conversation_3") then
                zoneFlagDone[pname].conv3 = true
                if pname == "Player_01" then
                    setFlagON(FLAG_CONV3_P1)
                elseif pname == "Player_02" then
                    setFlagON(FLAG_CONV3_P2)
                end
            end

            -- Conversation_6
            if not zoneFlagDone[pname].conv6 and inZone(u, "Conversation_6") then
                zoneFlagDone[pname].conv6 = true
                if pname == "Player_01" then
                    setFlagON(FLAG_CONV6_P1)
                elseif pname == "Player_02" then
                    setFlagON(FLAG_CONV6_P2)
                end
            end
        end
    end
end

local function distToCarrierNm(u, c)
    if not u or not u:isExist() or not c or not c:isExist() then return 99999 end
    local pu, pc = u:getPoint(), c:getPoint()
    if not pu or not pc then return 99999 end
    return ((((pu.x - pc.x)^2 + (pu.z - pc.z)^2)^0.5) / 1852)
end

local function clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

----------------------------------------------------------------
-- IFEI BRIGHTNESS CONFIRM (RADIO COMMAND)
----------------------------------------------------------------
local IFEI_DONE = false

do
    local function confirmIFEI()
        if IFEI_DONE then return end
        IFEI_DONE = true
        addScore(1, "IFEI brightness set (~10%)")
    end

    missionCommands.addCommandForCoalition(
        coalition.side.BLUE,
        "IFEI brightness set",
        nil,
        confirmIFEI
    )
end

-- Dummy (önceki kırpma faciasının intikamı: artık nil yok)
local function updateIFEI(_u)
    -- IFEI radio ile one-shot confirm ediliyor; loop'ta iş yok
end

----------------------------------------------------------------
-- GLOBAL: 60NM WARNING (independent, DISABLED BY DEFAULT)
----------------------------------------------------------------
local WARN60_ENABLED = false   -- <<< HERE Activate/Deactivate
local WARN60_DONE    = false

local function updateFarWarning(u)
    if not WARN60_ENABLED then return end
    if WARN60_DONE then return end

    local c = uCarrier()
    if not c or not c:isExist() then return end

    local d = distToCarrierNm(u, c)
    if d >= 60 then
        WARN60_DONE = true
        trigger.action.outText(
            "WARNING: 60 NM from mother. You're out in the weeds.",
            10
        )
    end
end

----------------------------------------------------------------
-- FUEL & GROSS WEIGHT MODULE (v18)
--
-- v16'daki "GROOVE FUEL SCORING" bloguu kaldirildi (frac * 11000 ile
-- kaba yakit tahmini yapiyordu).
--
-- OLCUM SINIRI: DCS scripting API'sinde gross weight donduren fonksiyon
-- YOKTUR. getAmmo() sadece mermi/bomba SAYISI verir, kutle vermez; pod,
-- pilon, rack ve dis tanklari HIC raporlamaz. Bu yuzden agirlik su
-- modelle takip ediliyor:
--
--   GW = EMPTY_MASS_LB + fuelLbs() + storesLbs()
--
--   EMPTY_MASS_LB : ME'den okunan sabit (getDesc().massEmpty DEGIL - bkz. not)
--   fuelLbs()     : getFuel() * FUEL_INTERNAL_MAX_LB  (ic + dis tank yakiti)
--   storesLbs()   : INITIAL_STORES_LB eksi harcanan muhimmat kutlesi
--
-- Yani stores "sifirdan toplanmiyor", bilinen bir baslangic degerinden
-- DUSULUYOR. Boylece tablodaki bosluklar (pod, pilon, rack) hatayi
-- buyutmuyor; sadece harcanan muhimmatin kutlesini bilmek yetiyor.
----------------------------------------------------------------

----------------------------------------------------------------
-- ME'DEN ALINAN COLD START REFERANSI (Player_01)
--   Empty                     25093 lb
--   Total fuel (ic + 2 tank)  15291 lb
--   Stores (silah+pod+rack+bos tank)  8076 lb
--   TOTAL                     48460 lb
--
-- NOT 1 - EMPTY_MASS_LB neden sabit:
--   getDesc().massEmpty F/A-18C icin 10455 kg = 23049 lb donduruyor.
--   ME'nin gosterdigi 25093 lb ile arada 2044 lb fark var (pilot, top
--   mermisi, yag vb. muhtemelen ME tarafinda dahil). Bu yuzden getDesc()
--   KULLANILMIYOR, asagidaki sabit kullaniliyor.
--
-- NOT 2 - FUEL_INTERNAL_MAX_LB (kokpitte kalibre edildi):
--   getFuel() IC yakitin kesrini dondurur ve dis tank varsa 1.0'i asar.
--   Cold start olcumu: getFuel = 1.4155.
--     15291 / 1.4155 = 10802.5 lb  ->  4900 kg x 2.20462 = 10802.6 lb
--   Yani ic kapasite 4900 kg. Ilk tahmin olan 10780 lb (4890 kg) yakiti
--   32 lb eksik gosteriyordu (gross'un %0.07'si). Duzeltildi.
--   Dis yakit: 15291 - 10803 = 4488 lb, tank basina 2244 lb;
--   330 galon x 6.8 lb/gal ile tutarli.
----------------------------------------------------------------
local EMPTY_MASS_LB        = 25093
local FUEL_INTERNAL_MAX_LB = 10802.6
local INITIAL_STORES_LB    = 8076
local COLDSTART_TOTAL_LB   = 48460   -- sadece dogrulama ciktisi icin

-- Harcanabilir muhimmat kutleleri (lb/adet). SIRALI liste: ilk eslesen
-- kazanir, o yuzden ozel olan once yazilir.
--
-- Eslestirme NORMALIZE edilerek yapilir: hem tablodaki desen hem de
-- getAmmo()'dan gelen typeName+displayName kucuk harfe cevrilip harf/rakam
-- disindaki her sey atilir. Boylece
--   "GBU-31(V)2"  ->  "gbu31v2"
--   "weapons.bombs.GBU_31_V_2B|GBU-31(V)2/B"  ->  "weaponsbombsgbu31v2bgbu31v2b"
-- eslesir ve DCS'in tam typeName string'ini bilmek gerekmez.
--
-- Pod / pilon / rack / bos tank buraya YAZILMAZ: onlar INITIAL_STORES_LB
-- icinde zaten var ve harcanmiyorlar.
local STORE_MASS_LB = {
    { "GBU-31(V)2", 2059 },
    { "GBU-31",     2059 },
    { "AIM-120C",    357 },
    { "AIM-120",     357 },
    { "AIM-9X",      188 },
    { "AIM-9",       188 },
}

-- ESIKLER
local COMMENCE_MIN_FUEL_LB = 5000    -- commence aninda alt sinir (uyari)
local COMMENCE_WARN_GW_LB  = 34000   -- commence aninda uyari esigi
local MAX_TRAP_WEIGHT_LB   = 33000   -- F/A-18C max trap weight

local LAND_MIN_FUEL_LB     = 3000    -- touchdown yakit cezasi esigi
local LAND_FUEL_PENALTY    = -7
local LAND_WEIGHT_OK       =  5      -- GW < 33000
local LAND_WEIGHT_OVER     = -5      -- 33000 <= GW <= 34000
local LAND_WEIGHT_HEAVY    = -10     -- GW > 34000

-- Recovery tanker bilgisi (uyari metninde kullanilir)
local TANKER_CALLSIGN = "ARCO-5-1"
local TANKER_FREQ     = "252.5"
local TANKER_TACAN    = "25Y"

-- Modul durumu
local WF = {
    commenceDone = false,   -- commence uyarilari bir kez verildi mi
    landDone     = false,   -- touchdown puanlamasi bir kez yapildi mi
    baseAmmo     = nil,     -- cold start muhimmat sayimi
}

local unknownStores = {}

----------------------------------------------------------------
-- YAKIT
----------------------------------------------------------------
local function fuelLbs(u)
    if not u or not u:isExist() then return nil end
    local frac = u:getFuel()
    if type(frac) ~= "number" then return nil end
    return frac * FUEL_INTERNAL_MAX_LB
end

----------------------------------------------------------------
-- MUHIMMAT
----------------------------------------------------------------
-- Eslestirme icin sadelestirme: kucuk harf + yalniz harf/rakam.
local function normKey(s)
    return (tostring(s):lower():gsub("[^%w]", ""))
end

-- getAmmo()'yu { anahtar = adet } tablosuna indirger.
-- Anahtar = typeName .. "|" .. displayName (ikisi de eslestirmede kullanilir).
local function ammoCounts(u)
    if not u or not u:isExist() then return nil end
    local ok, ammo = pcall(function() return u:getAmmo() end)
    if not ok or type(ammo) ~= "table" then return nil end

    local t = {}
    for _, e in pairs(ammo) do
        if type(e) == "table" and e.count and e.desc then
            local tn = e.desc.typeName or ""
            local dn = e.desc.displayName or ""
            if tn ~= "" or dn ~= "" then
                local key = tn .. "|" .. dn
                t[key] = (t[key] or 0) + e.count
            end
        end
    end
    return t
end

-- Anahtara karsilik gelen birim kutle. Bulunamazsa nil.
local function massForKey(key)
    local nk = normKey(key)
    for _, row in ipairs(STORE_MASS_LB) do
        if string.find(nk, normKey(row[1]), 1, true) then return row[2] end
    end
    return nil
end

-- Ekranda gosterilecek kisa ad (displayName varsa o).
local function prettyKey(key)
    local dn = tostring(key):match("|(.*)$")
    if dn and dn ~= "" then return dn end
    return tostring(key)
end

-- Kalan stores kutlesi: baslangictan harcanani dus.
--
-- v20 KRITIK DUZELTME:
-- v19'da WF.baseAmmo TEMBEL yakalaniyordu; ilk storesLbs() cagrisinda
-- ne varsa o baseline oluyordu. storesLbs() ise sadece WEIGHT CHECK,
-- commence ve inis anlarinda cagriliyordu. Yani oyuncu WEIGHT CHECK'i
-- bombalari BIRAKTIKTAN sonra ilk kez calistirdiysa baseline bombasiz
-- yakalaniyor, harcanan = 0 kaliyor ve stores sonsuza kadar 8076'da
-- takiliyordu.
--   Saha kaydi: commence'te GW 38519 = 25093 + 5350 + 8076.
--   Iki GBU-31 birakilmisti, stores 3958 olmaliydi -> 4118 lb fazla.
-- v20'de baseline artik misyon basinda zamanlayiciyla yakalaniyor
-- (bkz. asagidaki captureBaseline dongusu) ve rearm durumu da islenir.
local function storesLbs(u)
    local now = ammoCounts(u)
    if not now then return INITIAL_STORES_LB, {} end

    if not WF.baseAmmo then
        WF.baseAmmo = now
        return INITIAL_STORES_LB, {}
    end

    -- Rearm / yeniden yukleme: sayim baseline'i asarsa baseline'i yukselt.
    for key, cnt in pairs(now) do
        local b = WF.baseAmmo[key]
        if not b or cnt > b then WF.baseAmmo[key] = cnt end
    end

    local spent, unknown = 0, {}
    for key, baseCount in pairs(WF.baseAmmo) do
        local nowCount = now[key] or 0
        local used = baseCount - nowCount
        if used > 0 then
            local m = massForKey(key)
            if m then
                spent = spent + (used * m)
            else
                unknown[#unknown + 1] = string.format("%s x%d expended", prettyKey(key), used)
                if not unknownStores[key] then
                    unknownStores[key] = true
                    env.warning("[CASE-III v18] STORE_MASS_LB'de yok, 0 lb sayildi: " .. tostring(key))
                end
            end
        end
    end

    local remaining = INITIAL_STORES_LB - spent
    if remaining < 0 then remaining = 0 end
    return remaining, unknown
end

-- Tahmini gross weight, lb.
local function grossWeightLbs(u)
    if not u or not u:isExist() then return nil end
    local f = fuelLbs(u)
    if not f then return nil end
    local st = storesLbs(u)
    return EMPTY_MASS_LB + f + st
end

----------------------------------------------------------------
-- MUHIMMAT BASELINE'INI MISYON BASINDA YAKALA (v20)
-- Oyuncunun WEIGHT CHECK calistirmasina bagli kalmadan, unit var olur
-- olmaz baseline'i al. Basarili olunca dongu kendini durdurur.
----------------------------------------------------------------
timer.scheduleFunction(function()
    if WF.baseAmmo then return nil end

    local u = Unit.getByName(PLAYER_NAME)
    if u and u:isExist() then
        local now = ammoCounts(u)
        if now then
            WF.baseAmmo = now
            local n = 0
            for _ in pairs(now) do n = n + 1 end
            env.info(string.format(
                "[CASE-III v20] ammo baseline captured: %d entry, stores %.0f lbs",
                n, INITIAL_STORES_LB))
            return nil
        end
    end

    return timer.getTime() + 2
end, nil, timer.getTime() + 2)

----------------------------------------------------------------
-- F10 > WEIGHT CHECK : kalibrasyon / dogrulama komutu
-- Cold start'ta calistir: GROSS 48460 lb okumali.
----------------------------------------------------------------
do
    local function weightCheck()
        local u = Unit.getByName(PLAYER_NAME)
        if not u or not u:isExist() then
            trigger.action.outText("WEIGHT CHECK: " .. PLAYER_NAME .. " not available.", 8)
            return
        end

        local f           = fuelLbs(u) or 0
        local st, unknown = storesLbs(u)
        local gw          = EMPTY_MASS_LB + f + st
        local frac        = u:getFuel() or 0

        local txt = string.format(
            "WEIGHT CHECK (estimate)\n"
            .. "Empty   : %7.0f lbs\n"
            .. "Fuel    : %7.0f lbs   (getFuel = %.4f)\n"
            .. "Stores  : %7.0f lbs   (start %.0f lbs)\n"
            .. "GROSS   : %7.0f lbs   (max trap %.0f lbs)\n"
            .. "Cold start reference: %.0f lbs",
            EMPTY_MASS_LB, f, frac, st, INITIAL_STORES_LB,
            gw, MAX_TRAP_WEIGHT_LB, COLDSTART_TOTAL_LB)

        if #unknown > 0 then
            txt = txt .. "\nUNKNOWN expended stores (0 lbs assumed):\n  "
                .. table.concat(unknown, "\n  ")
        end

        trigger.action.outText(txt, 30)
        env.info("[CASE-III v18] " .. txt)
    end

    missionCommands.addCommandForCoalition(
        coalition.side.BLUE,
        "WEIGHT CHECK",
        nil,
        weightCheck
    )
end



----------------------------------------------------------------
-- COMMENCE ADVISORIES (puan yok, sadece ikaz)
-- Holding degerlendirmesi kapandigi an, yani 10.000 ft'ten 1200 ft'e
-- inisin baslayacagi noktada bir kez calisir.
----------------------------------------------------------------
local function runCommenceAdvisories(u)
    if WF.commenceDone then return end
    if not u or not u:isExist() then return end
    WF.commenceDone = true

    local f  = fuelLbs(u)
    local gw = grossWeightLbs(u)

    trigger.action.outText("COMMENCE: descend to 1,200 ft.", 8)

    if f and f < COMMENCE_MIN_FUEL_LB then
        trigger.action.outText(string.format(
            "FUEL ADVISORY: %.0f lbs on board, below the %.0f lbs commence minimum.\n"
            .. "Proceed to recovery tanker %s - %s MHz - TACAN %s.",
            f, COMMENCE_MIN_FUEL_LB, TANKER_CALLSIGN, TANKER_FREQ, TANKER_TACAN), 20)
    elseif f then
        trigger.action.outText(string.format("Fuel state at commence: %.0f lbs.", f), 8)
    end

    -- v20: agirlik dokumu de basilir, boylece stores hatasi gorunur olur.
    do
        local st, unk = storesLbs(u)
        local line = string.format("Weight at commence: %.0f lbs (empty %.0f + fuel %.0f + stores %.0f)",
            (gw or 0), EMPTY_MASS_LB, (f or 0), st)
        if #unk > 0 then
            line = line .. "\nUNKNOWN expended stores (0 lbs assumed): " .. table.concat(unk, ", ")
        end
        trigger.action.outText(line, 12)
    end

    if gw and gw >= COMMENCE_WARN_GW_LB then
        trigger.action.outText(string.format(
            "WEIGHT ADVISORY: estimated gross weight %.0f lbs.\n"
            .. "F/A-18C max trap weight is %.0f lbs. Dump fuel or jettison stores before the ball.",
            gw, MAX_TRAP_WEIGHT_LB), 20)
    end
end

----------------------------------------------------------------
-- TOUCHDOWN FUEL / WEIGHT SCORING (ONE-SHOT, Player_01)
----------------------------------------------------------------
local function scoreLandingFuelWeight(u)
    if WF.landDone then return end
    if not u or not u:isExist() then return end
    WF.landDone = true

    local f  = fuelLbs(u)
    local gw = grossWeightLbs(u)

    do
        local st, unk = storesLbs(u)
        local line = string.format("Weight at trap: %.0f lbs (empty %.0f + fuel %.0f + stores %.0f)",
            (gw or 0), EMPTY_MASS_LB, (f or 0), st)
        if #unk > 0 then
            line = line .. "\nUNKNOWN expended stores (0 lbs assumed): " .. table.concat(unk, ", ")
        end
        trigger.action.outText(line, 12)
    end

    -- Yakit cezasi
    if f then
        if f < LAND_MIN_FUEL_LB then
            addScore(LAND_FUEL_PENALTY, string.format(
                "Trapped below minimum fuel state: %.0f lbs (minimum %.0f lbs)",
                f, LAND_MIN_FUEL_LB))
        else
            trigger.action.outText(string.format("Fuel at trap: %.0f lbs.", f), 8)
        end
    end

    -- Agirlik puanlamasi
    if gw then
        if gw < MAX_TRAP_WEIGHT_LB then
            addScore(LAND_WEIGHT_OK, string.format(
                "Trapped under max trap weight: %.0f lbs (limit %.0f lbs)",
                gw, MAX_TRAP_WEIGHT_LB))
        elseif gw <= COMMENCE_WARN_GW_LB then
            addScore(LAND_WEIGHT_OVER, string.format(
                "Trapped over max trap weight: %.0f lbs (limit %.0f lbs)",
                gw, MAX_TRAP_WEIGHT_LB))
        else
            addScore(LAND_WEIGHT_HEAVY, string.format(
                "Trapped heavily over max trap weight: %.0f lbs (limit %.0f lbs)",
                gw, MAX_TRAP_WEIGHT_LB))
        end
    end
end

----------------------------------------------------------------
-- REFUEL SCORING (PLAYER ZONE-BASED + AI TREND-BASED, EVENT-INDEPENDENT)
----------------------------------------------------------------
local REFUEL_UNITS = {}
local lastFuel, baseline, rewarded = {}, {}, {}

-- Player zone refuel gate
local PLAYER_REFUEL_ZONES = {
    "TANKER_1_SAFE_ZONE",
    "TANKER_2_SAFE_ZONE",
    "TANKER_5_SAFE_ZONE"
}
local playerRefuel = {
    inZone   = false,
    baseline = nil,
    done     = false
}

timer.scheduleFunction(function()
    local groups = coalition.getGroups(coalition.side.BLUE, Group.Category.AIRPLANE) or {}
    for _, g in ipairs(groups) do
        for _, u in ipairs(g:getUnits() or {}) do
            if u and u:isExist() then
                local n = u:getName()
                if n then REFUEL_UNITS[n] = true end
            end
        end
    end
    return timer.getTime() + 10
end, nil, timer.getTime() + 1)

local function inAnyRefuelZone(u)
    for _, zn in ipairs(PLAYER_REFUEL_ZONES) do
        if inZone(u, zn) then
            return true
        end
    end
    return false
end

local function updatePlayerZoneRefuel()
    if playerRefuel.done then return end

    local u = Unit.getByName(PLAYER_NAME)
    if not u or not u:isExist() then return end

    local f = u:getFuel()
    if not f then return end

    local inside = inAnyRefuelZone(u)

    -- Zone entry -> capture baseline
    if inside and not playerRefuel.inZone then
        playerRefuel.inZone   = true
        playerRefuel.baseline = f
        return
    end

    -- Zone exit -> reset
    if not inside and playerRefuel.inZone then
        playerRefuel.inZone   = false
        playerRefuel.baseline = nil
        return
    end

    -- While inside: +20% from entry baseline -> reward (one-shot)
    if inside and playerRefuel.baseline and (f - playerRefuel.baseline) >= 0.2 then
        playerRefuel.done = true
        addScore(7, "Aerial Refuel Complete: " .. PLAYER_NAME)

        -- FLAG: Player_01 refuel success
        -- v15: sadece girinti duzeltildi. Bu blok v14'te de zaten dis if'in
        -- icindeydi; girinti yanlis oldugu icin disaridaymis gibi gorunuyordu.
        if PLAYER_NAME == "Player_01" then
            setFlagON(FLAG_REFUEL_P1)
        end
    end
end

timer.scheduleFunction(function()
    -- PLAYER (zone-based, deterministic)
    updatePlayerZoneRefuel()

    -- AI (trend-based, original logic; excludes player)
    for name in pairs(REFUEL_UNITS) do
        if name ~= PLAYER_NAME then
            local u = Unit.getByName(name)
            if u and u:isExist() then
                local f = u:getFuel()
                if f then
                    if lastFuel[name] == nil then
                        lastFuel[name] = f
                        baseline[name] = nil
                        rewarded[name] = false
                    else
                        local df = f - lastFuel[name]

                        -- fuel decreasing -> reset cycle
                        if df < -0.005 then
                            baseline[name] = nil
                            rewarded[name] = false
                        end

                        -- first positive trend -> capture baseline
                        if df > 0 and not baseline[name] then
                            baseline[name] = lastFuel[name]
                        end

                        -- +3% from baseline -> reward
                        if baseline[name] and not rewarded[name] and (f - baseline[name]) >= 0.03 then
                            rewarded[name] = true
                            addScore(7, "Aerial Refuel Complete: " .. name)

                -- FLAG: Player_02 refuel success (if applicable)
                if name == "Player_02" then
                    setFlagON(FLAG_REFUEL_P2)
                end
                        end

                        lastFuel[name] = f
                    end
                end
            end
        end
    end
    return timer.getTime() + 1
end, nil, timer.getTime() + 1)

-- Reset on takeoff (new sortie / new cycle)
do
    local REH = {}
    function REH:onEvent(e)
        if not e or not e.initiator then return end
        if e.id ~= world.event.S_EVENT_TAKEOFF then return end

        local u = e.initiator
        if not u or not u.getName then return end
        local n = u:getName()
        if not n then return end

        -- Player: clear zone gate for a fresh refuel later
        if n == PLAYER_NAME then
            playerRefuel.inZone   = false
            playerRefuel.baseline = nil
            playerRefuel.done     = false
        end

        -- AI: clear trend trackers for that unit
        lastFuel[n] = nil
        baseline[n] = nil
        rewarded[n] = false
    end
    world.addEventHandler(REH)
end
----------------------------------------------------------------
-- DEAD SCORING TABLE (FULL)
----------------------------------------------------------------
local DEAD_SCORES = {

    ["SAM 15 (8-13-15-19)-1"] = 10, 
    ["SAM 15 (8-13-15-19)-2"] = 9, 
    ["SAM 15 (8-13-15-19)-3"] = 8,
    ["SAM 15 (8-13-15-19)-4"] = 7,
    ["SAM 7 (13)-1"] = 5,
    ["SAM 7 (13)-2"] = 7,

    ["POPUP_TARGET1"] = 9, ["STRIKE1_TRG2"]  = 9,
    ["AKROTIRI_Chemical_Factory"] = 10, ["STRIKE1_TRG1"] = 10,

    ["TANKER-1-1"] = -8, ["TANKER-2-1"] = -8, ["TANKER-3-1"] = -8, ["TANKER-4-1"] = -8,
    ["ARCO-5-1"]   = -8, ["TANKER-6-1"] = -8,

    ["MAGIC-2-1"]    = -10,
    ["OVERLORD-1-1"] = -10,
}

do
    local deadHandled = {}
    local DEH = {}

    function DEH:onEvent(e)
        if not e or e.id ~= world.event.S_EVENT_DEAD then return end
        local tgt = e.initiator
        if not tgt or not tgt.getName then return end

        local unitName = tgt:getName()
        if not unitName or deadHandled[unitName] then return end

        local delta = DEAD_SCORES[unitName]

        -- Prefix fallback
        if not delta then
            for key, val in pairs(DEAD_SCORES) do
                if string.find(unitName, key, 1, true) == 1 then
                    delta = val
                    break
                end
            end
        end
        if not delta then return end

        deadHandled[unitName] = true
        -- SPECIAL FLAGS: strike targets
                if unitName == "STRIKE1_TRG1" then
                    setFlagON(FLAG_TRG1_DEAD)
                elseif unitName == "STRIKE1_TRG2" then
                    setFlagON(FLAG_TRG2_DEAD)
                end

                addScore(delta, "TARGET DESTROYED: " .. unitName)
    end

    world.addEventHandler(DEH)
end

----------------------------------------------------------------
-- CASE II / CASE III CHART MODULE (IF + HOLD + 12NM)
----------------------------------------------------------------

----------------------------------------------------------------
-- v16 PARAMETRELERI (hepsi burada, tolerans ayari icin tek yer)
----------------------------------------------------------------
-- 1) HOLD FIX geometrisi (CVN -> Player radyali + DME)
local HOLDFIX_DME_NM     = 25    -- NM
local HOLDFIX_DME_TOL    = 2     -- +/- NM
local HOLDFIX_RADIAL_DEG = 195   -- derece (magnetic)
local HOLDFIX_RADIAL_TOL = 5     -- +/- derece

-- Grid -> Magnetic offset. Carrier_Geometry_v1.lua ile AYNI olmali.
local MAGVAR_DEG         = -5

-- 2) Holding suresi
local HOLD_MIN_SEC       = 90    -- saniye, kesintisiz

-- 3) 12NM gate parametreleri
local ZONE12_ALT_TARGET  = 1200  -- ft
local ZONE12_ALT_TOL     = 100   -- +/- ft
local ZONE12_SPD_TARGET  = 250   -- kts
local ZONE12_SPD_TOL     = 15    -- +/- kts
-- NOT: 346 final bearing AYRICA olculmuyor. 12NMb_Zone ME'de o hizaya
-- yerlestirildigi icin zone'a girmek hizayi tutturmus saymak demek.
-- Kontrol edilen tek sey: giris anindaki irtifa ve hiz.

-- 4) Inis cezasi (adim 1 + adim 2 tamamlanmadan inildiyse)
local LANDING_MISS_PENALTY = -5

----------------------------------------------------------------
-- GEOMETRI YARDIMCILARI
----------------------------------------------------------------
-- En kisa isaretli acisal fark, (-180, 180]. Wrap-safe.
local function angleDiff(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end

-- CVN -> unit radyali, 0-360, TACAN "from station" konvansiyonu.
-- Carrier_Geometry_v1.lua'daki radialDeg() ile ayni matematik.
local function radialFromCarrier(c, u)
    local p1, p2 = c:getPoint(), u:getPoint()
    if not p1 or not p2 then return nil end
    local dx = p2.x - p1.x -- kuzey bileseni
    local dz = p2.z - p1.z -- dogu bileseni
    return (math.deg(math.atan2(dz, dx)) + MAGVAR_DEG) % 360
end

-- CASE II / III shared state
local CASE2 = {
    fixHit     = false,  -- DME/radyal toleransi icinde en az bir kez yakalandi mi
    fixDone    = false,  -- adim 1 puanlandi mi (one-shot)
    bestMiss   = nil,    -- fix noktasina en yakin gecis mesafesi (NM)
    bestDme    = nil,    -- o andaki DME
    bestRad    = nil,    -- o andaki radyal
    fixPassed  = false,  -- adim 1 basarili miydi
    holdEnter  = nil,    -- Holding_Zone'a giris zamani
    holdDone   = false,  -- adim 2 puanlandi mi (one-shot)
    holdPassed = false,  -- adim 2 basarili miydi
    nm12Done   = false,  -- adim 3 puanlandi mi (one-shot)
}

----------------------------------------------------------------
-- F10 > FIX CHECK (v19)
-- Script'in hesapladigi DME/radyali ekrana basar. Kokpit HSI'daki
-- TACAN bearing/DME ile karsilastir:
--   HSI bearing TO station = X  ->  radyal FROM station = X +/- 180
-- Ikisi 1-2 dereceden fazla ayrisiyorsa MAGVAR_DEG yanlistir.
----------------------------------------------------------------
do
    local function fixCheck()
        local u = Unit.getByName(PLAYER_NAME)
        local c = Unit.getByName(CARRIER)
        if not u or not u:isExist() or not c or not c:isExist() then
            trigger.action.outText("FIX CHECK: unit or carrier not available.", 8)
            return
        end

        local dme = distToCarrierNm(u, c)
        local rad = radialFromCarrier(c, u)
        if not rad then
            trigger.action.outText("FIX CHECK: geometry unavailable.", 8)
            return
        end

        local toStation = (rad + 180) % 360
        local dDme = dme - HOLDFIX_DME_NM
        local dRad = angleDiff(rad, HOLDFIX_RADIAL_DEG)
        local inTol = (math.abs(dDme) <= HOLDFIX_DME_TOL)
                  and (math.abs(dRad) <= HOLDFIX_RADIAL_TOL)

        trigger.action.outText(string.format(
            "FIX CHECK\n"
            .. "DME          : %6.1f NM   (target %d, delta %+.1f)\n"
            .. "Radial FROM  : R-%03.0f      (target R-%03d, delta %+.1f)\n"
            .. "Bearing TO   : %03.0f       <-- compare with HSI TACAN needle\n"
            .. "In tolerance : %s   (magvar %+d)",
            dme, HOLDFIX_DME_NM, dDme,
            rad, HOLDFIX_RADIAL_DEG, dRad,
            toStation,
            inTol and "YES" or "NO", MAGVAR_DEG), 25)
    end

    missionCommands.addCommandForCoalition(
        coalition.side.BLUE,
        "FIX CHECK",
        nil,
        fixCheck
    )
end


----------------------------------------------------------------
-- RESET (called on recovery activation)
----------------------------------------------------------------
local function resetCASE2()
    CASE2.fixHit     = false
    CASE2.fixDone    = false
    CASE2.bestMiss   = nil
    CASE2.bestDme    = nil
    CASE2.bestRad    = nil
    CASE2.fixPassed  = false
    CASE2.holdEnter  = nil
    CASE2.holdDone   = false
    CASE2.holdPassed = false
    CASE2.nm12Done   = false
end

----------------------------------------------------------------
-- Select correct 12NM zone by CASE
----------------------------------------------------------------
local function get12nmZoneForActiveCase()
    if CASE_II_ENABLED then
        return ZONE_12NM_CASE2
    end
    if CASE_III_ENABLED then
        return ZONE_12NM_CASE3
    end
    return nil
end

----------------------------------------------------------------
-- HOLD FIX degerlendirmesini kapat (holding fazi sonlandiginda).
-- Fix hic tutturulmadiysa -5 ve en yakin gecis raporu.
----------------------------------------------------------------
local function closeFixEvaluation()
    if CASE2.fixDone then return end
    CASE2.fixDone   = true
    CASE2.fixPassed = false

    local detail
    if CASE2.bestMiss then
        detail = string.format(
            "closest approach %.1f NM off fix (DME %.1f / R-%03.0f)",
            CASE2.bestMiss, CASE2.bestDme, CASE2.bestRad)
    else
        detail = "no valid geometry sample recorded"
    end

    addScore(-5, string.format("Hold Fix: missed - expected DME %d / R-%03d, %s",
        HOLDFIX_DME_NM, HOLDFIX_RADIAL_DEG, detail))
end

----------------------------------------------------------------
-- UPDATE LOOP (IF -> HOLD -> 12NM) [SCORING]
----------------------------------------------------------------
local function updateCASEII(u, now)
    if not u or not u:isExist() then return end

    local c = uCarrier()
    if not c or not c:isExist() then return end

    ------------------------------------------------------------
    -- ADIM 1: HOLD FIX (v19)
    --
    -- v18 HATASI: geometri surekli olculuyordu ama PUANLAMA ANI
    -- Holding_Zone girisine bagliydi. Holding_Zone bir daire ve sinirI
    -- fix noktasindan birkac mil ONCE kesiliyor. Oyuncu sinirI gectiginde
    -- henuz DME bandina girmemis ya da radyale oturmamis oluyordu ->
    -- haksiz -5. (Saha kaydi: R-194 / DME 23.2 ile fix tutturulmusken
    -- ceza zaten yazilmisti.)
    --
    -- v19 COZUMU: puanlama anI zone girisinden KOPARILDI.
    --   +5 : DME ve radyal ayni anda tolerans icine girdigi AN verilir.
    --   -5 : holding fazi kapandiginda (ADIM 2 sonuclaninca) hala
    --        tutturulmadiysa verilir; mesajda en yakin gecis raporlanir.
    -- Boylece fix'i gec tutturmak da sayilir, erken zone girisi cezalandirmaz.
    ------------------------------------------------------------
    if not CASE2.fixDone then
        local dme = distToCarrierNm(u, c)
        local rad = radialFromCarrier(c, u)

        if rad then
            -- Fix noktasina gercek gecis mesafesi (kosinus teoremi, polar):
            --   miss^2 = dme^2 + R^2 - 2*dme*R*cos(delta radyal)
            local dRad = math.rad(angleDiff(rad, HOLDFIX_RADIAL_DEG))
            local miss = math.sqrt(
                dme * dme + HOLDFIX_DME_NM * HOLDFIX_DME_NM
                - 2 * dme * HOLDFIX_DME_NM * math.cos(dRad))

            if not CASE2.bestMiss or miss < CASE2.bestMiss then
                CASE2.bestMiss = miss
                CASE2.bestDme  = dme
                CASE2.bestRad  = rad
            end

            if math.abs(dme - HOLDFIX_DME_NM) <= HOLDFIX_DME_TOL
               and math.abs(angleDiff(rad, HOLDFIX_RADIAL_DEG)) <= HOLDFIX_RADIAL_TOL then
                CASE2.fixDone   = true
                CASE2.fixPassed = true
                CASE_PHASE      = "IF"
                addScore(5, string.format(
                    "Hold Fix: established at DME %.1f / R-%03.0f (target DME %d / R-%03d)",
                    dme, rad, HOLDFIX_DME_NM, HOLDFIX_RADIAL_DEG))
            end
        end
    end

    ------------------------------------------------------------
    -- ADIM 2: HOLDING SURESI (ONE-SHOT)
    -- Kesintisiz HOLD_MIN_SEC icerde kalirsa +5.
    -- Sure dolmadan zone'dan cikarsa -5.
    -- Faz kapanirken fix tutturulmadiysa ADIM 1 cezasi da burada yazilir.
    ------------------------------------------------------------
    if not CASE2.holdDone then
        local insideHold = inZone(u, HOLD_ZONE)

        if insideHold then
            if not CASE2.holdEnter then
                CASE2.holdEnter = now
            end

            if (now - CASE2.holdEnter) >= HOLD_MIN_SEC then
                CASE2.holdDone   = true
                CASE2.holdPassed = true
                CASE_PHASE       = "HOLD"
                closeFixEvaluation()
                addScore(5, string.format("Holding duration OK (>=%ds)", HOLD_MIN_SEC))

                -- COMMENCE noktasi: 10.000 ft -> 1.200 ft inisi burada baslar.
                runCommenceAdvisories(u)
            end

        elseif CASE2.holdEnter then
            -- Zone'a girmisti ama sure dolmadan cikti -> erken cikis
            local dur = now - CASE2.holdEnter
            CASE2.holdDone   = true
            CASE2.holdPassed = false
            CASE_PHASE       = "HOLD"
            closeFixEvaluation()
            addScore(-5, string.format("Holding: left early (%.0fs / %ds required)",
                dur, HOLD_MIN_SEC))

            -- Holding basarisiz olsa da inise geciyor; uyarilar yine verilir.
            runCommenceAdvisories(u)
        end

        return
    end

    ------------------------------------------------------------
    -- ADIM 3: 12NM GATE (ONE-SHOT, sadece ADIM 2 kapandiktan sonra)
    -- Zone'a GIRIS ANINDA olculur: 1200 ft +/- tol ve 250 kts +/- tol.
    -- 346 hizasi ayrica olculmez; zone'a girmis olmak bunu saglamis sayilir.
    ------------------------------------------------------------
    if CASE2.holdDone and not CASE2.nm12Done then
        local zone12 = get12nmZoneForActiveCase()
        if not zone12 then return end

        if inZone(u, zone12) then
            local alt = altFt(u)
            local spd = spdKts(u)

            local okAlt = math.abs(alt - ZONE12_ALT_TARGET) <= ZONE12_ALT_TOL
            local okSpd = math.abs(spd - ZONE12_SPD_TARGET) <= ZONE12_SPD_TOL

            local label = CASE_III_ENABLED and "CASE III" or "CASE II"
            local state = string.format("%.0f ft, %.0f kts", alt, spd)

            if okAlt and okSpd then
                addScore(5, label .. " 12NM: within parameters (" .. state .. ")")
            else
                addScore(-5, label .. " 12NM: out of parameters (" .. state .. ")")
            end

            CASE2.nm12Done = true
            CASE_PHASE     = "ARC12"
        end
    end
end

----------------------------------------------------------------
-- EXPLICIT RULES ACTIVATION (SINGLE-SHOT, 60NM)
----------------------------------------------------------------
local function checkRulesActivation()
    -- HARD GUARD: sadece bir kere çalışır
    if RECOVERY_ACTIVE then return end

    local u = uPlayer()
    local c = uCarrier()
    if not u or not u:isExist() or not c or not c:isExist() then return end

    local dist = distToCarrierNm(u, c)

    -- EXPLICIT ACTIVATION: 60 NM only
    local activate = (dist >= 60)

    if not activate then return end

    ------------------------------------------------------------
    -- ACTIVATE RECOVERY (ONE WAY)
    ------------------------------------------------------------
    RECOVERY_ACTIVE = true
    CASE_PHASE = "ACTIVE"

    ------------------------------------------------------------
    -- HARD RESET: CASE II / III chart state
    ------------------------------------------------------------
    resetCASE2()

    -- RESET fuel/weight advisory + touchdown scoring (per recovery)
    WF.commenceDone = false
    WF.landDone     = false

    ------------------------------------------------------------
    -- HARD KILL: Bankler CASE III'te ASLA çalışmaz
    ------------------------------------------------------------
    if CASE_III_ENABLED then
        BANKLER_MERGED = true
    end

    ------------------------------------------------------------
    -- ANNOUNCE
    ------------------------------------------------------------
    if CASE_I_ENABLED then
        trigger.action.outText("Recovery Rules Activated: CASE I", 10)
    elseif CASE_II_ENABLED then
        trigger.action.outText("Recovery Rules Activated: CASE II", 10)
    else
        trigger.action.outText("Recovery Rules Activated: CASE III", 10)
    end
end

----------------------------------------------------------------
-- CASE I/II: BANKLER (minimal, robust)
----------------------------------------------------------------
local BANKLER = {
    armed = false,
    started = false,
    done = false,
}

local function armBankler()
    BANKLER.armed = true
    BANKLER.started = false
    BANKLER.done = false
end

local function updateBankler(u)
    if not (CASE_I_ENABLED or CASE_II_ENABLED) then return end
    if not BANKLER.armed or BANKLER.done then return end
    if not u or not u:isExist() then return end

    local c = uCarrier()
    if not c or not c:isExist() then return end

    -- Trigger: near ship + low alt + decent speed + enters IF zone (your workflow)
    local dist = distToCarrierNm(u, c)
    local alt  = altFt(u)
    local spd  = spdKts(u)

    if inZone(u, IF_ZONE) and dist <= 12 and alt <= 900 and spd >= 250 and spd <= 370 then
        if not BANKLER.started then
            BANKLER.started = true
            trigger.action.outText("Bankler: commence. Report platform.", 8)
            if CASE_II_ENABLED then
                trigger.action.outText("CASE II: expect 'see you at ten' at 12.", 8)
            end
        end
    end

    -- End bankler when in groove (rough)
    if dist <= 1.6 and alt <= 900 and spd >= 105 and spd <= 210 then
        if BANKLER.started and not BANKLER.done then
            BANKLER.done = true
            trigger.action.outText("Bankler complete.", 6)
        end
    end
end

-- Arm Bankler once airborne (for CASE I/II)
timer.scheduleFunction(function()
    if not (CASE_I_ENABLED or CASE_II_ENABLED) then return timer.getTime() + 2 end

    local u = uPlayer()
    local c = uCarrier()
    if not u or not u:isExist() or not c or not c:isExist() then
        return timer.getTime() + 2
    end

    if not BANKLER.armed then
        local dist = distToCarrierNm(u, c)
        local alt  = altFt(u)
        local spd  = spdKts(u)
        if dist > 0.3 and alt > 50 and spd > 80 then
            armBankler()
        end
    end

    return timer.getTime() + 2
end, nil, timer.getTime() + 2)

----------------------------------------------------------------
-- LANDING / FINAL SCORE (PLAYER + WINGMAN LOGIC)
----------------------------------------------------------------
local FINAL_SHOWN    = false
local WINGMAN_LANDED = false

world.addEventHandler({
    onEvent = function(_, e)
        if not e or e.id ~= world.event.S_EVENT_LAND then return end

        local u = e.initiator
        if not u or not u:isExist() or not u.getName then return end

        local uname = u:getName()
        if not isTrackedPlayer(uname) then return end

        local c = uCarrier()
        if not c or not c:isExist() then return end

        -- Must be an actual carrier landing
        if distToCarrierNm(u, c) > 0.15 then return end

        ----------------------------------------------------------------
        -- PLAYER_01 LANDING (MAIN FINAL)
        ----------------------------------------------------------------
        if uname == PLAYER_NAME then
            addScore(5, "Successful Carrier Landing: " .. uname)

                -- FLAG: Player_01 landed
                if uname == "Player_01" then
                    setFlagON(FLAG_LAND_P1)
                end

            ----------------------------------------------------------------
            -- v16 ADIM 4: HOLD FIX + HOLDING tamamlanmadan inildiyse ek ceza.
            -- Hem "denedi ve basaramadi" hem "hic denemedi" durumunu kapsar,
            -- cunku fixPassed/holdPassed sadece basarili puanlamada true olur.
            -- FINAL SCORE yazdirilmadan ONCE uygulanir.
            ----------------------------------------------------------------
            -- v19: Holding_Zone'a hic girilmediyse ADIM 1 degerlendirmesi
            -- acik kalir. Inis anında kapat ki fix cezasi kaybolmasin.
            closeFixEvaluation()

            if not (CASE2.fixPassed and CASE2.holdPassed) then
                addScore(LANDING_MISS_PENALTY,
                    "Recovery: hold fix / holding not completed before landing")
            end

            -- v18: touchdown yakit + gross weight puanlamasi
            scoreLandingFuelWeight(u)

            if not FINAL_SHOWN then
                FINAL_SHOWN = true
                local final = trigger.misc.getUserFlag(FLAG) or 0
                trigger.action.outText(
                    "FINAL SCORE: " .. tostring(final),
                    15,
                    true
                )
            end
            return
        end

        ----------------------------------------------------------------
        -- PLAYER_02 LANDING (WINGMAN BONUS)
        ----------------------------------------------------------------
        if uname ~= PLAYER_NAME and not WINGMAN_LANDED then
            WINGMAN_LANDED = true

            addScore(5, "Wingman recovered: " .. uname)

                -- FLAG: Player_02 landed
                if uname == "Player_02" then
                    setFlagON(FLAG_LAND_P2)
                end

            local final = trigger.misc.getUserFlag(FLAG) or 0
            trigger.action.outText(
                "Wingman recovered. +5 bonus applied. YOUR FINAL SCORE: " .. tostring(final),
                15,
                true
            )
        end
    end
})

----------------------------------------------------------------
-- MAIN LOOP (1 Hz)
----------------------------------------------------------------
timer.scheduleFunction(function()
    local u = uPlayer()
    if not u or not u:isExist() then
        return timer.getTime() + 1
    end

    local now = timer.getTime()

    updateIFEI(u)
    updateFarWarning(u)

    -- EXPLICIT activation (60NM)
    checkRulesActivation()

-- Case-independent modules
updateBankler(u)

-- Inbound / recovery-only modules
if RECOVERY_ACTIVE then
    if CASE_II_ENABLED or CASE_III_ENABLED then
        updateCASEII(u, now)
    end
end

    return now + 1
end, nil, timer.getTime() + 1)
