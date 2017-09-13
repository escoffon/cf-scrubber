module Cf
  module Scrubber
    module RIDB
      # The namespace for framework classes to implement various RIDB scripts.

      module Script
      end
    end
  end
end

require 'cf/scrubber/script'

require 'cf/scrubber/ridb/script/organizations'
require 'cf/scrubber/ridb/script/activities'
require 'cf/scrubber/ridb/script/rec_areas'
require 'cf/scrubber/ridb/script/list_national_forests'
require 'cf/scrubber/ridb/script/print_national_forests'
require 'cf/scrubber/ridb/script/query'
require 'cf/scrubber/ridb/script/forest_query'
