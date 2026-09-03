-- panel.luau — радио: станции не пропадают, меню редактирования
--!nonstrict

local stations = {}
local current_index = 1
local is_playing = false
local current_name = ""
local volume = 80
local last_state_version = -1

local base_width = 400
local base_height = 500

noctalia.log("Radio panel: скрипт загружен")

local function sendCommand(cmd)
    noctalia.state.set("cmd", cmd)
end

local function syncFromWidget()
    local s = noctalia.state.get("stations")
    -- Если в состоянии есть станции — используем их, иначе оставляем текущую таблицу (не обнуляем)
    if s and #s > 0 then
        stations = s
    elseif not s then
        -- Если состояние вообще не задано — можно оставить как есть или сбросить
        stations = {}
    end

    local ci = noctalia.state.get("current_index")
    if ci then current_index = ci end

    is_playing = noctalia.state.get("is_playing") or false
    current_name = noctalia.state.get("current_name") or ""
    volume = noctalia.state.get("volume") or volume
end

-- ==========================================
-- Состояние меню редактирования
-- ==========================================
local editing_mode = false
local edit_name = ""
local edit_url = ""

local render  -- forward declaration

-- ==========================================
-- Рендер модального окна редактирования
-- ==========================================
local function buildEditModal()
    -- Секция добавления
    local add_section = ui.column({ gap = 8, width = "100%" }, {
        ui.label({
            text = "Добавить станцию",
            fontSize = 14, fontWeight = "bold",
            color = "primary"
        }),
        ui.input({
            placeholder = "Название станции",
            value = edit_name,
            onChange = "onEditNameInput"
        }),
        ui.input({
            placeholder = "URL потока",
            value = edit_url,
            onChange = "onEditUrlInput"
        }),
        ui.button({
            text = "Добавить", variant = "primary", controlSize = "md",
            onClick = "onAddStationClicked"
        })
    })

    -- Список для удаления
    local delete_section
    if #stations == 0 then
        delete_section = ui.column({
            gap = 8, align = "center", justify = "center"
        }, {
            ui.glyph({ name = "info", size = 24, color = "on_surface_variant" }),
            ui.label({
                text = "Нет станций для удаления",
                fontSize = 13,
                color = "on_surface_variant"
            })
        })
    else
        local delete_rows = {}
        for i, station in ipairs(stations) do
            table.insert(delete_rows, ui.row({
                key = "del_" .. tostring(i),
                gap = 8, align = "center", padding = 8,
                radius = 6, fill = "surface_variant/0.3"
            }, {
                ui.label({
                    text = station.name, fontSize = 13, flexGrow = 1,
                    color = "on_surface"
                }),
                ui.button({
                    glyph = "trash", variant = "ghost", controlSize = "sm",
                    onClick = function()
                        sendCommand({ action = "remove", index = i })
                    end
                })
            }))
        end

        delete_section = ui.column({ gap = 6, width = "100%", flexGrow = 1 }, {
            ui.label({
                text = "Удалить станцию",
                fontSize = 14, fontWeight = "bold",
                color = "on_surface_variant"
            }),
            ui.scroll({
                gap = 4, fill = "surface_variant/0.3",
                radius = 8, padding = 4, flexGrow = 1
            }, delete_rows)
        })
    end

    local done_button = ui.button({
        text = "Готово", variant = "secondary", controlSize = "lg",
        onClick = "onEditDoneClicked"
    })

    return ui.column({
        gap = 16, padding = 16,
        fill = "surface", flexGrow = 1
    }, {
        ui.row({ align = "center", justify = "space-between" }, {
            ui.label({
                text = "Управление станциями",
                fontSize = 18, fontWeight = "bold",
                color = "primary", flexGrow = 1
            }),
            ui.button({
                glyph = "close", variant = "ghost",
                onClick = "onEditDoneClicked"
            })
        }),
        ui.separator({ spacing = 4 }),
        add_section,
        ui.separator({ spacing = 4 }),
        delete_section,
        done_button
    })
end

-- ==========================================
-- Основной интерфейс
-- ==========================================
local function buildMainUI()
    if #stations == 0 then
        return ui.column({
            gap = 16, padding = 24,
            align = "center", justify = "center",
            fill = "surface", flexGrow = 1
        }, {
            ui.glyph({ name = "loader", size = 32, color = "primary" }),
            ui.label({ text = "Нет станций", color = "on_surface_variant" }),
            ui.label({
                text = "Добавьте их в меню управления",
                fontSize = 12, color = "on_surface_variant"
            })
        })
    end

    local header = ui.row({ align = "center", justify = "space-between" }, {
        ui.label({
            text = "Радио", fontSize = 18,
            fontWeight = "bold", color = "primary", flexGrow = 1
        }),
        ui.row({ gap = 4 }, {
            ui.button({
                glyph = "list-plus", variant = "ghost",
                tooltip = "Управление станциями",
                onClick = "onOpenEditMenuClicked"
            }),
            ui.button({
                glyph = "close", variant = "ghost",
                onClick = "onCloseClicked"
            })
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

    local controls = ui.row({ gap = 8, align = "center", justify = "center" }, {
        ui.button({
            glyph = "player-skip-back", variant = "ghost",
            controlSize = "lg", onClick = "onPrev"
        }),
        ui.button({
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
        ui.slider({
            min = 0, max = 100, step = 1,
            value = volume, flexGrow = 1,
            onChange = "onVolume"
        }),
        ui.label({
            text = volume .. "%", fontSize = 12,
            color = "on_surface_variant"
        })
    })

    local sep = ui.separator({ spacing = 4 })

    local station_rows = {}
    for i, station in ipairs(stations) do
        local is_current = (i == current_index) and is_playing
        table.insert(station_rows, ui.row({
            key = tostring(i),
            gap = 8, align = "center", padding = 8,
            radius = 6,
            fill = is_current and "primary/0.15" or "surface_variant/0.3",
            onClick = function()
                sendCommand({ action = "select", index = i })
            end
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

    local station_list = ui.scroll({
        gap = 2, fill = "surface_variant/0.3",
        radius = 8, padding = 4, flexGrow = 1
    }, station_rows)

    return ui.column({
        gap = 12, padding = 16,
        fill = "surface", flexGrow = 1
    }, {
        header,
        now_playing,
        controls,
        volume_row,
        sep,
        station_list
    })
end

local function buildTree()
    if editing_mode then
        return buildEditModal()
    end
    return buildMainUI()
end

render = function()
    panel.render(buildTree())
end

-- ==========================================
-- Колбэки панели
-- ==========================================
function onOpen(context)
    panel.setWantsSecondTicks(true)
    local new_width = math.floor(base_width * 1.3)
    panel.setSize(new_width, base_height)
    syncFromWidget()
    last_state_version = noctalia.state.get("state_version") or 0
    editing_mode = false
    edit_name = ""
    edit_url = ""
    render()
end

function update()
    local sv = noctalia.state.get("state_version") or 0
    if sv ~= last_state_version then
        last_state_version = sv
        syncFromWidget()
        render()
    end
end

function onCloseClicked()
    panel.close()
end

function onToggle()
    sendCommand({ action = "toggle" })
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

-- ==========================================
-- Колбэки меню редактирования
-- ==========================================
function onOpenEditMenuClicked()
    editing_mode = true
    render()
end

function onEditDoneClicked()
    editing_mode = false
    render()
end

function onEditNameInput(text)
    edit_name = text or ""
end

function onEditUrlInput(text)
    edit_url = text or ""
end

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
