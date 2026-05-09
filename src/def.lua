-- luacheck: no unused args
---@meta adamant-ModpackLib

---@class AdamantModpackLib
local lib = {}

---@alias AdamantModpackLib.Color number[]
---@alias AdamantModpackLib.ChoiceValue any
---@alias AdamantModpackLib.ChoiceDisplayValues table<any, string>
---@alias AdamantModpackLib.ValueColorMap table<any, AdamantModpackLib.Color>
---@alias AdamantModpackLib.PackedSelectionMode "singleEnabled"|"singleDisabled"
---@alias AdamantModpackLib.MutationShape "patch"|"manual"|"hybrid"

---@class AdamantModpackLib.Config
---@field DebugMode boolean Whether Lib should emit internal diagnostic warnings.

---@class AdamantModpackLib.HashGroup
---@field keyPrefix string Hash group family prefix.
---@field items (string|string[])[] Ordered aliases or alias bundles to pack together.

---@alias AdamantModpackLib.HashGroupPlan AdamantModpackLib.HashGroup[]

---@class AdamantModpackLib.StorageNode
---@field type "bool"|"int"|"string"|"packedInt"|"table"
---@field alias string Public alias used by store/session/widget APIs and as the persisted backing key.
---@field label? string UI label.
---@field tooltip? string UI tooltip.
---@field default? any Default value for this storage node.
---@field persist? boolean Whether the alias persists through config; defaults true.
---@field stage? boolean Whether the alias participates in staged session UI; defaults true.
---@field hash? boolean Whether the alias participates in hash/profile surfaces; defaults true.
---@field visibleIf? string|AdamantModpackLib.VisibilityCondition Visibility condition used by UI helpers.
---@field min? number Integer lower bound.
---@field max? number Integer upper bound.
---@field width? number Packed/hash bit width for integer-like nodes.
---@field maxLen? number String max length for input widgets/hash normalization.
---@field bits? AdamantModpackLib.PackedBitNode[] Packed child bit aliases for `packedInt`.
---@field row? AdamantModpackLib.StorageSchema Row schema for `table` roots.
---@field minRows? integer Minimum row count for `table` roots.
---@field maxRows? integer Maximum row count for `table` roots.
---@field defaultRows? integer Default row count for `table` roots.

---@class AdamantModpackLib.PackedBitNode
---@field type "bool"|"int"
---@field alias string Public alias for a child bit field.
---@field label? string UI label.
---@field tooltip? string UI tooltip.
---@field default? any Default value for this bit field.
---@field offset number Bit offset inside the parent packed integer.
---@field width number Bit width inside the parent packed integer.
---@field min? number Integer lower bound.
---@field max? number Integer upper bound.

---@alias AdamantModpackLib.StorageSchema AdamantModpackLib.StorageNode[]

---Table handles are object handles; call methods with colon syntax (`rows:read(...)`).
---@class AdamantModpackLib.StorageTableReadOnly
---@field count fun(self: AdamantModpackLib.StorageTableReadOnly): integer
---@field read fun(self: AdamantModpackLib.StorageTableReadOnly, rowIndex: integer, alias: string): any
---@field row fun(self: AdamantModpackLib.StorageTableReadOnly, rowIndex: integer): table?
---@field rows fun(self: AdamantModpackLib.StorageTableReadOnly): table[]

---Writable table handles are object handles; call methods with colon syntax (`rows:write(...)`).
---@class AdamantModpackLib.StorageTableSession: AdamantModpackLib.StorageTableReadOnly
---@field write fun(self: AdamantModpackLib.StorageTableSession, rowIndex: integer, alias: string, value: any): boolean
---@field reset fun(self: AdamantModpackLib.StorageTableSession, rowIndex: integer, alias: string): boolean
---@field resetRow fun(self: AdamantModpackLib.StorageTableSession, rowIndex: integer): boolean
---@field append fun(self: AdamantModpackLib.StorageTableSession, rowValues?: table): boolean
---@field insert fun(self: AdamantModpackLib.StorageTableSession, rowIndex: integer, rowValues?: table): boolean
---@field remove fun(self: AdamantModpackLib.StorageTableSession, rowIndex: integer): boolean
---@field clear fun(self: AdamantModpackLib.StorageTableSession): boolean

