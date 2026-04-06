local lu = require('luaunit')

local function assertWarningContains(fragment)
    for _, warning in ipairs(Warnings) do
        if string.find(warning, fragment, 1, true) then
            return
        end
    end
    lu.fail("expected warning containing '" .. fragment .. "'")
end

TestStorageValidation = {}

function TestStorageValidation:setUp()
    CaptureWarnings()
end

function TestStorageValidation:tearDown()
    RestoreWarnings()
end

function TestStorageValidation:testDuplicateAliasWarns()
    lib.validateStorage({
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
        { type = "bool", alias = "Enabled", configKey = "OtherEnabled", default = false },
    }, "DupAlias")

    assertWarningContains("duplicate alias 'Enabled'")
end

function TestStorageValidation:testDuplicateConfigKeyWarns()
    lib.validateStorage({
        { type = "bool", alias = "EnabledA", configKey = "Enabled", default = false },
        { type = "bool", alias = "EnabledB", configKey = "Enabled", default = false },
    }, "DupKey")

    assertWarningContains("duplicate configKey 'Enabled'")
end

function TestStorageValidation:testRootAliasDefaultsToConfigKey()
    local storage = {
        { type = "bool", configKey = "Enabled", default = false },
    }

    lib.validateStorage(storage, "AliasDefault")

    local aliases = lib.getStorageAliases(storage)
    lu.assertNotNil(aliases.Enabled)
    lu.assertEquals(aliases.Enabled.configKey, "Enabled")
end

function TestStorageValidation:testPackedOverlapWarns()
    lib.validateStorage({
        {
            type = "packedInt",
            alias = "Packed",
            configKey = "Packed",
            bits = {
                { alias = "FlagA", offset = 0, width = 2, type = "int", default = 0 },
                { alias = "FlagB", offset = 1, width = 2, type = "int", default = 0 },
            },
        },
    }, "Overlap")

    assertWarningContains("packed bit overlaps bit 1")
end

function TestStorageValidation:testPackedAliasMatchingExistingRootAliasWarns()
    lib.validateStorage({
        { type = "bool", alias = "Mode", configKey = "Mode", default = false },
        {
            type = "packedInt",
            alias = "Packed",
            configKey = "Packed",
            bits = {
                { alias = "Mode", offset = 0, width = 1, type = "bool", default = true },
            },
        },
    }, "Conflict")

    assertWarningContains("duplicate alias 'Mode'")
end

TestUiValidation = {}

function TestUiValidation:setUp()
    CaptureWarnings()
end

function TestUiValidation:tearDown()
    RestoreWarnings()
end

function TestUiValidation:testWidgetStorageTypeMismatchWarns()
    local storage = {
        { type = "int", alias = "Count", configKey = "Count", default = 2, min = 1, max = 5 },
    }
    lib.validateStorage(storage, "WidgetType")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Count" }, label = "Count" },
    }, "WidgetType", storage)

    assertWarningContains("bound alias 'Count' is int, expected bool")
end

function TestUiValidation:testVisibleIfRequiresBoolAlias()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIf")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = "Mode" },
    }, "VisibleIf", storage)

    assertWarningContains("visibleIf alias 'Mode' must resolve to bool storage")
end

function TestUiValidation:testUnknownVisibleIfAliasWarns()
    local storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIfMissing")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = "MissingGate" },
    }, "VisibleIfMissing", storage)

    assertWarningContains("visibleIf alias 'MissingGate' does not exist")
end

function TestUiValidation:testVisibleIfValueSupportsNonBoolAliases()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIfValue")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", value = "Forced" } },
    }, "VisibleIfValue", storage)

    lu.assertEquals(#Warnings, 0)
end

function TestUiValidation:testVisibleIfAnyOfRequiresNonEmptyList()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIfAnyOf")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", anyOf = {} } },
    }, "VisibleIfAnyOf", storage)

    assertWarningContains("visibleIf.anyOf must be a non-empty list")
end

function TestUiValidation:testVisibleIfRejectsValueAndAnyOfTogether()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIfConflict")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", value = "Forced", anyOf = { "Forced" } } },
    }, "VisibleIfConflict", storage)

    assertWarningContains("visibleIf cannot specify both value and anyOf")
end

function TestUiValidation:testLayoutChildrenValidateRecursively()
    local storage = {
        { type = "bool", alias = "Gate", configKey = "Gate", default = true },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
    }
    lib.validateStorage(storage, "Layout")

    lib.validateUi({
        {
            type = "group",
            label = "Outer",
            children = {
                { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = "Gate" },
            },
        },
    }, "Layout", storage)

    lu.assertEquals(#Warnings, 0)
end

function TestUiValidation:testPrepareUiNodeValidatesAgainstRawStorage()
    local storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
    }
    local node = { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" }

    lib.prepareUiNode(node, "PrepareRaw", storage)

    lu.assertEquals(#Warnings, 0)
    local aliases = lib.getStorageAliases(storage)
    lu.assertNotNil(aliases.Enabled)
end

function TestUiValidation:testPrepareUiNodeWarnsUnknownAliasAgainstRawStorage()
    local storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
    }
    local node = { type = "checkbox", binds = { value = "Missing" }, label = "Enabled" }

    lib.prepareUiNode(node, "PrepareRawMissing", storage)

    assertWarningContains("binds.value unknown alias 'Missing'")
end

function TestUiValidation:testValidateUiAcceptsRawStorage()
    local storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
    }

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
    }, "ValidateRaw", storage)

    lu.assertEquals(#Warnings, 0)
end
