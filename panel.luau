-- panel.luau v13 — принудительная пересборка кнопки через key
--!nonstrict

local stations = {}
local current_index = 1
local is_playing = false
local current_name = ""
local volume = 80
local prev_is_playing = nil
local prev_stations_count = 0
local prev_current_index = nil
local prev_volume = nil
local prev_editing_mode = nil

noctalia.log("Radio panel v13: скрипт загружен. key-based forcing.")

local function sendCommand(cmd)
    noctalia.state.set("cmd", cmd)
end

local editing_mode = false
local edit_name = ""
local edit_url = ""
local render

-- ==========================================
-- UI: Модальное окно редактирования
-- ==========================================
local function buildEditModal()
    local add_section = ui.column({ gap = 8, width = "100%" }, {
        ui.label({ text = "Добавить станцию", fontSize = 14, fontWeight = "bold", color = "primary" }),
        ui.input({ placeholder = "Название", value = edit_name, onChange = "onEditNameInput" }),
        ui.input({ placeholder = "URL", value = edit_url, onChange = "onEditUrlInput" }),
        ui.button({ text = "Добавить", variant = "primary", controlSize = "md", onClick = "onAddStationClicked" })
    })

    local delete_section
    if #stations == 0 then
        delete_section = ui.column({ gap = 8, align = "center" }, {
            ui.glyph({ name = "info", size = 24, color = "on_surface_variant" }),
            ui.label({ text = "Нет станций", color = "on_surface_variant" })
        })
    else
        local rows = {}
        for i, station in ipairs(stations) do
            if type(station) == "table" and station.name then
                table.insert(rows, ui.row({ key = "del_" .. i, gap = 8, padding = 8, radius = 6, fill = "surface_variant/0.3" }, {
                    ui.label({ text = station.name, fontSize = 13, flexGrow = 1, color = "on_surface" }),
                    ui.button({ glyph = "trash", variant = "ghost", controlSize = "sm", onClick = function() sendCommand({ action = "remove", index = i }) end })
                }))
            end
        end
        delete_section = ui.column({ gap = 6, width = "100%", flexGrow = 1 }, {
            ui.label({ text = "Удалить станцию", fontSize = 14, fontWeight = "bold", color = "on_surface_variant" }),
            ui.scroll({ gap = 4, fill = "surface_variant/0.3", radius = 8, padding = 4, flexGrow = 1 }, rows)
        })
    end

    return ui.column({ gap = 16, padding = 16, fill = "surface", flexGrow = 1 }, {
        ui.row({ align = "center", justify = "space-between" }, {
            ui.label({ text = "Управление станциями", fontSize = 18, fontWeight = "bold", color = "primary", flexGrow = 1 }),
            ui.button({ glyph = "close", variant = "ghost", onClick = "onEditDoneClicked" })
        }),
        ui.separator({ spacing = 4 }),
        add_section,
        ui.separator({ spacing = 4 }),
        delete_section,
        ui.button({ text = "Готово", variant = "secondary", controlSize = "lg", onClick = "onEditDoneClicked" })
    })
end

-- ==========================================
-- UI: Основной интерфейс
-- ==========================================
local function buildMainUI()
    if #stations == 0 then
        return ui.column({ gap = 16, padding = 24, align = "center", fill = "surface", flexGrow = 1 }, {
            ui.glyph({ name = "loader", size = 32, color = "primary" }),
            ui.label({ text = "Нет станций", color = "on_surface_variant" }),
            ui.label({ text = "Добавьте их в меню управления", fontSize = 12, color = "on_surface_variant" })
        })
    end

    local header = ui.row({ align = "center", justify = "space-between" }, {
        ui.label({ text = "Радио", fontSize = 18, fontWeight = "bold", color = "primary", flexGrow = 1 }),
        ui.row({ gap = 4 }, {
            ui.button({ glyph = "list-plus", variant = "ghost", tooltip = "Управление", onClick = "onOpenEditMenuClicked" }),
            ui.button({ glyph = "close", variant = "ghost", onClick = "onCloseClicked" })
        })
    })

    local now_playing = ui.row({ gap = 8, align = "center" }, {
        ui.glyph({
            name = "radio",
            size = 16,
            color = is_playing and "primary" or "on_surface_variant"
        }),
        ui.label({
            text = is_playing and current_name or "Не воспроизводится",
            fontSize = 14, flexGrow = 1,
            color = is_playing and "on_surface" or "on_surface_variant"
        })
    })

    -- ГЛАВНОЕ: key меняется в зависимости от is_playing
    -- Это заставляет UI-движок СОЗДАТЬ НОВУЮ кнопку вместо обновления старой
    local controls = ui.row({ gap = 8, align = "center", justify = "center" }, {
        ui.button({
            glyph = "player-skip-back", variant = "ghost",
            controlSize = "lg", onClick = "onPrev"
        }),
        ui.button({
            key = is_playing and "btn_stop" or "btn_play",
            glyph = is_playing and "player-stop" or "player-play",
            variant = "primary", controlSize = "lg",
            onClick = "onToggle"
        }),
        ui.button({
            glyph = "player-skip-forward", variant = "ghost",
            controlSize = "lg", onClick = "onNext"
        })
    })

    local volume_row = ui.row({ gap = 8, align = "center" }, {
        ui.glyph({ name = "volume-2", size = 14, color = "on_surface_variant" }),
        ui.slider({ min = 0, max = 100, step = 1, value = volume, flexGrow = 1, onChange = "onVolume" }),
        ui.label({ text = volume .. "%", fontSize = 12, color = "on_surface_variant" })
    })

    local station_rows = {}
    for i, station in ipairs(stations) do
        if type(station) == "table" and station.name then
            local is_current = (i == current_index) and is_playing
            table.insert(station_rows, ui.row({
                key = tostring(i), gap = 8, align = "center", padding = 8, radius = 6,
                fill = is_current and "primary/0.15" or "surface_variant/0.3",
                onClick = function() sendCommand({ action = "select", index = i }) end
            }, {
                ui.glyph({
                    name = is_current and "player-play" or "point",
                    size = 14,
                    color = is_current and "primary" or "on_surface_variant"
                }),
                ui.label({
                    text = station.name, fontSize = 13, flexGrow = 1,
                    color = is_current and "primary" or "on_surface"
                })
            }))
        end
    end

    return ui.column({ gap = 12, padding = 16, fill = "surface", flexGrow = 1 }, {
        header, now_playing, controls, volume_row, ui.separator({ spacing = 4 }),
        ui.scroll({ gap = 2, fill = "surface_variant/0.3", radius = 8, padding = 4, flexGrow = 1 }, station_rows)
    })
