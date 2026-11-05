-- Carrier_Geometry | v1.1.0
-- Distance_Flag_v3 + Radial_Flag_v1 birlesimi. Ayni Unit lookup, ayni tick,
-- iki flag. Flag ID'leri (6550, 6551) eskisiyle ayni - mevcut ME trigger'lar
-- bozulmaz. Bu dosya yuklendiginde eski iki dosyayi loadfile zincirinden
-- CIKAR, aksi halde iki ayri script ayni flag'lere yazmaya calisir.

-- DEBUG: script loading check (one-time)
trigger.action.outText("Carrier geometry measuring activated", 5)

do
  local playerName = "Player_01"
  local cvnName    = "CVN"

  local distFlagId = 6550   -- DME (NM)
  local radFlagId  = 6551   -- Radyal (derece, CVN -> Player)

  local updateInterval = 1.0 -- saniye

  -- --- DISTANCE ayarlari (Distance_Flag_v3 ile ayni) ---
  local distHysteresis      = 0.25 -- NM, sinirdaki titresimi keser
  local distResyncThreshold = 2    -- NM, bu kadar sapinca adim adim degil dogrudan hizala

  -- --- RADIAL ayarlari (Radial_Flag_v1 ile ayni) ---
  local sectorSize         = 1   -- derece cozunurluk, 360'i TAM bolmeli
  local radHysteresis      = 0.3 -- derece
  local radResyncThreshold = 5   -- derece

  -- Grid (Vec3 x/z, F10 harita) -> Magnetic donusum offseti.
  -- Syria haritasi icin ED'nin resmi/dokumante edilmis bir degeri yok.
  -- -5, kokpit TCN (WSH ident, CVN'e kilitli) ile flag arasinda iki farkli
  -- konumda olculdu, ikisinde de sapma tutarli cikti. DCS versiyonuna
  -- bagli olabilir, majör patch sonrasi tekrar dogrula.
  local magVarDeg = -5

  -- Debug switch flag'leri - AYRI:
  -- DEBUG_FLAG: sadece flag degisiminde ("R-191, DME 27") ozet basar. Hafif,
  --   normal operasyon sirasinda acik birakilabilir.
  -- RAW_DEBUG_FLAG: her debugInterval saniyede bir surekli ham veri basar.
  --   Sadece aktif teshis/desync arama sirasinda ac, surekli acik birakma -
  --   ekran spam eder.
  -- 0 = sus, 1 = konus
  local DEBUG_FLAG     = 9001
  local RAW_DEBUG_FLAG = 9004

  local debugInterval = 2.0 -- saniye, surekli ham veri yazdirma araligi
  local lastDebugTime = 0

  local totalSectors
  if 360 % sectorSize == 0 then
    totalSectors = 360 / sectorSize
  end

  if not totalSectors then
    trigger.action.outText("Carrier_Geometry: sectorSize 360'i tam bolmuyor, script devre disi.", 15)
  else

    local lastDist     = nil -- NM (tam sayi bucket)
    local lastRadIndex = nil -- sektor indeksi, 0..totalSectors-1

    local function debug(msg)
      if trigger.misc.getUserFlag(DEBUG_FLAG) == 1 then
        trigger.action.outText(msg, 3)
      end
    end

    local function metersToNM(m)
      return m / 1852
    end

    local function distanceNM(u1, u2)
      local p1 = u1:getPoint()
      local p2 = u2:getPoint()
      local dx = p1.x - p2.x
      local dz = p1.z - p2.z
      return metersToNM(math.sqrt(dx*dx + dz*dz))
    end

    -- En kisa isaretli acisal fark: a-b, araligi (-180, 180]. Wrap-safe.
    local function angleDiff(a, b)
      local d = (a - b) % 360
      if d > 180 then d = d - 360 end
      return d
    end

    -- CVN -> toUnit radyali, derece, 0-360. TACAN "from station" konvansiyonu:
    -- 0=kuzey, 90=dogu, 180=guney, 270=bati.
    local function radialDeg(fromUnit, toUnit)
      local p1 = fromUnit:getPoint()
      local p2 = toUnit:getPoint()
      local dx = p2.x - p1.x -- kuzey bileseni
      local dz = p2.z - p1.z -- dogu bileseni
      local deg = math.deg(math.atan2(dz, dx)) + magVarDeg
      deg = deg % 360
      return deg
    end

    local function tick()
      local player = Unit.getByName(playerName)
      local cvn    = Unit.getByName(cvnName)

      if not player or not cvn or not player:isExist() or not cvn:isExist() then
        return timer.getTime() + updateInterval
      end

      local dNM     = distanceNM(player, cvn)
      local bearing = radialDeg(cvn, player)

      -- Surekli (throttled) ham veri yazdirma - transition beklemez.
      -- Sadece RAW_DEBUG_FLAG acikken, DEBUG_FLAG'den bagimsiz.
      if trigger.misc.getUserFlag(RAW_DEBUG_FLAG) == 1 and (timer.getTime() - lastDebugTime) >= debugInterval then
        lastDebugTime = timer.getTime()
        trigger.action.outText(string.format(
          "RAW dNM=%.2f radial=%.2f  | flag DME=%s R=%s",
          dNM, bearing,
          tostring(lastDist),
          tostring(lastRadIndex and (lastRadIndex * sectorSize) or "nil")
        ), 2)
      end

      local changed = false

      -- ===== DISTANCE =====
      if lastDist == nil then
        lastDist = math.floor(dNM)
        changed = true
      elseif math.abs(dNM - lastDist) > (1 + distHysteresis + distResyncThreshold) then
        -- Buyuk desync korumasi: adim adim degil dogrudan hizala.
        lastDist = math.floor(dNM)
        changed = true
      else
        local upThreshold   = (lastDist + 1) + distHysteresis
        local downThreshold = lastDist - distHysteresis
        if dNM >= upThreshold then
          lastDist = lastDist + 1
          changed = true
        elseif dNM < downThreshold then
          lastDist = math.max(0, lastDist - 1)
          changed = true
        end
      end

      -- ===== RADIAL =====
      if lastRadIndex == nil then
        lastRadIndex = math.floor(bearing / sectorSize) % totalSectors
        changed = true
      else
        local currentLowerEdge = lastRadIndex * sectorSize
        local diffToCurrent = angleDiff(bearing, currentLowerEdge)

        if math.abs(diffToCurrent) > (sectorSize + radHysteresis + radResyncThreshold) then
          -- Buyuk desync korumasi: adim adim degil dogrudan hizala.
          lastRadIndex = math.floor(bearing / sectorSize) % totalSectors
          changed = true
        else
          local relBearing = (bearing - currentLowerEdge) % 360
          if relBearing >= (sectorSize + radHysteresis) then
            lastRadIndex = (lastRadIndex + 1) % totalSectors
            changed = true
          elseif relBearing >= (360 - radHysteresis) then
            lastRadIndex = (lastRadIndex - 1 + totalSectors) % totalSectors
            changed = true
          end
        end
      end

      if changed then
        local lastRad = lastRadIndex * sectorSize
        trigger.action.setUserFlag(distFlagId, lastDist)
        trigger.action.setUserFlag(radFlagId, lastRad)
        debug(string.format("R-%03d, DME %d", lastRad, lastDist))
      end

      return timer.getTime() + updateInterval
    end

    timer.scheduleFunction(function()
      return tick()
    end, {}, timer.getTime() + 1)

  end
end
