local helpers = ...

---@class ButtonOpts
---@field id string|number|nil
---@field tooltip string|nil
---@field action string|nil Staged session action key to replace when clicked.
---@field value any Staged session action payload.
---@field onClick fun(imgui: table)|nil

---@class ConfirmButtonOpts
---@field tooltip string|nil
---@field confirmLabel string|nil
---@field cancelLabel string|nil
---@field action string|nil Staged session action key to replace when confirmed.
---@field value any Staged session action payload.
---@field onConfirm fun(imgui: table)|nil

local function StageAction(session, opts)
    if opts.action ~= nil then
        session.stageAction(opts.action, opts.value)
    end
end

---@param imgui table
---@param session Session
---@param label any
---@param opts ButtonOpts|nil
---@return boolean
function public.widgets.button(imgui, session, label, opts)
    opts = opts or {}
    local id = tostring(opts.id or label or "")
    local clicked = imgui.Button(tostring(label or "") .. "##" .. id)
    helpers.ShowTooltip(imgui, opts.tooltip)
    if clicked then
        if type(opts.onClick) == "function" then
            opts.onClick(imgui)
        end
        StageAction(session, opts)
    end
    return clicked == true
end

---@param imgui table
---@param session Session
---@param id string|number
---@param label any
---@param opts ConfirmButtonOpts|nil
---@return boolean
function public.widgets.confirmButton(imgui, session, id, label, opts)
    opts = opts or {}
    local popupId = tostring(id) .. "##popup"
    local changed = false
    if imgui.Button(tostring(label or "") .. "##" .. tostring(id)) then
        imgui.OpenPopup(popupId)
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
    if imgui.BeginPopup(popupId) then
        local confirmLabel = tostring(opts.confirmLabel or "Confirm")
        local cancelLabel = tostring(opts.cancelLabel or "Cancel")
        if imgui.Button(confirmLabel .. "##confirm_" .. tostring(id)) then
            if type(opts.onConfirm) == "function" then
                opts.onConfirm(imgui)
            end
            StageAction(session, opts)
            imgui.CloseCurrentPopup()
            changed = true
        end
        imgui.SameLine()
        if imgui.Button(cancelLabel .. "##cancel_" .. tostring(id)) then
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
    return changed
end
