require 'optparse'
require 'logger'

require 'cf/scrubber'
require 'cf/scrubber/doi/script/nps'

module Cf::Scrubber::DOI::Script::NPS
  # Framework class for iterating through rec areas for various states.

  class RecAreas < Cf::Scrubber::Script::Base
    # A class to parse command line arguments.
    #
    # The base class defines the following options:
    # - *-sSTATES* (*--states=STATES*) to set the list of states for which to list rec areas.

    class Parser < Cf::Scrubber::Script::Parser
      # Initializer.

      def initialize()
        rv = super()
        opts = self.parser

        opts.on_head("-sSTATES", "--states=STATES", "Comma-separated list of states for which to list rec areas. You may use two-character state codes.") do |sl|
          self.options[:states] = sl.split(',').map do |s|
            t = s.strip
            (t.length == 2) ? t.upcase : t
          end
        end

        self.options.merge!({ states: nil })

        rv
      end
    end

    # Initializer.
    #
    # @param parser [Cf::Scrubber::DOI::Script::States::Parser] The parser to use.

    def initialize(parser)
      @parser = parser
    end

    # Processor.
    # This is the framework method; it fetches rec areas for each state and iterates
    # over each, yielding to the block provided.
    #
    # @yield [nps, s, ra] The processor block
    #
    # @yieldparam [Cf::Scrubber::DOI::NationalParkService] nps The active scrubber instance.
    # @yieldparam [String] s The state name.
    # @yieldparam [Hash] ra A hash containing rec area information:
    #  - *:name* A string containing the rec area name.
    #  - *:id* A string containing the rec area's identifier.
    #  - *:data* A hash containing the rec area data.

    def process(&blk)
      states = self.parser.options[:states]
      unless states.is_a?(Array) && (states.count > 0)
        print("error: you must list at least one state\n")
        exit(1)
      end

      nps = Cf::Scrubber::DOI::NationalParkService.new(nil, {
                                                         :output => self.parser.options[:output],
                                                         :logger => self.parser.options[:logger],
                                                         :logger_level => self.parser.options[:logger_level]
                                                       })

      states.each do |s|
        nps.rec_areas_for_state(s).each do |rak, ra|
          blk.call(nps, s, { id: rak.to_s, name: ra['RecAreaName'], data: ra })
        end
      end
    end
  end
end
