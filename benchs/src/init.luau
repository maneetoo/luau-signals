--!strict

const shared = require '@self/shared'
const groups, scenarios = shared.groups, shared.scenarios

const fluid, vide, signals = 
    require '@self/fluid', require '@self/vide', require '@self/signals'

const SAMPLES, TARGET_SAMPLE, HUGE = 11, .03, math.huge
const YIELD_BETWEEN_GROUPS: boolean, STOP_ON_MISSING: boolean = true, false

type Scope = 'fluid' | 'vide' | 'signals'
type Group = 'source' | 'write' | 'effect' | 'derive' | 'batch' | 'all'

type Instance = {
	step: (number) -> any,
	dispose: (() -> ())?,
	tick: number,
	n: number,
	samples: { number },
}

type ScenResult = {
	med: number,
	min: number,
	err: string?,
}

const median = function(xs: { number }): number
	const c = table.clone(xs)
	table.sort(c)
	return c[(#c + 1) // 2]
end

const minOf = function(xs: { number }): number
	local m: number = HUGE
	for _, x in xs do
		if x < m then
			m = x
		end
	end
	return m
end

const timeRun = function(inst: Instance, n: number): number
	const step = inst.step
    local k = inst.tick
	const t = os.clock()
	for _ = 1, n do
		k += 1
		step(k)
	end
	inst.tick = k
	return os.clock() - t
end

const calibrate = function(inst: Instance): number
	local n: number = 1
	while true do
		if timeRun(inst, n) >= TARGET_SAMPLE or n >= 2 ^ 26 then
			return n
		end
		n *= 2
	end
end

const fmtNs = function(x: number): string
	if x >= 1e6 then
		return string.format("%.2f ms", x / 1e6)
	elseif x >= 1e3 then
		return string.format("%.2f µs", x / 1e3)
	end
	return string.format("%.1f ns", x)
end

const runScenario = function(sc, L: shared.Lib): ScenResult
	local inst: Instance?, err: string? = nil, nil
	const ok, step, dispose = pcall(sc.setup, L)
	if ok then
		inst = { step = step, dispose = dispose, tick = 0, n = 1, samples = {} }
	else
		err = tostring(step)
	end

	if inst then
		inst.n = calibrate(inst :: Instance)
		timeRun(inst :: Instance, inst.n)
		for _ = 1, SAMPLES do
			gcinfo()
			table.insert(inst.samples, timeRun(inst :: Instance, inst.n) / inst.n * 1e9)
		end
		if inst.dispose then
			pcall(inst.dispose)
		end
	end

	local med = if inst then median(inst.samples) else nil
	local mn = if inst then minOf(inst.samples) else nil

	return { med = med :: number, min = mn :: number, err = err }
end

return function(scope: Scope?, group: Group?, waitBeforeStart: number?): ()
    scope, group = (scope or 'signals'), (group or 'all')
    waitBeforeStart = (waitBeforeStart or 0)

    assert((function(): boolean
        if (scope == 'fluid' or scope == 'signals' or scope == 'vide') then
            return true
        end
        return false
    end)(), `scope must be 'fluid' | 'vide' | 'signals': got {scope}`)
    assert((function(): boolean
        if (group == 'source' or group == 'write' or group == 'effect' or group == 'derive' or group == 'batch' or group == 'all') then
            return true
        end
        return false
    end)(), `group must be 'source' | 'write' | 'effect' | 'derive' | 'batch' | 'all': got {group}`)
    assert(type(waitBeforeStart) == 'number', `waitBeforeStart must be number, got: {type(waitBeforeStart)}`)

    if ((waitBeforeStart ~= nil) and (task and task.wait)) then
        task.wait(waitBeforeStart)
    end

    const scenariosToBench: { string } = groups[group]
    local L: shared.Lib
    if (scope == 'fluid') then L = fluid
    elseif (scope == 'vide') then L = vide
    else L = signals end

    const byName: { [string]: any } = {}
    for _, s in scenarios do
        byName[s.name] = s
    end

	print(`{scope} ({group}) benchmark is starting...`)

    for _, name in scenariosToBench do
        const sc = byName[name]
        if sc == nil then
            if STOP_ON_MISSING then
                error(`[{scope}] scenario {name} not found`, 2)
            end
            print(`[{scope}] {name} - ERROR: scenario not found`)
        else
            const r = runScenario(sc, L)
            if r.err then
                print(`[{scope}] {name} - ERROR: {r.err}`)
            else
                print(`[{scope}] {name} - avg. {fmtNs(r.med)}`)
            end
        end

		if (task and task.wait) then
            task.wait()
        end
    end
end
