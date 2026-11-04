--!strict
const h = require './_helpers'
const describe, test, eq, eqLog, push, truthy = h.describe, h.test, h.eq, h.eqLog, h.push, h.truthy
const signal, effect, isSignal = h.signal, h.effect, h.isSignal

describe("signal", function()
    test("reads the first and last recorded value", function()
        const s = signal(1)
        eq(s(), 1)
        s(2)
        eq(s(), 2)
        s(3)
        s(4)
        eq(s(), 4)
    end)

    test("signal() with no arguments stores nil", function()
        const s = signal()
        eq(s(), nil)
        s(7)
        eq(s(), 7)
    end)

    test("`nil` write is a write, not a read", function()
        const s = signal(5)
        const log = {}
        effect(function()
            push(log, s())
        end)
        s(nil)
        eq(s(), nil)
        eqLog(log, { 5, "nil" })
        s(1)
        eqLog(log, { 5, "nil", 1 })
    end)

    test("`signal(nil)` is different from 'no value': writing after `nil` works", function()
        const s = signal(nil)
        const log = {}
        effect(function()
            push(log, s())
        end)
        s(false)
        s(0)
        eqLog(log, { "nil", false, 0 })
    end)

    test("falsy values (false, 0, an empty string) are preserved", function()
        const s = signal(false)
        eq(s(), false)
        s(0)
        eq(s(), 0)
        s("")
        eq(s(), "")
    end)

    test("write returns nothing", function()
        const s = signal(1)
        eq(s(2), nil)
    end)

    test("writing the same value does not trigger the effect", function()
        const s = signal(1)
        local runs = 0
        effect(function()
            s()
            runs += 1
        end)
        s(1)
        s(1)
        eq(runs, 1)
        s(2)
        eq(runs, 2)
        s(2)
        eq(runs, 2)
    end)

    test("tables are compared by identity", function()
        const t = {}
        const s = signal(t)
        local runs = 0
        effect(function()
            s()
            runs += 1
        end)
        s(t)
        eq(runs, 1)
        s({})
        eq(runs, 2)
    end)

    test("signal is a callable table", function()
        const s = signal(1)
        eq(type(s), "table")
        truthy(isSignal(s))
    end)

    test("independent signals do not affect each other", function()
        const a, b = signal(1), signal(2)
        local runsA = 0
        effect(function()
            a()
            runsA += 1
        end)
        b(10)
        eq(runsA, 1)
        eq(b(), 10)
    end)
end)

return nil
