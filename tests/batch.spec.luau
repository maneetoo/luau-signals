--!strict
const h = require './_helpers'
const describe, test, eq, eqLog, push = h.describe, h.test, h.eq, h.eqLog, h.push
const signal, computed, effect, startBatch, endBatch, getBatchDepth = h.signal, h.computed, h.effect, h.startBatch, h.endBatch, h.getBatchDepth

describe("batch", function()
    test("defers effect run until endBatch", function()
        local a, b = signal(1), signal(2)
        local log = {}
        effect(function()
            push(log, a() + b())
        end)
        startBatch()
        a(10)
        b(20)
        eqLog(log, { 3 })
        endBatch()
        eqLog(log, { 3, 30 })
    end)

    test("inside a batch, reading a signal sees the new value", function()
        const s = signal(1)
        startBatch()
        s(5)
        eq(s(), 5)
        endBatch()
    end)

    test("inside a batch, computed returns the fresh value", function()
        const s = signal(1)
        const c = computed(function()
            return s() * 2
        end)
        eq(c(), 2)
        startBatch()
        s(4)
        eq(c(), 8)
        endBatch()
    end)

    test("nested batches: flush only on the outer endBatch", function()
        const s = signal(0)
        local runs = 0
        effect(function()
            s()
            runs += 1
        end)
        startBatch()
        startBatch()
        s(1)
        endBatch()
        eq(runs, 1)
        s(2)
        endBatch()
        eq(runs, 2)
    end)

    test("getBatchDepth reflects nesting", function()
        eq(getBatchDepth(), 0)
        startBatch()
        eq(getBatchDepth(), 1)
        startBatch()
        eq(getBatchDepth(), 2)
        endBatch()
        eq(getBatchDepth(), 1)
        endBatch()
        eq(getBatchDepth(), 0)
    end)

    test("effect depending on several changed signals runs once", function()
        const a, b, c = signal(1), signal(1), signal(1)
        local runs = 0
        effect(function()
            a()
            b()
            c()
            runs += 1
        end)
        startBatch()
        a(2)
        b(2)
        c(2)
        endBatch()
        eq(runs, 2)
    end)

    test("write that restores the previous value inside a batch: effect stays consistent", function()
        const s = signal(1)
        const log = {}
        effect(function()
            push(log, s())
        end)
        startBatch()
        s(2)
        s(1)
        endBatch()
        eq(s(), 1)
        eq(log[1], "1")
        eq(log[#log], "1")
    end)
end)

return nil