---@class AdamantModpackLib.ManagedStore
---@field read fun(alias: string): any
---@field table fun(alias: string): AdamantModpackLib.StorageTableReadOnly?
---@field writeUnstaged fun(alias: string, value: any): boolean

---@class AdamantModpackLib.Session
---@field view table<string, any>
---@field read fun(alias: string): any
---@field table fun(alias: string): AdamantModpackLib.StorageTableSession?
---@field getAliasSchema fun(alias: string): AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode|nil Read-only schema metadata.
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field _flushToConfig fun()
---@field _reloadFromConfig fun()
---@field _captureDirtyConfigSnapshot fun(): table[]
---@field _restoreConfigSnapshot fun(snapshot: table[]?)
---@field isDirty fun(): boolean
---@field auditMismatches fun(): string[]

---@class AdamantModpackLib.AuthorSession
---@field view table<string, any>
---@field read fun(alias: string): any
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field getAliasSchema fun(alias: string): AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode|nil Read-only schema metadata.
---@field resetToDefaults fun(opts?: AdamantModpackLib.ResetOpts): boolean, integer

---@class AdamantModpackLib.AuthorHost
---@field isEnabled fun(): boolean
---@field getIdentity fun(): AdamantModpackLib.ModuleIdentity
---@field getMeta fun(): AdamantModpackLib.ModuleMeta

---@class AdamantModpackLib.ModuleDefinition
---@field modpack? string Coordinator pack id for coordinated modules.
---@field id? string Stable module id within the pack.
---@field name? string Display name.
---@field shortName? string Short UI label.
---@field tooltip? string UI tooltip.
---@field storage? AdamantModpackLib.StorageSchema Module storage schema.
---@field hashGroupPlan? AdamantModpackLib.HashGroupPlan Hash compaction hints.

---@class AdamantModpackLib.PreparedDefinition: AdamantModpackLib.ModuleDefinition

---@class AdamantModpackLib.ManualMutation
---@field apply fun(store: AdamantModpackLib.ManagedStore)
---@field revert fun(store: AdamantModpackLib.ManagedStore)

---@class AdamantModpackLib.MutationBundle
---@field affectsRunData boolean
---@field patchMutation? fun(plan: AdamantModpackLib.MutationPlan, store: AdamantModpackLib.ManagedStore)
---@field manualMutation? AdamantModpackLib.ManualMutation

---@class AdamantModpackLib.ModuleHostOpts
---@field definition AdamantModpackLib.PreparedDefinition
---@field pluginGuid string Plugin guid captured at module file load time.
---@field store AdamantModpackLib.ManagedStore
---@field session AdamantModpackLib.Session
---@field hookOwner? table Persistent table used by hot-reload-safe hooks.
---@field registerHooks? fun()
---@field registerPatchMutation? fun(plan: AdamantModpackLib.MutationPlan, store: AdamantModpackLib.ManagedStore)
---@field registerManualMutation? AdamantModpackLib.ManualMutation
---@field onSettingsCommitted? fun(store: AdamantModpackLib.ManagedStore) Post-commit observer for rebuilding derived runtime/UI structures.
---@field registerIntegrations? fun(host: AdamantModpackLib.AuthorHost)
---@field drawTab fun(imgui: table, session: AdamantModpackLib.AuthorSession, host: AdamantModpackLib.AuthorHost)
---@field drawQuickContent? fun(imgui: table, session: AdamantModpackLib.AuthorSession, host: AdamantModpackLib.AuthorHost)

---@class AdamantModpackLib.ModuleCreateOpts
---@field owner table Persistent module owner used for structural hot-reload tracking and hook refresh ownership.
---@field pluginGuid string Plugin guid captured at module file load time.
---@field config table Module config table.
---@field definition AdamantModpackLib.ModuleDefinition Raw module definition.
---@field registerHooks? fun()
---@field registerPatchMutation? fun(plan: AdamantModpackLib.MutationPlan, store: AdamantModpackLib.ManagedStore)
---@field registerManualMutation? AdamantModpackLib.ManualMutation
---@field onSettingsCommitted? fun(store: AdamantModpackLib.ManagedStore) Post-commit observer for rebuilding derived runtime/UI structures.
---@field registerIntegrations? fun(host: AdamantModpackLib.AuthorHost)
---@field drawTab fun(imgui: table, session: AdamantModpackLib.AuthorSession, host: AdamantModpackLib.AuthorHost)
---@field drawQuickContent? fun(imgui: table, session: AdamantModpackLib.AuthorSession, host: AdamantModpackLib.AuthorHost)

