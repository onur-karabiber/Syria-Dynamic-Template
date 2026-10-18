-- Skynet_Init_Main | v1.1.0
----------------------------------------------------------------
-- SKYNET IADS - CUSTOM INIT (PREFIX + COMMAND CENTER)
-- Skynet version: 3.3.0
-- Author: sen (inat), ben (temizlikci)
--
-- v1.1.0:
--  * FIX: Command Center / Power / Connection node cozumlemesi.
--    v1.0.x Unit.getByName("RED_CC_1") cagiriyordu; "RED_CC_1" bir GRUP adi,
--    unit adi "RED_CC_1-1" (dcs.log MOOSE kaydi: Group RED_CC_1 -> Unit RED_CC_1-1).
--    Sonuc: "COMMAND CENTER NOT FOUND", IADS komuta merkezsiz kuruluyordu.
--    Ayni hata RED_PWR_1 ve RED_COM_1 icin de gecerliydi (CC bulunamadigi icin
--    log'a dusmedi, cunku kontrol "if cc" blogunun icindeydi).
--  * resolveObject(): once Unit, sonra Static, sonra Grup (ilk unit) dener.
--    Config'e grup adi girilse de calisir; hangi yolla cozuldugu log'a yazilir.
----------------------------------------------------------------

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CFG = {
    IADS_NAME      = "RED_IADS",

    -- Prefixes
    EW_PREFIX      = "EW",     -- UNIT name prefix
    SAM_PREFIX     = "SAM",    -- GROUP name prefix

    -- Command Center (UNIT names; grup adi da kabul edilir, bkz. resolveObject)
    COMMAND_CENTER_UNIT = "RED_CC_1-1",
    CC_POWER_UNIT       = "RED_PWR_1-1",   -- Command Center power source
    CC_CONNECTION_UNIT  = "RED_COM_1-1",   -- Command Center connection node

    -- Retry logic (DCS race condition fix)
    RETRY_INTERVAL = 1,   -- seconds
    RETRY_TIMEOUT  = 60,  -- seconds

    -- Minimal on-screen sanity check
    SHOW_TEXT      = true,
    TEXT_TIME      = 8,
}

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function info(msg)
    env.info("[SKYNET_CUSTOM] " .. msg)
end

local function errorLog(msg)
    env.error("[SKYNET_CUSTOM] " .. msg)
end

local function out(msg)
    if CFG.SHOW_TEXT then
        trigger.action.outText(msg, CFG.TEXT_TIME)
    end
end

-- Unit -> Static -> Grup(ilk unit) sirasiyla cozer.
-- Dondurur: dcsObject, cozum_yolu (string) | nil
local function resolveObject(name)
    local u = Unit.getByName(name)
    if u then return u, "unit" end

    local s = StaticObject.getByName(name)
    if s then return s, "static" end

    local g = Group.getByName(name)
    if g then
        local units = g:getUnits()
        if units and units[1] then
            return units[1], "group -> unit '" .. units[1]:getName() .. "'"
        end
    end

    return nil, nil
end

----------------------------------------------------------------
-- INIT FUNCTION
----------------------------------------------------------------
redIADS = redIADS or nil

local function initSkynet()
    if not mist then
        errorLog("MIST not loaded yet")
        return false
    end

    if not SkynetIADS then
        errorLog("Skynet IADS not loaded yet")
        return false
    end

    ----------------------------------------------------------------
    -- CREATE IADS
    ----------------------------------------------------------------
    redIADS = SkynetIADS:create(CFG.IADS_NAME)

    ----------------------------------------------------------------
    -- DEBUG SETTINGS
    ----------------------------------------------------------------
    local debug = redIADS:getDebugSettings()

    debug.IADSStatus     = false
    debug.contacts       = false
    debug.samWentDark    = true
    debug.radarWentLive  = true

    debug.addedEWRadar   = true
    debug.addedSAMSite   = true
    debug.warnings       = true
    debug.harmDefence    = true

    -- NOT: hasNoPower ve samNoConnection BILEREK false/kapali.
    -- Skynet cekirdegi (satir 2059, 2067) bu bayraklar acikken
    -- printOutput()'u typeWarning=nil ile cagiriyor, bu da HER
    -- kontrol turunda trigger.action.outText() ile EKRANA yazi
    -- basiyor (log'a degil). CC'nin connection/power node'u olunce
    -- bu, saniyede defalarca tekrarlanan mesaj kutusu yagmuruna
    -- donusuyor ve ust uste binen kutular ekranin buyuk bolumunu
    -- siyaha bogyuyor. commandCenterStatusEnvOutput guvenli: o
    -- printOutputToLog()/env.info() kullaniyor, sadece dcs.log'a yazıyor.
    debug.hasNoPower               = false
    debug.samNoConnection          = false
    debug.commandCenterStatusEnvOutput = true

    ----------------------------------------------------------------
    -- ADD EW RADARS (UNIT PREFIX)
    ----------------------------------------------------------------
    redIADS:addEarlyWarningRadarsByPrefix(CFG.EW_PREFIX)

    ----------------------------------------------------------------
    -- ADD SAM SITES (GROUP PREFIX)
    ----------------------------------------------------------------
    redIADS:addSAMSitesByPrefix(CFG.SAM_PREFIX)

    ----------------------------------------------------------------
    -- ADD COMMAND CENTER (EXPLICIT)
    ----------------------------------------------------------------
    local cc, ccHow = resolveObject(CFG.COMMAND_CENTER_UNIT)
    if cc then
        local comCenter = redIADS:addCommandCenter(cc)
        info("COMMAND CENTER ADDED: " .. CFG.COMMAND_CENTER_UNIT .. " (" .. ccHow .. ")")

        local pwr, pwrHow = resolveObject(CFG.CC_POWER_UNIT)
        if pwr then
            comCenter:addPowerSource(pwr)
            info("CC POWER SOURCE ADDED: " .. CFG.CC_POWER_UNIT .. " (" .. pwrHow .. ")")
        else
            errorLog("CC POWER SOURCE NOT FOUND: " .. CFG.CC_POWER_UNIT)
        end

        local conn, connHow = resolveObject(CFG.CC_CONNECTION_UNIT)
        if conn then
            comCenter:addConnectionNode(conn)
            info("CC CONNECTION NODE ADDED: " .. CFG.CC_CONNECTION_UNIT .. " (" .. connHow .. ")")
        else
            errorLog("CC CONNECTION NODE NOT FOUND: " .. CFG.CC_CONNECTION_UNIT)
        end
    else
        errorLog("COMMAND CENTER NOT FOUND: " .. CFG.COMMAND_CENTER_UNIT
            .. " (tried unit, static, group) - power/connection node also NOT attached")
    end

    ----------------------------------------------------------------
    -- BUILD + ACTIVATE
    ----------------------------------------------------------------
    redIADS:buildRadarCoverage()
    redIADS:activate()

    info("SKYNET IADS INITIALIZED (" .. CFG.IADS_NAME .. ")")
    out("SKYNET Integrated Air Defence System (IADS) is ready")

    return true
end

----------------------------------------------------------------
-- RETRY LOOP (SAFE START)
----------------------------------------------------------------
do
    local startTime = timer.getTime()

    local function tick()
        local elapsed = timer.getTime() - startTime

        if elapsed > CFG.RETRY_TIMEOUT then
            errorLog("INIT FAILED: timeout")
            out("SKYNET IADS INIT FAILED")
            return nil
        end

        if initSkynet() then
            return nil
        end

        return timer.getTime() + CFG.RETRY_INTERVAL
    end

    timer.scheduleFunction(
        function()
            return tick()
        end,
        nil,
        timer.getTime() + 0.1
    )
end
