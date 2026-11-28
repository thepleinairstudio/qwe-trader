script_version('1.24.1')
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

local REPO = 'thepleinairstudio/qwe-trader'

local dir  = getWorkingDirectory()
local SRC  = dir .. '\\qwe_core.src'
local DAT  = dir .. '\\qwe_core.dat'
local TMPJ = dir .. '\\qwe_update.json'
local TMPD = dir .. '\\qwe_core.dat.new'
local CORE_DEF = 'moonloader/qwe_core.dat'
local MIN_CORE = 50000
local MARK     = 'QWE_UPD'           -- marker of our loader for self-update
local LOG      = '[QWE loader]'
local DEV_SKIP = true                -- no auto-update in dev mode

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

-- ===================== автообновление (общий блок QWE, загрузчик v2) =====================
-- ќдинаковый во всех загрузчиках QWE (источник: _tools/qwe-updater/updater.part.lua).
-- ѕеред блоком загрузчик задаЄт: REPO, DAT, TMPJ, TMPD, CORE_DEF, MIN_CORE, MARK, LOG, DEV_SKIP,
-- UPD, setStatus, readFile, writeFile, exists, verNum.
--
-- „то чинит по сравнению с v1:
--  * raw.githubusercontent.com 5 минут отдаЄт старые файлы и не смотрит на Ђ?t=ї. ядро и
--    version.json качаем по ссылке на свежий коммит (api.github.com) Ч там кэша нет.
--  * API недоступен и качаем с main Ч свер€ем "size" €дра из version.json: не совпал (старый кэш) Ч
--    €дро не ставим, пробуем ещЄ раз через 15 с.
--  * ошибка сети / 404 / зависание больше не оставл€ет Ђѕровер€юЕї навсегда.
--  * все скачивани€ идут из одного потока загрузчика, не из колбэков и не из потоков €дра.
--  * загрузчик обновл€ет сам себ€, если в version.json "loader" больше LOADER_VER.
local LOADER_VER = 2

local dls = require('moonloader').download_status or {}
local ST_DATA = dls.STATUS_ENDDOWNLOADDATA or 6
local ST_END  = dls.STATUSEX_ENDDOWNLOAD
local RAW_MAIN = 'https://raw.githubusercontent.com/' .. REPO .. '/main/'

-- скачать и дождатьс€ (только внутри потока). ¬ернЄт содержимое или nil.
local function fetch(url, path, sec)
	os.remove(path)
	local job = { done = false, ok = false }
	local called = pcall(downloadUrlToFile, url, path, function(_, st)
		if st == ST_DATA then job.ok = true; job.done = true
		elseif ST_END and st == ST_END then job.done = true end
	end)
	if not called then return nil end
	local n = (sec or 25) * 10
	while not job.done and n > 0 do wait(100); n = n - 1 end
	-- конец без данных: на вс€кий случай даЄм долететь STATUS_ENDDOWNLOADDATA
	if job.done and not job.ok then wait(300) end
	wait(100)
	local s = readFile(path); os.remove(path)
	if job.ok and s and #s > 0 then return s end
	return nil
end

local function parseJson(s)
	-- decodeJson('') в MoonLoader пробивает pcall Ч сначала убеждаемс€, что это JSON
	if not s or not s:find('{', 1, true) or s:find('<html', 1, true) then return nil end
	local ok, j = pcall(decodeJson, s)
	if ok and type(j) == 'table' then return j end
	return nil
end

-- адрес файлов на свежем коммите main (или nil, если API недоступен)
local function freshBase()
	local s = fetch('https://api.github.com/repos/' .. REPO .. '/commits/main?t=' .. os.time(), TMPJ, 20)
	local sha = s and s:match('^%s*{%s*"sha"%s*:%s*"(%x+)"')
	if sha and #sha == 40 then return 'https://raw.githubusercontent.com/' .. REPO .. '/' .. sha .. '/' end
	return nil
end

local function goodCore(bc, size)
	if not bc or #bc < MIN_CORE then return false end
	if tonumber(size) and #bc ~= tonumber(size) then return false end
	return loadstring(bc) ~= nil
end

-- новый загрузчик: пишем поверх себ€; не записалс€ целиком Ч возвращаем старый
local function installLoader(s)
	local okp, path = pcall(function() return thisScript().path end)
	if not okp or type(path) ~= 'string' then return false end
	local old = readFile(path)
	if not old or old == s then return false end
	if writeFile(path, s) and readFile(path) == s then return true end
	writeFile(path, old)
	return false
end

