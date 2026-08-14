-- DEBUG: script load check
trigger.action.outText("Civil Random Air Traffic (RAT) activated", 5)

----------------------------------------------------------------
-- CIVIL RAT – SPLIT DEPARTURE / DESTINATION (FAIL-SAFE)
----------------------------------------------------------------

----------------------------------------------------------------
-- SAFE HELPERS
----------------------------------------------------------------

-- Template var mı kontrolü
local function SafeRAT(templateName, setupFunc)
  if Group.getByName(templateName) then
    local rat = RAT:New(templateName)
    setupFunc(rat)
  else
    env.info("[RAT] Template NOT found, skipped: "..templateName)
  end
end

-- Airfield var mı kontrolü
local function SafeAirfields(list)
  local safe = {}
  for _, name in ipairs(list) do
    if Airbase.getByName(name) then
      table.insert(safe, name)
    else
      env.info("[RAT] Airfield NOT found, skipped: "..name)
    end
  end
  return safe
end

----------------------------------------------------------------
-- AIRFIELD GROUPS (RAW)
----------------------------------------------------------------

-- Batı / Güney / Kıyı
local WEST_FIELDS_RAW = {
  "Larnaca",
  "Paphos",
  "Beirut_Rafic_Hariri",
  "King_Hussein_Air_College",
  "Ercan",
  "Haifa",
  "Incirlik",
  "Gazipasa",
  "Gaziantep"
}

-- İç / Kuzey
local EAST_FIELDS_RAW = {
  "Damascus",
  "Aleppo",
  "Bassel_Al_Assad",
  "Marka"
}

----------------------------------------------------------------
-- SAFE AIRFIELD LISTS
----------------------------------------------------------------

local WEST_FIELDS = SafeAirfields(WEST_FIELDS_RAW)
local EAST_FIELDS = SafeAirfields(EAST_FIELDS_RAW)

----------------------------------------------------------------
-- A320
----------------------------------------------------------------
SafeRAT("RAT_A320", function(e3)
  e3:SetDeparture(WEST_FIELDS)
  e3:SetDestination(EAST_FIELDS)
  e3:RespawnAfterLanding(360)
  e3:ATC_Messages(false)
  e3:StatusReports(false)
  e3:Spawn(3)
end)

----------------------------------------------------------------
-- A330
----------------------------------------------------------------
SafeRAT("RAT_A330", function(e3)
  e3:SetDeparture(WEST_FIELDS)
  e3:SetDestination(EAST_FIELDS)
  e3:RespawnAfterLanding(360)
  e3:ATC_Messages(false)
  e3:StatusReports(false)
  e3:Spawn(3)
end)

----------------------------------------------------------------
-- B727
----------------------------------------------------------------
SafeRAT("RAT_B727", function(e3)
  e3:SetDeparture(EAST_FIELDS)
  e3:SetDestination(WEST_FIELDS)
  e3:RespawnAfterLanding(360)
  e3:ATC_Messages(false)
  e3:StatusReports(false)
  e3:Spawn(4)
end)

----------------------------------------------------------------
-- B737
----------------------------------------------------------------
SafeRAT("RAT_B737", function(e3)
  e3:SetDeparture(EAST_FIELDS)
  e3:SetDestination(WEST_FIELDS)
  e3:RespawnAfterLanding(360)
  e3:ATC_Messages(false)
  e3:StatusReports(false)
  e3:Spawn(4)
end)

----------------------------------------------------------------
-- B757
----------------------------------------------------------------
SafeRAT("RAT_B757", function(e3)
  e3:SetDeparture(SafeAirfields({"Beirut_Rafic_Hariri","Damascus","Gaziantep"}))
  e3:SetDestination(SafeAirfields({"Larnaca","Paphos","Incirlik"}))
  e3:RespawnAfterLanding(360)
  e3:ATC_Messages(false)
  e3:StatusReports(false)
  e3:Spawn(4)
end)

----------------------------------------------------------------
-- DC-10
----------------------------------------------------------------
SafeRAT("RAT_DC10", function(e3)
  e3:SetDeparture(SafeAirfields({"Larnaca","Beirut_Rafic_Hariri","Incirlik"}))
  e3:SetDestination(SafeAirfields({"Damascus"}))
  e3:RespawnAfterLanding(360)
  e3:ATC_Messages(false)
  e3:StatusReports(false)
  e3:Spawn(2)
end)

----------------------------------------------------------------
-- END
----------------------------------------------------------------
