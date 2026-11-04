--!strict
--!native
--!optimize 2
--!nolint SameLineStatement
--upstream: https://github.com/stackblitz/alien-signals/blob/master/src/system.ts

--NOTE: Luau does not have `interface` as a distinct type like TS does—only `type`—so we use and export `type` instead of an interface.
export type ReactiveNode = {
    deps: Link?;
    depsTail: Link?;
    subs: Link?;
    subsTail: Link?;
    flags: number;
};

--NOTE: In Luau, there is no such concept as `undefined`, `null`, or anything similar; there is only `nil` — so that is what we use.
export type Link = {
    version: number;
    dep: ReactiveNode;
    sub: ReactiveNode;
    prevSub: Link | nil;
    nextSub: Link | nil;
    prevDep: Link | nil;
    nextDep: Link | nil;
};

--NOTE: The original implementation uses a linked list (`Stack<T>`) as a stack, which allocates a new table for every push. 
--In Luau it is cheaper to use a plain array together with a depth counter. The array is created lazily (only if the stack is 
--actually needed) and is local to a single call, so it is safe for reentrant calls (`update` / `notify` can call back into 
--the reactive system) and for errors thrown from inside these callbacks. Because of this, the `Stack<T>` type is removed.

--NOTE: Unlike JS, Luau does not have enums; therefore, we first define a type, and then define a constant based 
--on that type.
--NOTE: The `read` keyword is used to indicate that the properties of the type are read-only, similar to how enums 
--work in TypeScript. This is done to prevent the flags from being modified at runtime or from outside `system.luau`.
export type ReactiveFlags = {
    read None: number;
    read Mutable: number;
    read Watching: number;
    read RecursedCheck: number;
    read Recursed: number;
    read Dirty: number;
    read Pending: number;
};

--NOTE: Unlike JS, Luau does not support `export const`; therefore, we use a table to hold all the enums and functions 
--to be exported, and return that table.
const system = {};

--NOTE: The values of the flags are declared as standalone constants, and the exported `ReactiveFlags` table is built from 
--them. The Luau compiler inlines constants as immediate values, whereas every read of a field from a table 
--(`ReactiveFlags.Pending`) or of an upvalue in the hot path costs an additional lookup. So internally we always use the 
--`FLAG_*` constants, and `ReactiveFlags` exists only for the outside code.
const FLAG_NONE = 0;
const FLAG_MUTABLE = 1;
const FLAG_WATCHING = 2;
const FLAG_RECURSED_CHECK = 4;
const FLAG_RECURSED = 8;
const FLAG_DIRTY = 16;
const FLAG_PENDING = 32;

const ReactiveFlags: ReactiveFlags = table.freeze {
    None = FLAG_NONE,
    Mutable = FLAG_MUTABLE,
    Watching = FLAG_WATCHING,
    RecursedCheck = FLAG_RECURSED_CHECK,
    Recursed = FLAG_RECURSED,
    Dirty = FLAG_DIRTY,
    Pending = FLAG_PENDING,
} system.ReactiveFlags = ReactiveFlags;

--NOTE: Luau does not have native bitwise operators &, |, or ~ (with the exception of the use of & and | within type syntax). 
--For bitwise operations, we must use the `bit32` library.
--NOTE: `bit32.btest(a, b)` is equivalent to `bit32.band(a, b) ~= 0`, but it is a single built-in call, so we use it for all 
--"is any of these flags set" checks.
--NOTE: All masks are built from constants, so with `--!optimize 2` they are folded at compile time into plain numbers.
--docs: https://luau.org/library/#bit32-library
const RECURSED_CHECK_MASK = bit32.bor(
    FLAG_RECURSED_CHECK,
    FLAG_RECURSED,
    FLAG_DIRTY,
    FLAG_PENDING
);
const NONE_CHECK_MASK = bit32.bor(
    FLAG_RECURSED_CHECK,
    FLAG_RECURSED
);
const PENDING_DIRTY_MASK = bit32.bor(
    FLAG_DIRTY,
    FLAG_PENDING
);
const PENDING_RECURSED_MASK = bit32.bor(
    FLAG_PENDING,
    FLAG_RECURSED
);
const SHALLOW_NOTIFY_CHECK_MASK = bit32.bor(
    FLAG_WATCHING,
    FLAG_RECURSED_CHECK
);
const MUTABLE_DIRTY_MASK = bit32.bor(
    FLAG_MUTABLE,
    FLAG_DIRTY
);
const MUTABLE_PENDING_CHECK_MASK = bit32.bor(
    FLAG_MUTABLE,
    FLAG_PENDING
);

