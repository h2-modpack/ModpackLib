public.imguiHelpers = public.imguiHelpers or {}

local helpers = public.imguiHelpers

helpers.ImGuiComboFlags = {
    NoPreview = _G.ImGuiComboFlags.NoPreview,
}

helpers.ImGuiCol = {
    Text = _G.ImGuiCol.Text,
}

helpers.ImGuiTreeNodeFlags = {
    None = _G.ImGuiTreeNodeFlags.None,
    Selected = _G.ImGuiTreeNodeFlags.Selected,
    Framed = _G.ImGuiTreeNodeFlags.Framed,
    AllowOverlap = _G.ImGuiTreeNodeFlags.AllowOverlap,
    NoTreePushOnOpen = _G.ImGuiTreeNodeFlags.NoTreePushOnOpen,
    NoAutoOpenOnLog = _G.ImGuiTreeNodeFlags.NoAutoOpenOnLog,
    DefaultOpen = _G.ImGuiTreeNodeFlags.DefaultOpen,
    OpenOnDoubleClick = _G.ImGuiTreeNodeFlags.OpenOnDoubleClick,
    OpenOnArrow = _G.ImGuiTreeNodeFlags.OpenOnArrow,
    Leaf = _G.ImGuiTreeNodeFlags.Leaf,
    Bullet = _G.ImGuiTreeNodeFlags.Bullet,
    FramePadding = _G.ImGuiTreeNodeFlags.FramePadding,
    SpanAvailWidth = _G.ImGuiTreeNodeFlags.SpanAvailWidth,
    SpanFullWidth = _G.ImGuiTreeNodeFlags.SpanFullWidth,
    NavLeftJumpsBackHere = _G.ImGuiTreeNodeFlags.NavLeftJumpsBackHere,
    CollapsingHeader = _G.ImGuiTreeNodeFlags.CollapsingHeader,
}

function helpers.unpackColor(color)
    return color[1], color[2], color[3], color[4]
end
