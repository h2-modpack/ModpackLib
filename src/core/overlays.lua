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
}

local state = internal.overlays
local values = internal.values
state.uiSuppressors = state.uiSuppressors or {}
state.nextUiSuppressorId = state.nextUiSuppressorId or 0
state.retained = state.retained or {}
state.retained.tableRegistries = state.retained.tableRegistries or setmetatable({}, { __mode = "k" })
state.retained.explicitRegistries = state.retained.explicitRegistries or {}
state.retained.nextOwnerId = state.retained.nextOwnerId or 0
state.retained.intervalDriverRegistered = state.retained.intervalDriverRegistered == true

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

local function isEntryVisible(entry)
    local visible = resolveValue(entry.visible)
    return visible ~= false
end

local function isGameHudVisible()
    return getGameValue("ShowingCombatUI") == true
end

local function isVisible(entry)
    return isGameHudVisible() and not overlays.isUiSuppressed() and isEntryVisible(entry)
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

local function retainedHandleId(registry, name)
    return tostring(registry.ownerId) .. ":" .. tostring(name)
end

local function retainedRowId(registry, name, index)
    return retainedHandleId(registry, name) .. ":row:" .. tostring(index)
end

local function getRetainedRegistry(owner, create)
    if type(owner) == "string" then
        local registry = state.retained.explicitRegistries[owner]
        if not registry and create then
            local hookOwner = {}
            registry = {
                owner = hookOwner,
                ownerId = owner,
                generation = 0,
                refreshing = false,
                elements = {},
                events = {
                    commit = {},
                    intervals = {},
                    afterHooks = {},
                },
            }
            state.retained.explicitRegistries[owner] = registry
            state.retained.tableRegistries[hookOwner] = registry
        end
        return registry
    end

    if type(owner) ~= "table" then
        internal.violate("overlays.invalid_registration", "lib.overlays: owner must be a persistent table or string")
    end

    local registry = state.retained.tableRegistries[owner]
    if not registry and create then
        state.retained.nextOwnerId = state.retained.nextOwnerId + 1
        registry = {
            owner = owner,
            ownerId = "owner" .. tostring(state.retained.nextOwnerId),
            generation = 0,
            refreshing = false,
            elements = {},
            events = {
                commit = {},
                intervals = {},
                afterHooks = {},
            },
        }
        state.retained.tableRegistries[owner] = registry
    end
    return registry
end

local function copyArray(source)
    local copy = {}
    for index, value in ipairs(source or {}) do
        copy[index] = value
    end
    return copy
end

