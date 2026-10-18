deltaTime = 0.5
abortsActive = true  -- false for straight-in
startingStep = 1
case1StartingStep = 1  -- Normally 1, and 8 for straight-in.
case3StartingStep = 8
case1PatternModeStartingStep = 5
lsoActive = true
useLsoVoiceOver = true
printDebugGlideslopeFeedback = false
printDebugLineupFeedback = false
printDebugWireFeedback = false
sendPlayerFeedbackToAllPlayers = false
inFlightFeedback = true
scriptVersion = "7.5.0"
numberOfPlayers = 44
carrierTCN = "74X"
onSpeedAlpha_Hornet = 8.1
onSpeedAlpha_Tomcat = 10.6
onSpeedAlpha_Goshawk = 7.0
player33callsign = "Enfield1" --Should be "Enfield1" normally, "Cheetah4" for MA custom
player33modex = 140  --Should be 140 normally, 500 for MA custom

playerInTheGroove = -1
maxScore = 75
case = 1
patternMode = false
brc = 353

--This is the point at which the aircraft's center point should be aiming, to be on perfect 3.5 degree glideslope and nail a 3-wire.
--Matt's point x=37.327, y=13.979, z=-23.655 (mine is 0.4m above since it seems to give more accurate results)
focalPointX = 37.327
focalPointY = 14.379
focalPointZ = -23.655

SoundPack = {
	ClassName = "SOUNDPACK",
}

function SetSuperCarrier(enabled)
	if(enabled) then
		carrierTCN = "72X"
	else
		carrierTCN = "74X"
	end
end

function SetBRC(newBRC)
	brc = newBRC
end

function SoundPack:New( id, fileNames ) 
	local self = BASE:Inherit( self, BASE:New() )
	self.id = id
	self.sounds = {}
	self.size = 0
	self.index = 1
	
	for i, fileName in ipairs(fileNames) do
		local userSound = USERSOUND:New(fileName)
		self.sounds[i] = userSound
		self.size = i
		--env.info("Adding " .. fileName .. " to " .. id .. " in array slot " .. i)
	end
	
	--env.info("Size: " .. self.size)
	
	return self
end

function SoundPack:Play()
	--env.info("Play: " .. self.id .. " index " .. self.index)
	self.sounds[self.index]:ToAll()
	self.index = self.index + 1
	if(self.index > self.size) then
		self.index = 1
	end
end

sfx_paddlesContact = SoundPack:New("sfx_paddlesContact", {"PaddlesContact_1.wav"})
sfx_FlyDown_Intensity_1 = SoundPack:New("sfx_FlyDown_Intensity_1", {"YoureHi_1.ogg", "YoureHi_2.ogg", "YoureHi_3.ogg"})
sfx_FlyUp_Intensity_1 = SoundPack:New("sfx_FlyUp_Intensity_1", {"Power_1.ogg", "Power_2.ogg", "Power_3.ogg"})
sfx_FlyLeft_Intensity_1 = SoundPack:New("sfx_FlyLeft_Intensity_1", {"ComeLeft_1.ogg", "ComeLeft_2.ogg", "ComeLeft_3.ogg"})
sfx_FlyRight_Intensity_1 = SoundPack:New("sfx_FlyRight_Intensity_1", {"RightForLineup_1.ogg", "RightForLineup_2.ogg", "RightForLineup_3.ogg"})
sfx_Reset = SoundPack:New("sfx_Reset", {"Reset.wav"})

function GetRelativePositionToCarrier(position)
  -- Carrier position
  local a = carrier:GetVec3()  
  -- Player position
  local b = position 
  -- Vector from carrier to player.
  local c = {x = b.x - a.x, y = 0, z = b.z - a.z}
  
  -- Orientation of carrier.
  local x = carrier:GetOrientationX()  
  -- Projection of player pos on x component.
  local dx = UTILS.VecDot(x,c) 
  -- Orientation of carrier.
  local z = carrier:GetOrientationZ()  
  -- Projection of player pos on z component.  
  local dz = UTILS.VecDot(z,c)
  -- Use absolute altitude for the Y component.
  local dy = b.y
  
  return dx, dy, dz
end

function GeneratePlayerId(number)
	local numberPart = ""
	
	if(number < 10) then
		numberPart = "0" .. number
	else
		numberPart = "" .. number
	end
	
	return "Player_" .. numberPart
end

function GenerateFixedPlayerCallsign(number)
	callsignNumber = ((number - 1) % 4) + 1

	if(number >= 1 and number <= 4) then
		return "Chevy1" .. callsignNumber
	elseif(number >= 5 and number <= 8) then
		return "Colt2" .. callsignNumber
	elseif(number >= 9 and number <= 12) then
		return "Dodge3" .. callsignNumber
	elseif(number >= 13 and number <= 16) then
		return "Enfield4" .. callsignNumber
	elseif(number >= 17 and number <= 20) then
		return "Ford5" .. callsignNumber
	elseif(number >= 21 and number <= 24) then
		return "Pontiac6" .. callsignNumber
	elseif(number >= 25 and number <= 28) then
		return "Springfield7" .. callsignNumber
	elseif(number >= 29 and number <= 32) then
		return "Uzi8" .. callsignNumber
	elseif(number >= 33 and number <= 36) then
		return player33callsign .. callsignNumber --Should be Enfield1 for T-45, Cheetah4 for MA custom
	elseif(number >= 37 and number <= 40) then
		return "Enfield2" .. callsignNumber
	elseif(number >= 41 and number <= 44) then
		return "Enfield3" .. callsignNumber
	end
end

function GenerateFixedPlayerModex(number)
	modexOffset = ((number - 1) % 4)

	if(number >= 1 and number <= 4) then
		return 200 + modexOffset
	elseif(number >= 5 and number <= 8) then
		return 204 + modexOffset
	elseif(number >= 9 and number <= 12) then
		return 210 + modexOffset
	elseif(number >= 13 and number <= 16) then
		return 400 + modexOffset
	elseif(number >= 17 and number <= 20) then
		return 404 + modexOffset
	elseif(number >= 21 and number <= 24) then
		return 100 + modexOffset
	elseif(number >= 25 and number <= 28) then
		return 110 + modexOffset
	elseif(number >= 29 and number <= 32) then
		return 104 + modexOffset
	elseif(number >= 33 and number <= 36) then
		return player33modex + modexOffset --Should be 140 for T-45, 500 for MA custom
	elseif(number >= 37 and number <= 40) then
		return 144 + modexOffset
	elseif(number >= 41 and number <= 44) then
		return 150 + modexOffset
	end
end

PlayerData = {
	ClassName = "PLAYERDATA",
}

function PlayerData:New( id ) 
	local self = BASE:Inherit( self, BASE:New() )
	self.unit = UNIT:FindByName(GeneratePlayerId(id))
	self.fixedCallsign = GenerateFixedPlayerCallsign(id)
	self.modex = GenerateFixedPlayerModex(id)
	env.info(self.unit.onboardnum);
	self.client = CLIENT:FindByName(self.unit.UnitName, nil, true)	
	self.playerName = self.unit:GetPlayerName()
	self.totalScore = 0
	self.passes = 0
	self.collectedResultString = ""
	self.hasShownVersionMessage = false
	self.typeName = self.unit:GetTypeName()
	self.isTomcat = self.typeName:find("F-14", 1, true) ~= nil
	self.isGoshawk = self.typeName == "T-45"
	
	if(self.isTomcat) then
		self.onSpeedAlpha = onSpeedAlpha_Tomcat
	elseif(self.isGoshawk) then
		self.onSpeedAlpha = onSpeedAlpha_Goshawk
	else
		self.onSpeedAlpha = onSpeedAlpha_Hornet
	end
	
	return self
end

function PlayerData:InitNewRound()
	self.score = 0
	self.summary = ""
	self.step = 0
	self.longDownwindChecked = false
	self.longDownwind = false
	self.didSettle = false
	self.shitHotBreak = false;
	self.highestCarrierXDiff = -9999999
	self.secondsStandingStill = 0
	self.lowestAltitude = 999999
	self.grooveTime = 0
	self.hasReachedTrapAltitude = false
	self.hasIdentifiedTrapSlowdown = false
	self.lastLineupError = -9
	self.highestLineupError = 0
	self.lowestLineupError = 0
	self.shbSpeed = 0
	
	--LSO DATA
	self.lso_lastLineupError = -9 --Starting left since we always come from that direction
	self.lso_lastGlideslopeError = -1 --Assume we come in a little low and don't comment if we're working our way up.
	self.lso_lastAdviceTime = 0
	
	--VV data
	self.verticalVelocityArray = {}
	for i=1, 3 do
		self.verticalVelocityArray[i] = 0
	end
end

function PlayerData:IncreaseScore(amount)
	self.score = self.score + amount
end

function PlayerData:AddToSummary(item)
	self.summary = self.summary .. item .. "\n"
end

function PlayerData:AddToCollectedResult(item)
	self.collectedResultString = self.collectedResultString .. item .. "\n"
end

playerDatas = {}
for i=1, numberOfPlayers do
	playerDatas[i] = nil
end

carrier = UNIT:FindByName("CVN")
carrier:PatrolRoute()

startZone = ZONE_UNIT:New( "startZone", carrier, 1000, { dx = -2000, dy = 100, relative_to_unit = true } )
patternModeStartZone = ZONE_UNIT:New( "patternModeStartZone", carrier, 250, { dx = 500, dy = 0, relative_to_unit = true } )
giantZone = ZONE_UNIT:New( "giantZone", carrier, 30000, { dx = 0, dy = 0, relative_to_unit = true } )

