--!strict
const h = require './_helpers'
const describe, test, eq, eqLog, push, truthy, throws = h.describe, h.test, h.eq, h.eqLog, h.push, h.truthy, h.throws
const signal, computed, effect, getActiveSub = h.signal, h.computed, h.effect, h.getActiveSub

describe("computed", function()
    test("lazy evaluation: getter not called until first read", function()
        const s = signal(1)
        local runs = 0
        const c = computed(function()
            runs += 1
            return s() * 2
        end)
        eq(runs, 0)
        s(2)
        eq(runs, 0)
        eq(c(), 4)
        eq(runs, 1)
    end)

    test("value is cached between reads", function()
        const s = signal(1)
        local runs = 0
        const c = computed(function()
            runs += 1
            return s() + 1
        end)
        eq(c(), 2)
        eq(c(), 2)
        eq(c(), 2)
        eq(runs, 1)
    end)

    test("re-computed lazily after a dependency change", function()
        const s = signal(1)
        local runs = 0
        const c = computed(function()
            runs += 1
            return s() + 1
        end)
        eq(c(), 2)
        s(5)
        s(6)
        eq(runs, 1)
        eq(c(), 7)
        eq(runs, 2)
    end)

    test("previous value is passed to the getter (nil on first call)", function()
        const s = signal(1)
        local prevs = {}
        const c = computed(function(prev)
            push(prevs, prev)
            return s() * 10
        end)
        c()
        s(2)
        c()
        s(3)
        c()
        eqLog(prevs, { "nil", 10, 20 })
    end)

    test("computed chain", function()
        const s = signal(1)
        const a = computed(function()
            return s() + 1
        end)
        const b = computed(function()
            return a() * 2
        end)
        const c = computed(function()
            return b() + 3
        end)
        eq(c(), 7)
        s(2)
        eq(c(), 9)
        eq(b(), 6)
        eq(a(), 3)
    end)

    test("deep chain", function()
        const DEPTH = 60
        const s = signal(0)
        local node: any = computed(function()
            return s()
        end)
        for _ = 1, DEPTH do
            const prev = node
            node = computed(function()
                return prev() + 1
            end)
        end
        eq(node(), DEPTH)
        s(10)
        eq(node(), DEPTH + 10)
    end)

    test("diamond: effect runs once, without glitches", function()
        const a = signal(1)
        const b = computed(function()
            return a() * 2
        end)
        const c = computed(function()
            return a() + 1
        end)
        local dRuns = 0
        const d = computed(function()
            dRuns += 1
            return b() + c()
        end)
        const log = {}
        effect(function()
            push(log, d())
        end)
        a(2)
        eqLog(log, { 4, 7 })
        eq(dRuns, 2)
    end)

    test("if computed returns the same value, subscribers do not re-run", function()
        const s = signal(0)
        const parity = computed(function()
            return s() % 2
        end)
        const log = {}
        effect(function()
            push(log, parity())
        end)
        s(2)
        eqLog(log, { 0 })
        s(3)
        eqLog(log, { 0, 1 })
        s(5)
        eqLog(log, { 0, 1 })
    end)

    test("computed dynamic dependencies", function()
        const cond, a, b = signal(true), signal("a"), signal("b")
        local runs = 0
        const c = computed(function()
            runs += 1
            if cond() then
                return a()
            else
                return b()
            end
        end)
        eq(c(), "a")
        eq(runs, 1)
        b("b2")
        eq(c(), "a")
        eq(runs, 1, "b was not read")
        cond(false)
        eq(c(), "b2")
        eq(runs, 2)
        a("a2")
        eq(c(), "b2")
        eq(runs, 2, "a is no longer a dependency")
    end)

    test("computed can return nil and false", function()
        const s = signal(0)
        const c = computed(function()
            const v = s()
            if v == 0 then
                return nil
            elseif v == 1 then
                return false
            end
            return v
        end)
        eq(c(), nil)
        s(1)
        eq(c(), false)
        s(2)
        eq(c(), 2)
    end)

    test("effect re-runs when computed actually changed", function()
        const s = signal(1)
        const c = computed(function()
            return s() * 3
        end)
        const log = {}
        effect(function()
            push(log, c())
        end)
        s(2)
        s(3)
        eqLog(log, { 3, 6, 9 })
    end)

    test("after the last subscriber is removed, computed remains correct", function()
        const s = signal(1)
        local runs = 0
        const c = computed(function()
            runs += 1
            return s() * 2
        end)
        const stop = effect(function()
            c()
        end)
        eq(runs, 1)
        stop()
        s(2)
        eq(runs, 1, "no subscribers — no recompute")
        eq(c(), 4)
        eq(runs, 2)
        eq(c(), 4)
        eq(runs, 2)
    end)

    test("reading outside an effect does not create subscriptions on the effect", function()
        const s = signal(1)
        const c = computed(function()
            return s()
        end)
        local runs = 0
        effect(function()
            runs += 1
        end)
        c()
        s(2)
        eq(runs, 1)
    end)

    test("getActiveSub inside getter is the computed itself, nil after read", function()
        local inside
        const c = computed(function()
            inside = getActiveSub()
            return 1
        end)
        c()
        truthy(inside ~= nil)
        eq(getActiveSub(), nil)
    end)

    test("error in getter is re-thrown as-is, state is restored", function()
        const obj = { msg = "boom" }
        const s = signal(1)
        const c = computed(function()
            s()
            error(obj)
        end)
        const err = throws(function()
            c()
        end)
        eq(err, obj)
        eq(getActiveSub(), nil)
        local d = computed(function()
            return s() + 1
        end)
        eq(d(), 2)
        s(5)
        eq(d(), 6)
    end)

    test("error during re-computation does not overwrite the old value", function()
        const s = signal(1)
        const c = computed(function()
            const v = s()
            if v == 2 then
                error("bad", 0)
            end
            return v * 10
        end)
        eq(c(), 10)
        s(2)
        eq(throws(function()
            c()
        end), "bad")
        eq(getActiveSub(), nil)
        s(3)
        eq(c(), 30)
    end)
end)

return nil
