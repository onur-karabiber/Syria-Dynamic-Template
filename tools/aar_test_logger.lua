-- AAR_Test_Logger | v1.0.0
-- Injected by tools/make_test_variant.py (--start AAR / AAR-S) as a "triggerOnce" DO SCRIPT.
-- NOT part of the template build. Logs, for the AAR test flight (project doc
-- claude/aar-test-flight-2026-10-30.md), the hero's position relative to the tanker in the
-- tanker's body axes, closure, radar state (Unit.getRadar), probe draw argument 22 and fuel.
-- Every 10 s inside 20 NM, every 2 s inside 2 NM. Refuelling events with fuel.
-- The SILENCE value below is filled in by make_test_variant.py: true (AAR-S) sets AI.Option.Air.id.SILENCE on the tanker group.
do
    local HERO, TKR_UNIT, TKR_GROUP = 'Player_01', 'TANKER-1-1', 'TANKER-1'
    local SILENCE = __SILENCE__
    local NM, FT, KT, LB = 1852, 3.28084, 1.94384, 2.20462
    local PROBE_ARG = 22

    local function log(s) env.info('[AAR-TEST] ' .. s) end

    local function fuelLb(u)
        local ok, f = pcall(function() return u:getFuel() * u:getDesc().fuelMassMax * LB end)
        return ok and f or -1
    end

    if SILENCE then
        local g = Group.getByName(TKR_GROUP)
        if g then
            local ok, err = pcall(function() g:getController():setOption(AI.Option.Air.id.SILENCE, true) end)
            log('TANKER-1 SILENCE set: ' .. tostring(ok) .. (err and (' ' .. tostring(err)) or ''))
        else
            log('TANKER-1 group not found, SILENCE not set')
        end
    end
    log('v1.0.0 loaded, SILENCE=' .. tostring(SILENCE))

    local function tick(_, t)
        local h, k = Unit.getByName(HERO), Unit.getByName(TKR_UNIT)
        if not (h and h:isExist() and k and k:isExist()) then return t + 10 end
        local hp, kp = h:getPoint(), k:getPoint()
        local rx, ry, rz = hp.x - kp.x, hp.y - kp.y, hp.z - kp.z
        local d = math.sqrt(rx * rx + rz * rz)
        if d > 20 * NM then return t + 10 end
        local P = k:getPosition()                         -- x fwd, y up, z right (unit vectors)
        local fwd   = rx * P.x.x + ry * P.x.y + rz * P.x.z
        local up    = rx * P.y.x + ry * P.y.y + rz * P.y.z
        local right = rx * P.z.x + ry * P.z.y + rz * P.z.z
        local vh, vk = h:getVelocity(), k:getVelocity()
        local r3 = math.sqrt(rx * rx + ry * ry + rz * rz)
        local clos = 0
        if r3 > 1 then
            clos = -((vh.x - vk.x) * rx + (vh.y - vk.y) * ry + (vh.z - vk.z) * rz) / r3 * KT
        end
        local okR, rOn, rTgt = pcall(function() return h:getRadar() end)
        local radar = okR and tostring(rOn) or 'n/a'
        local tgt = (okR and rTgt and rTgt.getName and rTgt:getName()) or '-'
        local okP, probe = pcall(function() return h:getDrawArgumentValue(PROBE_ARG) end)
        local tas = math.sqrt(vk.x * vk.x + vk.z * vk.z) * KT
        local hdg = (math.deg(math.atan2(P.x.z, P.x.x)) + 360) % 360
        log(string.format('d=%.2fNM fwd=%.0fft right=%.0fft up=%.0fft clos=%.1fkt radar=%s tgt=%s probe=%s fuel=%.0f | tkr tas=%.0f alt=%.0f hdg=%03.0f',
            d / NM, fwd * FT, right * FT, up * FT, clos, radar, tgt, okP and string.format('%.2f', probe) or 'n/a',
            fuelLb(h), tas, kp.y * FT, hdg))
        return t + ((d < 2 * NM) and 2 or 10)
    end
    timer.scheduleFunction(tick, nil, timer.getTime() + 5)

    local H = {}
    function H:onEvent(e)
        if not (e and e.initiator and e.initiator.getName) then return end
        local ok, nm = pcall(function() return e.initiator:getName() end)
        if not ok or nm ~= HERO then return end
        if e.id == world.event.S_EVENT_REFUELING then
            log(string.format('REFUELING start fuel=%.0f', fuelLb(e.initiator)))
        elseif e.id == world.event.S_EVENT_REFUELING_STOP then
            log(string.format('REFUELING stop fuel=%.0f', fuelLb(e.initiator)))
        end
    end
    world.addEventHandler(H)
end
