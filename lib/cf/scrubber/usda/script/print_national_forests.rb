require 'cf/scrubber/usda/script'
require 'cf/scrubber/ridb/script'
require 'cf/scrubber/usda/usfs_helper'
require 'cf/scrubber/usda/usfs.rb'

module Cf::Scrubber::USDA::Script
  # This class implements the +usfs_national_forests_db+ utility.
  # It iterates the rec areas listed in RIDB for the USFS, and generates a file containing descriptors
  # for these forests, grouped by state.
  #
  # The generated file contains a Ruby code fragment that lists the USFS national forests and grasslands
  # as known to the USFS web site.
  # This fragment defines a hash called +USFS_NATIONAL_FORESTS+, whose keys are national forest or grassland
  # names, and values are hashes containing the forest info.

  class PrintNationalForests < Cf::Scrubber::RIDB::Script::ListNationalForests
    # Parser for the USFS national forests script.

    class Parser < Cf::Scrubber::RIDB::Script::ListNationalForests::Parser
      # Initializer.

      def initialize()
        super()
      end
    end

    # @!attribute [r] total_forests
    # @return [Integer] The number of forests processed thus far.

    attr_reader :total_forests

    protected

    # Initialize processing.
    # Cals the +super+ implementation and then sets the forest counter to 0 and  emits the file header.

    def process_init
      super()

      @usfs = Cf::Scrubber::USDA::USFS.new(nil, {
                                             :output => self.parser.options[:output],
                                             :logger => self.parser.options[:logger],
                                             :logger_level => self.parser.options[:logger_level]
                                           })
      @ridb_data = { }
      @usfs_data = { }
      @states = if self.parser.options[:states]
                  (self.parser.options[:states].split(',').map { |s| s.strip.upcase.to_sym }).sort
                else
                  STATE_CODES.keys.sort
#                  (usfs.states.keys.map { |s| usfs.state_code(s) }).sort
                end
    end

    # Processing ended.
    # Run some sanity checks the generated data and emits the file, and then calls the +super+ implementation.

    def process_end()
      check_and_emit()
      super()
    end

    # Process national forests for a state.
    # Builds national forest descriptors from the RIDB data, and emits them to the output file.
    #
    # @param api [Cf::Scrubber::RIDB::API] The active instance of {Cf::Scrubber::RIDB::API}.
    # @param state [String] The two-letter state code.
    # @param forests [Array<Hash>] An array of hashes containing the national forests data structure
    #  for the state; see the class documentation for {Cf::Scrubber::RIDB::Script::ListNationalForests}
    #  for details.

    def process_national_forests(api, state, forests)
      @ridb_data[state.upcase.to_sym] = { rec_areas: forests }
      Cf::Scrubber::USDA::USFSHelper.ridb_forest_descriptors_for_state(state, @ridb_data).each do |fd|
        @usfs_data[fd[:name]] = fd
      end
    end

    private

    def find_forest(state, forest)
      fd = @usfs_data[forest]
      if fd.nil?
        # The forest is not in the descriptors. This is due to a few possible causes:
        # 1. There is a rec area by that name, and it has facilities that also look like NG/NG.
        #    In that case, the algorithm returns the facilities and ignores the rec area.
        #    For example, Angeles NF in CA.
        #    In this case, we see if there is a top level entry by this name.
        # 2. There is an entry, but it is not named quite the same. For example, the RIDB uses
        #    'Bankhead NF' in NC, but the USFS site returns 'William F. Bankhead NF'
        # 3. There is neither rec area, nor facility. This is typically because the NF is under a cluster
        #    in the RIDB, and the RIDB does not define facilities for it. For example, CO has a cluster
        #    called PSICC which includes 'San Isabel NF' (the SI in PSICC), and there is no 'San Isabel NF'
        #    facility.

        @ridb_data[state][:rec_areas].each do |ra|
          # ARGH! some NF names are all uppercase (Shasta-Trinity NF in CA), so let's compare
          # normalized strings. And let's also ignore whitespaces.

          if ra[:name] =~ Regexp.new(forest.gsub(/\s+/, '\\s+'), Regexp::IGNORECASE)
            self.logger.warn { "no forest descriptor for '#{forest}', but we found a rec area" }
            fd = ra
            break
          end
        end
      end

      fd
    end

    def check_and_emit()
      o = self.output

      states = (self.parser.options[:states]) ? " -s #{self.parser.options[:states]}" : ''
      o.print("# generated by: usfs_national_forests_db #{states}\n")
      o.print("# generated on: #{Time.new}\n")
      o.print("USFS_NATIONAL_FORESTS = {")

      @total_forests = 0
      @total_states = 0
      comma = ''
      forest_states = { }

      @states.each do |state|
        @total_states += 1
        if @total_states == 1
          o.print("#{comma}\n  # state: #{state}")
        else
          o.print("#{comma}\n\n  # state: #{state}")
        end
        comma = ''

        @usfs.forest_ids_for_state(state).keys.sort.each do |forest|
          @total_forests += 1
          o.print("#{comma}\n")
          comma = ''

          name = forest.gsub("'") { "\\'" }
          fd = find_forest(state, forest)

          if forest_states[forest]
            forest_states[forest] << state
          else
            forest_states[forest] = [ state ]
          end

          if fd
            o.print("  '#{name}' => {\n")
            o.print("    name: '#{name}'")
            o.print(",\n    ignore: true") if fd[:ignore]
            o.print(",\n    shared: true") if fd[:shared]
            o.printf(",\n    ridb_id: %d", fd[:ridb_id]) if fd[:ridb_id] && fd[:ridb_id].is_a?(Numeric)
            o.printf(",\n    usfs_id: %d", fd[:usfs_id]) if fd[:usfs_id] && fd[:usfs_id].is_a?(Numeric)
            o.printf(",\n    label: '%s'", fd[:label]) if fd[:label] && fd[:label].is_a?(String)
            o.printf(",\n    container_ridb_id: %d", fd[:container_ridb_id]) if fd[:container_ridb_id] && fd[:container_ridb_id].is_a?(Numeric)
            o.printf(",\n    container_usfs_id: %d", fd[:container_usfs_id]) if fd[:container_usfs_id] && fd[:container_usfs_id].is_a?(Numeric)
            o.printf(",\n    container_label: '%s'", fd[:container_label]) if fd[:container_label] && fd[:container_label].is_a?(String)
            o.print(",\n    url: '#{fd[:url]}'") if fd.has_key?(:url)
            o.print("\n  }")

            comma = ","
          else
            self.logger.error { "no NF/NG descriptor for '#{forest}'" }

            o.print("  #  '#{name}': {\n")
            o.print("  #    name: '#{name}'")
            o.print(",\n  #    ignore: true")
            o.print("\n  #  }")
          end
        end
      end

      o.print("\n}\n")

      forest_states.keys.sort.each do |forest|
        if forest_states[forest].count > 1
          o.print("# multiple states for '#{forest}' (#{forest_states[forest].join(', ')})\n")
          self.logger.warn { "# multiple states for '#{forest}' (#{forest_states[forest].join(', ')})" }
        end
      end

      o.print("# total: #{self.total_states} states\n")
      o.print("# total: #{self.total_forests} forests\n")
    end
  end
end
