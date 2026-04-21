# ImGui Lua Binding Reference

Reference for the Dear ImGui Lua binding exposed by ReturnOfModdingBase.

Written for widget and UI authors who need precise behavior facts without re-reading
the C++ binding source on every question.

## Source of Truth

Binding documentation:
- `ReturnOfModdingBase/docs/lua/tables/ImGui.md`

Binding source:
- `ReturnOfModdingBase/src/lua/bindings/imgui.hpp`

---

## Cursor and Layout

### Positioning

```lua
-- Read current cursor position (relative to window content area)
x, y = ImGui.GetCursorPos()
x    = ImGui.GetCursorPosX()
y    = ImGui.GetCursorPosY()

-- Set cursor position (relative to window content area)
ImGui.SetCursorPos(x, y)
ImGui.SetCursorPosX(x)
ImGui.SetCursorPosY(y)

-- Read the absolute screen position at the current cursor
x, y = ImGui.GetCursorScreenPos()

-- Set cursor at an absolute screen position
ImGui.SetCursorScreenPos(x, y)

-- Read the start position of the current window's content region
x, y = ImGui.GetCursorStartPos()
```

`SetCursorPosX/Y` and `GetCursorPosX/Y` are local to the current window content area.
`GetCursorScreenPos` gives the absolute screen coordinate - useful when you need to know
the actual rendered Y after drawing a sequence of items.

### Flow control

```lua
-- Keep next item on the same line
ImGui.SameLine()
ImGui.SameLine(offset_from_start_x)
ImGui.SameLine(offset_from_start_x, spacing)
```

All three overloads are available in Lua. `spacing` overrides the default item spacing
for that same-line step.

```lua
-- Force a line break
ImGui.NewLine()

-- Add vertical spacing (one item-spacing worth)
ImGui.Spacing()

-- Reserve space without drawing (advances the cursor by size_x, size_y)
ImGui.Dummy(size_x, size_y)

-- Indent / unindent content
ImGui.Indent()
ImGui.Indent(indent_w)
ImGui.Unindent()
ImGui.Unindent(indent_w)
```

### Text alignment

```lua
-- Vertically align the next Text() call to frame height (call before Text, not after)
ImGui.AlignTextToFramePadding()
```

Call this before `Text(...)` when rendering text beside a taller widget like a button
or input. Without it, the text baseline sits at the top of the item row rather than
vertically centered to the frame height.

### Groups

```lua
ImGui.BeginGroup()
-- ... draw items ...
ImGui.EndGroup()
```

`BeginGroup`/`EndGroup` wraps items into a single bounding box. Useful for:
- tooltip hit detection over a composite widget
- treating multiple draw calls as one unit for `SameLine` chaining

---

## Size and Region Queries

### Window size

```lua
width  = ImGui.GetWindowWidth()
height = ImGui.GetWindowHeight()
x, y   = ImGui.GetWindowSize()
x, y   = ImGui.GetWindowPos()
```

### Available space

```lua
-- Available content region from the current cursor position
x, y = ImGui.GetContentRegionAvail()

-- Absolute bounds of the current window's content region
x, y = ImGui.GetWindowContentRegionMin()
x, y = ImGui.GetWindowContentRegionMax()
```

`GetContentRegionAvail()` is the preferred query when you want to know how much space
is left to draw into from the current cursor. It accounts for scrollbars and window
padding. `GetWindowWidth()` does not.

### Row and frame height

```lua
height = ImGui.GetTextLineHeight()            -- font size only
height = ImGui.GetTextLineHeightWithSpacing() -- font size + item spacing
height = ImGui.GetFrameHeight()               -- font size + frame padding * 2
height = ImGui.GetFrameHeightWithSpacing()    -- frame height + item spacing
```

These are the reliable way to estimate row advancement without drawing an item.
`GetFrameHeight()` matches the height of buttons, inputs, and most interactive widgets.

---

## Item Queries

```lua
-- Size of the last drawn item
x, y = ImGui.GetItemRectSize()

-- Bounding box of the last drawn item (screen coordinates)
x, y = ImGui.GetItemRectMin()
x, y = ImGui.GetItemRectMax()

-- State queries for the last drawn item
hovered    = ImGui.IsItemHovered()
active     = ImGui.IsItemActive()
focused    = ImGui.IsItemFocused()
clicked    = ImGui.IsItemClicked()
clicked    = ImGui.IsItemClicked(ImGuiMouseButton.Middle)
visible    = ImGui.IsItemVisible()
edited     = ImGui.IsItemEdited()
activated  = ImGui.IsItemActivated()
deactivated = ImGui.IsItemDeactivated()
deactivated_after_edit = ImGui.IsItemDeactivatedAfterEdit()
```

`GetItemRectSize()` returns `x, y` - a tuple, not a scalar. Test doubles often
simplify this to a single number; real backend returns two values.

---

## Text Measurement

```lua
x, y = ImGui.CalcTextSize(text)
x, y = ImGui.CalcTextSize(text, hide_text_after_double_hash)
x, y = ImGui.CalcTextSize(text, hide_text_after_double_hash, wrap_width)
```