end

local function buildTree()
    return editing_mode and buildEditModal() or buildMainUI()
end

render = function() panel.render(buildTree()) end

-- ==========================================
-- Чтение состояния из виджета
-- ==========================================
local function syncState()
    local changed = false

    local s = noctalia.state.get("stations")
    if s and type(s) == "table" then
        if #s ~= prev_stations_count then
            stations = s
            prev_stations_count = #s
            changed = true
        elseif #s > 0 then
            stations = s
        end
    end

    local ci = noctalia.state.get("current_index")
    if ci ~= nil and ci ~= prev_current_index then
        current_index = ci
        prev_current_index = ci
        changed = true
    end

    local playing = noctalia.state.get("is_playing")
    if playing ~= nil and playing ~= prev_is_playing then
        is_playing = playing
        prev_is_playing = playing
        changed = true
        noctalia.log("Radio panel: is_playing изменился на " .. tostring(is_playing))
    end

    local name = noctalia.state.get("current_name")
    if name ~= nil then current_name = name end

    local vol = noctalia.state.get("volume")
    if vol ~= nil and vol ~= prev_volume then
        volume = vol
        prev_volume = vol
        changed = true
    end

    if editing_mode ~= prev_editing_mode then
        prev_editing_mode = editing_mode
        changed = true
    end

    return changed
end

-- ==========================================
-- Колбэки панели
-- ==========================================
function onOpen(context)
    noctalia.log("Radio panel: onOpen")
    noctalia.setUpdateInterval(500)

    -- Сброс prev-переменных, чтобы при следующем update() точно сработал render
    prev_is_playing = nil
    prev_stations_count = 0
    prev_current_index = nil
    prev_volume = nil
    prev_editing_mode = nil

    -- Читаем начальное состояние
    local s = noctalia.state.get("stations")
    if s and type(s) == "table" then stations = s end

    local ci = noctalia.state.get("current_index")
    if ci then current_index = ci end

    local playing = noctalia.state.get("is_playing")
    if playing ~= nil then is_playing = playing end

    local name = noctalia.state.get("current_name")
    if name then current_name = name end

    local vol = noctalia.state.get("volume")
    if vol then volume = vol end

    editing_mode = false
    edit_name = ""
    edit_url = ""
    render()
end

function update()
    -- Перерисовываем только если что-то реально изменилось
    if syncState() then
        render()
    end
end

function onCloseClicked() panel.close() end
function onToggle()
    sendCommand({ action = "toggle" })
    -- Оптимистичное обновление: меняем локальный флаг сразу,
    -- чтобы кнопка отреагировала мгновенно, не дожидаясь ответа виджета
    is_playing = not is_playing
    prev_is_playing = is_playing
    if is_playing then
        current_name = "Загрузка..."
    else
        current_name = ""
    end
    render()
end

function onNext()
    sendCommand({ action = "next" })
end

function onPrev()
    sendCommand({ action = "prev" })
end

function onVolume(value)
    local vol = tonumber(value)
    if vol then
        volume = math.floor(vol)
        sendCommand({ action = "volume", value = volume })
    end
end

function onOpenEditMenuClicked() editing_mode = true; render() end
function onEditDoneClicked() editing_mode = false; render() end
function onEditNameInput(text) edit_name = text or "" end
function onEditUrlInput(text) edit_url = text or "" end

function onAddStationClicked()
    if edit_name and edit_url and edit_name ~= "" and edit_url ~= "" then
        sendCommand({ action = "add", name = edit_name, url = edit_url })
        edit_name = ""
        edit_url = ""
    else
        noctalia.notify("Радио", "Укажите название и URL")
    end
    render()
end