initMonitorAltitudeMeters = 400
initMonitorNormalZoneName = "InitZone"
initMonitorNormalAnchorUnitName = "Oliver Hazzard Perry"
initMonitorPatternZoneName = "PatternModeInitZone"
initMonitorPatternAnchorUnitName = "PatternModeBoat"
initMonitorNormalFallbackRadius = 3657.6
initMonitorPatternFallbackRadius = 548.64

initMonitorMissingLogs = {}

function LogInitMonitorMissingOnce(key, message)
	if(not initMonitorMissingLogs[key]) then
		env.info(message)
		initMonitorMissingLogs[key] = true
	end
end

function CreateInitMonitorMovingZone(zoneName, anchorUnitName, fallbackRadius)
	local anchorUnit = UNIT:FindByName(anchorUnitName)
	if(not anchorUnit) then
		LogInitMonitorMissingOnce("missing_anchor_" .. anchorUnitName, "TrapTraining init monitor: Anchor unit '" .. anchorUnitName .. "' not found; skipping zone '" .. zoneName .. "'")
		return nil
	end
	
	local radius = fallbackRadius
	local templateZone = ZONE:FindByName(zoneName)
	if(templateZone and templateZone.GetRadius) then
		local templateRadius = templateZone:GetRadius()
		if(templateRadius and templateRadius > 0) then
			radius = templateRadius
		end
	else
		LogInitMonitorMissingOnce("missing_zone_" .. zoneName, "TrapTraining init monitor: Zone template '" .. zoneName .. "' not found; using fallback radius " .. fallbackRadius)
	end
	
	return ZONE_UNIT:New( zoneName .. "_Monitor", anchorUnit, radius )
end

initMonitorNormalZone = CreateInitMonitorMovingZone(initMonitorNormalZoneName, initMonitorNormalAnchorUnitName, initMonitorNormalFallbackRadius)
initMonitorPatternZone = CreateInitMonitorMovingZone(initMonitorPatternZoneName, initMonitorPatternAnchorUnitName, initMonitorPatternFallbackRadius)

initMonitorNormalWasTrue = {}
initMonitorPatternWasTrue = {}
for i=1, numberOfPlayers do
	initMonitorNormalWasTrue[i] = false
	initMonitorPatternWasTrue[i] = false
end

function GetPlayerUnitForInitMonitor(id)
	local playerData = playerDatas[id]
	if(playerData and playerData.unit and playerData.unit:IsAlive() and playerData.unit:GetPlayerName()) then
		return playerData.unit
	end

	local playerUnit = UNIT:FindByName(GeneratePlayerId(id))
	if(playerUnit and playerUnit:IsAlive() and playerUnit:GetPlayerName()) then
		return playerUnit
	end

	return nil
end

function IsUnitBelowInitAltitude(unit)
	if(not unit or not unit:IsAlive()) then
		return false
	end
	
	local position = unit:GetVec3()
	if(not position) then
		return false
	end
	
	return position.y < initMonitorAltitudeMeters
end

function EvaluateInitMonitorForPlayer(id)
	local playerUnit = GetPlayerUnitForInitMonitor(id)
	if(not playerUnit) then
		initMonitorNormalWasTrue[id] = false
		initMonitorPatternWasTrue[id] = false
		return
	end
	
	local belowAltitude = IsUnitBelowInitAltitude(playerUnit)
	local normalCondition = false
	local patternCondition = false
	
	if(initMonitorNormalZone and belowAltitude and playerUnit:IsInZone(initMonitorNormalZone)) then
		normalCondition = true
	end
	
	if(initMonitorPatternZone and belowAltitude and playerUnit:IsInZone(initMonitorPatternZone)) then
		patternCondition = true
	end
	
	if(normalCondition and not initMonitorNormalWasTrue[id]) then
		Init(id, false)
	end
	
	if(patternCondition and not initMonitorPatternWasTrue[id]) then
		Init(id, true)
	end
	
	initMonitorNormalWasTrue[id] = normalCondition
	initMonitorPatternWasTrue[id] = patternCondition
end

second = 0

BanklerCase1Menu = nil
MenuItem_PublicFeedback_On = nil
MenuItem_PublicFeedback_Off = nil
MenuItem_InFlightFeedback_On = nil
MenuItem_InFlightFeedback_Off = nil
MenuItem_LSO_On = nil
MenuItem_LSO_Off = nil
MenuItem_Mode_Break = nil
MenuItem_Mode_Pattern = nil
MenuItem_Mode_Case_1 = nil
MenuItem_Mode_Case_3 = nil

function CreateRadioMenu()
	BanklerCase1Menu = MENU_MISSION:New( "Bankler's CASE 1 Training" )
	--MENU_MISSION_COMMAND:New("End Mission", BanklerCase1Menu, EndMission)	--Disabled in MA custom
end

function EndMission()
	local UserFlag = USERFLAG:New( "777" )
	UserFlag:Set( 1 )
end

function TogglePublicFeedback(enabled, silentChange)
	sendPlayerFeedbackToAllPlayers = enabled
	local message = ""
	if(enabled) then	
		if(MenuItem_PublicFeedback_On ~= nil) then
			MenuItem_PublicFeedback_On:Remove()
		end
		
		MenuItem_PublicFeedback_Off = MENU_MISSION_COMMAND:New( "Disable Public Feedback", BanklerCase1Menu, TogglePublicFeedback, false)
		message = "Public Feedback: ENABLED"
	else 
		if(MenuItem_PublicFeedback_Off ~= nil) then
			MenuItem_PublicFeedback_Off:Remove()
		end
		
		MenuItem_PublicFeedback_On = MENU_MISSION_COMMAND:New( "Enable Public Feedback", BanklerCase1Menu, TogglePublicFeedback, true)
		message = "Public Feedback: DISABLED"
	end
	
	if not silentChange then
		MessageToAllIncludingSpectators(message)
	end
end

function ToggleInFlightFeedback(enabled, silentChange)
	inFlightFeedback = enabled
	local message = ""
	if(enabled) then	
		if(MenuItem_InFlightFeedback_On ~= nil) then
			MenuItem_InFlightFeedback_On:Remove()
		end
		
		MenuItem_InFlightFeedback_Off = MENU_MISSION_COMMAND:New( "Disable In-flight Feedback", BanklerCase1Menu, ToggleInFlightFeedback, false)
		message = "In-flight Feedback: ENABLED"
	else 
		if(MenuItem_InFlightFeedback_Off ~= nil) then
			MenuItem_InFlightFeedback_Off:Remove()
		end
		
		MenuItem_InFlightFeedback_On = MENU_MISSION_COMMAND:New( "Enable In-flight Feedback", BanklerCase1Menu, ToggleInFlightFeedback, true)
		message = "In-flight Feedback: DISABLED"
	end
	
	if not silentChange then
		MessageToAllIncludingSpectators(message)
	end
end

function ToggleLSO(enabled, silentChange)
	lsoActive = enabled
	local message = ""
	if(enabled) then	
		if(MenuItem_LSO_On ~= nil) then
			MenuItem_LSO_On:Remove()
		end
		
		MenuItem_LSO_Off = MENU_MISSION_COMMAND:New( "Disable LSO", BanklerCase1Menu, ToggleLSO, false)
		message = "LSO: ENABLED"
	else 
		if(MenuItem_LSO_Off ~= nil) then
			MenuItem_LSO_Off:Remove()
		end
		
		MenuItem_LSO_On = MENU_MISSION_COMMAND:New( "Enable LSO", BanklerCase1Menu, ToggleLSO, true)
		message = "LSO: DISABLED"
	end
	
	if not silentChange then
		MessageToAllIncludingSpectators(message)
	end
end

function SetCase(caseIndex, showMessage)
	case = caseIndex
	local message = ""
	if(caseIndex == 1) then
		message = "CASE 1 activated"
		
		if(mode == "pattern") then
			startingStep = case1PatternModeStartingStep
		else
			startingStep = case1StartingStep
		end
		
		UpdateMaxScore()
		
		if(MenuItem_Case_1 ~= nil) then
			MenuItem_Case_1:Remove()
		end
		
		MenuItem_Case_3 = MENU_MISSION_COMMAND:New( "Set CASE 3", BanklerCase1Menu, SetCase, 3, true)
	elseif(case == 3) then
		message = "CASE 3 activated"
		startingStep = case3StartingStep
		UpdateMaxScore()
		
		if(MenuItem_Case_3 ~= nil) then
			MenuItem_Case_3:Remove()
		end
		
		MenuItem_Case_1 = MENU_MISSION_COMMAND:New( "Set CASE 1", BanklerCase1Menu, SetCase, 1, true)
	end
	
	if(showMessage) then
		MessageToAllIncludingSpectators(message)
	end
end

function SetMode(mode, silentChange)
	local message = ""
	if(mode == "break") then
		patternMode = false
		startingStep = case1StartingStep
		UpdateMaxScore()
		message = "BREAK MODE: Reset each pass by flying over the trailing ship."
		if(MenuItem_Mode_Break ~= nil) then
			MenuItem_Mode_Break:Remove()
		end
		
		MenuItem_Mode_Pattern = MENU_MISSION_COMMAND:New( "Enable Pattern Mode", BanklerCase1Menu, SetMode, "pattern")
		
	elseif(mode == "pattern") then
		patternMode = true
		startingStep = case1PatternModeStartingStep
		UpdateMaxScore()
		message = "PATTERN MODE: Reset each pass by flying 0.5 nm ahead of carrier."
		if(MenuItem_Mode_Pattern ~= nil) then
			MenuItem_Mode_Pattern:Remove()
		end
		
		MenuItem_Mode_Break = MENU_MISSION_COMMAND:New( "Enable Break Mode", BanklerCase1Menu, SetMode, "break")
	end
	
	for i = 1, numberOfPlayers do
		local playerData = playerDatas[i]
		
		if playerData then
			playerData.step = 0
		end
	end
	
	if not silentChange then
		MessageToAllIncludingSpectators(message)
	end
