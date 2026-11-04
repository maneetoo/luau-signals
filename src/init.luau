--!strict
--!native
--!optimize 2
--!nolint SameLineStatement
--upstream: https://github.com/stackblitz/alien-signals/blob/master/src/index.ts

const system = require '@self/system';
const createReactiveSystem = system.createReactiveSystem;

type ReactiveNode = system.ReactiveNode;
type Link = system.Link;

--NOTE: In TS, `interface EffectScopeNode extends ReactiveNode {}` adds nothing to the base node, so in Luau it is just an 
--alias for `ReactiveNode`; it is kept to stay close to the original naming.
type EffectScopeNode = ReactiveNode;

--NOTE: In TS the callback is typed `fn(): (() => void) | void` and the field is `cleanup: (() => void) | void`. In Luau a 
--method and a function-typed field are the same thing, and `void` becomes `nil` — so the type of the callback's result is 
--`Cleanup?`.
--NOTE: `() -> ()` and `() -> Cleanup?` are declared as a union on purpose: Luau's type checker requires *every* code path of 
--a function to return a value of the declared return type, so a single `() -> Cleanup?` would reject the most common form 
--`effect(function() ... end)` (a function without a `return` statement is typed `() -> ()`, and `()` is not `Cleanup?`).
type Cleanup = () -> ();
type EffectFn = (() -> ()) | (() -> Cleanup?);

type EffectNode = ReactiveNode & {
    fn: EffectFn;
    cleanup: Cleanup?;
};

--NOTE: The TS interfaces are generic (`ComputedNode<T>`, `SignalNode<T>`). Luau supports generics, but a signal/computed is a 
--callable table (see `SIGNAL_META` below) and Luau's type system cannot describe a callable table at all, so the value 
--handed back to the user is `any` and the stored value is `any` too — exactly what `<T = any>` means in the original.
type ComputedNode = ReactiveNode & {
    value: any;
    getter: (previousValue: any) -> any;
};

type SignalNode = ReactiveNode & {
    currentValue: any;
    pendingValue: any;
};

--NOTE: Luau has no `try`/`catch`/`finally`, so every `finally` block of the original is reproduced with `pcall` and a 
--re-`error`. The analyzer derives the result types of `pcall` from the callee, and for a callback typed `() -> ()` it would 
--give `pcall` a single `boolean` result — therefore every callback that is called through `pcall` is cast to this alias, 
--which makes `pcall` return `(boolean, any)` no matter what the callback actually returns.
--NOTE: the alias is used as a *cast* at the call site, never as the annotation of a callback: Luau refuses to type a 
--function *without* a `return` statement as `() -> any` ("not all codepaths return 'any'"), so `function() ... end` is 
--always declared as-is and cast only when it is handed to `pcall`.
type Thunk = () -> any;

--NOTE: As in `system.luau`, the flag values are copied into standalone constants: reading a `const` upvalue on the hot path 
--is cheaper than reading a field of the `ReactiveFlags` table, while the values still come from a single source of truth 
--(`system.luau`), so the two files cannot drift apart.
const ReactiveFlags = system.ReactiveFlags;

const FLAG_NONE = ReactiveFlags.None;
const FLAG_MUTABLE = ReactiveFlags.Mutable;
const FLAG_WATCHING = ReactiveFlags.Watching;
const FLAG_RECURSED_CHECK = ReactiveFlags.RecursedCheck;
const FLAG_RECURSED = ReactiveFlags.Recursed;
const FLAG_DIRTY = ReactiveFlags.Dirty;
const FLAG_PENDING = ReactiveFlags.Pending;

--NOTE: `HasChildEffect` marks a parent (an effect or a scope) whose deps include at least one child effect. Used to gate the 
--dispose-children-first slow path in `run()` so that leaf effects (no children, no own cleanup) avoid the extra deps walk.
--The bit is outside `ReactiveFlags`' range and is never touched by `system.luau`.
const HasChildEffect = 64;

