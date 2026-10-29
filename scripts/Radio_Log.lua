-- Radio_Log | v1.0.0
--[[
  Mirrors every on-screen message (radio subtitles, hints, score lines) into dcs.log, so a flight
  can be reviewed afterwards without screenshots (Onur, 2026-10-30).

  How: wraps trigger.action.outText / outTextForCoalition / outTextForCountry / outTextForGroup /
  outTextForUnit once. Each call is logged, then passed on unchanged. MOOSE MESSAGE and every
  template script go through these functions at call time, so they are all covered from the
  moment this script runs. A script that stored its own local copy of one of these functions
  BEFORE this script loaded bypasses the log (none in the repo does this, checked 2026-10-30).

  Log line:  [RADIO] 22:32:09 G1 [POINTER 11] HORNET 51, ... | second line ...
             mission clock (HH:MM:SS, timer.getAbsTime), target (ALL / C<side> / N<country> /
             G<group id> / U<unit id>), the text with line breaks as " | ".
  Identical text to the same target within DUP_S seconds is logged once (repeat warnings).
]]

_G.TRT = _G.TRT or {}
if _G.TRT.RADIO_LOG then return end          -- loaded twice: keep the first wrapper

local DUP_S = 2
local last = {}

local function Clock()
    local t = math.floor(timer.getAbsTime()) % 86400
    return string.format("%02d:%02d:%02d", math.floor(t / 3600), math.floor((t % 3600) / 60), t % 60)
end

local function Log(target, text)
    if type(text) ~= "string" or text == "" then return end
    local key = target .. "\0" .. text
    local now = timer.getTime()
    if last[key] and now - last[key] < DUP_S then return end
    last[key] = now
    local one = text:gsub("\r", ""):gsub("\n+", " | ")
    env.info(string.format("[RADIO] %s %s %s", Clock(), target, one))
end

local A = trigger.action
local orig = {
    outText             = A.outText,
    outTextForCoalition = A.outTextForCoalition,
    outTextForCountry   = A.outTextForCountry,
    outTextForGroup     = A.outTextForGroup,
    outTextForUnit      = A.outTextForUnit,
}

local function safe(target, text) pcall(Log, target, text) end

if orig.outText then
    A.outText = function(text, ...) safe("ALL", text); return orig.outText(text, ...) end
end
if orig.outTextForCoalition then
    A.outTextForCoalition = function(side, text, ...) safe("C" .. tostring(side), text)
        return orig.outTextForCoalition(side, text, ...) end
end
if orig.outTextForCountry then
    A.outTextForCountry = function(c, text, ...) safe("N" .. tostring(c), text)
        return orig.outTextForCountry(c, text, ...) end
end
if orig.outTextForGroup then
    A.outTextForGroup = function(gid, text, ...) safe("G" .. tostring(gid), text)
        return orig.outTextForGroup(gid, text, ...) end
end
if orig.outTextForUnit then
    A.outTextForUnit = function(uid, text, ...) safe("U" .. tostring(uid), text)
        return orig.outTextForUnit(uid, text, ...) end
end

_G.TRT.RADIO_LOG = { version = "1.0.0", orig = orig }
env.info("[RADIO] Radio_Log v1.0.0 online - on-screen messages are mirrored to dcs.log")