end

function UpdateMaxScore()
	if(case == 3) then
		maxScore = 33
	else
		if(patternMode) then
			maxScore = 63
		else
			maxScore = 75
		end
	end
end

SCHEDULER:New( nil,
	function()
		second = second + deltaTime
	
		--local a = carrier:GetVec3() 
		--env.info(a.y)
		
		for i = 1, numberOfPlayers do
			EvaluateInitMonitorForPlayer(i)
			local playerData = playerDatas[i]
			
			if playerData then
			
				local unit = playerData.unit
				local step = playerData.step
				
				if(unit:IsAlive()) then

					if unit:IsInZone( giantZone ) then
						Tick(playerData)
					end
					
					local position = playerData.unit:GetVec3()
					local altitude = UTILS.Round( UTILS.MetersToFeet( position.y ) )
					local dx, dy, dz = GetRelativePositionToCarrier(position)
					
					if(step > 0 and altitude > 2000) then
						AbortPattern(playerData, "You went too high, exiting the pattern")
					end
					
					if(step > 0 and step < 7 and dz > 4080) then --2.2nm
						AbortPattern(playerData, "Exiting the pattern")
					end
					
					if (step == 6 or step == 7) and not playerData.longDownwindChecked and unit:IsInZone( giantZone ) then
						CheckForLongDownwind(playerData)
					end
					
					if step == 1 and unit:IsInZone( startZone ) then
						Start(playerData)
					--elseif step == 1.5 and unit:IsInZone( giantZone ) then
					--	PatternStart(playerData)
					elseif step == 2 and unit:IsInZone( giantZone ) then
						Upwind(playerData)
					elseif step == 3 and unit:IsInZone( giantZone ) then
						Break(playerData, "early")
					elseif step == 4 and unit:IsInZone( giantZone ) then
						Break(playerData, "late")
					elseif step == 5 and unit:IsInZone( giantZone ) then
						Abeam(playerData)
					elseif step == 6 and unit:IsInZone( giantZone ) then
						Ninety(playerData)
					elseif step == 7 and unit:IsInZone( giantZone ) then
						Wake(playerData)
					elseif step == 8 and unit:IsInZone( giantZone ) then
						Groove(playerData)
					elseif step == 9 and unit:IsInZone( giantZone ) then
						Middle(playerData)
					elseif step == 10 and unit:IsInZone( giantZone ) then
						InClose(playerData)
					elseif step == 11 and unit:IsInZone( giantZone ) then
						AtTheRamp(playerData)
					elseif step == 12 and unit:IsInZone( giantZone ) then
						Trap(playerData)
					end	

				else
					playerDatas[i] = nil
				end
			end
		end
	end,
  {}, 0, deltaTime )


function Tick(playerData)

	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)
	local aoa = playerData.unit:GetAoA()
	
	--[[
	local hint2 = "Vertical speed: "
	local VS = GetUnitVerticalVelocity(playerData.unit)
	local fullhint2 = hint2 .. VS
	
	SendMessageToPlayer(fullhint2, 8, playerData)
	SendMessageToPlayer("AOA: " .. aoa, 2, playerData)
	]]--

	local vv = GetUnitVerticalVelocity(playerData.unit)
	playerData.verticalVelocityArray[3] = playerData.verticalVelocityArray[2]
	playerData.verticalVelocityArray[2] = playerData.verticalVelocityArray[1]
	playerData.verticalVelocityArray[1] = vv
			
	--local fullhint2 = playerData.verticalVelocityArray[3] .. "   " .. playerData.verticalVelocityArray[2] .. "   " .. playerData.verticalVelocityArray[1]
	--SendMessageToPlayer(fullhint2, 8, playerData)
	
	--SendMessageToPlayer("dx: " .. dx .. ", dy: " .. dy.. ", dz: " .. dz, 0.5, playerData)

	--env.info(aoa)
	--env.info("dx: " .. dx .. ", dz: " .. dz)
	--local cx = carrier:GetOrientationX()  
	--local px = playerData.unit:GetOrientationX()  
	--local dot = UTILS.VecDot(cx, px) 
	--env.info("DOT: " .. dot)

	-- Orientation of carrier.
	--local position = playerData.unit:GetVec3()
	--local dx, dy, dz = GetRelativePositionToCarrier(position)
	--env.info(dx .. ", " .. dz)

	--env.info(position.y)

	if(printDebugGlideslopeFeedback) then
		dx, dy, dz = AdjustDeltasToMatchFocalPoint(dx, dy, dz)
		PrintGlideslopeFeedback(GetGlideslope(dx, dy, dz), 3.5, playerData)
	end
	
	if(printDebugLineupFeedback) then
		HandleLSO(playerData)
	end 
end

function Init(id, patternModeZone)	
	if(case == 1 and patternModeZone ~= patternMode) then
		return
	end

	local playerData = nil
	
	local existingData = playerDatas[id]
	if(existingData and existingData.unit:IsAlive()) then
		playerData = playerDatas[id]
	else	
		playerData = PlayerData:New(id)
	end

	playerData:InitNewRound()

	playerDatas[id] = playerData
	env.info("Created playerData object for " .. playerData.unit.UnitName)

	if(not playerData.hasShownVersionMessage) then
		SendMessageToPlayer("Running Bankler's CASE 1 Recovery Trainer v " .. scriptVersion, 3, playerData)
		playerData.hasShownVersionMessage = true
	end
	
	local patternModeText = ""
	
	playerData.step = startingStep -- 1 !!
	if(case == 1 and patternMode) then
		patternModeText = "[PATTERN MODE] "
	end
	
	local brcText = ""
	
	if(brc > -1) then
		brcText = ", BRC " .. brc .. ""
	end 
	
	MessageToAllIncludingSpectators( patternModeText .. "Welcome back, " .. playerData.playerName .. " (" .. playerData.modex .. ", " .. playerData.fixedCallsign .. ")! Initial! TCN " .. carrierTCN .. brcText .. ".", 5 )
	--PrintTestSummary(playerData) --!!
	
	playerData.highestCarrierXDiff = -9999999
	playerData.secondsStandingStill = 0
	playerData.summary = ""
	
	sfx_Reset:Play()
end

function PrintTestSummary(playerData)
	local summary = ""
	summary = summary .. "Break:\n"
	summary = summary .. "• On altitude entering the break\n"
	summary = summary .. "• On altitude in the early break\n"
	summary = summary .. "• On altitude in the late break break\n"
	summary = summary .. "Pattern:\n"
	summary = summary .. "• On altitude with perfect distance abeam\n"
	summary = summary .. "• On altitude at the 90\n"
	summary = summary .. "• Little hight at the wake\n"
	summary = summary .. "Groove:"
	summary = summary .. "• Start: Low\n"
	summary = summary .. "• Middle: On altitude\n"
	summary = summary .. "• Close: On altitude\n"
	summary = summary .. "• Groove time: 23.5\n"
	summary = summary .. "• Trapped catching the 3-wire\n"
		
	SendMessageToPlayer(summary, 8, playerData)
	
	SendMessageToPlayer("Bankler (Chevy 1-1)'s 4 passes: 68 (4w), 64 (3W), 40 (Bolter), 45 (2W), 64 (3W), 40 (Bolter), 45 (2W), 64 (3W), 40 (Bolter), 45 (2W), 64 (3W), 40 (Bolter), 45 (2W) (TOTAL: 238)", 8, playerData)
	
	SendMessageToPlayer("Return 4 nm aft (over the trailing ship) to restart the exercise.", 8, playerData)
end

function SendInFlightFeedbackToPlayer(message, duration, playerData)
	if(inFlightFeedback) then
		SendMessageToPlayer(message, duration, playerData)
	end
end

function SendMessageToPlayer(message, duration, playerData)
	if(sendPlayerFeedbackToAllPlayers) then
		MessageToAllIncludingSpectators(message, duration)
	else
		if(playerData.client) then
			MESSAGE:New( message, duration, ""):ToClient(playerData.client)
		end
	end
end

function MessageToAllIncludingSpectators(message, duration)
	MESSAGE:New( message, duration, "" ):ToAll()
end

function Start(playerData)
	if(patternMode) then
		--Pattern mode was activated when we had already triggered a break run.
		local hint = "Pattern mode is active. Continue past the ship at least 0.5 nm before breaking."
		SendMessageToPlayer(hint, 5, playerData)
		playerData.step = 0
		return
	end

	local speedText = "350"
	if(playerData.isGoshawk) then
		speedText = "300"
	end
	
	local hint = "Entering the break, " .. playerData.playerName .. " (" .. playerData.modex .. ", " .. playerData.fixedCallsign .. ")! Aim for 800 feet and " .. speedText .. " kts in the break entry."
	SendInFlightFeedbackToPlayer(hint, 8, playerData)
	playerData.score = 0
	playerData.step = 2
end	
  
