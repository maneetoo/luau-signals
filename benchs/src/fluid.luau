--!strict

const shared = require './shared'
const fluid = require './pkgs/fluid'

return table.freeze {
    name = "fluid",
	source = fluid.source,
	derive = fluid.derive,
	effect = fluid.effect,
	effectCleanup = function(fn, cleanupFn)
		return fluid.effect(function()
			fn()
			fluid.cleanup(cleanupFn)
		end)
	end,
	-- fluid does not have batches: records are propagated immediately
	batch = function(fn)
        fn()
    end,
	scope = fluid.root,
} :: shared.Lib
