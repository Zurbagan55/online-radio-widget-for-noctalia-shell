-- widget.luau v6 — радио-виджет
--!nonstrict

local m3u_path = noctalia.expandPath(
    noctalia.getConfig("m3u_path") or "~/Музыка/myradio.m3u"
)
local mpv_socket = noctalia.getConfig("mpv_socket") or "/tmp/mpv_radio_socket"
local default_volume = noctalia.getConfig("default_volume") or 80
local show_station_name = noctalia.getConfig("show_station_name")
if show_station_name == nil then show_station_name = true end

local stations = {}
local current_index = 1
local is_playing = false
local current_station_name = ""
local volume = default_volume
local volume_display_timer = 0
local state_version = 0
local publishing = false

noctalia.log("Radio widget v6: скрипт загружен, m3u=" .. m3u_path)

-- ===== Утилиты =====
local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clamp(val, lo, hi)
    if val < lo then return lo end
    if val > hi then return hi end
    return val
end

local function shellEscape(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- ===== Проверка зависимостей =====
local function checkDeps()
    if not noctalia.commandExists("mpv") then
        noctalia.notifyError("Radio", "mpv не установлен. sudo pacman -S mpv")
        return false
    end
    if not noctalia.commandExists("socat") then
        noctalia.notifyError("Radio", "socat не установлен. sudo pacman -S socat")
        return false
    end
    return true
end

-- ===== Сохранение/загрузка состояния =====
local function getDataPath()
    local dir = noctalia.pluginDataDir()
    return dir and (dir .. "/radio_state.json")
end

local function saveState()
    local path = getDataPath()
    if not path then return end
    noctalia.writeFile(path, noctalia.json.encode({
        station_index = current_index,
        volume = volume,
        is_playing = is_playing,
        current_station_name = current_station_name
    }))
end

local function loadSavedState()
    local path = getDataPath()
    if not path then return nil end
    local raw = noctalia.readFile(path)
    if not raw then return nil end
    return noctalia.json.decode(raw)
end

-- ===== Парсинг M3U =====
local function loadStations()
    stations = {}
    local raw = noctalia.readFile(m3u_path)
    if not raw then
        noctalia.log("Radio: M3U файл не найден: " .. m3u_path)
        return
    end

    local name = nil
    for line in raw:gmatch("[^\r\n]+") do
        line = trim(line)
        if line:sub(1, 7) == "#EXTINF" then
            local comma = line:find(",")
            if comma then name = line:sub(comma + 1) end
        elseif line:sub(1, 1) ~= "#" and line ~= "" then
            table.insert(stations, { name = name or line, url = line })
            name = nil
        end
    end
    noctalia.log("Radio: загружено станций: " .. #stations)
end

-- ===== Запись M3U =====
local function saveStations()
    local content = "#EXTM3U\n"
    for _, station in ipairs(stations) do
        content = content .. "#EXTINF:-1," .. station.name .. "\n" .. station.url .. "\n"
    end
    noctalia.writeFile(m3u_path, content)
    noctalia.log("Radio: сохранён M3U, станций: " .. #stations)
end

-- ===== MPV IPC =====
local function sendMpvCmd(cmd_table)
    local json = noctalia.json.encode(cmd_table)
    if not json then return end
    json = json:gsub("'", "'\\''")
    noctalia.runAsync(string.format(
        "echo '%s' | socat -T1 - UNIX-CONNECT:%s 2>/dev/null",
        json, mpv_socket
    ))
end

local function checkMpvAlive(callback)
    local cmd = string.format(
        "echo '{\"command\":[\"get_property\",\"volume\"]}' | socat -T2 - UNIX-CONNECT:%s 2>/dev/null",
        mpv_socket
    )
    noctalia.runAsync(cmd, function(result)
        if result and result.exitCode == 0 and result.stdout and result.stdout ~= "" then
            callback(true)
        else
            callback(false)
        end
    end)
end

-- ===== Публикация состояния =====
local function publishState()
    if publishing then return end
    publishing = true
    state_version = state_version + 1
    noctalia.state.set("state_version", state_version)
    noctalia.state.set("stations", stations)
    noctalia.state.set("current_index", current_index)
    noctalia.state.set("is_playing", is_playing)
    noctalia.state.set("current_name", current_station_name)
    noctalia.state.set("volume", volume)
    noctalia.log("Radio: publishState v" .. state_version .. " playing=" .. tostring(is_playing))
    publishing = false
end

-- ===== Отображение виджета на баре =====
-- На баре ВСЕГДА иконка радио. Цвет меняется в зависимости от состояния.
local function updateWidgetDisplay()
    if not barWidget or not barWidget.setTooltip then return end

    local tooltip
    if #stations == 0 then
        tooltip = "Нет станций. Проверьте путь к M3U."
    elseif is_playing then
        tooltip = "Станция: " .. current_station_name
            .. "\nЛКМ — список · Колесо — громкость"
    else
        tooltip = "Радио выключено\nЛКМ — список станций"
    end
    barWidget.setTooltip(tooltip)

    if volume_display_timer > 0 then
        barWidget.setGlyph("volume-2")
        barWidget.setGlyphColor("primary")
        barWidget.setColor("primary")
        barWidget.setText(volume .. "%")
        volume_display_timer = volume_display_timer - 1
        return
    end

    barWidget.setGlyph("radio")
    if is_playing then
        barWidget.setGlyphColor("primary")
        barWidget.setColor("primary")
        if show_station_name then
            local name = current_station_name
            if #name > 20 then name = name:sub(1, 17) .. "..." end
            barWidget.setText(name)
        else
            barWidget.setText("")
        end
    else
        barWidget.setGlyphColor("on_surface_variant")
        barWidget.setColor("on_surface_variant")
        barWidget.setText("")
    end
end

-- ===== Управление радио =====
local function startRadio()
    noctalia.log("Radio: startRadio, idx=" .. current_index .. ", stations=" .. #stations)

    if #stations == 0 then
        loadStations()
        if #stations == 0 then
            noctalia.notifyError("Radio", "Нет станций в M3U")
            return
        end
    end

    local station = stations[current_index]
    if not station then
        noctalia.log("Radio: станция " .. current_index .. " не найдена")
        return
    end

    noctalia.log("Radio: запускаю: " .. station.name .. " url=" .. station.url)

    local cmd = string.format(
        "echo '{\"command\":[\"quit\"]}' | socat -T2 - UNIX-CONNECT:%s 2>/dev/null; sleep 0.3; rm -f %s 2>/dev/null; setsid mpv --no-video --no-terminal --input-ipc-server=%s --volume=%d %s </dev/null >/dev/null 2>&1",
        mpv_socket, mpv_socket, mpv_socket, volume, shellEscape(station.url)
    )
    noctalia.runAsync(cmd)

    is_playing = true
    current_station_name = station.name
    saveState()
    publishState()
    updateWidgetDisplay()
    noctalia.notify("Radio", "▶ " .. station.name)
end

local function stopRadio()
    noctalia.log("Radio: stopRadio")
    sendMpvCmd({ command = { "quit" } })
    is_playing = false
    current_station_name = ""
    saveState()
    publishState()
    updateWidgetDisplay()
    noctalia.notify("Radio", "Воспроизведение остановлено")
end

local function nextStation()
    if #stations == 0 then return end
    current_index = current_index + 1
    if current_index > #stations then current_index = 1 end
    startRadio()
end

local function prevStation()
    if #stations == 0 then return end
    current_index = current_index - 1
    if current_index < 1 then current_index = #stations end
    startRadio()
end

local function setVolume(vol)
    volume = clamp(math.floor(vol), 0, 100)
    sendMpvCmd({ command = { "set_property", "volume", volume } })
    saveState()
    publishState()
    volume_display_timer = 2
    updateWidgetDisplay()
end

local function toggleRadio()
    if is_playing then stopRadio() else startRadio() end
end

-- ===== Добавление/удаление станций =====
local function addStation(name, url)
    table.insert(stations, { name = name, url = url })
    saveStations()
    publishState()
    updateWidgetDisplay()
    noctalia.notify("Радио", "Добавлена станция: " .. name)
end

local function removeStation(index)
    if index < 1 or index > #stations then return end

    if index == current_index and is_playing then
        stopRadio()
    end

    table.remove(stations, index)

    if index < current_index then
        current_index = current_index - 1
    elseif index == current_index and current_index > #stations then
        current_index = #stations
    end

    if current_index < 1 then current_index = 1 end

    saveStations()
    saveState()
    publishState()
    updateWidgetDisplay()
    noctalia.notify("Радио", "Станция удалена")
end

-- ===== Колбэки виджета =====
function update()
    if not barWidget then return end
    noctalia.setUpdateInterval(2000)
    updateWidgetDisplay()
end

function onScroll(axis, steps)
    if axis ~= "vertical" then return end
    setVolume(volume - steps * 5)
end

function onExit(signal, reason)
    saveState()
    if reason == "uninstall" or reason == "shutdown" then
        sendMpvCmd({ command = { "quit" } })
        noctalia.log("Radio: onExit reason=" .. tostring(reason) .. " — mpv остановлен")
    else
        noctalia.log("Radio: onExit reason=" .. tostring(reason) .. " — mpv не тронут")
    end
end

-- ===== Команды от панели =====
noctalia.state.watch("cmd", function(cmd)
    if type(cmd) ~= "table" or type(cmd.action) ~= "string" then
        return
    end
    noctalia.log("Radio: команда: " .. cmd.action .. " index=" .. tostring(cmd.index))

    local ok, err = pcall(function()
        if cmd.action == "play" then startRadio()
        elseif cmd.action == "stop" then stopRadio()
        elseif cmd.action == "toggle" then toggleRadio()
        elseif cmd.action == "next" then nextStation()
        elseif cmd.action == "prev" then prevStation()
        elseif cmd.action == "select" and cmd.index then
            local idx = tonumber(cmd.index)
            if idx and idx >= 1 and idx <= #stations then
                current_index = idx
                startRadio()
            end
        elseif cmd.action == "volume" and cmd.value then
            setVolume(cmd.value)
        elseif cmd.action == "add" and cmd.name and cmd.url then
            addStation(cmd.name, cmd.url)
        elseif cmd.action == "remove" and cmd.index then
            local idx = tonumber(cmd.index)
            if idx then removeStation(idx) end
        end
    end)
    if not ok then
        noctalia.log("Radio: ошибка: " .. tostring(err))
    end
end)

-- ===== Инициализация =====
checkDeps()
loadStations()

if #stations == 0 and not noctalia.fileExists(m3u_path) then
    noctalia.writeFile(m3u_path, "#EXTM3U\n")
    noctalia.log("Radio: создан пустой M3U: " .. m3u_path)
end

local saved = loadSavedState()
if saved then
    if saved.station_index then current_index = saved.station_index end
    if saved.volume then volume = saved.volume end
end

publishState()
updateWidgetDisplay()

if saved and saved.is_playing then
    current_station_name = saved.current_station_name or ""
    checkMpvAlive(function(alive)
        if alive then
            is_playing = true
            noctalia.log("Radio: mpv жив, восстанавливаю")
            publishState()
            updateWidgetDisplay()
        else
            noctalia.log("Radio: mpv мёртв, перезапускаю")
            noctalia.removeFile(mpv_socket)
            startRadio()
        end
    end)
else
    noctalia.log("Radio: инициализация, станций: " .. #stations .. ", индекс: " .. current_index)
end

