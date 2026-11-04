# Type Guards

```luau
isSignal(value: any) -> boolean
isComputed(value: any) -> boolean
isEffect(value: any) -> boolean
isEffectScope(value: any) -> boolean
```

Four functions that answer "is this table a node of that kind?" by metatable identity. They are the exact equivalent of the upstream's `fn.name === 'bound ' + oper.name` checks, ported to the callable-table representation.

## Signature

| Function | True when the value is… |
|---|---|
| `isSignal` | a signal node (created by `signal`) |
| `isComputed` | a computed node (created by `computed`) |
| `isEffect` | an effect node (created by `effect`) |
| `isEffectScope` | a scope node (created by `effectScope`) |

## Semantics

- The check is `type(value) == "table" and getmetatable(value) == <META>` — identity comparison against the module's internal, frozen metatables.
- **Non-table arguments return `false`**, never an error. This is deliberately more forgiving than the TypeScript original, where `isSignal(undefined)` throws (it reads `fn.name`): passing a string is safe here (strings share a metatable in Luau and would otherwise be a trap — the `type` guard prevents that).
- The four kinds are mutually exclusive: a node has exactly one metatable, so at most one guard returns `true` for any value.
- The metatables are frozen at module load; no user code can make a fake node that satisfies a guard (short of `table.freeze`-identical tables being impossible to forge for metatables — identity, not content, is compared).

```luau
local s = signal(1)
local c = computed(function() return s() end)
local e = effect(function() s() end)
local sc = effectScope(function() end)

print(isSignal(s))    -- true
print(isSignal(c))    -- false
print(isComputed(c))  -- true
print(isEffect(e))    -- true
print(isEffectScope(sc)) -- true
print(isSignal({}))   -- false
print(isSignal("hi")) -- false (no error)
print(isSignal(nil))  -- false (no error)
```

## Why metatable identity

The upstream TypeScript discriminates node kinds with `'getter' in node` / `'currentValue' in node` / `'fn' in node` — property-existence checks. That cannot be ported to Luau literally: a field holding `nil` **does not exist** in a Luau table, so `signal(nil)` would lose its `currentValue` marker and be misclassified. The port instead tags every node with a frozen metatable at creation (which is needed anyway to make the node callable), and identity of that metatable is a reliable, unforgeable kind tag. See [How It Works: node kinds](../tutorials/how-it-works#node-kinds-and-metatables).

## Uses

Guards are for writing glue around the library — serialization of graphs, debugging tools, or APIs that accept "any reactive node":

```luau
local function describeNode(value: any): string
    if isSignal(value) then return "signal" end
    if isComputed(value) then return "computed" end
    if isEffect(value) then return "effect" end
    if isEffectScope(value) then return "effectScope" end
    return "not a node"
end
```

::: tip
If you are checking a node's kind to decide whether to *call* it, remember the calling conventions differ: signals read/write, computeds read, effects and scopes dispose. The guards tell you which is which.
:::

## Performance

Each guard is one `type` check plus one `getmetatable` plus one identity comparison — no table scans, no field probes. They are cheap enough for hot paths, though most code never needs them at all.
