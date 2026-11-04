--!strict
const lib = require '../src'
const getActiveSub, setActiveSub, getBatchDepth, startBatch, endBatch, isSignal, isEffect, isEffectScope, signal, computed, effect, effectScope, trigger =
    lib.getActiveSub, lib.setActiveSub, lib.getBatchDepth, lib.startBatch, lib.endBatch, lib.isSignal,
    lib.isEffect, lib.isEffectScope, lib.signal, lib.computed, lib.effect, lib.effectScope, lib.trigger

local passed, failed, group = 0, 0, ""
const failures: { string } = {}

const function describe(name: string, body: () -> ())
    group = name
    body()
    group = ""
end

const function test(name: string, body: () -> ())
    local ok, err = pcall(body)
    const leaked = {}
    if getActiveSub() ~= nil then
        table.insert(leaked, "activeSub must be nil")
        setActiveSub(nil)
    end
    if getBatchDepth() ~= 0 then
        table.insert(leaked, `batchDepth = { getBatchDepth() }`)
        while getBatchDepth() > 0 do
            endBatch()
        end
    end
    if #leaked > 0 then
        const suffix = "leaker: " .. table.concat(leaked, ", ")
        err = if ok then suffix else tostring(err) .. " | " .. suffix
        ok = false
    end
    if ok then
        passed += 1
    else
        failed += 1
        table.insert(failures, string.format("[%s] %s\n    %s", group, name, tostring(err)))
    end
end

const function fmt(v: any): string
    if type(v) == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

const function eq(actual: any, expected: any, msg: string?)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "eq", fmt(expected), fmt(actual)), 2)
    end
end

const function truthy(v: any, msg: string?)
    if not v then
        error(msg or "expected truthy value", 2)
    end
end

const function push(log: { string }, v: any)
    table.insert(log, tostring(v))
end

const function eqLog(log: { string }, expected: { any }, msg: string?)
    const e = {}
    for i, v in expected do
        e[i] = tostring(v)
    end
    const a, b = table.concat(log, ","), table.concat(e, ",")
    if a ~= b then
        error(string.format("%s: expected log [%s], got [%s]", msg or "log", b, a), 2)
    end
end

const function throws(body: () -> ()): any
    const ok, err = pcall(body)
    if ok then
        error("expected exception but none was thrown", 2)
    end
    return err
end

const function lcg(seed: number)
    local state = seed
    return function(n: number): number
        state = (state * 48271) % 2147483647
        return state % n + 1
    end
end

const function report(): number
    if failed == 0 then
        print(`passed: { passed }`)
        return 0
    end
    print(`failed: { failed } of { passed + failed }\n`)
    for _, msg in failures do
        print(msg)
    end
    return 1
end

return {
    describe = describe,
    test = test,
    eq = eq,
    truthy = truthy,
    push = push,
    eqLog = eqLog,
    throws = throws,
    lcg = lcg,
    report = report,
    signal = signal,
    computed = computed,
    effect = effect,
    effectScope = effectScope,
    trigger = trigger,
    getActiveSub = getActiveSub,
    setActiveSub = setActiveSub,
    getBatchDepth = getBatchDepth,
    startBatch = startBatch,
    endBatch = endBatch,
    isSignal = isSignal,
    isEffect = isEffect,
    isEffectScope = isEffectScope,
}