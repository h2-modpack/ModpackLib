-- =============================================================================
-- ADAMANT-LIB: Shared utilities for adamant standalone mods
-- =============================================================================
-- Access via: local lib = rom.mods['adamant-Modpack_Lib']
--
-- Provides:
--   backup, restore = lib.createBackupSystem()
--   local cb = lib.standaloneUI(def, config, apply, restore)  -- returns callback
--   rom.gui.add_to_menu_bar(cb)  -- caller registers in own plugin context
--   staging, snapshot, sync = lib.createSpecialState(config, schema)
--   lib.isEnabled(modConfig) — true if module AND master toggle are both on

local mods = rom.mods
envy = mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

--- Check if a module should be active.
--- Returns true only if the module's own Enabled flag is true AND
--- the master toggle (ModEnabled) is true when Core is installed.
--- When Core is not installed, only the module's own flag is checked.
--- @param modConfig table  The module's chalk config (needs .Enabled)
--- @return boolean
function public.isEnabled(modConfig)
    local core = mods['adamant-Modpack_Core']
    if core and not core.config.ModEnabled then return false end
    return modConfig.Enabled == true
end

--- Create an isolated backup/restore pair.
--- Each mod gets its own state — no collision between mods.
--- backup() accepts variadic keys: backup(tbl, "k1", "k2", ...)
--- @return function backup
--- @return function restore
function public.createBackupSystem()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for _, key in ipairs({...}) do
            if saved[key] == nil then
                local v = tbl[key]
                saved[key] = (v == nil) and NIL or (type(v) == "table" and rom.game.DeepCopyTable(v) or v)
            end
        end
    end

    local function restore()
        for tbl, keys in pairs(savedValues) do
            for key, v in pairs(keys) do
                if v == NIL then
                    tbl[key] = nil
                elseif type(v) == "table" then
                    tbl[key] = rom.game.DeepCopyTable(v)
                else
                    tbl[key] = v
                end
            end
        end
    end

    return backup, restore
end

--- Build a menu-bar callback for a boolean mod.
--- Returns a function — the caller must register it via rom.gui.add_to_menu_bar().
--- Skips rendering when adamant-Modpack_Core is installed.
--- @param def table         public.definition (needs .name, .tooltip, .dataMutation)
--- @param modConfig table   the mod's chalk config (needs .Enabled)
--- @param apply function    called on enable
--- @param restoreFn function called on disable
--- @return function callback
function public.standaloneUI(def, modConfig, apply, restoreFn)
    return function()
        if mods['adamant-Modpack_Core'] then return end
        if rom.ImGui.BeginMenu("adamant") then
            local val, chg = rom.ImGui.Checkbox(def.name, modConfig.Enabled)
            if chg then
                modConfig.Enabled = val
                if val then apply() else restoreFn() end
                if def.dataMutation then rom.game.SetupRunData() end
            end
            if rom.ImGui.IsItemHovered() and (def.tooltip or "") ~= "" then
                rom.ImGui.SetTooltip(def.tooltip)
            end
            rom.ImGui.EndMenu()
        end
    end
end

-- =============================================================================
-- HELPERS
-- =============================================================================

--- Calculate the minimum number of bits needed to represent `n` values.
--- @param n number  The number of distinct values
--- @return number bits
local function bitsRequired(n)
    if n <= 1 then return 1 end
    return math.ceil(math.log(n) / math.log(2))
end
public.bitsRequired = bitsRequired

