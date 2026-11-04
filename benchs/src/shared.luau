--!strict

export type Lib = {
	name: string,
	source: (any) -> any,
	derive: (() -> any) -> any,
	effect: (() -> ()) -> any,
	effectCleanup: (() -> (), () -> ()) -> any,
	batch: (() -> ()) -> (),
	scope: (() -> ()) -> (() -> ()),
}

const lcg = function(seed: number): (number) -> number
	local state: number = seed
	return function(n: number): number
		state = (state * 48271) % 2147483647
		return state % n + 1
	end
end

const fanOut = function(count: number): (L: Lib) -> ((i: any) -> (), () -> ())
	return function(L: Lib): ((i: any) -> (), () -> ())
		const s = L.source(0)
		local sink = 0
		const dispose = L.scope(function()
			for _ = 1, count do
				L.effect(function()
					sink = s()
				end)
			end
		end)
		return function(i: any)
			s(i)
		end,
			dispose
	end
end

const chain = function(depth: number): (L: Lib) -> ((i: any) -> (), () -> ())
	return function(L: Lib): ((i: any) -> (), () -> ())
		const s = L.source(0)
		local tail: any = s
		const dispose = L.scope(function()
			for _ = 1, depth do
				const prev = tail
				tail = L.derive(function()
					return prev() + 1
				end)
			end
		end)
		tail() -- warm-up: the first pass performs the computation to the full depth
		return function(i: any)
			s(i)
			return tail()
		end,
			dispose
	end
end

const chainWithEffect = function(depth: number): (L: Lib) -> ((i: any) -> (), () -> ())
	return function(L: Lib): ((i: any) -> (), () -> ())
		const s = L.source(0)
		local sink = 0
		const dispose = L.scope(function()
			local tail: any = s
			for _ = 1, depth do
				const prev = tail
				tail = L.derive(function()
					return prev() + 1
				end)
			end
			L.effect(function()
				sink = tail()
			end)
		end)
		return function(i: any)
			s(i)
		end,
			dispose
	end
end

const batchScenario = function(useBatch: boolean)
	return function(L: Lib)
		const srcs: { (number?) -> number } = {}
		local sink: number, cur: number = 0, 0
		const dispose = L.scope(function()
			for k = 1, 10 do
				srcs[k] = L.source(0)
			end
			L.effect(function()
				local sum: number = 0
				for k = 1, 10 do
					sum += srcs[k]()
				end
				sink = sum
			end)
		end)
		const function writeAll()
			for k = 1, 10 do
				srcs[k](cur)
			end
		end
		return function(i)
			cur = i
			if useBatch then
				L.batch(writeAll)
			else
				writeAll()
			end
		end,
			dispose
	end
end

