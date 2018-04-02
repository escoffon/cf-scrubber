require 'optparse'
require 'logger'

module Cf
  module Scrubber
    module Script
      # Base class for option parsers.
      # This class creates an options parser and registers the following standard options:
      # - <tt>-o FILE</tt> (<tt>--output-file=FILE</tt>) The file to use for the output.
      #   If not present, use STDOUT.
      # - <tt>-l FILE</tt> (<tt>--log-file=FILE</tt>) The file to use for the logger.
      #   If not present, use STDERR.
      # - <tt>-v LEVEL</tt> (<tt>--verbosity=LEVEL</tt>) Sets the logger level; this is one of the level
      #   constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
      # - <tt>-?</tt> Show help; we use <tt>-?</tt> instead of <tt>-h</tt> because the Rails console runner
      #   catches <tt>-h</tt>.
      #
      # Subclasses can register additional options in their initializers (and to register a banner):
      #   class MyParser < Cf::Scrubber::Script::Parser
      #     def initialize()
      #       self.parser.banner = "my banner\n"
      #       self.parser.on_head("-i", "--with-index", "Help string here") do |n|
      #         self.options.mrge!({ show_index: true })
      #       end
      #     end
      #   end

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
        # Creates an options parser and installs standard options, as described in the class documentation.

        def initialize()
          @parser = OptionParser.new do |opts|
            opts.on("-oFILE", "--output-file=FILE", "The file to use for the output. If not present, use STDOUT") do |l|
              self.options[:out_file] = l
            end

            opts.on("-lFILE", "--log-file=FILE", "The file to use for the logger. If not present, use STDERR") do |l|
              self.options[:log_file] = l
            end

            opts.on("-vLEVEL", "--verbosity=LEVEL", "Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.") do |l|
              self.options[:logger_level] = "Logger::#{l}"
            end

            opts.on("-?", "Show help") do
              puts opts
              exit
            end
          end

          @options = { out_file: nil, log_file: nil, logger_level: Logger::WARN }
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
        # @return [Cf::Scrubber::Script::Parser] the options parser to use.

        attr_reader :parser

        # @!attribute [r]
        # @return [Logger] the logger object.

        attr_reader :logger

        # @!attribute [r]
        # @return [IO] the output stream.

        attr_reader :output

        # Initializer.
        #
        # @param parser [Cf::Scrubber::Script::Parser] The parser to use.

        def initialize(parser)
          @parser = parser
          @logger = nil
          @output = nil
        end

        # Execute the script.
        # This method performs the following operations:
        # 1. Calls {#setup_log} to set up the logger object: log file and log level.
        # 2. Calls {#setup_output} to set up the output stream.
        # 3. Calls {#process_init}.
        # 4. Calls {#process}, passing the block in _blk_.
        # 5. Calls {#process_end}
        #
        # @param blk [Block] The block to pass to the processor.

        def exec(&blk)
          begin
            setup_log
            setup_output
            process_init
            process(&blk)
            process_end
          rescue => exc
            self.logger.fatal("#-- Exception: #{exc.message}")
            self.output.printf("#-- Exception: #{exc.message}\n")
            exc.backtrace.each do |f|
              bt = "#-- Backtrace: #{f}"
              self.logger.fatal(bt)
              self.output.printf("%s\n", bt)
            end
          end
        end

        protected

        # Set up the logger.
        # Sets up the log file and log level based on the {#parser}'s <tt>-l</tt> and <tt>-v</tt> flags.
        # If the <tt>-l</tt> flag is +nil+, the logger writes to +STDERR+.
        # If it is the string +STDOUT+ or +STDERR+, the logger writes to the corresponding output stream.
        # Any other string values are assumed to be the path to a log file, which is opened in append mode.
        # Any other value logs to +STDERR+.
        #
        # The method also places the logger object in the *:logger* option of the parser.

        def setup_log()
          logfile = self.parser.options[:log_file]
          if logfile.is_a?(String)
            case logfile
            when 'STDOUT'
              @logger = Logger.new(STDOUT)
            when 'STDERR'
              @logger = Logger.new(STDERR)
            else
              begin
                @logger = Logger.new(File.open(logfile, 'a'))
              rescue => exc
                @logger = Logger.new(STDERR)
              end
            end
          else
            @logger = Logger.new(STDERR)
          end
          self.parser.options[:logger] = @logger

          lvl = self.parser.options[:logger_level]
          if lvl.is_a?(String)
            self.logger.level = lvl.split('::').inject(Object) { |o,c| o.const_get c }
          elsif lvl.is_a?(Integer)
            self.logger.level = lvl
          else
            self.logger.level = Logger::WARN
          end
        end

        # Set up the output stream.
        # Sets up the output file and log level based on the {#parser}'s <tt>-o</tt> flag.
        # If the <tt>-o</tt> flag is +nil+, the script writes to +STDOUT+.
        # If it is the string +STDOUT+ or +STDERR+, the script writes to the corresponding output stream.
        # Any other string values are assumed to be the path to an output file, which is opened in create mode.
        # Any other value logs to +STDOUT+.
        #
        # The method also places the output stream in the *:output* option of the parser.

        def setup_output()
          outfile = self.parser.options[:out_file]
          if outfile.is_a?(String)
            case outfile
            when 'STDOUT'
              @output = STDOUT
            when 'STDERR'
              @output = STDERR
            else
              @output = File.open(outfile, 'w')
            end
          else
            @output = STDOUT
          end
          self.parser.options[:output] = @output
        end

        # Initialize processing.
        # The base implementation is a no-op.

        def process_init
        end

        # Processor.
        # This is the framework method; it is declared here to define a signature, but it *must* be
        # implemented by subclasses: the base implementation raises an exception.
        #
        # Subclass implementations are expected to iterate as needed, yielding to the block _blk_.
        # The block parameters are subclass-specific.

        def process(&blk)
          raise "please implement #{self.class.name}#process"
        end

        # End processing.
        # The base implementation is a no-op.

        def process_end
        end
      end
    end
  end
end