function Upwind(playerData)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)
	
	local px = playerData.unit:GetOrientationX()  
	local cz = carrier:GetOrientationZ()  
	local dotZ = UTILS.VecDot(cz, px)  -- dotZ < 0 means that we are heading port

	if(dx > -1000) then
		local velocityKnots = UTILS.Round(playerData.unit:GetVelocityKNOTS())
		if(velocityKnots > playerData.shbSpeed) then
			playerData.shbSpeed = velocityKnots
			--SendInFlightFeedbackToPlayer("" .. playerData.shbSpeed .. " Kts", 2,  playerData)
		end
	end

	if(dz < -10 and dotZ < -0.259) then --A small bit to the left and also heading more left (dot == -0.259 means 15 degrees left)
		SendInFlightFeedbackToPlayer("Shit Hot Break (" .. playerData.shbSpeed .. " kts)", 5, playerData)
		playerData.shitHotBreak = true;
		playerData.step = 6 --Next step is the 90
		return
	end
	
	if(dz > 1200 or dz < -1200 or dx < -4000) then
		AbortPattern(playerData, "Too far from the boat when entering the break")
		return
	end
	
	if(dx < 400 or dz < 0) then return end
	
	local idealAltitude = 800
	local altitude = UTILS.Round( UTILS.MetersToFeet( position.y ) )

	local hint = "• "
	local score = 0

	if(altitude > 900) then
		score = 0
		hint = hint .. "Very high entering the break (out of CTS)"
	elseif(altitude > 875) then
		score = 1
		hint = hint .. "Very high entering the break"
	elseif(altitude > 850) then
		score = 2
		hint = hint .. "High entering the break"
	elseif(altitude > 825) then
		score = 3
		hint = hint .. "Little high entering the break"
	elseif(altitude > 775) then
		score = 4
		hint = hint .. "On altitude entering the break"
	elseif(altitude > 750) then
		score = 3
		hint = hint .. "Little low entering the break"
	elseif(altitude > 725) then
		score = 2
		hint = hint .. "Low entering the break"
	elseif(altitude > 700) then
		score = 1
		hint = hint .. "Very low entering the break"
	else
		score = 0
		hint = hint .. "Very low entering the break (out of CTS)"		
	end
	
	hint = hint .. GetStepScoreString(score, 4)	
	playerData:IncreaseScore(score)	
	SendInFlightFeedbackToPlayer(hint, 8, playerData)	
	PrintAltitudeFeedback(altitude, idealAltitude, playerData)
	playerData:AddToSummary("Break:")	
	playerData:AddToSummary(hint)
	playerData.shitHotBreak = false
	playerData.step = 3
end

function Break(playerData, part)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)

	if(dz > 1500 or dz < -3700) then
		AbortPattern(playerData, "Too far offset in the break")
		return
	elseif(dx < -200) then
		AbortPattern(playerData, "Too tight break turn")
		return
	end

	local limit = -370
		
	if(part == "late") then
		limit = -1470
	end

	if dz < limit then
		local idealAltitude = 800
		local altitude = UTILS.Round( UTILS.MetersToFeet( position.y ) )

		local hint = "• "
		local score = 0

		if(altitude > 900) then
			score = 0
			hint = hint .. "Very high in the " .. part .. " break (out of CTS)"
		elseif(altitude > 875) then
			score = 1
			hint = hint .. "Very high in the " .. part .. " break"
		elseif(altitude > 850) then
			score = 2
			hint = hint .. "High in the " .. part .. " break"
		elseif(altitude > 825) then
			score = 3
			hint = hint .. "Little high in the " .. part .. " break"
		elseif(altitude > 775) then
			score = 4
			hint = hint .. "On altitude in the " .. part .. " break"
		elseif(altitude > 750) then
			score = 3
			hint = hint .. "Little low in the " .. part .. " break"
		elseif(altitude > 725) then
			score = 2
			hint = hint .. "Low in the " .. part .. " break"
		elseif(altitude > 700) then
			score = 1
			hint = hint .. "Very low in the " .. part .. " break"
		else
			score = 0
			hint = hint .. "Very low in the " .. part .. " break (out of CTS)"
		end
		
		hint = hint .. GetStepScoreString(score, 4)		
		playerData:IncreaseScore(score)		
		SendInFlightFeedbackToPlayer( hint, 8, playerData )
		PrintAltitudeFeedback(altitude, idealAltitude, playerData)	
		playerData:AddToSummary(hint)

		if(part == "early") then
			playerData.step = 4
		else
			playerData.step = 5
		end
	end
end

function Abeam(playerData)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)
	
	if(dz > -1000 and not patternMode) then
		env.info("Distance to carrier: " .. dz)
		AbortPattern(playerData, "Too close to the carrier")
		return
	elseif(dz < -3700) then
		env.info("Distance to carrier: " .. dz)
		AbortPattern(playerData, "Too far from the carrier")
		return
	end
	
	local limit = -200
	
	if dx < limit then
		local aoa = playerData.unit:GetAoA()	
		local onSpeedScore = GetOnSpeedScore(aoa, playerData)	
		local idealAltitude = 600
		local altitude = UTILS.Round( UTILS.MetersToFeet( position.y ) )
		local hint = "• "
		local score = 0

		if(altitude > 700) then
			score = 0
			hint = hint .. "Very high (" .. altitude .. " ft) (out of CTS)"
		elseif(altitude > 675) then
			score = 1
			hint = hint .. "Very high (" .. altitude .. " ft)"
		elseif(altitude > 650) then
			score = 2
			hint = hint .. "High (" .. altitude .. " ft)"
		elseif(altitude > 625) then
			score = 3
			hint = hint .. "Little high (" .. altitude .. " ft)"
		elseif(altitude > 575) then
			score = 4
			hint = hint .. "On altitude (" .. altitude .. " ft)"
		elseif(altitude > 550) then
			score = 3
			hint = hint .. "Little low (" .. altitude .. " ft)"
		elseif(altitude > 525) then
			score = 2
			hint = hint .. "Low (" .. altitude .. " ft)"
		elseif(altitude > 500) then
			score = 1
			hint = hint .. "Very low (" .. altitude .. " ft)"
		else
			score = 0
			hint = hint .. "Very low (" .. altitude .. " ft) (out of CTS)"	
		end

		local distanceHint = ""
		local distanceScore		
		local nm = -dz / 1852 --nm conversion
		local idealDistance = 1.2		
		local roundedNm = UTILS.Round(nm,2)
		
		if(playerData.isGoshawk) then
			nm = nm + 0.2 --A little hacky, but pragmatic approach.
			idealDistance = 1.0
		end
		
		if(nm < 1.0) then
			distanceScore = 0
			distanceHint = "too close (" .. roundedNm .. " nm) (out of CTS) abeam"
		elseif(nm < 1.1) then
			distanceScore = 2
			distanceHint = "too close (" .. roundedNm .. " nm) abeam"
		elseif(nm < 1.4) then
			distanceScore = 4
			distanceHint = "with perfect distance (" .. roundedNm .. " nm) abeam"
		elseif(nm < 1.5) then
			distanceScore = 3
			distanceHint = "little wide (" .. roundedNm .. " nm) abeam"
		elseif(nm < 1.6) then
			distanceScore = 1
			distanceHint = "too wide (" .. roundedNm .. " nm) abeam"
		else
			distanceScore = 0
			distanceHint = "too wide (" .. roundedNm .. " nm) (out of CTS) abeam"
		end
		
		local declutteredAoAFeedback = GetDeclutteredAoAFeedback(aoa, playerData)
		local scoreString = GetStepScoreString(score + distanceScore + onSpeedScore, 11)	
		local fullHint = hint .. ", " .. distanceHint .. declutteredAoAFeedback .. scoreString
		
		SendInFlightFeedbackToPlayer( fullHint, 8, playerData )
		SendInFlightFeedbackToPlayer( "(Target: 600 ft and " .. idealDistance .. " nm)", 8, playerData )
		playerData:IncreaseScore(score + distanceScore + onSpeedScore)
		playerData:AddToSummary("Pattern:")
		playerData:AddToSummary(fullHint)
		playerData.step = 6
		
		--GiveLSOFeedback("PaddlesContact", playerData)	
	end
end

function CheckForLongDownwind(playerData)
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)

	--local limit = -1500 --0.8 nm
	local limit = -1250 -- 0.67 nm
	
	if(playerData.isTomcat) then
		--limit = -2780
		limit = -1800
	end
	
	if(playerData.shitHotBreak) then
		limit = -1800 --Allow some extra wiggle room
	end
	
	if dx < limit then
		local cx = carrier:GetOrientationX()  
		local px = playerData.unit:GetOrientationX()  
		local dot = UTILS.VecDot(cx, px)  -- dot > 0 means that we are past 90 degrees and about to align
		
		if(dot < -0.98) then  -- About 10 degrees off.
			local score = -10
			if(playerData.shitHotBreak) then
				score = -20 --Punish harder if screwing up a SHB
			end
			
			local hint = "• Too long downwind. Turn final earlier next time. - " .. score
			SendInFlightFeedbackToPlayer( hint, 8, playerData )
			
			playerData:IncreaseScore(score)
			playerData:AddToSummary(hint)
			playerData.longDownwindChecked = true
			playerData.longDownwind = true
		end
	end
end

