require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/ca/script'
require 'cf/scrubber/script/campground_list'

module Cf
  module Scrubber
    module CA
      module Script
        # Framework class for extracting the park list.

        class ParkList < Cf::Scrubber::Script::CampgroundList
          # A class to parse command line arguments.
          #
          # This class defines the following options:
          # - <tt>-n</tt> (<tt>--no-details</tt>) to have the script not load campground details.

          class Parser < Cf::Scrubber::Script::CampgroundList::Parser
            # Initializer.

            def initialize()
              rv = super()
              opts = self.parser

              opts.on_head("-n", "--no-details", "If present, do not emit the additional info and location info.") do
                self.options[:show_details] = false
              end

              self.options.merge!({ show_details: true })

              rv
            end
          end

          # Processor.
          # This is the framework method; it fetches the list of activities from the CA state park system's
          # web site, and yields to the block.
          #
          # @yield [sp, act] passes the following arguments to the block:
          #  - *sp* is the active instance of {Cf::Scrubber::CA::StateParks}.
          #  - *pd* is a hash containing data for a park.

          def process(&blk)
            sp = Cf::Scrubber::CA::StateParks.new(nil, {
                                                    :output => self.parser.options[:output],
                                                    :logger => self.parser.options[:logger],
                                                    :logger_level => self.parser.options[:logger_level]
                                                  })
            pl = if self.parser.options[:all]
                   sp.get_park_list_raw.map { |e| sp.convert_park_data(e, self.parser.options[:show_details]) }
                 else
                   sp.select_campground_list(self.parser.options[:types], self.parser.options[:show_details])
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
