require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/nc/script'
require 'cf/scrubber/nc/state_parks'
require 'cf/scrubber/script/campground_list'

module Cf
  module Scrubber
    module NC
      module Script
        # Framework class for extracting the park list.

        class ParkList < Cf::Scrubber::Script::CampgroundList
          # Initializer.
          #
          # @param parser [Cf::Scrubber::Script::CampgroundList::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of activities from the NC state park system's
          # web site, and yields to the block.
          #
          # @yield [sp, act] passes the following arguments to the block:
          #  - *sp* is the active instance of {Cf::Scrubber::NC::StateParks}.
          #  - *pd* is a hash containing data for a park.

          def process(&blk)
            sp = Cf::Scrubber::NC::StateParks.new(nil, {
                                                    :output => self.parser.options[:output],
                                                    :logger => self.parser.options[:logger],
                                                    :logger_level => self.parser.options[:logger_level]
                                                  })

            # EMIL add options here to select types, activities, facilities?

            pl = sp.get_park_campgrounds
            if pl.is_a?(Array)
              pl.each do |pd|
                blk.call(sp, pd)
              end
            end
          end
        end
      end
    end
  end
end
