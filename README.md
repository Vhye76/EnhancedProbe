# EnhancedProbe

A standalone World of Warcraft addon that captures machine-diffable snapshots of the client's Lua-visible API surface. Run the same battery on two builds and diff the output to see exactly what was added, removed, or changed.

## Captures

- Census: every loose global by type, every C_* namespace and its function names, the Enum table tree
- Docs: the in-client API documentation tree, serialized in full
- Secrets: per-field aura read behavior, recorded across execution contexts
- Frames: keys and methods present on aura-related frames and mixins

## Usage

Install the EnhancedProbe folder into Interface/AddOns, then:

```
/eprobe              run the full battery
/eprobe <name>       run a single probe (census, docs, frames, secrets)
/eprobe show         show the latest capture in a copyable window
/eprobe list, help   list commands and registered probes
/eprobe wipe         clear the stored capture
```

The secrets probe also arms deferred captures that record again when your auras change and when the camera zooms, in and out of combat. Trigger each before reloading for a complete matrix.

Only the most recent capture is kept. Reload the UI (or log out) to flush it to disk, then collect the file from WTF/Account/ACCOUNT/SavedVariables/EnhancedProbe.lua.

## Diffing builds

Capture on each build, collecting one SavedVariables file per build (a live baseline and the PTR), then:

```
luajit tools/EnhancedDiff.lua baseline.lua ptr.lua
```

It loads both files directly and reports only what changed, secrets first: aura fields whose secret-tagging or operation behavior flipped, globals and C_* members added or removed or retyped, enum value changes, frame methods, and API documentation signature changes.
