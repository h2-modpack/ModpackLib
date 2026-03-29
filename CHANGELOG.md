# Changelog

## [Unreleased]

### Added
- Initial release of adamant-ModpackLib shared library
- `createBackupSystem()` - isolated backup/revert with first-call-only semantics
- `createSpecialState()` - managed `specialState` object for special modules
- `standaloneUI()` - menu-bar toggle callback for regular modules running without Core
- `isEnabled()` - checks module config and coordinator master toggle
- `warn()` - debug-guarded framework diagnostic print
- `log()` - caller-gated module trace print
- `readPath()` / `writePath()` - string and table-path accessors for nested config keys
- `drawField()` - ImGui widget renderer delegating to the FieldTypes registry
- `validateSchema()` - declaration-time field descriptor validation
- `captureSpecialConfigSnapshot()` / `warnIfSpecialConfigBypassedState()` - debug helpers for detecting schema-backed config writes outside `public.specialState`
- FieldTypes registry with `checkbox`, `dropdown`, and `radio` types
- Luacheck linting on push/PR
- Unit tests for field types, path helpers, validation, backup system, special state, and isEnabled (LuaUnit, Lua 5.1)
- Branch protection on `main` requiring CI pass

[Unreleased]:
