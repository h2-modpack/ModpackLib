local internal = AdamantModpackLib_Internal
local shared = internal.shared

shared.fieldRegistry = shared.fieldRegistry or {}

import 'field_registry/shared.lua'
import 'field_registry/storage.lua'
import 'field_registry/widgets/init.lua'
import 'field_registry/layouts.lua'
import 'field_registry/ui.lua'

public.registry = public.registry or {}
public.registry.storage = shared.StorageTypes
public.registry.widgets = shared.WidgetTypes
public.registry.widgetHelpers = shared.WidgetHelpers
public.registry.layouts = shared.LayoutTypes
public.registry.validate = shared.fieldRegistry.validateRegistries
public.registry.validate()
