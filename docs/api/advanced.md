# Advanced

```luau
getActiveSub() -> ReactiveNode?
setActiveSub(sub: ReactiveNode?) -> ReactiveNode?
```

The two subscriber-stack functions the effect machinery itself uses. They are exported for advanced patterns — untracked reads, custom subscriber nodes, library integrations. Most code should never need them: prefer [batches](./batching) for coalesced writes and `trigger` for forced refreshes.

## getActiveSub

Returns the node currently tracking reads — the effect whose callback is running, the computed whose getter is running, the scope whose function is running, or `nil` when no tracking context is active.

```luau
local function tracking()
    return getActiveSub() ~= nil
end

effect(function()
    print(tracking()) -- true
end)

print(tracking()) -- false (plain code)
```

Its primary consumer is the library's own test suite, which asserts `getActiveSub() == nil` after every test to prove no subscriber leaked.

## setActiveSub

Installs `sub` as the active tracking node and **returns the previous one**. The return value is the restore handle — the contract is always save/restore, never fire-and-forget:

```luau
const prev = setActiveSub(nil)
local value = someSignal() -- untracked: reads link to nothing
setActiveSub(prev)          -- tracking restored
```

### Untracked reads

The canonical pattern — read a value inside an effect without subscribing to it:

```luau
effect(function()
    const prev = setActiveSub(nil)
    local snapshot = inventory() -- logged, not tracked
    setActiveSub(prev)

    print(`[{os.clock()}] inventory snapshot: {snapshot}`)
    -- reads after the restore are tracked normally:
    local shown = visibleCount()
    label.Text = `{shown} items`
end)
```

The effect restarts only when `visibleCount` changes — inventory writes alone do not wake it.

::: warning
An unbalanced `setActiveSub` (missing restore, or restoring a stale value across an effect boundary) corrupts tracking for everything downstream. Wrap it in `pcall` if the code between can throw:

```luau
const prev = setActiveSub(nil)
local ok, value = pcall(function() return someSignal() end)
setActiveSub(prev) -- runs even on error
if not ok then error(value, 0) end
```

The library itself restores `activeSub` through every user-callback boundary (getter, effect, cleanup, scope, trigger, flush) — `getActiveSub()` is always the right node when your code runs from those entry points.
:::

### Custom subscriber nodes

`setActiveSub` accepts any table shaped like a `ReactiveNode` — the five bookkeeping fields. The library's own [`trigger`](./trigger) builds its throwaway subscriber this way. You can do the same to collect dependencies for your own purposes:

```luau
-- minimal collector: same shape `trigger` uses
local function collectDeps(fn: () -> ()): { any }
    local collected = {}
    local node = {
        deps = nil, depsTail = nil, subs = nil, subsTail = nil,
        flags = 0,
    }
    const prev = setActiveSub(node)
    fn()
    setActiveSub(prev)
    -- node.deps now links everything fn read — walk it:
    local link = node.deps
    while link ~= nil do
        table.insert(collected, link.dep)
        link = link.nextDep
    end
    return collected
end
```

::: danger
A custom node stays **linked into the graph** until you unlink it — leave one installed without cleanup and you have a permanent subscriber the system will try to notify. If you experiment with this, copy `trigger`'s unlink loop (or just call `trigger` and let it do the bookkeeping).
:::

## The system module

One layer below the public API sits the graph engine, in `src/system.luau`. It is not exported from the package's entry point, but the file is plain Luau and can be required directly by tooling that wants the primitives:

```luau
-- inside the package's own folder (sibling require):
const system = require '@self/system'
```

| Export | Purpose |
|---|---|
| `system.createReactiveSystem(t)` | Factory: takes `update`/`notify`/`unwatched` callbacks, returns `link`, `unlink`, `propagate`, `checkDirty`, `shallowPropagate` |
| `system.ReactiveNode` | Type: the 5-field node shape |
| `system.Link` | Type: the 7-field link shape |
| `system.ReactiveFlags` | Frozen table of flag values (`None`, `Mutable`, `Watching`, `RecursedCheck`, `Recursed`, `Dirty`, `Pending`) |

`createReactiveSystem` is the seam between the two files: `src/init.luau` provides the node-layer callbacks (what "update" means for a signal vs a computed, what "notify" does to the queue, what "unwatched" does per kind) and receives the graph operations back. This is the same composition as the upstream's `system.ts`/`index.ts` split.

::: tip
`ReactiveFlags` values are useful when building debugging tools that inspect node state:

```luau
local Dirty = system.ReactiveFlags.Dirty

local function isDirty(node: any): boolean
    return bit32.btest(node.flags, Dirty)
end
```
:::

## Graph-shape rules for custom nodes

If you build a custom subscriber, it must honor the invariants the engine relies on:

- the five `ReactiveNode` fields present (explicit `nil`s written, so the table's hash part is allocated once),
- `flags` kept in sync with the flag semantics — a node that is `Watching` may be queued by `notify`, so a custom node meant to never run should not carry that flag,
- no metatable unless you want `unwatched`'s dispatch to treat it as one of the four kinds (a metatable-less node is treated as a scope).

## Threading and reentrancy

The library is single-threaded by design (Luau/Roblox semantics). All module state (`activeSub`, the counters, the queue) is per-VM. The engine's walks are iterative, and `update`/`notify` may reenter the reactive system safely (the stack arrays used by `propagate`/`checkDirty` are per-call, lazily allocated).

Parallel Luau actors each get their own module instance — signals do not cross actor boundaries, so a signal graph is always confined to one VM.