--NOTE: Luau has no `&`, `|` or `~` operators for numbers — only the `bit32` library (see `system.luau`), and `bit32.btest` 
--is the single-call form of "are any of these flags set". Every mask/clear value that is used more than once is precomputed 
--here; with `--!optimize 2` these `bit32` calls on constant arguments are folded at compile time.
const CLEAR_WATCHING_FLAG = bit32.bnot(FLAG_WATCHING);
const CLEAR_RECURSED_CHECK_FLAG = bit32.bnot(FLAG_RECURSED_CHECK);
const CLEAR_PENDING_FLAG = bit32.bnot(FLAG_PENDING);
const MUTABLE_DIRTY_MASK = bit32.bor(FLAG_MUTABLE, FLAG_DIRTY);
const MUTABLE_RECURSED_CHECK_MASK = bit32.bor(FLAG_MUTABLE, FLAG_RECURSED_CHECK);
const WATCHING_RECURSED_CHECK_MASK = bit32.bor(FLAG_WATCHING, FLAG_RECURSED_CHECK);
const WATCHING_RECURSED_MASK = bit32.bor(FLAG_WATCHING, FLAG_RECURSED);

--NOTE: Every module-level counter is mutated, so the `let` of the original becomes `local` (`const` cannot be used for them).
--NOTE: `cycle` is never read on its own — it is only passed to `link` as the "version" — but it must still be a `local` 
--because it is incremented.
local cycle = 0;
local runDepth = 0;
local batchDepth = 0;
local notifyIndex = 0;
local queuedLength = 0;
--NOTE: `let activeSub: ReactiveNode | undefined` becomes `ReactiveNode?` initialised with `nil`: there is no `undefined` in 
--Luau, only `nil`.
local activeSub: ReactiveNode? = nil;

--NOTE: `queued` is the notify queue. In TS it is a plain array that grows from index 0 to `queuedLength`, every consumed 
--slot is set back to `undefined`, and the array is never shrunk (it is reused by the next flush) — the port does exactly 
--the same with `nil`, hence the `{ EffectNode? }` element type.
const queued: { EffectNode? } = {};

--NOTE: The five functions returned by `createReactiveSystem` are used by almost everything below, but in Luau there is no 
--hoisting: `const` requires a value at the point of declaration, and the call itself can only be made once the callbacks it 
--receives (`update`, `notify`, `unwatched`) exist — and those callbacks use the very functions that the call returns. So 
--they are forward-declared with `local` here and assigned once, right after the `createReactiveSystem` call below. Nothing 
--is lost at runtime: reading a `local` upvalue and reading a `const` upvalue compile to the same instruction.
local link: (dep: ReactiveNode, sub: ReactiveNode, version: number) -> ();
local unlink: (link: Link, sub: ReactiveNode?) -> (Link?);
local propagate: (link: Link, innerWrite: boolean) -> ();
local checkDirty: (link: Link, sub: ReactiveNode) -> boolean;
local shallowPropagate: (link: Link) -> ();

--NOTE: the four node metatables are forward-declared for the same reason, and the cycle is even tighter: the operations 
--below identify the node kind by its metatable (see `SIGNAL_META`), while each metatable needs the operation it wraps as 
--its `__call` handler. They are created once, right after the last of those operations.
--NOTE: they are typed `any` (a metatable that makes a table callable has no type in Luau) and they are frozen, so neither 
--the `__call` handler of a kind nor the identity of a metatable can be replaced from the outside once the module is loaded.
local SIGNAL_META: any;
local COMPUTED_META: any;
local EFFECT_SCOPE_META: any;
local EFFECT_META: any;

--NOTE: `setActiveSub` and `getActiveSub` are placed here (instead of with the rest of the public API at the bottom) because 
--the first function that uses them is defined below, and in Luau `const function` must be defined before it is referenced.
const function setActiveSub(sub: ReactiveNode?): ReactiveNode?
    const prevSub = activeSub;
    activeSub = sub;
    return prevSub;
end;

const function getActiveSub(): ReactiveNode?
    return activeSub;
end;

--NOTE: `purgeDeps` is used by `updateComputed`, so it has to come first (see the note in `system.luau` about 
--`isValidLink`/`propagate`: in Luau constants cannot be used before they are defined).
const function purgeDeps(sub: ReactiveNode): ()
    const depsTail = sub.depsTail;
    --NOTE: Luau has no ternary operator, but `if ... then ... else ...` is an *expression* and is the direct equivalent of 
    --`depsTail !== undefined ? depsTail.nextDep : sub.deps`.
    local dep = if depsTail ~= nil then depsTail.nextDep else sub.deps;
    while (dep ~= nil) do
        dep = unlink(dep, sub);
    end;
end;