--- Resolve the `bits` field on a schema entry.
--- If `bits` is provided, use it. Otherwise auto-calculate from the values/type.
--- @param field table  A schema field descriptor
--- @return number bits
local function resolveBits(field)
    if field.bits then return field.bits end
    if field.type == "checkbox" then return 1 end
    if (field.type == "dropdown" or field.type == "radio") then
        if field.values then
            return bitsRequired(#field.values)
        end
        -- No values list — can't auto-calculate, fall back to 1.
        -- Core.warn will catch this at encode time when DebugMode is on.
        return 1
    end
    return 1
end
public.resolveBits = resolveBits

-- =============================================================================
-- SPECIAL MODULE STATE
-- =============================================================================
-- Staging system for special modules. Provides a plain Lua table mirroring
-- the Chalk config for fast UI reads/writes.
--
-- Schema is an ordered list of field descriptors. Supported types:
--
--   "checkbox" — single boolean toggle
--     { type="checkbox", configKey="X", default=false }
--
--   "dropdown" — pick one from a list (combo box)
--     { type="dropdown", configKey="X", values={...}, default="" }
--
--   "radio"    — pick one from a list (radio buttons)
--     { type="radio", configKey="X", values={...}, default="" }
--
-- configKey can be a string ("Mode") or a table path ({"FirstHammers", "BaseStaffAspect"})
-- for nested config access.
--
-- Hashing is handled by Core via definition.stateSchema — modules don't encode/decode.
--
-- Returns: staging, snapshot, sync
--
--- @param modConfig table  The module's chalk config
--- @param schema table     Ordered list of field descriptors
--- @return table staging       Plain table mirroring config (fast reads/writes for UI)
--- @return function snapshot   Re-read config into staging (after profile load)
--- @return function sync       Flush staging to config (after UI edits)
function public.createSpecialState(modConfig, schema)
    local staging = {}

    -- -----------------------------------------------------------------
    -- Helpers: nested configKey access
    -- -----------------------------------------------------------------

    --- Read a value from config using a configKey (string or table path).
    local function readConfig(key)
        if type(key) == "table" then
            local tbl = modConfig
            for i = 1, #key - 1 do tbl = tbl[key[i]] end
            return tbl[key[#key]]
        end
        return modConfig[key]
    end

    --- Write a value to config using a configKey (string or table path).
    local function writeConfig(key, value)
        if type(key) == "table" then
            local tbl = modConfig
            for i = 1, #key - 1 do tbl = tbl[key[i]] end
            tbl[key[#key]] = value
            return
        end
        modConfig[key] = value
    end

    --- Read from staging using a configKey. Nested keys use nested tables
    --- so UI code can naturally access staging.FirstHammers[aspectKey].
    local function readStaging(key)
        if type(key) == "table" then
            local tbl = staging
            for i = 1, #key - 1 do
                if not tbl[key[i]] then return nil end
                tbl = tbl[key[i]]
            end
            return tbl[key[#key]]
        end
        return staging[key]
    end

    --- Write to staging using a configKey. Creates nested tables as needed.
    local function writeStaging(key, value)
        if type(key) == "table" then
            local tbl = staging
            for i = 1, #key - 1 do
                tbl[key[i]] = tbl[key[i]] or {}
                tbl = tbl[key[i]]
            end
            tbl[key[#key]] = value
            return
        end
        staging[key] = value
    end

    -- -----------------------------------------------------------------
    -- Copy helpers
    -- -----------------------------------------------------------------

    local function copyConfigToStaging()
        for _, field in ipairs(schema) do
            local val = readConfig(field.configKey)
            if field.type == "checkbox" then
                writeStaging(field.configKey, val == true)
            elseif field.type == "dropdown" or field.type == "radio" then
                writeStaging(field.configKey, val)
            end
        end
    end

    local function copyStagingToConfig()
        for _, field in ipairs(schema) do
            writeConfig(field.configKey, readStaging(field.configKey))
        end
    end

    -- -----------------------------------------------------------------
    -- Initialize staging from current config
    -- -----------------------------------------------------------------
    copyConfigToStaging()

    -- -----------------------------------------------------------------
    -- Public functions
    -- -----------------------------------------------------------------

    local function snapshot()
        copyConfigToStaging()
    end

    local function sync()
        copyStagingToConfig()
    end

    return staging, snapshot, sync
end
