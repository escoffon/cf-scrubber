require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/states_helper'
require 'cf/scrubber/usda/script/forests'

module Cf::Scrubber::USDA::Script
  # Driver for a utility to generate lists of national forests and grasslands for each state.
  # This script iterates through the list of forests and grasslands for each requested state, queries
  # the USFS web site, and prints out the list of forests and grasslands associated with each state.

  class PrintForestsPerState < Forests
    include Cf::Scrubber::StatesHelper

    # Command line parser.
    # This class adds the following options:
    # - <tt>-S FORMAT</tt> (<tt>--state-format=FORMAT</tt>) is the output format to use
    #   for the state name. The possible formats are: +full+ is the full name; +short+ is the two-letter
    #   state code. Defaults to +full+.
    # - <tt>-D FORMAT</tt> (<tt>--data-format=FORMAT</tt>) is the output format to use
    #   for the forest descriptor. The possible formats are: +plain+, +ruby+, and +json+.
    #   Defaults to +plain+.
    # - <tt>-i</tt> (<tt>--with-index</tt>) If present, emit the state indeces as well as names.

    class Parser < Forests::Parser
      # @!visibility private
      STATE_FORMATS = [ :full, :short ]

      # @!visibility private
      DATA_FORMATS = [ :plain, :ruby, :json ]

      # Initializer.
      # Registers the command line options.

      def initialize()
        rv = super()
        p = self.parser

        p.on_head("-i", "--with-index", "If present, emit the state indeces as well as names") do |n|
          self.options[:show_index] = true
        end

        p.on_head("-SFORMAT", "--state-format=FORMAT", "The output format to use for the state name: full or short (two-letter code).") do |f|
          f = f.to_sym
          self.options[:state_format] = f if STATE_FORMATS.include?(f)
        end
      
        p.on_head("-DFORMAT", "--data-format=FORMAT", "The output format to use for the data: plain, ruby, or json.") do |f|
          f = f.to_sym
          self.options[:data_format] = f if DATA_FORMATS.include?(f)
        end

        self.options.merge!({ state_format: :short, data_format: :plain, show_index: false })

        rv
      end
    end

    # Initializer.
    #
    # @param parser [Cf::Scrubber::USDA::Script::PrintForestsPerState] The parser to use.

    def initialize(parser)
      super(parser)
    end

    # Driver method.
    # This method triggers the processing loop with a custom block.

    def list_forests()
      self.exec do |nfs, s, f, desc|
        if @cur_state != s
          @total_states += 1

          sn = (self.parser.options[:state_format] == :short) ? get_state_code(s) : s

          case self.parser.options[:data_format]
          when :plain
            self.output.printf("%s\n", sn)
          when :ruby
            self.output.print("\n  ]") if @total_states > 1
            self.output.printf("%s\n  %s: [", ((@total_states > 1) ? ',' : ''), sn)
          when :json
            self.output.print("\n  ]") if @total_states > 1
            self.output.printf("%s\n  \"%s\": [", ((@total_states > 1) ? ',' : ''), sn)
          end

          @cur_state = s
          @total_forests = 0
        end

        @total_forests += 1

        case self.parser.options[:data_format]
        when :plain
          if self.parser.options[:show_index] && desc[:id]
            self.output.printf("  %-42s: %d\n", f, desc[:id])
          else
            self.output.print("  #{f}\n")
          end
        when :ruby
          if self.parser.options[:show_index] && desc[:id]
            self.output.printf("%s\n    [ '%s', %d ]", ((@total_forests > 1) ? ',' : ''), f.gsub("'") { "\\'" }, desc[:id])
          else
            self.output.printf("%s\n    '%s'", ((@total_forests > 1) ? ',' : ''), f.gsub("'") { "\\'" })
          end
        when :json
          if self.parser.options[:show_index] && desc[:id]
            self.output.printf("%s\n    [ \"%s\", %d ]", ((@total_forests > 1) ? ',' : ''), f.gsub('"') { "\\\"" }, desc[:id])
          else
            self.output.printf("%s\n    \"%s\"", ((@total_forests > 1) ? ',' : ''), f.gsub('"') { "\\\"" })
          end
        end
      end
    end

    protected

    # Process intialization.
    # Calls the superclass implementation, sets up the custom execution context, and writes the file header.

    def process_init()
      super()

      @cur_state = ''
      @total_states = 0

      case self.parser.options[:data_format]
      when :ruby
        self.output.print("USFS_STATE_FORESTS = {")
      when :json
        self.output.print("\"USFS_STATE_FORESTS\": {")
      end
    end

    # Process termination.
    # Writes the file footer and calls the superclass implementation.

    def process_end()
      case self.parser.options[:data_format]
      when :ruby
        self.output.print("\n  ]\n}\n")
      when :json
        self.output.print("\n  ]\n}\n")
      end

      super()
    end
  end
end
