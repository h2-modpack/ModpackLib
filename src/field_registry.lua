local internal = AdamantModpackLib_Internal
local shared = internal.shared

shared.fieldRegistry = shared.fieldRegistry or {}

import 'field_registry/shared.lua'
import 'field_registry/storage.lua'
import 'field_registry/widgets.lua'
import 'field_registry/layouts.lua'
import 'field_registry/ui.lua'

public.StorageTypes = shared.StorageTypes
public.WidgetTypes = shared.WidgetTypes
public.LayoutTypes = shared.LayoutTypes
public.validateRegistries()
