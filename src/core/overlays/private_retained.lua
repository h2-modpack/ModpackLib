local deps = ...

local internal = AdamantModpackLib_Internal
local retainedState = deps.state
local renderer = deps.renderer

local function resolveValue(value)
    if type(value) == "function" then
        return value()
    end
    return value
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

local function validateName(apiName, name)
    if type(name) ~= "string" or name == "" then
        internal.violate("overlays.invalid_registration", "lib.overlays.%s: name must be a non-empty string", apiName)
    end
end

local function validateSpec(apiName, spec)
    if type(spec) ~= "table" then
        internal.violate("overlays.invalid_registration", "lib.overlays.%s: spec must be a table", apiName)
    end
end

local function retainedHandleId(registry, name)
    return tostring(registry.ownerId) .. ":" .. tostring(name)
end

local function retainedRowId(registry, name, index)
    return retainedHandleId(registry, name) .. ":row:" .. tostring(index)
end

local function ensureRegistryShape(registry, owner, explicitOwner)
    registry.hookOwner = registry.hookOwner or {}
    registry.owner = owner
    registry.explicitOwner = explicitOwner == true
end

local function getRegistry(owner, create)
    if type(owner) == "string" then
        local registry = retainedState.explicitRegistries[owner]
        if not registry and create then
            registry = {
                owner = owner,
                hookOwner = {},
                ownerId = owner,
                explicitOwner = true,
                generation = 0,
                refreshing = false,
                elements = {},
                events = {
                    commit = {},
                    intervals = {},
                    afterHooks = {},
                },
            }
            retainedState.explicitRegistries[owner] = registry
        end
        if registry then
            ensureRegistryShape(registry, owner, true)
        end
        return registry
    end

    if type(owner) ~= "table" then
        internal.violate("overlays.invalid_registration", "lib.overlays: owner must be a persistent table or string")
    end

    local registry = retainedState.tableRegistries[owner]
    if not registry and create then
        retainedState.nextOwnerId = retainedState.nextOwnerId + 1
        registry = {
            owner = owner,
            hookOwner = {},
            ownerId = "owner" .. tostring(retainedState.nextOwnerId),
            generation = 0,
            refreshing = false,
            elements = {},
            events = {
                commit = {},
                intervals = {},
                afterHooks = {},
            },
        }
        retainedState.tableRegistries[owner] = registry
    end
    if registry then
        ensureRegistryShape(registry, owner, false)
    end
    return registry
end

local function unregisterElement(slot)
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

