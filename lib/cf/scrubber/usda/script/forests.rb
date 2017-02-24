require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/usda/script'

module Cf
  module Scrubber
    module Usda
      module Script
        # Framework class for iterating through forests or grasslands for various states.

        class Forests < Cf::Scrubber::Script::Base
          # A class to parse command line arguments.
          #
          # The base class defines the following options:
          # - *-sSTATES* (*--states=STATES*) to set the list of states for which to list forests.
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

                opts.on("-h", "--help", "Show help") do
                  puts opts
                  exit
                end
              end

              super(opt_parser, { level: Logger::WARN, states: nil } )
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
          # @yield [nfs, s, f, idx] passes the following arguments to the block:
          #  - *nfs* is the active instance of {Cf::Scrubber::Usda::NationalForestService}.
          #  - *s* is the state name.
          #  - *f* is the forest name.
          #  - *idx* is the corresponding forest identifier.

          def process(&blk)
            nfs = Cf::Scrubber::Usda::NationalForestService.new(nil,
                                                                :logger_level => self.parser.options[:level])

            self.parser.options[:states] = nfs.states if self.parser.options[:states].nil?
            self.parser.options[:states].each do |s|
              f = nfs.forests_for_state(s)
              f.keys.sort.each do |fk|
                blk.call(nfs, s, fk, f[fk])
              end
            end
          end
        end
      end
    end
  end
end