const CLEAR_RECURSED_FLAG = bit32.bnot(FLAG_RECURSED);
const CLEAR_PENDING_FLAG = bit32.bnot(FLAG_PENDING);

--NOTE: In Luau, you cannot simply accept a table in a function without specifying its name, so let’s just call it `t`.
const function createReactiveSystem(t: {
    update: (sub: ReactiveNode) -> boolean,
    notify: (sub: ReactiveNode) -> (),
    unwatched: (sub: ReactiveNode) -> (),
})
    --NOTE: In Luau, you cannot return a table at the beginning of a function as you might in JS—firstly, because you cannot 
    --place any code within the function body before the return statement, and secondly, because you cannot include values 
    --​​(constants) in a table if they have not yet been declared.
    --NOTE: We add constants from `t` (the table passed into the function from the outside) to the hot path for quick access, 
    --while also maintaining their availability just as in the original implementation.
    const update, notify, unwatched = t.update, t.notify, t.unwatched
    --NOTE: In Luau, `()` is like `void` in TS.
    const function link(dep: ReactiveNode, sub: ReactiveNode, version: number): ()
        const prevDep = sub.depsTail;
        --NOTE: Luau does not distinguish between strict equality and loose equality (`==` vs `===`); therefore, any comparison 
        --using `==` in Luau is always strict (equivalent to `===` in JS).
        --NOTE: Luau does not have an `&&` operator per se, but it does have a direct alternative: `and`.
        --NOTE: In Luau, the `~=` operator is equivalent to `!==` in JS.
        if (prevDep ~= nil and prevDep.dep == dep) then
            return;
        end;
        --NOTE: Luau does not have a `?` operator like JS, so we use a standard `if then else` to define the `nextDep` constant.
        const nextDep = if prevDep ~= nil then prevDep.nextDep else sub.deps
        if (nextDep ~= nil and nextDep.dep == dep) then
            nextDep.version = version;
            sub.depsTail = nextDep;
            return;
        end;
        const prevSub = dep.subsTail;
        if (prevSub ~= nil and prevSub.version == version and prevSub.sub == sub) then
            return;
        end;
        --NOTE: In Luau, unlike in JS, you cannot simultaneously declare a constant and reassign other constants to a new value 
        --in a single statement. So we just define a new constant and change the old ones afterward.
        --NOTE: `nextSub = nil` is written explicitly on purpose: it makes the compiler allocate the hash part for all 7 fields 
        --at once, so assigning `nextSub` later does not cause the table to be resized (rehashed).
        const newLink: Link = {
            version = version,
            dep = dep,
            sub = sub,
            prevDep = prevDep,
            nextDep = nextDep,
            prevSub = prevSub,
            nextSub = nil,
        };
        sub.depsTail = newLink;
        dep.subsTail = newLink;
        if (nextDep ~= nil) then
            nextDep.prevDep = newLink;
        end;
        if (prevDep ~= nil) then
            prevDep.nextDep = newLink;
        else
            sub.deps = newLink;
        end;
        if (prevSub ~= nil) then
            prevSub.nextSub = newLink;
        else
            dep.subs = newLink;
        end;
    end;

    --NOTE: In Luau, unlike in JS, you cannot directly assign a value while simultaneously providing a fallback for cases where 
    --that value is undefined (e.g., `sub = link.sub`). Instead, we explicitly account for the possibility that a value might be 
    --undefined, and then define it using the `or` operator (see below).
    const function unlink(link: Link, sub: ReactiveNode?): Link | nil
        --NOTE: if `sub` is undefined (`nil`), the `or` operator will replace it with `link.sub`.
        sub = sub or link.sub 
        --NOTE: In Luau, you cannot extract values ​​from a table using `{ val1, val2}` — that is why we retrieve them directly 
        --from the table.
        const dep, prevDep, nextDep, nextSub, prevSub = link.dep, link.prevDep, link.nextDep, link.nextSub, link.prevSub;
        if (nextDep ~= nil) then
            nextDep.prevDep = prevDep;
        else
            sub.depsTail = prevDep;
        end;
        if (prevDep ~= nil) then
            prevDep.nextDep = nextDep;
        else
            sub.deps = nextDep;
        end;
        if (nextSub ~= nil) then
            nextSub.prevSub = prevSub;
        else
            dep.subsTail = prevSub;
        end;
        if (prevSub ~= nil) then
            prevSub.nextSub = nextSub;
        --NOTE: Similar to the approach used above for defining `sub`, here we employ a slightly different method: we first 
        --redefine `dep.subs` and only then check for `nil` (`undefined`). We check the local `nextSub` (it is the value that 
        --was just assigned to `dep.subs`) instead of reading `dep.subs` from the table once again.
        else
            dep.subs = nextSub;
            if (nextSub == nil) then
                unwatched(dep);
            end;
        end;
        return nextDep;
    end;

    --NOTE: The `isValidLink` function is used within `propagate`. In Luau, functions are also considered constants, and 
    --constants cannot be used before they are defined. Therefore, we place the `isValidLink` function before `propagate`.
    const function isValidLink(checkLink: Link, sub: ReactiveNode): boolean
        --NOTE: In Luau, `local` is the equivalent of `let` in JavaScript.
        local link = sub.depsTail;
        while (link ~= nil) do
            if (link == checkLink) then
                return true;
            end;
            link = link.prevDep;
        end;
        return false;
    end;

    const function propagate(link: Link, innerWrite: boolean): ()
        --NOTE: `innerWrite` does not change while the function is running, so instead of checking it on every iteration of the 
        --loop, we calculate the flags that must be set once, before the loop.
        const pendingFlags = if innerWrite then PENDING_RECURSED_MASK else FLAG_PENDING;
        local next = link.nextSub;
        --NOTE: The array is created only when the first branching occurs (see the NOTE about `Stack<T>` above). `depth` is 
        --the number of elements currently stored in it.
        local stack: { Link }? = nil;
        local depth = 0;

        --NOTE: Unlike Lua 5.2, Luau does not include the `goto` statement or labels like `::label::` — though these are not 
        --strictly necessary, as Luau allows the use of `break` and `continue` within loops without disrupting the rest of 
        --the code.
        while (true) do
            const sub = link.sub;
            local flags = sub.flags;
            --NOTE: See above for why `bit32` libraries are used instead of bitwise operators.
            if (not bit32.btest(flags, RECURSED_CHECK_MASK)) then
                sub.flags = bit32.bor(flags, pendingFlags);
            elseif (not bit32.btest(flags, NONE_CHECK_MASK)) then
                flags = FLAG_NONE;
            elseif (not bit32.btest(flags, FLAG_RECURSED_CHECK)) then
                sub.flags = bit32.bor(bit32.band(flags, CLEAR_RECURSED_FLAG), FLAG_PENDING);
            elseif (not bit32.btest(flags, PENDING_DIRTY_MASK) and isValidLink(link, sub)) then
                sub.flags = bit32.bor(flags, PENDING_RECURSED_MASK);
                flags = bit32.band(flags, FLAG_MUTABLE);
            else
                flags = FLAG_NONE;
            end;

            if (bit32.btest(flags, FLAG_WATCHING)) then
                notify(sub);
            end;

            if (bit32.btest(flags, FLAG_MUTABLE)) then
                const subSubs = sub.subs;
                if (subSubs ~= nil) then
                    link = subSubs;
                    const nextSub = subSubs.nextSub;
                    if (nextSub ~= nil) then
                        --NOTE: The original implementation pushes `next` onto the stack even if it is `nil`, and then skips 
                        --such elements when popping. We simply do not push `nil` at all; the order of the remaining elements 
                        --does not change, so the behavior is the same.
                        if (next ~= nil) then
                            const branches: { Link } = stack or table.create(4) :: { Link };
                            stack = branches;
                            depth += 1;
                            branches[depth] = next;
                        end;
                        next = nextSub;
                    end;
                    continue;
                end;
            end;

            if (next ~= nil) then
                link = next;
                next = link.nextSub;
                continue;
            end;

            --NOTE: Luau does not support `::labels::`, so we cannot jump to the top of the loop from a nested loop. Since 
            --only non-`nil` elements are stored in the stack, there is no need for a nested loop here at all: we just pop 
            --a single element and continue the main loop, so the "break to top" flag is not needed.
            if (depth > 0) then
                link = (stack :: { Link })[depth];
                depth -= 1;
                next = link.nextSub;
                continue;
            end;

            break;
        end;
    end;

    --NOTE: The `shallowPropagate` function is used within `checkDirty`. In Luau, functions are also considered constants, 
    --and constants cannot be used before they are defined. Therefore, we place the `shallowPropagate` function before `checkDirty`.
    const function shallowPropagate(link: Link): ()
        local cur: Link? = link;
        while (cur ~= nil) do
            const sub = cur.sub;
            const flags = sub.flags;
            if (bit32.band(flags, PENDING_DIRTY_MASK) == FLAG_PENDING) then
                sub.flags = bit32.bor(flags, FLAG_DIRTY);
                if (bit32.band(flags, SHALLOW_NOTIFY_CHECK_MASK) == FLAG_WATCHING) then
                    notify(sub);
                end;
            end;
            cur = cur.nextSub;
        end;
    end;

    const function checkDirty(link: Link, sub: ReactiveNode): boolean
        --NOTE: similar to the one above in the `propagate` function.
        local stack: { Link }? = nil;
        local depth = 0;
        local dirty = false;

        while (true) do
            const dep = link.dep;
            const flags = dep.flags;

            if (bit32.btest(sub.flags, FLAG_DIRTY)) then
                dirty = true;
            elseif (bit32.band(flags, MUTABLE_DIRTY_MASK) == MUTABLE_DIRTY_MASK) then
                const subs = dep.subs :: Link;
                if (update(dep)) then
                    if (subs.nextSub ~= nil) then
                        shallowPropagate(subs);
                    end;
                    dirty = true;
                end;
            elseif (bit32.band(flags, MUTABLE_PENDING_CHECK_MASK) == MUTABLE_PENDING_CHECK_MASK) then
                const frames: { Link } = stack or table.create(4) :: { Link };
                stack = frames;
                --NOTE: Luau does not have a `++` operator, so we add 1 to `depth` using the standard `+=` operator.
                depth += 1;
                frames[depth] = link;
                link = dep.deps :: Link;
                sub = dep;
                continue;
            end;
            
            --NOTE: There is no `!` operator for use with `if` in Luau, so we use the standard `not` operator instead.
            if (not dirty) then
                const nextDep = link.nextDep;
                if (nextDep ~= nil) then
                    link = nextDep;
                    continue;
                end;
            end;

            --NOTE: Luau does not support `::labels::`, so using `continue` would simply keep the loop running—resulting in 
            --an infinite loop. Therefore, we use a flag and exit the loop via `break`.
            local isBreakedToTop: boolean = false;
            --NOTE: `depth` replaces the `checkDepth` counter from the original implementation: the number of elements in 
            --the stack is exactly the number of levels we have descended into. Unlike in JS, Luau does not support the `--` 
            --operator after a numeric variable in a loop; therefore, we use the basic expression `(depth > 0)` and decrease 
            --`depth` manually.
            while (depth > 0) do
                link = (stack :: { Link })[depth];
                depth -= 1;
                if (dirty) then
                    --NOTE: `sub` is always equal to `link.dep` here, so we read `sub.subs`, exactly as in the original.
                    const subs = sub.subs :: Link;
                    if (update(sub)) then
                        if (subs.nextSub ~= nil) then
                            shallowPropagate(subs);
                        end;
                        sub = link.sub;
                        continue;
                    end;
                    dirty = false;
                else
                    sub.flags = bit32.band(sub.flags, CLEAR_PENDING_FLAG);
                end;
                sub = link.sub;
                const nextDep = link.nextDep;
                if (nextDep ~= nil) then
                    link = nextDep;
                    isBreakedToTop = true;
                    break;
                end;
            end;

            --NOTE: Check the flag; if it’s `true`, continue the main loop.
            if isBreakedToTop then
                continue;
            end;

            return (dirty and sub.flags ~= 0);
        end
        --NOTE: It will never actually be thrown here, but in Luau, omitting this line would result in a `TypeError`:
        --Type Error: Not all codepaths in this function return 'boolean'.
        return false;
    end;

    --NOTE: we return a frozen table so that the reactive system remains immutable.
    return table.freeze {
        link = link,
        unlink = unlink,
        propagate = propagate,
        checkDirty = checkDirty,
        shallowPropagate = shallowPropagate,
    };
end system.createReactiveSystem = createReactiveSystem;

return table.freeze(system)
