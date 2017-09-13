require 'cf/scrubber/ridb/script'

module Cf::Scrubber::RIDB::Script
  # This class implements the +ridb_forest_query+ utility.
  # It runs a query against the RIDB, converts the records into forest descriptors, and emits them.
  #
  # The generated file contains a Ruby code fragment that lists the forest descriptors.
  # See the documentation for {Cf::Scrubber::RIDB::Script::ListNationalForests} for details on the
  # contents and structure of the forest descriptors.
  #
  # ==== Note
  # Note that only facilities that contain any of the words in the query string are displayed.
  # The reason is that the query parameter in the RIDB looks in the description as well as name and
  # keywords, and that is likely to pull in  facilities that are not relevant.
  # *This is not implemented yet!*

  class ForestQuery < Query
    # @!visibility private

    USFS_WEB_SITE_RE = /www\.fs\.(usda|fed)\.(us|gov)\/(.*)/i

    # Parser for the RIDB national forests script.

    class Parser < Cf::Scrubber::RIDB::Script::Query::Parser
      # Initializer.

      def initialize()
        super()

        self.options.merge!({ full: true })
      end
    end

    # Initializer.
    #
    # @param parser [Cf::Scrubber::Script::Parser] The parser to use.

    def initialize(parser)
      super(parser)
    end

    protected

    # Initialize processing.
    # Cals the +super+ implementation and then emits the file header.

    def process_init
      super()

      @total_records = 0

      o = self.output

      o.print("[\n")
    end

    # Processing ended.
    # Emits the file footer, and then calls the +super+ implementation.

    def process_end()
      o = self.output

      o.print("\n]\n")

      super()
    end

    # Process forest records.
    #
    # @param api [Cf::Scrubber::RIDB::API] The active instance of {Cf::Scrubber::RIDB::API}.
    # @param type [String] The record type.
    # @param rec [Hash] The record.

    def process_record(api, type, rec)
      @total_records += 1

      o = self.output
      o.print(",\n") if @total_records > 1

      case type
      when 'R'
        r = {
          name: rec['RecAreaName'],
          ridb_id: rec['RecAreaID'],
          usfs_id: rec['OrgRecAreaID']
        }

        if rec.has_key?('LINK')
          rec['LINK'].each do |l|
            if l['LinkType'] == 'Official Web Site'
              r[:url] = l['URL']
            end
          end
        end

        if r[:url] && (r[:url] =~ USFS_WEB_SITE_RE)
          r[:label] = Regexp.last_match[3]
        end

        o.printf("  # rec area: '%s'\n", r[:name].gsub("'") { "\\'" })
        o.printf("  {\n    name: '%s',\n", r[:name].gsub("'") { "\\'" })
        o.printf("    ridb_id: %d,\n    usfs_id: %d", r[:ridb_id], r[:usfs_id])
        o.print(",\n    label: '#{r[:label]}'") if r.has_key?(:label)
        o.print(",\n    url: '#{r[:url]}'") if r.has_key?(:url)

        o.print("\n  }")
      when 'F'
        fh = {
          name: rec['FacilityName'],
          ridb_id: rec['FacilityID']
        }

        r = api.get_facility(rec['FacilityID'], true)
        fh[:usfs_id] = r['OrgFacilityID']

        if r.has_key?('LINK')
          r['LINK'].each do |l|
            if l['LinkType'] == 'Official Web Site'
              fh[:url] = l['URL']
            end
          end
        end

        if !fh.has_key?(:url)
#          self.logger.warn { "no URL in facility #{fh[:name]}" }
          fh[:ignore] = true
        end

        o.printf("  # facility: '%s'\n", fh[:name].gsub("'") { "\\'" })
        o.printf("  {\n    name: '%s',\n", fh[:name].gsub("'") { "\\'" })
        o.printf("    ridb_id: %s,\n    usfs_id: %s", fh[:ridb_id], fh[:usfs_id])
        o.print(",\n    url: '#{fh[:url]}'") if fh.has_key?(:url)

        o.print("\n  }")
      end
    end
  end
end
