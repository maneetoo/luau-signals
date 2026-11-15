--!strict
const lib = require '../src'
const h = require './_helpers'
const describe, test, eq, truthy = h.describe, h.test, h.eq, h.truthy
const signal, computed, effect, effectScope, isSignal = h.signal, h.computed, h.effect, h.effectScope, h.isSignal

type Signal<T> = lib.Signal<T>
type Computed<T> = lib.Computed<T>
type Disposer = lib.Disposer

describe("types", function()
    test("signal(x) is a Signal<T>: read gives T, write takes T", function()
        const n: Signal<number> = signal(1)
        const v: number = n()
        n(v + 1)
        eq(n(), 2)
        const str = signal("a")
        const s: string = str()
        str(s .. "b")
        eq(str(), "ab")
    end)

    test("signal() with no argument is a Signal<T?>", function()
        const o: Signal<number?> = signal()
        const v: number? = o()
        eq(v, nil)
        o(5)
        eq(o(), 5)
        o(nil)
        eq(o(), nil)
    end)

    test("computed infers T from the getter", function()
        const n = signal(2)
        const c: Computed<number> = computed(function()
            return n() * 2
        end)
        const v: number = c()
        eq(v, 4)
    end)

    test("computed getter may take the previous value", function()
        const n = signal(1)
        const c: Computed<number> = computed(function(prev: number?)
            return (prev or 0) + n()
        end)
        eq(c(), 1)
        n(2)
        eq(c(), 3)
    end)

    test("effect and effectScope return a Disposer", function()
        const stopEffect: Disposer = effect(function() end)
        const stopCleanup: Disposer = effect(function()
            return function() end
        end)
        const stopScope: Disposer = effectScope(function() end)
        stopEffect()
        stopCleanup()
        stopScope()
    end)

    test("type guards accept any value", function()
        const n = signal(1)
        truthy(isSignal(n))
        eq(isSignal(nil), false)
        eq(isSignal(5), false)
        eq(isSignal("x"), false)
        eq(isSignal({}), false)
    end)
end)

return nil
