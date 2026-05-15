local lu = require('luaunit')

TestDefinitionContract = {}

function TestDefinitionContract:setUp()
    CaptureWarnings()
end

function TestDefinitionContract:tearDown()
    RestoreWarnings()
end

function TestDefinitionContract:testCreateStoreErrorsOnUnknownTopLevelDefinitionKey()
    lu.assertErrorMsgContains("unknown definition key 'ui'", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "Example",
            name = "Example",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            ui = {},
        })
    end)
end

function TestDefinitionContract:testValidateDefinitionErrorsOnOldVocabularyKeysAsUnknown()
    lu.assertErrorMsgContains("unknown definition key 'category'", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            modpack = "test-pack",
            id = "ExampleSpecial",
            name = "Example Special",
            category = "Run Mods",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
        })
    end)
end

function TestDefinitionContract:testPrepareDefinitionRejectsBehaviorFieldsAsUnknownKeys()
    lu.assertErrorMsgContains("unknown definition key 'affectsRunData'", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "Example",
            name = "Example",
            affectsRunData = true,
        })
    end)

    lu.assertErrorMsgContains("unknown definition key 'apply'", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "Example",
            name = "Example",
            apply = function() end,
        })
    end)
end