--NOTE: `disposeAllDepsInReverse` is used by `effectScopeOper` (and by the `unwatched` callback), so it is defined before 
--both of them.
const function disposeAllDepsInReverse(sub: ReactiveNode): ()
    --NOTE: the original calls this variable `link` as well; it is renamed to `depLink` so that it does not shadow the 
    --`link` function of the reactive system that is forward-declared above.
    local depLink = sub.depsTail;
    while (depLink ~= nil) do
        const prev = depLink.prevDep;
        unlink(depLink, sub);
        depLink = prev;
    end;
end;

--NOTE: `runCleanup` is used by `effectOper` and by `run`, so it is defined before both of them.
const function runCleanup(e: EffectNode): ()
    const cleanup = e.cleanup :: Cleanup;
    e.cleanup = nil;
    const prevSub = activeSub;
    activeSub = nil;
    --NOTE: this is the `try { cleanup() } finally { activeSub = prevSub }` of the original. Luau has no `finally`, so the 
    --body is called through `pcall` and the state is restored immediately afterwards; `error(err, 0)` then re-throws the 
    --original error object unchanged (level `0` means "do not attach the current position to it").
    --NOTE: a cleanup must never be able to observe itself as the active subscriber, which is why `activeSub` is cleared 
    --before the call and restored after it — even if the cleanup throws.
    const ok, err = pcall(cleanup :: Thunk);
    activeSub = prevSub;
    if (not ok) then
        error(err, 0);
    end;
end;

--NOTE: `effectScopeOper` is used by `effectOper` and by the `unwatched` callback, so it is defined before both of them.
const function effectScopeOper(e: EffectScopeNode): ()
    e.flags = FLAG_NONE;
    disposeAllDepsInReverse(e);
    --NOTE: `unlink(sub)` — the second argument of `unlink` is optional in `system.luau` and defaults to `link.sub`, which is 
    --exactly what the original one-argument call relies on.
    const sub = e.subs;
    if (sub ~= nil) then
        unlink(sub);
    end;
end;

const function effectOper(e: EffectNode): ()
    effectScopeOper(e);
    if (e.cleanup ~= nil) then
        runCleanup(e);
    end;
end;

--NOTE: `updateSignal` is used by `update` and by `signalOper`, so it is defined before both of them.
const function updateSignal(s: SignalNode): boolean
    s.flags = FLAG_MUTABLE;
    --NOTE: the original writes `s.currentValue !== (s.currentValue = s.pendingValue)`; Luau has no assignment expressions, so 
    --the old value is read into a constant first and the new one is written in a separate statement.
    const oldValue = s.currentValue;
    s.currentValue = s.pendingValue;
    return oldValue ~= s.currentValue;
end;

--NOTE: `updateComputed` is used by `update` and by `computedOper`, so it is defined before both of them.
const function updateComputed(c: ComputedNode): boolean
    --NOTE: the walk over the deps only happens when the computed is marked as having child effects (see `HasChildEffect`): 
    --any child effect/scope that the getter does not re-create on this run is unlinked, and therefore disposed, *before* the 
    --getter runs again.
    if (bit32.btest(c.flags, HasChildEffect)) then
        --NOTE: `link` is renamed to `depLink` here for the same reason as in `disposeAllDepsInReverse`.
        local depLink = c.depsTail;
        while (depLink ~= nil) do
            const prev = depLink.prevDep;
            const dep = depLink.dep;
            --NOTE: TS writes `!('getter' in dep) && !('currentValue' in dep)`, i.e. "this dep is neither a computed nor a 
            --signal, therefore it is a child effect/scope". A literal port is impossible — in Luau a field holding `nil` 
            --does not exist at all, so `signal(nil)` would be misidentified — which is why the node kind is taken from the 
            --metatable (see `SIGNAL_META` below) instead.
            if (getmetatable(dep) ~= COMPUTED_META and getmetatable(dep) ~= SIGNAL_META) then
                unlink(depLink, c);
            end;
            depLink = prev;
        end;
    end;
    c.depsTail = nil;
    c.flags = MUTABLE_RECURSED_CHECK_MASK;
    const prevSub = setActiveSub(c);
    --NOTE: this is the `try { ... } finally { ... }` of the original (see `runCleanup`). The value of the computed is 
    --assigned only after the getter has returned, exactly as in TS, where an exception aborts the assignment.
    cycle += 1;
    const oldValue = c.value;
    const ok, result = pcall(c.getter, oldValue);
    -- finally
    activeSub = prevSub;
    c.flags = bit32.band(c.flags, CLEAR_RECURSED_CHECK_FLAG);
    purgeDeps(c);
    if (not ok) then
        error(result, 0);
    end;
    c.value = result;
    return oldValue ~= result;