---@class AdamantModpackLib.ModuleHost
---@field getIdentity fun(): AdamantModpackLib.ModuleIdentity
---@field getMeta fun(): AdamantModpackLib.ModuleMeta
---@field affectsRunData fun(): boolean
---@field getHashHints fun(): AdamantModpackLib.HashGroupPlan?
---@field getStorage fun(): AdamantModpackLib.StorageSchema?
---@field read fun(alias: string): any
---@field writeAndFlush fun(alias: string, value: any): boolean
---@field stage fun(alias: string, value: any): boolean
---@field flush fun(): boolean
---@field reloadFromConfig fun()
---@field resync fun(): string[]
---@field resetToDefaults fun(opts?: AdamantModpackLib.ResetOpts): boolean, integer
---@field commitIfDirty fun(): boolean, string?, boolean
---@field isEnabled fun(): boolean
---@field setEnabled fun(enabled: boolean): boolean, string?
---@field setDebugMode fun(enabled: boolean)
---@field applyOnLoad fun(): boolean, string?
---@field applyMutation fun(): boolean, string?
---@field revertMutation fun(): boolean, string?
---@field drawTab fun(imgui: table)
---@field drawQuickContent? fun(imgui: table)

---@class AdamantModpackLib.ModuleIdentity
---@field id? string
---@field modpack? string

---@class AdamantModpackLib.ModuleMeta
---@field name? string
---@field shortName? string
---@field tooltip? string

---@class AdamantModpackLib.ResetOpts
---@field exclude? table<string, boolean> Root aliases to skip.

---@class AdamantModpackLib.StandaloneRuntime
---@field renderWindow fun()
---@field addMenuBar fun()

---@class AdamantModpackLib.CoordinatorConfig
---@field ModEnabled boolean

---@class AdamantModpackLib.MutationInfo
---@field hasPatch boolean
---@field hasApply boolean
---@field hasRevert boolean
---@field hasManual boolean

---@alias AdamantModpackLib.MutationPlanFn fun(self: AdamantModpackLib.MutationPlan, ...: any): AdamantModpackLib.MutationPlan

---@class AdamantModpackLib.MutationPlan
---@field set AdamantModpackLib.MutationPlanFn
---@field setMany AdamantModpackLib.MutationPlanFn
---@field transform AdamantModpackLib.MutationPlanFn
---@field append AdamantModpackLib.MutationPlanFn
---@field appendUnique AdamantModpackLib.MutationPlanFn
---@field removeElement AdamantModpackLib.MutationPlanFn
---@field setElement AdamantModpackLib.MutationPlanFn
---@field apply fun(): boolean
---@field revert fun(): boolean

---@class AdamantModpackLib.IntegrationProvider
---@field providerId string
---@field api table

---@class AdamantModpackLib.GameObjectApi
---@field get fun(object: table, packId: string, moduleId: string, key: string, factory?: fun(): table): table
---@field peek fun(object: table, packId: string, moduleId: string, key: string): table?
---@field clear fun(object: table, packId: string, moduleId: string, key: string): boolean

---@class AdamantModpackLib.VisibilityCondition
---@field alias string
---@field value? any
---@field anyOf? any[]

---@class AdamantModpackLib.NavTab
---@field key string|number
---@field label? string
---@field group? string
---@field color? AdamantModpackLib.Color

---@class AdamantModpackLib.VerticalTabsOpts
---@field id? string|number
---@field navWidth? number
---@field height? number
---@field tabs? AdamantModpackLib.NavTab[]
---@field activeKey? string|number

---@class AdamantModpackLib.TextOpts
---@field color? AdamantModpackLib.Color
---@field tooltip? string
---@field alignToFramePadding? boolean

