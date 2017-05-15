require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/nv/script'

module Cf
  module Scrubber
    module Nv
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
          # This is the framework method; it fetches the list of activities from the NV state park system's
          # web site, and yields to the block.
          #
          # @yield [sp, act] passes the following arguments to the block:
          #  - *sp* is the active instance of {Cf::Scrubber::Nv::StateParks}.
          #  - *pd* is a hash containing data for a park.

          def process(&blk)
            sp = Cf::Scrubber::Nv::StateParks.new(nil, {
                                                    :output => self.parser.options[:output],
                                                    :logger => self.parser.options[:logger],
                                                    :logger_level => self.parser.options[:logger_level]
                                                  })
            pl = if self.parser.options[:all]
                   sp.any_park_list
                 else
                   sp.select_campground_list(self.parser.options[:types])
                 end
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
