require 'cf/scrubber/ridb/script'
require 'cf/scrubber/usda/usfs_helper'

module Cf::Scrubber::RIDB::Script
  # This class implements a loop to list rec areas from the RIDB that appear to be national forests.
  # It iterates the rec areas listed in RIDB for the USFS; many of these rec areas are national forests
  # (or grasslands). However, some states define "umbrella" rec areas that encompass multiple national
  # forests, and place the individual national forests in the list of facilities for the rec area.
  # The tool uses the simple and somewhat naive heuristic that a facility whose name contains
  # +National For+ (or +NF+) or +National Gras+ (or +NG+) is a national forest or grassland.
  # It looks in the rec area's facilities for records whose name matches the two values listed above,
  # and adds them to the list of facilities associated with the rec area.
  #
  # Note that the pattern we use are likely to return facilities that are not national forests, so that
  # the generated data structure may contain more than just national forests or grasslands.
  # Users of the data structure will have to provide additional filtering as needed.
  # 
  # The generated data structure for each state is an array of rec area info hashes.
  # Each rec area hash contains the following key/value pairs:
  # - *:name* The rec area name (from the RIDB field +RecAreaName+).
  # - *:ignore* Duplicate rec area entries are marked ignored by the presence of this key.
  # - *:ridb_id* The RIDB ID of the rec area (from the IRDB field +RecAreaID').
  # - *:usfs_id* The USFS ID of the rec area (from the RIDB field +OrgRecAreaID').
  # - *:url* If the rec area contains a *LINK* property that in turns contains a +Official Web Site+ link,
  #   this is the URL of the rec area's home page.
  # - *:facilities* An array containing the list of facilities that match the name heuristic described above.
  #   The elements are hashes that contain these key/value pairs:
  #   - *:name* The facility name (from the RIDB field +FacilityName+).
  #   - *:ignore* Duplicate facility entries are marked ignored by the presence of this key.
  #   - *:ridb_id* The RIDB ID of the facility (from the IRDB field +FacilityID').
  #   - *:usfs_id* The USFS ID of the facility (from the RIDB field +OrgFacilityID').
  #   - *:url* If facility area contains a *LINK* property that in turns contains a +Official Web Site+ link,
  #     this is the URL of the facility's home page.
  #
  # ==== Note
  # This script doesn't really do anything other than loading the data structure: it is a framework for
  # specialized processing of those state hashes. This specialized processing is implemented by overriding
  # the {#process_init}, {#process_end}, and {#process_national_forests} methods as needed.

  class ListNationalForests < RecAreas
    # @!visibility private
    # The regexp for national forest names.

    NF_RE = /\bNational\s+Fo/i

    # @!visibility private
    # The regexp for national grassland names.

    NG_RE = /\bNational\s+Gr/i

    # Parser for the RIDB national forests script.

    class Parser < Cf::Scrubber::RIDB::Script::RecAreas::Parser
      # Initializer.
      # Sets the *:full* option's default value to +true+.

      def initialize()
        rv = super()

        self.options.merge!({ full: true })

        rv
      end
    end

    # @!attribute [r] total_states
    # @return [Integer] The number of states processed thus far.

    attr_reader :total_states

    # Lists national forests.
    # This is the method that should be called to run the script; it starts the process, and for each
    # state processed it calls {#process_national_forests}.
    #

    def list_national_forests()
      self.exec do |api, state, areas|
        _list_national_forests(api, state, areas)
      end
    end

    protected

    # Initialize processing.
    # Cals the +super+ implementation and then initializes the {#states} counter to 0.

    def process_init
      super()

      @total_states = 0
    end

    # Processing ended.
    # Currently simply calls the +super+ implementation.

    def process_end()
      super()
    end

    # Process national forests for a state.
    # This implementation is empty; subclasses are expected to override it to provide their own
    # processing functionality.
    #
    # @param api [Cf::Scrubber::RIDB::API] The active instance of {Cf::Scrubber::RIDB::API}.
    # @param state [String] The two-letter state code.
    # @param forests [Array<Hash>] An array of hashes containing the national forests data structure
    #  for the state; see the class documentation for details.

    def process_national_forests(api, state, forests)
    end

    private

    def _list_national_forests(api, state, areas, &blk)
      urls = { }

      @total_states += 1

      forests = areas.map do |a|
        ah = {
          name: a['RecAreaName'],
          ridb_id: a['RecAreaID'],
          usfs_id: a['OrgRecAreaID']
        }
        self.logger.debug { "processing (#{ah[:name]}) RIDB: (#{ah[:ridb_id]}) USFS: (#{ah[:usfs_id]})" }

        if a.has_key?('LINK')
          a['LINK'].each do |l|
            if l['LinkType'] == 'Official Web Site'
              ah[:url] = l['URL']
              label = Cf::Scrubber::USDA::USFSHelper.extract_label(ah[:url])
              ah[:label] = label unless label.nil?
            end
          end
        end

        if !ah.has_key?(:url)
          self.logger.warn { "no URL in rec area #{ah[:name]} for state #{state}" }
          ah[:ignore] = true
        elsif urls[ah[:url]]
          self.logger.warn { "duplicate URL {#{ah[:url]}) in rec area (#{ah[:name]}) for state (#{state}) defined in (#{urls[ah[:url]][:name]})" }
          ah[:ignore] = true
        end

        urls[ah[:url]] = ah if ah[:url]

        fac = [ ]
        if a.has_key?('FACILITY')
          a['FACILITY'].each do |f|
            if (f['FacilityName'] =~ NF_RE) || (f['FacilityName'] =~ NG_RE)
              fh = {
                name: f['FacilityName'],
                ridb_id: f['FacilityID']
              }

              r = api.get_facility(f['FacilityID'], true)
              fh[:usfs_id] = r['OrgFacilityID']

              if r.has_key?('LINK')
                r['LINK'].each do |l|
                  if l['LinkType'] == 'Official Web Site'
                    fh[:url] = l['URL']
                  end
                end
              end

              if !fh.has_key?(:url)
                self.logger.warn { "no URL in facility #{fh[:name]} for state #{state}" }
                fh[:ignore] = true
              elsif urls[fh[:url]]
                self.logger.warn { "duplicate URL #{fh[:url]} in facility #{fh[:name]} for state #{state}" }
                fh[:ignore] = true
              end

              urls[fh[:url]] = fh if fh[:url]
              fac << fh
            end
          end
        end

        ah[:facilities] = fac
        ah
      end

      process_national_forests(api, state, forests)
    end
  end
end