---@class AdamantModpackLib.ButtonOpts
---@field id? string|number
---@field tooltip? string
---@field onClick? fun(imgui: table)

---@class AdamantModpackLib.ConfirmButtonOpts
---@field tooltip? string
---@field confirmLabel? string
---@field cancelLabel? string
---@field onConfirm? fun(imgui: table)

---@class AdamantModpackLib.InputTextOpts
---@field label? string
---@field tooltip? string
---@field maxLen? number
---@field controlWidth? number
---@field controlGap? number

---@class AdamantModpackLib.DropdownOpts
---@field label? string
---@field tooltip? string
---@field values? AdamantModpackLib.ChoiceValue[]
---@field default? AdamantModpackLib.ChoiceValue
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? AdamantModpackLib.ValueColorMap
---@field controlWidth? number
---@field controlGap? number

---@class AdamantModpackLib.MappedDropdownOption
---@field id? string|number
---@field label? string
---@field value any
---@field color? AdamantModpackLib.Color
---@field onSelect? fun(option: AdamantModpackLib.MappedDropdownOption, session: AdamantModpackLib.Session): boolean?

---@class AdamantModpackLib.MappedDropdownOpts
---@field label? string
---@field tooltip? string
---@field controlWidth? number
---@field controlGap? number
---@field getPreview? fun(view: table<string, any>): string|number|boolean?
---@field getPreviewColor? fun(view: table<string, any>): AdamantModpackLib.Color?
---@field getOptions? fun(view: table<string, any>): AdamantModpackLib.MappedDropdownOption[]|any[]

---@class AdamantModpackLib.PackedDropdownOpts
---@field label? string
---@field tooltip? string
---@field controlWidth? number
---@field controlGap? number
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? table<string, AdamantModpackLib.Color>
---@field noneLabel? string
---@field multipleLabel? string
---@field selectionMode? AdamantModpackLib.PackedSelectionMode

---@class AdamantModpackLib.RadioOpts
---@field label? string
---@field values? AdamantModpackLib.ChoiceValue[]
---@field default? AdamantModpackLib.ChoiceValue
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? AdamantModpackLib.ValueColorMap
---@field optionsPerLine? number
---@field optionGap? number

---@class AdamantModpackLib.MappedRadioOption
---@field label? string
---@field value any
---@field color? AdamantModpackLib.Color
---@field selected? boolean
---@field onSelect? fun(option: AdamantModpackLib.MappedRadioOption, session: AdamantModpackLib.Session): boolean?

---@class AdamantModpackLib.MappedRadioOpts
---@field label? string
---@field optionsPerLine? number
---@field optionGap? number
---@field getOptions? fun(view: table<string, any>): AdamantModpackLib.MappedRadioOption[]|any[]

---@class AdamantModpackLib.PackedRadioOpts
---@field label? string
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? table<string, AdamantModpackLib.Color>
---@field noneLabel? string
---@field selectionMode? AdamantModpackLib.PackedSelectionMode
---@field optionsPerLine? number
---@field optionGap? number

---@class AdamantModpackLib.StepperOpts
---@field label? string
---@field default? number
---@field min? number
---@field max? number
---@field step? number
---@field displayValues? table<number, string>
---@field valueWidth? number
---@field buttonSpacing? number

---@class AdamantModpackLib.SteppedRangeOpts: AdamantModpackLib.StepperOpts
---@field defaultMax? number
---@field rangeGap? number

---@class AdamantModpackLib.CheckboxOpts
---@field label? string
---@field tooltip? string
---@field color? AdamantModpackLib.Color

---@class AdamantModpackLib.PackedCheckboxListOpts
---@field filterText? string
---@field filterMode? "all"|"checked"|"unchecked"
---@field valueColors? table<string, AdamantModpackLib.Color>
---@field slotCount? number
---@field optionsPerLine? number
---@field optionGap? number

---@class AdamantModpackLib.LifecycleApi
---@type AdamantModpackLib.LifecycleApi
lib.lifecycle = {}

---@param packId string
---@param config AdamantModpackLib.CoordinatorConfig
function lib.lifecycle.registerCoordinator(packId, config)
end

