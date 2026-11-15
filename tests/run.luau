--!strict
const h = require './_helpers'

require './signal.spec'
require './effect.spec'
require './effectNesting.spec'
require './computed.spec'
require './batch.spec'
require './effectScope.spec'
require './trigger.spec'
require './errors.spec'
require './types.spec'

return h.report()
