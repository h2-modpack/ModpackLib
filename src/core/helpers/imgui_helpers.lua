public.imguiHelpers = public.imguiHelpers or {}

-- The ReturnOfModding Lua binding exposes these flag values as raw integer
-- parameters, but does not consistently expose the C++ enum tables at runtime.
public.imguiHelpers.ImGuiComboFlags = {
    None = 0,
    NoPreview = 64,
}

public.imguiHelpers.ImGuiCol = {
    Text = 0,
}

public.imguiHelpers.ImGuiTreeNodeFlags = {
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

function public.imguiHelpers.unpackColor(color)
    return color[1], color[2], color[3], color[4]
end

function public.imguiHelpers.textColored(ui, color, text)
    ui.TextColored(color[1], color[2], color[3], color[4], text)
end