local function createLineSlot(registry, name, spec, existingValues)
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
    slot.handle = renderer.createStackRow({
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

local function createTableSlot(registry, name, spec, existingRows, existingRowIndexByKey)
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

        slot.handles[rowIndex] = renderer.createStackRow({
            id = retainedRowId(registry, name, rowIndex),
            componentName = spec.componentName and (spec.componentName .. "_" .. tostring(rowIndex)) or nil,
            region = spec.region,
            order = (tonumber(spec.order) or public.overlays.order.module) + rowIndex - 1,
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

local function snapshotSlot(slot)
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

local function snapshotRegistry(registry)
    local elements = {}
    for name, slot in pairs(registry.elements) do
        elements[name] = snapshotSlot(slot)
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

local function restoreRegistry(registry, snapshot)
    for _, slot in pairs(registry.elements) do
        unregisterElement(slot)
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
            local slot = createLineSlot(registry, name, slotSnapshot.spec, slotSnapshot.values)
            slot.generation = slotSnapshot.generation
            registry.elements[name] = slot
        elseif slotSnapshot.kind == "table" then
            local slot = createTableSlot(
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

local function createProjectionContext(registry)
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
        renderer.refreshStackRows(region)
    end

    function ctx.refreshAll()
        renderer.refreshStackRows()
        renderer.refreshTextElements(true)
    end

    return ctx
end

local function ensureIntervalDriver()
    if retainedState.intervalDriverRegistered then
        return
    end
    retainedState.intervalDriverRegistered = true
    if rom and rom.gui and type(rom.gui.add_always_draw_imgui) == "function" then
        rom.gui.add_always_draw_imgui(function()
            internal.overlays.dispatchIntervals(os.clock())
        end)
    end
end

local function declareLine(registry, name, spec)
    validateName("createLine", name)
    validateSpec("createLine", spec)
    registry.seenElements[name] = true

    local previous = registry.elements[name]
    local previousValues = previous and previous.kind == "line" and previous.values or nil
    if previous then
        unregisterElement(previous)
    end

    registry.elements[name] = createLineSlot(registry, name, spec, previousValues)
end

local function declareTable(registry, name, spec)
    validateName("createTable", name)
    validateSpec("createTable", spec)
    if type(spec.columns) ~= "table" or #spec.columns == 0 then
        internal.violate(
            "overlays.invalid_registration",
            "lib.overlays.createTable: columns must be a non-empty array"
        )
    end
    local maxRows = tonumber(spec.maxRows)
    if not maxRows or maxRows < 1 or math.floor(maxRows) ~= maxRows then
        internal.violate(
            "overlays.invalid_registration",
            "lib.overlays.createTable: maxRows must be a positive integer"
        )
    end
    registry.seenElements[name] = true

    local previous = registry.elements[name]
    local previousRows = previous and previous.kind == "table" and previous.rows or nil
    local previousRowIndexByKey = previous and previous.kind == "table" and previous.rowIndexByKey or nil
    if previous then
        unregisterElement(previous)
    end

    registry.elements[name] = createTableSlot(
        registry,
        name,
        spec,
        previousRows,
        previousRowIndexByKey
    )
end

local function registerCommitProjection(registry, callback)
    if type(callback) ~= "function" then
        internal.violate("overlays.invalid_registration", "lib.overlays.onCommit: callback must be a function")
    end
    registry.pendingEvents.commit[#registry.pendingEvents.commit + 1] = callback
end

local function registerIntervalProjection(registry, name, seconds, callback, opts)
    validateName("onInterval", name)
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
end

local function registerAfterHookProjection(registry, path, callback)
    validateName("afterHook", path)
    if type(callback) ~= "function" then
        internal.violate("overlays.invalid_registration", "lib.overlays.afterHook: callback must be a function")
    end
    registry.pendingEvents.afterHooks[path] = {
        path = path,
        callback = callback,
    }
    public.hooks.WrapOwned(registry.hookOwner, path, "overlay.after:" .. path, function(base, ...)
        local args = { ... }
        local results = { base(...) }
        internal.overlays.dispatchAfterHook(registry.owner, path, args, results)
        return table.unpack(results)
    end)
end

local function createDeclarationSurface(registry)
    return {
        createLine = function(name, spec)
            return declareLine(registry, name, spec)
        end,
        createTable = function(name, spec)
            return declareTable(registry, name, spec)
        end,
        onCommit = function(callback)
            return registerCommitProjection(registry, callback)
        end,
        onInterval = function(name, seconds, callback, opts)
            return registerIntervalProjection(registry, name, seconds, callback, opts)
        end,
        afterHook = function(path, callback)
            return registerAfterHookProjection(registry, path, callback)
        end,
    }
end

local function beginTransaction(owner)
    local registry = getRegistry(owner, true)
    local snapshot = snapshotRegistry(registry)
    local hookTransaction = internal.hooks.beginTransaction(registry.hookOwner)
    local closed = false

    return {
        commit = function()
            hookTransaction.commit()
            closed = true
        end,
        rollback = function()
            if closed then
                return
            end
            hookTransaction.rollback()
            restoreRegistry(registry, snapshot)
            closed = true
        end,
    }
end

local function refresh(owner, ownerId, authorHost, store, register)
    if type(register) ~= "function" then
        internal.violate("overlays.invalid_registration", "internal.overlays.refresh: register must be a function")
    end

    local registry = getRegistry(owner, true)
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

    local ok, err = pcall(function()
        internal.hooks.refresh(registry.hookOwner, function()
            return register(createDeclarationSurface(registry))
        end)
    end)
    registry.refreshing = false

    if ok then
        for name, slot in pairs(registry.elements) do
            if not registry.seenElements[name] then
                unregisterElement(slot)
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

local function dispatchCommit(owner, commit)
    local registry = getRegistry(owner, false)
    if not registry then
        return
    end

    local ctx = createProjectionContext(registry)
    for _, callback in ipairs(registry.events.commit or {}) do
        callback(ctx, commit)
    end
end

local function dispatchIntervals(now)
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
                ctx = ctx or createProjectionContext(registry)
                event.callback(ctx, {
                    name = event.name,
                    now = now,
                })
            end
        end
    end

    for _, registry in pairs(retainedState.explicitRegistries) do
        dispatchRegistry(registry)
    end
    for _, registry in pairs(retainedState.tableRegistries) do
        if registry.explicitOwner ~= true then
            dispatchRegistry(registry)
        end
    end
end

local function dispatchAfterHook(owner, path, args, results)
    local registry = getRegistry(owner, false)
    local event = registry and registry.events.afterHooks and registry.events.afterHooks[path] or nil
    if not event then
        return
    end

    local ctx = createProjectionContext(registry)
    event.callback(ctx, {
        path = path,
        args = args or {},
        result = results and results[1] or nil,
        results = results or {},
    })
end

return {
    beginTransaction = beginTransaction,
    refresh = refresh,
    dispatchCommit = dispatchCommit,
    dispatchIntervals = dispatchIntervals,
    dispatchAfterHook = dispatchAfterHook,
}
