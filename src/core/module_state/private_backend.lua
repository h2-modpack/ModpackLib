local deps = ...

local chalk = deps.chalk
local backendState = deps.state

local function getConfigBackend(config)
    if not chalk then
        return nil
    end

    local ok, rawConfig = pcall(chalk.original, config)
    if not ok or type(rawConfig) ~= "table" or type(rawConfig.entries) ~= "table" then
        return nil
    end

    local backend = backendState.cache[rawConfig]
    if backend then
        return backend
    end

    local entryIndex = {}
    for descriptor, entry in pairs(rawConfig.entries) do
        local section = descriptor.section
        local key = descriptor.key
        if section ~= nil and key ~= nil then
            local sectionEntries = entryIndex[section]
            if not sectionEntries then
                sectionEntries = {}
                entryIndex[section] = sectionEntries
            end
            sectionEntries[key] = entry
        end
    end

    local pathEntryCache = {}
    backend = {}

    function backend.getEntry(alias)
        local cached = pathEntryCache[alias]
        if cached ~= nil then
            return cached or nil
        end

        local entry = entryIndex.config and entryIndex.config[alias] or nil
        if entry then
            pathEntryCache[alias] = entry
            return entry
        end

        pathEntryCache[alias] = false
        return nil
    end

    function backend.ensureValue(alias, value)
        local entry = backend.getEntry(alias)
        if entry then
            return true
        end

        if type(alias) ~= "string" or alias == "" or type(rawConfig.bind) ~= "function" then
            return false
        end

        entry = rawConfig:bind("config", alias, value, "")
        if not entry then
            return false
        end

        local sectionEntries = entryIndex.config
        if not sectionEntries then
            sectionEntries = {}
            entryIndex.config = sectionEntries
        end
        sectionEntries[alias] = entry
        pathEntryCache[alias] = entry

        if type(rawConfig.save) == "function" then
            rawConfig:save()
        end
        return true
    end

    function backend.readValue(alias)
        local entry = backend.getEntry(alias)
        if entry then
            return entry:get()
        end
        return nil
    end

    function backend.writeValue(alias, value)
        local entry = backend.getEntry(alias)
        if entry then
            entry:set(value)
            return true
        end
        return false
    end

    backend.rawConfig = rawConfig
    backendState.cache[rawConfig] = backend
    return backend
end

return {
    getConfigBackend = getConfigBackend,
}
