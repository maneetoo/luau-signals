--!strict
const h = require './_helpers'
const describe, test, eq, eqLog, push, truthy = h.describe, h.test, h.eq, h.eqLog, h.push, h.truthy
const signal, effect, getActiveSub, setActiveSub, isEffect, isSignal = h.signal, h.effect, h.getActiveSub, h.setActiveSub, h.isEffect, h.isSignal

describe("effect", function()
    test("runs immediately and exactly once", function()
        local runs = 0
        effect(function()
            runs += 1
        end)
        eq(runs, 1)
    end)

    test("re-runs when a dependency changes", function()
        const s = signal(1)
        const log = {}
        effect(function()
            push(log, s())
        end)
        s(2)
        s(3)
        eqLog(log, { 1, 2, 3 })
    end)

    test("tracks several signals", function()
        const a, b = signal(1), signal(10)
        const log = {}
        effect(function()
            push(log, a() + b())
        end)
        a(2)
        b(20)
        eqLog(log, { 11, 12, 22 })
    end)

    test("dynamic dependencies: branch that wasn't read does not trigger", function()
        const cond, a, b = signal(true), signal("a"), signal("b")
        const log = {}
        effect(function()
            if cond() then
                push(log, a())
            else
                push(log, b())
            end
        end)
        b("b2")
        eqLog(log, { "a" })
        cond(false)
        eqLog(log, { "a", "b2" })
        a("a2")
        eqLog(log, { "a", "b2" })
        b("b3")
        eqLog(log, { "a", "b2", "b3" })
    end)

    test("effects of the same signal run in creation order", function()
        const s = signal(0)
        const log = {}
        for _, name in { "a", "b", "c" } do
            effect(function()
                s()
                push(log, name)
            end)
        end
        eqLog(log, { "a", "b", "c" })
        s(1)
        eqLog(log, { "a", "b", "c", "a", "b", "c" })
    end)

    test("disposer stops the effect; repeated call is safe", function()
        const s = signal(1)
        local runs = 0
        const stop = effect(function()
            s()
            runs += 1
        end)
        s(2)
        eq(runs, 2)
        stop()
        s(3)
        eq(runs, 2)
        stop()
        s(4)
        eq(runs, 2)
    end)

    test("disposer is a callable effect node", function()
        const stop = effect(function() end)
        truthy(isEffect(stop))
        eq(isSignal(stop), false)
    end)

    test("cleanup runs before re-run and on dispose", function()
        const s = signal(1)
        const log = {}
        const stop = effect(function()
            const v = s()
            push(log, "run" .. v)
            return function()
                push(log, "cleanup" .. v)
            end
        end)
        s(2)
        stop()
        eqLog(log, { "run1", "cleanup1", "run2", "cleanup2" })
        stop()
        eqLog(log, { "run1", "cleanup1", "run2", "cleanup2" }, "cleanup must not run twice")
    end)

    test("effect without cleanup works", function()
        const s = signal(1)
        local runs = 0
        const stop = effect(function()
            s()
            runs += 1
        end)
        s(2)
        stop()
        eq(runs, 2)
    end)

    test("cleanup does not track dependencies", function()
        const a, b = signal(1), signal(1)
        local runs = 0
        effect(function()
            a()
            runs += 1
            return function()
                b()
            end
        end)
        b(2)
        eq(runs, 1)
        a(2)
        eq(runs, 2)
        b(3)
        eq(runs, 2)
    end)

    test("cleanup can dispose its own effect — no re-run", function()
        const s = signal(1)
        local runs = 0
        local stop; stop = effect(function()
            s()
            runs += 1
            return function()
                stop()
            end
        end)
        s(2)
        eq(runs, 1)
        s(3)
        eq(runs, 1)
    end)

    test("effect writing to another signal triggers dependent effects", function()
        const a, b = signal(1), signal(0)
        const log = {}
        effect(function()
            b(a() * 2)
        end)
        effect(function()
            push(log, b())
        end)
        a(2)
        a(3)
        eqLog(log, { 2, 4, 6 })
    end)

    test("getActiveSub: not nil inside effect, nil outside", function()
        eq(getActiveSub(), nil)
        local inside
        effect(function()
            inside = getActiveSub()
        end)
        truthy(inside ~= nil)
        eq(getActiveSub(), nil)
    end)

    test("setActiveSub(nil) allows reading without subscription", function()
        const a, b = signal(1), signal(1)
        local runs = 0
        effect(function()
            a()
            const prev = setActiveSub(nil)
            b()
            setActiveSub(prev)
            runs += 1
        end)
        b(2)
        eq(runs, 1)
        a(2)
        eq(runs, 2)
    end)

    test("setActiveSub returns previous subscriber", function()
        eq(setActiveSub(nil), nil)
        effect(function()
            const cur = getActiveSub()
            eq(setActiveSub(nil), cur)
            eq(setActiveSub(cur), nil)
        end)
    end)

    test("many subscribers to a single signal", function()
        const s = signal(0)
        local count = 0
        for _ = 1, 1000 do
            effect(function()
                s()
                count += 1
            end)
        end
        eq(count, 1000)
        s(1)
        eq(count, 2000)
    end)
end)

return nil
