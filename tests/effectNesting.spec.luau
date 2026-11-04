--!strict
const h = require './_helpers'
const describe, test, eq = h.describe, h.test, h.eq
const signal, effect = h.signal, h.effect

describe("effect: nesting", function()
    test("on parent re-run, old child is disposed and one new child is created", function()
        const s = signal(1)
        local parentRuns, childRuns, childCleanups = 0, 0, 0
        effect(function()
            s()
            parentRuns += 1
            effect(function()
                s()
                childRuns += 1
                return function()
                    childCleanups += 1
                end
            end)
        end)
        eq(parentRuns, 1)
        eq(childRuns, 1)
        s(2)
        eq(parentRuns, 2)
        eq(childRuns, 2, "child must not run twice")
        eq(childCleanups, 1)
        s(3)
        eq(parentRuns, 3)
        eq(childRuns, 3)
        eq(childCleanups, 2)
    end)

    test("child reacts to its signal without re-running parent", function()
        const a, b = signal(1), signal(1)
        local parentRuns, childRuns = 0, 0
        effect(function()
            a()
            parentRuns += 1
            effect(function()
                b()
                childRuns += 1
            end)
        end)
        b(2)
        eq(parentRuns, 1)
        eq(childRuns, 2)
        b(3)
        eq(parentRuns, 1)
        eq(childRuns, 3)
    end)

    test("parent dispose disposes children (and runs their cleanup)", function()
        const s = signal(1)
        local childRuns, childCleanups = 0, 0
        const stop = effect(function()
            effect(function()
                s()
                childRuns += 1
                return function()
                    childCleanups += 1
                end
            end)
        end)
        eq(childRuns, 1)
        stop()
        eq(childCleanups, 1)
        s(2)
        eq(childRuns, 1)
    end)

    test("parent reading signal(nil) correctly re-runs together with children", function()
        const s = signal(nil)
        local parentRuns, childRuns = 0, 0
        effect(function()
            s()
            parentRuns += 1
            effect(function()
                childRuns += 1
            end)
        end)
        s(1)
        s(2)
        eq(parentRuns, 3)
        eq(childRuns, 3)
    end)
end)

return nil
