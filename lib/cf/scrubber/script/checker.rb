require 'cf/scrubber/script/processor'
require 'cf/scrubber/usda/usfs'

module Cf::Scrubber::Script
  # Scrub processor that checks the contets of a USFS scrub file.

  class Checker < Cf::Scrubber::Script::Processor
    # Check the contents of a scrub file.
    # Calls {#exec} with a specialized block that performs the following checks:
    # - The location is empty.
    # - The "at a glance" hash is empty.
    # Any of these conditions might indicate that the record does not contain campground data.

    def check_file()
      self.exec do |loader, cd|
        @total_campgrounds << cd

        errors = [ ]

        unless has_location(cd)
          @counters[:location] << cd
          errors << [ :location, 'missing or empty :location' ]
        end

        unless has_at_a_glance(cd)
          @counters[:at_a_glance] << cd
          errors << [ :at_a_glance, 'missing or empty :at_a_glance' ]
        end

        if errors.count > 0
          self.output.print("---- #{cd[:name]}\n")
          print("  -- I url : #{cd[:uri]}\n")
          errors.each do |e|
            self.output.printf("  -- W %-20s : %s\n", e[0], e[1])
          end
        end
      end
    end

    protected

    # Process initialization.
    # Call the superclass implementation, and sets up counters.

    def process_init()
      super()

      @total_campgrounds = []
      @counters = {
        location: [],
        at_a_glance: []
      }
    end

    # Process termination.
    # Prints statistics and then calls the superclass implementation.

    def process_end()
      self.output.print("processed #{@total_campgrounds.count} records\n")
      @counters.keys.sort.each do |k|
        if @counters[k].count > 0
          self.output.printf("%-20s : %d\n", k, @counters[k].count)
          @counters[k].each do |c|
            self.output.print("  #{c[:name]}\n")
          end
        end
      end

      super()
    end

    private

    def has_location(camp)
      has_location = false

      if !camp[:location].nil?
        loc = camp[:location]
        if loc.is_a?(Hash)
          if !loc[:lat].nil? && !loc[:lon].nil?
            has_location = true
          end
        elsif loc.is_a?(String)
            has_location = (loc.length > 0)
        end
      end

      has_location
    end

    def has_at_a_glance(cd)
      !((cd[:organization] == Cf::Scrubber::USDA::USFS::ORGANIZATION_NAME) \
      	&& (!cd.has_key?(:at_a_glance) || (cd[:at_a_glance].count < 1)))
    end
  end
end
