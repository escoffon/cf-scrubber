require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/or/script'
require 'cf/scrubber/script/campground_list'

module Cf
  module Scrubber
    module OR
      module Script
        # Framework class for extracting the park list.

        class ParkList < Cf::Scrubber::Script::CampgroundList
          # A class to parse command line arguments.
          #
          # This class defines the following options:
          # - <tt>-L</tt> (<tt>--list-activities</tt>) to have the script list the activity names.
          # - <tt>-M</tt> (<tt>--map-activities</tt>) to have the script output the list of activity
          #   names and the campgrounds that offer them.

          class Parser < Cf::Scrubber::Script::CampgroundList::Parser
            # Initializer.

            def initialize()
              rv = super()
              opts = self.parser

              opts.on_head("-L", "--list-activities", "If present, output a list of activity names.") do
                self.options[:list_activities] = true
              end
              opts.on_head("-M", "--map-activities", "If present, output a map of activity names to campground URLs.") do
                self.options[:map_activities] = true
              end

              self.options.merge!({ list_activities: false, map_activities: false })

              rv
            end
          end

          # Initializer.
          #
          # @param parser [Cf::Scrubber::Script::CampgroundList::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of activities from the OR state park system's
          # web site, and yields to the block.
          #
          # @yield [sp, act] passes the following arguments to the block:
          #  - *sp* is the active instance of {Cf::Scrubber::OR::StateParks}.
          #  - *pd* is a hash containing data for a park.

          def process(&blk)
            @sp = Cf::Scrubber::OR::StateParks.new(nil, {
                                                     :output => self.parser.options[:output],
                                                     :logger => self.parser.options[:logger],
                                                     :logger_level => self.parser.options[:logger_level]
                                                   })
            pl = if self.parser.options[:all]
                   @sp.build_park_list(false)
                 else
                   @sp.build_overnight_park_list(self.parser.options[:types])
                 end
            if pl.is_a?(Array)
              pl.each do |pd|
                blk.call(@sp, pd)
              end
            end
          end

          # End processing: output activity list and map if requested, and then call the superclass.
        
          def process_end()
             if self.parser.options[:list_activities]
               @sp.activity_map.keys.sort.each { |ak| self.output.printf("#-- Activity %s\n", ak) }
             end

            if self.parser.options[:map_activities]
              @sp.activity_map.keys.sort.each do |ak|
                self.output.printf("#-- Activity %s\n", ak)
                self.activities_map[ak].each do |url|
                  self.output.printf("#-- Park %s\n", url)
                end
              end
            end

            super()
          end
        end
      end
    end
  end
end
