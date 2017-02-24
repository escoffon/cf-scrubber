require 'optparse'
require 'logger'
require 'cf/scrubber'

module Cf
  module Scrubber
    module Usda
      module Script
        # Framework class for iterating through campgrounds for various states and forests.

        class Campgrounds < Cf::Scrubber::Script::Base
          # A class to parse command line arguments.
          #
          # The base class defines the following options:
          # - *-sSTATES* (*--states=STATES*) to set the list of states for which to list campgrounds.
          # - *-sFORESTS* (*--forests=FORESTS*) to set the list of forests for which to list campgrounds.
          # - *-d* (*--with-details*) to have the script load campground details.
          # - *-vLEVEL* (*--level=LEVEL*) to set the logger's output level.
          # - *-h* (*--help*) to emit a help statement.
          #
          # Subclasses may extend it to add their own options. For example:
          #   class MyParser < Cf::Scrubber::Usda::Script::States::Parser
          #     def initialize()
          #       super('my banner')
          #       self.parser.on_head("-i", "--with-index", "Hels tring here") do |n|
          #         self.options[:show_index] = true
          #       end
          #     end
          #   end

          class Parser < Cf::Scrubber::Script::Parser
            # Initializer.

            def initialize()
              opt_parser = OptionParser.new do |opts|
                opts.on("-vLEVEL", "--verbosity=LEVEL", "Set the logger level; this is one of the level constants defined by the Logger clsss (WARN, INFO, etc...). Defaults to WARN.") do |l|
                  self.options[:level] = "Logger::#{l}"
                end

                opts.on("-sSTATES", "--states=STATES", "Comma-separated list of states for which to list forests. Shows all states if not given. You may use two-character state codes.") do |sl|
                  self.options[:states] = sl.split(',').map do |s|
                    t = s.strip
                    (t.length == 2) ? t.upcase : t
                  end
                end

                opts.on("-rFORESTS", "--forests=FORESTS", "Comma-separated list of forests for which to list campgrounds. Shows all forests (per state) if not given.") do |sl|
                  self.options[:forests] = sl.split(',').map do |s|
                    s.strip
                  end
                end

                opts.on("-d", "--with-details", "If present, emit the additional info and location info.") do
                  self.options[:show_details] = true
                end

                opts.on("-h", "--help", "Show help") do
                  puts opts
                  exit
                end
              end

              super(opt_parser, { level: Logger::WARN, states: nil, forests: nil, show_details: false } )
            end
          end

          # Initializer.
          #
          # @param parser [Cf::Scrubber::Usda::Script::States::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of states and forests from the USFS web site,
          # iterates over each campground, yielding to the block provided.
          #
          # @yield [nfs, s, f, c] passes the following arguments to the block:
          #  - *nfs* is the active instance of {Cf::Scrubber::Usda::NationalForestService}.
          #  - *s* is the state name.
          #  - *f* is the forest name.
          #  - *c* is the campground data.

          def process(&blk)
            nfs = Cf::Scrubber::Usda::NationalForestService.new(nil,
                                                                :logger_level => self.parser.options[:level])

            self.parser.options[:states] = nfs.states if self.parser.options[:states].nil?
            self.parser.options[:states].each do |s|
              fl = (self.parser.options[:forests].nil?) ? nfs.forests_for_state(s).keys : self.parser.options[:forests]
              fl.sort.each do |f|
                nfs.get_forest_campgrounds(s, f, self.parser.options[:show_details]).each do |c|
                  blk.call(nfs, s, f, c)
                end
              end
            end
          end
        end
      end
    end
  end
end
