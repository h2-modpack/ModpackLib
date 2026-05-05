local internal = AdamantModpackLib_Internal

public.overlays = public.overlays or {}
local overlays = public.overlays
overlays.order = overlays.order or {
    framework = 0,
    module = 1000,
    debug = 2000,
}

internal.overlays = internal.overlays or {
    hudText = {},
    stackedText = {},
    suppressedOwners = {},
}

local state = internal.overlays
local values = internal.values

local REGIONS = {
    middleRightStack = {
        RightOffset = 10,
        Y = 200,
        itemHeight = 28,
        gap = 4,
        groupGap = 12,
        justification = "Right",
        verticalJustification = "Top",
        fontSize = 18,
    },
}

local DEFAULT_TEXT_ARGS = {
    Text = "",
    Font = "MonospaceTypewriterBold",
    FontSize = 18,
    Color = { 1, 1, 1, 1 },
    ShadowRed = 0.1,
    ShadowBlue = 0.1,
    ShadowGreen = 0.1,
    OutlineColor = { 0.113, 0.113, 0.113, 1 },
    OutlineThickness = 2,
    ShadowAlpha = 1.0,
    ShadowBlur = 1,
    ShadowOffset = { 0, 4 },
    Justification = "Right",
    VerticalJustification = "Top",
    DataProperties = { OpacityWithOwner = true },
}

local function sanitizeComponentName(id)
    return "AdamantOverlay_" .. tostring(id):gsub("[^%w_%-]", "_")
end

local function getGameValue(name)
    if rom and rom.game and rom.game[name] ~= nil then
        return rom.game[name]
    end
    return _G[name]
end

local function resolveValue(value)
    if type(value) == "function" then
        return value()
    end
    return value
end

local function normalizeOwner(owner)
    if type(owner) == "string" and owner ~= "" then
        return owner
    end
    return nil
end

local function isOwnerSuppressed(entry)
    return entry.owner ~= nil and state.suppressedOwners[entry.owner] == true
end

local function isEntryVisible(entry)
    if isOwnerSuppressed(entry) then
        return false
    end
    local visible = resolveValue(entry.visible)
    return visible ~= false
end

local function isGameHudVisible()
    return getGameValue("ShowingCombatUI") == true
end

local function isVisible(entry)
    return isGameHudVisible() and isEntryVisible(entry)
end

local function resolveText(entry)
    return tostring(resolveValue(entry.text) or "")
end

local function isColumnVisible(rowVisible, column)
    if rowVisible == false then
        return false
    end
    local visible = resolveValue(column.visible)
    return visible ~= false
end

local function overlayOrderBand(order)
    if order >= overlays.order.debug then
        return "debug"
    end
    if order >= overlays.order.module then
        return "module"
    end
    return "framework"
end

local function sanitizeStackedTextArgs(textArgs)
    local sanitized = values.deepCopy(textArgs or {})
    sanitized.FontSize = nil
    sanitized.Justification = nil
    sanitized.VerticalJustification = nil
    sanitized.OffsetX = nil
    sanitized.OffsetY = nil
    return sanitized
end

local function columnComponentName(baseName, column, index)
    local suffix = column.key or index
    return sanitizeComponentName(baseName .. "." .. tostring(suffix))
end

local function layoutSignature(layout)
    layout = layout or {}
    return table.concat({
        tostring(layout.X),
        tostring(layout.Y),
        tostring(layout.RightOffset),
        tostring(layout.BottomOffset),
    }, "|")
end

local function ensureComponentData(entry)
    local screenData = getGameValue("ScreenData")
    if not (screenData and screenData.HUD and screenData.HUD.ComponentData) then
        return false
    end

    local data = values.deepCopy(entry.layout or {})
    data.Name = data.Name or "BlankObstacle"
    data.GroupName = data.GroupName or "HUD_Overlay"
    data.Alpha = data.Alpha or 1.0
    data.AlphaTarget = data.AlphaTarget or 1.0
    data.TextArgs = values.deepCopy(DEFAULT_TEXT_ARGS)
    for key, value in pairs(entry.textArgs or {}) do
        data.TextArgs[key] = values.deepCopy(value)
    end
    data.TextArgs.Text = ""
    screenData.HUD.ComponentData[entry.componentName] = data
    return true
end

local function discardExistingComponent(entry)
    local hudScreen = getGameValue("HUDScreen")
    local component = hudScreen and hudScreen.Components and hudScreen.Components[entry.componentName]
    if not component then
        return
    end

    local destroy = getGameValue("Destroy")
    if type(destroy) == "function" and component.Id ~= nil then
        destroy({ Id = component.Id })
    end
    hudScreen.Components[entry.componentName] = nil
    entry.displayedText = nil
    entry.displayedVisible = nil
    entry.componentLayoutSignature = nil
    entry.componentId = nil
end

