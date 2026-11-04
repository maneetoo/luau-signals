--!strict

const shared = require './shared'
const signals = require './pkgs/luau-signals'

return table.freeze {
	name = "luau-signals",
	source = signals.signal,
	derive = signals.computed,
	effect = signals.effect,
	effectCleanup = function(fn, cleanupFn)
		return signals.effect(function()
			fn()
		    return cleanupFn
		end)
	end,
	batch = function(fn)
		signals.startBatch()
		fn()
		signals.endBatch()
	end,
	scope = signals.effectScope,
} :: shared.Lib
