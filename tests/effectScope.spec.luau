--!strict
const h = require './_helpers'
const describe, test, eq, eqLog, push, truthy, throws = h.describe, h.test, h.eq, h.eqLog, h.push, h.truthy, h.throws
const signal, effect, effectScope, getActiveSub, isEffect, isEffectScope = h.signal, h.effect, h.effectScope, h.getActiveSub, h.isEffect, h.isEffectScope

describe("effectScope", function()
    test("runs the function immediately", function()
        local ran = false
        effectScope(function()
            ran = true
        end)
        truthy(ran)
    end)

    test("disposer disposes all effects in scope and runs cleanup", function()
        const s = signal(1)
        const log = {}
        const stop = effectScope(function()
            effect(function()
                push(log, "a" .. s())
                return function()
                    push(log, "ca")
                end
            end)
            effect(function()
                push(log, "b" .. s())
            end)
        end)
        eqLog(log, { "a1", "b1" })
        s(2)
        eqLog(log, { "a1", "b1", "ca", "a2", "b2" })
        stop()
        eqLog(log, { "a1", "b1", "ca", "a2", "b2", "ca" })
        s(3)
        eqLog(log, { "a1", "b1", "ca", "a2", "b2", "ca" })
    end)

    test("effects outside the scope are untouched", function()
        const s = signal(1)
        local outer, inner = 0, 0
        effect(function()
            s()
            outer += 1
        end)
        const stop = effectScope(function()
            effect(function()
                s()
                inner += 1
            end)
        end)
        stop()
        s(2)
        eq(outer, 2)
        eq(inner, 1)
    end)

    test("nested scopes are disposed together with outer", function()
        const s = signal(1)
        local runs = 0
        const stop = effectScope(function()
            effectScope(function()
                effect(function()
                    s()
                    runs += 1
                end)
            end)
        end)
        s(2)
        eq(runs, 2)
        stop()
        s(3)
        eq(runs, 2)
    end)

    test("disposing the inner scope does not touch the outer one", function()
        const s = signal(1)
        local outerRuns, innerRuns = 0, 0
        local stopInner
        effectScope(function()
            effect(function()
                s()
                outerRuns += 1
            end)
            stopInner = effectScope(function()
                effect(function()
                    s()
                    innerRuns += 1
                end)
            end)
        end)
        stopInner()
        s(2)
        eq(outerRuns, 2)
        eq(innerRuns, 1)
    end)

    test("disposer is safe to call repeatedly; node kind is scope", function()
        const stop = effectScope(function() end)
        truthy(isEffectScope(stop))
        eq(isEffect(stop), false)
        stop()
        stop()
    end)

    test("error inside scope is re-thrown, activeSub is restored", function()
        const err = throws(function()
            effectScope(function()
                error("in scope", 0)
            end)
        end)
        eq(err, "in scope")
        eq(getActiveSub(), nil)
    end)

    test("effect created inside an effect inside a scope dies with the scope", function()
        const s = signal(1)
        local runs = 0
        const stop = effectScope(function()
            effect(function()
                effect(function()
                    s()
                    runs += 1
                end)
            end)
        end)
        eq(runs, 1)
        stop()
        s(2)
        eq(runs, 1)
    end)
end)

return nil