---@param packId string
---@param callback fun(reason: table): boolean
function lib.lifecycle.registerCoordinatorRebuild(packId, callback)
end

---@param packId string
---@param reason table
---@return boolean requested
function lib.lifecycle.requestCoordinatorRebuild(packId, reason)
end

---@param mutationBundle AdamantModpackLib.MutationBundle?
---@return AdamantModpackLib.MutationShape? shape
---@return AdamantModpackLib.MutationInfo info
function lib.lifecycle.inferMutation(mutationBundle)
end

---@param mutationBundle AdamantModpackLib.MutationBundle?
---@return boolean affects
function lib.lifecycle.affectsRunData(mutationBundle)
end

---@param def AdamantModpackLib.ModuleDefinition
---@param mutationBundle AdamantModpackLib.MutationBundle?
---@param store AdamantModpackLib.ManagedStore?
---@return boolean ok
---@return string? err
function lib.lifecycle.applyMutation(def, mutationBundle, store)
end

---@param def AdamantModpackLib.ModuleDefinition
---@param mutationBundle AdamantModpackLib.MutationBundle?
---@param store AdamantModpackLib.ManagedStore?
---@return boolean ok
---@return string? err
function lib.lifecycle.revertMutation(def, mutationBundle, store)
end

---@param def AdamantModpackLib.ModuleDefinition
---@param mutationBundle AdamantModpackLib.MutationBundle?
---@param store AdamantModpackLib.ManagedStore?
---@return boolean ok
---@return string? err
function lib.lifecycle.reapplyMutation(def, mutationBundle, store)
end

---@param def AdamantModpackLib.ModuleDefinition
---@param mutationBundle AdamantModpackLib.MutationBundle?
---@param store AdamantModpackLib.ManagedStore
---@return boolean ok
---@return string? err
function lib.lifecycle.applyOnLoad(def, mutationBundle, store)
end

---@param def AdamantModpackLib.ModuleDefinition
---@param settingsObserver fun(store: AdamantModpackLib.ManagedStore)?
---@param store AdamantModpackLib.ManagedStore
---@return boolean ok
---@return string? err
function lib.lifecycle.notifySettingsCommitted(def, settingsObserver, store)
end

---@param def AdamantModpackLib.ModuleDefinition
---@param session AdamantModpackLib.Session
---@return string[] mismatches
function lib.lifecycle.resyncSession(def, session)
end

---@param def AdamantModpackLib.ModuleDefinition
---@param mutationBundle AdamantModpackLib.MutationBundle?
---@param settingsObserver fun(store: AdamantModpackLib.ManagedStore)?
---@param store AdamantModpackLib.ManagedStore
---@param session AdamantModpackLib.Session
---@return boolean ok
---@return string? err
function lib.lifecycle.commitSession(def, mutationBundle, settingsObserver, store, session)
end

---@param def AdamantModpackLib.ModuleDefinition
---@param mutationBundle AdamantModpackLib.MutationBundle?
---@param store AdamantModpackLib.ManagedStore
---@param enabled boolean
---@return boolean ok
---@return string? err
function lib.lifecycle.setEnabled(def, mutationBundle, store, enabled)
end

---@param store AdamantModpackLib.ManagedStore
---@param enabled boolean
function lib.lifecycle.setDebugMode(store, enabled)
end

---@class AdamantModpackLib.MutationApi
---@type AdamantModpackLib.MutationApi
lib.mutation = {}

---@return fun(tbl: table, ...: any) backup
---@return fun() restore
function lib.mutation.createBackup()
end

---@return AdamantModpackLib.MutationPlan
function lib.mutation.createPlan()
end

---@class AdamantModpackLib.LoggingApi
---@type AdamantModpackLib.LoggingApi
lib.logging = {}

---@param packId string
---@param enabled boolean
---@param fmt string
function lib.logging.warnIf(packId, enabled, fmt, ...)
end

---@param packId string
---@param fmt string
function lib.logging.warn(packId, fmt, ...)
end

---@param name string
---@param enabled boolean
---@param fmt string
function lib.logging.logIf(name, enabled, fmt, ...)
end