return table.freeze {
    groups = {
        source = {
            "source: create",
            "source: read (untracked)",
            "source: write, no subscribers",
            "source: write, same value (no-op)",
        },
        write = {
            "write -> 1 effect",
            "write -> 10 effects",
            "write -> 100 effects",
        },
        effect = {
            "effect: create + dispose",
            "effect: rerun with cleanup",
            "effect: dynamic deps (branch toggle)",
        },
        derive = {
            "derive: write + read (depth 1)",
            "derive: chain depth 10, write + read tail",
            "derive: chain depth 10 -> effect",
            "derive: chain depth 40, write + read tail",
            "derive: unobserved, write only (lazy vs eager)",
            "derive: diamond -> effect",
            "derive: 1 source -> 50 derives -> 1 effect",
            "derive: cutoff (value unchanged -> effect not rerun)",
        },
        batch = {
            "batch: 10 writes, no batch -> 1 effect",
            "batch: 10 writes, batched -> 1 effect",
            "graph: build 20 src + 20 derive + effect, dispose",
            "mixed: 30 src, 60 derive, 15 effects, random write",
        },
        all = {
            "source: create",
            "source: read (untracked)",
            "source: write, no subscribers",
            "source: write, same value (no-op)",
            "write -> 1 effect",
            "write -> 10 effects",
            "write -> 100 effects",
            "effect: create + dispose",
            "effect: rerun with cleanup",
            "effect: dynamic deps (branch toggle)",
            "derive: write + read (depth 1)",
            "derive: chain depth 10, write + read tail",
            "derive: chain depth 10 -> effect",
            "derive: chain depth 40, write + read tail",
            "derive: unobserved, write only (lazy vs eager)",
            "derive: diamond -> effect",
            "derive: 1 source -> 50 derives -> 1 effect",
            "derive: cutoff (value unchanged -> effect not rerun)",
            "batch: 10 writes, no batch -> 1 effect",
            "batch: 10 writes, batched -> 1 effect",
            "graph: build 20 src + 20 derive + effect, dispose",
            "mixed: 30 src, 60 derive, 15 effects, random write",
        }
    },
    scenarios = {
        {
            name = "source: create",
            setup = function(L)
                return function()
                    L.source(0)
                end
            end,
        },
        {
            name = "source: read (untracked)",
            setup = function(L)
                const s = L.source(1)
                return function()
                    return s()
                end
            end,
        },
        {
            name = "source: write, no subscribers",
            setup = function(L)
                const s = L.source(0)
                return function(i)
                    s(i)
                end
            end,
        },
        {
            name = "source: write, same value (no-op)",
            setup = function(L)
                const s: (number?) -> number = L.source(1)
                const dispose = L.scope(function()
                    L.effect(function()
                        s()
                    end)
                end)
                return function()
                    s(1)
                end,
                dispose
            end,
        },
        {
            name = "write -> 1 effect",
            setup = fanOut(1),
        },
        {
            name = "write -> 10 effects",
            setup = fanOut(10),
        },
        {
            name = "write -> 100 effects",
            setup = fanOut(100),
        },
        {
            name = "effect: create + dispose",
            setup = function(L)
                const s = L.source(0)
                local sink = 0
                return function()
                    local d = L.scope(function()
                        L.effect(function()
                            sink = s()
                        end)
                    end)
                    d()
                end
            end,
        },
        {
            name = "effect: rerun with cleanup",
            setup = function(L)
                const s = L.source(0)
                local count = 0
                local dispose = L.scope(function()
                    L.effectCleanup(function()
                        s()
                    end, function()
                        count += 1
                    end)
                end)
                return function(i)
                    s(i)
                end,
                dispose
            end,
        },
        {
            name = "effect: dynamic deps (branch toggle)",
            setup = function(L)
                const cond: (number?) -> number, a, b = L.source(0), L.source(0), L.source(0)
                local sink = 0
                const dispose = L.scope(function()
                    L.effect(function()
                        if cond() == 0 then
                            sink = a()
                        else
                            sink = b()
                        end
                    end)
                end)
                return function(i: number)
                    cond(i % 2)
                end,
                dispose
            end,
        },
        {
            name = "derive: write + read (depth 1)",
            setup = chain(1),
        },
        {
            name = "derive: chain depth 10, write + read tail",
            setup = chain(10),
        },
        {
            name = "derive: chain depth 40, write + read tail",
            setup = chain(40),
        },
        {
            name = "derive: chain depth 10 -> effect",
            setup = chainWithEffect(10),
        },
        {
            name = "derive: unobserved, write only (lazy vs eager)",
            setup = function(L)
                const s: (number?) -> number = L.source(0)
                const dispose = L.scope(function()
                    local tail: (number?) -> number = s
                    for _ = 1, 10 do
                        const prev = tail
                        tail = L.derive(function()
                            return prev() + 1
                        end)
                    end
                    tail()
                end)
                return function(i)
                    s(i)
                end,
                dispose
            end,
        },
        {
            name = "derive: diamond -> effect",
            setup = function(L)
                const a = L.source(0)
                local sink = 0
                const dispose = L.scope(function()
                    const b = L.derive(function()
                        return (a() :: number) * 2
                    end)
                    const c = L.derive(function()
                        return (a() :: number) + 1
                    end)
                    const d = L.derive(function()
                        return (b() :: number) + (c() :: number)
                    end)
                    L.effect(function()
                        sink = d()
                    end)
                end)
                return function(i)
                    a(i)
                end,
                dispose
            end,
        },
        {
            name = "derive: 1 source -> 50 derives -> 1 effect",
            setup = function(L)
                const s, ds = L.source(0), {}
                local sink = 0
                const dispose = L.scope(function()
                    for k = 1, 50 do
                        ds[k] = L.derive(function()
                            return (s() :: number) + k
                        end)
                    end
                    L.effect(function()
                        local sum = 0
                        for k = 1, 50 do
                            sum += (ds[k] :: () -> number)()
                        end
                        sink = sum
                    end)
                end)
                return function(i)
                    s(i)
                end,
                dispose
            end,
        },
        {
            name = "derive: cutoff (value unchanged -> effect not rerun)",
            setup = function(L)
                const s: (number?) -> number = L.source(0)
                local sink = 0
                const dispose = L.scope(function()
                    const parity = L.derive(function()
                        return s() % 2
                    end)
                    L.effect(function()
                        sink = parity()
                    end)
                end)
                return function(i: number)
                    s(i * 2)
                end,
                dispose
            end,
        },
        {
            name = "batch: 10 writes, no batch -> 1 effect",
            setup = batchScenario(false),
        },
        {
            name = "batch: 10 writes, batched -> 1 effect",
            setup = batchScenario(true),
        },
        {
            name = "graph: build 20 src + 20 derive + effect, dispose",
            setup = function(L)
                local sink = 0
                return function()
                    local d = L.scope(function()
                        local last: ((number?) -> number)? = nil
                        for k = 1, 20 do
                            const src = L.source(k)
                            const prev = last
                            last = L.derive(function()
                                if prev ~= nil then
                                    return (src() :: number) + (prev() :: number)
                                end
                                return src()
                            end)
                        end
                        L.effect(function()
                            sink = (last :: () -> number)()
                        end)
                    end)
                    d()
                end
            end,
        },
        {
            name = "mixed: 30 src, 60 derive, 15 effects, random write",
            setup = function(L)
                const rng = lcg(777)
                const N_SRC, N_DER, N_EFF = 30, 60, 15
                const nodes, srcs = {}, {}
                local sink = 0
                const dispose = L.scope(function()
                    for i = 1, N_SRC do
                        srcs[i] = L.source(i)
                        nodes[i] = srcs[i]
                    end
                    for k = 1, N_DER do
                        const idx = N_SRC + k
                        const d1, d2, d3 = nodes[rng(idx - 1)], nodes[rng(idx - 1)], nodes[rng(idx - 1)]
                        nodes[idx] = L.derive(function()
                            return ((d1() :: number) + (d2() :: number) + (d3() :: number)) % 1000
                        end)
                    end
                    for _ = 1, N_EFF do
                        const n = nodes[N_SRC + rng(N_DER)]
                        L.effect(function()
                            sink = n()
                        end)
                    end
                end)
                return function()
                    srcs[rng(N_SRC)](rng(1000))
                end,
                dispose
            end,
        },
    },
}