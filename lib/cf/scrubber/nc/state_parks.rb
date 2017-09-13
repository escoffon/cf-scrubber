require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'
require 'cf/scrubber/base'

module Cf
  module Scrubber
    # The namespace for scrubbers for NC sites.

    module NC
      # Scrubber for state park system campgrounds.
      # This scrubber walks the North Carolina State Park System web site to extract information about
      # campgrounds.

      class StateParks < Cf::Scrubber::Base
        # The name of the organization dataset (the NC State Park System, which is part of NC)

        ORGANIZATION_NAME = 'nc:state'

        # The (fixed) region name is +North Carolina+, since these are NC state parks.

        REGION_NAME = 'North Carolina'

        # The URL of the NC State Park System web site

        ROOT_URL = 'https://www.ncparks.gov'

        # The name of the camping extractor descriptor.

        EXTRACTOR_CAMPING = :camping

        # The name of the fishing extractor descriptor.

        EXTRACTOR_FISHING = :fishing

        # The name of the boating extractor descriptor.

        EXTRACTOR_BOATING = :boating

        # The name of the swimming extractor descriptor.

        EXTRACTOR_SWIMMING = :swimming

        # The path in the web site for the camping activity page

        ACTIVITY_CAMPING_PATH = '/find-an-activity/camping'

        # Campground types and query (tid) codes.

        CAMPGROUND_TYPES = {
          tid: 'tid',
          values: {
            standard: { code: 22, type: Cf::Scrubber::Base::TYPE_STANDARD },
            rv: { code: 23, type: Cf::Scrubber::Base::TYPE_RV },
            group: { code: 241, type: Cf::Scrubber::Base::TYPE_GROUP },
            cabin: { code: 24, type: Cf::Scrubber::Base::TYPE_CABIN }
            # , equestrian: { code: 25, type: Cf::Scrubber::Base::TYPE_ }
          }
        }

        # The descriptors of the supported extractors.

        EXTRACTORS = {
          camping: {
            # The path in the web site for the camping activity page
            path: '/find-an-activity/camping',

            # Campground facility types and query (tid_2) codes.
            facilities: [
                     {
                       tid: 'tid_2',
                       values: {
                         restrooms: { code: 242, name: 'Restrooms' },
                         showers: { code: 243, name: 'Showers' },
                         electric: { code: 244, name: 'Electric Hookups' },
                         water: { code: 245, name: 'Water Hookups' },
                         sewer: { code: 246, name: 'Sewer Hookups' },
                         dumpstation: { code: 247, name: 'Dump Station' }
                       }
                     },
                     {
                       tid: 'tid_1',
                       values: {
                         restrooms: { code: 21, name: 'Handicap Accessible Campsites' }
                       }
                     }
                    ]
          },

          fishing: {
            # The path in the web site for the fishing activity page
            path: '/find-an-activity/fishing',

            # Fishing activity types and query (tid) codes.
            activities: [
                         {
                           tid: 'tid',
                           values: {
                             freshwater: { code: 33, name: 'Freshwater Fishing' },
                             saltwater: { code: 34, name: 'Saltwater Fishing' },
                             brackish: { code: 228, name: 'Brackish Fishing' },
                             lake: { code: 31, name: 'Lake/Pond Fishing' },
                             stream: { code: 30, name: 'Stream/River Fishing' },
                             ocean: { code: 32, name: 'Ocean/Sound Fishing' }
                           }
                         }
                        ],

            # Fishing facility types and query (tid_2) codes.
            facilities: [
                         {
                           tid: 'tid_2',
                           values: {
                             bait_shop: { code: 36, name: 'Bait Shop' },
                             food_concession: { code: 37, name: 'Food Concession' },
                             tackle_shop: { code: 35, name: 'Tackle Shop' }
                           }
                         }
                        ]
          },

          boating: {
            # The path in the web site for the boating  activity page
            path: '/find-an-activity/boating-and-paddling',

            # Boating activity types and query (tid) codes.
            activities: [
                         {
                           tid: 'tid',
                           values: {
                             coastal: { code: 55, name: 'Coastal Boating/Paddling' },
                             estuarine: { code: 56, name: 'Estuarine Boating/Paddling' },
                             lake: { code: 58, name: 'Lake Boating/Paddling' },
                             river: { code: 57, name: 'River Boating/Paddling' }
                           }
                         }
                        ],

            # Boating facility types and query (tid_2) codes.
            facilities: [
                         {
                           tid: 'tid_1',
                           values: {
                             ada: { code: 179, name: 'Boat Handicap Access' },
                             has_ramp: { code: 39, name: 'Boat Ramp' },
                             ramp_near: { code: 40, name: 'Boat Ramp Nearby' },
                             boat_rental: { code: 50, name: 'Boat Rental Nearby' },
                             canoe_rental: { code: 46, name: 'Canoe/Kayak Rental' },
                             fuel: { code: 41, name: 'Boat Fueling' },
                             marina: { code: 38, name: 'Marina' },
                             access_not_access: { code: 43, name: 'Non-motorized Boat Access' },
                             access_not_motorized: { code: 44, name: 'Non-motorized Boats Only Area' },
                             paddle_trail: { code: 45, name: 'Paddle Trail' },
                             paddleboard_rental: { code: 48, name: 'Paddleboard Rental' },
                             pedalboat_rental: { code: 49, name: 'Pedalboat Rental' },
                             pumpout: { code: 42, name: 'Pumpout (Boats)' },
                             rowboat_rental: { code: 47, name: 'Rowboat Rental' },
                             tube_rental: { code: 51, name: 'Tube Rental Nearby' }
                           }
                         }
                        ]
          },

          swimming: {
            # The path in the web site for the swimming activity page
            path: '/find-an-activity/swimming',

            # Swimming activity types and query (tid) codes.
            activities: [
                         {
                           tid: 'tid',
                           values: {
                             pool: { code: 59, name: 'Pool Swimming' },
                             pond: { code: 60, name: 'Pond/Lake Swimming' },
                             river: { code: 61, name: 'River Swimming' },
                             ocean: { code: 62, name: 'Ocean/Estuary Swimming' },
                             ada: { code: 230, name: 'Handicap Accessible Swimming' }
                           }
                         }
                        ],

            # Swimming facility types and query (tid_2) codes.
            facilities: [
                         {
                           tid: 'tid_1',
                           values: {
                             diving: { code: 149, name: 'Diving Platform' },
                             lifeguard: { code: 148, name: 'Lifeguards (limited hours)' },
                             bathhouse: { code: 229, name: 'Bathhouse' },
                             beach: { code: 317, name: 'Beach' }
                           }
                         }
                        ]
          }
        }

        # All the activities.

        ALL_ACTIVITIES = [ :fishing, :boating, :swimming ]

        # All the facilities.

        ALL_FACILITIES = [ :camping, :fishing, :boating, :swimming ]

        # Initializer.
        #
        # @param root_url [String] The root URL for the web site to scrub; if not defined, it uses the
        #  value of {Cf::Scrubber::NC::StateParks::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
        end

        # Build the list of parks that provide campground facilities.
        #
        # @param types [Array<Symbol>] An array of symbols containing the campground types to search for.
        #  If +nil+, all campground types are looked up.
        # @param activities [Array<Symbol>] An array of symbols containing the activity types to include.
        #  If +nil+, all activity types are looked up.
        # @param facilities [Array<Symbol>] An array of symbols containing the facility types to include.
        #  If +nil+, all facility types are looked up.
        #
        # @return [Array<Hash>] Returns an array of hashes containing standardized information for the parks.

        def get_park_campgrounds(types = nil, activities = nil, facilities = nil)
          # OK first of all let's get the parks that do have campgrounds

          parks = parks_with_campgrounds(types)

          # now load activities and facilities

          activities = ALL_ACTIVITIES unless activities.is_a?(Array)
          activities.each do |a|
            load_park_activities(parks, a)
          end

          facilities = ALL_FACILITIES unless facilities.is_a?(Array)
          facilities.each do |a|
            load_park_facilities(parks, a)
          end

          # To generate the standardized information, unfortunately we have to parse the park page,
          # because that's where the location is displayed (and also the reservation URL).

          parks.values.map do |p|
            pdoc = park_details_page(p)
            loc = extract_location(pdoc)
            res_uri = extract_reservation_url(pdoc)

            add = { }
            add[:activities] = p[:activities].join(', ') if p[:activities]
            add[:amenities] = p[:facilities].join(', ') if p[:facilities]

            cpd = {
              signature: "state/north-carolina/#{p[:name].downcase}/#{p[:name].downcase}",
              organization: ORGANIZATION_NAME,
              name: p[:name],
              uri: self.root_url + p[:url],
              region: REGION_NAME,
              area: '',
              types: p[:types],
              additional_info: add
            }

            cpd[:location] = loc if loc
            cpd[:reservation_uri] = res_uri if res_uri

            cpd
          end
        end

        # Get the list of parks that support camping options.
        # This method queries the +Camping+ page for all the supported campground types, and
        # builds a hash where the keys are URLs to the park's detail page, and the values are
        # hashes that contain the following key/value pairs:
        # - *:name* The park name, as extracted from the query results.
        # - *:url* The URL to the park page, as extracted from the query results; this is the same as
        #   the key for this value.
        # - *:types* An array of symbols containing the list of all campground types available in the park.
        #
        # @param types [Array<Symbol>] An array of symbols containing the campground types to search for.
        #  If +nil+, all campground types are looked up.
        #
        # @return [Hash] Returns a hash as described above.

        def parks_with_campgrounds(types = nil)
          types = CAMPGROUND_TYPES[:values].keys unless types.is_a?(Array)
          rurl = self.root_url + ACTIVITY_CAMPING_PATH
          parks = { }

          types.each do |t|
            park_list("#{rurl}?tid[0]=#{CAMPGROUND_TYPES[:values][t][:code]}").each do |p|
              purl = p[:href]
              if parks.has_key?(purl)
                parks[purl][:types] << t
              else
                parks[purl] = {
                  name: p[:name],
                  url: purl,
                  types: [ t ]
                }
              end
            end
          end

          parks
        end

        # Load facilities information for a list of parks.
        # This method queries an activity page for the facilities available to parks,
        # and adds them to the *:facilities* keys in _parks_.
        #
        # @param parks [Hash] A hash as returned by {#parks_with_campgrounds}.
        # @param name [Symbol] The name of the extractor to use. For example, to load the facilities
        #  associated with the swimming page, pass +:swimming+.
        #
        # @return [Hash] Returns the _parks_ hash.

        def load_park_facilities(parks, name)
          if EXTRACTORS.has_key?(name)
            x = EXTRACTORS[name]
            park_properties(parks, self.root_url + x[:path], :facilities, x[:facilities])
          else
            parks
          end
        end

        # Load activities information for a list of parks.
        # This method queries an activity page for the activities available to parks,
        # and adds them to the *:activities* keys in _parks_.
        #
        # @param parks [Hash] A hash as returned by {#parks_with_campgrounds}.
        # @param name [Symbol] The name of the extractor to use. For example, to load the activities
        #  associated with the swimming page, pass +:swimming+.
        #
        # @return [Hash] Returns the _parks_ hash.

        def load_park_activities(parks, name)
          if EXTRACTORS.has_key?(name)
            x = EXTRACTORS[name]
            park_properties(parks, self.root_url + x[:path], :activities, x[:activities])
          else
            parks
          end
        end

        protected

        # Fetch property information from a list of parks.
        # This method queries the given page for a class of properties available to parks,
        # and adds them to the _name_ key in _parks_.
        #
        # @param parks [Hash] A hash as returned by {#parks_with_campgrounds}.
        # @param rurl [String] The root URL for the query.
        # @param name [Symbol] The name of the value in the park hash that will be updated with the
        #  properties.
        # @param properties [Array<Hash>] An array of hashes that contains the list of properties to look up,
        #  and how to look them up. Each element in the hash contains the following key/value pairs:
        #  - *:tid* is a string containing the name of the query parameters array that contains
        #    the request filter. This is one of +tid+, +tid_1+, or +tid_2+.
        #  - *:values* is a hash containing the values to look up.
        #    The keys are property identifiers, and the values are hashes containing the following
        #    key/value pairs:
        #    - *:code* is the code of the property as passed in the _tid_ parameter.
        #    - *:name* is the property name.
        #
        # @return [Hash] Returns the _parks_ hash.

        def park_properties(parks, rurl, name, properties)
          properties.each do |props|
            url = "#{rurl}?#{props[:tid]}[0]="
            props[:values].each do |k, f|
              park_list("#{url}#{f[:code]}").each do |p|
                purl = p[:href]
                if parks.has_key?(purl)
                  parks[purl][name] = [ ] unless parks[purl][name]
                  parks[purl][name] << f[:name]
                end
              end
            end
          end

          parks
        end

        private

        def park_details_page(pd)
          url = self.root_url + pd[:url]
          self.logger.info { "park_details_page: #{url}" }
          res = get(url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            Nokogiri::HTML(res.body)
          else
            nil
          end
        end

        def extract_location(doc)
          loc = nil
          d = doc.css('div.getlocations_fields_latlon_wrapper_themed').first
          if d
            lat_div = d.css('div.getlocations_fields_lat_wrapper_themed').first
            lon_div = d.css('div.getlocations_fields_lon_wrapper_themed').first
            if lat_div && lon_div
              lat = if lat_div.text() =~ /-?[0-9]{1,3}\.[0-9]+/
                      Regexp.last_match[0]
                    else
                      nil
                    end

              lon = if lon_div.text() =~ /-?[0-9]{1,3}\.[0-9]+/
                      Regexp.last_match[0]
                    else
                      nil
                    end

              loc = { lat: lat, lon: lon } if lat && lon
            end
          end

          loc
        end

        def extract_reservation_url(doc)
          a = doc.css('div.field-name-field-make-a-reservation-link div.field-item a').first
          (a) ? a[:href] : nil
        end

        def park_list(url)
          self.logger.info { "park_list: #{url}" }
          parks = [ ]
          page_next = url
          while page_next
            p = fetch_parks_page(page_next)
            parks.concat(p[:parks])
            page_next = (p[:page_next]) ? self.root_url + p[:page_next] : nil
          end

          parks
        end

        def fetch_parks_page(url)
          self.logger.debug { "fetch_parks_page: #{url}" }
          res = get(url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            parks = doc.css("div.view-content div.views-row article").map do |nart|
              na = nart.css("h2 a").first
              self.logger.debug { "  ++++++++ na: #{na['href']} - #{na.text()}" }
              { href: na['href'], name: na.text() }
            end
            np = doc.css("div.text-center ul.pagination li.next a")
            page_next = (np.count > 0) ? np[0]['href'] : nil
            self.logger.debug { "  ++++++++ page_next: #{page_next}" }
          else
            doc = nil
            parks = [ ]
            page_next = nil
          end

          { doc: doc, parks: parks, page_next: page_next }
        end
      end
    end
  end
end
