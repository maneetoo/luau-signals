--!strict

const shared = require './shared'
const Flux = require './pkgs/flux'

return table.freeze {
    name = "flux",
    source = Flux.signal,
    derive = Flux.computed,
    effect = function(fn)
        local node = Flux.effect(fn)
        return function() node:Destroy() end
    end,
    effectCleanup = function(fn, cleanupFn)
        local node = Flux.effect(function()
            fn()
            Flux.cleanup(cleanupFn)
        end)
        return function() node:Destroy() end
    end,
    batch = function(fn)
        fn()
        Flux.flush()
    end,
    scope = function(fn)
        local scope = Flux.scope(fn)
        return function() scope:Destroy() end
    end,
} :: shared.Lib
