<div align="center">

<img src=".github/assets/logo.svg" width="100">

# luau-signals
Luau Port of [alien-signals](https://github.com/stackblitz/alien-signals) 👾 the lightest signal library

[![Get On Wally](https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/2214a2aca82cbdd386b946d759d3348705d7555e/Badges/Community/Package/link-wally.svg)](https://wally.run/package/maneetoo/luau-signals)
[![Get On Pesde](https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/2214a2aca82cbdd386b946d759d3348705d7555e/Badges/Community/Package/link-pesde.svg)](https://pesde.dev/packages/maneetoo/luausignals)
[![Documentation](https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/2214a2aca82cbdd386b946d759d3348705d7555e/Badges/Roblox-Styled/Original/link-documentation.svg)](https://maneetoo.github.io/luau-signals/)
[![GitHub Releases](https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/2214a2aca82cbdd386b946d759d3348705d7555e/Badges/Community/GitHub/link-github-releases.svg)](https://github.com/maneetoo/luau-signals/releases)
[![Roblox OSS Discord Server](https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/2214a2aca82cbdd386b946d759d3348705d7555e/Badges/Community/Discord/link-discord-roblox-oss.svg)](https://discord.gg/vtUJdtUK2J)
[![Changelog](https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/2214a2aca82cbdd386b946d759d3348705d7555e/Badges/Roblox-Styled/Original/link-changelog.svg)](https://github.com/maneetoo/luau-signals/blob/main/CHANGELOG.md)
[![My Works](https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/2214a2aca82cbdd386b946d759d3348705d7555e/Badges/Roblox-Styled/Original/link-my-works.svg)](https://github.com/maneetoo/)

</div>

## About

[`luau-signals`](https://github.com/maneetoo/luau-signals) is a faithful Luau port of [`alien-signals`](https://github.com/stackblitz/alien-signals), a push-pull reactive signals library whose core algorithm has been adopted by [Vue 3.6](https://github.com/vuejs/core/tree/minor). It brings the same `signal` / `computed` / `effect` / `effectScope` primitives to [`Luau 🦭`](https://luau.org/) and Roblox, with the same lazy, glitch-free semantics: signals hold state, computed values are derived lazily, effects react to changes, and scopes let you dispose whole component trees at once.

The port preserves the upstream constraints that make [`alien-signals`](https://github.com/stackblitz/alien-signals) fast. Writes push flags through the graph while reads pull fresh values only when needed, so an unobserved `computed` chain is never touched. The hot path uses linked lists and plain arrays only — no `Set`, no `Map`, no dynamic fields — and `propagate`, `checkDirty`, and `shallowPropagate` are iterative rather than recursive. Each `Link` is seven flat fields with no hidden allocation.

What is specific to Luau is mostly adaptation. Signals, computed values, and effects are callable tables — the node *is* the API — so no closure or wrapper is allocated per node. Node kinds are identified by metatable identity instead of `'getter' in node` checks, which cannot be ported literally because a [`nil`](https://luau.org/types/basic-types/#builtin-types)-valued field does not exist in Luau; this also makes `signal(nil)` unambiguous. All flag operations go through [`bit32`](https://luau.org/library/#bit32-library) (Luau has no native `&`, `|`, `~` for numbers), with masks precomputed and `bit32.btest` used for "any of these bits set". Every `finally` block from the original is reproduced with `pcall` plus a re-`error`, including state restoration on thrown errors, and the linked-list stack is replaced with a plain array plus a depth counter for cheaper push/pop and safe reentrancy.

## Getting Started

Please follow the documentation [here](https://maneetoo.github.io/luau-signals/)!

## Benchmarks

Currently, `Vide` is the most popular and frequently chosen reactivity library for Luau, thanks to its speed and an API largely derived from `Solid.js` - which is why it was selected for comparison with `luau-signals`. Furthermore, unlike `Fusion`, `Vide` is currently being actively maintained and updated.

| Scenario | `signals` | `vide` | Winner | Rupture |
|:--|--:|--:|:--|--:|
| `batch: 10 writes, batched` | 1.86 µs | 1.89 µs | ≈ equal | ~1.0× |
| `batch: 10 writes, no batch` | **10.2 µs** | 12.0 µs | 🟢 signals | 1.17× |
| `derive: 1 src → 50 derives → 1 effect` | **12.4 µs** | 17.3 µs | 🟢 signals | **1.39×** |
| `derive: chain depth 10` | **2.36 µs** | 2.53 µs | 🟢 signals | 1.07× |
| `derive: chain depth 10 → effect` | **2.41 µs** | 2.60 µs | 🟢 signals | 1.08× |
| `derive: chain depth 40` | **7.79 µs** | 9.50 µs | 🟢 signals | 1.22× |
| `derive: cutoff (value unchanged)` | 529 ns | **308 ns** | 🔴 vide | **1.72×*** |
| `derive: diamond → effect` | 1.17 µs | 1.11 µs | ≈ equal | ~1.0× |
| `derive: unobserved (lazy vs eager)` | **137 ns** | 2.44 µs | 🟢 signals | **17.83×** |
| `derive: write + read (depth 1)` | 377 ns | 371 ns | ≈ equal | ~1.0× |
| `effect: create + dispose` | 1.14 µs | 1.11 µs | ≈ equal | ~1.0× |
| `effect: dynamic deps (branch toggle)` | 681 ns | **421 ns** | 🔴 vide | **1.62×*** |
| `effect: rerun with cleanup` | 465 ns | 453 ns | ≈ equal | ~1.0× |
| `graph: 20 src + 20 derive` | **18.8 µs** | 21.2 µs | 🟢 signals | 1.12× |
| `mixed: 30 src, 60 derive, 15 effects` | **2.68 µs** | 9.90 µs | 🟢 signals | **3.69×** |
| `source: create` | 110 ns | 106 ns | ≈ equal | ~1.0× |
| `source: read (untracked)` | **37 ns** | 56 ns | 🟢 signals | **1.52×** |
| `source: write, no subscribers` | **46 ns** | 81 ns | 🟢 signals | **1.76×** |
| `source: write, same value` | 37 ns | 39 ns | ≈ equal | ~1.0× |
| `write → 1 effect` | 419 ns | **317 ns** | 🔴 vide | **1.32×*** |
| `write → 10 effects` | **2.21 µs** | 2.62 µs | 🟢 signals | 1.18× |
| `write → 100 effects` | **18.9 µs** | 25.2 µs | 🟢 signals | **1.34×** |

`*` - Scenarios where Vide excels - essentially its "natural habitat" - are those involving a single action (e.g. write operation resulting in one effect) or situations where nothing changes following an update. In such cases, its "eager" update model incurs lower computational overhead. For larger-scale tasks, `luau-signals` is a better choice.

## Code Sample
```luau
const luau_signals = require './luau-signals'
const signal, computed, effect, effectScope, startBatch, endBatch =
    luau_signals.signal, luau_signals.computed, luau_signals.effect, luau_signals.effectScope, luau_signals.startBatch, luau_signals.endBatch

const price, qty = signal(100), signal(2)
const total = computed(function()
    return price() * qty()
end)

-- effectScope — groups effects for collective disposal
const dispose = effectScope(function()
    -- effect — reacts to changes
    effect(function()
        print(`Total: { total() }`)
    end)
end) -- Output: `Total: 200`

price(150) -- Output: `Total: 300`

-- batch — multiple changes → a single effect restart
startBatch()
price(200)
qty(5)
endBatch() -- Output: `Total: 1000`

dispose() -- Unsubscribing from the entire scope
price(999) -- Nothing is being output
```

## Attribution

The core algorithm is by [Johnson Chu](https://github.com/johnsoncodehk) ([alien-signals](https://github.com/stackblitz/alien-signals), MIT).

[luau-signals](https://github.com/maneetoo/luau-signals) is licensed under [MIT License](https://github.com/maneetoo/luau-signals/blob/main/LICENSE)