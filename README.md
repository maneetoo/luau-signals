<div align="center">

<img src=".github/assets/logo.svg" width="100">

# luau-signals
Luau Port of [alien-signals](https://github.com/stackblitz/alien-signals) 👾 the lightest signal library

[![Get On Wally](https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/2214a2aca82cbdd386b946d759d3348705d7555e/Badges/Community/Package/link-wally.svg)](https://wally.run/package/maneetoo/luau-signals)
[![Get On Pesde](https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/2214a2aca82cbdd386b946d759d3348705d7555e/Badges/Community/Package/link-pesde.svg)](https://pesde.dev/packages/maneetoo/luau_signals)
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

<details>
	<summary>Comparing with Vide</summary>

| Scenario | `signals` | `vide` | Winner | Rupture |
|:--|--:|--:|:--|--:|
| `batch: 10 writes, batched` | 2.15 µs | 2.1 µs | ≈ equal | ~1.0× |
| `batch: 10 writes, no batch` | **11.8 µs** | 14.7 µs | 🟢 signals | 1.24× |
| `derive: 1 src → 50 derives → 1 effect` | **13.4 µs** | 20.6 µs | 🟢 signals | **1.54×** |
| `derive: chain depth 10` | **2.48 µs** | 3.03 µs | 🟢 signals | 1.22× |
| `derive: chain depth 10 → effect` | 2.8 µs | 2.9 µs | ≈ equal | ~1.0× |
| `derive: chain depth 40` | **9.11 µs** | 11.6 µs | 🟢 signals | 1.27× |
| `derive: cutoff (value unchanged)` | 560 ns | **381 ns** | 🔴 vide | **1.47×*** |
| `derive: diamond → effect` | 1.22 µs | 1.28 µs | ≈ equal | ~1.0× |
| `derive: unobserved (lazy vs eager)` | **141 ns** | 2.56 µs | 🟢 signals | **18.18×** |
| `derive: write + read (depth 1)` | 452 ns | 437 ns | ≈ equal | ~1.0× |
| `effect: create + dispose` | 1.14 µs | 1.11 µs | ≈ equal | ~1.0× |
| `effect: dynamic deps (branch toggle)` | 708 ns | **515 ns** | 🔴 vide | **1.37×*** |
| `effect: rerun with cleanup` | 502 ns | 502 ns | ≈ equal | ~1.0× |
| `graph: 20 src + 20 derive` | **18.8 µs** | 21.9 µs | 🟢 signals | 1.17× |
| `mixed: 30 src, 60 derive, 15 effects` | **2.73 µs** | 11 µs | 🟢 signals | **4.04×** |
| `source: create` | 106 ns | **100 ns** | 🔴 vide | 1.06×* |
| `source: read (untracked)` | **39 ns** | 59 ns | 🟢 signals | **1.52×** |
| `source: write, no subscribers` | **53 ns** | 86 ns | 🟢 signals | **1.63×** |
| `source: write, same value` | 40 ns | 41 ns | ≈ equal | ~1.0× |
| `write → 1 effect` | 409 ns | **316 ns** | 🔴 vide | 1.30×* |
| `write → 10 effects` | **2.26 µs** | 3.24 µs | 🟢 signals | **1.43×** |
| `write → 100 effects` | **18.3 µs** | 24.4 µs | 🟢 signals | **1.33×** |

`*` - Scenarios where Vide excels - essentially its "natural habitat" - are those involving a single action (e.g. write operation resulting in one effect) or situations where nothing changes following an update. In such cases, its "eager" update model incurs lower computational overhead. For larger-scale tasks, `luau-signals` is a better choice.
</details>

<details>
	<summary>Comparing with Fluid (fork of Vide)</summary>

| Scenario | `signals` | `fluid` | Winner | Rupture |
|:--|--:|--:|:--|--:|
| `batch: 10 writes, batched` | **2.15 µs** | 53.31 µs | 🟢 signals | **24.80×** |
| `batch: 10 writes, no batch` | **11.81 µs** | 54.46 µs | 🟢 signals | **4.61×** |
| `derive: 1 src → 50 derives → 1 effect` | **13.40 µs** | 574.68 µs | 🟢 signals | **42.89×** |
| `derive: chain depth 10` | **2.48 µs** | 8.52 µs | 🟢 signals | **3.44×** |
| `derive: chain depth 10 → effect` | **2.80 µs** | 11.26 µs | 🟢 signals | **4.02×** |
| `derive: chain depth 40` | **9.11 µs** | 36.91 µs | 🟢 signals | **4.05×** |
| `derive: cutoff (value unchanged)` | **560.2 ns** | 1.56 µs | 🟢 signals | **2.78×** |
| `derive: diamond → effect` | **1.22 µs** | 4.54 µs | 🟢 signals | **3.72×** |
| `derive: unobserved (lazy vs eager)` | **140.8 ns** | 294.8 ns | 🟢 signals | **2.09×** |
| `derive: write + read (depth 1)` | **451.7 ns** | 1.27 µs | 🟢 signals | **2.81×** |
| `effect: create + dispose` | **1.14 µs** | 2.37 µs | 🟢 signals | **2.08×** |
| `effect: dynamic deps (branch toggle)` | **707.5 ns** | 1.77 µs | 🟢 signals | **2.50×** |
| `effect: rerun with cleanup` | **501.8 ns** | 1.53 µs | 🟢 signals | **3.05×** |
| `graph: 20 src + 20 derive` | **18.77 µs** | 43.14 µs | 🟢 signals | **2.30×** |
| `mixed: 30 src, 60 derive, 15 effects` | **2.73 µs** | 13.03 µs | 🟢 signals | **4.77×** |
| `source: create` | **105.8 ns** | 208.1 ns | 🟢 signals | **1.97×** |
| `source: read (untracked)` | **38.8 ns** | 74.2 ns | 🟢 signals | **1.91×** |
| `source: write, no subscribers` | **52.6 ns** | 137.6 ns | 🟢 signals | **2.62×** |
| `source: write, same value (no-op)` | **40.1 ns** | 71.1 ns | 🟢 signals | **1.77×** |
| `write → 1 effect` | **409.4 ns** | 1.24 µs | 🟢 signals | **3.03×** |
| `write → 10 effects` | **2.26 µs** | 11.65 µs | 🟢 signals | **5.15×** |
| `write → 100 effects` | **18.34 µs** | 115.79 µs | 🟢 signals | **6.31×** |
</details>

<details>
	<summary>Comparing with Flux (@kohltastrophe)</summary>

| Scenario | `signals` | `flux` | Winner | Rupture |
|:--|--:|--:|:--|--:|
| `batch: 10 writes, batched` | 2.15 µs | **1.86 µs** | 🔴 flux | 1.16× |
| `batch: 10 writes, no batch` | 11.81 µs | **10.42 µs** | 🔴 flux | 1.13× |
| `derive: 1 src → 50 derives → 1 effect` | 13.40 µs | **12.48 µs** | 🔴 flux | 1.07× |
| `derive: chain depth 10` | 2.48 µs | **2.27 µs** | 🔴 flux | 1.09× |
| `derive: chain depth 10 → effect` | **2.80 µs** | 3.06 µs | 🟢 signals | 1.09× |
| `derive: chain depth 40` | 9.11 µs | 8.75 µs | ≈ equal | ~1.0× |
| `derive: cutoff (value unchanged)` | 560.2 ns | 544.1 ns | ≈ equal | ~1.0× |
| `derive: diamond → effect` | 1.22 µs | **1.12 µs** | 🔴 flux | 1.09× |
| `derive: unobserved (lazy vs eager)` | **140.8 ns** | 168.8 ns | 🟢 signals | 1.20× |
| `derive: write + read (depth 1)` | 451.7 ns | **406.1 ns** | 🔴 flux | 1.11× |
| `effect: create + dispose` | **1.14 µs** | 1.27 µs | 🟢 signals | 1.11× |
| `effect: dynamic deps (branch toggle)` | **707.5 ns** | 922.9 ns | 🟢 signals | **1.30×** |
| `effect: rerun with cleanup` | 501.8 ns | **471.0 ns** | 🔴 flux | 1.07× |
| `graph: 20 src + 20 derive` | 18.77 µs | **17.58 µs** | 🔴 flux | 1.07× |
| `mixed: 30 src, 60 derive, 15 effects` | **2.73 µs** | 2.87 µs | 🟢 signals | 1.05× |
| `source: create` | 105.8 ns | 101.7 ns | ≈ equal | ~1.0× |
| `source: read (untracked)` | **38.8 ns** | 41.3 ns | 🟢 signals | 1.06× |
| `source: write, no subscribers` | 52.6 ns | 52.1 ns | ≈ equal | ~1.0× |
| `source: write, same value (no-op)` | 40.1 ns | 41.2 ns | ≈ equal | ~1.0× |
| `write → 1 effect` | **409.4 ns** | 455.2 ns | 🟢 signals | 1.11× |
| `write → 10 effects` | **2.26 µs** | 2.38 µs | 🟢 signals | 1.05× |
| `write → 100 effects` | **18.34 µs** | 19.49 µs | 🟢 signals | 1.06× |

`flux` is close to `signals` — within 1.05–1.3× on every scenario, unlike `fluid` (2–43× slower). In this run `signals` is ahead in 9 scenarios, `flux` in 8, and 5 are within noise. The largest gaps are `effect: dynamic deps (branch toggle)` (1.30× in favour of `signals`) and `batch: 10 writes, batched` (1.16× in favour of `flux`). This suggests `flux` also uses a lazy push-pull model with similar overhead; the difference is likely in constant factors (`getmetatable` vs internal tags, closure handling, queue flush strategy) rather than architecture.
</details>


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