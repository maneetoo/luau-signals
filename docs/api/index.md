# API Overview

The whole library is two files, one module, one require. Everything below is exported from the module returned by requiring `luau-signals`:

```luau
local signals = require(ReplicatedStorage["luau-signals"])
```

## The full surface

| Function | Kind | Purpose |
|---|---|---|
| [`signal`](./signal) | creator | Create a reactive value |
| [`computed`](./computed) | creator | Create a lazy derived value |
| [`effect`](./effect) | creator | Run a callback when its reads change |
| [`effectScope`](./effect-scope) | creator | Group effects for collective disposal |
| [`trigger`](./trigger) | action | Re-run observers without changing a value |
| [`startBatch`](./batching) | action | Begin a write batch |
| [`endBatch`](./batching) | action | End a batch; flush when depth hits 0 |
| [`getBatchDepth`](./batching) | introspection | Current batch nesting level |
| [`isSignal`](./type-guards) | guard | Is the value a signal node? |
| [`isComputed`](./type-guards) | guard | Is the value a computed node? |
| [`isEffect`](./type-guards) | guard | Is the value an effect node? |
| [`isEffectScope`](./type-guards) | guard | Is the value a scope node? |
| [`getActiveSub`](./advanced) | advanced | The currently-tracking node, if any |
| [`setActiveSub`](./advanced) | advanced | Install/restore the tracking subscriber |

The module table is **frozen** — it cannot be patched or extended from outside. Each node's metatable is frozen too, so a signal's read/write dispatch can never be swapped.

## Design invariants

These hold for every function below and are worth internalizing before using the advanced ones:

- **Nodes are callable tables.** A signal *is* its read/write function; an effect node *is* its disposer. No wrapper objects, no `.get()`/`.set()`.
- **Reads track, writes propagate.** Calling a signal/computed inside a running effect or getter subscribes the runner. Calling with an argument writes.
- **One argument is a write — even `nil`.** Reads take zero arguments. Argument counting uses `select('#', ...)`, so an explicit `nil` is unambiguously a write of `nil`.
- **Effects run from a queue, never inline.** A write marks and queues; the flush (at the write site, or at `endBatch`) runs effects in parent-before-child order.
- **Computeds are lazy and cutoff-aware.** A getter runs only when a subscriber reads it, and an unchanged result stops propagation.
- **State survives user errors.** The library restores its internal state (`activeSub`, `runDepth`, the queue) via `pcall` + re-`error` in every guarded region. The one caller-owned piece is `batchDepth`.

## Types

The library is `--!strict` throughout. Where the upstream TypeScript is generic (`Signal<T>`), the Luau port uses `any` on the node-facing types — Luau's type system cannot describe a callable table, so `signal(1)`, `signal("x")` and `signal(nil)` are all the same type to the checker. Your own code can still be fully typed around the values it puts in and takes out:

```luau
--!strict
local signals = require(ReplicatedStorage["luau-signals"])
local signal, computed, effect = signals.signal, signals.computed, signals.effect

local hp = signal(100) :: any
-- read/write as `any`; keep your own types at the boundaries:
local function applyDamage(current: number, amount: number): number
    return math.max(0, current - amount)
end
```

For the internal graph types (`ReactiveNode`, `Link`, `ReactiveFlags`), see [Advanced](./advanced) — they are exported from `src/system.luau` and used by `createReactiveSystem`, which is how the node layer and the graph layer are composed.

## Conventions used in this reference

- **Signature blocks** show the function as the module exposes it, plus the callable-table calling convention where relevant.
- **Behavior** sections describe exact semantics: what is tracked, what is deferred, what throws.
- **Errors** sections note what happens when a callback throws — the library's `pcall`-restore guarantee applies everywhere.
