local internal = AdamantModpackLib_Internal
local libConfig = internal.libConfig

local AllowedViolationSeverity = {
    error = true,
    warn = true,
    debug = true,
    ignore = true,
}

local DefaultViolationPolicy = {
    ["coordinator.invalid_registration"] = {
        severity = "error",
        description = "Coordinator registration requires a stable pack id and config table.",
    },
    ["coordinator.invalid_rebuild_callback"] = {
        severity = "error",
        description = "Coordinator rebuild callbacks must be callable so structural reloads can be delegated.",
    },

    ["definition.incomplete_manual_lifecycle"] = {
        severity = "error",
        description = "Manual lifecycle definitions must provide apply and revert as a pair.",
    },
    ["definition.invalid_field_type"] = {
        severity = "debug",
        description = "Definition metadata fields should use the expected public contract types.",
    },
    ["definition.invalid_args"] = {
        severity = "error",
        description = "Definition preparation requires valid owner and definition arguments.",
    },
    ["definition.missing_coordinated_id"] = {
        severity = "debug",
        description = "Coordinated modules should declare an id for discovery and hash/profile identity.",
    },
    ["definition.missing_mutation"] = {
        severity = "error",
        description = "Definitions that affect run data must declare a patch plan or manual lifecycle.",
    },
    ["definition.structural_reload_required"] = {
        severity = "warn",
        description = "An uncoordinated structural hot reload cannot be reconciled without a full reload.",
    },
    ["definition.unknown_key"] = {
        severity = "debug",
        description = "Unknown definition keys are ignored by Lib and may indicate stale author code.",
    },
    ["definition.reserved_storage_alias"] = {
        severity = "error",
        description = "Built-in storage aliases are owned by Lib and cannot be declared by modules.",
    },

    ["game_object.invalid_args"] = {
        severity = "error",
        description = "Game-object state access requires object, pack id, module id, and key arguments.",
    },
    ["game_object.invalid_bucket"] = {
        severity = "error",
        description = "Game-object state buckets must remain tables owned by Lib.",
    },
    ["game_object.invalid_factory"] = {
        severity = "error",
        description = "Game-object state factories must be functions that return tables.",
    },

    ["host.invalid_create_opts"] = {
        severity = "error",
        description = "Module hosts require prepared definitions, store/session handles, drawTab, and pluginGuid.",
    },
    ["host.invalid_standalone_binding"] = {
        severity = "error",
        description = "Standalone hosting requires a plugin guid with a registered live module host.",
    },
    ["host.coordinated_runtime_sync_failed"] = {
        severity = "warn",
        description = "A coordinated module failed its runtime on-load reconciliation.",
    },
    ["host.enable_transition_failed"] = {
        severity = "warn",
        description = "A module enable/disable transition failed and the UI state may need resync.",
    },
    ["host.session_commit_failed"] = {
        severity = "warn",
        description = "A UI session commit failed and Lib attempted to restore the previous config state.",
    },
    ["host.standalone_startup_lifecycle_failed"] = {
        severity = "warn",
        description = "Standalone startup lifecycle failed while applying module behavior.",
    },
    ["host.structural_rebuild_unavailable"] = {
        severity = "error",
        description = "A coordinated structural reload was detected but no rebuild callback accepted it.",
    },

    ["hooks.invalid_registration"] = {
        severity = "error",
        description = "Hook registration requires valid owners, paths, and callback functions.",
    },
    ["hooks.inactive_override"] = {
        severity = "error",
        description = "Inactive hook replacements should not be invoked after refresh invalidation.",
    },
    ["hooks.modutil_unavailable"] = {
        severity = "error",
        description = "Hook registration requires SGG_Modding-ModUtil to be available.",
    },

    ["integrations.invalid_args"] = {
        severity = "error",
        description = "Integration registry calls require non-empty ids and valid provider APIs.",
    },
    ["integrations.provider_failed"] = {
        severity = "warn",
        description = "An integration provider method failed; Lib returned the caller fallback.",
    },

    ["lifecycle.on_settings_committed_failed"] = {
        severity = "warn",
        description = "A module onSettingsCommitted callback raised an error.",
    },
    ["lifecycle.on_settings_committed_false"] = {
        severity = "warn",
        description = "A module onSettingsCommitted callback returned false.",
    },
    ["lifecycle.session_drift_detected"] = {
        severity = "warn",
        description = "Staged UI state drifted from persisted config and was reloaded.",
    },
    ["lifecycle.session_rollback_reapply_failed"] = {
        severity = "warn",
        description = "A session rollback could not fully reapply the previous mutation state.",
    },

    ["overlays.invalid_registration"] = {
        severity = "error",
        description = "Overlay registration requires valid ids, draw functions, and column descriptors.",
    },

    ["session.unknown_reset_alias"] = {
        severity = "error",
        description = "Session reset only accepts declared staged storage aliases.",
    },
    ["session.unknown_read_alias"] = {
        severity = "error",
        description = "Session reads only accept declared staged storage aliases.",
    },
    ["session.unknown_table_alias"] = {
        severity = "error",
        description = "Session table access only accepts declared table storage aliases.",
    },
    ["session.unknown_write_alias"] = {
        severity = "error",
        description = "Session writes only accept declared staged storage aliases.",
    },
    ["session.invalid_table_alias"] = {
        severity = "error",
        description = "Session table access requires a table root alias, not scalar or packed-bit aliases.",
    },
    ["session.invalid_table_surface"] = {
        severity = "error",
        description = "Session table access is only valid for staged table storage.",
    },
    ["session.invalid_read_surface"] = {
        severity = "error",
        description = "Session reads cannot access unstaged runtime-cache storage.",
    },
    ["session.invalid_write_surface"] = {
        severity = "error",
        description = "Session writes cannot mutate unstaged runtime-cache storage.",
    },
    ["session.readonly_view_write"] = {
        severity = "error",
        description = "Session view is read-only; writes must go through session.write.",
    },

    ["store.invalid_create_args"] = {
        severity = "error",
        description = "Store creation requires a prepared definition from lib.prepareDefinition.",
    },
    ["store.invalid_config"] = {
        severity = "error",
        description = "Store creation requires a module config table for persisted backing values.",
    },
    ["store.invalid_managed_store"] = {
        severity = "error",
        description = "Internal persisted writes require a Lib-managed store handle.",
    },
    ["store.invalid_read_surface"] = {
        severity = "error",
        description = "Store reads cannot access staged-only transient UI storage.",
    },
    ["store.invalid_table_alias"] = {
        severity = "error",
        description = "Store table access requires a table root alias, not scalar or packed-bit aliases.",
    },
    ["store.invalid_table_surface"] = {
        severity = "error",
        description = "Store table access cannot read staged-only transient table storage.",
    },
    ["store.invalid_write_surface"] = {
        severity = "error",
        description = "Persisted store writes cannot mutate staged-only transient UI storage.",
    },
    ["store.unknown_read_alias"] = {
        severity = "error",
        description = "Store reads only accept declared storage aliases.",
    },
    ["store.unknown_table_alias"] = {
        severity = "error",
        description = "Store table access only accepts declared table storage aliases.",
    },
    ["store.unknown_write_alias"] = {
        severity = "error",
        description = "Persisted store writes only accept declared storage aliases.",
    },
    ["store.invalid_unstaged_write"] = {
        severity = "error",
        description = "store.writeUnstaged only accepts root aliases declared with stage=false.",
    },

    ["storage.duplicate_alias"] = {
        severity = "error",
        description = "Storage aliases must be unique across roots and packed child aliases.",
    },
    ["storage.hash_requires_persist"] = {
        severity = "error",
        description = "Hash/profile storage must be persisted so values can round-trip.",
    },
    ["storage.hash_requires_stage"] = {
        severity = "error",
        description = "Hash/profile storage must be staged so UI/profile changes use the session path.",
    },
    ["storage.invalid_axis_type"] = {
        severity = "error",
        description = "Storage axis options and numeric bounds must use supported value types.",
    },
    ["storage.invalid_default"] = {
        severity = "error",
        description = "Storage defaults must match the declared storage type.",
    },
    ["storage.invalid_node"] = {
        severity = "error",
        description = "Storage schema entries must be valid typed nodes with aliases.",
    },
    ["storage.invalid_packed_bit"] = {
        severity = "error",
        description = "Packed bit declarations must have valid aliases, offsets, widths, and types.",
    },
    ["storage.invalid_schema"] = {
        severity = "error",
        description = "Storage schemas must be valid arrays of storage nodes.",
    },
    ["storage.invalid_table_row"] = {
        severity = "error",
        description = "Table row schemas must be flat storage schemas owned by the table root.",
    },
    ["storage.missing_persisted_default"] = {
        severity = "error",
        description = "Persisted storage roots must declare effective defaults.",
    },
    ["storage.packed_requires_stage"] = {
        severity = "error",
        description = "PackedInt roots currently require staging so child aliases stay synchronized.",
    },
    ["storage.packed_child_default_mismatch"] = {
        severity = "debug",
        description = "Packed child defaults should match the encoded packedInt root default.",
    },
    ["storage.readonly_table_handle"] = {
        severity = "error",
        description = "Read-only table handles cannot perform row mutations.",
    },
}

