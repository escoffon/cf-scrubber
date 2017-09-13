require 'json'

require 'cf/scrubber/script/base'

module Cf::Scrubber::Script
  # Framework class for processing a scrub file.
  # This class implements framework code to parse and process a scrub file; subclasses define specialized
  # processing functionality like loading campgrounds into the database or listing the contents of the scrub
  # file.
  #
  # This class assumes that the scrub file has been generated in JSON format.

  class Processor < Cf::Scrubber::Script::Base
    # A class to parse command line arguments.
    #
    # This class defines the following options:
    # - <tt>-i FILE</tt> (<tt>--input-file=FILE</tt>) is the path to the input (scrub) file to load.
    #   Defaults to +STDIN+.

    class Parser < Cf::Scrubber::Script::Parser
      # Initializer.

      def initialize()
        rv = super()
        opts = self.parser

        opts.on_head("-iFILE", "--input-file=FILE", "Path to the file to parse and load; HTTP URLs will work as well. Uses STDIN if not present.") do |f|
          self.options[:input_file] = f
        end

        self.options.merge!({ input_file: nil })

        rv
      end
    end

    # Initializer.
    #
    # @param parser [Cf::Scrubber::Script::Parser] The parser to use.

    def initialize(parser)
      super(parser)
    end

    # @!attribute [r]
    # The input stream to use.

    attr_reader :istream

    protected

    # Sets up scrub file processing.
    # 1. Calls the superclass implementation.
    # 2. Reads the file header, extracts the format specifier, and confirms that it is supported.
    #    Currently, only JSON format is supported.

    def process_init()
      super()

      opts = self.parser.options
      begin
        @istream = if opts[:input_file]
                     @needs_close = true
                     open(opts[:input_file], 'r')
                   else
                     @needs_close = false
                     STDIN
                   end
      rescue => exc
        self.logger.error("#{exc.message}\n")
        exit(1)
      end

      @fmt = read_format()
      if @fmt.nil?
        self.logger.error("missing format line\n")
        exit(1)
      elsif @fmt != :json
        self.logger.error("unsupported format: #{@fmt}\n")
        exit(1)
      end
    end

    # End of processing.
    # 1. Close the input file if necessary.
    # 2. Calls the superclass implementation.

    def process_end
      @istream.close if @needs_close

      super()
    end

    # Process a scrub file.
    # Loops over all campgrounds in the file, yielding to the block for each.
    #
    # @yield [processor, cd] passes the following arguments to the block:
    #  - *processor* is the active instance of {Cf::Scrubber::Script::Processor}.
    #  - *cd* is a hash containing data for a campground.

    def process(&blk)
      if seek_campground()
        active = true
        while active do
          cd = load_campground()
          if cd
            blk.call(self, cd)
          else
            active = false
          end
        end
      end
    end

    private

    def read_format()
      until @istream.eof? do
        line = @istream.gets
        return nil if line.nil?
        if line =~ /#-- Format ([a-z]+)/
          m = Regexp.last_match
          return m[1].to_sym
        end
      end

      nil
    end

    def seek_campground()
      until @istream.eof? do
        line = @istream.gets
        return false if line.nil? || (line =~ /#-- EOD/)
        return true if line =~ /#-- Campground/
      end
    end

    def load_campground()
      lines = [ ]
      until @istream.eof? do
        line = @istream.gets
        break if line.nil? || (line =~ /#--/)
        lines << line
      end

      seek_campground() if line !~ /#-- Campground/

      s = lines.join("\n")
      return (s.length > 1) ? symbolize_keys(JSON.parse(s)) : nil
    end

    def symbolize_keys(h)
      nh = { }
      h.each do |hk, hv|
        if hv.is_a?(Hash)
          nh[hk.to_sym] = symbolize_keys(hv)
        else
          nh[hk.to_sym] = hv
        end
      end

      nh
    end
  end
end
