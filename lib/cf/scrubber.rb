# The top-level Campfinder module; provides the root namespace for Campfinder code.

module Cf
  # The namespace module for scrubbers.

  module Scrubber
  end
end

require 'cf/scrubber/base'
require 'cf/scrubber/ca/state_parks'
require 'cf/scrubber/co/state_parks'
require 'cf/scrubber/doi/nps'
require 'cf/scrubber/ga/state_parks'
require 'cf/scrubber/nc/state_parks'
require 'cf/scrubber/nv/state_parks'
require 'cf/scrubber/or/state_parks'
require 'cf/scrubber/ridb/api'
require 'cf/scrubber/usda/usfs'
require 'cf/scrubber/ut/state_parks'