end;

--NOTE: `run` is used by `flush`, so it is defined before it.
const function run(e: EffectNode): ()
    const flags = e.flags;
    --NOTE: `flags & Dirty || (flags & Pending && checkDirty(...))` — `&&`/`||` become `and`/`or`, and "is the flag set" 
    --becomes `bit32.btest` (see `system.luau`).
    if (
        bit32.btest(flags, FLAG_DIRTY)
        or (
            bit32.btest(flags, FLAG_PENDING)
            and checkDirty(e.deps :: Link, e)
        )
    ) then
        if (bit32.btest(flags, HasChildEffect)) then
            --NOTE: same child-effect walk as in `updateComputed` (including the metatable-based kind check).
            local depLink = e.depsTail;
            while (depLink ~= nil) do
                const prev = depLink.prevDep;
                const dep = depLink.dep;
                if (getmetatable(dep) ~= COMPUTED_META and getmetatable(dep) ~= SIGNAL_META) then
                    unlink(depLink, e);
                end;
                depLink = prev;
            end;
        end;
        if (e.cleanup ~= nil) then
            runCleanup(e);
            --NOTE: the cleanup may have disposed the effect (or the scope it belongs to), in which case `run` must stop here.
            if (e.flags == FLAG_NONE) then
                return;
            end;
        end;
        e.depsTail = nil;
        e.flags = WATCHING_RECURSED_CHECK_MASK;
        const prevSub = setActiveSub(e);
        --NOTE: `try { ++cycle; ++runDepth; e.cleanup = e.fn(); } finally { ... }` (see `runCleanup`).
        cycle += 1;
        runDepth += 1;
        const ok, cleanup = pcall(e.fn :: Thunk);
        -- finally
        runDepth -= 1;
        activeSub = prevSub;
        e.flags = bit32.band(e.flags, CLEAR_RECURSED_CHECK_FLAG);
        purgeDeps(e);
        if (not ok) then
            error(cleanup, 0);
        end;
        e.cleanup = cleanup :: Cleanup?;
    elseif (e.deps ~= nil) then
        e.flags = bit32.bor(FLAG_WATCHING, bit32.band(flags, HasChildEffect));
    end;
end;

--NOTE: `flush` is used by `signalOper`, `trigger` and `endBatch`, so it is defined before all three of them.
const function flush(): ()
    --NOTE: `try { while ... } finally { while ...; notifyIndex = 0; queuedLength = 0; }` (see `runCleanup`). The loop is 
    --wrapped in a `pcall`ed closure, so that an error thrown by an effect cannot leave the queue half-consumed: the 
    --`finally` part below drains the remaining effects and resets the cursors before the error is re-thrown.
    const flushQueue = function(): ()
        while (notifyIndex < queuedLength) do
            --NOTE: TS uses the non-null assertion `queued[notifyIndex]!`; in Luau the same thing is expressed with a cast.
            const effect = queued[notifyIndex] :: EffectNode;
            queued[notifyIndex] = nil;
            notifyIndex += 1;
            run(effect);
        end;
    end;
    const ok, err = pcall(flushQueue :: Thunk);
    -- finally
    while (notifyIndex < queuedLength) do
        const effect = queued[notifyIndex] :: EffectNode;
        queued[notifyIndex] = nil;
        notifyIndex += 1;
        --NOTE: an effect that was queued but not run keeps the `Watching` flag and is marked as `Recursed`, so that the next 
        --write notifies it again.
        effect.flags = bit32.bor(effect.flags, WATCHING_RECURSED_MASK);
    end;
    notifyIndex = 0;
    queuedLength = 0;
    if (not ok) then
        error(err, 0);
    end;
end;

