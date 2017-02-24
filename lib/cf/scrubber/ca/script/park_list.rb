require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/ca/script'

module Cf
  module Scrubber
    module Ca
      module Script
        # Framework class for extracting the park list.

        class ParkList < Cf::Scrubber::Script::Base
          # A class to parse command line arguments.
          #
          # The base class defines the following options:
          # - *-C* (*--campgrounds*) lists only campgrounds.
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
                opts.on("-C", "--campgrounds", "If present, only campgrounds are listed.") do |l|
                  self.options[:campgrounds] = true
                end

                opts.on("-vLEVEL", "--verbosity=LEVEL", "Set the logger level; this is one of the level constants defined by the Logger clsss (WARN, INFO, etc...). Defaults to WARN.") do |l|
                  self.options[:level] = "Logger::#{l}"
                end

                opts.on("-h", "--help", "Show help") do
                  puts opts
                  exit
                end
              end

              super(opt_parser, { campgrounds: false, level: Logger::WARN } )
            end
          end

          # Initializer.
          #
          # @param parser [Cf::Scrubber::Usda::Script::States::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of activities from the CA state park system's
          # web site, and yields to the block.
          #
          # @yield [sp, act] passes the following arguments to the block:
          #  - *sp* is the active instance of {Cf::Scrubber::Ca::StateParks}.
          #  - *pd* is a hash containing data for a park.

          def process(&blk)
            sp = Cf::Scrubber::Ca::StateParks.new(nil, :logger_level => self.parser.options[:level])
            pl = (self.parser.options[:campgrounds]) ? sp.select_campground_list : sp.get_park_list_raw
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