local function copyMap(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function unregisterRetainedElement(slot)
    if not slot then
        return
    end
    if slot.kind == "line" and slot.handle then
        slot.handle.unregister()
        slot.handle = nil
        return
    end
    if slot.kind == "table" and slot.handles then
        for _, handle in ipairs(slot.handles) do
            handle.unregister()
        end
        slot.handles = {}
    end
end

local function readLineColumn(slot, column)
    local valuesTable = slot.values
    if type(valuesTable) ~= "table" then
        return valuesTable
    end
    return valuesTable[column.key]
end

local function normalizeLineColumns(spec)
    if type(spec.columns) == "table" and #spec.columns > 0 then
        return spec.columns
    end
    return {
        {
            key = "text",
            minWidth = spec.minWidth,
            justify = spec.justify,
            textArgs = spec.textArgs,
        },
    }
end

local function normalizeRetainedColumn(column, index, textResolver)
    return {
        key = column.key or tostring(index),
        componentName = column.componentName,
        minWidth = column.minWidth,
        justify = column.justify,
        visible = column.visible,
        textArgs = column.textArgs,
        text = textResolver,
    }
end

local function createRetainedLine(registry, name, spec, existingValues)
    local slot = {
        kind = "line",
        name = name,
        generation = registry.generation,
        spec = spec,
        values = existingValues,
    }
    local columns = {}
    for index, column in ipairs(normalizeLineColumns(spec)) do
        local key = column.key or tostring(index)
        columns[#columns + 1] = normalizeRetainedColumn(column, index, function()
            return readLineColumn(slot, { key = key }) or ""
        end)
    end
    slot.handle = overlays.registerStackedRow({
        id = retainedHandleId(registry, name),
        componentName = spec.componentName,
        region = spec.region,
        order = spec.order,
        columnGap = spec.columnGap,
        visible = spec.visible,
        columns = columns,
    })
    return slot
end

local function readTableCell(slot, rowIndex, column)
    local row = slot.rows and slot.rows[rowIndex] or nil
    if type(row) ~= "table" then
        return ""
    end
    return row[column.key] or ""
end

local function createRetainedTable(registry, name, spec, existingRows, existingRowIndexByKey)
    local maxRows = math.max(0, math.floor(tonumber(spec.maxRows) or 0))
    local slot = {
        kind = "table",
        name = name,
        generation = registry.generation,
        spec = spec,
        rows = existingRows or {},
        rowIndexByKey = existingRowIndexByKey or {},
        handles = {},
    }

    for rowIndex = 1, maxRows do
        local columns = {}
        for columnIndex, column in ipairs(spec.columns or {}) do
            local key = column.key or tostring(columnIndex)
            columns[#columns + 1] = normalizeRetainedColumn(column, columnIndex, function()
                return readTableCell(slot, rowIndex, { key = key })
            end)
        end

        slot.handles[rowIndex] = overlays.registerStackedRow({
            id = retainedRowId(registry, name, rowIndex),
            componentName = spec.componentName and (spec.componentName .. "_" .. tostring(rowIndex)) or nil,
            region = spec.region,
            order = (tonumber(spec.order) or overlays.order.module) + rowIndex - 1,
            columnGap = spec.columnGap,
            visible = function()
                local visible = resolveValue(spec.visible)
                return visible ~= false and slot.rows[rowIndex] ~= nil
            end,
            columns = columns,
        })
    end

    return slot
end

local function snapshotRetainedSlot(slot)
    if slot.kind == "line" then
        return {
            kind = slot.kind,
            name = slot.name,
            generation = slot.generation,
            spec = slot.spec,
            values = slot.values,
        }
    end
    return {
        kind = slot.kind,
        name = slot.name,
        generation = slot.generation,
        spec = slot.spec,
        rows = slot.rows,
        rowIndexByKey = slot.rowIndexByKey,
    }
end

local function snapshotRetainedRegistry(registry)
    local elements = {}
    for name, slot in pairs(registry.elements) do
        elements[name] = snapshotRetainedSlot(slot)
    end
    return {
        ownerId = registry.ownerId,
        generation = registry.generation,
        refreshing = registry.refreshing,
        elements = elements,
        events = {
            commit = copyArray(registry.events.commit),
            intervals = copyMap(registry.events.intervals),
            afterHooks = copyMap(registry.events.afterHooks),
        },
    }
end

local function restoreRetainedRegistry(registry, snapshot)
    for _, slot in pairs(registry.elements) do
        unregisterRetainedElement(slot)
    end

    registry.ownerId = snapshot.ownerId
    registry.generation = snapshot.generation
    registry.refreshing = snapshot.refreshing
    registry.events = {
        commit = copyArray(snapshot.events.commit),
        intervals = copyMap(snapshot.events.intervals),
        afterHooks = copyMap(snapshot.events.afterHooks),
    }
    registry.elements = {}

    for name, slotSnapshot in pairs(snapshot.elements) do
        if slotSnapshot.kind == "line" then
            local slot = createRetainedLine(registry, name, slotSnapshot.spec, slotSnapshot.values)
            slot.generation = slotSnapshot.generation
            registry.elements[name] = slot
        elseif slotSnapshot.kind == "table" then
            local slot = createRetainedTable(
                registry,
                name,
                slotSnapshot.spec,
                slotSnapshot.rows,
                slotSnapshot.rowIndexByKey
            )
            slot.generation = slotSnapshot.generation
            registry.elements[name] = slot
        end
    end
end

local function makeRetainedContext(registry)
    local owner = registry.owner
    local authorHost = registry.authorHost
    local store = registry.store
    local ctx = {}

    function ctx.read(alias)
        if store and type(store.read) == "function" then
            return store.read(alias)
        end
        return nil
    end

    function ctx.isEnabled()
        if authorHost and type(authorHost.isEnabled) == "function" then
            return authorHost.isEnabled()
        end
        return true
    end

    function ctx.log(fmt, ...)
        if authorHost and type(authorHost.log) == "function" then
            return authorHost.log(fmt, ...)
        end
        print(internal.formatLogMessage("[overlays:" .. tostring(registry.ownerId) .. "] ", fmt, ...))
    end

    function ctx.logIf(fmt, ...)
        if authorHost and type(authorHost.logIf) == "function" then
            return authorHost.logIf(fmt, ...)
        end
    end

    function ctx.setLine(name, valuesTable)
        local slot = registry.elements[name]
        if slot and slot.kind == "line" then
            slot.values = valuesTable
            return true
        end
        return false
    end

    function ctx.setTable(name, rows)
        local slot = registry.elements[name]
        if not (slot and slot.kind == "table") then
            return false
        end
        slot.rows = {}
        slot.rowIndexByKey = {}
        for index, row in ipairs(rows or {}) do
            if index > #slot.handles then
                break
            end
            slot.rows[index] = row
            if type(row) == "table" and row.key ~= nil then
                slot.rowIndexByKey[row.key] = index
            end
        end
        return true
    end

    function ctx.setCell(tableName, rowKey, columnKey, value)
        local slot = registry.elements[tableName]
        if not (slot and slot.kind == "table") then
            return false
        end
        local rowIndex = slot.rowIndexByKey[rowKey]
        local row = rowIndex and slot.rows[rowIndex] or nil
        if type(row) ~= "table" then
            return false
        end
        row[columnKey] = value
        return true
    end

    function ctx.refresh(name)
        local slot = registry.elements[name]
        if not slot then
            return false
        end
        if slot.kind == "line" then
            slot.handle.refresh()
        elseif slot.kind == "table" then
            for _, handle in ipairs(slot.handles) do
                handle.refresh()
            end
        end
        return true
    end

    function ctx.refreshRegion(region)
        overlays.refreshStackedText(region)
    end

    function ctx.refreshAll()
        overlays.refreshStackedText()
        overlays.refreshHudText(true)
    end

    ctx.owner = owner
    return ctx
end

local function ensureIntervalDriver()
    if state.retained.intervalDriverRegistered then
        return
    end
    state.retained.intervalDriverRegistered = true
    if rom and rom.gui and type(rom.gui.add_always_draw_imgui) == "function" then
        rom.gui.add_always_draw_imgui(function()
            internal.overlays.dispatchIntervals(os.clock())
        end)
    end
end

local function validateRetainedName(apiName, name)
    if type(name) ~= "string" or name == "" then
        internal.violate("overlays.invalid_registration", "lib.overlays.%s: name must be a non-empty string", apiName)
    end
end

local function validateRetainedSpec(apiName, spec)
    if type(spec) ~= "table" then
        internal.violate("overlays.invalid_registration", "lib.overlays.%s: spec must be a table", apiName)
    end
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

local function refreshAllOverlays()
    overlays.refreshStackedText()
    overlays.refreshHudText(true)
end

function overlays.isUiSuppressed()
    return next(state.uiSuppressors) ~= nil
end

function overlays.suppressForUi()
    state.nextUiSuppressorId = state.nextUiSuppressorId + 1
    local id = state.nextUiSuppressorId
    local wasSuppressed = overlays.isUiSuppressed()
    state.uiSuppressors[id] = true
    if not wasSuppressed then
        refreshAllOverlays()
    end

    local released = false
    return {
        release = function()
            if released then
                return
            end
            released = true
            state.uiSuppressors[id] = nil
            if not overlays.isUiSuppressed() then
                refreshAllOverlays()
            end
        end,
    }
end

local function createRetainedSurface(registry)
    return {
        createLine = function(name, spec)
            validateRetainedName("createLine", name)
            validateRetainedSpec("createLine", spec)
            registry.seenElements[name] = true

            local previous = registry.elements[name]
            local previousValues = previous and previous.kind == "line" and previous.values or nil
            if previous then
                unregisterRetainedElement(previous)
            end

            registry.elements[name] = createRetainedLine(registry, name, spec, previousValues)
        end,
        createTable = function(name, spec)
            validateRetainedName("createTable", name)
            validateRetainedSpec("createTable", spec)
            if type(spec.columns) ~= "table" or #spec.columns == 0 then
                internal.violate(
                    "overlays.invalid_registration",
                    "lib.overlays.createTable: columns must be a non-empty array"
                )
            end
            registry.seenElements[name] = true

            local previous = registry.elements[name]
            local previousRows = previous and previous.kind == "table" and previous.rows or nil
            local previousRowIndexByKey = previous and previous.kind == "table" and previous.rowIndexByKey or nil
            if previous then
                unregisterRetainedElement(previous)
            end

            registry.elements[name] = createRetainedTable(
                registry,
                name,
                spec,
                previousRows,
                previousRowIndexByKey
            )
        end,
        onCommit = function(callback)
            if type(callback) ~= "function" then
                internal.violate("overlays.invalid_registration", "lib.overlays.onCommit: callback must be a function")
            end
            registry.pendingEvents.commit[#registry.pendingEvents.commit + 1] = callback
        end,
        onInterval = function(name, seconds, callback, opts)
            validateRetainedName("onInterval", name)
            if type(callback) ~= "function" then
                internal.violate("overlays.invalid_registration", "lib.overlays.onInterval: callback must be a function")
            end
            seconds = tonumber(seconds)
            if not seconds or seconds <= 0 then
                internal.violate("overlays.invalid_registration", "lib.overlays.onInterval: seconds must be positive")
            end
            registry.pendingEvents.intervals[name] = {
                name = name,
                seconds = seconds,
                callback = callback,
                opts = opts or {},
                lastRun = registry.events.intervals[name] and registry.events.intervals[name].lastRun or nil,
            }
            ensureIntervalDriver()
        end,
        afterHook = function(path, callback)
            validateRetainedName("afterHook", path)
            if type(callback) ~= "function" then
                internal.violate("overlays.invalid_registration", "lib.overlays.afterHook: callback must be a function")
            end
            registry.pendingEvents.afterHooks[path] = {
                path = path,
                callback = callback,
            }
            public.hooks.WrapOwned(registry.owner, path, "overlay.after:" .. path, function(base, ...)
                local args = { ... }
                local results = { base(...) }
                internal.overlays.dispatchAfterHook(registry.owner, path, args, results)
                return table.unpack(results)
            end)
        end,
    }
end

function internal.overlays.beginTransaction(owner)
    local registry = getRetainedRegistry(owner, true)
    local snapshot = snapshotRetainedRegistry(registry)
    local closed = false

    return {
        commit = function()
            closed = true
        end,
        rollback = function()
            if closed then
                return
            end
            restoreRetainedRegistry(registry, snapshot)
            closed = true
        end,
    }
end

function internal.overlays.refresh(owner, ownerId, authorHost, store, register)
    if type(register) ~= "function" then
        internal.violate("overlays.invalid_registration", "internal.overlays.refresh: register must be a function")
    end

    local registry = getRetainedRegistry(owner, true)
    if type(ownerId) == "string" and ownerId ~= "" then
        registry.ownerId = ownerId
    end
    registry.authorHost = authorHost
    registry.store = store
    registry.generation = registry.generation + 1
    registry.refreshing = true
    registry.seenElements = {}
    registry.pendingEvents = {
        commit = {},
        intervals = {},
        afterHooks = {},
    }

    local ok, err = pcall(register, createRetainedSurface(registry))
    registry.refreshing = false

    if ok then
        for name, slot in pairs(registry.elements) do
            if not registry.seenElements[name] then
                unregisterRetainedElement(slot)
                registry.elements[name] = nil
            else
                slot.generation = registry.generation
            end
        end
        registry.events = registry.pendingEvents
    end

    registry.seenElements = nil
    registry.pendingEvents = nil

    if not ok then
        error(err, 0)
    end
end

function internal.overlays.dispatchCommit(owner, commit)
    local registry = getRetainedRegistry(owner, false)
    if not registry then
        return
    end

    local ctx = makeRetainedContext(registry)
    for _, callback in ipairs(registry.events.commit or {}) do
        callback(ctx, commit)
    end
end

function internal.overlays.dispatchIntervals(now)
    now = tonumber(now) or os.clock()
    local function dispatchRegistry(registry)
        local ctx = nil
        for _, event in pairs(registry.events.intervals or {}) do
            local shouldRun = true
            if event.opts and type(event.opts.when) == "function" then
                shouldRun = event.opts.when() == true
            end
            if shouldRun and (event.lastRun == nil or now - event.lastRun >= event.seconds) then
                event.lastRun = now
                ctx = ctx or makeRetainedContext(registry)
                event.callback(ctx, {
                    name = event.name,
                    now = now,
                })
            end
        end
    end

    for _, registry in pairs(state.retained.explicitRegistries) do
        dispatchRegistry(registry)
    end
    for _, registry in pairs(state.retained.tableRegistries) do
        dispatchRegistry(registry)
    end
end

function internal.overlays.dispatchAfterHook(owner, path, args, results)
    local registry = getRetainedRegistry(owner, false)
    local event = registry and registry.events.afterHooks and registry.events.afterHooks[path] or nil
    if not event then
        return
    end

    local ctx = makeRetainedContext(registry)
    event.callback(ctx, {
        path = path,
        args = args or {},
        result = results and results[1] or nil,
        results = results or {},
    })
end

function overlays.defineOwned(owner, register)
    if type(owner) ~= "string" or owner == "" then
        internal.violate("overlays.invalid_registration", "lib.overlays.defineOwned: owner must be a non-empty string")
    end
    local transaction = internal.overlays.beginTransaction(owner)
    local ok, err = pcall(function()
        internal.overlays.refresh(owner, owner, nil, nil, register)
    end)
    if ok then
        transaction.commit()
        internal.overlays.dispatchCommit(owner, {})
        return true
    end

    transaction.rollback()
    error(err, 0)
end

local function refreshOverlayVisibility()
    overlays.refreshHudText(true)
end

local function ensureHooks()
    public.hooks.WrapOwned(internal, "StartRoomPresentation", "overlays:roomPresentation",
        function(base, currentRun, currentRoom, metaPointsAwarded)
            base(currentRun, currentRoom, metaPointsAwarded)
            refreshOverlayVisibility()
        end)
    public.hooks.WrapOwned(internal, "ShowCombatUI", "overlays:showCombatUI", function(base, flag, args)
        base(flag, args)
        refreshOverlayVisibility()
    end)
    public.hooks.WrapOwned(internal, "HideCombatUI", "overlays:hideCombatUI", function(base, flag, args)
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
    if type(opts) ~= "table" then
        internal.violate("overlays.invalid_registration", "lib.overlays.registerHudText: opts must be a table")
    end
    if type(opts.id) ~= "string" or opts.id == "" then
        internal.violate("overlays.invalid_registration", "lib.overlays.registerHudText: id must be a non-empty string")
    end

    local entry = {
        id = opts.id,
        componentName = opts.componentName or sanitizeComponentName(opts.id),
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
    if type(opts) ~= "table" then
        internal.violate("overlays.invalid_registration", "lib.overlays.registerStackedText: opts must be a table")
    end
    if type(opts.id) ~= "string" or opts.id == "" then
        internal.violate("overlays.invalid_registration", "lib.overlays.registerStackedText: id must be a non-empty string")
    end

    local region = opts.region or "middleRightStack"
    if REGIONS[region] == nil then
        internal.violate(
            "overlays.invalid_registration",
            "lib.overlays.registerStackedText: unknown region '%s'",
            tostring(region)
        )
    end

    local handle = overlays.registerHudText({
        id = stackedHandleId(region, opts.id),
        componentName = opts.componentName,
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
    if type(opts) ~= "table" then
        internal.violate("overlays.invalid_registration", "lib.overlays.registerStackedRow: opts must be a table")
    end
    if type(opts.id) ~= "string" or opts.id == "" then
        internal.violate("overlays.invalid_registration", "lib.overlays.registerStackedRow: id must be a non-empty string")
    end
    if type(opts.columns) ~= "table" or #opts.columns == 0 then
        internal.violate("overlays.invalid_registration", "lib.overlays.registerStackedRow: columns must be a non-empty array")
    end

    local region = opts.region or "middleRightStack"
    if REGIONS[region] == nil then
        internal.violate(
            "overlays.invalid_registration",
            "lib.overlays.registerStackedRow: unknown region '%s'",
            tostring(region)
        )
    end

    local componentBase = opts.componentName or opts.id
    local columnGap = tonumber(opts.columnGap) or 6
    local columns = {}
    for index, column in ipairs(opts.columns) do
        if type(column) ~= "table" then
            internal.violate(
                "overlays.invalid_registration",
                "lib.overlays.registerStackedRow: column #%d must be a table",
                index
            )
        end
        local columnEntry = {
            key = column.key or tostring(index),
            minWidth = tonumber(column.minWidth) or 0,
            justify = column.justify,
            text = column.text or "",
            visible = column.visible,
            handle = overlays.registerHudText({
                id = stackedHandleId(region, opts.id .. ":" .. tostring(column.key or index)),
                componentName = column.componentName or columnComponentName(componentBase, column, index),
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