---@class AdamantModpackLib.IntegrationsApi
---@type AdamantModpackLib.IntegrationsApi
lib.integrations = {}

---@param id string
---@param providerId string
---@param api table
---@return table api
function lib.integrations.register(id, providerId, api)
end

---@param id string
---@param providerId string
---@return boolean removed
function lib.integrations.unregister(id, providerId)
end

---@param providerId string
---@return integer count
function lib.integrations.unregisterProvider(providerId)
end

---@param id string
---@return table? api
---@return string? providerId
function lib.integrations.get(id)
end

---@param id string
---@param methodName string
---@param fallback any
---@return any result
---@return string? providerId
function lib.integrations.invoke(id, methodName, fallback, ...)
end

---@param id string
---@return AdamantModpackLib.IntegrationProvider[] providers
function lib.integrations.list(id)
end

---@type AdamantModpackLib.GameObjectApi
lib.gameObject = {}

---@param object table
---@param packId string
---@param moduleId string
---@param key string
---@param factory? fun(): table
---@return table state
function lib.gameObject.get(object, packId, moduleId, key, factory)
end

---@param object table
---@param packId string
---@param moduleId string
---@param key string
---@return table? state
function lib.gameObject.peek(object, packId, moduleId, key)
end

---@param object table
---@param packId string
---@param moduleId string
---@param key string
---@return boolean cleared
function lib.gameObject.clear(object, packId, moduleId, key)
end

---@class AdamantModpackLib.HudTextOverlayOpts
---@field id string Stable overlay id.
---@field componentName? string Explicit retained HUD component name.
---@field layout? table Hades II HUD component layout fields such as `RightOffset`, `BottomOffset`, `X`, and `Y`.
---@field textArgs? table Text format overrides.
---@field text? string|fun(): string
---@field visible? boolean|fun(): boolean

---@class AdamantModpackLib.HudTextOverlayHandle
---@field setText fun(text: string|fun(): string)
---@field setVisible fun(visible: boolean|fun(): boolean)
---@field refresh fun()
---@field unregister fun()

---@class AdamantModpackLib.StackedTextOverlayHandle : AdamantModpackLib.HudTextOverlayHandle
---@field refreshText fun()

---@class AdamantModpackLib.StackedRowOverlayHandle
---@field setColumnText fun(key: string, text: string|fun(): string): boolean
---@field setVisible fun(visible: boolean|fun(): boolean)
---@field refresh fun()
---@field refreshText fun()
---@field unregister fun()

---@class AdamantModpackLib.StackedTextOverlayOpts : AdamantModpackLib.HudTextOverlayOpts
---@field region? string Stack region name. Defaults to `middleRightStack`.
---@field order? integer Sort key within the region.
---@field textArgs? table Text style overrides. Stacked regions own size, justification, and offsets.

---@class AdamantModpackLib.StackedRowColumnOpts
---@field key? string Stable column key used by row handles.
---@field componentName? string Explicit retained HUD component name for this column.
---@field minWidth? number Reserved layout width used to keep following columns aligned; text is not clipped.
---@field justify? "Left"|"Center"|"Right" Column text justification. Defaults to the stack region justification.
---@field text? string|fun(): string
---@field textArgs? table Text style overrides. Stacked regions own `FontSize`, `VerticalJustification`, `OffsetX`, and `OffsetY`.

---@class AdamantModpackLib.StackedRowOverlayOpts
---@field id string Stable overlay row id.
---@field componentName? string Base retained HUD component name.
---@field region? string Stack region name. Defaults to `middleRightStack`.
---@field order? integer Sort key within the region.
---@field columnGap? number Reserved space between columns.
---@field columns AdamantModpackLib.StackedRowColumnOpts[] Ordered columns, declared left-to-right.
---@field visible? boolean|fun(): boolean

---@class AdamantModpackLib.OverlaysApi
---@field order table<string, integer> Shared overlay order bands.
---@type AdamantModpackLib.OverlaysApi
lib.overlays = {}

---@class AdamantModpackLib.UiSuppressionToken
---@field release fun()

