require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'

module Cf
  module Scrubber
    # The namespace for scrubbers for NV sites.

    module Nv
      # Scrubber for state park system campgrounds.
      # This scrubber walks the Nevada State Park System web site to extract information about campgrounds.

      class StateParks < Cf::Scrubber::Base
        # The name of the organization dataset (the NV State Park System, which is part of NV)

        ORGANIZATION_NAME = 'nv:state'

        # The (fixed) region name is +Nevada+, since these are NV state parks.

        REGION_NAME = 'Nevada'

        # The URL of the NV State Park System web site

        ROOT_URL = 'http://parks.nv.gov'

        # The path in the web site for the index page

        INDEX_PATH = '/parks'

        # All activity codes and their names.

        ACTIVITY_CODES = {
          'ada-campsites' => 'ADA Campsites',
          'bike-trails' => 'Bike Trails',
          'bird-watching' => 'Bird Watching',
          'boat-launch' => 'Boat Launch',
          'cabins-yurts' => 'Cabins/Yurts',
          'campsites' => 'Campsites',
          'canoeing-water-sports' => 'Canoeing / Water Sports',
          'drinking-water' => 'Drinking Water',
          'equestrian' => 'Equestrian',
          'fishing' => 'Fishing',
          'gift-shop' => 'Gift Shop',
          'hiking' => 'Hiking',
          'historic-site' => 'Historic Site',
          'pets-okay' => 'Pets Okay',
          'picnic-sites' => 'Picnic Sites',
          'restrooms' => 'Restrooms',
          'rv-dump-station' => 'RV Dump Station',
          'rv-hookups' => 'RV Hookups',
          'showers' => 'Showers',
          'visitor-center' => 'Visitor Center'
        }

        # Activity codes that indicate camping available.

        CAMPING_ACTIVITY_CODES = [ 'ada-campsites', 'cabins-yurts', 'campsites', 'rv-hookups' ]

        # Activity codes for listing activities.

        ACTIVITY_ACTIVITY_CODES = [ 'bike-trails', 'bird-watching', 'canoeing-water-sports', 'equestrian',
                                    'fishing', 'hiking' ]

        # Activity codes for listing amenities.

        AMENITY_ACTIVITY_CODES = [ 'boat-launch', 'gift-shop', 'pets-okay', 'picnic-sites',
                                   'rv-dump-station', 'rv-hookups' ]


        # Activity codes for information center facilities.

        LEARNING_ACTIVITY_CODES = [ 'historic-site', 'visitor-center' ]

        # Activity codes for restroom facilities.

        RESTROOM_ACTIVITY_CODES = [ 'restrooms' ]

        # Activity codes for water facilities.

        WATER_ACTIVITY_CODES = [ 'drinking-water', 'showers' ]

        # @!visibility private
        ACTIVITY_MAP = {
          :campsite_types => CAMPING_ACTIVITY_CODES,
          :activities => ACTIVITY_ACTIVITY_CODES,
          :amenities => AMENITY_ACTIVITY_CODES,
          :learning => LEARNING_ACTIVITY_CODES,
          :restroom => RESTROOM_ACTIVITY_CODES,
          :water => WATER_ACTIVITY_CODES
        }

        # Map of activity codes to campground types.

        CAMPGROUND_TYPES_MAP = {
          standard: [ 'ada-campsites', 'campsites' ],
          group: [  ],
          rv: [ 'rv-hookups' ],
          cabin: [ 'cabins-yurts' ]
        }

        # Initializer.
        #
        # @param root_url [String] The root URL for the web site to scrub; if not defined, it uses the
        #  value of {Cf::Scrubber::Nv::StateParks::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
        end

        # Build the list of features from the index page.
        # This method parses the HTML returned by the index page, picks up the ul.nav_categories element,
        # and extracts category id and label from its li elements.
        #
        # @return [Array<Hash>] Returns an array of hashes, each containing the following keys:
        #  - *:activity_id* is a string containing the activity identifier (+ada-campsites+, +bike-trails+,
        #    etc...).
        #  - *:name* is a string containing the activity name.
        #  The array is returned in the order in which the li elements are listed.

        def get_activity_list()
          res = get(self.root_url + INDEX_PATH, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css("ul.nav_categories li label").map do |n|
              i = n.css("input")[0]
              {
                activity_id: i['value'].to_sym,
                name: n.text().strip
              }
            end
          else
            [ ]
          end
        end

        # Get the contents of the detail page for a park.
        #
        # @param [String] url The URL to the park's detail page.
        #
        # @return [String] Returns the contents of the detail page (the response body).

        def get_park_details_page(url)
          res = get(url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            res.body
          else
            ''
          end
        end

        # Build the park list from the contents of the park cards in the index page.
        # Note that this method loads just the local data, and clients will have to call
        # {#extract_details_park_data} in order to have a fully populated set.
        # The reason we split this is to avoid fetching detail pages for parks that may be dropped by
        # a filter later.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing the local park data
        #  (data that can be extracted from the park index page).
        #  Returns +nil+ if it can't find it in the page.
        #  The local park data contain the following standard key/value pairs:
        #  - *:organization* Is +nv:parks+.
        #  - *:name* The campground name.
        #  - *:uri* The URL to the campground's details page.
        #  - *:region* The string +Nevada+.
        #  - *:area* An empty string.
        #  - *:types* An array listing the types of campsites in the campground; often this will be a one
        #    element array, but some campgrounds have multiple site types.
        #  - *:blurb* A short description of the campground.
        #  - *:additional_info* A hash containing information about the campground, as extracted from the
        #    raw data.
        #  It also contains scrubber-specific keys:
        #  - *:features* An array containing the identifiers (from {ACTIVITY_CODES}) of the features
        #    available at this park.

        def get_park_list()
          res = get(self.root_url + INDEX_PATH, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css("div.parkCard-wrapper > div.parkCard-item").map do |nc|
              extract_local_park_data(nc, res)
            end
          else
            [ ]
          end
        end

        # Get the list of parks that provide any of the given facilities.
        # This method calls {#get_park_list} to get the park data, then selects the ones
        # that provide at least one of the given facilities.
        #
        # @param actlist [Array<String>] An array containing the activities to use for the filtering:
        #  if any activity in _actlist_ has a nonzero value in the park data, the park is added to the
        #  return set. If _actlist_ is +nil+, all parks are returned (no filtering is done).
        # @param with_details [Boolean] If +true+, look in the park's detail page for additional data
        #  (for example, for the blurb).
        #  This parameter is currently ignored.
        #
        # @return [Array<Hash>, nil] Returns an array containing the park list. The array elements are
        #  hashes containing the standardized park data; see {#get_park_list} and {#extract_details_park_data}.
        #  Returns +nil+ if it can't find it in the page.

        def any_park_list(actlist = nil, with_details = false)
          if actlist.is_a?(Array)
            return [ ] if actlist.count < 1
            get_park_list().select do |pd|
              if any_activity?(pd[:features], actlist)
                extract_details_park_data(pd)
                true
              else
                false
              end
            end
          else
            get_park_list().map { |pd| extract_details_park_data(pd) }
          end            
        end

        # Get the list of parks that provide all of the given facilities.
        # This method calls {#get_park_list} to get the park data, then selects the ones
        # that provide all of the given facilities.
        #
        # @param actlist [Array<String>] An array containing the activities to use for the filtering:
        #  if all activities in _actlist_ have a nonzero value in the park data, the park is added to the
        #  return set. If _actlist_ is +nil+, all parks are returned (no filtering is done).
        # @param with_details [Boolean] If +true+, look in the park's detail page for additional data
        #  (for example, for the blurb).
        #  This parameter is currently ignored.
        #
        # @return [Array<Hash>, nil] Returns an array containing the park list. The array elements are
        #  hashes containing the standardized park data; see {#get_park_list} and {#extract_details_park_data}.
        #  Returns +nil+ if it can't find it in the page.

        def all_park_list(actlist = nil, with_details = false)
          if actlist.is_a?(Array)
            return [ ] if actlist.count < 1
            get_park_list().select do |pd|
              if all_activity?(pd[:features], actlist)
                extract_details_park_data(pd)
                true
              else
                false
              end
            end
          else
            get_park_list().map { |pd| extract_details_park_data(pd) }
          end            
        end

        # Get the list of parks that provide camping facilities.
        # This method builds an activity list based on the requested campground types, and then calls
        # {#any_park_list} with it.
        #
        # @param types [Array<Symbol>] An array listing the campsite types to include in the list; campgrounds
        #  that offer campsites from the list are added to the return set.
        #  A +nil+ value indicates that all camping types are to be included.
        #  See {Cf::Scrubber::Base::CAMPSITE_TYPES}.
        # @param with_details [Boolean] If +true+, look in the park's detail page for additional data
        #  (for example, for the blurb).
        #
        # @return [Array<Hash>, nil] Returns a string containing the park list. The array elements are
        #  hashes containing the standardized park data, as described in {#get_park_list}.
        #  Returns +nil+ if it can't find it in the page.

        def select_campground_list(types = nil, with_details = false)
          actlist = [ ]
          tt = (types.is_a?(Array)) ? types : Cf::Scrubber::Base::CAMPSITE_TYPES
          tt.each { |t| actlist |= CAMPGROUND_TYPES_MAP[t] if CAMPGROUND_TYPES_MAP.has_key?(t) }

          any_park_list(actlist, with_details)
        end

        # Extract the park data that are stored in the park's details page.
        # The method extracts the following keys from the details page, and loads them in _lpd_:
        #  - *:location* The geographic coordinates of the campground: *:lat*, *:lon*, and *:elevation*.
        #
        # @param [Hash] lpd A hash containing the local park data; see {#get_park_list}.
        #
        # @return [Hash] Returns the park data, which now contain the details properties.

        def extract_details_park_data(lpd)
          body = get_park_details_page(lpd[:uri])
          unless body.nil?
            extract_park_location(body, lpd)
          end

          self.logger.info { "extracted details park data for (#{lpd[:region]}) (#{lpd[:area]}) (#{lpd[:name]})" }
          lpd
        end

        private

        def has_activity?(fl, aid)
          fl.include?(aid)
        end

        def list_activities(fl, alist)
          l = [ ]
          alist.each do |e|
            l << ACTIVITY_CODES[e] if has_activity?(fl, e)
          end

          l
        end

        def make_types(fl)
          types = [ ]
          CAMPGROUND_TYPES_MAP.each { |tk, tv| types << tk if any_activity?(fl, tv) }
          types
        end

        def any_activity?(fl, alist)
          alist.any? { |e| has_activity?(fl, e) }
        end

        def all_activity?(fl, alist)
          alist.all? { |e| has_activity?(fl, e) }
        end

        def extract_park_name(nf)
          pn = nf.css("div.parkCard-description > h3")[0]
          pn.text();
        end

        def extract_park_blurb(nf)
          pn = nf.css("div.parkCard-description > p")[0]
          pn.text();
        end

        def extract_park_uri(nf, res)
          an = nf.css("a.parkCard-item-front-linkWrapper")[0]
          adjust_href(an['href'], res.uri)
        end

        def extract_features(nb, park_uri)
          nb.css("ul.parkCard-item-back-amenities > li > span > .icon").map do |n|
            f = ''
            n['class'].split.each do |c|
              if c =~ /^icon-symbols-(.+)/
                m = Regexp.last_match
                f = m[1].downcase
                unless ACTIVITY_CODES.has_key?(f)
                  self.logger.warn { "unknown activity code (#{f}) for park at (#{park_uri})" }
                end
                break
              end
            end

            f
          end
        end

        def extract_park_location(dpg, cpd)
          if dpg.length > 0
            doc = Nokogiri::HTML(dpg)
            doc.css("div.parkQuickLinks > ul > li > a").each do |an|
              uri = URI(an['href'])
              if uri.host =~ /google.com/
                if uri.path =~ /\/maps\//
                  idx = uri.path.index('@')
                  if idx
                    s = uri.path[idx+1, uri.path.length].split(',')
                    cpd[:location] = {
                      lat: s[0],
                      lon: s[1]
                    }
                  else
                    uri.query.split('&').each do |qe|
                      idx = qe.index('ll=')
                      if idx == 0
                        s = qe[idx+3, qe.length].split(',')
                        cpd[:location] = {
                          lat: s[0],
                          lon: s[1]
                        }
                        break
                      end
                    end
                  end
                end

                break
              end
            end
          end
        end

        def extract_local_park_data(nc, res)
          nf = nc.css("div.parkCard-item-front")[0]
          nb = nc.css("div.parkCard-item-back")[0]

          park_uri = extract_park_uri(nf, res)

          fl = extract_features(nb, park_uri)
          add = {}
          ACTIVITY_MAP.each do |ak, al|
            a = list_activities(fl, al)
            add[ak] = a.join(', ') if a.count > 0
          end

          cpd = {
            organization: ORGANIZATION_NAME,
            name: extract_park_name(nf),
            uri: park_uri,
            types: make_types(fl),
            region: REGION_NAME,
            area: '',
            additional_info: add,
            features: fl
          }

          self.logger.info { "extracted local park data for (#{cpd[:region]}) (#{cpd[:area]}) (#{cpd[:name]})" }
          cpd
        end
      end
    end
  end
end
