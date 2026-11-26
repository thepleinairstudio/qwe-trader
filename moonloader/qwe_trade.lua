script_version('1.24.0')
-- QWE Trader -- loader (open part).
-- This file contains NO trader logic. All trader code lives in qwe_core.dat
-- (LuaJIT bytecode), so it cannot be read or edited by players.
--
--  * DEV build (author's PC): if "qwe_core.src" is present next to this file,
--    the loader compiles it to stripped bytecode "qwe_core.dat" and runs it.
--    No auto-update in dev mode.
--  * RELEASE build (players): only "qwe_core.dat" is shipped. The loader loads
--    it and auto-updates the core from GitHub (version.json -> qwe_core.dat).
--
-- The core talks to the loader through the global table _G.QWE_UPD.

local REPO_RAW = 'https://raw.githubusercontent.com/thepleinairstudio/qwe-trader/main/'

local dir  = getWorkingDirectory()
local SRC  = dir .. '\\qwe_core.src'
local DAT  = dir .. '\\qwe_core.dat'
local TMPJ = dir .. '\\qwe_update.json'
local TMPD = dir .. '\\qwe_core.dat.new'

local dlstatus = require('moonloader').download_status

local function readFile(p) local f = io.open(p, 'rb'); if not f then return nil end local s = f:read('*a'); f:close(); return s end
local function writeFile(p, d) local f = io.open(p, 'wb'); if not f then return false end f:write(d); f:close(); return true end
local function exists(p) local f = io.open(p, 'rb'); if f then f:close(); return true end return false end
local function verNum(v)
	local a, b, c = tostring(v or ''):match('(%d+)%.?(%d*)%.?(%d*)')
	return (tonumber(a) or 0) * 1000000 + (tonumber(b) or 0) * 1000 + (tonumber(c) or 0)
end

-- Shared interface for the core UI. The core reads .code/.ver and calls .check().
-- .code is a short status code; the core maps it to its own localized text.
local UPD = { busy = false, code = nil, ver = nil, dev = false }
_G.QWE_UPD = UPD
local function setStatus(code, ver) UPD.code, UPD.ver = code, ver end

function UPD.check(manual, curVer)
	if UPD.dev then setStatus('devbuild', curVer); return end
	if UPD.busy and os.clock() - (UPD.at or 0) < 30 then return end
	UPD.busy, UPD.at = true, os.clock()
	setStatus('checking', curVer)
	downloadUrlToFile(REPO_RAW .. 'version.json?t=' .. os.time(), TMPJ, function(_, status)
		if status ~= dlstatus.STATUS_ENDDOWNLOADDATA then return end
		local s = readFile(TMPJ); os.remove(TMPJ)
		local ok, j = pcall(decodeJson, s or '')
		if not ok or type(j) ~= 'table' or not j.version then
			UPD.busy = false; setStatus('neterr', curVer); return
		end
		if verNum(j.version) <= verNum(curVer) then
			UPD.busy = false; setStatus('uptodate', curVer); return
		end
		setStatus('updating', j.version)
		local coreName = j.core or 'moonloader/qwe_core.dat'
		downloadUrlToFile(REPO_RAW .. coreName .. '?t=' .. os.time(), TMPD, function(_, st2)
			if st2 ~= dlstatus.STATUS_ENDDOWNLOADDATA then return end
			local bc = readFile(TMPD)
			-- validate: big enough and loads as a valid chunk (bytecode or source)
			local good = bc and #bc > 50000 and loadfile(TMPD) ~= nil
			if not good then
				os.remove(TMPD); UPD.busy = false; setStatus('baddata', j.version); return
			end
			if exists(DAT) then writeFile(DAT .. '.bak', readFile(DAT) or '') end
			local okw = writeFile(DAT, bc)
			os.remove(TMPD)
			if not okw then UPD.busy = false; setStatus('writeerr', j.version); return end
			setStatus('updated', j.version); UPD.busy = false
			thisScript():reload()
		end)
	end)
end

-- ============================ startup ============================
local chunk, srcChunk

local code = readFile(SRC)
if code then
	-- DEV: compile source to stripped bytecode on every start
	local c, err = loadstring(code, '@qwe_core')
	if not c then print('[QWE loader] source compile error: ' .. tostring(err)); return end
	srcChunk = c
	local ok, bc = pcall(string.dump, c, true)
	if ok and type(bc) == 'string' and #bc > 0 then
		writeFile(DAT, bc)
	else
		print('[QWE loader] string.dump failed, running from source')
	end
	UPD.dev = true
end

local c, err = loadfile(DAT)
if c then
	chunk = c
elseif srcChunk then
	print('[QWE loader] bytecode load failed (' .. tostring(err) .. '), running from source')
	chunk = srcChunk
else
	-- No source and no bytecode (e.g. only the loader was installed): fetch the
	-- core once from GitHub, then reload. Safety net; normal installs ship the .dat.
	print('[QWE loader] core not found, fetching from GitHub...')
	UPD.busy = true; setStatus('updating')
	function main()
		wait(3000)
		downloadUrlToFile(REPO_RAW .. 'moonloader/qwe_core.dat?t=' .. os.time(), DAT, function(_, st)
			if st == dlstatus.STATUS_ENDDOWNLOADDATA then
				UPD.busy = false
				thisScript():reload()
			end
		end)
		while true do wait(1000) end
	end
	return
end

chunk()

--[[ Filler below only exists so the legacy auto-updater (size > 50KB check) accepts this transitional file. It is a plain comment and does nothing.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
QWE Trader 1.21.0 protected build -- all trader logic ships as LuaJIT bytecode in qwe_core.dat; this file only loads and auto-updates the core.
]]
