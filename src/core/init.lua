local internal = AdamantModpackLib_Internal
local shared = internal.shared
local StorageTypes = shared.StorageTypes
local chalk = shared.chalk
local _mutationRuntime = shared.mutationRuntime or setmetatable({}, { __mode = "k" })
shared.mutationRuntime = _mutationRuntime

import 'core/coordinators.lua'
import 'core/accessors.lua'
import 'core/definitions.lua'
import 'core/mutations.lua'
import 'core/store.lua'
import 'core/standalone.lua'
