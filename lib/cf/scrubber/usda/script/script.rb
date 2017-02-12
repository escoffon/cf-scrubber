require 'optparse'

module Cf
  module Scrubber
    module Usda
      # The namespace for framework classes to implement various USFS scripts.

      module Script
        # Base class for option parsers.

        class Parser
          # @!attribute [r]
          # The option parser used by this object.
          #
          # @return [OptionParser] the instance of {OptionParser} used by the object.

          attr_reader :parser

          # @!attribute [r]
          # The hash of option values.
          #
          # @return [Hash] the hash containing option values.

          attr_reader :options

          # Initializer.
          #
          # @param parser [OptionParser] The option parser to use.
          # @param options [Hash] Initial value of the options.

          def initialize(parser, options = {})
            @parser = parser
            @options = options.dup
          end

          # Parse options and return them.
          #
          # @param options [Array] An array containing the options to parse; typically this is +ARGV+.
          #
          # @return [Hash] Returns a hash containing the parsed options; this value is also returned
          #  by the {#options} attribute.

          def parse(options)
            self.parser.parse!(options)
            self.options
          end
        end

        # Base class for scripts.

        class Base
          # @!attribute [r]
          # The parser to use.
          #
          # @return [Cf::Scrubber::Usda::Script::Parser] the options parser to use.

          attr_reader :parser

          # Initializer.
          #
          # @param parser [Cf::Scrubber::Usda::Script::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end
        end
      end
    end
  end
end
