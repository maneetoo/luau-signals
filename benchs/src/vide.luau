--!strict

const shared = require './shared'
const vide = require './pkgs/vide'

return table.freeze {
    name = "vide",
	source = vide.source,
	derive = vide.derive,
	effect = vide.effect,
	effectCleanup = function(fn, cleanupFn)
		return vide.effect(function()
			fn()
			vide.cleanup(cleanupFn)
		end)
	end,
	batch = vide.batch,
	scope = vide.root,
} :: shared.Lib
