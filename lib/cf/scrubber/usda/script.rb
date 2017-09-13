module Cf
  module Scrubber
    module USDA
      # The namespace for framework classes to implement various USFS scripts.

      module Script
      end
    end
  end
end

require 'cf/scrubber/script'

require 'cf/scrubber/usda/script/states'
require 'cf/scrubber/usda/script/forests'
require 'cf/scrubber/usda/script/campgrounds'
require 'cf/scrubber/usda/script/print_forests_per_state'
require 'cf/scrubber/usda/script/print_national_forests'
