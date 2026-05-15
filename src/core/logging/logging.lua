local internal = AdamantModpackLib_Internal
local libConfig = internal.libConfig
local DefaultViolationPolicy = import 'core/logging/policies.lua'

local AllowedViolationSeverity = {
    error = true,
    warn = true,
    debug = true,
    ignore = true,
}

local function FormatMessage(prefix, fmt, ...)
    return prefix .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

internal.formatLogMessage = FormatMessage
internal.violationPolicy = internal.violationPolicy or {}
internal.violationSeverity = nil

for id, entry in pairs(DefaultViolationPolicy) do
    local current = internal.violationPolicy[id]
    if type(current) ~= "table" then
        internal.violationPolicy[id] = {
            severity = entry.severity,
            description = entry.description,
        }
    end
end

function internal.violate(id, fmt, ...)
    assert(type(id) == "string" and id ~= "", "internal.violate: id must be a non-empty string")
    assert(type(fmt) == "string", "internal.violate: fmt must be a string")

    local policy = internal.violationPolicy[id]
    if type(policy) ~= "table" then
        error(FormatMessage("[lib] violation.unknown_id: ", "unknown violation id '%s'", id), 2)
    end
    local severity = policy.severity
    if not AllowedViolationSeverity[severity] then
        error(FormatMessage("[lib] violation.invalid_severity: ",
            "%s is configured with invalid severity '%s'", id, tostring(severity)), 2)
    end

    local message = FormatMessage("[lib] " .. id .. ": ", fmt, ...)
    if severity == "error" then
        error(message, 2)
    elseif severity == "warn" then
        print(message)
    elseif severity == "debug" and libConfig.DebugMode then
        print(message)
    end

    return severity, message
end