Returns `x, y` - a tuple. The `x` component is the width you usually want for sizing.

`hide_text_after_double_hash = true` stops measurement at `##` (same as ImGui label
truncation). Useful when measuring a label string that includes an ID suffix.

`wrap_width` enables word-wrap simulation in the measurement. Omit unless you are
measuring wrapped text.

```lua
-- Width of the current item width context (PushItemWidth / SetNextItemWidth)
width = ImGui.CalcItemWidth()

-- Font size in pixels
fontSize = ImGui.GetFontSize()
```

---

## Style and Color

### Color

```lua
-- Push a color override for a style slot
ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
ImGui.PushStyleColor(ImGuiCol.Text, color_u32)

-- Pop color overrides
ImGui.PopStyleColor()
ImGui.PopStyleColor(count)

-- Read a style color as r, g, b, a
r, g, b, a = ImGui.GetStyleColorVec4(ImGuiCol.Text)
```

### Style vars

```lua
-- Push a scalar or vec2 style override
ImGui.PushStyleVar(ImGuiStyleVar.Alpha, value)
ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, x, y)

-- Pop style var overrides
ImGui.PopStyleVar()
ImGui.PopStyleVar(count)
```

### Item width

```lua
-- Set item width for all subsequent items until popped
ImGui.PushItemWidth(width)
ImGui.PopItemWidth()

-- Set item width for the next item only
ImGui.SetNextItemWidth(width)
```

Negative values for `PushItemWidth` are relative to the right edge of the window.
`-1` means "fill to right edge."

---

## Text Widgets

```lua
ImGui.Text(text)
ImGui.TextColored(r, g, b, a, text)
ImGui.TextDisabled(text)
ImGui.TextWrapped(text)
ImGui.TextUnformatted(text)
ImGui.LabelText(label, text)
ImGui.BulletText(text)
```

---

## Buttons

```lua
clicked = ImGui.Button(label)
clicked = ImGui.Button(label, size_x, size_y)

clicked = ImGui.SmallButton(label)
clicked = ImGui.InvisibleButton(label, size_x, size_y)
clicked = ImGui.ArrowButton(str_id, ImGuiDir.Down)
```

---

## Input Widgets

### Checkbox

```lua
value, pressed = ImGui.Checkbox(label, value)
```

Returns the new value and whether it was toggled.

### Radio button

```lua
-- Bool overload (manual active state)
pressed = ImGui.RadioButton(label, active)

-- Int overload (value comparison)
value, pressed = ImGui.RadioButton(label, value, v_button)
```

### Combo / dropdown

```lua
-- Managed combo
current_item, clicked = ImGui.Combo(label, current_item, items_table, items_count)
current_item, clicked = ImGui.Combo(label, current_item, items_table, items_count, popup_max_height)

-- Manual combo (BeginCombo/EndCombo loop)
shouldDraw = ImGui.BeginCombo(label, preview_value)
shouldDraw = ImGui.BeginCombo(label, preview_value, ImGuiComboFlags.PopupAlignLeft)
ImGui.EndCombo()
```

### Text input

```lua
text, changed = ImGui.InputText(label, text, max_length)
text, changed = ImGui.InputText(label, text, max_length, ImGuiInputTextFlags.None)

text, changed = ImGui.InputTextMultiline(label, text, max_length, size_x, size_y)
text, changed = ImGui.InputTextWithHint(label, hint, text, max_length)
```

### Numeric steppers

```lua
value, used = ImGui.InputInt(label, value)
value, used = ImGui.InputInt(label, value, step, step_fast)
value, used = ImGui.InputFloat(label, value)
value, used = ImGui.InputFloat(label, value, step, step_fast, format)
```

### Sliders and drags

```lua
value, used = ImGui.SliderInt(label, value, min, max)
value, used = ImGui.SliderFloat(label, value, min, max)
value, used = ImGui.DragInt(label, value)
value, used = ImGui.DragInt(label, value, speed, min, max)
value, used = ImGui.DragFloat(label, value)
value, used = ImGui.DragFloat(label, value, speed, min, max, format)
```

---

## ID Stack

```lua
ImGui.PushID(str_id)
ImGui.PushID(int_id)
ImGui.PopID()

id = ImGui.GetID(str_id)
```

Use PushID/PopID when drawing repeated items that share the same label text. ImGui
generates widget IDs from the label — duplicate labels in the same scope collide.

---

## Windows and Child Windows

### Windows

```lua
shouldDraw = ImGui.Begin(name)
shouldDraw = ImGui.Begin(name, ImGuiWindowFlags.NoMove)
open, shouldDraw = ImGui.Begin(name, open)
open, shouldDraw = ImGui.Begin(name, open, ImGuiWindowFlags.NoMove)
ImGui.End()
```

Always call `End()` even when `shouldDraw` is false.

### Child windows

