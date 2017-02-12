require 'optparse'
require 'logger'
require 'cf/scrubber'

module Cf
  module Scrubber
    module Usda
      module Script
        # Framework class for iterating through the states with national forests or grasslands.

        class States < Cf::Scrubber::Usda::Script::Base
          # A class to parse command line arguments.
          #
          # The base class defines the following options:
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

          class Parser < Cf::Scrubber::Usda::Script::Parser
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
          # @param parser [Cf::Scrubber::Usda::Script::States::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of states from the USFS web site, iterates
          # over each, yielding to the block provided.
          #
          # @yield [nfs, s, idx] passes the following arguments to the block:
          #  - *nfs* is the active instance of {Cf::Scrubber::Usda::NationalForestService}.
          #  - *s* is the state name.
          #  - *idx* is the corresponding state identifier.

          def process(&blk)
            nfs = Cf::Scrubber::Usda::NationalForestService.new(nil,
                                                                :logger_level => self.parser.options[:level])
            s = nfs.states
            s.keys.sort.each do |sk|
              blk.call(nfs, sk, s[sk])
            end
          end
        end
      end
    end
  end
end
