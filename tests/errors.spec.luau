--!strict
const h = require './_helpers'
const describe, test, eq, eqLog, push, throws = h.describe, h.test, h.eq, h.eqLog, h.push, h.throws
const signal, computed, effect, getActiveSub, getBatchDepth, startBatch, endBatch =
    h.signal, h.computed, h.effect, h.getActiveSub, h.getBatchDepth, h.startBatch, h.endBatch

describe("errors: flush", function()
    test("effect that throws during flush: error is re-thrown, queued effects are not lost", function()
        const s = signal(0)
        const log = {}
        effect(function()
            if s() == 1 then
                error("boom", 0)
            end
        end)
        effect(function()
            push(log, s())
        end)
        eqLog(log, { 0 })
        eq(throws(function()
            s(1)
        end), "boom")
        eq(getActiveSub(), nil)
        eq(getBatchDepth(), 0)
        --the second effect was queued but not run: it must be notified again by the next write
        eqLog(log, { 0 })
        s(2)
        eq(log[#log], "2")
    end)

    test("after a throwing flush the queue cursors are reset: unrelated effects still work", function()
        const bad, good = signal(0), signal(0)
        const log = {}
        effect(function()
            if bad() == 1 then
                error("boom", 0)
            end
        end)
        effect(function()
            push(log, good())
        end)
        throws(function()
            bad(1)
        end)
        good(1)
        good(2)
        eqLog(log, { 0, 1, 2 })
    end)

    test("error inside a batch is re-thrown from endBatch, batch depth is restored", function()
        const s = signal(0)
        effect(function()
            if s() == 1 then
                error("boom", 0)
            end
        end)
        startBatch()
        s(1)
        eq(throws(function()
            endBatch()
        end), "boom")
        eq(getBatchDepth(), 0)
        eq(getActiveSub(), nil)
    end)

    test("cleanup that throws: error is re-thrown as-is, activeSub is restored, other effects keep working", function()
        const s, other = signal(0), signal(0)
        local runs, cleanups, otherRuns = 0, 0, 0
        effect(function()
            s()
            runs += 1
            return function()
                cleanups += 1
                error("cleanup boom", 0)
            end
        end)
        effect(function()
            other()
            otherRuns += 1
        end)
        eq(throws(function()
            s(1)
        end), "cleanup boom")
        eq(getActiveSub(), nil)
        eq(runs, 1, "the effect must not re-run after its cleanup threw")
        eq(cleanups, 1)
        other(1)
        eq(otherRuns, 2)
    end)
end)

describe("errors: assignment happens before purgeDeps (as in the original `try`/`finally`)", function()
    --NOTE: both tests below make `purgeDeps` throw: the run that is being finished stops reading a computed `d` that owns
    --a child effect, so `d` loses its last subscriber and the child's cleanup (which throws) runs from `purgeDeps`.

    test("computed: value computed by the getter is already stored when purgeDeps throws", function()
        const toggle, dep = signal(true), signal(0)
        local boom = false
        const d = computed(function()
            effect(function()
                dep()
                return function()
                    if boom then
                        error("cleanup boom", 0)
                    end
                end
            end)
            return 1
        end)
        const c = computed(function()
            if toggle() then
                return d()
            end
            return 2
        end)
        eq(c(), 1)
        boom = true
        toggle(false)
        eq(throws(function()
            c()
        end), "cleanup boom")
        eq(getActiveSub(), nil)
        eq(c(), 2, "c.value must already hold the new value")
    end)

    test("effect: cleanup returned by the callback is already stored when purgeDeps throws", function()
        const toggle, dep = signal(true), signal(0)
        local boom = false
        local lastCleanupRuns = 0
        const d = computed(function()
            effect(function()
                dep()
                return function()
                    if boom then
                        error("cleanup boom", 0)
                    end
                end
            end)
            return 1
        end)
        const stop = effect(function()
            if toggle() then
                d()
            end
            return function()
                lastCleanupRuns += 1
            end
        end)
        boom = true
        eq(throws(function()
            toggle(false)
        end), "cleanup boom")
        eq(getActiveSub(), nil)
        eq(lastCleanupRuns, 1, "only the first cleanup has run so far")
        stop()
        eq(lastCleanupRuns, 2, "the cleanup of the failed re-run must be stored, so dispose runs it")
    end)
end)

describe("flush: early exit when nothing is queued", function()
    test("write to a signal watched only by computeds, then a batch of such writes", function()
        const s = signal(0)
        const c = computed(function()
            return s() + 1
        end)
        eq(c(), 1)
        startBatch()
        s(5)
        endBatch()
        eq(c(), 6)
        local runs = 0
        effect(function()
            s()
            runs += 1
        end)
        s(6)
        eq(runs, 2)
        eq(c(), 7)
    end)

    test("nested empty flush inside an effect does not break the queue", function()
        const a, mirror = signal(0), signal(0)
        const doubled = computed(function()
            return mirror() * 2
        end)
        eq(doubled(), 0)
        const log = {}
        --NOTE: the second effect is the last one in the queue, so the write to `mirror` (watched only by a computed) makes
        --a nested `flush` that finds the queue empty.
        effect(function()
            push(log, a())
        end)
        effect(function()
            mirror(a() + 1)
        end)
        a(1)
        a(2)
        a(3)
        eqLog(log, { 0, 1, 2, 3 })
        eq(doubled(), 8)
    end)
end)

return nil