--NOTE: `signalOper` is the `__call` handler of a signal node (see `SIGNAL_META` below), so it is defined before the 
--metatables.
const function signalOper(s: SignalNode, ...: any): any
    --NOTE: the original is a pair of overloads that tell a read from a write with `value.length` (rest parameters). Luau has 
    --no rest parameters, so the number of passed arguments is obtained with `select('#', ...)`. It is used instead of 
    --`#{...}` on purpose: `select` counts explicit `nil`s, and `s(nil)` must be a *write* of `nil`, not a read.
    if (select("#", ...) > 0) then
        const newValue = ...;
        --NOTE: `this.pendingValue !== (this.pendingValue = value[0])` — read, write, compare (see `updateSignal`).
        const oldValue = s.pendingValue;
        s.pendingValue = newValue;
        if (oldValue ~= newValue) then
            s.flags = MUTABLE_DIRTY_MASK;
            const subs = s.subs;
            if (subs ~= nil) then
                --NOTE: `!!runDepth` becomes `runDepth ~= 0`: `propagate` expects a boolean.
                propagate(subs, runDepth ~= 0);
                --NOTE: inside a batch the flush is deferred to `endBatch`.
                if (batchDepth == 0) then
                    flush();
                end;
            end;
        end;
    else
        --NOTE: reading a signal is a "lazy write": the pending value is committed only when somebody actually reads it.
        if (bit32.btest(s.flags, FLAG_DIRTY)) then
            if (updateSignal(s)) then
                const subs = s.subs;
                if (subs ~= nil) then
                    shallowPropagate(subs);
                end;
            end;
        end;
        const sub = activeSub;
        if (sub ~= nil) then
            link(s, sub, cycle);
        end;
        return s.currentValue;
    end;
    --NOTE: a write returns nothing, which is `undefined` in the original and `nil` here; Luau requires the `return` to be 
    --written out explicitly when the function is declared to return a value.
    return nil;
end;

--NOTE: `computedOper` is the `__call` handler of a computed node (see `COMPUTED_META` below).
const function computedOper(c: ComputedNode): any
    const flags = c.flags;
    --NOTE: the original condition is a single expression that hides an assignment inside it through the comma operator:
    --`flags & Dirty || (flags & Pending && (checkDirty(this.deps!, this) || (this.flags = flags & ~Pending, false)))`.
    --Luau has neither a comma operator nor assignment expressions, so the same logic is spelled out with an explicit 
    --`dirty` variable. The evaluation order — and therefore the behavior — is unchanged: `Dirty` short-circuits `Pending`, 
    --and the pending flag is cleared (without recomputing) only when `checkDirty` reports "not dirty".
    local dirty = false;
    if (bit32.btest(flags, FLAG_DIRTY)) then
        dirty = true;
    elseif (bit32.btest(flags, FLAG_PENDING)) then
        --NOTE: TS uses the non-null assertion `this.deps!`; in Luau the same thing is expressed with a cast.
        if (checkDirty(c.deps :: Link, c)) then
            dirty = true;
        else
            c.flags = bit32.band(flags, CLEAR_PENDING_FLAG);
        end;
    end;
    if (dirty) then
        if (updateComputed(c)) then
            const subs = c.subs;
            if (subs ~= nil) then
                shallowPropagate(subs);
            end;
        end;
    elseif (flags == FLAG_NONE) then
        --NOTE: the very first read of a computed: it has no deps and no flags, so it is evaluated directly, without going 
        --through `updateComputed` (which is only for an already-tracked node).
        c.flags = MUTABLE_RECURSED_CHECK_MASK;
        const prevSub = setActiveSub(c);
        --NOTE: `try { this.value = this.getter(); } finally { ... }` (see `runCleanup`). Note that the getter is called 
        --without an argument here — the previous value is passed only by `updateComputed`.
        const ok, value = pcall(c.getter);
        -- finally
        activeSub = prevSub;
        c.flags = bit32.band(c.flags, CLEAR_RECURSED_CHECK_FLAG);
        if (not ok) then
            error(value, 0);
        end;
        c.value = value;
    end;
    const sub = activeSub;
    if (sub ~= nil) then
        link(c, sub, cycle);
    end;
    return c.value;
end;

--NOTE: In TS the public surface of a signal/computed/effect is a *bound function*: `signalOper.bind(node)` etc. Calling it 
--runs the oper with the node bound to `this`. Luau has no `bind`, and its type system cannot describe a callable table, so 
--the node itself is made callable through a `__call` metatable: `__call` receives the table as its first argument, which is 
--exactly what `this` is in the original. Nothing extra is allocated per signal/computed/effect/scope — no wrapper table 
--and no closure.
--NOTE: these metatables double as the node-kind tag. The original discriminates the node kinds with `'getter' in node` / 
--`'currentValue' in node` / `'fn' in node`, and that cannot be ported literally, because in Luau a field holding `nil` does 
--not exist at all (`signal(nil)` would lose its `currentValue` and be mistaken for a scope). The metatable is always 
--present, so it is a reliable tag — and it is needed anyway to make the node callable.
--NOTE: `isSignal`/`isComputed`/`isEffect`/`isEffectScope` compare these metatables by identity, which is the exact 
--equivalent of the `fn.name === 'bound ' + signalOper.name` check of the original.
--NOTE: the metatables are frozen, so neither the `__call` handler of a kind nor the identity of a metatable can be 
--replaced from the outside once the module is loaded.
SIGNAL_META = table.freeze({ __call = signalOper });
COMPUTED_META = table.freeze({ __call = computedOper });
EFFECT_SCOPE_META = table.freeze({ __call = effectScopeOper });
EFFECT_META = table.freeze({ __call = effectOper });

