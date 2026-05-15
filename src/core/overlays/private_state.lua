AdamantModpackLib_OverlayState = AdamantModpackLib_OverlayState or {}

local state = AdamantModpackLib_OverlayState

state.renderer = state.renderer or {}
state.renderer.textElements = state.renderer.textElements or {}
state.renderer.stackRows = state.renderer.stackRows or {}

state.uiSuppressors = state.uiSuppressors or {}
state.nextUiSuppressorId = state.nextUiSuppressorId or 0

state.retained = state.retained or {}
state.retained.tableRegistries = state.retained.tableRegistries or setmetatable({}, { __mode = "k" })
state.retained.explicitRegistries = state.retained.explicitRegistries or {}
state.retained.nextOwnerId = state.retained.nextOwnerId or 0
state.retained.intervalDriverRegistered = state.retained.intervalDriverRegistered == true

return state