function Ninety(playerData)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)

	if(not playerData.shitHotBreak) then
		if(dz < -3700 or dx < -3700 or dx > 0) then
			AbortPattern(playerData, "Too far out in the 90")
			return
		end
	end
	
	local cx = carrier:GetOrientationX()  
	local px = playerData.unit:GetOrientationX()  
	local dot = UTILS.VecDot(cx, px)  -- dot > 0 means that we are 90 degrees and about to align
	
	local cz = carrier:GetOrientationZ()  
	local dotZ = UTILS.VecDot(cz, px)  -- dotZ > 0 means that we are heading starboard
	
	if (dot > 0 and dotZ > 0) then 
		
		--SHB Handling
		if(playerData.shitHotBreak) then
			if(not playerData.longDownwind) then
				local hint = "• Shit Hot Break Bonus - 30/30 (" .. playerData.shbSpeed .. " kts)"
				SendInFlightFeedbackToPlayer(hint, 8, playerData )
				playerData:AddToSummary(hint)
				playerData:IncreaseScore(30)
			end
			playerData.longDownwindChecked = true
			playerData.step = 7
			return
		end
		-----
	
		local idealAltitude = 450
		local altitude = UTILS.Round( UTILS.MetersToFeet( position.y ) )

		local hint = "• "
		local score = 0

		if(altitude > 575) then
			score = 0
			hint = hint .. "Very high at the 90 (out of CTS)"
		elseif(altitude > 550) then
			score = 1
			hint = hint .. "Very high at the 90"
		elseif(altitude > 525) then
			score = 2
			hint = hint .. "High at the 90"
		elseif(altitude > 502) then
			score = 3
			hint = hint .. "Little high at the 90"
		elseif(altitude > 448) then
			score = 4
			hint = hint .. "On altitude at the 90"
		elseif(altitude > 425) then
			score = 2
			hint = hint .. "Little low at the 90"
		elseif(altitude > 400) then
			score = 1
			hint = hint .. "Low at the 90"
		else
			score = 0
			hint = hint .. "Very low at the 90 (out of CTS)"	
		end
	
		local aoa = playerData.unit:GetAoA()		
		local onSpeedScore = GetOnSpeedScore(aoa, playerData)

		playerData:IncreaseScore(score + onSpeedScore)
	
		local declutteredAoAFeedback = GetDeclutteredAoAFeedback(aoa, playerData)
		local scoreString = GetStepScoreString(score + onSpeedScore, 7)
		
		hint = hint .. declutteredAoAFeedback .. scoreString
	
		SendInFlightFeedbackToPlayer( hint, 8, playerData )
		PrintAltitudeFeedback(altitude, idealAltitude, playerData, 50)
		
		playerData:AddToSummary(hint)
		playerData.longDownwindChecked = true
		playerData.step = 7
	end
end

function Wake(playerData)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)
	
	if(dz < -2000 or dx < -4000 or dx > 0) then
		AbortPattern(playerData, "Too far away from the wake")
		return
	end
	
	if dz > 0 and dx > -4000 then
	
		local idealAltitude = 370
		local altitude = UTILS.Round( UTILS.MetersToFeet( position.y ) )

		local hint = "• "
		local score = 0

		if(altitude > 475) then
			score = 0
			hint = hint .. "Very high at the wake (out of CTS)"
		elseif(altitude > 450) then
			score = 1
			hint = hint .. "Very high at the wake"
		elseif(altitude > 425) then
			score = 2
			hint = hint .. "High at the wake"
		elseif(altitude > 400) then
			score = 3
			hint = hint .. "Little high at the wake"
		elseif(altitude > 350) then
			score = 4
			hint = hint .. "On altitude at the wake"
		elseif(altitude > 325) then
			score = 2
			hint = hint .. "Little low at the wake"
		elseif(altitude > 300) then
			score = 1
			hint = hint .. "Low at the wake"
		else
			score = 0
			hint = hint .. "Very low at the wake (out of CTS)"	
		end
		
		local aoa = playerData.unit:GetAoA()
		local aoaFeedback = PrintAoAFeedback(aoa, playerData)		
		local onSpeedScore = GetOnSpeedScore(aoa, playerData)

		playerData:IncreaseScore(score + onSpeedScore)

		local declutteredAoAFeedback = GetDeclutteredAoAFeedback(aoa, playerData)
		local scoreString = GetStepScoreString(score + onSpeedScore, 7)
		
		hint = hint .. declutteredAoAFeedback .. scoreString

		SendInFlightFeedbackToPlayer( hint, 8, playerData )
		PrintAltitudeFeedback(altitude, idealAltitude, playerData)
		playerData:AddToSummary(hint)
		playerData.step = 8
	end
end

function Groove(playerData)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)
	dx, dy, dz = AdjustDeltasToMatchFocalPoint(dx, dy, dz)
	local lineupError = GetLineupError(dx, dy, dz)

	if(abortsActive and (dx > 0 or dx < -4000) and case < 3) then
		AbortPattern(playerData, "Didn't enter the groove")
		return
	end
		
	if(dx > -250) then --Reached in close before groove
		local scoreString = GetStepScoreString(0, 7)
		local hint = "• You're too far left and never reached the groove." .. scoreString
		SendInFlightFeedbackToPlayer( hint, 8, playerData )
		playerData:AddToSummary(hint)
		playerData.step = 9
	else	
		local roll = playerData.unit:GetRoll()
		local absRoll = math.abs(roll)
		
		if(lineupError > playerData.highestLineupError) then
			playerData.highestLineupError = lineupError
		end
		
		--env.info("Lineup error: " .. lineupError .. ", Roll: " .. absRoll .. ", dx: " .. dx .. ", Highest Lineup Error: " .. playerData.highestLineupError)		
		if dx > -1500 then			
			local crossedCenterlineLimit = -0.6 -- within 0.6 degrees offset of FB.
			local crossedWingsLevelLimit = -3.2 -- within 3-4 degrees offset of FB.					
			local crossedCenterline = lineupError > crossedCenterlineLimit 		
			local crossedWingsLevel = lineupError > crossedWingsLevelLimit and absRoll < 4			
			local enteredGroove = crossedCenterline or crossedWingsLevel
			
			if enteredGroove then
				--env.info("Start - Roll: " .. absRoll .. ", Lineup Error: " .. lineupError)
				--SendMessageToPlayer("Start - Roll: " .. absRoll .. ", Lineup Error: " .. lineupError, 2, playerData ) --!!
			
				local idealAltitude = 300
				local altitude = UTILS.Round( UTILS.MetersToFeet( position.y ) )
				local hint = "• "
				local score = 0
				
				local glideslope = GetGlideslope(dx, dy, dz)
				local lineupDrift = (lineupError - playerData.lastLineupError) * deltaTime
				--SendMessageToPlayer( "Lineup drift: " .. lineupDrift, 4, playerData )
				
				playerData:AddToSummary("Groove:")
				
				if(glideslope > 4.35) then
					score = 0
					hint = hint .. "Start: CLARA High"
				elseif(glideslope > 3.9) then
					score = 3
					hint = hint .. "Start: High"
				elseif(glideslope > 3.3) then
					score = 4
					hint = hint .. "Start: On altitude"
				elseif (glideslope > 3.1) then
					score = 1
					hint = hint .. "Start: Low"
				elseif (glideslope > 2.7) then
					score = 0
					hint = hint .. "Start: Low RED"
				else
					score = 0
					hint = hint .. "Start: CLARA Low"
				end

				local aoa = playerData.unit:GetAoA()				
				local onSpeedScore = GetOnSpeedScore(aoa, playerData)
				
				--Special handling for Start step
				
				local lineupScore = 0;
				local lineupHint = ""
				if(playerData.highestLineupError > 2.75) then
					lineupScore = -3;
					lineupHint = " (Heavy overshoot)"
				elseif(playerData.highestLineupError > 2.00) then
					lineupScore = -2;
					lineupHint = " (Overshoot)"
				elseif(playerData.highestLineupError > 1.25) then
					lineupScore = -1;
					lineupHint =  " (Little overshoot)"
				elseif(lineupError > -1.25) then
					lineupScore = 0;
				elseif(absRoll < 4) then
					if(lineupError > -2.00) then
						lineupScore = -1;
						lineupHint = " (Slightly angling approach)"
					elseif(lineupError > -2.75) then
						lineupScore = -2;
						lineupHint = " (Angling approach)"
					else
						lineupScore = -3;
						lineupHint = " (Heavily angling approach)"
					end
				end
				
				local stepScore = score + onSpeedScore + lineupScore
				playerData:IncreaseScore(stepScore)
	
				local declutteredAoAFeedback = GetDeclutteredAoAFeedback(aoa, playerData)
				local scoreString = GetStepScoreString(stepScore, 7)				
				local fullHint = hint .. declutteredAoAFeedback .. lineupHint .. scoreString
				
				SendInFlightFeedbackToPlayer( fullHint, 4, playerData )
				playerData:AddToSummary(fullHint)				
				playerData.step = 9
				
				playerData.highestLineupError = 0
				playerData.lowestLineupError = 0
			end
		end
		
		playerData.lastLineupError = lineupError;
	end
end

function GetLineupScore(lineupError, lineupDrift, playerData)
	local lineupScore = 0;
	local lineupHint = ""
	
	--local absDrift = math.abs(lineupDrift)
	local driftedLeft = lineupDrift < -0.0
	local driftedRight = lineupDrift > 0.0
	
	--env.info("Highest Lineup Error: " .. playerData.highestLineupError)
	
	if(lineupError > 2.75) then
		lineupScore = -3;
		lineupHint = " (Lined up far right)"
		if(driftedRight) then
			lineupScore = -4;
			lineupHint = " (Drifted far right)"
		end
	elseif(lineupError > 2.00) then
		lineupScore = -2;
		lineupHint = " (Lined up right)"
		if(driftedRight) then
			lineupScore = -3;
			lineupHint = " (Drifted right)"
		end
	elseif(lineupError > 1.25) then
		lineupScore = -1;
		lineupHint = " (Lined up a little right)"
		if(driftedRight) then
			lineupScore = -2;
			lineupHint = " (Drifted a little right)"
		end
	elseif(lineupError > 0.75) then
		--Good, as long as we're correcting in the right direction
		lineupScore = 0;
		if(driftedRight) then
			lineupScore = -1;
			lineupHint = " (Drifted slightly right)"
		end
	elseif(lineupError > -0.75) then
		lineupScore = 0;
		--PERFECT 
	elseif(lineupError > -1.25) then
		--Good, as long as we're correcting in the right direction
		lineupScore = 0;
		if(driftedLeft) then
			lineupScore = -1;
			lineupHint = " (Drifted slightly left)"
		end
	elseif(lineupError > -2.00) then
		lineupScore = -1;
		lineupHint = " (Lined up a little left)"
		if(driftedLeft) then
			lineupScore = -2;
			lineupHint = " (Drifted a little left)"
		end
	elseif(lineupError > -2.75) then
		lineupScore = -2;
		lineupHint = " (Lined up left)"
		if(driftedLeft) then
			lineupScore = -3;
			lineupHint = " (Drifted left)"
		end
	else
		lineupScore = -3;
		lineupHint = " (Lined up far left)"
		if(driftedLeft) then
			lineupScore = -4;
			lineupHint = " (Drifted far left)"
		end
	end
	
	--If everything looked good, we make a final check to see if the player at any time was outside the 1.25 limit.
	if(lineupScore == 0) then
		if(playerData.lowestLineupError < -1.25) then
			lineupScore = -1;
			lineupHint = " (Corrected left lineup)"
			env.info("Momentarily outside < -1.25");
		end
		if(playerData.highestLineupError > 1.25) then
			lineupScore = -1;
			lineupHint = " (Corrected right lineup)"
			env.info("Momentarily outside > 1.25");
		end
	end
	
	--SendMessageToPlayer( "Lineup error: " .. lineupError .. ", Lineup drift: " .. lineupDrift, 4, playerData )
	
	return lineupScore, lineupHint
