require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/co/script'
require 'cf/scrubber/script/campground_list'

module Cf
  module Scrubber
    module CO
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
          # This is the framework method; it fetches the list of activities from the CO state park system's
          # web site, and yields to the block.
          #
          # @yield [sp, act] passes the following arguments to the block:
          #  - *sp* is the active instance of {Cf::Scrubber::CO::StateParks}.
          #  - *pd* is a hash containing data for a park.

          def process(&blk)
            sp = Cf::Scrubber::CO::StateParks.new(nil, {
                                                    :output => self.parser.options[:output],
                                                    :logger => self.parser.options[:logger],
                                                    :logger_level => self.parser.options[:logger_level]
                                                  })
            all_parks = sp.build_full_park_list(nil, true)
            if !self.parser.options[:all]
              if self.parser.options[:types].nil?
                pl = all_parks.select { |p| p[:types].count > 0 }
              else
                types = self.parser.options[:types]
                pl = all_parks.select { |p| (p[:types] & types).count > 0 }
              end
            else
              pl = all_parks
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
