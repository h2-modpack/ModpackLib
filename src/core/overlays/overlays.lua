local internal = AdamantModpackLib_Internal

public.overlays = public.overlays or {}

-- Public API: shared overlay order bands used by module and system retained overlays.
public.overlays.order = public.overlays.order or {
    framework = 0,
    module = 1000,
    debug = 2000,
}

internal.overlays = internal.overlays or {}

local overlayState = import('core/overlays/private_state.lua')

-- Shared overlay visibility gate. UI suppression is global because foreground
-- configuration UI and gameplay overlays should not compete for screen space.
local function isUiSuppressed()
    return next(overlayState.uiSuppressors) ~= nil
end

local renderer = import('core/overlays/private_renderer.lua', nil, {
    state = overlayState.renderer,
    isUiSuppressed = isUiSuppressed,
})

local retained = import('core/overlays/private_retained.lua', nil, {
    state = overlayState.retained,
    renderer = renderer,
})

-- Module overlay declarations are public by callback surface, not by global
-- function. Host activation passes a scoped registrar into registerOverlays(...)
-- with createLine/createTable/onCommit/onInterval/afterHook.

-- Public API: acquire a token that hides all Lib-managed gameplay overlays while
-- foreground configuration UI is open.
function public.overlays.suppressForUi()
    overlayState.nextUiSuppressorId = overlayState.nextUiSuppressorId + 1
    local id = overlayState.nextUiSuppressorId
    local wasSuppressed = isUiSuppressed()
    overlayState.uiSuppressors[id] = true
    if not wasSuppressed then
        renderer.refreshAll()
    end

    local released = false
    return {
        release = function()
            if released then
                return
            end
            released = true
            overlayState.uiSuppressors[id] = nil
            if not isUiSuppressed() then
                renderer.refreshAll()
            end
        end,
    }
end

-- Public API: read whether any UI suppression token is currently active.
function public.overlays.isUiSuppressed()
    return isUiSuppressed()
end

-- Internal API: snapshot owner-scoped retained declarations so host activation
-- can roll them back if a later activation step fails.
function internal.overlays.beginTransaction(owner)
    return retained.beginTransaction(owner)
end

-- Internal API: rebuild the retained declaration surface for one owner.
-- Used by module host activation and hot reload.
function internal.overlays.refresh(owner, ownerId, authorHost, store, register)
    return retained.refresh(owner, ownerId, authorHost, store, register)
end

-- Internal API: dispatch overlay projections after settings commit.
function internal.overlays.dispatchCommit(owner, commit)
    return retained.dispatchCommit(owner, commit)
end

-- Internal API: dispatch retained interval projections from the ImGui tick driver.
function internal.overlays.dispatchIntervals(now)
    return retained.dispatchIntervals(now)
end

-- Internal API: dispatch an overlay after-hook projection registered by a retained owner.
function internal.overlays.dispatchAfterHook(owner, path, args, results)
    return retained.dispatchAfterHook(owner, path, args, results)
end

-- Public API: declare retained overlays for Lib/Framework systems that are not
-- owned by a module host.
function public.overlays.defineOwned(owner, register)
    if type(owner) ~= "string" or owner == "" then
        internal.violate("overlays.invalid_registration", "lib.overlays.defineOwned: owner must be a non-empty string")
    end
    local transaction = internal.overlays.beginTransaction(owner)
    local ok, err = pcall(function()
        internal.overlays.refresh(owner, owner, nil, nil, register)
    end)
    if ok then
        transaction.commit()
        internal.overlays.dispatchCommit(owner, {})
        return true
    end

    transaction.rollback()
    error(err, 0)
end
