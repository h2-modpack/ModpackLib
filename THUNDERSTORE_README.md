# adamant-ModpackLib

Shared support library for Hades II mods and modpacks built on the adamant stack.

## What This Is

This package provides common runtime helpers used by other mods. It is normally installed as a dependency and is not meant to be opened or configured by itself.

## How It Helps

Mods use this library for shared configuration handling, in-game UI helpers, profile/hash support, hot-reload-safe hooks, and runtime safety around gameplay changes.

Keeping this logic in one library lets dependent mods avoid copying the same support code.

## Gameplay Impact

This package does not add gameplay content by itself.

It can affect gameplay only through another installed mod that depends on it. If no dependent mod is installed, it should not change your run.

## Technical Info

Developer documentation and source code are available on GitHub:

- https://github.com/h2-modpack/adamant-ModpackLib
