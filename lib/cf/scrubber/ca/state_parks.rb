require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'

module Cf
  module Scrubber
    # The namespace for scrubbers for CA sites.

    module Ca
      # Scrubber for state park system campgrounds.
      # This scrubber walks the California State Park System web site to extract information about campgrounds.

      class StateParks < Cf::Scrubber::Base
        # The name of the organization dataset (the CA State Park System, which is part of CA)

        ORGANIZATION_NAME = 'ca:state'

        # The (fixed) region name is +California+, since these are CA state parks.

        REGION_NAME = 'California'

        # The URL of the CA State Park System web site

        ROOT_URL = 'https://www.parks.ca.gov'

        # The path in the web site for the index page

        INDEX_PATH = '/ParkIndex'

        # All activity codes and their names.

        ACTIVITY_CODES = {
          '81' => 'En route Campsites',
          '82' => 'Environmental Campsites',
          '83' => 'Family Campsites',
          '84' => 'Group Campsites',
          '85' => 'Hike or Bike Campsites',
          '86' => 'Primitive Camping',
          '87' => 'Historical/Cultural Site',
          '89' => 'Food Service',
          '90' => 'Lodging',
          '91' => 'Picnic Areas',
          '92' => 'RV Sites w/Hookups',
          '93' => 'Camp Store',
          '94' => 'RV Dump Station',
          '95' => 'Env. Learning/Visitor Center',
          '96' => 'Parking',
          '97' => 'Restrooms/Showers',
          '98' => 'Restrooms',
          '99' => 'Outdoor Showers',
          '100' => 'Drinking Water Available',
          '101' => 'Bike Trails',
          '102' => 'Boat-in/Floating Camps',
          '103' => 'Boating',
          '104' => 'Boat Ramps',
          '105' => 'Exhibits and Programs',
          '106' => 'Fishing',
          '107' => 'Guided Tours',
          '108' => 'Hiking Trails',
          '109' => 'Interpretive Exhibits',
          '110' => 'Horseback Riding',
          '111' => 'Off-Highway Vehicles',
          '112' => 'Scuba Diving/Snorkeling',
          '113' => 'Beach Area',
          '114' => 'Swimming',
          '115' => 'Vista Point',
          '116' => 'Nature and Wildlife Viewing',
          '117' => 'Windsurfing/Surfing',
          '118' => 'Wheelchair Accessible',
          '119' => 'Museums',
          '120' => 'Boat Rentals',
          '121' => 'Campers',
          '122' => 'Trailers',
          '123' => 'Alternative Camping',
          '124' => 'RV Access',
          '125' => 'Family Programs',
          '126' => 'Geocaching'
        }

        # Activity codes that indicate camping available.

        CAMPING_ACTIVITY_CODES = [
                                  # From the description this sounds like a place to plop down for the
                                  # night while traveling (by car), so let's keep it out for the time being
                                  # '81': 'En route Campsites',
                                  '82', '83', '84', '85', '86',
                                  # We need to check what this means...
                                  # '102': 'Boat-in/Floating Camps',
                                  '123'
                                 ]

        # Activity codes for listing activities.

        ACTIVITY_ACTIVITY_CODES = [ '101', '103', '106', '108', '110', '111', '112', '113', '114',
                                    '116', '117', '120', '125', '126'
                                  ]

        # Activity codes for listing amenities.

        AMENITY_ACTIVITY_CODES = [ '89', '91', '92', '93', '94', '96', '104', '115', '118', '124' ]

        # Activity codes for information center facilities.

        LEARNING_ACTIVITY_CODES = [ '87', '95', '105', '107', '109', '119' ]

        # Activity codes for restroom facilities.

        RESTROOM_ACTIVITY_CODES = [ '97', '98', '99' ]

        # Activity codes for water facilities.

        WATER_ACTIVITY_CODES = [ '100' ]

        # Activity codes for extracting feature lists.

        FEATURE_ACTIVITY_CODES = [
                                  '81', '82', '83', '84', '85', '86',
                                  '87', '89', '90', '91', '92', '93', '94', '95', '96', '97', '98', '99',
                                  '100', '101',
                                  '102',
                                  '103', '104', '105', '106', '107', '108', '109', '110', '111', '112',
                                  '113', '114', '115', '116', '117', '118', '119', '120', '121', '122',
                                  '123',
                                  '124', '125', '126'
                                 ]

        # @!visibility private
        ACTIVITY_MAP = {
          :campsite_types => CAMPING_ACTIVITY_CODES,
          :activities => ACTIVITY_ACTIVITY_CODES,
          :amenities => AMENITY_ACTIVITY_CODES,
          :learning => LEARNING_ACTIVITY_CODES,
          :restroom => RESTROOM_ACTIVITY_CODES,
          :water => WATER_ACTIVITY_CODES
        }

        # Abbreviations for park types.

        PARK_TYPES = {
          'State Recreation Area' => 'SRA',
          'State Park' => 'SP',
          'State Marine Reserve' => 'SMR',
          'State Historic Park' => 'SHP',
          'State Natural Reserve' => 'SNR',
          'State Beach' => 'SB',
          'Park Property' => 'PP',
          'Point of Interest' => 'PoI',
          'State Marine Park' => 'SMP',
          'State Vehicular Recreation Area' => 'SVRA',
          # This one looks like an outlier...
          'Wayside Campground' => 'WG'
        }

        # Initializer.
        #
        # @param root_url [String] The root URL for the web site to scrub; if not defined, it uses the
        #  value of {Cf::Scrubber::Usda::NationalForestService::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          @use_abbreviation = false
          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
        end

        # Build the list of features from the index page.
        # This method parses the HTML returned by the index page, looks in the "by feature" tab for
        # checkboxes for each feature, and their labels.
        #
        # @return [Array<Hash>] Returns an array of hashes, each containing the following keys:
        #  - *:activity_id* is a string containing the activity identifier (+81+, +82+, etc...).
        #  - *:name* is a string containing the activity name.
        #  The array is sorted by activity identifier, but the symbols are sorted using integer collation
        #  rather than string collation.

        def get_activity_list()
          ha = {}

          res = get(self.root_url + INDEX_PATH, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            tab_el = doc.css("#ParkinfoTab2 .accordion-body > .panel-body > .col-md-12").each do |n|
              n.css("input.activity_facility_search").each do |i_n|
                idn = i_n['value'].to_s
                looper = true
                sib = i_n
                while looper do
                  sib = sib.next_sibling
                  if sib.nil?
                    self.logger.warn { "get_activity_list did not find a <label> sibling for id #{idn}" }
                  else
                    sib_name = sib.name.downcase
                    if sib_name == 'input'
                      self.logger.warn { "get_activity_list did not find a <label> sibling for id #{idn}" }
                      looper = false
                    elsif sib_name == 'label'
                      sib_label = sib.text()
                      if ha.has_key?(idn)
                        self.logger.warn { "get_activity_list multiple <label> siblings for id #{idn}: (#{ha[idn]}) (#{sib_label})" }
                        ha[idn] << ",#{sib_label}"
                      else
                        ha[idn] = sib_label
                      end

                      looper = false
                    end
                  end
                end
              end
            end
          end

          # OK, now we sort and build the array

          skeys = ha.keys.sort do |k1, k2|
            ik1 = k1.to_i
            ik2 = k2.to_i
            ik1 <=> ik2
          end
          skeys.map do |k|
            { activity_id: k, name: ha[k] }
          end
        end

        # Extract the JSON fragment that contains the park list.
        # This method parses the HTML returned by the index page, looks for a <script> element that
        # contains the JS fragment with the park list, and returns that.
        #
        # @return [String, nil] Returns a string containing the park list, in JSON.
        #  Returns +nil+ if it can't find it in the page.

        def get_park_list_json()
          json = nil
          start_f = 'var vParksJson = ['
          stop_f = '}];'

          res = get(self.root_url + INDEX_PATH, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            tab_el = doc.css("body script").each do |n|
              unless n['src']
                # OK so we have a <script> element with no 'src' attribute.
                # Let's look inside and see if we can find the variable name

                txt = n.text()
                idx = txt.index(start_f)
                if idx
                  # OK we seem to have it; we could confirm by checking that this node is followed by a
                  # <script> element with 'src' == '/javascript/parkCoordinates.js', but that should not
                  # be necessary.

                  stxt = txt[idx+start_f.length-1, txt.length]
                  idx = stxt.index(stop_f)
                  if idx
                    json = stxt[0, idx+stop_f.length-1]
                  else
                    self.logger.warn { "get_park_list_json found a starting variable, but no closing sequence" }
                  end

                  break
                end
              end
            end
          end

          json
        end

        # Extract the JSON fragment that contains the park list and convert it to Ruby.
        # This method calls {#get_park_list_json} and parses the result into Ruby.
        #
        # @return [Array<Hash>, nil] Returns a string containing the park list.
        #  Returns +nil+ if it can't find it in the page.

        def get_park_list_raw()
          json = get_park_list_json()
          return (json.nil?) ? nil : JSON.parse(json)
        end

        # Get the list of parks that provide any of the given facilities.
        # This method calls {#get_park_list_raw} to get the park data, then selects the ones
        # that provide at least one of the given facilities.
        #
        # @param actlist [Array<String>] An array containing the activities to use for the filtering:
        #  if any activity in _actlist_ has a nonzero value in the park data, the park is added to the
        #  return set.
        #
        # @return [Array<Hash>, nil] Returns an array containing the park list.
        #  Returns +nil+ if it can't find it in the page.

        def select_park_list(actlist)
          get_park_list_raw().select do |p|
            count = actlist.inject(0) { |c, e| (p[e] != 0) ? c+1 : c }
            count > 0
          end
        end

        # Get the list of parks that provide camping facilities.
        # This method calls {#select_park_list}, passing either the value of _actlist_, or (more typically)
        # the default list of camping activity codes.
        #
        # @param actlist [Array<String>] An array containing the activities to use for the filtering.
        #  uses {CAMPING_ACTIVITY_CODES} if passed as +nil+
        #
        # @return [Array<Hash>, nil] Returns a string containing the park list.
        #  Returns +nil+ if it can't find it in the page.

        def select_campground_list(actlist = nil)
          select_park_list((actlist.is_a?(Array)) ? actlist : CAMPING_ACTIVITY_CODES)
        end

        # Convert raw park data to a standard format.
        #
        # @param pd [Hash] The park data, as one of the elements returned by {#get_park_list_raw}
        #  and related methods.
        # @param with_details [Boolean] If +true+, look in the park's detail page for additional data
        #  (for example, for the blurb).
        #
        # @return [Hash] Returns a hash that contains normalized, converted park data.

        def convert_park_data(pd, with_details = true)
          uri = park_uri(pd)
          blurb = (with_details) ? get_park_blurb(pd) : ''

          ptype = pd['type_desc']
          if @use_abbreviation
            abbr = PARK_TYPES[ptype]
            unless abbr
              self.logger.warn { "convert_park_data: no abbreviation for park type (#{ptype}) for park (#{pd['name']}" }
            end
          else
            abbr = ptype
          end

          add = {}
          ACTIVITY_MAP.each do |ak, al|
            a = list_activities(pd, al)
            add[ak] = a.join(', ') if a.count > 0
          end

          cpd = {
            organization: ORGANIZATION_NAME,
            name: "#{pd['long_name']} #{abbr}",
            uri: park_uri(pd),
            region: REGION_NAME,
            area: pd['Region'],
            location: {
              lat: pd['Latitude'],
              lon: pd['Longitude']
            },
            additional_info: add
          }

          self.logger.info { "extracted park data for (#{cpd[:region]}) (#{cpd[:area]}) (#{cpd[:name]})" }
          cpd
        end

        private

        def park_uri(pd)
          ROOT_URL + '/?page_id=' + pd['page_id'].to_s
        end

        def has_activity?(pd, aid)
          (pd[aid] == 0) ? false : true
        end

        def list_activities(pd, alist)
          l = [ ]
          alist.each do |e|
            l << ACTIVITY_CODES[e] if has_activity?(pd, e)
          end

          l
        end

        def get_park_blurb(pd)
          res = get(park_uri(pd), {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            
          end
        end
      end
    end
  end
end
