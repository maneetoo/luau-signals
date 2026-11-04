--!strict
const h = require './_helpers'
const describe, test, eq, eqLog, push, throws = h.describe, h.test, h.eq, h.eqLog, h.push, h.throws
const signal, effect, trigger, getBatchDepth, getActiveSub = h.signal, h.effect, h.trigger, h.getBatchDepth, h.getActiveSub

describe("trigger", function()
    test("re-runs effects of read signals without changing the value", function()
        const s = signal(1)
        local runs = 0
        effect(function()
            s()
            runs += 1
        end)
        trigger(function()
            s()
        end)
        eq(runs, 2)
        eq(s(), 1)
    end)

    test("affects only signals read inside", function()
        const a, b = signal(1), signal(1)
        local runsA, runsB = 0, 0
        effect(function()
            a()
            runsA += 1
        end)
        effect(function()
            b()
            runsB += 1
        end)
        trigger(function()
            a()
        end)
        eq(runsA, 2)
        eq(runsB, 1)
    end)

    test("multiple signals — effect runs once (inside a batch)", function()
        const a, b = signal(1), signal(1)
        local runs = 0
        effect(function()
            a()
            b()
            runs += 1
        end)
        trigger(function()
            a()
            b()
        end)
        eq(runs, 2)
    end)

    test("nothing happens without reads", function()
        const s = signal(1)
        local runs = 0
        effect(function()
            s()
            runs += 1
        end)
        trigger(function() end)
        eq(runs, 1)
    end)

    test("inside trigger, batch depth = 1, after it is restored", function()
        local inside
        trigger(function()
            inside = getBatchDepth()
        end)
        eq(inside, 1)
        eq(getBatchDepth(), 0)
    end)

    test("effects do not run until trigger finishes", function()
        const s = signal(1)
        const log = {}
        effect(function()
            s()
            push(log, "effect")
        end)
        trigger(function()
            s()
            push(log, "inside")
        end)
        eqLog(log, { "effect", "inside", "effect" })
    end)

    test("error is re-thrown, batch and activeSub are restored", function()
        const err = throws(function()
            trigger(function()
                error("trig", 0)
            end)
        end)
        eq(err, "trig")
        eq(getBatchDepth(), 0)
        eq(getActiveSub(), nil)
    end)

    test("what was read before the error is still triggered", function()
        const s = signal(1)
        local runs = 0
        effect(function()
            s()
            runs += 1
        end)
        throws(function()
            trigger(function()
                s()
                error("x", 0)
            end)
        end)
        eq(runs, 2)
    end)
end)

return nil
