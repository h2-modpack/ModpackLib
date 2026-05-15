local helpers = ...

---@class TextOpts
---@field color Color|nil
---@field tooltip string|nil
---@field alignToFramePadding boolean|nil

---@param imgui table
---@return nil
function public.widgets.separator(imgui)
    imgui.Separator()
end

---@param imgui table
---@param text any
---@param opts TextOpts|nil
---@return nil
function public.widgets.text(imgui, text, opts)
    opts = opts or {}
    local renderedText = tostring(text or "")
    local color = helpers.NormalizeColor(opts.color)
    if opts.alignToFramePadding == true then
        imgui.AlignTextToFramePadding()
    end
    if type(color) == "table" then
        imgui.TextColored(color[1], color[2], color[3], color[4], renderedText)
    else
        imgui.Text(renderedText)
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
end
