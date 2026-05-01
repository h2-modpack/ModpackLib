public.imguiHelpers = public.imguiHelpers or {}

local helpers = public.imguiHelpers

-- The ReturnOfModding Lua binding exposes these flag values as raw integer
-- parameters, but does not consistently expose the C++ enum tables at runtime.
helpers.ImGuiComboFlags = {
    None = 0,
    NoPreview = 64,
}

helpers.ImGuiCol = {
    Text = 0,
}

helpers.ImGuiTreeNodeFlags = {
    None = 0,
    Selected = 1,
    Framed = 2,
    AllowOverlap = 4,
    NoTreePushOnOpen = 8,
    NoAutoOpenOnLog = 16,
    DefaultOpen = 32,
    OpenOnDoubleClick = 64,
    OpenOnArrow = 128,
    Leaf = 256,
    Bullet = 512,
    FramePadding = 1024,
    SpanAvailWidth = 2048,
    SpanFullWidth = 4096,
    NavLeftJumpsBackHere = 8192,
    CollapsingHeader = 26,
}

function helpers.unpackColor(color)
    return color[1], color[2], color[3], color[4]
end

function helpers.textColored(ui, color, text)
    ui.TextColored(color[1], color[2], color[3], color[4], text)
end