end

function UpdateHighLowLineupError(lineupError, playerData)
	if(lineupError < playerData.lowestLineupError) then
		playerData.lowestLineupError = lineupError
	end

	if(lineupError > playerData.highestLineupError) then
		playerData.highestLineupError = lineupError
	end
end

function Middle(playerData)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)	
	dx, dy, dz = AdjustDeltasToMatchFocalPoint(dx, dy, dz)
	local lineupError = GetLineupError(dx, dy, dz)

	if(abortsActive and (dx > 0 or dx < -4000)) then
		AbortPattern(playerData, "Departed before reaching the middle")
		return
	end
	
	HandleLSO(playerData)
	
	playerData.grooveTime = playerData.grooveTime + deltaTime
	UpdateHighLowLineupError(lineupError, playerData)
	
	if dx > -800 then
		local hint = ""
		local score = 0
		
		local glideslope = GetGlideslope(dx, dy, dz)
		local lineupDrift = (lineupError - playerData.lastLineupError) * deltaTime
		
		hint = "• "
		
		if(glideslope > 4.35) then
			score = 0
			hint = hint .. "Middle: CLARA High"
		elseif(glideslope > 3.9) then
			score = 3
			hint = hint .. "Middle: High"
		elseif(glideslope > 3.3) then
			score = 4
			hint = hint .. "Middle: On altitude"
		elseif (glideslope > 3.1) then
			score = 1
			hint = hint .. "Middle: Low"
		elseif (glideslope > 2.7) then
			score = 0
			hint = hint .. "Middle: Low RED"
		else
			score = 0
			hint = hint .. "Middle: CLARA Low"
		end
		
		local aoa = playerData.unit:GetAoA()	
		local onSpeedScore = GetOnSpeedScore(aoa, playerData)
		
		local lineupScore, lineupHint = GetLineupScore(lineupError, lineupDrift, playerData)
		
		local stepScore = score + onSpeedScore + lineupScore
		playerData:IncreaseScore(stepScore)

		local declutteredAoAFeedback = GetDeclutteredAoAFeedback(aoa, playerData)			
		local scoreString = GetStepScoreString(stepScore, 7)			
		local fullHint = hint .. declutteredAoAFeedback .. lineupHint .. scoreString

		SendInFlightFeedbackToPlayer( fullHint, 4, playerData )		
		playerData:AddToSummary(fullHint)		
		playerData.step = 10
		playerData.highestLineupError = 0
		playerData.lowestLineupError = 0
	end

	playerData.lastLineupError = lineupError;
end

function InClose(playerData)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)
	dx, dy, dz = AdjustDeltasToMatchFocalPoint(dx, dy, dz)
	local lineupError = GetLineupError(dx, dy, dz)
	
	if(abortsActive and (dx > 0 or dx < -4000)) then
		AbortPattern(playerData, "Departed before reaching in-close")
		return
	end
	
	HandleLSO(playerData)
		
	playerData.grooveTime = playerData.grooveTime + deltaTime
	UpdateHighLowLineupError(lineupError, playerData)
	
	if dx > -400 then
		local glideslope = GetGlideslope(dx, dy, dz)
		local lineupDrift = (lineupError - playerData.lastLineupError) * deltaTime
		
		local hint = ""
		local score = 0
		
		hint = "• "
		
		if(glideslope > 4.35) then
			score = 0
			hint = hint .. "Close: CLARA High"
		elseif(glideslope > 3.9) then
			score = 3
			hint = hint .. "Close: High"
		elseif(glideslope > 3.3) then
			score = 4
			hint = hint .. "Close: On altitude"
		elseif (glideslope > 3.1) then
			score = 1
			hint = hint .. "Close: Low"
		elseif (glideslope > 2.7) then
			score = 0
			hint = hint .. "Close: Low RED"
		else
			score = 0
			hint = hint .. "Close: CLARA Low"
		end
		
		local aoa = playerData.unit:GetAoA()
		local onSpeedScore = GetOnSpeedScore(aoa, playerData)
		
		local lineupScore, lineupHint = GetLineupScore(lineupError, lineupDrift, playerData)
		
		local stepScore = score + onSpeedScore + lineupScore
		playerData:IncreaseScore(stepScore)

		local declutteredAoAFeedback = GetDeclutteredAoAFeedback(aoa, playerData)			
		local scoreString = GetStepScoreString(stepScore, 7)			
		local fullHint = hint .. declutteredAoAFeedback .. lineupHint .. scoreString

		SendInFlightFeedbackToPlayer( fullHint, 4, playerData )		
		playerData:AddToSummary(fullHint)		
		playerData.step = 11
		playerData.highestLineupError = 0
		playerData.lowestLineupError = 0
	end
	
	playerData.lastLineupError = lineupError;
end

function AtTheRamp(playerData)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)
	dx, dy, dz = AdjustDeltasToMatchFocalPoint(dx, dy, dz)
	local lineupError = GetLineupError(dx, dy, dz)
	
	if(abortsActive and (dx > 0 or dx < -4000)) then
		AbortPattern(playerData, "Didn't get to the ramp")
		return
	end
		
	if(dx < -250) then
		HandleLSO(playerData)
	end
		
	local fractionZ = dz / (-dx)
	local asinValueZ = math.asin(fractionZ)
	local angleZ = math.deg(asinValueZ)
	
	local roll = playerData.unit:GetRoll()
	local absRoll = math.abs(roll)
	
	playerData.grooveTime = playerData.grooveTime + deltaTime
	UpdateHighLowLineupError(lineupError, playerData)
	
	if dx > -200 then
		local glideslope = GetGlideslope(dx, dy, dz)
		local lineupDrift = (lineupError - playerData.lastLineupError) * deltaTime
		
		local vv = GetUnitVerticalVelocity(playerData.unit)		
		local didSettle = false
		local vvDiff_1 = playerData.verticalVelocityArray[1] - playerData.verticalVelocityArray[2]
		
		--Always treat < -1000 fpm as settled. Otherwise, if we fall with -600 or worse, check so the VV hasn't decreased more than a certain amount the last second (if it has, it means they settled).
		if(vv < -1000) then
			didSettle = true
		elseif (vv < - 700 and vvDiff_1 < -40) then
			didSettle = true
		end
		
		local settleHint = ""
		if(didSettle) then
			settleHint = " (Settled)"
		end
		
		--local vvHint = "VV: " .. UTILS.Round(vv) .. ", VV ACCELERATION: " .. UTILS.Round(vvDiff_1) .. settleHint
		--MessageToAllIncludingSpectators(vvHint, 15)
		
		local hint = ""
		local score = 0

		hint = "• "
		
		if(glideslope > 4.35) then
			score = 0
			hint = hint .. "Ramp: CLARA High" .. settleHint
		elseif(glideslope > 3.9) then
			score = 3
			hint = hint .. "Ramp: High" .. settleHint
		elseif(glideslope > 3.3) then
			score = 4
			hint = hint .. "Ramp: On altitude" .. settleHint
		elseif (glideslope > 3.1) then
			score = 1
			hint = hint .. "Ramp: Low" .. settleHint
		elseif (glideslope > 2.7) then
			score = 0
			hint = hint .. "Ramp: Low RED" .. settleHint
		else
			score = 0
			hint = hint .. "Ramp: CLARA Low" .. settleHint
		end		

		local aoa = playerData.unit:GetAoA()
		local onSpeedScore = GetOnSpeedScore(aoa, playerData)
		
		local lineupScore, lineupHint = GetLineupScore(lineupError, lineupDrift, playerData)
		
		local stepScore = score + onSpeedScore + lineupScore
		playerData:IncreaseScore(stepScore)

		local declutteredAoAFeedback = GetDeclutteredAoAFeedback(aoa, playerData)		
		local scoreString = GetStepScoreString(stepScore, 7)			
		local fullHint = hint .. declutteredAoAFeedback .. lineupHint .. scoreString
		
		SendInFlightFeedbackToPlayer( fullHint, 4, playerData )		
		playerData:AddToSummary(fullHint)		
		
		if(didSettle) then
			playerData.didSettle = true
			playerData:IncreaseScore(-10)
			local minusForSettleHint = "• Settled at the ramp - (-10)"
			SendInFlightFeedbackToPlayer( minusForSettleHint, 8, playerData )
			playerData:AddToSummary(minusForSettleHint)	
		end
		
		playerData.step = 12
		playerData.highestLineupError = 0
		playerData.lowestLineupError = 0
	end
	
	playerData.lastLineupError = lineupError;
end

