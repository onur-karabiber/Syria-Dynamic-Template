-- HardDeck | v1.0.3
-- v1.0.3: 20,000 ft MSL (Comms_Director v1.6.3). Still not loaded by any mission (violations unscored).
-- v1.0.2: hard deck unified to 23,000 ft MSL (was 21,000 / "FL210"), matches Comms_Director v1.2.0.
-- v1.0.1: PLAYER_UNIT_NAME read from _G.TRT.PLAYER_NAME (default "Player_01").
-- File was unversioned before this change; treated as v1.0.0.
-------------------------------------------------
-- ALTITUDE PENALTY SYSTEM (MOOSE)
-------------------------------------------------

PLAYER_UNIT_NAME = (_G.TRT and _G.TRT.PLAYER_NAME) or "Player_01"

ALT_LIMIT_FT        = 20000     -- eşik (ft MSL)
WARNING_TIME        = 60        -- saniye (önce uyarı)
PENALTY_INTERVAL    = 3         -- her 3 sn
CHECK_INTERVAL      = 1

-------------------------------------------------
-- ZONE NAMES
-------------------------------------------------
ZONE_NAMES = {
    "SA15_1",
    "SA15_2",
    "SA8_1",
    "SA8_2",
    "SA8_3",
    "SA8_4",
    "ENGAGEMENT_ZONE"
}

-------------------------------------------------
-- STATE
-------------------------------------------------
belowAltTime   = 0
penaltyTimer   = 0
scorePenalty   = 0

-------------------------------------------------
-- ZONE CHECK
-------------------------------------------------
function IsPointInAnyZone(coord)

    local vec2 = coord:GetVec2()

    for _, name in ipairs(ZONE_NAMES) do
        local z = ZONE:FindByName(name)
        if z and z:IsVec2InZone(vec2) then
            return true
        end
    end

    return false
end

-------------------------------------------------
-- MAIN LOOP
-------------------------------------------------
function ALTITUDE_PENALTY_UPDATE()

    local unit = UNIT:FindByName(PLAYER_UNIT_NAME)
    if not unit or not unit:IsAlive() then
        belowAltTime = 0
        penaltyTimer = 0
        return
    end

    local coord = unit:GetCoordinate()

    -- zone dışıysa reset
    if not IsPointInAnyZone(coord) then
        belowAltTime = 0
        penaltyTimer = 0
        return
    end

    local altMSL_ft = coord.y * 3.28084

    -- alt üstündeyse reset
    if altMSL_ft >= ALT_LIMIT_FT then
        belowAltTime = 0
        penaltyTimer = 0
        return
    end

    -- ALT < LIMIT → sayaç başlar
    belowAltTime = belowAltTime + CHECK_INTERVAL

    -- WARNING PHASE
    if belowAltTime <= WARNING_TIME then
        MESSAGE:New(
            string.format(
                "ROE: Hard deck %d ft MSL in this area. | %.0f ft MSL",
                ALT_LIMIT_FT, altMSL_ft
            ),
            1
        ):ToAll()
        return
    end

    -- PENALTY PHASE
    penaltyTimer = penaltyTimer + CHECK_INTERVAL

    if penaltyTimer >= PENALTY_INTERVAL then
        penaltyTimer = 0
        scorePenalty = scorePenalty - 1

        MESSAGE:New(
            string.format(
                "ALTITUDE PENALTY | -1 POINT | TOTAL: %d",
                scorePenalty
            ),
            2
        ):ToAll()

        -- burada istersen:
        -- trigger.action.setUserFlag("PENALTY", scorePenalty)
        -- trigger.action.outScoreText(...)
    end
end

-------------------------------------------------
-- START
-------------------------------------------------
MESSAGE:New("Hard Deck altitude monitoring has been initiated.", 10):ToAll()
env.info("[HardDeck] v1.0.3 loaded. Limit " .. ALT_LIMIT_FT .. " ft MSL")

ALTITUDE_PENALTY_SCHEDULER = SCHEDULER:New(
    nil,
    ALTITUDE_PENALTY_UPDATE,
    {},
    1,
    CHECK_INTERVAL
)