---@param opts AdamantModpackLib.HudTextOverlayOpts
---@return AdamantModpackLib.HudTextOverlayHandle handle
function lib.overlays.registerHudText(opts)
end

---@param opts AdamantModpackLib.StackedTextOverlayOpts
---@return AdamantModpackLib.StackedTextOverlayHandle handle
function lib.overlays.registerStackedText(opts)
end

---@param opts AdamantModpackLib.StackedRowOverlayOpts
---@return AdamantModpackLib.StackedRowOverlayHandle handle
function lib.overlays.registerStackedRow(opts)
end

function lib.overlays.refreshHudText()
end

---@param regionName? string Optional stack region to refresh.
function lib.overlays.refreshStackedText(regionName)
end

---@return boolean suppressed
function lib.overlays.isUiSuppressed()
end

---@return AdamantModpackLib.UiSuppressionToken token
function lib.overlays.suppressForUi()
end

---@class AdamantModpackLib.HashingApi
---@type AdamantModpackLib.HashingApi
lib.hashing = {}

---Returns read-only prepared storage roots used for hash/profile metadata inspection.
---@param storage AdamantModpackLib.StorageSchema
---@return AdamantModpackLib.StorageNode[] roots
function lib.hashing.getRoots(storage)
end

---Returns a read-only prepared alias map used for hash/widget metadata inspection.
---@param storage AdamantModpackLib.StorageSchema
---@return table<string, AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode> aliases
function lib.hashing.getAliases(storage)
end

---@param node AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode?
---@param a any
---@param b any
---@return boolean equal
function lib.hashing.valuesEqual(node, a, b)
end

---@param node AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode
---@return number? width
function lib.hashing.getPackWidth(node)
end

---@param node AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode
---@param value any
---@return string? encoded
function lib.hashing.toHash(node, value)
end

---@param node AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode
---@param str string
---@return any value
function lib.hashing.fromHash(node, str)
end

---@param packed number?
---@param offset number?
---@param width number?
---@return number value
function lib.hashing.readPackedBits(packed, offset, width)
end

---@param packed number?
---@param offset number?
---@param width number?
---@param value number?
---@return number packedValue
function lib.hashing.writePackedBits(packed, offset, width, value)
end

---@class AdamantModpackLib.HooksApi
---@type AdamantModpackLib.HooksApi
lib.hooks = {}

---@param owner table
---@param path string
---@param keyOrHandler string|fun(base: function, ...: any): any
---@param maybeHandler? fun(base: function, ...: any): any
function lib.hooks.Wrap(owner, path, keyOrHandler, maybeHandler)
end

---@param owner table
---@param path string
---@param keyOrReplacement any
---@param maybeReplacement? any
function lib.hooks.Override(owner, path, keyOrReplacement, maybeReplacement)
end

---@class AdamantModpackLib.HooksContextApi
---@type AdamantModpackLib.HooksContextApi
lib.hooks.Context = {}

---@param owner table
---@param path string
---@param keyOrContext string|fun(...: any): any
---@param maybeContext? fun(...: any): any
function lib.hooks.Context.Wrap(owner, path, keyOrContext, maybeContext)
end

---@class AdamantModpackLib.ImguiHelpersApi
---@type AdamantModpackLib.ImguiHelpersApi
lib.imguiHelpers = {}
lib.imguiHelpers.ImGuiComboFlags = {}
lib.imguiHelpers.ImGuiCol = {}
lib.imguiHelpers.ImGuiTreeNodeFlags = {}

---@param color AdamantModpackLib.Color
---@return number r
---@return number g
---@return number b
---@return number a
function lib.imguiHelpers.unpackColor(color)
end

---@param ui table
---@param color AdamantModpackLib.Color
---@param text string
function lib.imguiHelpers.textColored(ui, color, text)
end

---@class AdamantModpackLib.WidgetsApi
---@type AdamantModpackLib.WidgetsApi
lib.widgets = {}

---@param imgui table
function lib.widgets.separator(imgui)
end

---@param imgui table
---@param text any
---@param opts? AdamantModpackLib.TextOpts
function lib.widgets.text(imgui, text, opts)
end

---@param imgui table
---@param label any
---@param opts? AdamantModpackLib.ButtonOpts
---@return boolean clicked
function lib.widgets.button(imgui, label, opts)
end

