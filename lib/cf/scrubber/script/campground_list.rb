require 'optparse'
require 'logger'

module Cf
  module Scrubber
    module Script
      # Script to print a list of campgrounds.
      # This subclass implements the {#exec} to emit a list of campgrounds.

      class CampgroundList < Base
        # The base parser for campground list scripts.
        # Adds the following options:
        # - <tt>-A</tt> (<tt>--all</tt>) to list all parks.
        # - <tt>-t TYPES</tt> (<tt>--types=TYPES</tt>) to select parks that contain the given accommodation
        #   types.
        # - <tt>-D DATAFORMAT</tt> (<tt>--data-format=DATAFORMAT</tt>) is the output format to use: +raw+,
        #   +json+, or +name+. The +json+ format can include an integer containing the indentation level
        #   for the generated output; for example, +json:2+ generates a formatted output with a two-space
        #   indentation level. Defaults to +json+.

        class Parser < Cf::Scrubber::Script::Parser
          # The known (and supported) data formats.

          DATA_FORMATS = [ :raw, :json, :name ]

          def initialize()
            rv = super()
            opts = self.parser

            opts.on_head("-DDATAFORMAT", "--data-format=DATAFORMAT", "The output format to use: raw, json, or name. Use json:N to output formatted JSON with N spaces indentation.") do |f|
              if f =~ /^json\:([0-9]+)/i
                m = Regexp.last_match
                self.options[:data_format] = :json
                self.options[:json_opts] = { indent: sprintf("%#{m[1].to_i}s", ' ') }
              else
                f = f.to_sym
                if DATA_FORMATS.include?(f)
                  self.options[:data_format] = f
                  self.options[:json_opts] = false
                end
              end
            end

            opts.on_head("-tTYPES", "--types=TYPES", "Comma-separated list of types of campground to list. Lists all types if not given.") do |tl|
              self.options[:types] = tl.split(',').map do |s|
                s.strip.to_sym
              end
            end

            opts.on_head("-A", "--all", "If present, all parks are listed; otherwise only those with campgrounds are listed.") do |l|
              self.options[:all] = true
            end

            self.options.merge!({ data_format: :json, json_opts: false, all: false, types: nil })

            rv
          end
        end

        # Implements the processing loop for campgrounds.

        def process_campgrounds()
          exec { |sp, pd| emit_campground(pd) }
        end

        protected

        # Initialize processing: emit a dump header.
        # This method emits the following:
        # 1. A line containing the class name of the script generator (+self+) and current timestamp.
        # 2. A line containing the data format emitted. This is obtained from the +data_format+ options.
        # 3. The value of all the options, each on a single line.
        
        def process_init()
          opts = @parser.options

          self.output.print("#-- Scrubber #{self.class.name} - #{Time.new.to_s}\n")
          self.output.print("#-- Format #{opts[:data_format]}\n") if opts.has_key?(:data_format)
          opts.each { |ok, ov| self.output.print("#-- Option #{ok} : #{ov}\n") }
        end

        # End processing: emit a dump footer.
        # This method emits an EOD line unless the data format is +name+.
        
        def process_end()
          opts = @parser.options
          self.output.print("#-- EOD\n") if opts.has_key?(:data_format) && (opts[:data_format] != :name)
        end

        # Emit campground data.
        #
        # @param [Hash] pd The campground data.
        # @param [Symbol] format The format to emit; if +nil+, use the value from the +data_format+ option.

        def emit_campground(pd, format = nil)
          format = self.parser.options[:data_format] if format.nil?

          case format
          when :raw
            self.output.print("#-- Campground #{pd[:signature]}\n")
            self.output.print("#{pd}\n");
          when :json
            self.output.print("#-- Campground #{pd[:signature]}\n")
            if self.parser.options[:json_opts] == false
              self.output.print("#{JSON.generate(pd)}\n")
            else
              self.output.print("#{JSON.pretty_generate(pd, self.parser.options[:json_opts])}\n")
            end
          when :name
            self.output.print("#{pd[:name]} -- #{pd[:signature]}\n")
          else
            self.output.print("#-- Campground #{pd[:signature]}\n")
            self.output.print("#{pd}\n")
          end
        end
      end
    end
  end
end