--NOTE: These three callbacks are the only entry points that `system.luau` has into this module; they replace the object 
--literal that is passed to `createReactiveSystem` in the original. They are defined as named `const function`s (rather than 
--inline in the table literal) because they have to be declared before the `createReactiveSystem` call below.
const function update(node: ReactiveNode): boolean
    --NOTE: `if ('getter' in node) return updateComputed(node)` — the metatable-based equivalent (see `SIGNAL_META`).
    const meta = getmetatable(node);
    if (meta == COMPUTED_META) then
        return updateComputed(node :: ComputedNode);
    end;
    --NOTE: `if ('currentValue' in node) return updateSignal(node)`.
    if (meta == SIGNAL_META) then
        return updateSignal(node :: SignalNode);
    end;
    --NOTE: anything else is an effect scope: it holds no value of its own, so it is simply reset to "mutable" and reported 
    --as changed.
    node.flags = FLAG_MUTABLE;
    return true;
end;

--NOTE: `system.luau` declares the parameter of `notify` as a `ReactiveNode`, while the original narrows it to 
--`EffectNode`. TS accepts that silently (method parameters are bivariant in TS), but Luau checks the direction of the 
--conversion, so the parameter stays `ReactiveNode` here and is narrowed with a cast — `notify` is only ever called with an 
--effect, as in the original.
const function notify(node: ReactiveNode): ()
    local effect = node :: EffectNode;
    local insertIndex = queuedLength;
    --NOTE: `firstInsertedIndex` is only read by the reversal loop below, but that loop also advances it, so it must be a 
    --`local` (the original declares it with `let`).
    local firstInsertedIndex = insertIndex;
    --NOTE: `do { ... } while (true)` with a `break` inside becomes a plain `while (true)` loop with the same `break`s.
    while (true) do
        queued[insertIndex] = effect;
        insertIndex += 1;
        effect.flags = bit32.band(effect.flags, CLEAR_WATCHING_FLAG);
        --NOTE: TS writes `effect = effect.subs?.sub as EffectNode; if (effect === undefined || !(effect.flags & Watching))`.
        --Luau has no `?.`, so the `nil` check is spelled out; the "walk up to the parent effect" behavior is unchanged.
        const subs = effect.subs;
        if (subs == nil) then
            break;
        end;
        effect = subs.sub :: EffectNode;
        if (not bit32.btest(effect.flags, FLAG_WATCHING)) then
            break;
        end;
    end;
    queuedLength = insertIndex;
    --NOTE: `while (firstInsertedIndex < --insertIndex) { ... }`: the original reverses the inserted run in place, so that 
    --the parent effect is run before its children. Luau has no `--` operator, so the decrement is written out explicitly.
    insertIndex -= 1;
    while (firstInsertedIndex < insertIndex) do
        const left = queued[firstInsertedIndex];
        queued[firstInsertedIndex] = queued[insertIndex];
        queued[insertIndex] = left;
        firstInsertedIndex += 1;
        insertIndex -= 1;
    end;
end;

const function unwatched(node: ReactiveNode): ()
    --NOTE: `if ('getter' in node) ... else if ('currentValue' in node) ... else if ('fn' in node) ...` — again the kind is 
    --taken from the metatable (see `SIGNAL_META`).
    const meta = getmetatable(node);
    if (meta == COMPUTED_META) then
        if (node.depsTail ~= nil) then
            node.flags = MUTABLE_DIRTY_MASK;
            disposeAllDepsInReverse(node);
        end;
    elseif (meta == SIGNAL_META) then
        --NOTE: nothing to do for signals, they are always mutable and never dirty until `pendingValue` changes.
    elseif (meta == EFFECT_META) then
        --NOTE: `effectOper.call(node)` → a plain call, which is the same thing for a free function.
        effectOper(node :: EffectNode);
    else
        effectScopeOper(node);
    end;
