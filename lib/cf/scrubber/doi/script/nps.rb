require 'cf/scrubber/doi/nps'
require 'cf/scrubber/script'

module Cf::Scrubber::DOI::Script
  # The namespace for framework classes to implement various National Park Service scripts.

  module NPS
  end
end

require 'cf/scrubber/doi/script/nps/rec_areas'
require 'cf/scrubber/doi/script/nps/campgrounds'
