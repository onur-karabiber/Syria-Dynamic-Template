-- TRT_SortieReport | v1.0.0
--[[
  v1.0.0 (2026-11-07, Onur): every sortie is saved as an HTML report in
      Saved Games\DCS\Missions\Sortie Reports\<MISSION>_<YYYY-MM-DD>_<HHMM>.html
  (mission name + local date / time the mission started), plus the sortie's script lines in
      Sortie Reports\logs\<same name>.log                       (CFG.SAVE_LOG; dcs.log is overwritten at each DCS start)

  DCS hook (GUI environment, io / lfs / os available). Install as
      Saved Games\DCS\Scripts\Hooks\TRT_SortieReport.lua        (source: repo hooks/; read at DCS start)

  How: onSimulationStart notes the time and the mission name; onSimulationStop starts, detached,
      <python> tools/flight_report.py <dcs.log> --since <start, UTC> --name <stem> --outdir <Sortie Reports> --wait 5
  (flight_report.py >= v1.2.0). The tool waits 5 s for DCS to finish the log, takes the last sortie that started after
  the mission start and has scored lines; none (an untouched or non-template mission) -> it writes nothing.
  The HTML is the same report as "python tools/flight_report.py" (score groups, badges, ledger, fuel, timing, AAR,
  JTAC, radio). A sortie that ends without the [FR] JSON line (left airborne) is rebuilt from the score lines.

  Python: the first that exists of CFG.PYTHONS (pythonw / pyw: no console window); none -> logged, nothing started.
  dcs.log: "TRT_SortieReport | ..." lines.
]]

local VERSION = "1.0.0"

local function Log(s) if log and log.write then log.write("TRT_SortieReport", log.INFO, s) end end

local WD = (lfs and lfs.writedir and lfs.writedir()) or ""            -- ...\Saved Games\DCS\ (trailing backslash)
local HOME = os.getenv("USERPROFILE") or ""
local LAD = os.getenv("LOCALAPPDATA") or (HOME .. "\\AppData\\Local")
local WIN = os.getenv("SystemRoot") or "C:\\Windows"

local CFG = {
    REPO     = HOME .. "\\Documents\\GitHub\\Syria-Dynamic-Template",
    OUT      = WD .. "Missions\\Sortie Reports",
    LOG      = WD .. "Logs\\dcs.log",
    SAVE_LOG = true,
    WAIT_S   = 5,
    PYTHONS  = {                                                     -- first existing one is used
        WIN .. "\\pyw.exe",                                          -- python.org launcher
        { dir = LAD .. "\\Programs\\Python", exe = "pythonw.exe" },  -- per-user installs (Python3xx)
        { dir = "C:\\Program Files", match = "^Python", exe = "pythonw.exe" },
        "C:\\Dev\\dcs-f10-wheel\\.venv\\Scripts\\pythonw.exe",       -- the F10 Wheel venv (stdlib is enough)
    },
}

local function isFile(p) return lfs and lfs.attributes(p, "mode") == "file" end

local function findPython()
    for _, c in ipairs(CFG.PYTHONS) do
        if type(c) == "string" then
            if isFile(c) then return c end
        elseif lfs and lfs.attributes(c.dir, "mode") == "directory" then
            local best
            for name in lfs.dir(c.dir) do
                if name ~= "." and name ~= ".." and (not c.match or name:match(c.match)) then
                    local p = c.dir .. "\\" .. name .. "\\" .. c.exe
                    if isFile(p) and (not best or name > best.name) then best = { name = name, p = p } end
                end
            end
            if best then return best.p end
        end
    end
    return nil
end

local function stemOf(name)
    local s = tostring(name or "mission"):gsub("%.miz$", ""):gsub('[<>:"/\\|?*%c]', "_")
    s = s:gsub("^%s+", ""):gsub("[%s%.]+$", "")
    if s == "" then s = "mission" end
    return s
end

local function missionName()
    local fn = DCS and DCS.getMissionFilename and DCS.getMissionFilename() or nil
    local base = fn and fn:match("([^\\/]+)%.miz$")
    if base and not base:lower():match("^tempmission") then return base end
    local n = DCS and DCS.getMissionName and DCS.getMissionName() or nil
    if n and n ~= "" then return n end
    return base or "mission"
end

local S = { t0 = nil, name = nil }
local H = {}

function H.onSimulationStart()
    S.t0, S.name = os.time(), missionName()
    Log(string.format("mission start: '%s' at %s", S.name, os.date("%Y-%m-%d %H:%M", S.t0)))
end

function H.onSimulationStop()
    if not S.t0 then return end
    local t0, name = S.t0, S.name
    S.t0 = nil
    local py = findPython()
    local tool = CFG.REPO .. "\\tools\\flight_report.py"
    if not py then Log("no pythonw / pyw found - no report (CFG.PYTHONS)"); return end
    if not isFile(tool) then Log("tool not found: " .. tool); return end
    if not (os and os.execute) then Log("os.execute not available - no report"); return end
    local stem = stemOf(name) .. "_" .. os.date("%Y-%m-%d_%H%M", t0)
    local since = os.date("!%Y-%m-%d %H:%M:%S", t0 - 5)              -- dcs.log time stamps are UTC
    local cmd = string.format('start "" "%s" "%s" "%s" --since "%s" --name "%s" --outdir "%s" --wait %d%s',
        py, tool, CFG.LOG, since, stem, CFG.OUT, CFG.WAIT_S, CFG.SAVE_LOG and " --save-log" or "")
    local ok, err = pcall(os.execute, cmd)
    Log(ok and ("report requested: " .. CFG.OUT .. "\\" .. stem .. ".html (" .. py .. ")")
        or ("os.execute failed: " .. tostring(err)))
end

DCS.setUserCallbacks(H)
Log("v" .. VERSION .. " loaded; out " .. CFG.OUT .. "; python " .. tostring(findPython()))