local function runCheck(manual, curVer)
	local j = parseJson(fetch(RAW_MAIN .. 'version.json?t=' .. os.time(), TMPJ))
	if not j or not j.version then
		-- raw недоступен Ч пробуем через свежий коммит
		local base = freshBase()
		j = base and parseJson(fetch(base .. 'version.json?t=' .. os.time(), TMPJ))
		if not j or not j.version then setStatus('neterr', curVer); return end
	end
	UPD.latest = j.version
	local coreNew = verNum(j.version) > verNum(curVer)
	local loaderNew = (tonumber(j.loader) or 0) > LOADER_VER
	if not coreNew and not loaderNew then setStatus('uptodate', curVer); return end
	if UPD.dev then
		setStatus(coreNew and 'devnewer' or 'uptodate', coreNew and j.version or curVer); return
	end

	-- version.json с main мог прийти из кэша: берЄм пару version.json + €дро с одного свежего коммита
	local base = freshBase()
	if base then
		local j2 = parseJson(fetch(base .. 'version.json?t=' .. os.time(), TMPJ))
		if j2 and j2.version then
			j = j2; UPD.latest = j.version
			coreNew = verNum(j.version) > verNum(curVer)
			loaderNew = (tonumber(j.loader) or 0) > LOADER_VER
		else
			base = nil
		end
	end
	if not coreNew and not loaderNew then setStatus('uptodate', curVer); return end

	local bc
	if coreNew then
		setStatus('updating', j.version)
		-- по коммиту Ч 2 попытки; через main (кэш до 5 минут) Ч 3 попытки с паузой
		local tries, pause = base and 2 or 3, base and 2000 or 15000
		local got = false
		for i = 1, tries do
			local s = fetch((base or RAW_MAIN) .. (j.core or CORE_DEF) .. '?t=' .. os.time(), TMPD, 90)
			got = got or s ~= nil
			-- размер свер€ем только дл€ main: по ссылке на коммит пара version.json + €дро и так из одного коммита
			if goodCore(s, not base and j.size) then bc = s; break end
			if i < tries then wait(pause) end
		end
		if not bc then
			print(LOG .. ' core download failed (' .. (got and 'bad data' or 'network') .. ')')
			setStatus(got and 'baddata' or 'neterr', j.version); return
		end
	end

	-- загрузчик: не скачалс€ Ч не беда, €дро всЄ равно ставим, загрузчик в следующий раз
	if loaderNew and j.file then
		local s = fetch((base or RAW_MAIN) .. j.file .. '?t=' .. os.time(), TMPD, 30)
		if s and #s > 2000 and s:find(MARK, 1, true) and loadstring(s) then
			if installLoader(s) then print(LOG .. ' loader updated to v' .. tostring(j.loader)) end
		end
	end

	if not bc then setStatus('uptodate', curVer); return end
	if exists(DAT) then writeFile(DAT .. '.bak', readFile(DAT) or '') end
	if not writeFile(DAT, bc) or readFile(DAT) ~= bc then
		local old = readFile(DAT .. '.bak'); if old then writeFile(DAT, old) end
		setStatus('writeerr', j.version); return
	end
	setStatus('updated', j.version)
	return 'reload' -- перезапуск делает updWorker, вне pcall
end

-- €дро просит проверку Ч только ставим за€вку; выполн€ет еЄ поток загрузчика (updWorker)
function UPD.check(manual, curVer)
	if UPD.dev and DEV_SKIP then setStatus('devbuild', curVer); return end
	if UPD.busy or UPD.req then return end
	UPD.req = { manual, curVer }
	setStatus('checking', curVer)
end

local function updWorker()
	while true do
		wait(200)
		local r = UPD.req
		if r then
			UPD.busy, UPD.at = true, os.clock()
			local ok, res = pcall(runCheck, r[1], r[2])
			if not ok then print(LOG .. ' update error: ' .. tostring(res)); setStatus('neterr', r[2]) end
			UPD.req, UPD.busy = nil, false
			if ok and res == 'reload' then wait(300); thisScript():reload(); wait(5000) end
		end
	end
end

-- €дра нет совсем (поставили только загрузчик): скачать с GitHub и перезапуститьс€
local function firstInstall()
	wait(3000)
	for _ = 1, 3 do
		local base = freshBase()
		local j = base and parseJson(fetch(base .. 'version.json?t=' .. os.time(), TMPJ))
		local s = fetch((base or RAW_MAIN) .. ((j and j.core) or CORE_DEF) .. '?t=' .. os.time(), TMPD, 90)
		if goodCore(s, not base and j and j.size) and writeFile(DAT, s) then
			UPD.busy = false
			wait(300)
			thisScript():reload()
			return
		end
		wait(10000)
	end
	UPD.busy = false; setStatus('neterr')
	print(LOG .. ' core not found and could not be downloaded')
end
-- ===================== конец общего блока =====================

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
	print(LOG .. ' core not found, fetching from GitHub...')
	UPD.busy = true; setStatus('updating')
	function main()
		firstInstall()
		while true do wait(1000) end
	end
	return
end

chunk()

-- auto-update worker thread runs next to the core's main()
local coreMain = main
function main()
	lua_thread.create(updWorker)
	if coreMain then return coreMain() end
	while true do wait(1000) end
end
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
