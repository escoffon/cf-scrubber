require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/ga/script'

module Cf
  module Scrubber
    module Ga
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
                opts.on("-A", "--all", "If present, all parks are listed; otherwise only those with campgrounds are listed.") do |l|
                  self.options[:all] = true
                end

                opts.on("-tTYPES", "--types=TYPES", "Comma-separated list of types of campground to list. Lists all types if not given.") do |tl|
                  self.options[:types] = tl.split(',').map do |s|
                    s.strip.to_sym
                  end
                end

                opts.on("-vLEVEL", "--verbosity=LEVEL", "Set the logger level; this is one of the level constants defined by the Logger clsss (WARN, INFO, etc...). Defaults to WARN.") do |l|
                  self.options[:level] = "Logger::#{l}"
                end

                opts.on("-h", "--help", "Show help") do
                  puts opts
                  exit
                end
              end

              super(opt_parser, { all: false, types: nil, level: Logger::WARN } )
            end
          end

          # Initializer.
          #
          # @param parser [Cf::Scrubber::Usda::Script::States::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of activities from the GA state park system's
          # web site, and yields to the block.
          #
          # @yield [sp, act] passes the following arguments to the block:
          #  - *sp* is the active instance of {Cf::Scrubber::Ga::StateParks}.
          #  - *pd* is a hash containing data for a park.

          def process(&blk)
            sp = Cf::Scrubber::Ga::StateParks.new(nil, :logger_level => self.parser.options[:level])
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
