require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/ga/script'

module Cf
  module Scrubber
    module Ga
      module Script
        # Framework class for listing activity identifiers.

        class Activities < Cf::Scrubber::Script::Base
          # A class to parse command line arguments.
          #
          # The base class defines the following options:
          # - *-vLEVEL* (*--level=LEVEL*) to set the logger's output level.
          # - *-h* (*--help*) to emit a help statement.
          #
          # Subclasses may extend it to add their own options. For example:
          #   class MyParser < Cf::Scrubber::Ga::Script::States::Parser
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

                opts.on("-h", "--help", "Show help") do
                  puts opts
                  exit
                end
              end

              super(opt_parser, { level: Logger::WARN } )
            end
          end

          # Initializer.
          #
          # @param parser [Cf::Scrubber::Script::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of activities from the GA state park system's
          # web site, and yields to the block.
          #
          # @yield [sp, act] passes the following arguments to the block:
          #  - *sp* is the active instance of {Cf::Scrubber::Ga::StateParks}.
          #  - *act* is a hash containing activity information: *:activity_id*, *:name*, and *:parks*.

          def process(&blk)
            sp = Cf::Scrubber::Ga::StateParks.new(nil, :logger_level => self.parser.options[:level])
            sp.get_activity_list.each do |ak, act|
              a = act.dup
              a[:activity_id] = ak
              blk.call(sp, a)
            end
          end
        end
      end
    end
  end
end