```lua
shouldDraw = ImGui.BeginChild(name)
shouldDraw = ImGui.BeginChild(name, size_x, size_y)
shouldDraw = ImGui.BeginChild(name, size_x, size_y, border)
shouldDraw = ImGui.BeginChild(name, size_x, size_y, border, ImGuiWindowFlags.NoMove)
ImGui.EndChild()
```

Child windows create an isolated scrollable region with their own cursor origin.
`GetContentRegionAvail()` inside a child window returns the available space within
that child, not the parent window.

---

## Collapsing Headers

```lua
notCollapsed = ImGui.CollapsingHeader(label)
notCollapsed = ImGui.CollapsingHeader(label, ImGuiTreeNodeFlags.DefaultOpen)
open, notCollapsed = ImGui.CollapsingHeader(label, open)
```

---

## Tooltips

```lua
ImGui.BeginTooltip()
-- draw tooltip content
ImGui.EndTooltip()

ImGui.SetTooltip(text)
```

---

## Popups and Modals

```lua
-- Open a popup (call this where the trigger happens, not inside BeginPopup)
ImGui.OpenPopup(str_id)

-- Render a popup
open = ImGui.BeginPopup(str_id)
-- draw popup content
ImGui.EndPopup()

-- Render a modal
open = ImGui.BeginPopupModal(name)
open = ImGui.BeginPopupModal(name, open)
open = ImGui.BeginPopupModal(name, open, ImGuiWindowFlags.NoResize)
ImGui.EndPopup()

ImGui.CloseCurrentPopup()
```

Popups are identified by string ID. `BeginPopup` returns false until `OpenPopup`
has been called with the matching ID.

---

## Scrolling

```lua
y = ImGui.GetScrollY()
y = ImGui.GetScrollMaxY()
ImGui.SetScrollY(value)
ImGui.SetScrollHereY()
ImGui.SetScrollHereY(center_ratio)   -- 0 = top, 0.5 = center, 1 = bottom
```

---

## Separator

```lua
ImGui.Separator()
```

Draws a full-width horizontal rule. Note: in the Lua docs this is listed as `ImGui.Separator` without parentheses, but calling it as `ImGui.Separator()` works in practice.

---

## Disabling

```lua
ImGui.BeginDisabled()
ImGui.BeginDisabled(disabled)  -- pass false to conditionally skip disabling
ImGui.EndDisabled()
```

Items drawn inside `BeginDisabled`/`EndDisabled` are visually dimmed and do not respond
to interaction.

---

## Clipping

```lua
ImGui.PushClipRect(min_x, min_y, max_x, max_y, intersect_with_current)
ImGui.PopClipRect()
```

---

## Miscellaneous

```lua
-- Elapsed time since ImGui init
time = ImGui.GetTime()

-- Frame counter (increments every rendered frame)
frame_count = ImGui.GetFrameCount()

-- Rect visibility culling check
visible = ImGui.IsRectVisible(size_x, size_y)          -- from current cursor
visible = ImGui.IsRectVisible(min_x, min_y, max_x, max_y)  -- absolute
```

---

## Key Behavioral Facts

### `SameLine` has three overloads

```lua
ImGui.SameLine()
ImGui.SameLine(offset_from_start_x)
ImGui.SameLine(offset_from_start_x, spacing)
```

The two-argument form overrides item spacing for that same-line step. All three are
exported to Lua.

### `CalcTextSize` and `GetItemRectSize` return tuples

```lua
width, height = ImGui.CalcTextSize("text")
width, height = ImGui.GetItemRectSize()
```

Both return two values. Using them as a single return (e.g. `local w = ImGui.CalcTextSize(...)`)
silently discards the height. Test doubles sometimes return a scalar - the real backend does not.

### Cursor positions are window-local; screen positions are absolute

`SetCursorPosX/Y` and `GetCursorPosX/Y` are relative to the current window's content
origin. `GetCursorScreenPos` / `SetCursorScreenPos` are in screen (display) coordinates.
Do not mix them without converting.

### `GetContentRegionAvail` vs `GetWindowWidth`

`GetContentRegionAvail()` returns the space remaining from the current cursor to the
content boundary. `GetWindowWidth()` returns the full window width ignoring cursor
position, scrollbars, and padding. Prefer `GetContentRegionAvail()` when sizing
children to fill available space.

### `AlignTextToFramePadding` must be called before the text item

```lua
ImGui.AlignTextToFramePadding()
ImGui.Text("Label")
ImGui.SameLine()
ImGui.Button("Action")
```

Call it immediately before the `Text(...)` call it should affect. It adjusts the
vertical position of the next item only.

### ID collision with duplicate labels

ImGui derives widget IDs from label strings. Two widgets with the same label in the
same window scope will collide. Use `##suffix` to add a hidden ID component:

```lua
ImGui.Button("Reset##ModuleA")
ImGui.Button("Reset##ModuleB")
```

Or use `PushID`/`PopID` around repeated items in a loop.

### `GetStyle()` is not in the Lua binding

`GetStyle()` is not exported by this binding. Use `GetStyleColorVec4(ImGuiCol.*)`,
`GetFontSize()`, and `GetFrameHeight()` to read style metrics instead.