end;

--NOTE: Now that `update`, `notify` and `unwatched` exist, the reactive system can finally be created: `link`, `unlink`, 
--`propagate`, `checkDirty` and `shallowPropagate` are assigned to the forward-declared locals from the top of the file. 
--After this point they are ordinary upvalues again, exactly as in the original destructuring.
const reactiveSystem = createReactiveSystem {
    update = update,
    notify = notify,
    unwatched = unwatched,
};
link = reactiveSystem.link;
unlink = reactiveSystem.unlink;
propagate = reactiveSystem.propagate;
checkDirty = reactiveSystem.checkDirty;
shallowPropagate = reactiveSystem.shallowPropagate;

const function getBatchDepth(): number
    return batchDepth;
end;

--NOTE: the original uses `++batchDepth` and `if (!--batchDepth)`; Luau has no `++`/`--` operators (see the note in 
--`system.luau`), so the compound assignments `+=`/`-=` are used instead. The pre-decrement semantics are preserved.
const function startBatch(): ()
    batchDepth += 1;
end;

const function endBatch(): ()
    batchDepth -= 1;
    if (batchDepth == 0) then
        flush();
    end;
end;

--NOTE: the argument is typed `any` rather than `() -> void`: a signal is a callable table, which Luau's type system cannot 
--express. The `type(value) == "table"` guard is there because `getmetatable` is only meaningful for tables (strings share a 
--metatable, for instance, and must not be mistaken for a node).
--NOTE: this is also the one place where the port is deliberately more forgiving than the original: `isSignal(undefined)` 
--throws in TS (it reads `fn.name`), while here an argument of the wrong type simply gives `false`.
const function isSignal(value: any): boolean
    return type(value) == "table" and getmetatable(value) == SIGNAL_META;
end;

const function isComputed(value: any): boolean
    return type(value) == "table" and getmetatable(value) == COMPUTED_META;
end;

const function isEffect(value: any): boolean
    return type(value) == "table" and getmetatable(value) == EFFECT_META;
end;

const function isEffectScope(value: any): boolean
    return type(value) == "table" and getmetatable(value) == EFFECT_SCOPE_META;
end;