local function ensureComponent(entry)
    if entry.deferUntilLayout == true and entry.layoutSignature == nil then
        ensureComponentData(entry)
        return nil
    end

    ensureComponentData(entry)

    local hudScreen = getGameValue("HUDScreen")
    if not hudScreen or not hudScreen.Components then
        return nil
    end

    local component = hudScreen.Components[entry.componentName]
    local createComponentFromData = getGameValue("CreateComponentFromData")
    local screenData = getGameValue("ScreenData")
    if not component and type(createComponentFromData) == "function"
        and screenData and screenData.HUD and screenData.HUD.ComponentData then

        local componentData = screenData.HUD.ComponentData[entry.componentName]
        if componentData then
            component = createComponentFromData(screenData.HUD.ComponentData, componentData)
            component.Screen = hudScreen
            hudScreen.Components[entry.componentName] = component
            entry.componentLayoutSignature = layoutSignature(entry.layout)
        end
    end

    if not component then
        return nil
    end

    if entry.componentId ~= component.Id then
        entry.componentId = component.Id
        entry.displayedText = nil
        entry.displayedVisible = nil
        entry.componentLayoutSignature = entry.componentLayoutSignature or layoutSignature(entry.layout)
    end

    return component
end

local function applyVisibility(entry, component, force)
    local nextVisible = isVisible(entry)
    if not force and nextVisible == entry.displayedVisible then
        return
    end

    local setAlpha = getGameValue("SetAlpha")
    if type(setAlpha) == "function" then
        setAlpha({ Id = component.Id, Fraction = nextVisible and 1.0 or 0.0, Duration = 0.0 })
    end
    entry.displayedVisible = nextVisible
end

local function updateText(entry, force)
    local component = ensureComponent(entry)
    if not component then
        return
    end

    local nextText = resolveText(entry)
    if not force and nextText == entry.displayedText then
        return
    end

    getGameValue("ModifyTextBox")({ Id = component.Id, Text = nextText })
    entry.displayedText = nextText
    if not isVisible(entry) then
        applyVisibility(entry, component, true)
    end
end

local function updateVisibility(entry, force)
    local component = ensureComponent(entry)
    if not component then
        return
    end

    applyVisibility(entry, component, force)
end

local function updateEntry(entry)
    updateText(entry)
    updateVisibility(entry)
end

local function stackedHandleId(region, id)
    return "stacked:" .. tostring(region) .. ":" .. tostring(id)
end