function Trap(playerData)	
	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)
	
	local playerVelocity = playerData.unit:GetVelocityKMH()
	local carrierVelocity = carrier:GetVelocityKMH()
	
	if(abortsActive and (dz < -2000 or dz > 2000 or dx < -3000)) then
		AbortPattern(playerData, "Too far from the boat when about to trap")
		return
	end

	--SendMessageToPlayer("Y: " .. position.y, 1, playerData )
	
	local deckAltitude = 23
	if(playerData.isTomcat) then
		deckAltitude = 22
	end
	
	if(not playerData.hasReachedTrapAltitude) then
		if(position.y < deckAltitude ) then
			playerData.hasReachedTrapAltitude = true
			if(case < 3) then
				HandleGrooveTimeScore(playerData)
			end
		else
			playerData.grooveTime = playerData.grooveTime + deltaTime
		end
	end
	
	if(dx < -250) then
		HandleLSO(playerData)
	end

	if(dx > playerData.highestCarrierXDiff) then
		playerData.highestCarrierXDiff = dx
	end
	
	if(position.y < playerData.lowestAltitude) then
		playerData.lowestAltitude = position.y
	end
	
	local speedDiff = math.abs(playerVelocity - carrierVelocity)
	
	if(position.y < deckAltitude and not hasIdentifiedTrapSlowdown) then
		if(speedDiff < 5) then
			SendMessageToPlayer( "Trap! Cut power and stand still until score is presented!", 5, playerData )
			hasIdentifiedTrapSlowdown = true
		end
	end
	
	if speedDiff < 0.3 then
		playerData.secondsStandingStill = playerData.secondsStandingStill + deltaTime
	
		local pullback = playerData.highestCarrierXDiff - dx
		--local hasStoppedInWire = dx < playerData.highestCarrierXDiff - 1.75 or (dx < playerData.highestCarrierXDiff - 1.0 and playerData.secondsStandingStill > 5)
		local hasStoppedInWire = pullback > 1.75 or (pullback > 1.0 and playerData.secondsStandingStill > 5)
		
		if((not hasStoppedInWire) and (playerData.isTomcat or playerData.isGoshawk)) then
			hasStoppedInWire = playerData.secondsStandingStill > 2
		end
		
		--I you have been pulled back 1.75 meters, OR (if you have been pulled back at least a little, and stayed still for a while.
		if hasStoppedInWire then
			
			env.info("Trap identified! diff " .. dx .. ",  highestCarrierXDiff" .. playerData.highestCarrierXDiff .. ", secondsStandingStill: " .. playerData.secondsStandingStill)
				
			local wire = 1
			local score = -5
			
			if(playerData.isGoshawk) then
				if(dx < -44) then
					wire = 1
					score = 1
				elseif(dx < -36) then
					wire = 2
					score = 2			
				elseif (dx < -22) then
					wire = 3
					score = 5
				else
					wire = 4
					score = 3
				end
			else
				if(dx < -14) then
					wire = 1
					score = 1
				elseif(dx < -2) then -- previously -3 (Adjusted for Tomcat. -2.82 and -2.49 should be 2.wire
					wire = 2
					score = 2			
				elseif (dx < 10) then
					wire = 3
					score = 5
				else
					wire = 4
					score = 3
				end
			end
			if printDebugWireFeedback then
				SendMessageToPlayer("Distance! " .. UTILS.Round(dx, 3) .. " meters resulted in a " .. wire .. "-wire estimation after " .. UTILS.Round(pullback, 3) .. " meters pullback.", 15, playerData)
			end
			
			playerData:IncreaseScore(score)

			local scoreString = GetStepScoreString(score, 5)
			
			SendMessageToPlayer( "" .. wire .. "-wire! " .. scoreString, 30, playerData )
			env.info("Distance! " .. dx .. " meters resulted in a " .. wire .. "-wire estimation.")
			
			hint = "• "
			local fullHint = "• Trapped catching the " .. wire .. "-wire" .. scoreString
			
			playerData:AddToSummary(fullHint)
			
			playerData:AddToSummary("Score: " .. playerData.score .. " / " .. maxScore)
			
			PrintFinalScore(playerData, 60, wire)
			HandleCollectedResult(playerData, wire)
			playerData.step = 0
		end
	elseif (dx > 150) then
		
		local wire = 0
		local hint = ""
		local score = 0
		if(playerData.lowestAltitude < 23) then
			hint = "• You boltered"
		else
			hint = "• You were waved off"
			wire = -1
			score = -5
		end
		
		local scoreString = GetStepScoreString(score, 5)
		
		hint = hint .. scoreString
		
		SendMessageToPlayer( hint, 8, playerData )
		
		playerData:AddToSummary(hint)		
		playerData:AddToSummary("Score: " .. playerData.score .. " / " .. maxScore)
		
		PrintFinalScore(playerData, 60, wire)
		HandleCollectedResult(playerData, wire)
		playerData.step = 0
	end	
end

function HandleGrooveTimeScore(playerData)
	local grooveTime = playerData.grooveTime
	
	hint = "• "
	local score = 0
	
	if(grooveTime > 23) then
		score = 0
		hint = hint .. "Groove time: " .. grooveTime .. " (Very long)"
	elseif(grooveTime >= 18.5) then
		score = 3
		hint = hint .. "Groove time: " .. grooveTime .. " (Long)"
	elseif(grooveTime >= 14.5) then
		score = 5
		hint = hint .. "Groove time: " .. grooveTime .. " (Perfect)"
	elseif (grooveTime >= 10) then
		score = 3
		hint = hint .. "Groove time: " .. grooveTime .. " (Short)"
	else
		score = 0
		hint = hint .. "Groove time: " .. grooveTime .. " (Very short)"
	end	
	
	local scoreString = GetStepScoreString(score, 5)
	hint = hint .. scoreString
	
	playerData:IncreaseScore(score)
	playerData:AddToSummary(hint)
end

function GetLineupError(dx, dy, dz)
	local distance = math.sqrt(dx^2 + dz^2)	
	local fractionZ = dz / (-dx)
	local asinValueZ = math.asin(fractionZ)
	local angleZ = math.deg(asinValueZ)

	local lineupError = angleZ - 9.12
	return lineupError
end

function GetGlideslopeError(dx, dy, dz)
	return GetGlideslope(dx, dy, dz) - 3.5
end

function GetGlideslope(dx, dy, dz)
	local distance = math.sqrt(dx^2 + dz^2)	
	local fractionY = dy / distance
	local atanValueY = math.atan(fractionY)
	local angleY = math.deg(atanValueY)
	
	return angleY	
end

function AdjustDeltasToMatchFocalPoint(dx, dy, dz)
	--Modifying the deltas so that they match the focal point.
	dx = dx - focalPointX
	dy = dy - focalPointY
	dz = dz - focalPointZ
	
	return dx, dy, dz
end

function HandleLSO(playerData)
	local currentTime = timer.getAbsTime()

	local position = playerData.unit:GetVec3()
	local dx, dy, dz = GetRelativePositionToCarrier(position)
	dx, dy, dz = AdjustDeltasToMatchFocalPoint(dx, dy, dz)
	
	local lineupError = GetLineupError(dx, dy, dz)
	local glideslopeError = GetGlideslopeError(dx, dy, dz)

	local messageId = ""
	
	local hasAdvice = false
	
	--env.info("Glideslope error: " .. glideslopeError)
	--env.info("lineup error error: " .. lineupError)	
	--SendMessageToPlayer( "Glideslope error: " .. glideslopeError, 1, playerData )
	--SendMessageToPlayer( "Lineup error: " .. lineupError, 1, playerData )
	
	if(glideslopeError > 0.6) then
		if(glideslopeError > playerData.lso_lastGlideslopeError) then
			if(glideslopeError > 1.2) then
				messageId = "FlyDown_Intensity_2"
			else
				messageId = "FlyDown_Intensity_1"
			end
		end
	end
	
	if(glideslopeError < -0.3) then
		if(glideslopeError < playerData.lso_lastGlideslopeError) then
			if(glideslopeError < -1) then
				messageId = "FlyUp_Intensity_2"
			else
				messageId = "FlyUp_Intensity_1"
			end
		end
	end
	
	if(lineupError > 3) then
		if(lineupError > playerData.lso_lastLineupError) then
			if(lineupError > 5) then
				messageId = "FlyLeft_Intensity_2"
			else
				messageId = "FlyLeft_Intensity_1"
			end
		end
	end
	
	if(lineupError < -3) then
		if(lineupError < playerData.lso_lastLineupError) then
			if(lineupError < -5) then
				messageId = "FlyRight_Intensity_2"
			else
				messageId = "FlyRight_Intensity_1"
			end
		end
	end
	
	if(currentTime - playerData.lso_lastAdviceTime > 4) then
		if(messageId ~= "") then
			GiveLSOFeedback(messageId, playerData)
			playerData.lso_lastAdviceTime = currentTime
		end
	end

	playerData.lso_lastGlideslopeError = glideslopeError
	playerData.lso_lastLineupError = lineupError
end

function GiveLSOFeedback(messageId, playerData)
	--DisplayLSOFeedback(messageId, playerData)
	
	if(useLsoVoiceOver) then
		PlayLSOSound(messageId, playerData)
	end
end

function DisplayLSOFeedback(messageId, playerData)
	if(not lsoActive) then
		return
	end
	
	local message = ""
	
	if (messageId == "PaddlesContact") then message = "Paddles contact!"
	elseif (messageId == "FlyDown_Intensity_1") then message = "You're high..."
	elseif (messageId == "FlyDown_Intensity_2") then message = "You're high!"
	elseif (messageId == "FlyUp_Intensity_1") then message = "Power..."
	elseif (messageId == "FlyUp_Intensity_2") then message = "Power!"
	elseif (messageId == "FlyLeft_Intensity_1") then message = "Come left..."
	elseif (messageId == "FlyLeft_Intensity_2") then message = "Come left!"
	elseif (messageId == "FlyRight_Intensity_1") then message = "Right for lineup..."
	elseif (messageId == "FlyRight_Intensity_2") then message = "Right for lineup!"
	end
	
	SendMessageToPlayer( message, 2, playerData )
end

function PlayLSOSound(messageId, playerData)

	if(not lsoActive) then
		return
	end

	local sfxPack = nil

	if (messageId == "PaddlesContact") then sfxPack = sfx_paddlesContact
	elseif (messageId == "FlyDown_Intensity_1") then sfxPack = sfx_FlyDown_Intensity_1
	elseif (messageId == "FlyDown_Intensity_2") then sfxPack = sfx_FlyDown_Intensity_1
	elseif (messageId == "FlyUp_Intensity_1") then sfxPack = sfx_FlyUp_Intensity_1
	elseif (messageId == "FlyUp_Intensity_2") then sfxPack = sfx_FlyUp_Intensity_1
	elseif (messageId == "FlyLeft_Intensity_1") then sfxPack = sfx_FlyLeft_Intensity_1
	elseif (messageId == "FlyLeft_Intensity_2") then sfxPack = sfx_FlyLeft_Intensity_1
	elseif (messageId == "FlyRight_Intensity_1") then sfxPack = sfx_FlyRight_Intensity_1
	elseif (messageId == "FlyRight_Intensity_2") then sfxPack = sfx_FlyRight_Intensity_1
	end
	
	if(sfxPack == nil) then
		env.info("No SFX group for messageId " .. messageId)
	else
		sfxPack:Play()
	end
end

function PrintAltitudeFeedback(altitude, idealAltitude, playerData, altitudeSpan)
	local spanString = ""
	if(altitudeSpan ~= nil and altitudeSpan > 0) then
		spanString = "-" .. (idealAltitude + altitudeSpan)
	end
	SendInFlightFeedbackToPlayer( "Alt: " .. altitude .. " (Target: " .. idealAltitude .. spanString .. ")", 8, playerData )
end

function PrintGlideslopeFeedback(angle, idealAngle, playerData)
	angle = UTILS.Round(angle,2)
	local message = "Glideslope angle: " .. angle .. " degrees (Target: " .. idealAngle .. ")"
	SendInFlightFeedbackToPlayer(message, 8, playerData)
	--MessageToAllIncludingSpectators(message, 8)
end

function GetOnSpeedScore(AoA, playerData)
	local idealAoA = playerData.onSpeedAlpha
	local score = 0

	if(AoA > idealAoA + 1.2) then --Slow
		score = 0
	elseif(AoA > idealAoA + 0.8) then --Slightly slow
		score = 1
	elseif(AoA > idealAoA - 0.8) then --On speed
		score = 3
	elseif(AoA > idealAoA - 1.3) then --Slightly fast
		score = 1
	else --Fast
		score = 0
	end
	
	return score
end

function PrintAoAFeedback(AoA, playerData)
	local idealAoA = playerData.onSpeedAlpha
	local hint = ""

	if(AoA > idealAoA + 1.2) then
		hint = "Slow"
	elseif(AoA > idealAoA + 0.8) then
		hint = "Slightly slow"
	elseif(AoA > idealAoA - 0.8) then
		hint = "On speed"
	elseif(AoA > idealAoA - 1.3) then
		hint = "Slightly fast"
	else
		hint = "Fast"
	end

	--Convert degrees to Tomcat units
	if(playerData.isTomcat) then
		AoA = 1.0989 * (AoA + 3.01)
		idealAoA = 15
	end
	
	--Convert degrees to Goshawk units
	if(playerData.isGoshawk) then
		AoA = AoA + 10
		idealAoA = 17
	end
	
	local roundedAoA = UTILS.Round(AoA,2)
	
	SendInFlightFeedbackToPlayer( hint .. " AOA: " .. roundedAoA .. " (Target: " .. idealAoA .. ")", 8, playerData )
	
	return hint
end

function GetDeclutteredAoAFeedback(AoA, playerData)
	local idealAoA = playerData.onSpeedAlpha
	local hint = ""

	if(AoA > idealAoA + 1.2) then
		hint = "Slow"
	elseif(AoA > idealAoA + 0.8) then
		hint = "Slightly slow"
	elseif(AoA > idealAoA - 0.8) then
		hint = "On speed"
	elseif(AoA > idealAoA - 1.3) then
		hint = "Slightly fast"
	else
		hint = "Fast"
	end
	
	return " (" .. hint .. ")"
end

function GetStepScoreString(score, maxStepScore)
	return " - " .. score .. "/" .. maxStepScore
end

function PrintScore(score, playerData, alsoPrintTotalScore)
	if(alsoPrintTotalScore) then
		SendMessageToPlayer( "Score: " .. score .. " (Total: " .. playerData.score .. ")", 8, playerData )
	else
		SendMessageToPlayer( "Score: " .. score, 8, playerData )
	end
end

function PrintFinalScore(playerData, duration, wire)

	if(patternMode) then
		if(wire > 0) then
			SendMessageToPlayer("Take off and fly straight along the BRC at least 0.5 nm to restart the exercise.", 8, playerData)
		else
			SendMessageToPlayer("Fly straight along the BRC at least 0.5 nm to restart the exercise.", 8, playerData)
		end
	else
		SendMessageToPlayer( "Return 4 nm aft (over the trailing ship) to restart the exercise.", 20, playerData )
	end

	local wireText = ""
	if(wire == -2) then
		wireText = "Aborted approach"
	elseif(wire == -1) then
		wireText = "Wave-off"
	elseif(wire == 0) then
		wireText = "Bolter"
	else
		wireText = wire .. "-wire"
	end
	
	local shortHandScoreSummary = playerData.playerName .. " (" .. playerData.modex .. ", " .. playerData.fixedCallsign .. ") - Final score: " .. playerData.score .. " / " .. maxScore .. " (" .. wireText .. ")"
	
	if(playerData.longDownwind) then
		shortHandScoreSummary = shortHandScoreSummary .. " (Long DW)"
	end
	
	if(playerData.didSettle) then
		shortHandScoreSummary = shortHandScoreSummary .. " (Settled)"
	end
	
	MessageToAllIncludingSpectators(shortHandScoreSummary, duration)
	env.info(shortHandScoreSummary)
	
	SendMessageToPlayer(playerData.summary, duration, playerData)
	
	local logMessage = "\n" .. shortHandScoreSummary .. " - " .. playerData.typeName .. "\n" .. playerData.summary:gsub("•", "*")
	env.info(logMessage)
	WriteSummaryToFile(logMessage)
end

function WriteSummaryToFile(logMessage)
	if os and io and lfs then
		local fdir = lfs.writedir() .. [[Logs\BanklersCase1RecoveryTrainer.log]]
		local f = io.open(fdir, 'a')

		local dateString = "\n" .. os.date("%c")

		f:write(dateString .. logMessage)
		f:close()
	else
		env.info('insufficient libraries to run WriteSummaryToFile, you must disable the sanitization of the os, io and lfs libraries in ./Scripts/MissionScripting.lua')
	end
end

function HandleCollectedResult(playerData, wire)
	local newString = ""
	local modeString = ""
	
	if(patternMode) then
		modeString = "P "
	end
	
	if(wire == -2) then
		newString = modeString .. playerData.score .. " (Aborted)"
	elseif(wire == -1) then
		newString = modeString .. playerData.score .. " (Wave-off)"
	elseif(wire == 0) then
		newString = modeString .. playerData.score .. " (Bolter)"
	else
		newString = modeString .. playerData.score .. " (" .. wire .."W)"
	end
	
	if(playerData.longDownwind) then
		newString = newString .. " (Long DW)"
	end
	
	if(playerData.didSettle) then
		newString = newString .. " (Settled)"
	end
	
	playerData.totalScore = playerData.totalScore + playerData.score
	playerData.passes = playerData.passes + 1
	
	if(playerData.collectedResultString == "") then
		playerData.collectedResultString = newString
	else
		playerData.collectedResultString = playerData.collectedResultString .. ", " .. newString
		MessageToAllIncludingSpectators( playerData.playerName .. " (" .. playerData.modex .. ", " .. playerData.fixedCallsign .. ")'s " .. playerData.passes .. " passes: " .. playerData.collectedResultString .. " (TOTAL: " .. playerData.totalScore .. ")"  , 30 )
	end
end

function AbortPattern(playerData, reason)
	hint = ""
	if(reason ~= nil) then
		hint = reason .. ". Abort approach!"
	else
		hint = "You're too far from where you should be. Abort approach!"
	end
	
	SendMessageToPlayer(hint , 15, playerData )
	playerData:AddToSummary("Approach aborted.")
	PrintFinalScore(playerData, 30, -2)
	HandleCollectedResult(playerData, -2)
	playerData.step = 0
end

function GetFormattedScore(score, maxScore)
	if(score < maxScore) then
		return " (" .. score .. " points)."
	else
		return " (" .. score .. " points)!"
	end
end

function GetDistanceFeedback(distance, idealDistance)
	return distance .. " nm (Target: " .. idealDistance .. " nm)"
end

function GetUnitVerticalVelocity(unit)
    local velocityVec3 = unit:GetVelocityVec3()
    local verticalVelocity = velocityVec3.y * 3.28084 * 60
    return verticalVelocity
end


--STARTING PROCEDURE:

CreateRadioMenu()
ToggleInFlightFeedback(true, true)
TogglePublicFeedback(false, true)
ToggleLSO(true, true)
SetMode("break", true)
SetCase(1)