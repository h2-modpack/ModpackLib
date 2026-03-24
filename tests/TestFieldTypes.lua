local lu = require('luaunit')

-- =============================================================================
-- CHECKBOX
-- =============================================================================

TestCheckbox = {}

function TestCheckbox:testToHashTrue()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(lib.FieldTypes.checkbox.toHash(field, true), "1")
end

function TestCheckbox:testToHashFalse()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(lib.FieldTypes.checkbox.toHash(field, false), "0")
end

function TestCheckbox:testFromHashOne()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(lib.FieldTypes.checkbox.fromHash(field, "1"), true)
end

function TestCheckbox:testFromHashZero()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(lib.FieldTypes.checkbox.fromHash(field, "0"), false)
end

function TestCheckbox:testToStagingTrue()
    lu.assertEquals(lib.FieldTypes.checkbox.toStaging(true), true)
end

function TestCheckbox:testToStagingFalse()
    lu.assertEquals(lib.FieldTypes.checkbox.toStaging(false), false)
end

function TestCheckbox:testToStagingNil()
    lu.assertEquals(lib.FieldTypes.checkbox.toStaging(nil), false)
end

-- =============================================================================
-- DROPDOWN
-- =============================================================================

TestDropdown = {}

local dropdownField = {
    type = "dropdown",
    configKey = "Mode",
    values = { "Vanilla", "Always", "Never" },
    default = "Vanilla",
}

function TestDropdown:testToHash()
    lu.assertEquals(lib.FieldTypes.dropdown.toHash(dropdownField, "Always"), "Always")
end

function TestDropdown:testFromHash()
    lu.assertEquals(lib.FieldTypes.dropdown.fromHash(dropdownField, "Always"), "Always")
end

function TestDropdown:testRoundTrip()
    for _, v in ipairs(dropdownField.values) do
        lu.assertEquals(lib.FieldTypes.dropdown.fromHash(dropdownField,
            lib.FieldTypes.dropdown.toHash(dropdownField, v)), v)
    end
end

function TestDropdown:testToStaging()
    lu.assertEquals(lib.FieldTypes.dropdown.toStaging("Always"), "Always")
end

function TestDropdown:testFromHashUnknownValueFallsBackToDefault()
    lu.assertEquals(lib.FieldTypes.dropdown.fromHash(dropdownField, "OldRemovedValue"), "Vanilla")
end

function TestDropdown:testValidateWarnsPipeInValue()
    local warned = false
    local field = { type = "dropdown", configKey = "X", values = { "Good", "Bad|Value" } }
    local origWarn = lib.warn
    lib.warn = function() warned = true end
    lib.FieldTypes.dropdown.validate(field, "test")
    lib.warn = origWarn --luacheck: ignore
    lu.assertTrue(warned)
end

-- =============================================================================
-- RADIO
-- =============================================================================

TestRadio = {}

local radioField = {
    type = "radio",
    configKey = "Speed",
    values = { "Slow", "Normal", "Fast" },
    default = "Normal",
}

function TestRadio:testToHash()
    lu.assertEquals(lib.FieldTypes.radio.toHash(radioField, "Fast"), "Fast")
end

function TestRadio:testFromHash()
    lu.assertEquals(lib.FieldTypes.radio.fromHash(radioField, "Fast"), "Fast")
end

function TestRadio:testRoundTrip()
    for _, v in ipairs(radioField.values) do
        lu.assertEquals(lib.FieldTypes.radio.fromHash(radioField,
            lib.FieldTypes.radio.toHash(radioField, v)), v)
    end
end

function TestRadio:testFromHashUnknownValueFallsBackToDefault()
    lu.assertEquals(lib.FieldTypes.radio.fromHash(radioField, "OldRemovedValue"), "Normal")
end

function TestRadio:testValidateWarnsPipeInValue()
    local warned = false
    local field = { type = "radio", configKey = "X", values = { "Good", "Bad|Value" } }
    local origWarn = lib.warn
    lib.warn = function() warned = true end
    lib.FieldTypes.radio.validate(field, "test")
    lib.warn = origWarn --luacheck: ignore
    lu.assertTrue(warned)
end
