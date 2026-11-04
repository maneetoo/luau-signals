# Getting Started

This page covers installation for the three common ways to consume `luau-signals` in a Roblox project, then walks through a complete first program.

## Requirements

- Roblox place, with the library reachable through `ReplicatedStorage` (any tool below does this for you)
- Luau — the library is strict-mode pure Luau with no Roblox instance dependencies, so it also runs anywhere Luau runs (Lune, `luau` CLI, etc.)

## Installation

### Wally

Add the package to your `wally.toml`:

```toml
[dependencies]
LuauSignals = "manee/luau-signals@0.1.0"
```

::: tip
Sync the `Packages` folder into `ReplicatedStorage` with Rojo (the standard Wally workflow) so it is visible from both client and server scripts. The library is realm-agnostic — `shared` in its manifest — so one copy serves everyone.
:::

### pesde

Add the package to your `pesde.toml`:

```toml
[dependencies]
luausignals = { name = "maneetoo/luau_signals", version = "^0.1.0" }
```

::: tip
The exact instance path depends on your project's `pesde.toml`/Rojo mapping — check where pesde places `luau-signals` in your tree and require it from there.
:::

### Manual / Rojo

Copy `src/` into your project and map it. With Rojo, the repository's own `default.project.json` shows the intended layout:

```json
{
  "name": "luau-signals",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "luau-signals": { "$path": "src/" }
    }
  }
}
```

### Everything else

Since the whole library is two `.luau` files with no external dependencies, dropping `src/init.luau` and `src/system.luau` into any ModuleScript folder works too. Keep the two files side by side — `init.luau` requires `./system` (via `@self/system`, i.e. a sibling named `system.luau` in the same folder).

::: warning
Do not rename `system.luau` or move it away from `init.luau`: the internal require `'@self/system'` resolves to a sibling module of the entry point.
:::

## Your first program

Create a `ModuleScript`-based controller or a plain script wherever you need reactivity. The smallest useful example — a health readout:

```luau
--!strict
local signals = require(ReplicatedStorage["luau-signals"])
local signal, computed, effect = signals.signal, signals.computed, signals.effect

local maxHealth = signal(100)
local currentHealth = signal(100)

local healthFraction = computed(function()
    return currentHealth() / maxHealth()
end)

effect(function()
    print(`Health: {math.floor(healthFraction() * 100)}%`)
end) -- Output: Health: 100%

currentHealth(35) -- Output: Health: 35%
maxHealth(200)    -- Output: Health: 17%
```

Walk through what happened:

1. `effect` runs its callback immediately (the first run establishes what the effect *tracks*).
2. The callback read `healthFraction`, which read `currentHealth` and `maxHealth` — the effect is now subscribed to the whole chain.
3. Writing `currentHealth` marked `healthFraction` stale, queued the effect, and re-ran it — the getter recomputed once.
4. Writing `maxHealth` did the same, through the same chain.

## Effect cleanup

An effect callback may return a cleanup function, which runs before the *next* restart of that effect (and when the effect is disposed):

```luau
local target = signal(workspace.Door)

effect(function()
    local door = target()
    local conn = door.Touched:Connect(function()
        print("touched")
    end)
    return function()
        conn:Disconnect()
    end
end)
```

Every time `target` changes, the previous connection is disconnected before the callback reruns — no accumulating connections.

::: warning
The returned value is used as a cleanup only if it is a function. Returning anything else (a number, a table, `nil`) is fine and simply means "no cleanup".
:::

## Batching writes

When several writes belong together, wrap them in a batch so effects restart once with the final values:

```luau
local signals = require(ReplicatedStorage["luau-signals"])
local signal, effect, startBatch, endBatch =
    signals.signal, signals.effect, signals.startBatch, signals.endBatch

local x, y = signal(1), signal(1)

effect(function()
    print(`x={x()}, y={y()}`)
end) -- Output: x=1, y=1

startBatch()
x(10)
y(20)
endBatch() -- Output (once): x=10, y=20
```

Without the batch, the effect would run twice — once per write.

## Testing it in Studio

1. Serve your project (`rojo serve` if you use Rojo) and connect from Studio.
2. Put the script above in `ServerScriptService` (or `StarterPlayerScripts` — reactivity is not container-specific).
3. Press Play; check Output for the printed lines.
4. To see updates live, write to a signal from another event (a `Touched` handler, a RemoteEvent, a heartbeat counter) and watch the effect re-run.

## Next steps

- [Signals & Effects](./signals-and-effects) — how tracking works, dynamic dependencies, recursion protection
- [Computed Values](./computed) — caching and the previous-value argument
- [Effect Scopes](./effect-scopes) — group effects for one-call disposal
- [API Reference](/api/) — the full surface