--NOTE: TS declares `signal` with a pair of overloads (`signal<T>()` and `signal<T>(initialValue: T)`) and returns a bound 
--`signalOper`. Luau has no overloads and no callable-table type, so the function is a single `any -> any`: the parameter is 
--declared `any?` to keep the zero-argument form `signal()` legal (the value then simply starts as `nil`), and the get/set 
--distinction is made by `signalOper` from the number of arguments.
--NOTE: every field of the node — including the `nil`s — is written explicitly, so that the hash part is allocated once and 
--`link`/`unlink` never cause the table to be rehashed (the same reasoning as in `system.luau`'s `link`).
const function signal(initialValue: any?): any
    const s: SignalNode = {
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = FLAG_MUTABLE,
        currentValue = initialValue,
        pendingValue = initialValue,
    };
    --NOTE: `setmetatable` is called as a separate statement (and not around the literal) because the type checker does not 
    --accept a `nil`-initialised field when the literal is wrapped into a call — which is exactly what the `nil`s above are.
    --NOTE: the node is passed through a cast to `any` because Luau's type checker *replaces* the type of the variable that 
    --`setmetatable` is called on with its `setmetatable<T, M>` result, and the rest of the code would then stop recognizing 
    --the node as a plain `ReactiveNode`.
    setmetatable(s :: any, SIGNAL_META);
    return s;
end;

--NOTE: `computed<T>(getter: (previousValue?: T) => T)` becomes `(previousValue: any) -> any` for the same reason as above. 
--The node starts with `ReactiveFlags.None` — no flags at all mean "never evaluated yet", which is exactly what 
--`computedOper` checks for.
const function computed(getter: (previousValue: any) -> any): any
    const c: ComputedNode = {
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = FLAG_NONE,
        value = nil,
        getter = getter,
    };
    --NOTE: see `signal` for why `setmetatable` is a separate statement and why the node is cast to `any`.
    setmetatable(c :: any, COMPUTED_META);
    return c;
end;

--NOTE: `effect(fn)` returns `effectOper.bind(e)` in the original, i.e. a disposer. Here the effect node itself is the 
--disposer (its metatable makes it callable), so the metatable is attached at creation time — `update`/`unwatched` may see 
--the node through `link`/`unlink` even before `effect` returns, and they identify the node kind by its metatable.
--NOTE: `try { ++runDepth; e.cleanup = e.fn(); } finally { --runDepth; activeSub = prevSub; e.flags &= ~RecursedCheck; }` 
--— see `runCleanup`. The cleanup is stored only if the callback returned normally, exactly as in the original, where the 
--exception aborts the assignment.
const function effect(fn: EffectFn): any
    const e: EffectNode = {
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = WATCHING_RECURSED_CHECK_MASK,
        fn = fn,
        cleanup = nil,
    };
    --NOTE: see `signal` for why `setmetatable` is a separate statement and why the node is cast to `any`.
    setmetatable(e :: any, EFFECT_META);
    const prevSub = setActiveSub(e);
    if (prevSub ~= nil) then
        link(e, prevSub, 0);
        prevSub.flags = bit32.bor(prevSub.flags, HasChildEffect);
    end;
    --NOTE: `++runDepth` / `--runDepth`.
    runDepth += 1;
    const ok, cleanup = pcall(fn :: Thunk);
    -- finally
    runDepth -= 1;
    activeSub = prevSub;
    e.flags = bit32.band(e.flags, CLEAR_RECURSED_CHECK_FLAG);
    if (not ok) then
        error(cleanup, 0);
    end;
    e.cleanup = cleanup :: Cleanup?;
    return e;
end;

--NOTE: as with `effect`, the disposer is the node itself, so the node gets its metatable at creation time.
const function effectScope(fn: () -> ()): any
    const e: EffectScopeNode = {
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = FLAG_MUTABLE,
    };
    --NOTE: see `signal` for why `setmetatable` is a separate statement and why the node is cast to `any`.
    setmetatable(e :: any, EFFECT_SCOPE_META);
    const prevSub = setActiveSub(e);
    if (prevSub ~= nil) then
        link(e, prevSub, 0);
        prevSub.flags = bit32.bor(prevSub.flags, HasChildEffect);
    end;
    --NOTE: `try { fn(); } finally { activeSub = prevSub; }` (see `runCleanup`).
    const ok, err = pcall(fn :: Thunk);
    -- finally
    activeSub = prevSub;
    if (not ok) then
        error(err, 0);
    end;
    return e;
end;

--NOTE: `trigger` is the "write without a signal" primitive: everything that is read inside `fn` is tracked by a throw-away 
--subscriber, and the deps are then propagated manually. The `finally` part is much bigger than the body, so it is written 
--after the `pcall`ed call.
const function trigger(fn: () -> ()): ()
    --NOTE: a `ReactiveNode`, not a full node of any of the four kinds: it is never notified, never updated and never put 
    --into the queue, it only collects deps. It has no metatable, which is why `unwatched` treats it as a scope if it ever 
    --gets there (`link` only reports `unwatched` for deps that lose their last subscriber).
    const sub: ReactiveNode = {
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = WATCHING_RECURSED_CHECK_MASK,
    };
    const prevSub = setActiveSub(sub);
    batchDepth += 1;
    const ok, err = pcall(fn :: Thunk);
    -- finally
    activeSub = prevSub;
    sub.flags = FLAG_NONE;
    --NOTE: `link` is renamed to `depLink` here for the same reason as in `disposeAllDepsInReverse`.
    local depLink = sub.deps;
    while (depLink ~= nil) do
        const dep = depLink.dep;
        depLink = unlink(depLink, sub);
        const subs = dep.subs;
        if (subs ~= nil) then
            propagate(subs, runDepth ~= 0);
            shallowPropagate(subs);
        end;
    end;
    --NOTE: `if (!--batchDepth) flush();` — pre-decrement, then "is the batch over".
    batchDepth -= 1;
    if (batchDepth == 0) then
        flush();
    end;
    if (not ok) then
        error(err, 0);
    end;
end;

--NOTE: exactly as in `system.luau`, the module returns a frozen table, so that the public API cannot be patched or 
--extended from the outside once the module is loaded.
const index = {
    getActiveSub = getActiveSub,
    setActiveSub = setActiveSub,
    getBatchDepth = getBatchDepth,
    startBatch = startBatch,
    endBatch = endBatch,
    isSignal = isSignal,
    isComputed = isComputed,
    isEffect = isEffect,
    isEffectScope = isEffectScope,
    signal = signal,
    computed = computed,
    effect = effect,
    effectScope = effectScope,
    trigger = trigger,
};

return table.freeze(index);