---@param imgui table
---@param id string|number
---@param label any
---@param opts? AdamantModpackLib.ConfirmButtonOpts
---@return boolean confirmed
function lib.widgets.confirmButton(imgui, id, label, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.InputTextOpts
---@return boolean changed
function lib.widgets.inputText(imgui, session, alias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.DropdownOpts
---@return boolean changed
function lib.widgets.dropdown(imgui, session, alias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.MappedDropdownOpts
---@return boolean changed
function lib.widgets.mappedDropdown(imgui, session, alias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.PackedDropdownOpts
---@return boolean changed
function lib.widgets.packedDropdown(imgui, session, alias, opts)
end

---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.PackedDropdownOpts|AdamantModpackLib.PackedRadioOpts
---@return string? selectedAlias Selected child alias when exactly one packed choice is active; otherwise `nil`.
function lib.widgets.getPackedChoiceAlias(session, alias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.RadioOpts
---@return boolean changed
function lib.widgets.radio(imgui, session, alias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.MappedRadioOpts
---@return boolean changed
function lib.widgets.mappedRadio(imgui, session, alias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.PackedRadioOpts
---@return boolean changed
function lib.widgets.packedRadio(imgui, session, alias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.StepperOpts
---@return boolean changed
function lib.widgets.stepper(imgui, session, alias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param minAlias string
---@param maxAlias string
---@param opts? AdamantModpackLib.SteppedRangeOpts
---@return boolean changed
function lib.widgets.steppedRange(imgui, session, minAlias, maxAlias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.CheckboxOpts
---@return boolean changed
function lib.widgets.checkbox(imgui, session, alias, opts)
end

---@param imgui table
---@param session AdamantModpackLib.Session
---@param alias string
---@param opts? AdamantModpackLib.PackedCheckboxListOpts
---@return boolean changed
function lib.widgets.packedCheckboxList(imgui, session, alias, opts)
end

---@class AdamantModpackLib.NavApi
---@type AdamantModpackLib.NavApi
lib.nav = {}

---@param imgui table
---@param opts? AdamantModpackLib.VerticalTabsOpts
---@return string|number? activeKey
function lib.nav.verticalTabs(imgui, opts)
end

---@param session AdamantModpackLib.Session?
---@param condition? string|AdamantModpackLib.VisibilityCondition
---@return boolean visible
function lib.nav.isVisible(session, condition)
end

---@type AdamantModpackLib.Config
lib.config = {}

---@param owner table?
---@param definition AdamantModpackLib.ModuleDefinition
---@return AdamantModpackLib.PreparedDefinition definition
function lib.prepareDefinition(owner, definition)
end

---@param modConfig table
---@param definition AdamantModpackLib.PreparedDefinition
---@return AdamantModpackLib.ManagedStore store
---@return AdamantModpackLib.Session session
function lib.createStore(modConfig, definition)
end

---@param storage AdamantModpackLib.StorageSchema
---@param session AdamantModpackLib.Session
---@param opts? AdamantModpackLib.ResetOpts
---@return boolean changed
---@return integer count
function lib.resetStorageToDefaults(storage, session, opts)
end

---@param opts AdamantModpackLib.ModuleCreateOpts
---@return AdamantModpackLib.AuthorHost host
---@return AdamantModpackLib.ManagedStore store
function lib.createModule(opts)
end

---@param opts AdamantModpackLib.ModuleHostOpts
---@return AdamantModpackLib.AuthorHost host
function lib.createModuleHost(opts)
end

---@param pluginGuid string Plugin guid used when creating the module host.
---@return AdamantModpackLib.StandaloneRuntime runtime
function lib.standaloneHost(pluginGuid)
end

---@param pluginGuid string?
---@return AdamantModpackLib.ModuleHost? host
function lib.getLiveModuleHost(pluginGuid)
end

---@param packId string?
---@return boolean coordinated
function lib.isModuleCoordinated(packId)
end

---@param store AdamantModpackLib.ManagedStore?
---@param packId string?
---@return boolean enabled
function lib.isModuleEnabled(store, packId)
end

return lib
