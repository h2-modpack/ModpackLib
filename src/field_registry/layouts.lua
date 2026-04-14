local internal = AdamantModpackLib_Internal
local shared = internal.shared
local LayoutTypes = shared.LayoutTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry
local GetCursorPosXSafe = registry.GetCursorPosXSafe
local GetCursorPosYSafe = registry.GetCursorPosYSafe
local GetStyleMetricX = registry.GetStyleMetricX
local GetStyleMetricY = registry.GetStyleMetricY
local NormalizeColor = registry.NormalizeColor
local EstimateStructuredRowAdvanceY = registry.EstimateStructuredRowAdvanceY
local DrawStructuredAt = registry.DrawStructuredAt

local function ValidateChildren(node, prefix, layoutName)
    if node.children ~= nil and type(node.children) ~= "table" then
        libWarn("%s: %s children must be a table", prefix, layoutName)
    end
end

local function ValidateLayoutId(node, prefix, layoutName, required)
    if node.id == nil then
        if required then
            libWarn("%s: %s id must be a non-empty string", prefix, layoutName)
        end
        return
    end
    if type(node.id) ~= "string" or node.id == "" then
        libWarn("%s: %s id must be a non-empty string", prefix, layoutName)
    end
end

local function ValidateGap(node, prefix, layoutName)
    if node.gap ~= nil and (type(node.gap) ~= "number" or node.gap < 0) then
        libWarn("%s: %s gap must be a non-negative number", prefix, layoutName)
    end
end

local function ResolveGap(imgui, node, axis)
    if type(node.gap) == "number" then
        return node.gap
    end
    local style = imgui.GetStyle()
    if axis == "x" then
        return GetStyleMetricX(style, "ItemSpacing", 8)
    end
    return GetStyleMetricY(style, "ItemSpacing", 4)
end

local function PushLayoutId(imgui, node)
    local hasId = type(node.id) == "string" and node.id ~= ""
    if hasId then
        imgui.PushID(node.id)
    end
    return hasId
end

local function PopLayoutId(imgui, hasId)
    if hasId then
        imgui.PopID()
    end
end

