# Anime Ragdoll Physics

A Roblox ragdoll physics sandbox with anime fighters, with its source managed through [Rojo](https://rojo.space).

Play it on Roblox: https://www.roblox.com/games/125248938595050

## What's here

- `src/ServerScriptService` - server game logic, combat and shop services
- `src/ReplicatedStorage` - shared modules (combat, perks, emotes, shop catalog)
- `src/StarterPlayerScripts` - client scripts and UI
- `src/ServerStorage` - kits, map generators and tooling
- `default.project.json` - Rojo project file

A few models are stored as `.rbxm` because Rojo can't represent them as plain files. The world map and terrain in Workspace are not included in this repo, the real redeem codes have been replaced with a placeholder, and old backup copies of scripts are left out.

## Using it

```
rojo build -o AnimeRagdollPhysics.rbxlx
```

Or run `rojo serve` and connect from the Rojo plugin in Studio.
