require 'optparse'
require 'logger'
require 'cf/scrubber'

module Cf
  module Scrubber
    module Usda
      module Script
        # Framework class for iterating through campgrounds for various states and forests.

        class Campgrounds < Cf::Scrubber::Script::CampgroundList
          # A class to parse command line arguments.
          #
          # The base class defines the following options:
          # - *-sSTATES* (*--states=STATES*) to set the list of states for which to list campgrounds.
          # - *-sFORESTS* (*--forests=FORESTS*) to set the list of forests for which to list campgrounds.
          # - *-n* (*--no-details*) to have the script not load campground details.
          # - *-SSTATEFORMAT* (*--state-format=STATEFORMAT*) is the output format to use for the state name.

          class Parser < Cf::Scrubber::Script::CampgroundList::Parser
            # The known (and supported) state formats.

            STATE_FORMATS = [ :full, :short ]

            # Initializer.

            def initialize()
              rv = super()
              opts = self.parser

              opts.on_head("-SSTATEFORMAT", "--state-format=STATEFORMAT", "The output format to use for the state name: full or short (two-letter code).") do |f|
                f = f.to_sym
                self.options[:state_format] = f if STATE_FORMATS.include?(f)
              end

              opts.on_head("-n", "--no-details", "If present, do not load or emit the additional info and location info.") do
                self.options[:show_details] = false
              end

              opts.on_head("-rFORESTS", "--forests=FORESTS", "Comma-separated list of forests for which to list campgrounds. Shows all forests (per state) if not given.") do |sl|
                self.options[:forests] = sl.split(',').map do |s|
                  s.strip
                end
              end

              opts.on_head("-sSTATES", "--states=STATES", "Comma-separated list of states for which to list forests. Shows all states if not given. You may use two-character state codes.") do |sl|
                self.options[:states] = sl.split(',').map do |s|
                  t = s.strip
                  (t.length == 2) ? t.upcase : t
                end
              end

              self.options.merge!( { states: nil, forests: nil, state_format: :full, show_details: true })

              rv
            end
          end

          # Initializer.
          #
          # @param parser [Cf::Scrubber::Usda::Script::Campgrounds::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Implements the processing loop for campgrounds.

          def process_campgrounds()
            exec do |nfs, c, s, f|
              if @cur_state != s
                if self.parser.options[:state_format] == :short
                  self.output.printf("#-- State %s\n", nfs.state_code(s))
                else
                  self.output.printf("#-- State %s\n", s)
                end

                @cur_state = s
                @cur_forest = ''
              end

              if @cur_forest != f
                self.output.printf("#-- Forest %s\n", f)
                @cur_forest = f
              end

              emit_campground(c)
            end
          end

          protected

          # Initialize processing.
          # Calls the superclass and then sets up tracking variables

          def process_init
            super()

            # if the format is :name, we don't need the details

            self.parser.options[:show_details] = false if self.parser.options[:format] == :name

            @cur_state = ''
            @cur_forest = ''
          end

          # Processor.
          # This is the framework method; it fetches the list of states and forests from the USFS web site,
          # iterates over each campground, yielding to the block provided.
          #
          # @yield [nfs, c, s, f] passes the following arguments to the block:
          #  - *nfs* is the active instance of {Cf::Scrubber::Usda::NationalForestService}.
          #  - *c* is the campground data.
          #  - *s* is the state name.
          #  - *f* is the forest name.

          def process(&blk)
            nfs = Cf::Scrubber::Usda::NationalForestService.new(nil, {
                                                                  :output => self.parser.options[:output],
                                                                  :logger => self.parser.options[:logger],
                                                                  :logger_level => self.parser.options[:logger_level]
                                                                })

            if self.parser.options[:states].nil?
              self.parser.options[:states] = nfs.states.map { |s| s[1] }
            end
            self.parser.options[:states].each do |s|
              fl = (self.parser.options[:forests].nil?) ? nfs.forests_for_state(s).keys : self.parser.options[:forests]
              fl.sort.each do |f|
                nfs.get_forest_campgrounds(s, f, self.parser.options[:types],
                                           self.parser.options[:show_details]).each do |c|
                  blk.call(nfs, c, s, f)
                end
              end
            end
          end
        end
      end
    end
  end
end
