----------------------------------------------------------------
-- SKYNET IADS - CUSTOM INIT (PREFIX + COMMAND CENTER)
-- Skynet version: 3.3.0
-- Author: sen (inat), ben (temizlikçi)
----------------------------------------------------------------

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CFG = {
    IADS_NAME      = "RED_IADS",

    -- Prefixes
    EW_PREFIX      = "EW",     -- UNIT name prefix
    SAM_PREFIX     = "SAM",    -- GROUP name prefix

    -- Command Center (UNIT name)
    COMMAND_CENTER_UNIT = "RED_CC_1",
    CC_POWER_UNIT       = "RED_PWR_1",   -- Command Center power source
    CC_CONNECTION_UNIT  = "RED_COM_1",   -- Command Center connection node

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

    -- NOT: hasNoPower ve samNoConnection BİLEREK false/kapalı.
    -- Skynet çekirdeği (satır 2059, 2067) bu bayraklar açıkken
    -- printOutput()'u typeWarning=nil ile çağırıyor, bu da HER
    -- kontrol turunda trigger.action.outText() ile EKRANA yazı
    -- basıyor (log'a değil). CC'nin connection/power node'u ölünce
    -- bu, saniyede defalarca tekrarlanan mesaj kutusu yağmuruna
    -- dönüşüyor ve üst üste binen kutular ekranın büyük bölümünü
    -- siyaha boğuyor. commandCenterStatusEnvOutput güvenli: o
    -- printOutputToLog()/env.info() kullanıyor, sadece dcs.log'a yazıyor.
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
    local cc = Unit.getByName(CFG.COMMAND_CENTER_UNIT)
    if cc then
        local comCenter = redIADS:addCommandCenter(cc)
        info("COMMAND CENTER ADDED: " .. CFG.COMMAND_CENTER_UNIT)

        local pwr = Unit.getByName(CFG.CC_POWER_UNIT)
        if pwr then
            comCenter:addPowerSource(pwr)
            info("CC POWER SOURCE ADDED: " .. CFG.CC_POWER_UNIT)
        else
            errorLog("CC POWER SOURCE NOT FOUND: " .. CFG.CC_POWER_UNIT)
        end

        local conn = Unit.getByName(CFG.CC_CONNECTION_UNIT)
        if conn then
            comCenter:addConnectionNode(conn)
            info("CC CONNECTION NODE ADDED: " .. CFG.CC_CONNECTION_UNIT)
        else
            errorLog("CC CONNECTION NODE NOT FOUND: " .. CFG.CC_CONNECTION_UNIT)
        end
    else
        errorLog("COMMAND CENTER NOT FOUND: " .. CFG.COMMAND_CENTER_UNIT)
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