local function DrawChildrenVStack(imgui, node, drawChild, x, y, availWidth, availHeight)
    local children = type(node.children) == "table" and node.children or {}
    local gap = ResolveGap(imgui, node, "y")
    local currentY = y
    local maxWidth = 0
    local changed = false
    local drewAny = false

    for _, child in ipairs(children) do
        local childAvailHeight = type(availHeight) == "number"
            and math.max(availHeight - (currentY - y), 0)
            or nil
        local consumedWidth, consumedHeight, childChanged = drawChild(child, x, currentY, availWidth, childAvailHeight)
        if childChanged then
            changed = true
        end
        if type(consumedWidth) == "number" and consumedWidth > maxWidth then
            maxWidth = consumedWidth
        end
        if type(consumedHeight) == "number" and consumedHeight > 0 then
            currentY = currentY + consumedHeight
            drewAny = true
            if child ~= children[#children] then
                currentY = currentY + gap
            end
        end
    end

    if not drewAny then
        return 0, 0, changed
    end
    return maxWidth, math.max(currentY - y, 0), changed
end

local function DrawChildrenHStack(imgui, node, drawChild, x, y, availWidth, availHeight)
    local children = type(node.children) == "table" and node.children or {}
    local gap = ResolveGap(imgui, node, "x")
    local currentX = x
    local maxHeight = 0
    local changed = false
    local drewAny = false

    for _, child in ipairs(children) do
        local childAvailWidth = type(availWidth) == "number"
            and math.max(availWidth - (currentX - x), 0)
            or nil
        local consumedWidth, consumedHeight, childChanged = drawChild(child, currentX, y, childAvailWidth, availHeight)
        if childChanged then
            changed = true
        end
        if type(consumedHeight) == "number" and consumedHeight > maxHeight then
            maxHeight = consumedHeight
        end
        if type(consumedWidth) == "number" and consumedWidth > 0 then
            currentX = currentX + consumedWidth
            drewAny = true
            if child ~= children[#children] then
                currentX = currentX + gap
            end
        end
    end

    if not drewAny then
        return 0, 0, changed
    end
    return math.max(currentX - x, 0), maxHeight, changed
end

LayoutTypes.vstack = {
    validate = function(node, prefix)
        ValidateLayoutId(node, prefix, "vstack", false)
        ValidateGap(node, prefix, "vstack")
        ValidateChildren(node, prefix, "vstack")
    end,
    render = function(imgui, node, drawChild, x, y, availWidth, availHeight)
        local hasId = PushLayoutId(imgui, node)
        local consumedWidth, consumedHeight, changed = DrawChildrenVStack(
            imgui, node, drawChild, x, y, availWidth, availHeight)
        PopLayoutId(imgui, hasId)
        return consumedWidth, consumedHeight, changed
    end,
}

LayoutTypes.hstack = {
    validate = function(node, prefix)
        ValidateLayoutId(node, prefix, "hstack", false)
        ValidateGap(node, prefix, "hstack")
        ValidateChildren(node, prefix, "hstack")
    end,
    render = function(imgui, node, drawChild, x, y, availWidth, availHeight)
        local hasId = PushLayoutId(imgui, node)
        local consumedWidth, consumedHeight, changed = DrawChildrenHStack(
            imgui, node, drawChild, x, y, availWidth, availHeight)
        PopLayoutId(imgui, hasId)
        return consumedWidth, consumedHeight, changed
    end,
}

LayoutTypes.collapsible = {
    validate = function(node, prefix)
        if node.label ~= nil and type(node.label) ~= "string" then
            libWarn("%s: collapsible label must be string", prefix)
        end
        if node.defaultOpen ~= nil and type(node.defaultOpen) ~= "boolean" then
            libWarn("%s: collapsible defaultOpen must be boolean", prefix)
        end
        ValidateChildren(node, prefix, "collapsible")
    end,
    render = function(imgui, node, drawChild, x, y, availWidth, availHeight)
        local fallbackHeight = EstimateStructuredRowAdvanceY(imgui)
        local changed, endX, endY, consumedHeight = DrawStructuredAt(
            imgui,
            x,
            y,
            fallbackHeight,
            function()
                local flags = node.defaultOpen == true and 32 or 0
                local open = imgui.CollapsingHeader(node.label or "", flags)
                local childChanged = false
                if open then
                    local childX = GetCursorPosXSafe(imgui)
                    local childY = GetCursorPosYSafe(imgui)
                    local _, _, nestedChanged = DrawChildrenVStack(
                        imgui,
                        { children = node.children, gap = node.gap },
                        drawChild,
                        childX,
                        childY,
                        availWidth,
                        availHeight)
                    childChanged = nestedChanged
                end
                return childChanged
            end)

        local consumedWidth = type(availWidth) == "number"
            and availWidth
            or math.max((type(endX) == "number" and endX or x) - x, 0)
        local _ = endY
        return consumedWidth, consumedHeight, changed
    end,
}

local function ValidateTabbedChildren(node, prefix, layoutName)
    if node.children ~= nil and type(node.children) ~= "table" then
        libWarn("%s: %s children must be a table", prefix, layoutName)
        return false
    end
    if type(node.children) == "table" then
        for childIndex, child in ipairs(node.children) do
            local childPrefix = ("%s child #%d"):format(prefix, childIndex)
            if type(child) ~= "table" then
                libWarn("%s must be a table", childPrefix)
            else
                if type(child.tabLabel) ~= "string" or child.tabLabel == "" then
                    libWarn("%s: %s child tabLabel must be a non-empty string", childPrefix, layoutName)
                end
                if child.tabId ~= nil and (type(child.tabId) ~= "string" or child.tabId == "") then
                    libWarn("%s: %s child tabId must be a non-empty string", childPrefix, layoutName)
                end
                child._tabLabelColor = nil
                if child.tabLabelColor ~= nil then
                    local normalized = NormalizeColor(child.tabLabelColor)
                    if normalized == nil then
                        libWarn("%s: %s child tabLabelColor must be a 3- or 4-number color table", childPrefix, layoutName)
                    else
                        child._tabLabelColor = normalized
                    end
                end
            end
        end
    end
    return true
end

local function WithTabLabelColor(imgui, child, drawFn)
    local color = type(child) == "table" and child._tabLabelColor or nil
    if type(color) ~= "table" then
        return drawFn()
    end

    local textEnum = imgui.ImGuiCol and imgui.ImGuiCol.Text or 0
    imgui.PushStyleColor(textEnum, color[1], color[2], color[3], color[4])
    local ok, a, b, c, d = pcall(drawFn)
    imgui.PopStyleColor()
    if not ok then
        error(a)
    end
    return a, b, c, d
end

local function GetTabbedChildKey(child, index)
    if type(child) ~= "table" then
        return tostring(index)
    end
    if type(child.tabId) == "string" and child.tabId ~= "" then
        return child.tabId
    end
    if type(child.tabLabel) == "string" and child.tabLabel ~= "" then
        return child.tabLabel
    end
    return tostring(index)
end

local function FindTabbedChildByKey(children, activeKey)
    if type(children) ~= "table" or #children == 0 then
        return nil, nil
    end
    for index, child in ipairs(children) do
        if GetTabbedChildKey(child, index) == activeKey then
            return child, index
        end
    end
    return children[1], 1
end

local function SyncActiveTabBinding(node, bound, activeKey)
    node._activeTabKey = activeKey
    if bound and bound.activeTab and bound.activeTab.get and bound.activeTab.set then
        local currentBound = bound.activeTab:get()
        if currentBound ~= activeKey then
            bound.activeTab:set(activeKey)
        end
    end
end

LayoutTypes.tabs = {
    binds = {
        activeTab = { storageType = "string", optional = true },
    },
    validate = function(node, prefix)
        ValidateLayoutId(node, prefix, "tabs", true)
        if node.orientation ~= nil and node.orientation ~= "horizontal" and node.orientation ~= "vertical" then
            libWarn("%s: tabs orientation must be 'horizontal' or 'vertical'", prefix)
        end
        if node.navWidth ~= nil and (type(node.navWidth) ~= "number" or node.navWidth <= 0) then
            libWarn("%s: tabs navWidth must be a positive number", prefix)
        end
        ValidateTabbedChildren(node, prefix, "tabs")
    end,
    render = function(imgui, node, drawChild, x, y, availWidth, availHeight, _, bound)
        local children = type(node.children) == "table" and node.children or {}
        if #children == 0 then
            return 0, 0, false
        end

        local requestedKey = bound and bound.activeTab and bound.activeTab.get and bound.activeTab:get() or nil
        local activeChild, activeIndex = FindTabbedChildByKey(children, requestedKey or node._activeTabKey)
        SyncActiveTabBinding(node, bound, GetTabbedChildKey(activeChild, activeIndex))

        if node.orientation == "vertical" then
            local sidebarWidth = node.navWidth or 180
            local gap = ResolveGap(imgui, node, "x")
            local sidebarHeight = type(availHeight) == "number" and availHeight or 0
            local detailWidth = type(availWidth) == "number"
                and math.max(availWidth - sidebarWidth - gap, 0)
                or 0
            local changed = false
            local _, _, sidebarEndY, sidebarConsumedHeight = DrawStructuredAt(
                imgui,
                x,
                y,
                EstimateStructuredRowAdvanceY(imgui),
                function()
                    imgui.BeginChild(node.id .. "##tabs", sidebarWidth, sidebarHeight, true)
                    for index, child in ipairs(children) do
                        local childKey = GetTabbedChildKey(child, index)
                        local selected = WithTabLabelColor(imgui, child, function()
                            return imgui.Selectable(child.tabLabel, childKey == node._activeTabKey)
                        end)
                        if selected then
                            SyncActiveTabBinding(node, bound, childKey)
                        end
                    end
                    imgui.EndChild()
                    return false
                end)

            local detailChanged, _, detailEndY, detailConsumedHeight = DrawStructuredAt(
                imgui,
                x + sidebarWidth + gap,
                y,
                EstimateStructuredRowAdvanceY(imgui),
                function()
                    imgui.BeginChild(node.id .. "##detail", detailWidth, sidebarHeight, true)
                    activeChild = select(1, FindTabbedChildByKey(children, node._activeTabKey))
                    local childChanged = false
                    if activeChild ~= nil then
                        local childX = GetCursorPosXSafe(imgui)
                        local childY = GetCursorPosYSafe(imgui)
                        local _, _, nextChanged = DrawChildrenVStack(
                            imgui,
                            { children = { activeChild }, gap = 0 },
                            drawChild,
                            childX,
                            childY,
                            detailWidth ~= 0 and detailWidth or nil,
                            availHeight)
                        childChanged = nextChanged
                    end
                    imgui.EndChild()
                    return childChanged
                end)
            changed = detailChanged or changed

            local consumedWidth = type(availWidth) == "number" and availWidth or (sidebarWidth + gap + detailWidth)
            local consumedHeight = math.max(sidebarConsumedHeight or 0, detailConsumedHeight or 0)
            local finalBottom = math.max(sidebarEndY or y, detailEndY or y)
            if finalBottom > y + consumedHeight then
                consumedHeight = finalBottom - y
            end
            return consumedWidth, consumedHeight, changed
        end

        local changed, endX, _, consumedHeight = DrawStructuredAt(
            imgui,
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                local childChanged = false
                if imgui.BeginTabBar(node.id) then
                    for index, child in ipairs(children) do
                        local tabLabel = child.tabLabel
                        if type(child.tabId) == "string" and child.tabId ~= "" then
                            tabLabel = ("%s##%s"):format(tabLabel, child.tabId)
                        end
                        local opened = WithTabLabelColor(imgui, child, function()
                            return imgui.BeginTabItem(tabLabel)
                        end)
                        if opened then
                            SyncActiveTabBinding(node, bound, GetTabbedChildKey(child, index))
                            local childX = GetCursorPosXSafe(imgui)
                            local childY = GetCursorPosYSafe(imgui)
                            local _, _, nestedChanged = DrawChildrenVStack(
                                imgui,
                                { children = { child }, gap = 0 },
                                drawChild,
                                childX,
                                childY,
                                availWidth,
                                availHeight)
                            childChanged = nestedChanged or childChanged
                            imgui.EndTabItem()
                        end
                    end
                    imgui.EndTabBar()
                end
                return childChanged
            end)

        local consumedWidth = type(availWidth) == "number"
            and availWidth
            or math.max((type(endX) == "number" and endX or x) - x, 0)
        return consumedWidth, consumedHeight, changed
    end,
}

LayoutTypes.scrollRegion = {
    validate = function(node, prefix)
        ValidateLayoutId(node, prefix, "scrollRegion", true)
        ValidateGap(node, prefix, "scrollRegion")
        ValidateChildren(node, prefix, "scrollRegion")
        if node.width ~= nil and type(node.width) ~= "number" then
            libWarn("%s: scrollRegion width must be a number", prefix)
        end
        if node.height ~= nil and type(node.height) ~= "number" then
            libWarn("%s: scrollRegion height must be a number", prefix)
        end
        if node.border ~= nil and type(node.border) ~= "boolean" then
            libWarn("%s: scrollRegion border must be boolean", prefix)
        end
    end,
    render = function(imgui, node, drawChild, x, y, availWidth, availHeight)
        local regionWidth = type(node.width) == "number" and node.width
            or (type(availWidth) == "number" and availWidth or 0)
        local regionHeight = type(node.height) == "number" and node.height
            or (type(availHeight) == "number" and availHeight or 0)
        local changed, endX, _, consumedHeight = DrawStructuredAt(
            imgui,
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                imgui.BeginChild(node.id, regionWidth, regionHeight, node.border == true)
                local childX = GetCursorPosXSafe(imgui)
                local childY = GetCursorPosYSafe(imgui)
                local _, _, childChanged = DrawChildrenVStack(
                    imgui,
                    node,
                    drawChild,
                    childX,
                    childY,
                    regionWidth ~= 0 and regionWidth or nil,
                    regionHeight ~= 0 and regionHeight or nil)
                imgui.EndChild()
                return childChanged
            end)
        local consumedWidth = type(node.width) == "number"
            and node.width
            or (type(availWidth) == "number" and availWidth or math.max((endX or x) - x, 0))
        return consumedWidth, consumedHeight, changed
    end,
}

LayoutTypes.split = {
    validate = function(node, prefix)
        if node.orientation ~= nil and node.orientation ~= "horizontal" and node.orientation ~= "vertical" then
            libWarn("%s: split orientation must be 'horizontal' or 'vertical'", prefix)
        end
        ValidateGap(node, prefix, "split")
        ValidateChildren(node, prefix, "split")
        if type(node.children) == "table" and #node.children ~= 2 then
            libWarn("%s: split requires exactly two children", prefix)
        end
        if node.firstSize ~= nil and (type(node.firstSize) ~= "number" or node.firstSize < 0) then
            libWarn("%s: split firstSize must be a non-negative number", prefix)
        end
        if node.secondSize ~= nil and (type(node.secondSize) ~= "number" or node.secondSize < 0) then
            libWarn("%s: split secondSize must be a non-negative number", prefix)
        end
        if node.ratio ~= nil and (type(node.ratio) ~= "number" or node.ratio < 0 or node.ratio > 1) then
            libWarn("%s: split ratio must be between 0 and 1", prefix)
        end
    end,
    render = function(imgui, node, drawChild, x, y, availWidth, availHeight)
        local children = type(node.children) == "table" and node.children or {}
        local first = children[1]
        local second = children[2]
        if first == nil or second == nil then
            return 0, 0, false
        end

        local horizontal = node.orientation ~= "vertical"
        local gap = ResolveGap(imgui, node, horizontal and "x" or "y")
        local axisExtent = horizontal and availWidth or availHeight
        local firstExtent

        if type(node.firstSize) == "number" then
            firstExtent = node.firstSize
        elseif type(node.secondSize) == "number" and type(axisExtent) == "number" then
            firstExtent = math.max(axisExtent - gap - node.secondSize, 0)
        elseif type(node.ratio) == "number" and type(axisExtent) == "number" then
            firstExtent = math.max((axisExtent - gap) * node.ratio, 0)
        elseif type(axisExtent) == "number" then
            firstExtent = math.max((axisExtent - gap) / 2, 0)
        else
            firstExtent = 0
        end

        local secondExtent = type(axisExtent) == "number"
            and math.max(axisExtent - gap - firstExtent, 0)
            or nil

        if horizontal then
            local firstWidth, firstHeight, firstChanged = drawChild(first, x, y, firstExtent, availHeight)
            local secondX = x + (type(firstExtent) == "number" and firstExtent or firstWidth or 0) + gap
            local secondWidth, secondHeight, secondChanged = drawChild(second, secondX, y, secondExtent, availHeight)
            local consumedWidth = type(availWidth) == "number"
                and availWidth
                or math.max((firstWidth or firstExtent or 0) + gap + (secondWidth or secondExtent or 0), 0)
            local consumedHeight = math.max(firstHeight or 0, secondHeight or 0)
            return consumedWidth, consumedHeight, firstChanged or secondChanged
        end

        local firstWidth, firstHeight, firstChanged = drawChild(first, x, y, availWidth, firstExtent)
        local secondY = y + (type(firstExtent) == "number" and firstExtent or firstHeight or 0) + gap
        local secondWidth, secondHeight, secondChanged = drawChild(second, x, secondY, availWidth, secondExtent)
        local consumedWidth = math.max(firstWidth or 0, secondWidth or 0)
        local consumedHeight = type(availHeight) == "number"
            and availHeight
            or math.max((firstHeight or firstExtent or 0) + gap + (secondHeight or secondExtent or 0), 0)
        return consumedWidth, consumedHeight, firstChanged or secondChanged
    end,
}

local function DrawLayoutNode(imgui, node, drawChild, layoutTypes, uiState, x, y, availWidth, availHeight)
    local layoutType = layoutTypes[node.type]
    if not layoutType then
        return false, 0, 0, false
    end

    local bound = nil
    if type(layoutType.binds) == "table" then
        bound = node._boundCache
        if bound == nil or node._boundCacheUiState ~= uiState or node._boundCacheBindOwnerType ~= layoutType then
            bound = shared.fieldRegistry.BuildBoundEntries(node, layoutType, uiState)
        end
        bound._changed = false
    end

    local consumedWidth, consumedHeight, layoutChanged = layoutType.render(
        imgui,
        node,
        drawChild,
        x,
        y,
        availWidth,
        availHeight,
        uiState,
        bound)

    return true, consumedWidth or 0, consumedHeight or 0, (bound and bound._changed or false) or layoutChanged == true
end

registry.DrawLayoutNode = DrawLayoutNode
