local lu = require('luaunit')

TestNav = {}

local function makeSession(values)
    return {
        read = function(alias)
            return values[alias]
        end,
    }
end

function TestNav:testVisibilityConditions()
    local session = makeSession({
        Enabled = true,
        Region = "Surface",
        Count = 2,
    })

    lu.assertTrue(lib.nav.isVisible(session, nil))
    lu.assertTrue(lib.nav.isVisible(session, "Enabled"))
    lu.assertFalse(lib.nav.isVisible(session, "Missing"))
    lu.assertTrue(lib.nav.isVisible(session, { alias = "Region", value = "Surface" }))
    lu.assertFalse(lib.nav.isVisible(session, { alias = "Region", value = "Underworld" }))
    lu.assertTrue(lib.nav.isVisible(session, { alias = "Count", anyOf = { 1, 2, 3 } }))
    lu.assertFalse(lib.nav.isVisible(session, { alias = "Count", anyOf = { 4, 5 } }))
    lu.assertFalse(lib.nav.isVisible(session, { alias = "" }))
    lu.assertFalse(lib.nav.isVisible(session, { alias = "Count", anyOf = "bad" }))
    lu.assertTrue(lib.nav.isVisible(session, 42))
end

function TestNav:testVerticalTabsReturnsSelectedKeyAndDrawsGroupsAndColors()
    local calls = {
        beginChild = 0,
        endChild = 0,
        sameLine = 0,
        separators = 0,
        groups = {},
        selectedLabels = {},
        pushColors = 0,
        popColors = 0,
    }
    local imgui = {
        ImGuiCol = { Text = 5 },
        BeginChild = function(id, width, height, border)
            calls.beginChild = calls.beginChild + 1
            calls.child = { id = id, width = width, height = height, border = border }
        end,
        EndChild = function()
            calls.endChild = calls.endChild + 1
        end,
        SameLine = function()
            calls.sameLine = calls.sameLine + 1
        end,
        Separator = function()
            calls.separators = calls.separators + 1
        end,
        TextDisabled = function(label)
            table.insert(calls.groups, label)
        end,
        PushStyleColor = function(...)
            calls.pushColors = calls.pushColors + 1
            calls.colorArgs = { ... }
        end,
        PopStyleColor = function()
            calls.popColors = calls.popColors + 1
        end,
        Selectable = function(label, selected)
            table.insert(calls.selectedLabels, { label = label, selected = selected })
            return label == "Second##two"
        end,
    }

    local selected = lib.nav.verticalTabs(imgui, {
        id = "modules",
        navWidth = 200,
        height = 300,
        activeKey = "one",
        tabs = {
            { key = "one", label = "First", group = "Group A" },
            { key = "two", label = "Second", group = "Group A", color = { 1, 0, 0, 1 } },
            { key = "three", label = "Third", group = "Group B" },
        },
    })

    lu.assertEquals(selected, "two")
    lu.assertEquals(calls.child, { id = "modules##nav", width = 200, height = 300, border = true })
    lu.assertEquals(calls.beginChild, 1)
    lu.assertEquals(calls.endChild, 1)
    lu.assertEquals(calls.sameLine, 1)
    lu.assertEquals(calls.groups, { "Group A", "Group B" })
    lu.assertEquals(calls.separators, 3)
    lu.assertEquals(calls.selectedLabels[1], { label = "First##one", selected = true })
    lu.assertEquals(calls.pushColors, 1)
    lu.assertEquals(calls.popColors, 1)
    lu.assertEquals(calls.colorArgs, { 5, 1, 0, 0, 1 })
end
