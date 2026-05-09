local lu = require('luaunit')

TestCreateModule = {}

function TestCreateModule:setUp()
    CaptureWarnings()
end

function TestCreateModule:tearDown()
    RestoreWarnings()
end

function TestCreateModule:testCreateModuleRunsCanonicalPipeline()
    local owner = {}
    local callbackHost = nil
    local drawHost = nil
    local authorSchemaNode = nil
    local config = {}

    local host, store = lib.createModule({
        owner = owner,
        pluginGuid = "test-create-module",
        config = config,
        definition = {
            modpack = "create-module-pack",
            id = "CreateModule",
            name = "Create Module",
            storage = {
                { type = "bool", alias = "Flag", default = false },
            },
        },
        registerIntegrations = function(authorHost)
            callbackHost = authorHost
        end,
        drawTab = function(_, authorSession, authorHost)
            drawHost = authorHost
            authorSchemaNode = authorSession.getAliasSchema("Flag")
            authorSession.write("Flag", true)
        end,
    })

    local liveHost = lib.getLiveModuleHost("test-create-module")
    liveHost.drawTab({})

    lu.assertEquals(host, callbackHost)
    lu.assertEquals(host, drawHost)
    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(store.read("Flag"), false)
    liveHost.flush()
    lu.assertEquals(store.read("Flag"), true)
    lu.assertNotNil(authorSchemaNode)
    lu.assertEquals(authorSchemaNode.alias, "Flag")
    lu.assertEquals(authorSchemaNode.type, "bool")
    lu.assertEquals(type(owner._definitionStructuralFingerprint), "string")
end

function TestCreateModule:testCreateModuleReturnsOnlyAuthorHostSurface()
    local host = lib.createModule({
        owner = {},
        pluginGuid = "test-create-module-author-surface",
        config = {},
        definition = {
            modpack = "create-module-pack",
            id = "AuthorSurface",
            name = "Author Surface",
        },
        drawTab = function() end,
    })

    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(type(host.getIdentity), "function")
    lu.assertEquals(type(host.getMeta), "function")
    lu.assertNil(host.read)
    lu.assertNil(host.writeAndFlush)
    lu.assertNil(host.commitIfDirty)
    lu.assertNil(host.applyMutation)
    lu.assertNil(host.setEnabled)
end

function TestCreateModule:testCreateModuleRequiresOwner()
    lu.assertErrorMsgContains("owner is required", function()
        lib.createModule({
            pluginGuid = "test-create-module-hooks-no-owner",
            config = {},
            definition = {
                id = "HooksNoOwner",
                name = "Hooks No Owner",
            },
            drawTab = function() end,
        })
    end)
end