local function getRegionEntries(regionName)
    local entries = {}
    for _, entry in pairs(state.stackedText) do
        if entry.region == regionName and isEntryVisible(entry) then
            entries[#entries + 1] = entry
        end
    end
    table.sort(entries, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)
    return entries
end

local function layoutRegion(regionName)
    local region = REGIONS[regionName]
    if not region then
        return
    end

    local entries = getRegionEntries(regionName)
    local y = region.Y
    local previousBand = nil
    for index, entry in ipairs(entries) do
        local band = overlayOrderBand(entry.order)
        if index > 1 then
            if band ~= previousBand then
                y = y + (region.groupGap or region.gap or 0)
            else
                y = y + (region.gap or 0)
            end
        end

        local layout = {
            RightOffset = region.RightOffset,
            Y = y,
        }
        entry.setLayout(layout, {
            FontSize = region.fontSize,
            Justification = region.justification,
            VerticalJustification = region.verticalJustification,
        })
        y = y + (region.itemHeight or 24)
        previousBand = band
    end
end

local function refreshStackedEntry(entry, layoutAlreadyRefreshed)
    if layoutAlreadyRefreshed ~= true then
        layoutRegion(entry.region)
    end
    local visible = isEntryVisible(entry)
    entry.setVisible(visible)
    entry.refreshText(visible)
end

local function unregisterStackedEntry(region, key, unregisterComponents)
    state.stackedText[key] = nil
    unregisterComponents()
    overlays.refreshStackedText(region)
end

function overlays.refreshHudText(forceVisibility)
    for _, entry in pairs(state.hudText) do
        updateText(entry, forceVisibility == true)
        updateVisibility(entry, forceVisibility == true)
    end
end

function overlays.refreshStackedText(regionName)
    if regionName ~= nil then
        layoutRegion(regionName)
        for _, entry in pairs(state.stackedText) do
            if entry.region == regionName then
                refreshStackedEntry(entry, true)
            end
        end
        return
    end

    local laidOutRegions = {}
    for _, entry in pairs(state.stackedText) do
        if not laidOutRegions[entry.region] then
            layoutRegion(entry.region)
            laidOutRegions[entry.region] = true
        end
        refreshStackedEntry(entry, true)
    end
end

function overlays.setOwnerSuppressed(owner, suppressed)
    owner = normalizeOwner(owner)
    if not owner then
        return
    end

    local nextSuppressed = suppressed == true
    if (state.suppressedOwners[owner] == true) == nextSuppressed then
        return
    end

    state.suppressedOwners[owner] = nextSuppressed or nil
    overlays.refreshStackedText()
    overlays.refreshHudText(true)
end

local function refreshOverlayVisibility()
    overlays.refreshHudText(true)
end

local function ensureHooks()
    public.hooks.Wrap(internal, "StartRoomPresentation", "overlays:roomPresentation",
        function(base, currentRun, currentRoom, metaPointsAwarded)
            base(currentRun, currentRoom, metaPointsAwarded)
            refreshOverlayVisibility()
        end)
    public.hooks.Wrap(internal, "ShowCombatUI", "overlays:showCombatUI", function(base, flag, args)
        base(flag, args)
        refreshOverlayVisibility()
    end)
    public.hooks.Wrap(internal, "HideCombatUI", "overlays:hideCombatUI", function(base, flag, args)
        base(flag, args)
        refreshOverlayVisibility()
    end)
end

local function makeHandle(id)
    return {
        setText = function(text)
            local entry = state.hudText[id]
            if not entry then return end
            entry.text = text
            updateText(entry)
        end,
        setVisible = function(visible)
            local entry = state.hudText[id]
            if not entry then return end
            if type(visible) == "function" then
                entry.visible = visible
            else
                entry.visible = visible == true
            end
            if entry.deferHiddenComponentCreation == true and not isEntryVisible(entry) and entry.displayedText == nil then
                return
            end
            updateVisibility(entry)
        end,
        setLayout = function(layout, textArgs)
            local entry = state.hudText[id]
            if not entry then return end
            local nextLayout = layout or {}
            local nextSignature = layoutSignature(nextLayout)
            if entry.layoutSignature ~= nextSignature or entry.componentLayoutSignature ~= nextSignature then
                discardExistingComponent(entry)
            end
            entry.layout = nextLayout
            entry.layoutSignature = nextSignature
            for key, value in pairs(textArgs or {}) do
                entry.textArgs[key] = value
            end
            ensureComponentData(entry)
        end,
        refresh = function()
            local entry = state.hudText[id]
            if not entry then return end
            updateEntry(entry)
        end,
        unregister = function()
            local entry = state.hudText[id]
            if not entry then return end
            entry.visible = false
            updateVisibility(entry)
            discardExistingComponent(entry)
            state.hudText[id] = nil
        end,
    }
end

--- Registers or replaces one retained HUD text overlay.
---@param opts table
---@return table handle
function overlays.registerHudText(opts)
    assert(type(opts) == "table", "lib.overlays.registerHudText: opts must be a table")
    assert(type(opts.id) == "string" and opts.id ~= "",
        "lib.overlays.registerHudText: id must be a non-empty string")

    local entry = {
        id = opts.id,
        componentName = opts.componentName or sanitizeComponentName(opts.id),
        owner = normalizeOwner(opts.owner),
        layout = opts.layout or {},
        textArgs = opts.textArgs or {},
        text = opts.text or "",
        visible = opts.visible,
        displayedText = nil,
        deferHiddenComponentCreation = opts.deferHiddenComponentCreation == true,
        deferUntilLayout = opts.deferUntilLayout == true,
    }

    state.hudText[opts.id] = entry
    ensureComponentData(entry)
    ensureHooks()
    if opts.deferInitialUpdate ~= true then
        updateEntry(entry)
    end

    return makeHandle(opts.id)
end

--- Registers or replaces one text overlay in a managed stack region.
---@param opts table
---@return table handle
function overlays.registerStackedText(opts)
    assert(type(opts) == "table", "lib.overlays.registerStackedText: opts must be a table")
    assert(type(opts.id) == "string" and opts.id ~= "",
        "lib.overlays.registerStackedText: id must be a non-empty string")

    local region = opts.region or "middleRightStack"
    assert(REGIONS[region] ~= nil,
        "lib.overlays.registerStackedText: unknown region '" .. tostring(region) .. "'")

    local handle = overlays.registerHudText({
        id = stackedHandleId(region, opts.id),
        componentName = opts.componentName,
        owner = normalizeOwner(opts.owner),
        layout = {},
        textArgs = sanitizeStackedTextArgs(opts.textArgs),
        text = opts.text,
        visible = false,
        deferInitialUpdate = true,
        deferHiddenComponentCreation = true,
        deferUntilLayout = true,
    })

    local key = region .. "\0" .. opts.id
    local entry = nil
    entry = {
        id = opts.id,
        region = region,
        owner = normalizeOwner(opts.owner),
        order = tonumber(opts.order) or overlays.order.module,
        text = opts.text or "",
        visible = opts.visible,
        handle = handle,
        setLayout = function(layout, textArgs)
            handle.setLayout(layout, textArgs)
        end,
        setVisible = function(visible)
            handle.setVisible(visible)
        end,
        refreshText = function(visible)
            if visible then
                handle.setText(entry.text)
            end
        end,
    }
    state.stackedText[key] = entry
    refreshStackedEntry(entry)

    return {
        setText = function(text)
            entry.text = text
            refreshStackedEntry(entry)
        end,
        setVisible = function(visible)
            if type(visible) == "function" then
                entry.visible = visible
            else
                entry.visible = visible == true
            end
            refreshStackedEntry(entry)
        end,
        refresh = function()
            refreshStackedEntry(entry)
        end,
        refreshText = function()
            entry.refreshText(isEntryVisible(entry))
        end,
        unregister = function()
            unregisterStackedEntry(region, key, function()
                handle.unregister()
            end)
        end,
    }
end

--- Registers or replaces one multi-column text overlay row in a managed stack region.
---@param opts table
---@return table handle
function overlays.registerStackedRow(opts)
    assert(type(opts) == "table", "lib.overlays.registerStackedRow: opts must be a table")
    assert(type(opts.id) == "string" and opts.id ~= "",
        "lib.overlays.registerStackedRow: id must be a non-empty string")
    assert(type(opts.columns) == "table" and #opts.columns > 0,
        "lib.overlays.registerStackedRow: columns must be a non-empty array")

    local region = opts.region or "middleRightStack"
    assert(REGIONS[region] ~= nil,
        "lib.overlays.registerStackedRow: unknown region '" .. tostring(region) .. "'")

    local componentBase = opts.componentName or opts.id
    local columnGap = tonumber(opts.columnGap) or 6
    local columns = {}
    for index, column in ipairs(opts.columns) do
        assert(type(column) == "table", "lib.overlays.registerStackedRow: each column must be a table")
        local columnEntry = {
            key = column.key or tostring(index),
            minWidth = tonumber(column.minWidth) or 0,
            justify = column.justify,
            text = column.text or "",
            visible = column.visible,
            handle = overlays.registerHudText({
                id = stackedHandleId(region, opts.id .. ":" .. tostring(column.key or index)),
                componentName = column.componentName or columnComponentName(componentBase, column, index),
                owner = normalizeOwner(opts.owner),
                layout = {},
                textArgs = sanitizeStackedTextArgs(column.textArgs),
                text = column.text,
                visible = false,
                deferInitialUpdate = true,
                deferHiddenComponentCreation = true,
                deferUntilLayout = true,
            }),
        }
        columns[#columns + 1] = columnEntry
    end

    local entry = {
        id = opts.id,
        region = region,
        owner = normalizeOwner(opts.owner),
        order = tonumber(opts.order) or overlays.order.module,
        visible = opts.visible,
        columns = columns,
        setLayout = function(layout, textArgs)
            local trailingWidth = 0
            for index = #columns, 1, -1 do
                local column = columns[index]
                if not isColumnVisible(true, column) then
                    column.handle.setVisible(false)
                    goto continue
                end
                local columnTextArgs = values.deepCopy(textArgs or {})
                local justification = column.justify or columnTextArgs.Justification
                if justification then
                    columnTextArgs.Justification = justification
                end
                local rightOffset = (layout.RightOffset or 0) + trailingWidth
                if justification == "Left" then
                    rightOffset = rightOffset + column.minWidth
                end
                column.handle.setLayout({
                    RightOffset = rightOffset,
                    Y = layout.Y,
                }, columnTextArgs)
                trailingWidth = trailingWidth + column.minWidth
                if index > 1 then
                    trailingWidth = trailingWidth + columnGap
                end
                ::continue::
            end
        end,
        setVisible = function(visible)
            for _, column in ipairs(columns) do
                column.handle.setVisible(isColumnVisible(visible, column))
            end
        end,
        refreshText = function(visible)
            if not visible then return end
            for _, column in ipairs(columns) do
                if isColumnVisible(true, column) then
                    column.handle.setText(column.text)
                end
            end
        end,
    }

    local key = region .. "\0" .. opts.id
    state.stackedText[key] = entry
    refreshStackedEntry(entry)

    return {
        setColumnText = function(columnKey, text)
            for _, column in ipairs(columns) do
                if column.key == columnKey then
                    column.text = text
                    refreshStackedEntry(entry)
                    return true
                end
            end
            return false
        end,
        setVisible = function(visible)
            if type(visible) == "function" then
                entry.visible = visible
            else
                entry.visible = visible == true
            end
            refreshStackedEntry(entry)
        end,
        refresh = function()
            refreshStackedEntry(entry)
        end,
        refreshText = function()
            entry.refreshText(isEntryVisible(entry))
        end,
        unregister = function()
            unregisterStackedEntry(region, key, function()
                for _, column in ipairs(columns) do
                    column.handle.unregister()
                end
            end)
        end,
    }
end