local function FormatMessage(prefix, fmt, ...)
    return prefix .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

internal.formatLogMessage = FormatMessage
internal.violationPolicy = internal.violationPolicy or {}
internal.violationSeverity = internal.violationSeverity or {}

for id, entry in pairs(DefaultViolationPolicy) do
    assert(type(entry) == "table", "default violation policy entry must be a table: " .. tostring(id))
    assert(AllowedViolationSeverity[entry.severity], "default violation policy has invalid severity: " .. tostring(id))
    assert(type(entry.description) == "string" and entry.description ~= "",
        "default violation policy is missing a description: " .. tostring(id))
    if internal.violationPolicy[id] == nil then
        internal.violationPolicy[id] = entry
    end
    if internal.violationSeverity[id] == nil then
        internal.violationSeverity[id] = entry.severity
    end
end

function internal.violate(id, fmt, ...)
    assert(type(id) == "string" and id ~= "", "internal.violate: id must be a non-empty string")
    assert(type(fmt) == "string", "internal.violate: fmt must be a string")

    local severity = internal.violationSeverity[id]
    if severity == nil then
        error(FormatMessage("[lib] violation.unknown_id: ", "unknown violation id '%s'", id), 2)
    end
    if not AllowedViolationSeverity[severity] then
        error(FormatMessage("[lib] violation.invalid_severity: ", "%s is configured with invalid severity '%s'", id, tostring(severity)), 2)
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
